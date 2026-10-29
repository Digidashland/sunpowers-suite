-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 7 of 30
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U30). Safe to re-run.
-- ============================================================================

-- One call = everything for the dashboards.  p_days: 1..365   (compared with the previous equal period)
create or replace function public.sp_admin_analytics(p_pass text, p_days int default 30) returns jsonb language plpgsql security definer set search_path = public as $$
declare d int := greatest(1, least(coalesce(p_days, 30), 365)); t0 timestamptz; t1 timestamptz := now(); tp timestamptz; r jsonb := '{}'::jsonb;
        ord_cnt int; enq_new int; ord_new int; ord_unpaid int;
begin
  perform public.sp_check(p_pass);
  delete from public.sp_events where ts < now() - interval '400 days';
  t0 := date_trunc('day', now() - ((d - 1) || ' days')::interval); tp := t0 - (d || ' days')::interval;

  -- per site totals for current and previous period
  r := r || jsonb_build_object('cur', (
    select coalesce(jsonb_object_agg(site, o), '{}'::jsonb) from (
      select s.site, jsonb_build_object(
        'visitors', (select count(distinct sid) from public.sp_events where site = s.site and kind = 'view' and ts >= t0 and sid <> ''),
        'views',    (select count(*) from public.sp_events where site = s.site and kind = 'view' and ts >= t0),
        'clicks',   (select count(*) from public.sp_events where site = s.site and kind = 'click' and ts >= t0),
        'carts',    (select count(*) from public.sp_events where site = s.site and kind = 'cart' and ts >= t0),
        'searches', (select count(*) from public.sp_events where site = s.site and kind = 'search' and ts >= t0),
        'shop_views', (select count(*) from public.sp_events where site = s.site and kind = 'view' and ts >= t0 and page like '%shop.html%'),
        'shop_visitors', (select count(distinct sid) from public.sp_events where site = s.site and kind = 'view' and ts >= t0 and page like '%shop.html%' and sid <> ''),
        'mobile',   (select count(distinct sid) from public.sp_events where site = s.site and kind = 'view' and ts >= t0 and dev = 'mobile'),
        'orders',   (select count(*) from public.sp_orders where created_at >= t0 and (case when s.site = 'website' then coalesce(data ->> 'src', '') in ('website','shop') else coalesce(data ->> 'src', '') not in ('website','shop') end)),
        'sales',    (select coalesce(sum(nullif(data ->> 'total', '')::numeric), 0) from public.sp_orders where created_at >= t0 and (case when s.site = 'website' then coalesce(data ->> 'src', '') in ('website','shop') else coalesce(data ->> 'src', '') not in ('website','shop') end)),
        'enquiries',(select count(*) from public.sp_enquiries where created_at >= t0 and (case when s.site = 'website' then coalesce(data ->> 'source', 'website') <> 'store' else coalesce(data ->> 'source', '') = 'store' end))
      ) o from (values ('website'), ('store')) s(site)) q));
  r := r || jsonb_build_object('prev', (
    select coalesce(jsonb_object_agg(site, o), '{}'::jsonb) from (
      select s.site, jsonb_build_object(
        'visitors', (select count(distinct sid) from public.sp_events where site = s.site and kind = 'view' and ts >= tp and ts < t0 and sid <> ''),
        'views',    (select count(*) from public.sp_events where site = s.site and kind = 'view' and ts >= tp and ts < t0),
        'orders',   (select count(*) from public.sp_orders where created_at >= tp and created_at < t0 and (case when s.site = 'website' then coalesce(data ->> 'src', '') in ('website','shop') else coalesce(data ->> 'src', '') not in ('website','shop') end)),
        'sales',    (select coalesce(sum(nullif(data ->> 'total', '')::numeric), 0) from public.sp_orders where created_at >= tp and created_at < t0 and (case when s.site = 'website' then coalesce(data ->> 'src', '') in ('website','shop') else coalesce(data ->> 'src', '') not in ('website','shop') end)),
        'enquiries',(select count(*) from public.sp_enquiries where created_at >= tp and created_at < t0 and (case when s.site = 'website' then coalesce(data ->> 'source', 'website') <> 'store' else coalesce(data ->> 'source', '') = 'store' end))
      ) o from (values ('website'), ('store')) s(site)) q));

  -- daily series (one row per day, both sites)
  r := r || jsonb_build_object('days', (
    select coalesce(jsonb_agg(row_to_json(x) order by x.d), '[]'::jsonb) from (
      select to_char(g.d, 'YYYY-MM-DD') as d,
        (select count(distinct sid) from public.sp_events e where e.site = 'website' and e.kind = 'view' and e.ts >= g.d and e.ts < g.d + interval '1 day' and e.sid <> '') as wv,
        (select count(distinct sid) from public.sp_events e where e.site = 'store' and e.kind = 'view' and e.ts >= g.d and e.ts < g.d + interval '1 day' and e.sid <> '') as sv,
        (select count(*) from public.sp_events e where e.site = 'website' and e.kind = 'view' and e.page like '%shop.html%' and e.ts >= g.d and e.ts < g.d + interval '1 day') as shv,
        (select count(*) from public.sp_orders o where o.created_at >= g.d and o.created_at < g.d + interval '1 day' and coalesce(o.data ->> 'src', '') in ('website','shop')) as wo,
        (select count(*) from public.sp_orders o where o.created_at >= g.d and o.created_at < g.d + interval '1 day' and coalesce(o.data ->> 'src', '') not in ('website','shop')) as so,
        (select coalesce(sum(nullif(o.data ->> 'total', '')::numeric), 0) from public.sp_orders o where o.created_at >= g.d and o.created_at < g.d + interval '1 day' and coalesce(o.data ->> 'src', '') in ('website','shop')) as wsale,
        (select coalesce(sum(nullif(o.data ->> 'total', '')::numeric), 0) from public.sp_orders o where o.created_at >= g.d and o.created_at < g.d + interval '1 day' and coalesce(o.data ->> 'src', '') not in ('website','shop')) as ssale
      from generate_series(t0, date_trunc('day', now()), interval '1 day') g(d)) x));

  -- hour of day (0..23) visitors, both sites (IST)
  r := r || jsonb_build_object('hours', (
    select coalesce(jsonb_agg(jsonb_build_object('h', h, 'w', w, 's', s) order by h), '[]'::jsonb) from (
      select g.h, (select count(*) from public.sp_events e where e.site = 'website' and e.kind = 'view' and e.ts >= t0 and extract(hour from e.ts at time zone 'Asia/Kolkata') = g.h) as w,
                  (select count(*) from public.sp_events e where e.site = 'store' and e.kind = 'view' and e.ts >= t0 and extract(hour from e.ts at time zone 'Asia/Kolkata') = g.h) as s
      from generate_series(0, 23) g(h)) z));

  -- top pages / top buttons / traffic sources (per site)
  r := r || jsonb_build_object('pages', (select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
      select site, page, count(*) as views, count(distinct sid) as visitors from public.sp_events where kind = 'view' and ts >= t0 group by site, page order by count(*) desc limit 40) x));
  r := r || jsonb_build_object('clicks', (select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
      select site, label, page, count(*) as n from public.sp_events where kind = 'click' and ts >= t0 and label <> '' group by site, label, page order by count(*) desc limit 40) x));
  r := r || jsonb_build_object('searches', (select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
      select site, lower(label) as label, count(*) as n from public.sp_events where kind = 'search' and ts >= t0 and label <> '' group by site, lower(label) order by count(*) desc limit 20) x));
  r := r || jsonb_build_object('sources', (select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
      select site, case when src = '' then 'direct' else src end as src, count(distinct sid) as visitors from public.sp_events where kind = 'view' and ts >= t0 group by site, case when src = '' then 'direct' else src end order by count(distinct sid) desc limit 30) x));

  -- funnel (distinct visitors per step)
  r := r || jsonb_build_object('funnel', (select coalesce(jsonb_object_agg(site, f), '{}'::jsonb) from (
      select s.site, jsonb_build_object(
        'visit',    (select count(distinct sid) from public.sp_events where site = s.site and kind = 'view' and ts >= t0 and sid <> ''),
        'cart',     (select count(distinct sid) from public.sp_events where site = s.site and kind = 'cart' and ts >= t0 and sid <> ''),
        'checkout', (select count(distinct sid) from public.sp_events where site = s.site and kind in ('checkout','order') and ts >= t0 and sid <> ''),
        'order',    (select count(*) from public.sp_orders where created_at >= t0 and (case when s.site = 'website' then coalesce(data ->> 'src', '') in ('website','shop') else coalesce(data ->> 'src', '') not in ('website','shop') end))
      ) f from (values ('website'), ('store')) s(site)) q));

  -- top products sold (from orders in the period)
  r := r || jsonb_build_object('top_products', (select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
      select coalesce(i ->> 'title', i ->> 'titleEn', '?') as title, sum(coalesce(nullif(i ->> 'qty', '')::numeric, 1)) as qty, sum(coalesce(nullif(i ->> 'amount', '')::numeric, 0)) as amount,
             sum(case when coalesce(o.data ->> 'src', '') in ('website','shop') then coalesce(nullif(i ->> 'qty', '')::numeric, 1) else 0 end) as web_qty
      from public.sp_orders o, jsonb_array_elements(case when jsonb_typeof(o.data -> 'items') = 'array' then o.data -> 'items' else '[]'::jsonb end) i
      where o.created_at >= t0 group by 1 order by 3 desc limit 10) x));

  -- recent orders
  r := r || jsonb_build_object('recent_orders', (select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
      select id, to_char(created_at at time zone 'Asia/Kolkata', 'DD Mon HH24:MI') as at, status, data ->> 'order_no' as order_no, data ->> 'name' as name, nullif(data ->> 'total', '')::numeric as total,
             case when coalesce(data ->> 'src', '') in ('website','shop') then 'website' else 'store' end as site
      from public.sp_orders order by id desc limit 8) x));

  -- alerts
  select count(*) into ord_new from public.sp_orders where status = 'new';
  select count(*) into ord_unpaid from public.sp_orders where status = 'new' and created_at < now() - interval '24 hours';
  select count(*) into enq_new from public.sp_enquiries where status = 'new';
  r := r || jsonb_build_object('alerts', jsonb_build_object('orders_new', ord_new, 'orders_old', ord_unpaid, 'enquiries_new', enq_new,
        'enquiries_old', (select count(*) from public.sp_enquiries where status = 'new' and created_at < now() - interval '24 hours'),
        'events_total', (select count(*) from public.sp_events)));
  return r || jsonb_build_object('range', jsonb_build_object('days', d, 'from', to_char(t0, 'YYYY-MM-DD'), 'to', to_char(now(), 'YYYY-MM-DD')));
