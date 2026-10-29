-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 8 of 30
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U30). Safe to re-run.
-- ============================================================================

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
declare s public.crm_ses := public.crm_session(p ->> 'token'); l public.crm_records; pd jsonb := coalesce(p -> 'party', '{}'::jsonb); mob text; ex public.crm_records; pr jsonb; pid bigint; nm text;
begin
  select * into l from public.crm_records where id = (p ->> 'id')::bigint and kind = 'lead' and deleted_at is null;
  if l.id is null or not public.crm_vis(s, l) then raise exception 'Lead nahi mili'; end if;
  if not (public.crm_is_admin(s) or l.owner_id = (s).uid or l.assigned_to = (s).uid) then raise exception 'Sirf is lead ka user ya Admin ise customer list me bhej sakta hai'; end if;
  if jsonb_array_length(coalesce(l.data -> 'log', '[]'::jsonb)) = 0 then raise exception 'Pehle customer se baat karke "Baat-cheet" me remark likhein, phir Customer list me bhejein'; end if;
  mob := public.crm_mobile(coalesce(pd ->> 'mobile', l.mobile, ''));
  if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Customer ka sahi 10 ank ka mobile zaroori hai'; end if;
  nm := trim(coalesce(nullif(pd ->> 'name', ''), nullif(l.data ->> 'name', ''), l.title, ''));
  if nm = '' then raise exception 'Customer ka naam likhein'; end if;
  select * into ex from public.crm_records where kind = 'party' and deleted_at is null and mobile = mob limit 1;
  if ex.id is not null then
    if not public.crm_vis(s, ex) then raise exception 'Ye customer pehle se kisi aur ke paas hai — Admin se transfer karwayein'; end if;
    pid := ex.id;
  else
    pr := public.crm_save(jsonb_build_object('token', p ->> 'token', 'kind', 'party', 'data',
      (pd || jsonb_build_object('name', nm, 'mobile', mob, 'source', coalesce(nullif(pd ->> 'source', ''), l.data ->> 'source', ''), 'lead_id', l.id, 'type', 'customer')), 'assigned_to', l.assigned_to));
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
declare dd jsonb := coalesce(new.data, '{}'::jsonb); src text; intr text; hint text;
begin
  begin
    src := coalesce(public.crm_channel_name(dd ->> 'channel'), case when coalesce(dd ->> 'source', '') = 'website' then 'Website' else 'Online Store' end);
    intr := left(trim(concat_ws(' ', nullif(dd ->> 'subject', ''), nullif(dd ->> 'type', ''), nullif(dd ->> 'product', ''))), 200);
    hint := case when lower(concat_ws(' ', dd ->> 'subject', dd ->> 'type')) ~ '(clean|maintenance|amc|repair|shift|audit|service|error)' then 'service'
                 when lower(concat_ws(' ', dd ->> 'subject', dd ->> 'type', dd ->> 'product')) ~ '(shop|product|buy|order|inverter|panel|battery|cable|structure)' then 'product' else 'project' end;
    perform public.crm_inbound_lead(coalesce(dd ->> 'name', ''), coalesce(dd ->> 'phone', dd ->> 'mobile', ''), src,
      coalesce(dd ->> 'subject', dd ->> 'type', '') || ' ' || coalesce(dd ->> 'message', ''),
      jsonb_strip_nulls(jsonb_build_object('enquiry_id', new.id, 'email', nullif(dd ->> 'email', ''), 'city', nullif(dd ->> 'city', ''), 'address', nullif(dd ->> 'address', ''), 'pincode', nullif(dd ->> 'pincode', ''),
        'kw', nullif(dd ->> 'kw', ''), 'bill', nullif(dd ->> 'bill', ''), 'interest', nullif(intr, ''), 'kind_hint', hint, 'channel', nullif(dd ->> 'channel', ''))));
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
        instd text;
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
  foreach i in array public.crm_wf_flow_of(q) loop
    continue when i = 19;
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
grant execute on function public.crm_consumer_link_plant(jsonb), public.crm_consumer_plants(jsonb), public.crm_consumer_plant_doc(jsonb), public.crm_consumer_file(jsonb) to anon, authenticated;

-- ---------- blueprint tool: reuse the sign-up lead of the same person (one person = one lead) ----------

-- (Round 17 fix) Tools (Blueprint / Error Detector): if this person already has a lead from signing up, use THAT lead (one person = one lead)
grant execute on function public.sp_tool_use(jsonb) to anon, authenticated;


