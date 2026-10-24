-- ============================================================================
-- ROUND 34 — Maintenance & AMC: visit cycle (one-time / quarterly / half-yearly / yearly / 5 years) and visit time
-- ============================================================================
create or replace function public.crm_maint_contract(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); ex public.crm_records; pl public.crm_records; months int; yrs int; total int; i int;
        cid text := 'MC-' || encode(gen_random_bytes(4), 'hex'); start_ date; checks jsonb := '[]'::jsonb; pname text; cost numeric := 0; asg bigint := coalesce(nullif(p ->> 'assigned_to', '')::bigint, (s).uid); c jsonb; ck public.crm_records; cyc text := lower(coalesce(nullif(p ->> 'cycle', ''), '')); vt text := left(coalesce(p ->> 'time', ''), 5);
begin
  if not (public.crm_can(s, 'customers.create') or public.crm_can(s, 'customers.edit') or public.crm_can(s, 'items.view') or public.crm_is_admin(s)) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  select * into ex from public.crm_records where id = (p ->> 'party_id')::bigint and kind = 'party';
  if not public.crm_vis(s, ex) then raise exception 'Customer nahi mila'; end if;
  begin start_ := (p ->> 'start')::date; exception when others then raise exception 'Sahi tareekh chunein'; end;
  if start_ is null then raise exception 'Pehli visit ki tareekh chunein'; end if;
  select * into pl from public.crm_records where id = nullif(p ->> 'plan_id', '')::bigint and kind = 'item' and deleted_at is null and data ->> 'type' = 'maintenance';
  if pl.id is null then raise exception 'Plan chunein (Maintenance & Audit Packages me plan banayein)'; end if;
  pname := pl.title; months := public.crm_months_of(coalesce(nullif(cyc, ''), pl.data ->> 'period'));
  if cyc = 'one' then months := 0; elsif cyc = 'five' then months := 60; elsif cyc = 'monthly' then months := 1; end if;
  if vt <> '' and vt !~ '^[0-2][0-9]:[0-5][0-9]$' then raise exception 'Sahi time chunein'; end if;
  yrs := least(greatest(coalesce(nullif(pl.data ->> 'years', '')::int, 1), 1), 10);
  total := case when months = 0 then 1 else least(greatest(ceil(12.0 / months * yrs)::int, 1), 120) end;
  for c in select * from jsonb_array_elements(coalesce(pl.data -> 'checklist', '[]'::jsonb)) loop
    select * into ck from public.crm_records where id = nullif(c #>> '{}', '')::bigint and kind = 'item' and deleted_at is null and data ->> 'type' = 'mcheck';
    if ck.id is not null then
      checks := checks || jsonb_build_array(jsonb_build_object('id', ck.id, 'name', ck.title, 'cost', public.crm_num(ck.data -> 'cost'),
        'mat_id', nullif(ck.data ->> 'material_item_id', ''), 'mat_qty', public.crm_num(ck.data -> 'material_qty')));
      cost := cost + public.crm_num(ck.data -> 'cost');
    end if;
  end loop;
  for i in 0 .. total - 1 loop
    insert into public.crm_records(kind, title, status, owner_id, assigned_to, party_id, mobile, due_at, data, search, created_by)
    values ('reminder', 'Solar service — ' || ex.title, 'open', (s).uid, asg, ex.id, ex.mobile, (start_ + make_interval(months => i * months))::date,
      jsonb_build_object('type', 'amc', 'maint', true, 'contract_id', cid, 'plan_id', pl.id, 'plan_name', pname, 'free', coalesce((pl.data ->> 'free')::boolean, false), 'months', months, 'cycle', coalesce(nullif(cyc, ''), pl.data ->> 'period'), 'visit_time', vt,
        'visit_no', i + 1, 'visits_total', total, 'checks', checks, 'visit_cost', cost, 'mobile', coalesce(ex.mobile, ''), 'party_name', ex.title, 'title', 'Solar service — ' || ex.title),
      lower('solar service ' || ex.title || ' ' || pname), (s).uid);
  end loop;
  perform public.crm_log(s, 'create', 'maintenance', ex.id, 'Maintenance & Audit: ' || pname || ' → ' || ex.title || ' (' || total || ' visits)');
  return jsonb_build_object('ok', true, 'contract_id', cid, 'visits', total, 'first_due', start_);
end $$;

-- ============================================================================
-- ROUND 34 — single-service jobs: 'AMC only' and 'Site visit only' customer types (Lead / Customer / Conversation filled, then straight to that step)
-- ============================================================================
create or replace function public.crm_ctypes() returns text[] language sql immutable as $$ select array['Residential','Commercial','Industrial','VFD','Items only','Service','AMC only','Site visit only'] $$;

create or replace function public.crm_wf_flow(ct text) returns int[] language sql immutable as $$
  select case
    when ct = 'Items only'  then array[19,1,2,14,3,12,16,18]                               -- Product customer
    when ct = 'Service'     then array[19,1,2,3,4,12,17,16,18]                             -- Service customer (cleaning, AMC, repair, shifting, audit)
    when ct = 'AMC only'        then array[19,1,2,17]                                      -- only a Maintenance / AMC plan: Lead, Customer, Conversation filled, then AMC
    when ct = 'Site visit only' then array[19,1,2,4]                                       -- only a Site Visit: Lead, Customer, Conversation filled, then Site Visit
    when ct = 'Residential' then array[19,1,2,14,3,4,5,7,15,8,9,10,11,12,13,16,17,18]      -- Project, subsidy applies
    else                         array[19,1,2,14,3,4,5,7,15,8,9,10,11,12,16,17,18] end $$;

create or replace function public.crm_rules_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare pt public.crm_records; ex public.crm_records; miss text[] := '{}'; nm text; d jsonb; bypass boolean := coalesce(current_setting('sp.wf', true), '') = '1'; ct text;
        seg text; ck text; gs text;
begin
  if new.deleted_at is not null then return new; end if;
  d := coalesce(new.data, '{}'::jsonb);

  if new.kind = 'lead' then
    nm := trim(coalesce(d ->> 'name', new.title, ''));
    if TG_OP = 'INSERT' or new.mobile is distinct from old.mobile then
      if coalesce(new.mobile, '') !~ '^[6-9][0-9]{9}$' then raise exception 'Lead ke liye sahi 10 ank ka mobile zaroori hai (sirf email se lead nahi banti)'; end if;
    end if;
    -- every lead carries its path (where it came from); forms / ads / store fill it themselves, a manual lead without one is "Manual entry"
    if coalesce(trim(d ->> 'source'), '') = '' then d := d || jsonb_build_object('source', 'Manual entry'); new.data := d; end if;
    -- forms / signups / ads (inbound): name AND mobile are mandatory.  Manual add / Excel / contacts import: mobile alone is enough.
    if coalesce(d ->> 'intake', '') = 'inbound' and (nm = '' or nm ~* '^lead [0-9]') then raise exception 'Form / signup / ad se aayi lead me naam aur mobile dono zaroori hain'; end if;
    return new;
  end if;

  -- Customer: kind (project / product / service), segment (b2c / b2b), GSTIN shape, B2B needs a firm name.
  if new.kind = 'party' then
    seg := coalesce(d ->> 'segment', ''); ck := coalesce(d ->> 'cust_kind', ''); gs := upper(trim(coalesce(d ->> 'gstin', '')));
    if seg <> '' and seg not in ('b2c', 'b2b') then raise exception 'Customer ka segment galat hai (B2C ya B2B)'; end if;
    if ck <> '' and ck not in ('project', 'product', 'service') then raise exception 'Customer ka prakar galat hai (Project, Product ya Service)'; end if;
    if gs <> '' and (TG_OP = 'INSERT' or gs is distinct from upper(trim(coalesce(old.data ->> 'gstin', '')))) and gs !~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$' then
      raise exception 'GSTIN sahi nahi hai (15 akshar, jaise 09ABCDE1234F1Z5)'; end if;
    if seg = 'b2b' and coalesce(trim(d ->> 'company'), '') = '' and (TG_OP = 'INSERT' or coalesce(old.data ->> 'segment', '') <> 'b2b' or coalesce(trim(old.data ->> 'company'), '') <> '') then
      raise exception 'B2B customer ka Company / Firm ka naam likhein'; end if;
    -- a customer never moves down:  project  >  service  >  product
    if TG_OP = 'UPDATE' and coalesce(old.data ->> 'cust_kind', '') <> '' and
       (case ck when 'project' then 3 when 'service' then 2 when 'product' then 1 else 0 end) < (case old.data ->> 'cust_kind' when 'project' then 3 when 'service' then 2 when 'product' then 1 else 0 end) then
      d := d || jsonb_build_object('cust_kind', old.data ->> 'cust_kind'); new.data := d; ck := old.data ->> 'cust_kind'; end if;
    -- a NEW customer must carry everything the flow needs (path, address, kind and what he buys), so the flow never breaks later
    if TG_OP = 'INSERT' and coalesce(d ->> 'type', 'customer') <> 'supplier' then
      if coalesce(trim(d ->> 'source'), '') = '' then miss := miss || 'Path (kahan se aaya)'::text; end if;
      if coalesce(trim(d ->> 'address'), '') = '' then miss := miss || 'Pata'::text; end if;
      if coalesce(trim(d ->> 'city'), '') = '' then miss := miss || 'Shahar'::text; end if;
      if coalesce(d ->> 'pincode', '') !~ '^[0-9]{6}$' then miss := miss || 'Pincode (6 ank)'::text; end if;
      if seg = '' then miss := miss || 'B2C / B2B'::text; end if;
      if ck = '' then miss := miss || 'Kya kharidega (Project / Product / Service)'::text;
      elsif ck = 'project' then
        if coalesce(d ->> 'project_type', '') not in ('Residential', 'Commercial', 'Industrial', 'VFD') then miss := miss || 'Project type (Residential / Commercial / Industrial / VFD)'::text; end if;
        if public.crm_num(d -> 'kw') <= 0 then miss := miss || 'Kitne kW chahiye'::text; end if;
      elsif ck = 'product' then
        if coalesce(trim(d ->> 'interest'), '') = '' then miss := miss || 'Kaunsa product / kitna'::text; end if;
      elsif ck = 'service' then
        if coalesce(trim(d ->> 'service_type'), '') = '' then miss := miss || 'Kaunsi service chahiye'::text; end if;
      end if;
      if array_length(miss, 1) > 0 then raise exception 'Customer add karne se pehle ye bharna zaroori hai: %', array_to_string(miss, ', '); end if;
    end if;
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
      if coalesce(pt.data ->> 'segment', '') = 'b2b' and coalesce(trim(pt.data ->> 'company'), '') = '' then miss := miss || 'Company / Firm ka naam (B2B)'::text; end if;
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
    -- a project quotation makes the customer a project customer for life (stays even if the quotation is later rejected)
    if ct in ('Residential', 'Commercial', 'Industrial', 'VFD') and new.party_id is not null then
      update public.crm_records set data = data || jsonb_build_object('cust_kind', 'project'), updated_at = now()
        where id = new.party_id and kind = 'party' and coalesce(data ->> 'cust_kind', '') <> 'project';
    elsif ct in ('Service', 'AMC only', 'Site visit only') and new.party_id is not null then
      update public.crm_records set data = data || jsonb_build_object('cust_kind', 'service'), updated_at = now()
        where id = new.party_id and kind = 'party' and coalesce(data ->> 'cust_kind', '') in ('', 'product');
    end if;
    return new;
  end if;

  -- automatic steps: a finished Site Visit ticks "Site Visit"; an AMC / maintenance plan ticks "AMC / Maintenance"
  if new.kind = 'reminder' and new.party_id is not null then
    if d ->> 'type' = 'sitevisit' and d ->> 'visit_status' = 'done' then perform public.crm_wf_auto_p(new.party_id, 4, 'Site Visit (system)'); end if;
    if d ->> 'maint' = 'true' then perform public.crm_wf_auto_p(new.party_id, 17, 'Maintenance plan (system)'); end if;
    return new;
  end if;

  -- a document shared with the customer's plant ticks "Send Demo / Files"
  if new.kind = 'doc' and TG_OP = 'INSERT' and coalesce(d ->> 'shared_quote', '') ~ '^[0-9]+$' then
    perform public.crm_wf_auto_q((d ->> 'shared_quote')::bigint, 14, 'File bheji (system)');
  end if;
  return new;
end $$;

create or replace function public.crm_wf_get(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; pt public.crm_records; qid bigint := nullif(p ->> 'id', '')::bigint; pid bigint := nullif(p ->> 'party_id', '')::bigint; plants jsonb; fk text;
begin
  if qid is null and pid is not null then
    select * into pt from public.crm_records where id = pid and kind = 'party';
    if pt.id is null or not public.crm_vis(s, pt) then raise exception 'Customer nahi mila'; end if;
    select * into q from public.crm_records where kind = 'quote' and deleted_at is null and party_id = pid order by id desc limit 1;
    select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'ref', x.ref, 'title', coalesce(x.data ->> 'qtitle', x.title), 'ctype', x.data ->> 'ctype', 'status', x.status) order by x.id desc), '[]'::jsonb) into plants
      from public.crm_records x where x.kind = 'quote' and x.deleted_at is null and x.party_id = pid;
    if q.id is null then
      -- no quotation yet: show the flow of the customer's kind with Leads / Add Customer / Conversation done
      q.party_id := pid;
      q.data := jsonb_build_object('ctype', case coalesce(pt.data ->> 'cust_kind', '') when 'product' then 'Items only' when 'service' then 'Service' else '' end,
        'wf', jsonb_build_object('1', jsonb_build_object('at', to_char(pt.created_at at time zone 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS"+05:30"'), 'auto', true),
                                 '2', jsonb_build_object('at', to_char(pt.created_at at time zone 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS"+05:30"'), 'auto', true)));
      return jsonb_build_object('party_id', pid, 'quote_id', null, 'plants', '[]'::jsonb, 'project', false, 'kind', case coalesce(pt.data ->> 'cust_kind', '') when 'product' then 'product' when 'service' then 'service' else 'project' end, 'steps', public.crm_wf_steps(s, q));
    end if;
  else
    select * into q from public.crm_records where id = qid and kind = 'quote' and deleted_at is null;
    if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
    plants := '[]'::jsonb;
  end if;
  if not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  fk := case coalesce(q.data ->> 'ctype', '') when 'Items only' then 'product' when 'Service' then 'service' when 'AMC only' then 'service' when 'Site visit only' then 'service' else 'project' end;
  return jsonb_build_object('party_id', q.party_id, 'quote_id', q.id, 'ref', q.ref, 'title', coalesce(q.data ->> 'qtitle', q.title), 'ctype', q.data ->> 'ctype', 'status', q.status, 'plants', plants,
    'project', (q.data -> 'wf') ? '7', 'kind', fk, 'bill_state', q.data ->> 'bill_state', 'steps', public.crm_wf_steps(s, q));
end $$;

create or replace function public.crm_wf_set(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; n int := (p ->> 'step')::int; done boolean := coalesce((p ->> 'done')::boolean, true); note text := left(trim(coalesce(p ->> 'note', '')), 500);
        skip boolean := coalesce((p ->> 'skip')::boolean, false); w jsonb; flow int[]; ct text; inf jsonb := '{}'::jsonb; f jsonb; v text; miss text[] := '{}'; entry jsonb; has_info boolean := p ? 'info';
begin
  select * into q from public.crm_records where id = (p ->> 'id')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if n is null or n < 1 or n > 19 then raise exception 'Step galat hai'; end if;
  if public.crm_wf_is_auto(n) then raise exception 'Ye step apne aap hota hai (quotation / bill / lead se)'; end if;
  ct := coalesce(q.data ->> 'ctype', ''); flow := public.crm_wf_flow_of(q);
  if not (n = any (flow)) then
    if n = 13 then raise exception 'Subsidy sirf Residential solar ke liye hai'; end if;
    raise exception 'Ye step is customer ke liye nahi hai (% — %)', case ct when 'Items only' then 'Product customer' when 'Service' then 'Service customer' when 'AMC only' then 'AMC customer' when 'Site visit only' then 'Site visit customer' else 'Project customer' end, (public.crm_wf_names())[n];
  end if;
  if n = 13 and not (public.crm_is_admin(s) or (s).role = 'manager') then raise exception 'Subsidy sirf Admin ya Manager green kar sakte hain'; end if;
  if not public.crm_wf_can(s, n, 'edit') then raise exception 'Is step ko badalne ki permission nahi hai — Admin se allow karwayein'; end if;
  w := coalesce(q.data -> 'wf', '{}'::jsonb);
  if done then
    if n = 7 and not (w ? '6') then raise exception 'Pehle quotation Confirm hona chahiye'; end if;
    if (n in (8, 9, 10, 11, 13) or (n = 17 and ct not in ('Service', 'AMC only'))) and not (w ? '7') then raise exception 'Pehle Apply Process confirm karein — tabhi customer Projects me aata hai'; end if;
    if (n in (15, 16, 18) or (n = 17 and ct = 'Service')) and not (w ? '6') then raise exception 'Pehle quotation Confirm hona chahiye'; end if;
    if skip and not public.crm_wf_can_skip(n) then raise exception 'Ye step "Lagu nahi" nahi kiya ja sakta'; end if;
    if skip then
      entry := jsonb_build_object('at', public.crm_iso_now(), 'by', (s).name, 'by_id', (s).uid, 'note', note, 'skip', true);
    else
      -- keep only the fields this step defines; mandatory ones must be filled (only when the new screen sends "info")
      for f in select * from jsonb_array_elements(coalesce(public.crm_wf_fields() -> n::text, '[]'::jsonb)) loop
        v := left(trim(coalesce(p -> 'info' ->> (f ->> 'k'), '')), 200);
        if v <> '' then inf := inf || jsonb_build_object(f ->> 'k', v);
        elsif has_info and coalesce((f ->> 'req')::boolean, false) then miss := miss || (f ->> 'l'); end if;
      end loop;
      if array_length(miss, 1) > 0 then raise exception 'Ye details bharna zaroori hai: %', array_to_string(miss, ', '); end if;
      entry := jsonb_build_object('at', public.crm_iso_now(), 'by', (s).name, 'by_id', (s).uid, 'note', note) || case when inf = '{}'::jsonb then '{}'::jsonb else jsonb_build_object('info', inf) end;
    end if;
    w := w || jsonb_build_object(n::text, entry);
  else
    if not public.crm_is_admin(s) then raise exception 'Step wapas sirf Admin kar sakta hai'; end if;
    w := w - n::text;
  end if;
  perform set_config('sp.wf', '1', true);
  update public.crm_records set data = data || jsonb_build_object('wf', w), updated_at = now() where id = q.id;
  perform set_config('sp.wf', '', true);
  perform public.crm_log(s, 'workflow', 'quote', q.id, coalesce(q.ref, '') || ' — ' || (public.crm_wf_names())[n] || case when not done then ' ↩' when skip then ' (lagu nahi)' else ' ✔' end);
  select * into q from public.crm_records where id = q.id;
  return public.crm_wf_get(jsonb_build_object('token', p ->> 'token', 'id', q.id));
end $$;

-- ============================================================================
-- ROUND 34 — Naya Kaam for AMC-only / Site-visit-only (no inventory item needed)
-- ============================================================================
-- Naya Kaam for a customer who only wants one service: creates a light job record (no inventory items needed)
create or replace function public.crm_job_new(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); ex public.crm_records; ct text := coalesce(p ->> 'ctype', ''); nm text; r public.crm_records;
begin
  if ct not in ('AMC only', 'Site visit only') then raise exception 'Kaam ka prakar galat hai'; end if;
  if not (public.crm_can(s, 'customers.edit') or public.crm_can(s, 'customers.create') or public.crm_can(s, 'quotes.create') or public.crm_is_admin(s)) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  select * into ex from public.crm_records where id = (p ->> 'party_id')::bigint and kind = 'party' and deleted_at is null;
  if ex.id is null or not public.crm_vis(s, ex) then raise exception 'Customer nahi mila'; end if;
  nm := case ct when 'AMC only' then 'AMC' else 'Site Visit' end;
  insert into public.crm_records(kind, ref, title, status, owner_id, assigned_to, party_id, mobile, data, search, created_by)
  values ('quote', public.crm_next_no('quote'), ex.title, 'accepted', (s).uid, (s).uid, ex.id, ex.mobile,
          jsonb_build_object('ctype', ct, 'qtitle', nm || ' — ' || ex.title, 'lines', '[]'::jsonb, 'discount', 0, 'date', to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM-DD'), 'job_only', true,
                             'party', jsonb_build_object('name', ex.title, 'mobile', coalesce(ex.mobile, ''))),
          lower(nm || ' ' || ex.title), (s).uid)
  returning * into r;
  perform public.crm_log(s, 'create', 'quote', r.id, 'Naya kaam: ' || nm || ' → ' || ex.title);
  return jsonb_build_object('ok', true, 'id', r.id, 'ref', r.ref);
end $$;
do $g$ begin
  execute 'revoke all on function public.crm_job_new(jsonb) from public';
  execute 'grant execute on function public.crm_job_new(jsonb) to anon, authenticated';
exception when undefined_object then null; end $g$;

-- ============================================================================
-- ROUND 34b — 5 FIXED Maintenance & AMC plans (Random, Recommended, Valuable, Tension Free, Best Value): only Admin can change price + what is included; cycle / duration are locked.
-- ============================================================================
create or replace function public.crm_save(p jsonb)
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
    if isnew and exists (select 1 from public.crm_records where kind = 'lead' and deleted_at is null and mobile = mob and (owner_id = (s).uid or assigned_to = coalesce(asg, (s).uid))) then
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

create or replace function public.crm_maint_contract(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); ex public.crm_records; pl public.crm_records; months int; yrs int; total int; i int;
        cid text := 'MC-' || encode(gen_random_bytes(4), 'hex'); start_ date; checks jsonb := '[]'::jsonb; pname text; cost numeric := 0; asg bigint := coalesce(nullif(p ->> 'assigned_to', '')::bigint, (s).uid); c jsonb; ck public.crm_records; cyc text := ''; vt text := left(coalesce(p ->> 'time', ''), 5);
begin
  if not (public.crm_can(s, 'customers.create') or public.crm_can(s, 'customers.edit') or public.crm_can(s, 'items.view') or public.crm_is_admin(s)) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  select * into ex from public.crm_records where id = (p ->> 'party_id')::bigint and kind = 'party';
  if not public.crm_vis(s, ex) then raise exception 'Customer nahi mila'; end if;
  begin start_ := (p ->> 'start')::date; exception when others then raise exception 'Sahi tareekh chunein'; end;
  if start_ is null then raise exception 'Pehli visit ki tareekh chunein'; end if;
  select * into pl from public.crm_records where id = nullif(p ->> 'plan_id', '')::bigint and kind = 'item' and deleted_at is null and data ->> 'type' = 'maintenance';
  if pl.id is null then raise exception 'Plan chunein (Maintenance & Audit Packages me plan banayein)'; end if;
  cyc := lower(coalesce(nullif(p ->> 'cycle', ''), pl.data ->> 'period', ''));
  pname := pl.title; months := public.crm_months_of(coalesce(nullif(cyc, ''), pl.data ->> 'period'));
  if cyc = 'one' then months := 0; elsif cyc = 'five' then months := 60; elsif cyc = 'monthly' then months := 1; end if;
  if vt <> '' and vt !~ '^[0-2][0-9]:[0-5][0-9]$' then raise exception 'Sahi time chunein'; end if;
  yrs := least(greatest(coalesce(nullif(pl.data ->> 'years', '')::int, 1), 1), 10);
  total := case when months = 0 then 1 else least(greatest(ceil(12.0 / months * yrs)::int, 1), 120) end;
  for c in select * from jsonb_array_elements(coalesce(pl.data -> 'checklist', '[]'::jsonb)) loop
    select * into ck from public.crm_records where id = nullif(c #>> '{}', '')::bigint and kind = 'item' and deleted_at is null and data ->> 'type' = 'mcheck';
    if ck.id is not null then
      checks := checks || jsonb_build_array(jsonb_build_object('id', ck.id, 'name', ck.title, 'cost', public.crm_num(ck.data -> 'cost'),
        'mat_id', nullif(ck.data ->> 'material_item_id', ''), 'mat_qty', public.crm_num(ck.data -> 'material_qty')));
      cost := cost + public.crm_num(ck.data -> 'cost');
    end if;
  end loop;
  for i in 0 .. total - 1 loop
    insert into public.crm_records(kind, title, status, owner_id, assigned_to, party_id, mobile, due_at, data, search, created_by)
    values ('reminder', 'Solar service — ' || ex.title, 'open', (s).uid, asg, ex.id, ex.mobile, (start_ + make_interval(months => i * months))::date,
      jsonb_build_object('type', 'amc', 'maint', true, 'contract_id', cid, 'plan_id', pl.id, 'plan_name', pname, 'free', coalesce((pl.data ->> 'free')::boolean, false), 'months', months, 'cycle', coalesce(nullif(cyc, ''), pl.data ->> 'period'), 'visit_time', vt, 'plan_code', coalesce(pl.data ->> 'plan_code', ''), 'plan_price', public.crm_num(pl.data -> 'price'), 'plan_gst', public.crm_num(pl.data -> 'gst'), 'prev_contract', coalesce(p ->> 'prev_contract', ''),
        'visit_no', i + 1, 'visits_total', total, 'checks', checks, 'visit_cost', cost, 'mobile', coalesce(ex.mobile, ''), 'party_name', ex.title, 'title', 'Solar service — ' || ex.title),
      lower('solar service ' || ex.title || ' ' || pname), (s).uid);
  end loop;
  perform public.crm_log(s, 'create', 'maintenance', ex.id, 'Maintenance & Audit: ' || pname || ' → ' || ex.title || ' (' || total || ' visits)');
  return jsonb_build_object('ok', true, 'contract_id', cid, 'visits', total, 'first_due', start_);
end $$;

-- structure of a fixed plan can never change (not even by Admin); it cannot be deleted
create or replace function public.crm_plan_lock() returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('sp.restoring', true), '') = 'on' then return new; end if;
  if old.kind = 'item' and old.data ->> 'fixed' = 'true' then
    if new.deleted_at is not null and old.deleted_at is null then raise exception 'Fixed plan hataya nahi ja sakta'; end if;
    new.title := old.title; new.kind := old.kind;
    new.data := new.data || jsonb_build_object('fixed', true, 'type', 'maintenance', 'plan_code', old.data -> 'plan_code', 'name', old.data -> 'name', 'period', old.data -> 'period', 'years', old.data -> 'years', 'visits', old.data -> 'visits', 'unit', old.data -> 'unit', 'category', old.data -> 'category');
  end if;
  return new;
end $$;
drop trigger if exists crm_plan_lock on public.crm_records;
create trigger crm_plan_lock before update on public.crm_records for each row when (old.kind = 'item') execute function public.crm_plan_lock();

-- the 5 fixed plans (old test plans are removed; nobody was assigned to them)
create or replace function public.crm_seed_plans() returns void language plpgsql security definer set search_path = public as $$
declare rec record; ids jsonb := '{}'::jsonb; c record; ck jsonb;
begin
  update public.crm_records set deleted_at = now(), delete_reason = 'Purane plan hataye — 5 Fixed plans aaye'
    where kind = 'item' and data ->> 'type' = 'maintenance' and coalesce(data ->> 'fixed', '') <> 'true' and deleted_at is null;
  for c in select id, title from public.crm_records where kind = 'item' and data ->> 'type' = 'mcheck' and deleted_at is null loop ids := ids || jsonb_build_object(c.title, c.id); end loop;
  for rec in select * from (values
    ('random',      'Random Plan',        'one',       1,  1, 1500, 'Solar panel cleaning|Visual & physical inspection|Inverter check (error log, display, firmware)|Generation report', 'Sirf ek baar ki service — agli due date nahi'),
    ('recommended', 'Recommended Plan',   'quarterly', 1,  4, 4800, 'Solar panel cleaning|Visual & physical inspection|Inverter check (error log, display, firmware)|Earthing resistance test|ACDB check & tightening|DCDB check & tightening|Cable & MC4 connector check|Generation report', 'Quarterly: saal me 4 services (har 3 mahine)'),
    ('valuable',    'Valuable Plan',      'yearly',    1,  1, 1600, 'Solar panel cleaning|Visual & physical inspection|Inverter check (error log, display, firmware)|Generation report', 'Yearly: saal me 1 service'),
    ('tension',     'Tension Free Plan',  'quarterly', 5, 20, 20000, 'Solar panel cleaning|Visual & physical inspection|Inverter check (error log, display, firmware)|Earthing resistance test|ACDB check & tightening|DCDB check & tightening|Cable & MC4 connector check|Shadow & structure check|Lightning arrestor check|Generation report', 'Quarterly: saal me 4, 5 saal me 20 services'),
    ('best',        'Best Value Plan',    'yearly',    5,  5, 7000, 'Solar panel cleaning|Visual & physical inspection|Inverter check (error log, display, firmware)|Earthing resistance test|ACDB check & tightening|DCDB check & tightening|Cable & MC4 connector check|Generation report', 'Yearly: 5 saal me 5 services')
  ) as t(code, nm, per, yrs, vis, price, names, descr) loop
    if exists (select 1 from public.crm_records where kind = 'item' and data ->> 'plan_code' = rec.code and deleted_at is null) then continue; end if;
    select coalesce(jsonb_agg(ids -> n), '[]'::jsonb) into ck from unnest(string_to_array(rec.names, '|')) n where ids ? n;
    insert into public.crm_records(kind, title, status, owner_id, amount, data, search)
    values ('item', rec.nm, 'active', 0, rec.price, jsonb_build_object('type', 'maintenance', 'fixed', true, 'plan_code', rec.code, 'name', rec.nm, 'title', '', 'category', 'Maintenance', 'price', rec.price, 'gst', 18, 'unit', 'Plan',
      'period', rec.per, 'years', rec.yrs, 'visits', rec.vis, 'free', false, 'checklist', ck, 'desc', rec.descr), lower(rec.nm));
  end loop;
end $$;
select public.crm_seed_plans();
do $g$ begin execute 'revoke all on function public.crm_seed_plans() from public, anon, authenticated'; exception when undefined_object then null; end $g$;

-- Change plan for a customer who already has one: open visits of the old plan are cancelled, the new plan is scheduled from the next due date (or today)
create or replace function public.crm_maint_change(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records; old_cid text := p ->> 'contract_id'; nxt date; res jsonb; pid bigint;
begin
  if not (public.crm_can(s, 'customers.edit') or public.crm_can(s, 'items.view') or public.crm_is_admin(s)) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  if coalesce(old_cid, '') = '' then raise exception 'Purana plan nahi mila'; end if;
  select * into r from public.crm_records where kind = 'reminder' and data ->> 'contract_id' = old_cid and deleted_at is null order by id limit 1;
  if r.id is null or not public.crm_vis(s, r) then raise exception 'Purana plan nahi mila'; end if;
  pid := r.party_id;
  select min(due_at) into nxt from public.crm_records where kind = 'reminder' and data ->> 'contract_id' = old_cid and deleted_at is null and status = 'open';
  update public.crm_records set deleted_at = now(), delete_reason = 'Plan badal diya', updated_at = now()
    where kind = 'reminder' and data ->> 'contract_id' = old_cid and deleted_at is null and status = 'open';
  res := public.crm_maint_contract(jsonb_build_object('token', p ->> 'token', 'party_id', pid, 'plan_id', p -> 'plan_id', 'assigned_to', p -> 'assigned_to',
           'start', coalesce(nullif(p ->> 'start', ''), greatest(coalesce(nxt, public.crm_today()), public.crm_today())::text), 'time', coalesce(p ->> 'time', ''), 'prev_contract', old_cid));
  return res || jsonb_build_object('changed_from', old_cid);
end $$;
do $g$ begin
  execute 'revoke all on function public.crm_maint_change(jsonb) from public';
  execute 'grant execute on function public.crm_maint_change(jsonb) to anon, authenticated';
exception when undefined_object then null; end $g$;


-- ============================================================================
-- ROUND 35 — one permanent Customer ID (SP-C-000123) per person + stage: Lead -> Pending Inquiry -> Customer (on first bill)
-- ============================================================================
create or replace function public.crm_cust_id_next() returns text language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into public.crm_counters(key, n) values ('custid', 1) on conflict (key) do update set n = public.crm_counters.n + 1 returning public.crm_counters.n into n;
  return 'SP-C-' || lpad(n::text, 6, '0');
end $$;

-- BEFORE INSERT: every lead / customer gets the ID (same mobile = same ID); a new customer starts as a Pending Inquiry
create or replace function public.crm_custid_ins() returns trigger language plpgsql security definer set search_path = public as $$
declare cid text; d jsonb := coalesce(new.data, '{}'::jsonb);
begin
  if new.kind = 'party' and coalesce(d ->> 'type', 'customer') = 'supplier' then return new; end if;
  cid := nullif(d ->> 'cust_id', '');
  if cid is null and coalesce(new.mobile, '') <> '' then
    select data ->> 'cust_id' into cid from public.crm_records where kind in ('party', 'lead') and mobile = new.mobile and coalesce(data ->> 'cust_id', '') <> '' and deleted_at is null and coalesce(data ->> 'type', 'customer') <> 'supplier' order by id limit 1;
  end if;
  if cid is null then cid := public.crm_cust_id_next(); end if;
  d := d || jsonb_build_object('cust_id', cid);
  if new.kind = 'party' and coalesce(d ->> 'stage', '') not in ('inquiry', 'customer') then d := d || jsonb_build_object('stage', 'inquiry'); end if;
  new.data := d;
  new.search := trim(coalesce(new.search, '') || ' ' || lower(cid));
  return new;
end $$;
drop trigger if exists crm_custid_ins on public.crm_records;
create trigger crm_custid_ins before insert on public.crm_records for each row when (new.kind in ('party', 'lead')) execute function public.crm_custid_ins();

-- BEFORE UPDATE: the ID never changes; the stage changes only through the bill (never from a form)
create or replace function public.crm_custid_upd() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(old.data ->> 'cust_id', '') <> '' then new.data := new.data || jsonb_build_object('cust_id', old.data ->> 'cust_id'); end if;
  if new.kind = 'party' and coalesce(current_setting('sp.stage_ok', true), '') <> '1' and coalesce(current_setting('sp.restoring', true), '') <> 'on' then
    if coalesce(old.data ->> 'stage', '') <> '' then new.data := new.data || jsonb_build_object('stage', old.data ->> 'stage'); end if;
  end if;
  return new;
end $$;
drop trigger if exists crm_custid_upd on public.crm_records;
create trigger crm_custid_upd before update on public.crm_records for each row when (old.kind in ('party', 'lead')) execute function public.crm_custid_upd();

-- first bill => the Pending Inquiry becomes a Customer (stays there for life)
create or replace function public.crm_stage_bill() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.party_id is null then return new; end if;
  perform set_config('sp.stage_ok', '1', true);
  update public.crm_records set data = data || jsonb_build_object('stage', 'customer', 'billed_at', public.crm_iso_now()), updated_at = now()
    where id = new.party_id and kind = 'party' and coalesce(data ->> 'stage', '') = 'inquiry';
  perform set_config('sp.stage_ok', '', true);
  return new;
end $$;
drop trigger if exists crm_stage_bill on public.crm_records;
create trigger crm_stage_bill after insert on public.crm_records for each row when (new.kind = 'invoice') execute function public.crm_stage_bill();

-- backfill: IDs for everyone already there (one ID per mobile), stage = Customer when a bill exists, else Pending Inquiry
do $b$
declare r record; cid text; m text;
begin
  perform set_config('sp.restoring', 'on', true);
  for r in select id, kind, mobile, data from public.crm_records
           where kind in ('party', 'lead') and coalesce(data ->> 'cust_id', '') = '' and coalesce(data ->> 'type', 'customer') <> 'supplier' order by id loop
    cid := null; m := coalesce(r.mobile, '');
    if m <> '' then select data ->> 'cust_id' into cid from public.crm_records where kind in ('party', 'lead') and mobile = m and coalesce(data ->> 'cust_id', '') <> '' and coalesce(data ->> 'type', 'customer') <> 'supplier' order by id limit 1; end if;
    if cid is null then cid := public.crm_cust_id_next(); end if;
    update public.crm_records set data = data || jsonb_build_object('cust_id', cid), search = trim(coalesce(search, '') || ' ' || lower(cid)) where id = r.id;
  end loop;
  update public.crm_records p set data = data || jsonb_build_object('stage', case when exists (select 1 from public.crm_records i where i.kind = 'invoice' and i.party_id = p.id) then 'customer' else 'inquiry' end)
    where p.kind = 'party' and coalesce(p.data ->> 'type', 'customer') <> 'supplier' and coalesce(p.data ->> 'stage', '') not in ('inquiry', 'customer');
end $b$;


-- Customer app / shop page: one profile by mobile login — Customer ID, projects (+warranty, AMC), products (+warranty), services (+status), pending quotations
create or replace function public.crm_consumer_profile(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); pt public.crm_records; q public.crm_records; inv public.crm_records; l jsonb; k text; card jsonb; wl jsonb;
        projects jsonb := '[]'::jsonb; services jsonb := '[]'::jsonb; inquiries jsonb := '[]'::jsonb; products jsonb := '[]'::jsonb; cid text; it public.crm_records; qk text;
begin
  select * into pt from public.crm_records where kind = 'party' and deleted_at is null and mobile = u.mobile and u.mobile ~ '^[6-9][0-9]{9}$' and coalesce(data ->> 'type', 'customer') <> 'supplier' order by id limit 1;
  if pt.id is null then
    select data ->> 'cust_id' into cid from public.crm_records where kind = 'lead' and deleted_at is null and mobile = u.mobile order by id limit 1;
    return jsonb_build_object('cust_id', cid, 'stage', 'lead', 'name', u.name, 'mobile', u.mobile, 'projects', projects, 'services', services, 'products', products, 'inquiries', inquiries);
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
    qk := null;
    select case when q2.data ->> 'ctype' = 'Items only' then 'product' else 'other' end into qk from public.crm_records q2 where q2.id = nullif(inv.data ->> 'quote_id', '')::bigint;
    if qk = 'other' then continue; end if;
    for l in select * from jsonb_array_elements(coalesce(inv.data -> 'lines', '[]'::jsonb)) loop
      select * into it from public.crm_records where id = nullif(l ->> 'item_id', '')::bigint and kind = 'item';
      products := products || jsonb_build_array(jsonb_build_object('name', coalesce(l ->> 'name', it.title), 'qty', l -> 'qty', 'bill', inv.ref, 'date', inv.data ->> 'date', 'brand', it.data ->> 'brand', 'warranty', nullif(it.data ->> 'warranty', ''), 'paid', coalesce((inv.data ->> 'balance')::numeric, inv.amount) <= 0.009));
    end loop;
  end loop;
  return jsonb_build_object('cust_id', pt.data ->> 'cust_id', 'stage', coalesce(pt.data ->> 'stage', 'customer'), 'name', pt.title, 'mobile', pt.mobile,
    'projects', projects, 'services', services, 'products', products, 'inquiries', inquiries);
end $$;
grant execute on function public.crm_consumer_profile(jsonb) to anon, authenticated;


-- ============================================================================
-- ROUND 36 — Bills are non-refundable; a bill can be cancelled ("Cancelled – non refundable"); only Admin can allow a refund exception
-- ============================================================================
create or replace function public.crm_bill_cancel(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records; act text := coalesce(p ->> 'action', 'cancel'); why text := left(trim(coalesce(p ->> 'reason', '')), 300);
begin
  select * into r from public.crm_records where id = (p ->> 'id')::bigint and kind = 'invoice' and deleted_at is null;
  if r.id is null or not public.crm_vis(s, r) then raise exception 'Bill nahi mila'; end if;
  perform set_config('sp.restoring', 'on', true);   -- only a flag is changed here: skip the item-line guard of old bills
  if act = 'refund_ok' or act = 'refund_no' then
    if not public.crm_is_admin(s) then raise exception 'Refund ka exception sirf Admin laga sakta hai'; end if;
    update public.crm_records set data = data || jsonb_build_object('refund_ok', act = 'refund_ok', 'refund_note', why), updated_at = now() where id = r.id;
    perform public.crm_log(s, 'update', 'invoice', r.id, case when act = 'refund_ok' then 'Refund exception allowed: ' else 'Refund exception removed: ' end || r.ref);
    return jsonb_build_object('ok', true);
  end if;
  if not (public.crm_can(s, 'invoices.delete') or public.crm_can(s, 'invoices.edit') or public.crm_is_admin(s)) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  if length(why) < 3 then raise exception 'Cancel ka reason likhein'; end if;
  if act = 'restore' then
    if not public.crm_is_admin(s) then raise exception 'Bill dobara sirf Admin chalu kar sakta hai'; end if;
    update public.crm_records set data = (data - 'cancelled' - 'cancel_reason' - 'cancelled_at'), updated_at = now() where id = r.id;
    perform public.crm_log(s, 'update', 'invoice', r.id, 'Bill dobara chalu: ' || r.ref);
    return jsonb_build_object('ok', true);
  end if;
  update public.crm_records set data = data || jsonb_build_object('cancelled', true, 'cancel_reason', why, 'cancelled_at', public.crm_iso_now(), 'cancelled_by', (s).name), updated_at = now() where id = r.id;
  perform public.crm_log(s, 'update', 'invoice', r.id, 'Bill cancel (non-refundable): ' || r.ref || ' — ' || why);
  return jsonb_build_object('ok', true);
end $$;
do $g$ begin execute 'revoke all on function public.crm_bill_cancel(jsonb) from public'; execute 'grant execute on function public.crm_bill_cancel(jsonb) to anon, authenticated'; exception when undefined_object then null; end $g$;

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
