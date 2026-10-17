-- ============================================================================
-- PHASE 9 (Round 15): Visit / click tracking + Admin analytics + Look (colour theme) & Greeting settings
-- Run ONCE in Supabase SQL Editor (already included in MASTER-UPDATE.sql). Safe to re-run.
--   1) sp_events            : every page view / button click / cart / order event (website and store)
--   2) sp_track()           : public, write-only, batch insert (no personal data is stored)
--   3) sp_admin_analytics() : ONE call that returns everything the Admin dashboards draw
--   4) sp_get_cfg() / sp_save_cfg() / crm_cfg_save() : colour theme per panel + greeting banner
-- ============================================================================

create table if not exists public.sp_events (
  id    bigserial primary key,
  ts    timestamptz not null default now(),
  site  text not null check (site in ('website','store')),
  kind  text not null check (kind in ('view','click','cart','search','checkout','enquiry','order')),
  page  text not null default '',
  label text not null default '',
  sid   text not null default '',
  src   text not null default '',
  dev   text not null default '',
  val   numeric not null default 0
);
create index if not exists sp_events_ts on public.sp_events (ts);
create index if not exists sp_events_site_ts on public.sp_events (site, ts);
create index if not exists sp_events_kind_ts on public.sp_events (kind, ts);
alter table public.sp_events enable row level security;
do $$ begin revoke all on public.sp_events from anon, authenticated; exception when others then null; end $$;

-- Public, write-only. Up to 25 events per call. Nothing personal is stored (random visitor id only).
create or replace function public.sp_track(p jsonb) returns int language plpgsql security definer set search_path = public as $$
declare e jsonb; n int := 0; k text; s text;
begin
  if p is null or jsonb_typeof(p -> 'events') <> 'array' then return 0; end if;
  for e in select * from jsonb_array_elements(p -> 'events') limit 25 loop
    s := lower(coalesce(e ->> 'site', '')); k := lower(coalesce(e ->> 'kind', ''));
    if s in ('website','store') and k in ('view','click','cart','search','checkout','enquiry','order') then
      insert into public.sp_events(site, kind, page, label, sid, src, dev, val)
      values (s, k, left(coalesce(e ->> 'page', ''), 120), left(coalesce(e ->> 'label', ''), 80), left(coalesce(e ->> 'sid', ''), 40),
              left(lower(coalesce(e ->> 'src', '')), 30), left(lower(coalesce(e ->> 'dev', '')), 10),
              case when (e ->> 'val') ~ '^[0-9]{1,9}(\.[0-9]{1,2})?$' then (e ->> 'val')::numeric else 0 end);
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;

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