-- =====================================================================================================
-- ROUND 21 — Customer kinds (Project / Product, B2C / B2B) + 18-step flow
--   * Step keys 1..13 are UNCHANGED (live data stays valid). New keys: 14 Send Demo/Files, 15 Loan/Finance,
--     16 Suggest/Referral, 17 AMC/Maintenance, 18 Complaint Status, 19 Leads (computed, never stored).
--   * What a customer sees is decided by crm_wf_flow(): Project customer = full flow, Product customer = short flow.
--   * Safe to run more than once (create or replace only; no data is deleted or rewritten here).
-- =====================================================================================================

-- ---------- step names, indexed by step key ----------

-- ---------- which steps (in which order) a customer type sees. 6 (Confirmation) is internal and never shown ----------
create or replace function public.crm_wf_flow(ct text) returns int[] language sql immutable as $$
  select case
    when ct = 'Items only'  then array[19,1,2,14,3,12,16,18]                               -- Product customer
    when ct = 'Service'     then array[19,1,2,3,4,12,17,16,18]                             -- Service customer (cleaning, AMC, repair, shifting, audit)
    when ct = 'Residential' then array[19,1,2,14,3,4,5,7,15,8,9,10,11,12,13,16,17,18]      -- Project, subsidy applies
    else                         array[19,1,2,14,3,4,5,7,15,8,9,10,11,12,16,17,18] end $$;  -- Project (Commercial / Industrial / VFD / not chosen yet)

create or replace function public.crm_wf_flow_of(q public.crm_records) returns int[] language plpgsql stable security definer set search_path = public as $$
declare ct text := coalesce(q.data ->> 'ctype', ''); ck text;
begin
  if ct = '' and q.party_id is not null then
    select data ->> 'cust_kind' into ck from public.crm_records where id = q.party_id;
    if ck = 'product' then ct := 'Items only'; elsif ck = 'service' then ct := 'Service'; end if;
  end if;
  return public.crm_wf_flow(ct);
end $$;

-- ---------- details collected at each step (server whitelist; the CRM screen draws the same fields) ----------
-- req = mandatory when the step is completed from the new screen (old screens send no "info", so they are not blocked)
create or replace function public.crm_wf_fields() returns jsonb language sql immutable as $$
  select '{
   "4":  [{"k":"roof_type","l":"Chhat ka prakar"},{"k":"roof_area","l":"Chhat ka area (sq ft)"},{"k":"shadow","l":"Chhaya / shadow"},{"k":"phase","l":"Connection (1 / 3 phase)"},{"k":"structure_ht","l":"Structure ki height (ft)"}],
   "5":  [{"k":"kw_final","l":"Final plant size (kW)"},{"k":"panels","l":"Panels (sankhya)"}],
   "7":  [{"k":"discom","l":"DISCOM","req":true},{"k":"consumer_no","l":"Consumer number","req":true},{"k":"sanctioned_load","l":"Sanctioned load (kW)"},{"k":"category","l":"Category (LMV-1 etc.)"},{"k":"portal_app_no","l":"Portal application no."},{"k":"apply_date","l":"Apply ki tareekh"}],
   "8":  [{"k":"tech_name","l":"Technician ka naam","req":true},{"k":"tech_mobile","l":"Technician ka mobile"},{"k":"handover_date","l":"Hand over ki tareekh"}],
   "9":  [{"k":"start_date","l":"Installation shuru hui"},{"k":"team_size","l":"Team (log)"}],
   "10": [{"k":"inverter_sn","l":"Inverter serial no."},{"k":"panel_count","l":"Panels (sankhya)"},{"k":"jcr","l":"Joint Commissioning Report"},{"k":"comm_date","l":"Commissioning ki tareekh"}],
   "11": [{"k":"nm_app_no","l":"Net metering application no."},{"k":"meter_no","l":"Meter number"},{"k":"meter_date","l":"Meter lagne ki tareekh"},{"k":"discom_je","l":"DISCOM JE / contact"}],
   "13": [{"k":"sub_app_no","l":"Subsidy application no."},{"k":"sub_amount","l":"Subsidy amount (Rs)"},{"k":"sub_status","l":"Subsidy status"}],
   "14": [{"k":"sent_what","l":"Kya bheja (demo / datasheet / photo)"},{"k":"sent_mode","l":"Kaise bheja (WhatsApp / Email / Milkar)"}],
   "15": [{"k":"pay_mode","l":"Payment tarika (Cash / Loan / Mixed)","req":true},{"k":"bank","l":"Bank"},{"k":"loan_amount","l":"Loan amount (Rs)"},{"k":"loan_status","l":"Loan status"},{"k":"loan_ref","l":"Loan reference no."}],
   "16": [{"k":"ref_name","l":"Refer kiya (naam)"},{"k":"ref_mobile","l":"Refer kiya (mobile)"}],
   "17": [{"k":"amc_plan","l":"AMC / maintenance plan"},{"k":"amc_start","l":"Shuru ki tareekh"}],
   "18": [{"k":"c_status","l":"Complaint status (None / Open / In progress / Resolved)"},{"k":"c_issue","l":"Samasya"},{"k":"c_ticket","l":"Ticket / complaint no."},{"k":"c_handler","l":"Kisne sambhali (Installer / Dealer / Manufacturer)"},{"k":"c_brand","l":"Brand / product"},{"k":"c_serial","l":"Serial number"},{"k":"c_date","l":"Complaint ki tareekh"}]
  }'::jsonb $$;