end $$;

-- ---------- Look (colour theme per panel) + Greeting banner : one public row, edited only by Admin ----------
-- Shape: { theme: { website:{preset,...}, store:{...}, admin:{...}, crm:{...} },
--          greet: { on, text, icon, anim, from, to, id, targets:{ website, shop, store, admin, crm:{all, users:{<id>:true}} } } }
create or replace function public.sp_get_cfg() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select data from public.sp_store where id = 'cfg'), '{}'::jsonb);
$$;

create or replace function public.sp_save_cfg(p_pass text, p_data jsonb) returns timestamptz language plpgsql security definer set search_path = public, extensions as $$
declare t timestamptz := now();
begin
  perform public.sp_check(p_pass);
  if p_data is null or jsonb_typeof(p_data) <> 'object' then raise exception 'Invalid data'; end if;
  if length(p_data::text) > 60000 then raise exception 'Settings too large'; end if;
  insert into public.sp_store(id, data, updated_at) values ('cfg', p_data, t)
  on conflict (id) do update set data = excluded.data, updated_at = excluded.updated_at;
  return t;
end $$;

-- Same save, for an Admin-role user logged into the CRM (token based)
create or replace function public.crm_cfg_save(p jsonb) returns timestamptz language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); t timestamptz := now(); d jsonb := p -> 'data';
begin
  if not public.crm_can(s, 'users.manage') then raise exception 'Not allowed'; end if;
  if d is null or jsonb_typeof(d) <> 'object' then raise exception 'Invalid data'; end if;
  if length(d::text) > 60000 then raise exception 'Settings too large'; end if;
  insert into public.sp_store(id, data, updated_at) values ('cfg', d, t)
  on conflict (id) do update set data = excluded.data, updated_at = excluded.updated_at;
  return t;
