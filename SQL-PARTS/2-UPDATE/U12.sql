-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 12 of 30
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U30). Safe to re-run.
-- ============================================================================

-- customer app profile now also lists all bills (Pending / Paid / Cancelled)

-- Customer app / shop page: one profile by mobile login — Customer ID, projects (+warranty, AMC), products (+warranty), services (+status), pending quotations
create or replace function public.crm_consumer_profile(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); pt public.crm_records; q public.crm_records; inv public.crm_records; l jsonb; k text; card jsonb; wl jsonb;
        bills jsonb := '[]'::jsonb; projects jsonb := '[]'::jsonb; services jsonb := '[]'::jsonb; inquiries jsonb := '[]'::jsonb; products jsonb := '[]'::jsonb; cid text; it public.crm_records; qk text;
begin
  select * into pt from public.crm_records where kind = 'party' and deleted_at is null and mobile = u.mobile and u.mobile ~ '^[6-9][0-9]{9}$' and coalesce(data ->> 'type', 'customer') <> 'supplier' order by id limit 1;
  if pt.id is null then
    select data ->> 'cust_id' into cid from public.crm_records where kind = 'lead' and deleted_at is null and mobile = u.mobile order by id limit 1;
    return jsonb_build_object('cust_id', cid, 'stage', 'lead', 'name', u.name, 'mobile', u.mobile, 'projects', projects, 'services', services, 'products', products, 'inquiries', inquiries, 'bills', bills);
  end if;
  for q in select * from public.crm_records where kind = 'quote' and party_id = pt.id and deleted_at is null order by id loop
    k := case when q.data ->> 'ctype' in ('Residential', 'Commercial', 'Industrial', 'VFD') then 'project' when q.data ->> 'ctype' = 'Items only' then 'product' when coalesce(q.data ->> 'ctype', '') = '' then 'project' else 'service' end;
    if q.status in ('accepted', 'converted') then
      if k = 'product' then continue; end if;
      insert into public.crm_consumer_plants(user_id, quote_id) values (u.id, q.id) on conflict do nothing;
      card := public.crm_plant_card(q);
      wl := '[]'::jsonb;
      for l in select * from jsonb_array_elements(coalesce(q.data -> 'lines', '[]'::jsonb)) loop
        select * into it from public.crm_records where id = nullif(l ->> 'item_id', '')::bigint and kind = 'item';
        if it.id is not null and coalesce(it.data ->> 'warranty', '') <> '' then wl := wl || jsonb_build_array(jsonb_build_object('name', coalesce(l ->> 'name', it.title), 'warranty', it.data ->> 'warranty')); end if;
      end loop;
      card := card || jsonb_build_object('kind', k, 'warranty', wl, 'job_status', case when (q.data ->> 'closed') = 'true' then 'Poora hua' else 'Chal raha hai' end);
      if k = 'project' then projects := projects || jsonb_build_array(card); else services := services || jsonb_build_array(card); end if;
    elsif q.status in ('draft', 'sent') then
      inquiries := inquiries || jsonb_build_array(jsonb_build_object('id', q.id, 'ref', q.ref, 'title', coalesce(q.data ->> 'qtitle', q.title), 'kind', k, 'status', case q.status when 'sent' then 'Quotation bheji gayi' else 'Taiyaar ho rahi hai' end));
    end if;
  end loop;
  for inv in select i.* from public.crm_records i where i.kind = 'invoice' and i.party_id = pt.id and i.deleted_at is null order by i.id loop
    bills := bills || jsonb_build_array(jsonb_build_object('id', inv.id, 'ref', inv.ref, 'date', inv.data ->> 'date', 'title', coalesce(inv.data ->> 'qtitle', inv.title), 'amount', inv.amount, 'paid', coalesce((inv.data ->> 'paid')::numeric, 0), 'balance', coalesce((inv.data ->> 'balance')::numeric, inv.amount), 'due_date', nullif(coalesce(inv.data ->> 'due_date', inv.due_at::text), ''),
      'state', case when (inv.data ->> 'cancelled') = 'true' then 'cancelled' when coalesce((inv.data ->> 'balance')::numeric, inv.amount) <= 0.009 then 'paid' else 'pending' end, 'nonrefundable', coalesce((inv.data ->> 'refund_ok')::boolean, false) = false));
    qk := null;
    select case when q2.data ->> 'ctype' = 'Items only' then 'product' else 'other' end into qk from public.crm_records q2 where q2.id = nullif(inv.data ->> 'quote_id', '')::bigint;
    if qk = 'other' then continue; end if;
    for l in select * from jsonb_array_elements(coalesce(inv.data -> 'lines', '[]'::jsonb)) loop
      select * into it from public.crm_records where id = nullif(l ->> 'item_id', '')::bigint and kind = 'item';
      products := products || jsonb_build_array(jsonb_build_object('name', coalesce(l ->> 'name', it.title), 'qty', l -> 'qty', 'bill', inv.ref, 'date', inv.data ->> 'date', 'brand', it.data ->> 'brand', 'warranty', nullif(it.data ->> 'warranty', ''), 'paid', coalesce((inv.data ->> 'balance')::numeric, inv.amount) <= 0.009));
    end loop;
  end loop;
  return jsonb_build_object('cust_id', pt.data ->> 'cust_id', 'stage', coalesce(pt.data ->> 'stage', 'customer'), 'name', pt.title, 'mobile', pt.mobile,
    'projects', projects, 'services', services, 'products', products, 'inquiries', inquiries, 'bills', bills);