-- steps that cannot be ticked by hand (they come from the quotation, the bill, or the lead itself)
create or replace function public.crm_wf_is_auto(n int) returns boolean language sql immutable as $$ select n in (1, 2, 3, 6, 12, 19) $$;
-- steps that may be marked "Lagu nahi" (not applicable for this customer)
create or replace function public.crm_wf_can_skip(n int) returns boolean language sql immutable as $$ select n in (4, 5, 11, 13, 14, 15, 16, 17, 18) $$;

-- marks a step on a quotation by the system (never overwrites, never leaves the bypass flag on)
create or replace function public.crm_wf_auto_q(p_qid bigint, n int, p_by text) returns void language plpgsql security definer set search_path = public as $$
declare q public.crm_records; prev text := coalesce(current_setting('sp.wf', true), '');
begin
  select * into q from public.crm_records where id = p_qid and kind = 'quote' and deleted_at is null;
  if q.id is null or not (n = any (public.crm_wf_flow_of(q))) or (q.data -> 'wf') ? n::text then return; end if;
  perform set_config('sp.wf', '1', true);
  update public.crm_records set data = public.crm_wf_mark(data, n, p_by), updated_at = now() where id = q.id;
  perform set_config('sp.wf', prev, true);
end $$;

-- same, for the customer's latest live quotation
create or replace function public.crm_wf_auto_p(p_party bigint, n int, p_by text) returns void language plpgsql security definer set search_path = public as $$
declare qid bigint;
begin
  if p_party is null then return; end if;
  select id into qid from public.crm_records where kind = 'quote' and deleted_at is null and party_id = p_party and status not in ('rejected', 'expired') order by id desc limit 1;
  if qid is not null then perform public.crm_wf_auto_q(qid, n, p_by); end if;
end $$;

-- ---------- rules on every write (same trigger as before + party checks, project upgrade, auto steps) ----------

drop trigger if exists crm_rules on public.crm_records;
create trigger crm_rules before insert or update on public.crm_records for each row execute function public.crm_rules_trg();

-- ---------- the steps one customer / quotation shows, in flow order ----------

-- the workflow of one quotation (or of a customer who has no quotation yet)

-- confirm / skip / undo one manual step (with its details)

-- Admin: who can see / change which step (names now cover all 19 keys; the screen shows them in flow order)

-- Projects list: progress counts the steps this customer actually has

-- the customer's own "My Plant" tracker (Store / Website): same names and flow, without the internal Leads step

grant execute on function public.crm_wf_get(jsonb), public.crm_wf_set(jsonb), public.crm_wf_perm(jsonb), public.crm_projects(jsonb) to anon, authenticated;

-- ---------- one-time backfill: existing customers that already have a quotation get their kind (adds one key, changes nothing else) ----------
--   project quotation (Residential / Commercial / Industrial / VFD) => 'project'; only "Items only" quotations => 'product'.
--   Customers without any quotation stay unset (the CRM shows "Set nahi" until you choose). Running it again changes nothing.
update public.crm_records p set data = p.data || jsonb_build_object('cust_kind',
    case when exists (select 1 from public.crm_records q where q.kind = 'quote' and q.deleted_at is null and q.party_id = p.id and coalesce(q.data ->> 'ctype', '') in ('Residential', 'Commercial', 'Industrial', 'VFD'))
         then 'project' else 'product' end)
  where p.kind = 'party' and p.deleted_at is null and coalesce(p.data ->> 'cust_kind', '') = ''
    and exists (select 1 from public.crm_records q where q.kind = 'quote' and q.deleted_at is null and q.party_id = p.id and coalesce(q.data ->> 'ctype', '') <> '');