end $$;

do $$ begin
  revoke all on function public.sp_track(jsonb), public.sp_admin_analytics(text, int), public.sp_get_cfg(), public.sp_save_cfg(text, jsonb), public.crm_cfg_save(jsonb) from public;
  grant execute on function public.sp_track(jsonb), public.sp_admin_analytics(text, int), public.sp_get_cfg(), public.sp_save_cfg(text, jsonb), public.crm_cfg_save(jsonb) to anon, authenticated;
exception when undefined_object then null; end $$;


-- ============================================================================
-- ROUND 16 (database) — 13-step workflow, Projects, lead/quotation rules, pending bill, Documents sharing, customer "My Plant". Safe to re-run.
-- ============================================================================
-- =====================================================================
-- Round 16 — customer workflow, Projects, lead / quotation rules, pending-bill flags, Plant ID for customers
-- Safe to run more than once (create or replace / if not exists).
-- =====================================================================

-- ---------- 13-step customer workflow (names) -------------------------------------------------
create or replace function public.crm_wf_names() returns text[] language sql immutable as $$
  select array['Add Customer','Conversation','Quotation','Site Visit','Blueprint','Confirmation','Apply Process','Hand Over Technician','Start Installation',
               'Verification / Commissioning','Net Metering','Finish Work','Subsidy Redeem','Send Demo / Files','Loan / Finance','Suggest / Referral','AMC / Maintenance','Complaint Status','Leads'] $$;

