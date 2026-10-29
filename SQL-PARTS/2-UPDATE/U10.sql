-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 10 of 30
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U30). Safe to re-run.
-- ============================================================================

grant execute on function public.crm_share_create(jsonb) to anon, authenticated;

create or replace function public.crm_share_list(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token');
begin
  return coalesce((select jsonb_agg(jsonb_build_object('token', x.token, 'kind', x.kind, 'title', x.title, 'at', x.created_at, 'by', x.by_name, 'views', x.views,
            'last_view', x.last_view, 'revoked', x.revoked, 'expired', x.expires_at < now()) order by x.id desc)
     from (select * from public.sp_shares where ref = btrim(coalesce(p ->> 'ref', '')) and btrim(coalesce(p ->> 'ref', '')) <> '' order by id desc limit 20) x), '[]'::jsonb);
end $$;
revoke all on function public.crm_share_list(jsonb) from public;
grant execute on function public.crm_share_list(jsonb) to anon, authenticated;

create or replace function public.crm_share_revoke(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); n int;
begin
  update public.sp_shares set revoked = coalesce((p ->> 'on')::boolean, true) where token = btrim(coalesce(p ->> 'code', ''));
  get diagnostics n = row_count;
  return jsonb_build_object('ok', n > 0);
end $$;
revoke all on function public.crm_share_revoke(jsonb) from public;
grant execute on function public.crm_share_revoke(jsonb) to anon, authenticated;

-- customers on Website / Store (no login): short upload token + create, both rate-limited per IP ---------------------------
create or replace function public.sp_share_rate(p_max int) returns void
language plpgsql security definer set search_path = public as $$
declare v_ip text := coalesce(nullif(split_part(coalesce(current_setting('request.headers', true), '{}')::json ->> 'x-forwarded-for', ',', 1), ''), 'local');
begin
  delete from public.sp_share_rl where at < now() - interval '1 day';
  if (select count(*) from public.sp_share_rl where ip = v_ip and at > now() - interval '1 hour') >= p_max
     or (select count(*) from public.sp_share_rl where at > now() - interval '1 hour') >= 400 then
    raise exception 'Bahut zyada koshish — thodi der baad dobara karein';
  end if;
  insert into public.sp_share_rl(ip) values (v_ip);
end $$;
revoke all on function public.sp_share_rate(int) from public, anon, authenticated;

create or replace function public.sp_share_pub_token(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare t text := encode(gen_random_bytes(12), 'hex');
begin
  perform public.sp_share_rate(20);
  delete from public.sp_upload_tokens where exp < now();
  insert into public.sp_upload_tokens(token, exp) values (t, now() + interval '20 minutes');
  return jsonb_build_object('token', t);
end $$;
revoke all on function public.sp_share_pub_token(jsonb) from public;
grant execute on function public.sp_share_pub_token(jsonb) to anon, authenticated;

create or replace function public.sp_share_pub_create(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare t text;
begin
  perform public.sp_share_rate(20);
  t := public.sp_share_insert(p, null, 'Customer', 'public');
  return jsonb_build_object('token', t);
end $$;
revoke all on function public.sp_share_pub_create(jsonb) from public;
grant execute on function public.sp_share_pub_create(jsonb) to anon, authenticated;

-- the public link page (Vercel function /api/d) reads one share by its code; counts a view only for real people ------------
create or replace function public.sp_share_open(p_token text, p_count boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.sp_shares;
begin
  select * into r from public.sp_shares where token = btrim(coalesce(p_token, '')) and not revoked and expires_at > now();
  if r.id is null then return null; end if;
  if p_count then update public.sp_shares set views = views + 1, first_view = coalesce(first_view, now()), last_view = now() where id = r.id; end if;
  return jsonb_build_object('kind', r.kind, 'title', r.title, 'subtitle', r.subtitle, 'amount', r.amount, 'valid_till', r.valid_till, 'details', r.details,
    'pdf_url', r.pdf_url, 'view_url', r.view_url, 'file_name', r.file_name, 'brand', r.brand, 'phone', r.phone, 'created_at', r.created_at);
end $$;
revoke all on function public.sp_share_open(text, boolean) from public;
grant execute on function public.sp_share_open(text, boolean) to anon, authenticated;

notify pgrst, 'reload schema';

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