-- ======================================================================================================
-- ROUND 21b — Mobile number is mandatory EVERYWHERE (email is optional and never enough on its own),
--             every lead / customer carries its PATH (source), and a "Service" customer type.
-- ======================================================================================================

-- Lead -> Customer: mobile mandatory; the details come from the customer form (the trigger checks them)

-- name of an ad / marketing channel from its code (Settings → Marketing → channels)
create or replace function public.crm_channel_name(p_code text) returns text language sql stable security definer set search_path = public as $$
  select c ->> 'name' from public.crm_settings s, jsonb_array_elements(coalesce(s.data #> '{marketing,channels}', '[]'::jsonb)) c
   where s.id = 1 and coalesce(p_code, '') <> '' and upper(coalesce(c ->> 'code', '')) = upper(p_code) and coalesce(c ->> 'name', '') <> '' limit 1 $$;

-- Website / Store enquiry -> Lead.  Path (source) is filled by itself: ad channel > Website > Online Store; what he asked for travels along

-- Online Store order: the buyer is a PRODUCT / B2C customer when the order carries everything a customer needs (name, mobile, address, city, pincode);
-- otherwise he enters Leads (path "Online Store") and is made a customer by staff.  Either way a lead with its path exists.
create or replace function public.crm_order_customer(p_data jsonb, p_oid bigint) returns bigint language plpgsql security definer set search_path = public as $$
declare mob text := public.crm_mobile(coalesce(p_data ->> 'phone', p_data ->> 'mobile', '')); nm text := left(trim(coalesce(p_data ->> 'name', '')), 120); pid bigint; items text; ad text := trim(coalesce(p_data ->> 'address', ''));
        ct text := trim(coalesce(p_data ->> 'city', '')); pin text := regexp_replace(coalesce(p_data ->> 'pincode', ''), '\D', '', 'g');
begin
  if mob !~ '^[6-9][0-9]{9}$' or nm = '' then return null; end if;
  select id into pid from public.crm_records where kind = 'party' and deleted_at is null and mobile = mob order by id limit 1;
  if pid is not null then return pid; end if;
  if ad = '' or ct = '' or pin !~ '^[0-9]{6}$' then
    perform public.crm_inbound_lead(nm, mob, 'Online Store', 'Store order #' || p_oid, jsonb_strip_nulls(jsonb_build_object('email', nullif(p_data ->> 'email', ''), 'city', nullif(ct, ''), 'address', nullif(ad, ''), 'order_id', p_oid, 'kind_hint', 'product')));
    return null;
  end if;
  select left(string_agg(coalesce(i ->> 'title', ''), ', '), 180) into items from jsonb_array_elements(case when jsonb_typeof(p_data -> 'items') = 'array' then p_data -> 'items' else '[]'::jsonb end) i;
  insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, due_at, data, search, created_by)
    values ('party', nm, mob, 'active', 0, null, null,
      jsonb_strip_nulls(jsonb_build_object('name', nm, 'mobile', mob, 'email', nullif(lower(trim(coalesce(p_data ->> 'email', ''))), ''), 'address', ad, 'city', ct, 'pincode', pin, 'type', 'customer', 'source', 'Online Store',
        'cust_kind', 'product', 'segment', 'b2c', 'interest', coalesce(nullif(items, ''), 'Online Store order'), 'store_order_id', p_oid, 'intake', 'store')),
      lower(concat_ws(' ', nm, mob, ct)), 0)
    returning id into pid;
  return pid;
end $$;

-- every customer added directly (no lead behind it) gets a lead record with the same path, so Leads really is "all enquiries from everywhere"
create or replace function public.crm_party_lead_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare lid bigint; src text;
begin
  if new.kind <> 'party' or new.deleted_at is not null or coalesce(new.data ->> 'type', 'customer') = 'supplier' or (new.data ? 'lead_id') or coalesce(new.mobile, '') = '' then return new; end if;
  begin
    src := coalesce(nullif(trim(new.data ->> 'source'), ''), 'Purana / Unknown');
    select id into lid from public.crm_records where kind = 'lead' and deleted_at is null and mobile = new.mobile and status not in ('won', 'lost') order by id limit 1;
    if lid is not null then
      update public.crm_records set status = 'won', party_id = new.id, data = data || jsonb_build_object('transferred_party', new.id, 'transferred_at', public.crm_iso_now()), updated_at = now() where id = lid;
    else
      insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, due_at, party_id, data, search, created_by)
        values ('lead', new.title, new.mobile, 'won', coalesce(new.owner_id, 0), new.assigned_to, null, new.id,
          jsonb_build_object('name', new.title, 'mobile', new.mobile, 'source', src, 'city', coalesce(new.data ->> 'city', ''), 'intake', 'customer-add', 'transferred_party', new.id, 'transferred_at', public.crm_iso_now()),
          lower(concat_ws(' ', new.title, new.mobile)), 0);
    end if;
  exception when others then null; end;
  return new;