create or replace function public.crm_ctypes() returns text[] language sql immutable as $$ select array['Residential','Commercial','Industrial','VFD','Items only','Service'] $$;

create or replace function public.crm_iso_now() returns text language sql stable as $$
  select to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS"+05:30"') $$;

-- sets step n inside data.wf when it is not there yet
create or replace function public.crm_wf_mark(d jsonb, n int, by text, at_ text default null, auto boolean default true) returns jsonb language sql stable as $$
  select case when coalesce(d -> 'wf', '{}'::jsonb) ? n::text then d
    else d || jsonb_build_object('wf', coalesce(d -> 'wf', '{}'::jsonb) || jsonb_build_object(n::text, jsonb_build_object('at', coalesce(at_, public.crm_iso_now()), 'by', coalesce(by, ''), 'auto', auto))) end $$;

-- ---------- rules enforced on every write (cannot be bypassed from the browser) ---------------------
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
    elsif ct = 'Service' and new.party_id is not null then
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
declare names text[] := public.crm_wf_names(); out jsonb := '[]'::jsonb; n int; w jsonb := coalesce(q.data -> 'wf', '{}'::jsonb); st jsonb; v boolean; e boolean;
        priv boolean := public.crm_is_admin(s) or (s).role = 'manager'; pat text; auto boolean;