end $$;
grant execute on function public.crm_consumer_profile(jsonb) to anon, authenticated;

-- ================= ROUND 37 — ek customer = ek hi record (clone band) =================
-- Pehle STAGING me chalayein, phir backup ke baad LIVE me.

CREATE OR REPLACE FUNCTION public.crm_inbound_lead(p_name text, p_mobile text, p_source text, p_note text, p_extra jsonb DEFAULT '{}'::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pid_ bigint; mob text := public.crm_mobile(coalesce(p_mobile, '')); nm text := left(trim(coalesce(p_name, '')), 120); lid bigint; asg bigint;
begin
  if mob !~ '^[6-9][0-9]{9}$' or nm = '' then return null; end if;
  select id into pid_ from public.crm_records where kind = 'party' and deleted_at is null and mobile = mob order by id limit 1;
  if pid_ is not null then /* purana customer: naya lead nahi, par inquiry customer ke page par jud jaati hai */
    update public.crm_records set data = jsonb_set(data, '{inquiries}', coalesce(data -> 'inquiries', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('at', public.crm_iso_now(), 'source', coalesce(p_source, ''), 'note', left(coalesce(p_note, ''), 300))), true), updated_at = now()
      where id = pid_ and jsonb_array_length(coalesce(data -> 'inquiries', '[]'::jsonb)) < 60;
    return null;
  end if;
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
end $function$

;

CREATE OR REPLACE FUNCTION public.crm_lead_import(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); to_ bigint := nullif(p ->> 'assign_to', '')::bigint; r jsonb; m text; n int := 0; sk int := 0; own bigint; company boolean;
begin
  perform public.crm_need(s, 'leads.import');
  if to_ is not null and to_ <> (s).uid then
    perform public.crm_need(s, 'leads.assign');
    if not exists (select 1 from public.crm_users where id = to_ and status = 'active') then raise exception 'User nahi mila'; end if;
  end if;
  if jsonb_typeof(p -> 'rows') <> 'array' or jsonb_array_length(p -> 'rows') > 3000 then raise exception 'Ek baar me max 3000 leads'; end if;
  company := to_ is not null and to_ <> (s).uid;
  own := case when company then 0 else (s).uid end;
  for r in select * from jsonb_array_elements(p -> 'rows') loop
    if jsonb_typeof(r) <> 'object' or length(r::text) > 4000 then sk := sk + 1; continue; end if;
    m := public.crm_mobile(r ->> 'mobile');
    if m !~ '^[6-9][0-9]{9}$' then sk := sk + 1; continue; end if;
    if exists (select 1 from public.crm_records where kind = 'party' and deleted_at is null and mobile = m) or exists (select 1 from public.crm_records where kind = 'lead' and deleted_at is null and mobile = m and status not in ('won', 'lost')) then sk := sk + 1; continue; end if;
    insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, due_at, data, search, created_by)
    values ('lead', left(coalesce(nullif(trim(r ->> 'name'), ''), 'Lead ' || m), 120), m, 'new', own, coalesce(to_, (s).uid),
      case when coalesce(r ->> 'followup', '') ~ '^\d{4}-\d{2}-\d{2}$' then (r ->> 'followup')::date else null end,
      (r - 'mobile') || jsonb_build_object('mobile', m, 'source', coalesce(nullif(r ->> 'source', ''), case when company then 'Company' else 'Import' end), 'company', company),
      lower(concat_ws(' ', r ->> 'name', m, r ->> 'city', r ->> 'source')), (s).uid);
    n := n + 1;
  end loop;
  perform public.crm_log(s, 'import', 'lead', null, n || ' leads import' || case when company then ' → ' || public.crm_uname(to_) else '' end || ' (' || sk || ' chhodi)');
  return jsonb_build_object('added', n, 'skipped', sk);
