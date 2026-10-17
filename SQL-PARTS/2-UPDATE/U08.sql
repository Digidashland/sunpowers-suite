-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 8 of 9
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U09). Safe to re-run.
-- ============================================================================

-- ---------- rules enforced on every write (cannot be bypassed from the browser) ---------------------
create or replace function public.crm_rules_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare pt public.crm_records; ex public.crm_records; miss text[] := '{}'; nm text; d jsonb; bypass boolean := coalesce(current_setting('sp.wf', true), '') = '1'; ct text;
begin
  if new.deleted_at is not null then return new; end if;
  d := coalesce(new.data, '{}'::jsonb);

  if new.kind = 'lead' then
    nm := trim(coalesce(d ->> 'name', new.title, ''));
    if TG_OP = 'INSERT' or new.mobile is distinct from old.mobile then
      if coalesce(new.mobile, '') !~ '^[6-9][0-9]{9}$' then raise exception 'Lead ke liye sahi 10 ank ka mobile zaroori hai'; end if;
    end if;
    -- forms / signups / ads (inbound): name AND mobile are mandatory.  Manual add / Excel / contacts import: mobile alone is enough.
    if coalesce(d ->> 'intake', '') = 'inbound' and (nm = '' or nm ~* '^lead [0-9]') then raise exception 'Form / signup / ad se aayi lead me naam aur mobile dono zaroori hain'; end if;
    return new;
  end if;

  if new.kind = 'quote' then
    ct := coalesce(d ->> 'ctype', '');
    if ct <> '' and not (ct = any (public.crm_ctypes())) then raise exception 'Customer type galat hai'; end if;
    -- one customer = one open quotation (edit it); a new plant gets a new number only after the old one is confirmed
    if (TG_OP = 'INSERT' or new.party_id is distinct from old.party_id) and new.party_id is not null then
      select * into ex from public.crm_records where kind = 'quote' and deleted_at is null and party_id = new.party_id and id <> coalesce(new.id, 0) and status in ('draft', 'sent', 'rejected', 'expired') order by id desc limit 1;
      if ex.id is not null then raise exception 'Is customer ki quotation % pehle se hai — usi ko edit karein. Naya plant tabhi, jab ye confirm ho jaye.', coalesce(ex.ref, '#' || ex.id); end if;
    end if;
    -- mandatory customer details before the quotation is sent / confirmed
    if new.status in ('sent', 'accepted') and (TG_OP = 'INSERT' or old.status is distinct from new.status or coalesce(old.data ->> 'ctype', '') <> ct or coalesce(old.data ->> 'kw', '') <> coalesce(d ->> 'kw', '')) then
      select * into pt from public.crm_records where id = new.party_id and kind = 'party';
      if coalesce(trim(pt.title), '') = '' then miss := miss || 'Naam'::text; end if;
      if coalesce(pt.mobile, '') !~ '^[6-9][0-9]{9}$' then miss := miss || 'Mobile'::text; end if;
      if coalesce(trim(pt.data ->> 'address'), '') = '' then miss := miss || 'Pata'::text; end if;
      if coalesce(trim(pt.data ->> 'city'), '') = '' then miss := miss || 'Shahar'::text; end if;
      if ct = '' then miss := miss || 'Customer type (Residential / Commercial / Industrial / VFD / Items only)'::text; end if;
      if ct in ('Residential', 'Commercial', 'Industrial', 'VFD') and public.crm_num(d -> 'kw') <= 0 then miss := miss || 'Plant capacity (kW)'::text; end if;
      if array_length(miss, 1) > 0 then raise exception 'Quotation bhejne se pehle ye bharna zaroori hai: %', array_to_string(miss, ', '); end if;
    end if;
    -- workflow: only the server writes it
    if TG_OP = 'UPDATE' and not bypass then
      d := d - 'wf' - 'closed' - 'bill_state' - 'old_project';
      d := d || jsonb_build_object('wf', coalesce(old.data -> 'wf', '{}'::jsonb));
      if old.data ? 'closed' then d := d || jsonb_build_object('closed', old.data -> 'closed'); end if;
      if old.data ? 'bill_state' then d := d || jsonb_build_object('bill_state', old.data -> 'bill_state'); end if;
      if old.data ? 'old_project' then d := d || jsonb_build_object('old_project', old.data -> 'old_project'); end if;
    elsif TG_OP = 'INSERT' and not bypass then
      d := d - 'wf' - 'closed' - 'bill_state' - 'old_project';
    end if;
    if TG_OP = 'INSERT' then
      select * into pt from public.crm_records where id = new.party_id and kind = 'party';
      d := public.crm_wf_mark(d, 1, 'Customer', to_char(coalesce(pt.created_at, now()) at time zone 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS"+05:30"'));
      d := public.crm_wf_mark(d, 2, 'Customer', to_char(coalesce(pt.created_at, now()) at time zone 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS"+05:30"'));
    end if;
    if new.status in ('sent', 'accepted', 'converted') then d := public.crm_wf_mark(d, 3, 'Quotation'); end if;
    if new.status in ('accepted', 'converted') then d := public.crm_wf_mark(d, 6, 'Confirmation'); end if;
    new.data := d;
  end if;
  return new;
end $$;

drop trigger if exists crm_rules on public.crm_records;
create trigger crm_rules before insert or update on public.crm_records for each row execute function public.crm_rules_trg();

-- ---------- bill balance → quote flags (pending ribbon / list leaves at zero / Finish Work) ---------------
create or replace function public.crm_inv_recalc(p_inv bigint) returns void language plpgsql security definer set search_path = public as $$
declare paid numeric; tot numeric; qid bigint; bal numeric;
begin
  select coalesce(sum(amount), 0) into paid from public.crm_records where kind = 'payment' and deleted_at is null and (data ->> 'invoice_id') = p_inv::text;
  select amount into tot from public.crm_records where id = p_inv;
  bal := greatest(tot - paid, 0);
  update public.crm_records set data = data || jsonb_build_object('paid', paid, 'balance', bal),
    status = case when tot - paid <= 0.009 then 'paid' when paid > 0 then 'partial' else 'due' end, updated_at = now()
  where id = p_inv and kind = 'invoice';
  select nullif(data ->> 'quote_id', '')::bigint into qid from public.crm_records where id = p_inv and kind = 'invoice';
  if qid is not null then
    perform set_config('sp.wf', '1', true);
    update public.crm_records q set data = case when bal <= 0.009 then
        public.crm_wf_mark(q.data || jsonb_build_object('closed', true, 'bill_state', 'closed'), 12, 'Bill balance zero')
      else (q.data || jsonb_build_object('closed', false, 'bill_state', 'pending')) #- '{wf,12}' end, updated_at = now()
    where q.id = qid and q.kind = 'quote';
    perform set_config('sp.wf', '', true);
  end if;
end $$;

-- one-time: flag the quotes that were already billed
do $$ begin
  perform set_config('sp.wf', '1', true);
  update public.crm_records q set data = q.data || jsonb_build_object('bill_state', case when i.status = 'paid' then 'closed' else 'pending' end, 'closed', i.status = 'paid')
  from public.crm_records i where q.kind = 'quote' and q.deleted_at is null and i.kind = 'invoice' and i.id = nullif(q.data ->> 'invoice_id', '')::bigint and not (q.data ? 'bill_state');
  perform set_config('sp.wf', '', true);
end $$;

-- ---------- who may see / change which step ------------------------------------------------------------------
-- crm_settings.data.wf = { "perm": { "4": { "view": [uid..], "edit": [uid..] } }, "allow_old": false }
-- default: Admin and Manager see and change every step; others see only date+time until Admin authorises them.
create or replace function public.crm_wf_can(s public.crm_ses, n int, mode text) returns boolean language plpgsql stable security definer set search_path = public as $$
declare cfg jsonb; arr jsonb;
begin
  if public.crm_is_admin(s) then return true; end if;
  if (s).role = 'manager' then return true; end if;
  select data -> 'wf' -> 'perm' -> n::text into cfg from public.crm_settings where id = 1;
  arr := coalesce(cfg -> mode, '[]'::jsonb);
  if mode = 'view' then arr := arr || coalesce(cfg -> 'edit', '[]'::jsonb); end if;
  return arr @> to_jsonb((s).uid) or arr @> to_jsonb((s).uid::text);
end $$;

create or replace function public.crm_wf_steps(s public.crm_ses, q public.crm_records) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare names text[] := public.crm_wf_names(); out jsonb := '[]'::jsonb; i int; w jsonb := coalesce(q.data -> 'wf', '{}'::jsonb); st jsonb; v boolean; e boolean; resid boolean := (q.data ->> 'ctype') = 'Residential';
begin
  for i in 1..13 loop
    continue when i = 13 and not resid;
    st := w -> i::text; v := public.crm_wf_can(s, i, 'view'); e := public.crm_wf_can(s, i, 'edit');
    out := out || jsonb_build_array(jsonb_build_object('n', i, 'name', names[i], 'done', st is not null, 'at', st ->> 'at', 'auto', coalesce((st ->> 'auto')::boolean, false),
      'locked', not v, 'can_edit', e and i not in (1, 2, 3, 6, 12) and (i <> 13 or public.crm_is_admin(s) or (s).role = 'manager'),
      'by', case when v then st ->> 'by' end, 'note', case when v then st ->> 'note' end));
  end loop;
  return out;
end $$;

-- the workflow of one quotation (or the latest quotation of a customer)
create or replace function public.crm_wf_get(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; pt public.crm_records; qid bigint := nullif(p ->> 'id', '')::bigint; pid bigint := nullif(p ->> 'party_id', '')::bigint; plants jsonb;
begin
  if qid is null and pid is not null then
    select * into pt from public.crm_records where id = pid and kind = 'party';
    if pt.id is null or not public.crm_vis(s, pt) then raise exception 'Customer nahi mila'; end if;
    select * into q from public.crm_records where kind = 'quote' and deleted_at is null and party_id = pid order by id desc limit 1;
    select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'ref', x.ref, 'title', coalesce(x.data ->> 'qtitle', x.title), 'ctype', x.data ->> 'ctype', 'status', x.status) order by x.id desc), '[]'::jsonb) into plants
      from public.crm_records x where x.kind = 'quote' and x.deleted_at is null and x.party_id = pid;
    if q.id is null then
      return jsonb_build_object('party_id', pid, 'quote_id', null, 'plants', '[]'::jsonb, 'project', false, 'steps',
        jsonb_build_array(jsonb_build_object('n', 1, 'name', 'Customer Connect', 'done', true, 'at', to_char(pt.created_at at time zone 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS"+05:30"'), 'locked', false),
                          jsonb_build_object('n', 2, 'name', 'Starting Conversation', 'done', true, 'at', to_char(pt.created_at at time zone 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS"+05:30"'), 'locked', false)));
    end if;
  else
    select * into q from public.crm_records where id = qid and kind = 'quote' and deleted_at is null;
    if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
    plants := '[]'::jsonb;
  end if;
  if not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  return jsonb_build_object('party_id', q.party_id, 'quote_id', q.id, 'ref', q.ref, 'title', coalesce(q.data ->> 'qtitle', q.title), 'ctype', q.data ->> 'ctype', 'status', q.status, 'plants', plants,
    'project', (q.data -> 'wf') ? '7', 'bill_state', q.data ->> 'bill_state', 'steps', public.crm_wf_steps(s, q));
end $$;

-- confirm / undo one manual step
create or replace function public.crm_wf_set(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; n int := (p ->> 'step')::int; done boolean := coalesce((p ->> 'done')::boolean, true); note text := left(trim(coalesce(p ->> 'note', '')), 500); d jsonb; w jsonb;
begin
  select * into q from public.crm_records where id = (p ->> 'id')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if n is null or n < 1 or n > 13 then raise exception 'Step galat hai'; end if;
  if n in (1, 2, 3, 6, 12) then raise exception 'Ye step apne aap hota hai (quotation / bill se)'; end if;
  if n = 13 and (q.data ->> 'ctype') <> 'Residential' then raise exception 'Subsidy sirf Residential solar ke liye hai'; end if;
  if n = 13 and not (public.crm_is_admin(s) or (s).role = 'manager') then raise exception 'Subsidy sirf Admin ya Manager green kar sakte hain'; end if;
  if not public.crm_wf_can(s, n, 'edit') then raise exception 'Is step ko badalne ki permission nahi hai — Admin se allow karwayein'; end if;
  w := coalesce(q.data -> 'wf', '{}'::jsonb);
  if done then
    if (q.data ->> 'ctype') = 'Items only' or coalesce(q.data ->> 'ctype', '') = '' then raise exception 'Items-only customer ka process Confirmation par khatam hota hai'; end if;
    if n >= 7 and not (w ? '6') then raise exception 'Pehle quotation Confirm hona chahiye'; end if;
    if n > 7 and not (w ? '7') then raise exception 'Pehle Apply Process confirm karein — tabhi customer Projects me aata hai'; end if;
    w := w || jsonb_build_object(n::text, jsonb_build_object('at', public.crm_iso_now(), 'by', (s).name, 'by_id', (s).uid, 'note', note));
  else
    if not public.crm_is_admin(s) then raise exception 'Step wapas sirf Admin kar sakta hai'; end if;
    w := w - n::text;
  end if;
  perform set_config('sp.wf', '1', true);
  update public.crm_records set data = data || jsonb_build_object('wf', w), updated_at = now() where id = q.id;
  perform set_config('sp.wf', '', true);
  perform public.crm_log(s, 'workflow', 'quote', q.id, coalesce(q.ref, '') || ' — ' || (public.crm_wf_names())[n] || case when done then ' ✔' else ' ↩' end);
  select * into q from public.crm_records where id = q.id;
  return public.crm_wf_get(jsonb_build_object('token', p ->> 'token', 'id', q.id));
end $$;

-- Admin: who can see / change which step
create or replace function public.crm_wf_perm(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); cur jsonb;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  if p ? 'perm' then
    update public.crm_settings set data = jsonb_set(coalesce(data, '{}'::jsonb), '{wf}', coalesce(data -> 'wf', '{}'::jsonb) || jsonb_build_object('perm', coalesce(p -> 'perm', '{}'::jsonb), 'allow_old', coalesce((p ->> 'allow_old')::boolean, false))), updated_at = now() where id = 1;
    perform public.crm_log(s, 'settings', 'settings', 1, 'Workflow permission badli');
  end if;
  select data -> 'wf' into cur from public.crm_settings where id = 1;
  return jsonb_build_object('perm', coalesce(cur -> 'perm', '{}'::jsonb), 'allow_old', coalesce((cur ->> 'allow_old')::boolean, false), 'names', to_jsonb(public.crm_wf_names()));
end $$;

-- Projects list (Apply Process confirmed, or an old project Admin allowed)
create or replace function public.crm_projects(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token');
begin
  return coalesce((select jsonb_agg(x order by (x ->> 'id')::bigint desc) from (
    select jsonb_build_object('id', q.id, 'ref', q.ref, 'party_id', q.party_id, 'customer', q.title, 'mobile', q.mobile, 'title', coalesce(q.data ->> 'qtitle', q.title), 'ctype', q.data ->> 'ctype',
      'kw', q.data ->> 'kw', 'amount', q.amount, 'status', q.status, 'bill_state', q.data ->> 'bill_state', 'closed', coalesce((q.data ->> 'closed')::boolean, false), 'old', coalesce((q.data ->> 'old_project')::boolean, false),
      'owner', public.crm_uname(q.owner_id), 'done', (select count(*) from jsonb_object_keys(coalesce(q.data -> 'wf', '{}'::jsonb))),
      'total', case when (q.data ->> 'ctype') = 'Residential' then 13 else 12 end,
      'last', (select max(v ->> 'at') from jsonb_each(coalesce(q.data -> 'wf', '{}'::jsonb)) e(k, v)),
      'balance', (select (i.data ->> 'balance')::numeric from public.crm_records i where i.id = nullif(q.data ->> 'invoice_id', '')::bigint),
      'steps', public.crm_wf_steps(s, q)) as x
    from public.crm_records q
    where q.kind = 'quote' and q.deleted_at is null and coalesce(q.data ->> 'ctype', '') in ('Residential', 'Commercial', 'Industrial', 'VFD')
      and ((q.data -> 'wf') ? '7' or coalesce((q.data ->> 'old_project')::boolean, false)) and public.crm_vis(s, q) limit 2000) z), '[]'::jsonb);
end $$;

-- Admin may allow old (final) projects to be added to Projects
create or replace function public.crm_project_import(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; allow boolean;
begin
  select coalesce((data -> 'wf' ->> 'allow_old')::boolean, false) into allow from public.crm_settings where id = 1;
  if not (public.crm_is_admin(s) or allow) then raise exception 'Purane project jodne ki permission Admin ne nahi di'; end if;
  select * into q from public.crm_records where id = (p ->> 'id')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if coalesce(q.data ->> 'ctype', '') not in ('Residential', 'Commercial', 'Industrial', 'VFD') then raise exception 'Pehle quotation me Customer type chunein (Residential / Commercial / Industrial / VFD)'; end if;
  perform set_config('sp.wf', '1', true);
  update public.crm_records set data = public.crm_wf_mark(public.crm_wf_mark(public.crm_wf_mark(data || jsonb_build_object('old_project', true), 6, (s).name), 7, (s).name), 3, (s).name), updated_at = now() where id = q.id;
  perform set_config('sp.wf', '', true);
  perform public.crm_log(s, 'workflow', 'quote', q.id, coalesce(q.ref, '') || ' — purana project Projects me joda');
  return jsonb_build_object('ok', true);
end $$;

-- ---------- Leads → Customer list (only after a conversation) ------------------------------------------------------------
create or replace function public.crm_lead_transfer(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); l public.crm_records; pd jsonb := coalesce(p -> 'party', '{}'::jsonb); mob text; ex public.crm_records; pr jsonb; pid bigint; miss text[] := '{}';
begin
  select * into l from public.crm_records where id = (p ->> 'id')::bigint and kind = 'lead' and deleted_at is null;
  if l.id is null or not public.crm_vis(s, l) then raise exception 'Lead nahi mili'; end if;
  if not (public.crm_is_admin(s) or l.owner_id = (s).uid or l.assigned_to = (s).uid) then raise exception 'Sirf is lead ka user ya Admin ise customer list me bhej sakta hai'; end if;
  if jsonb_array_length(coalesce(l.data -> 'log', '[]'::jsonb)) = 0 then raise exception 'Pehle customer se baat karke "Baat-cheet" me remark likhein, phir Customer list me bhejein'; end if;
  mob := public.crm_mobile(coalesce(pd ->> 'mobile', l.mobile, ''));
  if coalesce(trim(pd ->> 'name'), '') = '' then miss := miss || 'Naam'::text; end if;
  if mob !~ '^[6-9][0-9]{9}$' then miss := miss || 'Mobile'::text; end if;
  if coalesce(trim(pd ->> 'address'), '') = '' then miss := miss || 'Pata'::text; end if;
  if coalesce(trim(pd ->> 'city'), '') = '' then miss := miss || 'Shahar'::text; end if;
  if array_length(miss, 1) > 0 then raise exception 'Customer list me bhejne se pehle ye bharein: %', array_to_string(miss, ', '); end if;
  select * into ex from public.crm_records where kind = 'party' and deleted_at is null and mobile = mob limit 1;
  if ex.id is not null then
    if not public.crm_vis(s, ex) then raise exception 'Ye customer pehle se kisi aur ke paas hai — Admin se transfer karwayein'; end if;
    pid := ex.id;
  else
    pr := public.crm_save(jsonb_build_object('token', p ->> 'token', 'kind', 'party', 'data',
      (pd || jsonb_build_object('mobile', mob, 'source', coalesce(nullif(pd ->> 'source', ''), l.data ->> 'source', ''), 'lead_id', l.id, 'type', 'customer')), 'assigned_to', l.assigned_to));
    pid := (pr ->> 'id')::bigint;
  end if;
  update public.crm_records set status = 'won', party_id = pid, data = data || jsonb_build_object('transferred_party', pid, 'transferred_at', public.crm_iso_now()), updated_at = now() where id = l.id;
  perform public.crm_log(s, 'lead', 'lead', l.id, 'Customer list me bheja → #' || pid);
  return jsonb_build_object('party_id', pid);
end $$;

-- ---------- inbound leads: website / store enquiry and consumer sign-up become CRM leads (name + mobile mandatory) --------
create or replace function public.crm_inbound_lead(p_name text, p_mobile text, p_source text, p_note text, p_extra jsonb default '{}'::jsonb) returns bigint language plpgsql security definer set search_path = public as $$
declare mob text := public.crm_mobile(coalesce(p_mobile, '')); nm text := left(trim(coalesce(p_name, '')), 120); lid bigint; asg bigint;
begin
  if mob !~ '^[6-9][0-9]{9}$' or nm = '' then return null; end if;
  if exists (select 1 from public.crm_records where kind = 'party' and deleted_at is null and mobile = mob) then return null; end if;
  select id into lid from public.crm_records where kind = 'lead' and deleted_at is null and mobile = mob and status not in ('won', 'lost') order by id limit 1;
  if lid is not null then
    update public.crm_records set data = jsonb_set(data, '{log}', coalesce(data -> 'log', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('t', 'Dobara sampark: ' || coalesce(p_source, '') || case when coalesce(p_note, '') <> '' then ' — ' || left(p_note, 300) else '' end, 'at', public.crm_iso_now(), 'by', 'System')), true), updated_at = now() where id = lid;
    return lid;
  end if;
  select nullif(data #>> '{blueprint,assign_to}', '')::bigint into asg from public.crm_settings where id = 1;
  insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, due_at, data, search, created_by)
    values ('lead', nm, mob, 'new', 0, asg, public.crm_today(), jsonb_build_object('name', nm, 'mobile', mob, 'source', coalesce(p_source, 'Website'), 'note', left(coalesce(p_note, ''), 500), 'company', true, 'intake', 'inbound') || coalesce(p_extra, '{}'::jsonb), lower(nm || ' ' || mob), 0)
    returning id into lid;
  return lid;
end $$;

create or replace function public.crm_enq_lead_trg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin
    perform public.crm_inbound_lead(coalesce(new.data ->> 'name', ''), coalesce(new.data ->> 'phone', new.data ->> 'mobile', ''), case when coalesce(new.data ->> 'source', '') = 'website' then 'Website' else 'Online Store' end,
      coalesce(new.data ->> 'subject', new.data ->> 'type', '') || ' ' || coalesce(new.data ->> 'message', ''), jsonb_build_object('enquiry_id', new.id));
  exception when others then null; end;
  return new;
end $$;
do $$ begin
  if to_regclass('public.sp_enquiries') is not null then
    drop trigger if exists crm_enq_lead on public.sp_enquiries;
    create trigger crm_enq_lead after insert on public.sp_enquiries for each row execute function public.crm_enq_lead_trg();
  end if;
end $$;

create or replace function public.crm_signup_lead_trg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.role = 'consumer' then begin perform public.crm_inbound_lead(new.name, new.mobile, 'Online Store', 'Online Store par signup kiya', jsonb_build_object('signup_uid', new.id)); exception when others then null; end; end if;
  return new;
end $$;
drop trigger if exists crm_signup_lead on public.crm_users;
create trigger crm_signup_lead after insert on public.crm_users for each row execute function public.crm_signup_lead_trg();

grant execute on function public.crm_wf_get(jsonb), public.crm_wf_set(jsonb), public.crm_wf_perm(jsonb), public.crm_projects(jsonb), public.crm_project_import(jsonb), public.crm_lead_transfer(jsonb) to anon, authenticated;

-- ---------- Documents & Gallery → send a stamped copy to a customer's plant (Plant ID = quotation number) ------------------
create or replace function public.crm_doc_share(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; b bytea; r public.crm_records; nm text := left(trim(coalesce(p ->> 'name', 'file')), 160); note text := left(trim(coalesce(p ->> 'note', '')), 300);
begin
  if not (public.crm_can(s, 'docs.view') or public.crm_can(s, 'docs.upload')) then raise exception 'Aapko documents bhejne ki permission nahi hai'; end if;
  select * into q from public.crm_records where id = (p ->> 'quote_id')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  begin b := decode(coalesce(p ->> 'b64', ''), 'base64'); exception when others then raise exception 'File padh nahi paye'; end;
  if octet_length(b) = 0 then raise exception 'File khaali hai'; end if;
  if octet_length(b) > 3 * 1024 * 1024 then raise exception 'File 3 MB se badi hai'; end if;
  insert into public.crm_records(kind, title, status, owner_id, party_id, data, search, created_by)
  values ('doc', nm, 'ok', (s).uid, q.party_id,
    jsonb_build_object('mime', left(coalesce(p ->> 'mime', 'application/octet-stream'), 80), 'size', octet_length(b), 'note', note, 'attach_kind', 'party', 'attach_id', q.party_id::text,
      'shared_quote', q.id, 'shared_ref', q.ref, 'shared_at', public.crm_iso_now(), 'shared_by', (s).name, 'stamped', coalesce((p ->> 'stamped')::boolean, false)),
    lower(nm || ' ' || coalesce(q.ref, '')), (s).uid) returning * into r;
  insert into public.crm_files(rec_id, mime, size, data) values (r.id, left(coalesce(p ->> 'mime', 'application/octet-stream'), 80), octet_length(b), b);
  perform public.crm_log(s, 'share', 'doc', r.id, 'Customer ko bheja: ' || nm || ' → ' || coalesce(q.ref, ''));
  return public.crm_row(s, r);
end $$;
grant execute on function public.crm_doc_share(jsonb) to anon, authenticated;

-- =====================================================================
-- Customer "My Plant": a logged-in customer links Plant IDs (= confirmed quotation numbers) that belong to THEIR OWN mobile.
-- Nothing else is exposed: only the whitelist below (no cost, margin, notes, other customers).
-- =====================================================================
create table if not exists public.crm_consumer_plants (user_id bigint not null, quote_id bigint not null, linked_at timestamptz not null default now(), primary key (user_id, quote_id));
create table if not exists public.crm_plant_try (id bigserial primary key, user_id bigint not null, at timestamptz not null default now());
alter table public.crm_consumer_plants enable row level security; alter table public.crm_plant_try enable row level security;
revoke all on public.crm_consumer_plants, public.crm_plant_try from anon, authenticated;

-- the quotation must (a) exist, (b) be confirmed, (c) belong to a customer whose mobile equals the logged-in mobile
create or replace function public.crm_plant_owned(u public.crm_users, q public.crm_records) returns boolean language sql stable security definer set search_path = public as $$
  select q.id is not null and q.kind = 'quote' and q.deleted_at is null and q.status in ('accepted', 'converted')
     and exists (select 1 from public.crm_records pt where pt.id = q.party_id and pt.kind = 'party' and pt.deleted_at is null and pt.mobile = u.mobile and u.mobile ~ '^[6-9][0-9]{9}$') $$;

create or replace function public.crm_plant_card(q public.crm_records) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare pt public.crm_records; inv public.crm_records; w jsonb := coalesce(q.data -> 'wf', '{}'::jsonb); nxt date; lastd text; visits jsonb; pay jsonb; docs jsonb; names text[] := public.crm_wf_names(); i int; tl jsonb := '[]'::jsonb;
        resid boolean := (q.data ->> 'ctype') = 'Residential'; instd text;
begin
  select * into pt from public.crm_records where id = q.party_id;
  select * into inv from public.crm_records where id = nullif(q.data ->> 'invoice_id', '')::bigint and kind = 'invoice' and deleted_at is null;
  select min(due_at) into nxt from public.crm_records where kind = 'reminder' and deleted_at is null and party_id = q.party_id and data ->> 'maint' = 'true' and status <> 'done';
  select max(coalesce(data ->> 'done_on', due_at::text)) into lastd from public.crm_records where kind = 'reminder' and deleted_at is null and party_id = q.party_id and data ->> 'maint' = 'true' and status = 'done';
  select coalesce(jsonb_agg(jsonb_build_object('visit', data ->> 'visit_no', 'plan', data ->> 'plan', 'due', due_at, 'done', status = 'done', 'done_on', data ->> 'done_on') order by due_at), '[]'::jsonb) into visits
    from public.crm_records where kind = 'reminder' and deleted_at is null and party_id = q.party_id and data ->> 'maint' = 'true';
  if inv.id is null then pay := jsonb_build_object('state', 'waiting');
  elsif coalesce((inv.data ->> 'balance')::numeric, inv.amount) <= 0.009 then pay := jsonb_build_object('state', 'paid', 'amount', inv.amount, 'bill', inv.ref);
  else pay := jsonb_build_object('state', 'due', 'amount', inv.amount, 'paid', coalesce((inv.data ->> 'paid')::numeric, 0), 'balance', coalesce((inv.data ->> 'balance')::numeric, inv.amount), 'due_date', coalesce(nullif(inv.data ->> 'due_date', ''), inv.due_at::text), 'bill', inv.ref); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'name', d.title, 'mime', d.data ->> 'mime', 'size', d.data -> 'size', 'at', d.data ->> 'shared_at', 'note', d.data ->> 'note') order by d.id desc), '[]'::jsonb) into docs
    from public.crm_records d where d.kind = 'doc' and d.deleted_at is null and (d.data ->> 'shared_quote') = q.id::text;
  for i in 1..13 loop
    continue when i = 13 and not resid;
    tl := tl || jsonb_build_array(jsonb_build_object('n', i, 'name', names[i], 'done', w ? i::text, 'at', w -> i::text ->> 'at'));
  end loop;
  instd := coalesce(w -> '10' ->> 'at', w -> '9' ->> 'at');
  return jsonb_build_object('id', q.id, 'plant_id', q.ref, 'customer', pt.title, 'ctype', q.data ->> 'ctype', 'kw', nullif(q.data ->> 'kw', ''), 'title', coalesce(q.data ->> 'qtitle', q.title),
    'install_date', left(instd, 10), 'installed', instd is not null, 'confirmed_at', w -> '6' ->> 'at',
    'maintenance', jsonb_build_object('next_due', nxt, 'last_done', lastd, 'visits', visits),
    'payment', pay, 'bill_ref', inv.ref, 'has_bill', inv.id is not null, 'files', docs, 'timeline', tl, 'finished', w ? '12', 'subsidy_done', w ? '13');
end $$;

create or replace function public.crm_consumer_link_plant(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); pid text := upper(regexp_replace(coalesce(p ->> 'plant_id', ''), '\s', '', 'g')); q public.crm_records;
begin
  if length(pid) < 4 or length(pid) > 40 then raise exception 'Plant ID likhein (jaise QT/...)'; end if;
  if (select count(*) from public.crm_plant_try where user_id = u.id and at > now() - interval '15 minutes') >= 8 then raise exception 'Bahut zyada koshish — 15 minute baad phir try karein'; end if;
  select * into q from public.crm_records where kind = 'quote' and deleted_at is null and upper(regexp_replace(coalesce(ref, ''), '\s', '', 'g')) = pid limit 1;
  if q.id is null or not public.crm_plant_owned(u, q) then
    insert into public.crm_plant_try(user_id) values (u.id);    -- returned (not raised) so the attempt is really stored
    return jsonb_build_object('error', 'Ye Plant ID aapke mobile number se juda nahi hai ya abhi confirm nahi hui. Sunpowers se sampark karein.');
  end if;
  insert into public.crm_consumer_plants(user_id, quote_id) values (u.id, q.id) on conflict do nothing;
  return public.crm_plant_card(q);
end $$;

create or replace function public.crm_consumer_unlink_plant(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token');
begin delete from public.crm_consumer_plants where user_id = u.id and quote_id = nullif(p ->> 'id', '')::bigint; return jsonb_build_object('ok', true); end $$;

create or replace function public.crm_consumer_plants(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token');
begin
  return coalesce((select jsonb_agg(public.crm_plant_card(q) order by cp.linked_at) from public.crm_consumer_plants cp join public.crm_records q on q.id = cp.quote_id
    where cp.user_id = u.id and public.crm_plant_owned(u, q)), '[]'::jsonb);
end $$;

-- printable data for the customer's own quotation / bill / maintenance summary (whitelisted fields only)
create or replace function public.crm_consumer_plant_doc(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); q public.crm_records; dk text := coalesce(p ->> 'kind', 'quotation'); src public.crm_records; pt public.crm_records; co jsonb; pays jsonb;
begin
  select q2.* into q from public.crm_records q2 join public.crm_consumer_plants cp on cp.quote_id = q2.id and cp.user_id = u.id where q2.id = nullif(p ->> 'id', '')::bigint;
  if q.id is null or not public.crm_plant_owned(u, q) then raise exception 'Plant nahi mila'; end if;
  select * into pt from public.crm_records where id = q.party_id;
  select data -> 'company' into co from public.crm_settings where id = 1;
  if dk = 'bill' then
    select * into src from public.crm_records where id = nullif(q.data ->> 'invoice_id', '')::bigint and kind = 'invoice' and deleted_at is null;
    if src.id is null then raise exception 'Bill abhi nahi bana'; end if;
    select coalesce(jsonb_agg(jsonb_build_object('date', py.due_at, 'amount', py.amount, 'mode', py.data ->> 'mode') order by py.due_at), '[]'::jsonb) into pays from public.crm_records py where py.kind = 'payment' and py.deleted_at is null and py.data ->> 'invoice_id' = src.id::text;
  else src := q; pays := '[]'::jsonb; end if;
  return jsonb_build_object('kind', dk, 'ref', src.ref, 'date', src.data ->> 'date', 'valid_till', case when dk = 'quotation' then src.data ->> 'valid_till' end, 'title', src.data ->> 'qtitle',
    'customer', jsonb_build_object('name', pt.title, 'mobile', pt.mobile, 'address', pt.data ->> 'address', 'city', pt.data ->> 'city', 'gstin', pt.data ->> 'gstin'),
    'company', jsonb_build_object('name', co ->> 'name', 'legal', co ->> 'legal', 'gstin', co ->> 'gstin', 'phone', co ->> 'phone', 'address', co ->> 'address'),
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('name', l ->> 'name', 'qty', l -> 'qty', 'price', l -> 'price', 'gst', l -> 'gst', 'hsn', l ->> 'hsn')), '[]'::jsonb) from jsonb_array_elements(coalesce(src.data -> 'lines', '[]'::jsonb)) l),
    'subtotal', src.data -> 'subtotal', 'gst_total', src.data -> 'gst_total', 'discount', src.data -> 'discount', 'grand', src.amount, 'paid', src.data -> 'paid', 'balance', src.data -> 'balance', 'payments', pays,
    'notes', src.data ->> 'notes', 'maintenance', public.crm_plant_card(q) -> 'maintenance');
end $$;

create or replace function public.crm_consumer_file(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); d public.crm_records; q public.crm_records; f public.crm_files;
begin
  select * into d from public.crm_records where id = nullif(p ->> 'id', '')::bigint and kind = 'doc' and deleted_at is null and data ? 'shared_quote';
  if d.id is null then raise exception 'File nahi mili'; end if;
  select q2.* into q from public.crm_records q2 join public.crm_consumer_plants cp on cp.quote_id = q2.id and cp.user_id = u.id where q2.id = (d.data ->> 'shared_quote')::bigint;
  if q.id is null or not public.crm_plant_owned(u, q) then raise exception 'File nahi mili'; end if;
  select * into f from public.crm_files where rec_id = d.id limit 1;
  if f.id is null then raise exception 'File nahi mili'; end if;
  return jsonb_build_object('name', d.title, 'mime', f.mime, 'b64', encode(f.data, 'base64'));
end $$;
grant execute on function public.crm_consumer_link_plant(jsonb), public.crm_consumer_unlink_plant(jsonb), public.crm_consumer_plants(jsonb), public.crm_consumer_plant_doc(jsonb), public.crm_consumer_file(jsonb) to anon, authenticated;