begin
  foreach n in array public.crm_wf_flow_of(q) loop
    auto := public.crm_wf_is_auto(n);
    if n = 19 then
      select to_char(created_at at time zone 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS"+05:30"') into pat from public.crm_records where id = q.party_id;
      out := out || jsonb_build_array(jsonb_build_object('n', 19, 'name', names[19], 'done', true, 'at', pat, 'auto', true, 'manual', false, 'skip', false, 'locked', false, 'can_edit', false,
        'note', 'Path (kahan se aaya): ' || coalesce(nullif((select data ->> 'source' from public.crm_records where id = q.party_id), ''), 'Purana / Unknown')));
      continue;
    end if;
    st := w -> n::text; v := public.crm_wf_can(s, n, 'view'); e := public.crm_wf_can(s, n, 'edit');
    out := out || jsonb_build_array(jsonb_build_object('n', n, 'name', names[n], 'done', st is not null, 'at', st ->> 'at',
      'auto', coalesce((st ->> 'auto')::boolean, false), 'manual', not auto, 'skip', coalesce((st ->> 'skip')::boolean, false), 'can_skip', public.crm_wf_can_skip(n),
      'locked', not v, 'can_edit', e and not auto and (n <> 13 or priv),
      'by', case when v then st ->> 'by' end, 'note', case when v then st ->> 'note' end, 'info', case when v then coalesce(st -> 'info', '{}'::jsonb) end));
  end loop;
  return out;
end $$;

-- the workflow of one quotation (or the latest quotation of a customer)
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
  fk := case coalesce(q.data ->> 'ctype', '') when 'Items only' then 'product' when 'Service' then 'service' else 'project' end;
  return jsonb_build_object('party_id', q.party_id, 'quote_id', q.id, 'ref', q.ref, 'title', coalesce(q.data ->> 'qtitle', q.title), 'ctype', q.data ->> 'ctype', 'status', q.status, 'plants', plants,
    'project', (q.data -> 'wf') ? '7', 'kind', fk, 'bill_state', q.data ->> 'bill_state', 'steps', public.crm_wf_steps(s, q));
end $$;

-- confirm / undo one manual step
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
    raise exception 'Ye step is customer ke liye nahi hai (% — %)', case ct when 'Items only' then 'Product customer' when 'Service' then 'Service customer' else 'Project customer' end, (public.crm_wf_names())[n];
  end if;
  if n = 13 and not (public.crm_is_admin(s) or (s).role = 'manager') then raise exception 'Subsidy sirf Admin ya Manager green kar sakte hain'; end if;
  if not public.crm_wf_can(s, n, 'edit') then raise exception 'Is step ko badalne ki permission nahi hai — Admin se allow karwayein'; end if;
  w := coalesce(q.data -> 'wf', '{}'::jsonb);
  if done then
    if n = 7 and not (w ? '6') then raise exception 'Pehle quotation Confirm hona chahiye'; end if;
    if (n in (8, 9, 10, 11, 13) or (n = 17 and ct <> 'Service')) and not (w ? '7') then raise exception 'Pehle Apply Process confirm karein — tabhi customer Projects me aata hai'; end if;
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
  return jsonb_build_object('perm', coalesce(cur -> 'perm', '{}'::jsonb), 'allow_old', coalesce((cur ->> 'allow_old')::boolean, false), 'names', to_jsonb(public.crm_wf_names()),
    'manual', (select coalesce(jsonb_agg(k order by k), '[]'::jsonb) from generate_series(1, 18) k where not public.crm_wf_is_auto(k)), 'flow', to_jsonb(public.crm_wf_flow('Residential')));
end $$;

-- Projects list (Apply Process confirmed, or an old project Admin allowed)
create or replace function public.crm_projects(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token');
begin
  return coalesce((select jsonb_agg(x order by (x ->> 'id')::bigint desc) from (
    select jsonb_build_object('id', q.id, 'ref', q.ref, 'party_id', q.party_id, 'customer', q.title, 'mobile', q.mobile, 'title', coalesce(q.data ->> 'qtitle', q.title), 'ctype', q.data ->> 'ctype',
      'kw', q.data ->> 'kw', 'amount', q.amount, 'status', q.status, 'bill_state', q.data ->> 'bill_state', 'closed', coalesce((q.data ->> 'closed')::boolean, false), 'old', coalesce((q.data ->> 'old_project')::boolean, false),
      'owner', public.crm_uname(q.owner_id),
      'done', (select count(*) from unnest(public.crm_wf_flow_of(q)) f where f = 19 or (q.data -> 'wf') ? f::text),
      'total', array_length(public.crm_wf_flow_of(q), 1),
      'last', (select max(v ->> 'at') from jsonb_each(coalesce(q.data -> 'wf', '{}'::jsonb)) e(k, v)),
      'balance', (select (i.data ->> 'balance')::numeric from public.crm_records i where i.id = nullif(q.data ->> 'invoice_id', '')::bigint),
      'steps', public.crm_wf_steps(s, q)) as x
    from public.crm_records q
    where q.kind = 'quote' and q.deleted_at is null and coalesce(q.data ->> 'ctype', '') in ('Residential', 'Commercial', 'Industrial', 'VFD')
      and ((q.data -> 'wf') ? '7' or coalesce((q.data ->> 'old_project')::boolean, false)) and public.crm_vis(s, q) limit 2000) z), '[]'::jsonb);
end $$;