end $function$

;

CREATE OR REPLACE FUNCTION public.crm_blueprint_save(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); bp jsonb := p -> 'blueprint'; id_ bigint := nullif(p ->> 'id', '')::bigint; old public.crm_records;
        nm text := left(trim(coalesce(p ->> 'name', '')), 80); mob text := public.crm_mobile(coalesce(p ->> 'mobile', '')); city text := left(trim(coalesce(p ->> 'city', '')), 80);
        mk boolean := coalesce((p ->> 'make_lead')::boolean, false); bid bigint; lid bigint; pid bigint := nullif(p ->> 'party_id', '')::bigint; pty public.crm_records; kw numeric; summary text; ex public.crm_records;
begin
  perform public.crm_need(s, 'leads.create');
  if bp is null or jsonb_typeof(bp) <> 'object' then raise exception 'Blueprint adhura hai'; end if;
  bp := (bp - 'photos' - 'video') || jsonb_build_object('photo_count', case when jsonb_typeof(bp -> 'photos') = 'array' then jsonb_array_length(bp -> 'photos') else coalesce(nullif(bp ->> 'photo_count', '')::int, 0) end);
  if length(bp::text) > 200000 then raise exception 'Blueprint bahut bada hai'; end if;
  if nm = '' then nm := 'Blueprint'; end if;
  if pid is not null then select * into pty from public.crm_records where id = pid and kind = 'party' and deleted_at is null; if pty.id is null or not public.crm_vis(s, pty) then raise exception 'Customer nahi mila'; end if; if mob = '' then mob := coalesce(pty.mobile, ''); end if;
  elsif mob ~ '^[6-9][0-9]{9}$' then select * into pty from public.crm_records where kind = 'party' and deleted_at is null and mobile = mob order by id limit 1; if pty.id is not null and not public.crm_vis(s, pty) then pty := null; end if; end if;
  pid := pty.id;
  if mk and mob !~ '^[6-9][0-9]{9}$' then raise exception 'Lead ke liye sahi 10 ank ka mobile likhein'; end if;
  kw := public.crm_num(bp #> '{result,kw}');
  if id_ is null then
    insert into public.crm_records(kind, title, mobile, status, owner_id, data, search, created_by)
      values ('blueprint', nm, nullif(mob, ''), 'new', (s).uid, (bp - 'customer') || jsonb_build_object('customer', jsonb_build_object('name', nm, 'mobile', mob, 'city', city), 'from', 'crm'), lower(nm || ' ' || coalesce(mob, '')), (s).uid) returning id into bid;
    perform public.crm_log(s, 'create', 'blueprint', bid, nm);
  else
    select * into old from public.crm_records where id = id_ and kind = 'blueprint' and deleted_at is null;
    if old.id is null or not public.crm_vis(s, old) then raise exception 'Blueprint nahi mila'; end if;
    update public.crm_records set title = nm, mobile = nullif(mob, ''), data = (bp - 'customer') || jsonb_build_object('customer', jsonb_build_object('name', nm, 'mobile', mob, 'city', city), 'lead_id', old.data -> 'lead_id', 'from', old.data -> 'from'),
      search = lower(nm || ' ' || coalesce(mob, '')), updated_at = now() where id = id_;
    bid := id_;
    perform public.crm_log(s, 'update', 'blueprint', bid, nm);
  end if;
  if pid is not null then /* customer pehle se hai: blueprint usi se judta hai, naya lead NAHI banta, flow ka Blueprint step apne aap */
    update public.crm_records set party_id = pid where id = bid;
    perform public.crm_wf_auto_p(pid, 5, 'Blueprint (system)');
    mk := false;
  end if;
  if mk then
    summary := 'Blueprint: ' || coalesce(bp #>> '{site,type}', '-') || ', ' || coalesce(bp #>> '{result,panels}', '0') || ' panels, ' || coalesce(kw::text, '0') || ' kW, structure ' || coalesce(bp #>> '{structure,type}', '-');
    select * into ex from public.crm_records where kind = 'lead' and deleted_at is null and mobile = mob and status not in ('won', 'lost') order by id desc limit 1;
    if ex.id is not null then
      update public.crm_records set data = data || jsonb_build_object('blueprint_id', bid, 'kw', kw, 'note', summary), updated_at = now() where id = ex.id; lid := ex.id;
    else
      insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, due_at, data, search, created_by)
        values ('lead', nm, mob, 'new', (s).uid, (s).uid, public.crm_today(),
          jsonb_build_object('name', nm, 'mobile', mob, 'city', city, 'source', 'Leads from project blueprint', 'kw', kw, 'note', summary, 'blueprint_id', bid, 'address', coalesce(bp #>> '{location,addr}', '')),
          lower(nm || ' ' || mob), (s).uid) returning id into lid;
      perform public.crm_log(s, 'create', 'lead', lid, nm || ' (blueprint)');
    end if;
    update public.crm_records set data = data || jsonb_build_object('lead_id', lid) where id = bid;
  end if;
  return jsonb_build_object('ok', true, 'id', bid, 'lead_id', lid, 'party_id', pid);
end $function$

;

-- 4 koi bhi naya lead: customer ya khuli lead ke mobile par nahi ban sakta (kisi bhi raaste se: form, Excel, manual, blueprint)
create or replace function public.crm_lead_dedupe_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare pt public.crm_records; ex public.crm_records;
begin
  if new.kind <> 'lead' or new.deleted_at is not null or new.status in ('won', 'lost') or coalesce(new.mobile, '') = '' then return new; end if;
  if coalesce(new.data ->> 'intake', '') = 'customer-add' then return new; end if;
  select * into pt from public.crm_records where kind = 'party' and deleted_at is null and mobile = new.mobile and coalesce(data ->> 'type', 'customer') <> 'supplier' order by id limit 1;
  if pt.id is not null then raise exception 'Ye customer pehle se hai: % (ID %) — Customers me jaakar usi ka kaam karein, nayi lead nahi banegi', pt.title, coalesce(pt.data ->> 'cust_id', '#' || pt.id); end if;
  select * into ex from public.crm_records where kind = 'lead' and deleted_at is null and mobile = new.mobile and status not in ('won', 'lost') and id <> coalesce(new.id, 0) order by id limit 1;
  if ex.id is not null then raise exception 'Ye lead pehle se hai: % (ID %) — usi ko kholein', ex.title, coalesce(ex.data ->> 'cust_id', '#' || ex.id); end if;
  return new;
end $$;
drop trigger if exists crm_lead_dedupe on public.crm_records;
create trigger crm_lead_dedupe before insert on public.crm_records for each row when (new.kind = 'lead') execute function public.crm_lead_dedupe_trg();

-- 5 site visit hamesha kisi customer se judti hai (mobile se apne aap judti hai; customer na ho to visit nahi banti)
create or replace function public.crm_visit_party_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare pid bigint;
begin
  if new.kind <> 'reminder' or coalesce(new.data ->> 'type', '') <> 'sitevisit' or new.deleted_at is not null or new.party_id is not null then return new; end if;
  select id into pid from public.crm_records where kind = 'party' and deleted_at is null and mobile = public.crm_mobile(coalesce(new.data ->> 'mobile', new.mobile, '')) order by id limit 1;
  if pid is not null then new.party_id := pid; return new; end if;
  if TG_OP = 'INSERT' then raise exception 'Site visit sirf customer ki hoti hai — pehle Customers me us customer ko jodein / chunein'; end if;
  return new;
end $$;
drop trigger if exists crm_visit_party on public.crm_records;
create trigger crm_visit_party before insert or update on public.crm_records for each row when (new.kind = 'reminder') execute function public.crm_visit_party_trg();

-- 6 Referral plant: customer system me nahi hai to wo bhi ek lead ban kar flow me aata hai (alag "bhoot" customer nahi rehta)
create or replace function public.crm_plant_lead_trg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.kind <> 'plant' or new.deleted_at is not null or new.party_id is not null or coalesce(new.mobile, '') = '' then return new; end if;
  begin
    perform public.crm_inbound_lead(coalesce(new.data ->> 'name', new.title, ''), new.mobile, 'Referral plant', 'Referral plant: ' || coalesce(new.data ->> 'kw', '') || ' kW', jsonb_strip_nulls(jsonb_build_object('city', nullif(new.data ->> 'city', ''), 'address', nullif(new.data ->> 'address', ''), 'kw', nullif(new.data ->> 'kw', ''), 'kind_hint', 'project')));
  exception when others then null; end;
  return new;
end $$;
drop trigger if exists crm_plant_lead on public.crm_records;
create trigger crm_plant_lead after insert on public.crm_records for each row when (new.kind = 'plant') execute function public.crm_plant_lead_trg();

-- 7 crm_save: purani 'won/lost' lead ab nayi lead ko nahi rokti (asli wajah wala saaf message milta hai)
CREATE OR REPLACE FUNCTION public.crm_save(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); k text := p ->> 'kind'; id_ bigint := nullif(p ->> 'id', '')::bigint;
        d jsonb := coalesce(p -> 'data', '{}'::jsonb); old public.crm_records; r public.crm_records; isnew boolean := id_ is null or id_ = 0;
        mob text; em text; ttl text; st text := coalesce(p ->> 'status', ''); asg bigint := nullif(p ->> 'assigned_to', '')::bigint; pid bigint := nullif(p ->> 'party_id', '')::bigint;
        due date := nullif(p ->> 'due_at', '')::date; amt numeric := 0; ref_ text; calc jsonb; srch text; ex public.crm_records; it public.crm_records; l jsonb;
        lim numeric; owner_ bigint; f public.crm_records; prev_status text; msg_ text;
begin
  if k not in ('party', 'item', 'quote', 'invoice', 'payment', 'purchase', 'lead', 'reminder', 'plant', 'earning', 'folder', 'doc', 'note', 'notice') then raise exception 'Galat record'; end if;
  if jsonb_typeof(d) <> 'object' or length(d::text) > 200000 then raise exception 'Data bahut bada ya galat hai'; end if;
  if not isnew then
    select * into old from public.crm_records where id = id_ and kind = k;
    if not public.crm_vis(s, old) then raise exception 'Record nahi mila'; end if;
    prev_status := old.status;
  end if;
  mob := public.crm_mobile(coalesce(d ->> 'mobile', ''));
  em := lower(left(trim(coalesce(d ->> 'email', '')), 160));
  ttl := left(trim(coalesce(d ->> 'name', d ->> 'title', '')), 200);
  owner_ := case when isnew then (s).uid else old.owner_id end;
  if not isnew and pid is null and not (p ? 'party_id') then pid := old.party_id; end if;
  if not isnew and not (p ? 'assigned_to') then asg := old.assigned_to; end if;
  if not isnew and not (p ? 'due_at') then due := old.due_at; end if;

  -- ---------------- per kind rules
  if k = 'party' then
    perform public.crm_need(s, case when isnew then 'customers.create' else 'customers.edit' end);
    if ttl = '' then raise exception 'Customer ka naam likhein'; end if;
    if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein (mobile zaroori hai)'; end if;
    if em <> '' and em !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'Sahi email likhein (ya khali chhodein)'; end if;
    select * into ex from public.crm_records where kind = 'party' and deleted_at is null and mobile = mob and id <> coalesce(id_, 0) limit 1;
    if ex.id is not null then
      if public.crm_vis(s, ex) then raise exception 'Ye customer pehle se list me hai: % (#%)', ex.title, ex.id;
      else raise exception 'Ye customer pehle se % ke paas hai — Admin se transfer karwayein', coalesce(public.crm_uname(ex.owner_id), 'kisi aur'); end if;
    end if;
    if (p ? 'assigned_to') and asg is distinct from (case when isnew then null else old.assigned_to end) then perform public.crm_need(s, 'customers.assign'); end if;
    pid := null; st := coalesce(nullif(st, ''), case when isnew then 'active' else old.status end);
  elsif k = 'item' then
    perform public.crm_need(s, case when isnew then 'items.create' else 'items.edit' end);
    if not isnew and old.data ->> 'fixed' = 'true' and not public.crm_is_admin(s) then raise exception 'Ye Fixed plan hai — sirf Admin iski keemat / kaam ki list badal sakta hai'; end if;
    if ttl = '' then raise exception 'Item ka naam likhein'; end if;
    amt := public.crm_num(d -> 'price'); mob := null; pid := null;
    if not public.crm_can(s, 'items.cost') and not isnew then d := d || jsonb_build_object('cost_price', old.data -> 'cost_price', 'min_price', old.data -> 'min_price'); end if;
    -- online store status: only the review flow can publish
    if not isnew then d := jsonb_set(d, '{store}', coalesce(old.data -> 'store', '{}'::jsonb) || (coalesce(d -> 'store', '{}'::jsonb) - 'status' - 'store_id' - 'reviewed_at')); end if;
    if isnew then d := jsonb_set(d, '{store}', (coalesce(d -> 'store', '{}'::jsonb) - 'store_id' - 'reviewed_at') || '{"status":"none"}'::jsonb); end if;
    d := public.crm_item_prep(isnew, case when isnew then null else old.data end, d);   -- Round 13: auto SKU (immutable), project line SKUs
    st := coalesce(nullif(st, ''), 'active');
  elsif k in ('quote', 'invoice', 'purchase') then
    perform public.crm_need(s, case when k = 'purchase' then 'purchase.manage' when isnew then k || 's.create' else k || 's.edit' end);
    if pid is null then raise exception 'Customer / party chunein'; end if;
    select * into ex from public.crm_records where id = pid and kind = 'party';
    if not public.crm_vis(s, ex) then raise exception 'Customer nahi mila'; end if;
    if jsonb_typeof(d -> 'lines') <> 'array' or jsonb_array_length(d -> 'lines') = 0 then raise exception 'Kam se kam 1 item jodein'; end if;
    if k = 'invoice' and isnew and coalesce(d ->> 'quote_id', '') = '' then raise exception 'Bill sirf quotation se banta hai — pehle quotation banayein'; end if;
    calc := public.crm_doc_calc(d);
    if k = 'quote' and not public.crm_can(s, 'quotes.discount_any') then
      for l in select * from jsonb_array_elements(d -> 'lines') loop
        if coalesce(l ->> 'kind', 'product') <> 'project' and coalesce(l ->> 'item_id', '') <> '' then
          select * into it from public.crm_records where id = (l ->> 'item_id')::bigint and kind = 'item';
          if it.id is not null and public.crm_num(it.data -> 'min_price') > 0 and public.crm_num(l -> 'price') < public.crm_num(it.data -> 'min_price') then
            raise exception '"%" ka rate minimum rate se kam hai — Admin se permission lein', it.title; end if;
        end if;
      end loop;
      select public.crm_num(meta -> 'max_discount_pct') into lim from public.crm_users where id = (s).uid;
      if (s).uid <> 0 and public.crm_num(calc -> 'discount') > 0 and public.crm_num(calc -> 'discount') > coalesce(lim, 0) * (public.crm_num(calc -> 'subtotal') + public.crm_num(calc -> 'gst_total')) / 100 + 0.009 then
        raise exception 'Discount aapki limit (% %%) se zyada hai', coalesce(lim, 0); end if;
    end if;
    if k = 'quote' then
      d := d || jsonb_build_object('qtitle', left(trim(coalesce(d ->> 'qtitle', case when isnew then '' else old.data ->> 'qtitle' end, '')), 120));
      if isnew and length(d ->> 'qtitle') < 2 then raise exception 'Quotation ka Title zaroori hai (jaise: 5 kW Rooftop - Sharma ji)'; end if;
      if coalesce(d ->> 'valid_till', '') !~ '^\d{4}-\d{2}-\d{2}$' then
        d := d || jsonb_build_object('valid_till', case when isnew or (old.data ->> 'valid_till') is null then (public.crm_today() + 15)::text else old.data ->> 'valid_till' end); end if;
    end if;
    d := d || calc; amt := public.crm_num(calc -> 'grand'); ttl := coalesce(ex.title, ''); mob := ex.mobile;
    if isnew then ref_ := public.crm_next_no(k); else ref_ := old.ref; end if;
    st := coalesce(nullif(st, ''), case when isnew then case k when 'quote' then 'draft' when 'invoice' then 'due' else 'open' end else old.status end);
    if k = 'quote' and coalesce(d ->> 'send_on', '') ~ '^\d{4}-\d{2}-\d{2}$' then due := (d ->> 'send_on')::date; end if;
    if k = 'quote' then
      if st = 'expired' and (isnew or old.status <> 'expired') then raise exception 'Expired apne aap hota hai — Renew button use karein'; end if;
      if not isnew and old.status = 'expired' then raise exception 'Expired quotation ko pehle Renew karein'; end if;
      if st in ('draft', 'sent', 'accepted') and not public.crm_can(s, 'stock.override') then
        msg_ := public.crm_quote_shortage(d -> 'lines', case when isnew then null else id_ end);
        if msg_ is not null then raise exception 'Stock kam hai (20%% online ke liye surakshit): %', msg_; end if;
      end if;
    end if;
    if k = 'invoice' then
      due := coalesce(nullif(d ->> 'due_date', '')::date, due);
      if not isnew then d := d || jsonb_build_object('paid', old.data -> 'paid', 'balance', old.data -> 'balance'); end if;
    end if;
    if k = 'purchase' and not isnew and old.status = 'received' then raise exception 'Received purchase badla nahi ja sakta'; end if;
  elsif k = 'payment' then
    perform public.crm_need(s, 'payments.record');
    amt := public.crm_num(d -> 'amount'); if amt <= 0 then raise exception 'Amount likhein'; end if;
    if coalesce(d ->> 'invoice_id', '') <> '' then
      select * into ex from public.crm_records where id = (d ->> 'invoice_id')::bigint and kind = 'invoice';
      if not public.crm_vis(s, ex) then raise exception 'Bill nahi mila'; end if;
      pid := ex.party_id;
    end if;
    if pid is null then raise exception 'Customer chunein'; end if;
    select * into f from public.crm_records where id = pid and kind = 'party';
    if not public.crm_vis(s, f) then raise exception 'Customer nahi mila'; end if;
    ttl := f.title; mob := f.mobile; ref_ := case when isnew then public.crm_next_no('payment') else old.ref end; st := 'ok';
    due := coalesce(nullif(d ->> 'date', '')::date, public.crm_today());
  elsif k = 'lead' then
    perform public.crm_need(s, 'leads.create');
    if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein (mobile zaroori hai)'; end if;
    if em <> '' and em !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'Sahi email likhein (ya khali chhodein)'; end if;
    if ttl = '' then ttl := 'Lead ' || mob; end if;
    if (p ? 'assigned_to') and asg is distinct from (case when isnew then null else old.assigned_to end) and asg is distinct from (s).uid then perform public.crm_need(s, 'leads.assign'); end if;
    if isnew and exists (select 1 from public.crm_records where kind = 'lead' and deleted_at is null and status not in ('won', 'lost') and mobile = mob and (owner_id = (s).uid or assigned_to = coalesce(asg, (s).uid))) then
      raise exception 'Ye lead pehle se aapki list me hai'; end if;
    st := coalesce(nullif(st, ''), case when isnew then 'new' else old.status end);
    if st not in ('new', 'contacted', 'visit', 'quote', 'won', 'lost') then st := 'new'; end if;
    if d ? 'followup' then due := nullif(d ->> 'followup', '')::date; end if;
  elsif k = 'reminder' then
    if ttl = '' then ttl := coalesce(nullif(d ->> 'type', ''), 'Reminder'); end if;
    if asg is null and isnew then asg := (s).uid; end if;
    if asg is distinct from (s).uid and (isnew or asg is distinct from old.assigned_to) then perform public.crm_need(s, 'reminders.assign'); end if;
    if not isnew and old.owner_id <> (s).uid and coalesce(old.assigned_to, -1) <> (s).uid and not public.crm_can(s, 'reminders.assign') then raise exception 'Ye reminder aapka nahi hai'; end if;
    if due is null then raise exception 'Tareekh chunein'; end if;
    st := coalesce(nullif(st, ''), case when isnew then 'open' else old.status end);
    if st = 'done' and (isnew or old.status <> 'done') then d := d || jsonb_build_object('done_at', now()); end if;
    if st = 'open' then d := d - 'done_at'; end if;
    mob := nullif(mob, '');
  elsif k = 'plant' then
    perform public.crm_need(s, 'plants.create');
    if ttl = '' then raise exception 'Customer ka naam likhein'; end if;
    if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Customer ka sahi mobile number zaroori hai'; end if;
    if not isnew and old.status <> 'pending' and not public.crm_can(s, 'plants.verify') then raise exception 'Verified plant sirf Admin badal sakta hai'; end if;
    st := case when public.crm_can(s, 'plants.verify') then coalesce(nullif(st, ''), case when isnew then 'verified' else old.status end) else 'pending' end;
    if st not in ('pending', 'verified', 'rejected') then st := 'pending'; end if;
    d := d || jsonb_build_object('ref', upper(coalesce(d ->> 'ref', case when (s).ref is not null and isnew then (s).ref else '' end)));
    amt := public.crm_num(d -> 'deal_value');
    if pid is null and mob <> '' then select id into pid from public.crm_records where kind = 'party' and mobile = mob and deleted_at is null limit 1; end if;
    if isnew then ref_ := public.crm_next_no('plant'); else ref_ := old.ref; end if;
    due := nullif(d ->> 'install', '')::date;
  elsif k = 'earning' then
    perform public.crm_need(s, 'earnings.manage');
    amt := public.crm_num(d -> 'amount'); if amt <= 0 and not isnew then amt := old.amount; end if; if amt <= 0 then raise exception 'Amount likhein'; end if;
    if isnew then owner_ := nullif(p ->> 'owner_id', '')::bigint; if owner_ is null or not exists (select 1 from public.crm_users where id = owner_) then raise exception 'User chunein'; end if; end if;
    st := coalesce(nullif(st, ''), case when isnew then 'due' else old.status end);
    if st not in ('due', 'paid') then st := 'due'; end if;
    if st = 'paid' and (isnew or old.status <> 'paid') then d := d || jsonb_build_object('paid_on', public.crm_today()); end if;
    if ttl = '' then ttl := 'Commission'; end if;
    due := coalesce(nullif(d ->> 'pay_on', '')::date, due);
  elsif k = 'folder' then
    perform public.crm_need(s, 'docs.folders');
    if ttl = '' then raise exception 'Folder ka naam likhein'; end if;
    if coalesce(d ->> 'parent_id', '') <> '' and not public.crm_folder_ok(s, (d ->> 'parent_id')::bigint) then raise exception 'Folder nahi mila'; end if;
    if not isnew and (d ->> 'parent_id') = id_::text then raise exception 'Folder khud ke andar nahi ja sakta'; end if;
    mob := null;
  elsif k = 'doc' then
    if isnew then raise exception 'Document upload button se jodein'; end if;
    if old.owner_id <> (s).uid and not public.crm_can(s, 'docs.folders') then raise exception 'Ye document aapka nahi hai'; end if;
    d := old.data || (d - 'file_id' - 'size' - 'mime');
    if coalesce(d ->> 'folder_id', '') <> '' and not public.crm_folder_ok(s, (d ->> 'folder_id')::bigint) then raise exception 'Folder nahi mila'; end if;
    ttl := coalesce(nullif(ttl, ''), old.title); mob := null;
  elsif k = 'note' then
    if not isnew and old.owner_id <> (s).uid then raise exception 'Ye note aapka nahi hai'; end if;
    mob := null;
  elsif k = 'notice' then
    perform public.crm_need(s, 'settings.manage'); mob := null;
  end if;

  srch := lower(concat_ws(' ', ttl, ref_, mob, em, d ->> 'city', d ->> 'company', d ->> 'gstin', d ->> 'note', d ->> 'type', d ->> 'brand', d ->> 'qtitle', d ->> 'category', d ->> 'subcategory', d ->> 'sku', d ->> 'mpn', d ->> 'source'));
  if isnew then
    insert into public.crm_records(kind, ref, title, mobile, status, owner_id, assigned_to, party_id, amount, due_at, data, search, created_by)
    values (k, ref_, ttl, nullif(mob, ''), st, coalesce(owner_, 0), asg, pid, coalesce(amt, 0), due, d, srch, (s).uid) returning * into r;
  else
    update public.crm_records set ref = coalesce(ref_, ref), title = ttl, mobile = nullif(mob, ''), status = st, assigned_to = asg, party_id = pid,
      amount = coalesce(amt, 0), due_at = due, data = d, search = srch, updated_at = now() where id = id_ returning * into r;
  end if;

  -- ---------------- side effects
  if k = 'payment' and coalesce(d ->> 'invoice_id', '') <> '' then perform public.crm_inv_recalc((d ->> 'invoice_id')::bigint); end if;
  if k = 'payment' and not isnew and coalesce(old.data ->> 'invoice_id', '') <> '' and old.data ->> 'invoice_id' <> coalesce(d ->> 'invoice_id', '') then perform public.crm_inv_recalc((old.data ->> 'invoice_id')::bigint); end if;
  if k = 'invoice' then perform public.crm_inv_recalc(r.id); select * into r from public.crm_records where id = r.id; end if;
  if k = 'plant' and (isnew or prev_status is distinct from r.status) then perform public.crm_commission(r.id, s); end if;
  if k = 'purchase' and r.status = 'received' and (isnew or prev_status <> 'received') then perform public.crm_stock(r.data, 1); end if;

  perform public.crm_log(s, case when isnew then 'create' else 'edit' end, k, r.id,
    case k when 'party' then 'Customer: ' when 'item' then 'Item: ' when 'quote' then 'Quotation ' || coalesce(r.ref, '') || ': ' when 'invoice' then 'Bill ' || coalesce(r.ref, '') || ': '
      when 'payment' then 'Payment ₹' || r.amount || ': ' when 'lead' then 'Lead: ' when 'reminder' then 'Reminder: ' when 'plant' then 'Plant: ' when 'earning' then 'Commission ₹' || r.amount || ': '
      when 'folder' then 'Folder: ' when 'doc' then 'Document: ' else '' end || r.title || case when r.status <> '' then ' [' || r.status || ']' else '' end);
  return public.crm_row(s, r);
end $function$

;