end $$;
drop trigger if exists crm_party_lead on public.crm_records;
create trigger crm_party_lead after insert on public.crm_records for each row when (new.kind = 'party') execute function public.crm_party_lead_trg();

create or replace function public.crm_order_customer_trg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin perform public.crm_order_customer(new.data, new.id); exception when others then null; end;
  return new;
end $$;

-- old store orders: buyers that are not in the CRM yet (complete ones become customers, the rest become leads)
do $$ begin
  if to_regclass('public.sp_orders') is not null then
    drop trigger if exists crm_order_customer on public.sp_orders;
    create trigger crm_order_customer after insert on public.sp_orders for each row execute function public.crm_order_customer_trg();
    perform public.crm_order_customer(o.data, o.id) from public.sp_orders o;
  end if;
end $$;

-- ================================================================= Round 22 cleanup: old, never-used functions are removed from live databases too
drop function if exists public.crm_register(jsonb);
drop function if exists public.crm_questions(jsonb);
drop function if exists public.crm_reset(jsonb);
drop function if exists public.crm_err(text);
drop function if exists public.crm_consumer_unlink_plant(jsonb);
drop function if exists public.sp_admin_pending_payments(text);

-- ================================================================= Round 22: Store App "Create ID with PIN" (mobile + PIN, no OTP) + small profile photo
-- A customer can create an ID with name + mobile + 4-digit PIN (optional photo, compressed to ~5 KB on the phone) and log in later with mobile + PIN.
-- Because the mobile is not verified by OTP, such an account sees only the orders placed under its OWN ID (not old orders that only share the mobile number).
create or replace function public.sp_cust_signup(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare m text := public.crm_mobile(p ->> 'mobile'); nm text := left(trim(coalesce(p ->> 'name', '')), 80); pin text := coalesce(p ->> 'pin', ''); av text := coalesce(p ->> 'avatar', '');
        ex public.crm_users; u public.crm_users; un text; recent int;
begin
  if nm = '' then raise exception 'Naam likhein'; end if;
  if m !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein'; end if;
  perform public.crm_auth_pin_valid(jsonb_build_object('pin_len', 4), pin);
  if av <> '' and (av !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' or length(av) > 9000) then av := ''; end if;
  select count(*) into recent from public.crm_activity where action = 'register' and role = 'consumer' and at > now() - interval '1 hour';
  if recent >= 60 then raise exception 'Abhi bahut ID ban rahi hain — thodi der baad koshish karein'; end if;
  select * into ex from public.crm_users where role = 'consumer' and mobile = m order by id limit 1;
  if ex.id is not null and (ex.pin_hash <> '' or ex.email_ok or coalesce(ex.pass_hash, '') <> '') then
    raise exception 'Is mobile se ID pehle se bani hai — "Login with PIN" dabayein'; end if;
  if ex.id is null then
    un := m;
    while exists (select 1 from public.crm_users where username = un) loop un := un || floor(random() * 10)::int::text; end loop;
    insert into public.crm_users(role, username, name, mobile, email, pass_hash, status, pin_hash, meta)
    values ('consumer', un, nm, m, '', '', 'active', crypt(pin, gen_salt('bf')), jsonb_build_object('mob_ok', false, 'quick', true) || case when av <> '' then jsonb_build_object('avatar', av) else '{}'::jsonb end)
    returning * into u;
    insert into public.crm_activity(user_id, user_name, role, action, summary) values (u.id, nm, 'consumer', 'register', 'Nayi ID (PIN): ' || m);
  else
    update public.crm_users set name = nm, pin_hash = crypt(pin, gen_salt('bf')), pin_fail = 0, status = case when status = 'blocked' then status else 'active' end,
      meta = coalesce(meta, '{}'::jsonb) || jsonb_build_object('mob_ok', false, 'quick', true) || case when av <> '' then jsonb_build_object('avatar', av) else '{}'::jsonb end
    where id = ex.id returning * into u;
  end if;
  if u.status = 'blocked' then raise exception 'Ye ID band hai — Admin se sampark karein'; end if;
  return public.crm_auth_session(jsonb_build_object('uid', u.id, 'name', u.name, 'role', 'consumer', 'status', 'active', 'has_q', false, 'dev_name', p ->> 'dev_name'), p ->> 'device', 'store');
end $$;