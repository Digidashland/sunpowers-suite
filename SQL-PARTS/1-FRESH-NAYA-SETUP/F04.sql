-- ============================================================================
-- SUNPOWERS — NAYA PROJECT SETUP — part 4 of 15
-- Naya (khali) Supabase project: pehle F01..F06, phir 2-UPDATE ke U01..U09.
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (F01 -> F06, phir U01 -> U09). Safe to re-run.
-- ============================================================================

create or replace function public.crm_team_stats(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); dt date := public.crm_today(); fr date := coalesce(nullif(p ->> 'from', '')::date, public.crm_today() - 30);
begin
  perform public.crm_need(s, 'team.stats');
  return coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'role', u.role, 'last_seen', u.last_seen,
    'open', (select count(*) from public.crm_records r where r.kind = 'reminder' and r.deleted_at is null and r.status = 'open' and coalesce(r.assigned_to, r.owner_id) = u.id),
    'overdue', (select count(*) from public.crm_records r where r.deleted_at is null and coalesce(r.assigned_to, r.owner_id) = u.id and r.due_at < dt
                 and ((r.kind = 'reminder' and r.status = 'open') or (r.kind = 'lead' and r.status not in ('won', 'lost')))),
    'done', (select count(*) from public.crm_records r where r.kind = 'reminder' and r.deleted_at is null and r.status = 'done' and coalesce(r.assigned_to, r.owner_id) = u.id and r.updated_at::date >= fr),
    'late', (select count(*) from public.crm_records r where r.kind = 'reminder' and r.deleted_at is null and r.status = 'done' and coalesce(r.assigned_to, r.owner_id) = u.id and r.updated_at::date >= fr
              and (r.data ->> 'done_at')::timestamptz::date > r.due_at),
    'leads', (select count(*) from public.crm_records r where r.kind = 'lead' and r.deleted_at is null and coalesce(r.assigned_to, r.owner_id) = u.id),
    'won', (select count(*) from public.crm_records r where r.kind = 'lead' and r.deleted_at is null and r.status = 'won' and coalesce(r.assigned_to, r.owner_id) = u.id),
    'quotes', (select count(*) from public.crm_records r where r.kind = 'quote' and r.deleted_at is null and r.owner_id = u.id and r.created_at::date >= fr),
    'sales', (select coalesce(sum(amount), 0) from public.crm_records r where r.kind = 'invoice' and r.deleted_at is null and r.owner_id = u.id and r.created_at::date >= fr),
    'plants', (select count(*) from public.crm_records r where r.kind = 'plant' and r.deleted_at is null and r.status = 'verified' and (r.owner_id = u.id or upper(r.data ->> 'ref') = u.ref_code))
  ) order by u.name) from public.crm_users u where u.role not in ('consumer') and u.status = 'active'), '[]'::jsonb);
end $$;

create or replace function public.crm_dashboard(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); dt date := public.crm_today(); m0 date := date_trunc('month', public.crm_today())::date; res jsonb; u bigint := (s).uid;
begin
  res := jsonb_build_object(
    'customers', (select count(*) from public.crm_records r where r.kind = 'party' and r.deleted_at is null and public.crm_vis(s, r)),
    'leads_new', (select count(*) from public.crm_records r where r.kind = 'lead' and r.deleted_at is null and r.status = 'new' and public.crm_vis(s, r)),
    'leads_open', (select count(*) from public.crm_records r where r.kind = 'lead' and r.deleted_at is null and r.status not in ('won', 'lost') and public.crm_vis(s, r)),
    'quotes_month', (select coalesce(sum(amount), 0) from public.crm_records r where r.kind = 'quote' and r.deleted_at is null and r.created_at >= m0 and public.crm_vis(s, r)),
    'quotes_count', (select count(*) from public.crm_records r where r.kind = 'quote' and r.deleted_at is null and r.created_at >= m0 and public.crm_vis(s, r)),
    'sales_month', (select coalesce(sum(amount), 0) from public.crm_records r where r.kind = 'invoice' and r.deleted_at is null and r.created_at >= m0 and public.crm_vis(s, r)),
    'receivable', (select coalesce(sum(public.crm_num(data -> 'balance')), 0) from public.crm_records r where r.kind = 'invoice' and r.deleted_at is null and r.status <> 'paid' and public.crm_vis(s, r)),
    'collected_month', (select coalesce(sum(amount), 0) from public.crm_records r where r.kind = 'payment' and r.deleted_at is null and r.due_at >= m0 and public.crm_vis(s, r)),
    'plants', (select count(*) from public.crm_records r where r.kind = 'plant' and r.deleted_at is null and r.status = 'verified' and public.crm_vis(s, r)),
    'plants_kw', (select coalesce(sum(public.crm_num(data -> 'kw')), 0) from public.crm_records r where r.kind = 'plant' and r.deleted_at is null and r.status = 'verified' and public.crm_vis(s, r)),
    'plants_pending', (select count(*) from public.crm_records r where r.kind = 'plant' and r.deleted_at is null and r.status = 'pending' and public.crm_vis(s, r)),
    'earn_due', (select coalesce(sum(amount), 0) from public.crm_records r where r.kind = 'earning' and r.deleted_at is null and r.status = 'due' and public.crm_vis(s, r)),
    'earn_paid', (select coalesce(sum(amount), 0) from public.crm_records r where r.kind = 'earning' and r.deleted_at is null and r.status = 'paid' and public.crm_vis(s, r)),
    'today', (select count(*) from public.crm_records r where r.deleted_at is null and coalesce(r.assigned_to, r.owner_id) = u and r.due_at <= dt
               and ((r.kind = 'reminder' and r.status = 'open') or (r.kind = 'lead' and r.status not in ('won', 'lost')))),
    'overdue', (select count(*) from public.crm_records r where r.deleted_at is null and coalesce(r.assigned_to, r.owner_id) = u and r.due_at < dt
               and ((r.kind = 'reminder' and r.status = 'open') or (r.kind = 'lead' and r.status not in ('won', 'lost')))),
    'target', (select meta -> 'target_monthly' from public.crm_users where id = u),
    'notices', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'title', title, 'body', data ->> 'body', 'at', created_at) order by id desc) from (select * from public.crm_records where kind = 'notice' and deleted_at is null order by id desc limit 5) n), '[]'::jsonb)
  );
  if public.crm_can(s, 'orders.view') then
    res := res || jsonb_build_object('orders_new', (select count(*) from public.sp_orders where status = 'new'), 'enquiries_new', (select count(*) from public.sp_enquiries where status = 'new'));
  end if;
  if public.crm_can(s, 'users.manage') then res := res || jsonb_build_object('users_pending', (select count(*) from public.crm_users where status = 'pending')); end if;
  if public.crm_can(s, 'items.to_store') then res := res || jsonb_build_object('store_pending', (select count(*) from public.crm_records where kind = 'item' and deleted_at is null and data #>> '{store,status}' = 'pending')); end if;
  return res;
end $$;

-- bell: new things since a time
create or replace function public.crm_pulse(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); since timestamptz := coalesce(nullif(p ->> 'since', '')::timestamptz, now() - interval '3 days'); items jsonb := '[]'::jsonb;
begin
  if public.crm_can(s, 'orders.view') then
    items := items || coalesce((select jsonb_agg(jsonb_build_object('type', 'order', 'id', id, 'at', created_at, 'title', 'Naya order #' || id || ' — ' || coalesce(data ->> 'name', ''), 'amount', data -> 'total'))
      from (select * from public.sp_orders where created_at > since order by id desc limit 20) o), '[]'::jsonb);
    items := items || coalesce((select jsonb_agg(jsonb_build_object('type', 'enquiry', 'id', id, 'at', created_at, 'title', 'Nayi enquiry — ' || coalesce(data ->> 'name', '') || ' (' || coalesce(data ->> 'source', 'store') || ')'))
      from (select * from public.sp_enquiries where created_at > since order by id desc limit 20) e), '[]'::jsonb);
  end if;
  items := items || coalesce((select jsonb_agg(jsonb_build_object('type', 'lead', 'id', id, 'at', updated_at, 'title', 'Lead mili: ' || title))
    from (select * from public.crm_records where kind = 'lead' and deleted_at is null and assigned_to = (s).uid and owner_id <> (s).uid and updated_at > since order by id desc limit 20) l), '[]'::jsonb);
  items := items || coalesce((select jsonb_agg(jsonb_build_object('type', 'reminder', 'id', id, 'at', created_at, 'title', 'Naya kaam: ' || title || ' (' || to_char(due_at, 'DD-MM') || ')'))
    from (select * from public.crm_records where kind = 'reminder' and deleted_at is null and assigned_to = (s).uid and owner_id <> (s).uid and created_at > since order by id desc limit 20) l), '[]'::jsonb);
  if public.crm_can(s, 'plants.verify') then
    items := items || coalesce((select jsonb_agg(jsonb_build_object('type', 'plant', 'id', id, 'at', created_at, 'title', 'Plant verify karna hai: ' || title))
      from (select * from public.crm_records where kind = 'plant' and deleted_at is null and status = 'pending' and created_at > since order by id desc limit 20) l), '[]'::jsonb);
  end if;
  if public.crm_can(s, 'users.manage') then
    items := items || coalesce((select jsonb_agg(jsonb_build_object('type', 'user', 'id', id, 'at', created_at, 'title', 'Nayi ID verify karni hai: ' || name || ' (' || role || ')'))
      from (select * from public.crm_users where status = 'pending' and created_at > since order by id desc limit 20) l), '[]'::jsonb);
  end if;
  return jsonb_build_object('now', now(), 'items', items);
end $$;

create or replace function public.crm_activity_list(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); u bigint := nullif(p ->> 'user_id', '')::bigint; fr date := nullif(p ->> 'from', '')::date; t date := nullif(p ->> 'to', '')::date; q text := lower(coalesce(p ->> 'q', ''));
begin
  perform public.crm_need(s, 'activity.view');
  return coalesce((select jsonb_agg(to_jsonb(a) order by a.id desc) from (select * from public.crm_activity a
    where (u is null or a.user_id = u) and (fr is null or (a.at at time zone 'Asia/Kolkata')::date >= fr) and (t is null or (a.at at time zone 'Asia/Kolkata')::date <= t)
      and (q = '' or lower(coalesce(a.summary, '') || ' ' || coalesce(a.user_name, '') || ' ' || a.action) like '%' || q || '%')
    order by a.id desc limit least(coalesce((p ->> 'limit')::int, 500), 3000)) a), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------- store orders + website enquiries inside CRM
create or replace function public.crm_orders(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); k text := p ->> 'kind'; st text := nullif(p ->> 'status', '');
begin
  perform public.crm_need(s, 'orders.view');
  if k = 'orders' then
    return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'created_at', created_at, 'status', status, 'data', data) order by id desc) from (select * from public.sp_orders where st is null or status = st order by id desc limit 500) o), '[]'::jsonb);
  elsif k = 'enquiries' then
    return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'created_at', created_at, 'status', status, 'data', data) order by id desc) from (select * from public.sp_enquiries where st is null or status = st order by id desc limit 500) o), '[]'::jsonb);
  end if;
  raise exception 'Galat list';
end $$;

create or replace function public.crm_order_status(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); k text := p ->> 'kind'; st text := p ->> 'status'; i bigint := (p ->> 'id')::bigint;
begin
  perform public.crm_need(s, 'orders.manage');
  if k = 'orders' then
    if st not in ('new', 'confirmed', 'paid', 'shipped', 'delivered', 'cancelled') then raise exception 'Galat status'; end if;
    update public.sp_orders set status = st where id = i;
  elsif k = 'enquiries' then
    if st not in ('new', 'contacted', 'closed', 'cancelled') then raise exception 'Galat status'; end if;
    update public.sp_enquiries set status = st where id = i;
  else raise exception 'Galat list'; end if;
  if not found then raise exception 'Record nahi mila'; end if;
  perform public.crm_log(s, 'status', k, i, k || ' #' || i || ' → ' || st);
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------- online store hand-off (CRM → Store Admin review → Publish)
create or replace function public.crm_to_store(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records;
begin
  perform public.crm_need(s, 'items.to_store');
  select * into r from public.crm_records where id = (p ->> 'id')::bigint and kind = 'item' and deleted_at is null;
  if r.id is null then raise exception 'Item nahi mila'; end if;
  if coalesce(r.data ->> 'type', 'product') not in ('product', 'project') then raise exception 'Sirf product ya project online store ko bheja ja sakta hai'; end if;
  update public.crm_records set data = jsonb_set(data, '{store}', coalesce(data -> 'store', '{}'::jsonb) || jsonb_build_object('status', 'pending', 'sent_at', now(), 'sent_by', (s).name)), updated_at = now() where id = r.id;
  perform public.crm_log(s, 'to_store', 'item', r.id, 'Online Store Admin ko bheja: ' || r.title);
  return jsonb_build_object('ok', true);
end $$;

-- Store Admin side (uses store admin password, same as admin.html)
create or replace function public.sp_admin_crm_items(p_pass text) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.sp_check(p_pass);
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'title', title, 'amount', amount, 'data', data, 'updated_at', updated_at) order by updated_at desc)
    from public.crm_records where kind = 'item' and deleted_at is null and coalesce(data #>> '{store,status}', 'none') in ('pending', 'published', 'rejected')), '[]'::jsonb);
end $$;

create or replace function public.sp_admin_crm_item_set(p_pass text, p_id bigint, p_status text, p_store_id text, p_note text) returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.sp_check(p_pass);
  if p_status not in ('published', 'rejected', 'pending') then raise exception 'Galat status'; end if;
  update public.crm_records set data = jsonb_set(data, '{store}', coalesce(data -> 'store', '{}'::jsonb) || jsonb_build_object('status', p_status, 'store_id', p_store_id, 'note', p_note, 'reviewed_at', now())), updated_at = now()
  where id = p_id and kind = 'item';
  insert into public.crm_activity(user_id, user_name, role, action, kind, rec_id, summary) values (0, 'Store Admin', 'admin', 'store_' || p_status, 'item', p_id, 'Online Store: ' || p_status || coalesce(' — ' || nullif(p_note, ''), ''));
  return found;
end $$;


-- ---------------------------------------------------------------- Online Store customer login (main app → "Mera Account")
create or replace function public.crm_csession(p_token text) returns public.crm_users
language plpgsql security definer set search_path = public as $$
declare se record; u public.crm_users;
begin
  select * into se from public.crm_sessions where token = coalesce(p_token, '') and expires_at > now() and role = 'consumer';
  if se.token is null then raise exception 'Login expired — dobara login karein'; end if;
  if se.expires_at < now() + interval '330 days' then update public.crm_sessions set expires_at = now() + interval '365 days' where token = se.token; end if;
  select * into u from public.crm_users where id = se.user_id and role = 'consumer';
  if u.id is null or u.status <> 'active' then raise exception 'Account active nahi hai'; end if;
  if u.last_seen is null or u.last_seen < now() - interval '5 minutes' then update public.crm_users set last_seen = now() where id = u.id; end if;
  return u;
end $$;

create or replace function public.crm_consumer_me(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token');
begin
  return jsonb_build_object('id', u.id, 'name', u.name, 'mobile', u.mobile, 'email', u.email, 'username', u.username, 'meta', coalesce(u.meta, '{}'::jsonb), 'created_at', u.created_at,
    'orders', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'created_at', o.created_at, 'status', o.status, 'total', o.data -> 'total', 'advance', o.data -> 'advance', 'payment', o.data ->> 'payment',
        'items', (select coalesce(jsonb_agg(jsonb_build_object('title', i ->> 'title', 'qty', i -> 'qty', 'amount', i -> 'amount')), '[]'::jsonb) from jsonb_array_elements(coalesce(o.data -> 'items', '[]'::jsonb)) i)) order by o.id desc)
      from (select * from public.sp_orders where (data ->> 'phone') = u.mobile or (data ->> 'customer_id') = u.id::text order by id desc limit 100) o), '[]'::jsonb),
    'enquiries', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'created_at', e.created_at, 'status', e.status, 'type', e.data ->> 'type', 'subject', e.data ->> 'subject', 'message', e.data ->> 'message') order by e.id desc)
      from (select * from public.sp_enquiries where (data ->> 'phone') = u.mobile or (data ->> 'customer_id') = u.id::text order by id desc limit 50) e), '[]'::jsonb));
end $$;

create or replace function public.crm_consumer_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); d jsonb := coalesce(p -> 'data', '{}'::jsonb);
begin
  if coalesce(trim(d ->> 'name'), '') = '' then raise exception 'Naam likhein'; end if;
  if coalesce(d ->> 'pincode', '') <> '' and (d ->> 'pincode') !~ '^\d{6}$' then raise exception 'Pincode 6 ank ka ho'; end if;
  if coalesce(p ->> 'new', '') <> '' then
    if crypt(coalesce(p ->> 'old', ''), u.pass_hash) <> u.pass_hash then perform pg_sleep(1); raise exception 'Purana password galat hai'; end if;
    if length(p ->> 'new') < 6 then raise exception 'Naya password kam se kam 6 akshar ka ho'; end if;
    update public.crm_users set pass_hash = crypt(p ->> 'new', gen_salt('bf')) where id = u.id;
  end if;
  update public.crm_users set name = left(trim(d ->> 'name'), 80), email = left(coalesce(d ->> 'email', ''), 120),
    meta = coalesce(meta, '{}'::jsonb) || jsonb_build_object('address', left(coalesce(d ->> 'address', ''), 300), 'city', left(coalesce(d ->> 'city', ''), 80), 'pincode', coalesce(d ->> 'pincode', ''))
  where id = u.id;
  return public.crm_consumer_me(jsonb_build_object('token', p ->> 'token'));
end $$;

-- CRM side: list of Online Store customers (who made a login in the main app)
create or replace function public.crm_consumers(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token');
begin
  perform public.crm_need(s, 'orders.view');
  return coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'mobile', case when public.crm_can(s, 'privacy.see_mobile') then u.mobile else left(u.mobile, 2) || '******' || right(u.mobile, 2) end,
      'email', u.email, 'city', u.meta ->> 'city', 'address', u.meta ->> 'address', 'pincode', u.meta ->> 'pincode', 'status', u.status, 'created_at', u.created_at, 'last_seen', u.last_seen,
      'orders', (select count(*) from public.sp_orders o where (o.data ->> 'phone') = u.mobile or (o.data ->> 'customer_id') = u.id::text),
      'in_crm', exists (select 1 from public.crm_records r where r.kind = 'party' and r.deleted_at is null and r.mobile = u.mobile)) order by u.id desc)
    from public.crm_users u where u.role = 'consumer'), '[]'::jsonb);
end $$;


-- =====================================================================
--  LOGIN SECURITY — Email OTP (Resend) + PIN + security questions + reset link
--  Admin: email OTP (new phone/browser) → 6-digit PIN every time
--  Others: email OTP once per device → 4-digit PIN → stay logged in until they log out
-- =====================================================================
do $$ begin create extension if not exists pg_net with schema extensions; exception when others then raise notice 'pg_net: %', sqlerrm; end $$;

alter table public.crm_users add column if not exists pin_hash text not null default '';
alter table public.crm_users add column if not exists pin_fail int not null default 0;
alter table public.crm_users add column if not exists q_fail int not null default 0;
alter table public.crm_users add column if not exists email_ok boolean not null default false;
alter table public.crm_sessions add column if not exists dev_hash text;
alter table public.crm_users alter column pass_hash set default '';

create table if not exists public.crm_auth_admin (
  id int primary key default 1 check (id = 1),
  email text not null default '', email2 text not null default '',
  pin_hash text not null default '', pin_fail int not null default 0,
  q1 text not null default '', a1 text not null default '', q2 text not null default '', a2 text not null default '', q_fail int not null default 0,
  updated_at timestamptz not null default now()
);
insert into public.crm_auth_admin(id, email, email2) values (1, 'helpsunpowers@gmail.com', 'surajanandpbh@gmail.com') on conflict (id) do nothing;
create table if not exists public.crm_devices (
  id bigserial primary key, user_id bigint not null, dev_hash text not null, name text not null default '',
  created_at timestamptz not null default now(), last_seen timestamptz not null default now(), unique (user_id, dev_hash)
);
create table if not exists public.crm_otps (
  id bigserial primary key, user_id bigint not null, purpose text not null default 'login', code_hash text not null,
  expires_at timestamptz not null, tries int not null default 0, used boolean not null default false,
  ticket_hash text, ticket_expires timestamptz, created_at timestamptz not null default now()
);
create index if not exists crm_otps_user on public.crm_otps(user_id, created_at desc);
create table if not exists public.crm_resets (
  token_hash text primary key, user_id bigint not null, app text not null, expires_at timestamptz not null,
  used boolean not null default false, created_at timestamptz not null default now()
);
create table if not exists public.crm_mail_log (
  id bigserial primary key, at timestamptz not null default now(), to_list text, subject text, request_id bigint, note text
);
alter table public.crm_auth_admin enable row level security;
alter table public.crm_devices enable row level security;
alter table public.crm_otps enable row level security;
alter table public.crm_resets enable row level security;
alter table public.crm_mail_log enable row level security;
do $$ begin
  revoke all on public.crm_auth_admin, public.crm_devices, public.crm_otps, public.crm_resets, public.crm_mail_log from anon, authenticated;
exception when undefined_object then null; end $$;

-- default settings for login: sender + app links used in reset e-mails
update public.crm_settings set data = jsonb_set(data, '{auth}', jsonb_build_object(
    'from', 'Sunpowers <no-reply@sunpowers.in>',
    'urls', jsonb_build_object('store', 'https://store.sunpowers.in', 'crm', 'https://crm.sunpowers.in', 'admin', 'https://admin.sunpowers.in'),
    'legacy_password', false) || coalesce(data -> 'auth', '{}'::jsonb))
where id = 1;

create or replace function public.crm_legacy() returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not coalesce((select (data #>> '{auth,legacy_password}')::boolean from public.crm_settings where id = 1), false) then
    raise exception 'Password wala login band hai — Email OTP + PIN se login karein';
  end if;
end $$;

create or replace function public.crm_h(t text) returns text language sql immutable set search_path = public, extensions as $$
  select encode(extensions.digest(coalesce(t, ''), 'sha256'), 'hex') $$;
create or replace function public.crm_mask_email(e text) returns text language sql immutable as $$
  select case when position('@' in coalesce(e, '')) > 1 then left(e, 2) || repeat('*', greatest(position('@' in e) - 3, 1)) || substr(e, position('@' in e)) else '' end $$;

-- ---------------------------------------------------------------- e-mail (Resend via pg_net)
create or replace function public.crm_resend_key() returns text language plpgsql security definer set search_path = public as $$
declare k text;
begin
  begin execute 'select decrypted_secret from vault.decrypted_secrets where name = $1 order by created_at desc limit 1' into k using 'resend_api_key';
  exception when others then k := null; end;
  if coalesce(k, '') = '' then select secrets ->> 'resend_api_key' into k from public.crm_settings where id = 1; end if;
  return nullif(trim(coalesce(k, '')), '');
end $$;

create or replace function public.crm_mail(p_to text[], p_subject text, p_html text) returns bigint
language plpgsql security definer set search_path = public, extensions as $$
declare k text := public.crm_resend_key(); fr text; rid bigint; tos text[];
begin
  select array_agg(x) into tos from (select distinct trim(x) x from unnest(p_to) x where trim(coalesce(x, '')) ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') q;
  if tos is null then raise exception 'Email ID nahi hai — Admin se email judwayein'; end if;
  if k is null then raise exception 'Email setup baaki hai (Resend API key) — Admin se sampark karein'; end if;
  select coalesce(nullif(data #>> '{auth,from}', ''), 'Sunpowers <onboarding@resend.dev>') into fr from public.crm_settings where id = 1;
  begin
    execute 'select net.http_post(url := $1, body := $2, headers := $3)' into rid
      using 'https://api.resend.com/emails', jsonb_build_object('from', fr, 'to', to_jsonb(tos), 'subject', p_subject, 'html', p_html),
            jsonb_build_object('Authorization', 'Bearer ' || k, 'Content-Type', 'application/json');
  exception when others then
    insert into public.crm_mail_log(to_list, subject, note) values (array_to_string(tos, ', '), p_subject, 'pg_net error: ' || sqlerrm);
    raise exception 'Email nahi ja paya (pg_net extension chalu karein)';
  end;
  insert into public.crm_mail_log(to_list, subject, request_id) values (array_to_string(tos, ', '), p_subject, rid);
  return rid;
end $$;

create or replace function public.crm_mail_tpl(p_title text, p_body text) returns text language plpgsql stable security definer set search_path = public as $$
declare u text; co text;
begin
  select coalesce(nullif(data #>> '{auth,urls,store}', ''), ''), coalesce(nullif(data #>> '{company,name}', ''), 'Sunpowers') into u, co from public.crm_settings where id = 1;
  return '<div style="font-family:Arial,Helvetica,sans-serif;background:#f4f7f2;padding:24px"><div style="max-width:480px;margin:auto;background:#fff;border-radius:16px;overflow:hidden;border:1px solid #e0e8de">'
    || '<div style="background:#0b2e1f;padding:18px 22px;color:#fff;font-size:20px;font-weight:bold">' || (case when u <> '' then '<img src="' || rtrim(u, '/') || '/icon-192.png" width="36" height="36" style="vertical-align:middle;border-radius:8px;margin-right:10px">' else '' end) || co || '</div>'
    || '<div style="padding:22px;color:#14231a;font-size:15px;line-height:1.55"><h2 style="margin:0 0 12px;font-size:19px;color:#0b2e1f">' || p_title || '</h2>' || p_body || '</div>'
    || '<div style="padding:12px 22px;background:#fafcf9;color:#5f6f64;font-size:12px">Ye email aapne nahi maanga to ise ignore karein — aapka account surakshit hai.</div></div></div>';
end $$;

-- ---------------------------------------------------------------- who is logging in
-- app: 'crm' (team + admin), 'store' (customers), 'admin' (store admin panel → only admin)
create or replace function public.crm_auth_find(p_app text, p_id text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare x text := lower(trim(coalesce(p_id, ''))); m text := public.crm_mobile(p_id); u public.crm_users; a public.crm_auth_admin;
begin
  if p_app not in ('crm', 'store', 'admin') then raise exception 'Galat app'; end if;
  if x = '' then raise exception 'Mobile / Email / Username likhein'; end if;
  if p_app = 'admin' or (p_app = 'crm' and x = 'admin') then
    if x <> 'admin' then raise exception 'Admin ke liye "admin" likhein'; end if;
    select * into a from public.crm_auth_admin where id = 1;
    return jsonb_build_object('uid', 0, 'name', 'Admin', 'role', 'admin', 'status', 'active', 'emails', jsonb_build_array(a.email), 'backup', a.email2,
      'email', a.email, 'has_pin', a.pin_hash <> '', 'pin_fail', a.pin_fail, 'q_fail', a.q_fail, 'has_q', a.q1 <> '' and a.q2 <> '', 'q1', a.q1, 'q2', a.q2, 'pin_len', 6);
  end if;
  select * into u from public.crm_users where ((p_app = 'store' and role = 'consumer') or (p_app = 'crm' and role <> 'consumer'))
    and (username = x or lower(email) = x or (length(m) = 10 and mobile = m)) order by id limit 1;
  if u.id is null then raise exception 'Ye ID nahi mili — mobile / email check karein'; end if;
  return jsonb_build_object('uid', u.id, 'name', u.name, 'role', u.role, 'status', u.status, 'emails', jsonb_build_array(u.email), 'email', u.email,
    'has_pin', u.pin_hash <> '', 'pin_fail', u.pin_fail, 'q_fail', u.q_fail, 'has_q', u.q1 <> '' and u.q2 <> '', 'q1', u.q1, 'q2', u.q2, 'pin_len', 4, 'email_ok', u.email_ok);
end $$;

create or replace function public.crm_auth_status_ok(f jsonb, p_allow_pending boolean) returns void language plpgsql immutable as $$
begin
  if f ->> 'status' = 'blocked' then raise exception 'Ye ID band hai — Admin se sampark karein'; end if;
  if f ->> 'status' = 'pending' and not p_allow_pending then raise exception 'Aapki ID abhi verify nahi hui — Admin se sampark karein'; end if;
end $$;

create or replace function public.crm_auth_backup(f jsonb, p jsonb) returns jsonb language plpgsql immutable as $$
begin
  if coalesce((p ->> 'backup')::boolean, false) then
    if coalesce(f ->> 'backup', '') = '' then raise exception 'Backup email set nahi hai'; end if;
    return f || jsonb_build_object('emails', jsonb_build_array(f ->> 'backup'));
  end if;
  return f;
end $$;

create or replace function public.crm_auth_send_otp(f jsonb, p_purpose text) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare uid bigint := (f ->> 'uid')::bigint; code text; last timestamptz; n int; tos text[];
begin
  if f ->> 'role' = 'marketing' then raise exception 'Marketing ID password se login hoti hai'; end if;
  select max(created_at), count(*) filter (where created_at > now() - interval '1 hour') into last, n from public.crm_otps where user_id = uid;
  if last is not null and last > now() - interval '40 seconds' then raise exception 'OTP abhi bheja hai — % second baad dobara maangein', 40 - floor(extract(epoch from now() - last))::int; end if;
  if n >= 6 then raise exception 'Bahut baar OTP maanga — 1 ghante baad koshish karein'; end if;
  select array_agg(e) into tos from jsonb_array_elements_text(f -> 'emails') e where e <> '';
  if tos is null then raise exception 'Is ID me email nahi hai — Admin se email judwayein'; end if;
  code := lpad((floor(random() * 1000000))::int::text, 6, '0');
  update public.crm_otps set used = true where user_id = uid and not used;
  insert into public.crm_otps(user_id, purpose, code_hash, expires_at) values (uid, p_purpose, crypt(code, gen_salt('bf')), now() + interval '10 minutes');
  perform public.crm_mail(tos, code || ' — Sunpowers login OTP',
    public.crm_mail_tpl('Aapka login OTP', 'Namaste ' || coalesce(f ->> 'name', '') || ',<br>Login ke liye ye OTP daalein:<div style="font-size:34px;font-weight:bold;letter-spacing:8px;color:#1e8e3e;margin:16px 0">' || code || '</div>Ye OTP <b>10 minute</b> tak chalega. Ise kisi ko na batayein — Sunpowers kabhi OTP nahi maangta.'));
  return jsonb_build_object('step', 'otp', 'email', (select string_agg(public.crm_mask_email(e), ', ') from unnest(tos) e), 'pin_len', f -> 'pin_len', 'name', f ->> 'name',
    'backup', case when coalesce(f ->> 'backup', '') <> '' then public.crm_mask_email(f ->> 'backup') end);
end $$;

create or replace function public.crm_auth_trusted(p_uid bigint, p_dev text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(p_dev, '') <> '' and exists (select 1 from public.crm_devices where user_id = p_uid and dev_hash = public.crm_h(p_dev)) $$;

create or replace function public.crm_auth_session(f jsonb, p_dev text, p_app text) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare uid bigint := (f ->> 'uid')::bigint; tok text := encode(gen_random_bytes(24), 'hex'); r text := f ->> 'role';
begin
  if coalesce(p_dev, '') <> '' then
    insert into public.crm_devices(user_id, dev_hash, name) values (uid, public.crm_h(p_dev), left(coalesce(f ->> 'dev_name', p_app), 80))
    on conflict (user_id, dev_hash) do update set last_seen = now();
  end if;
  if f ->> 'status' = 'pending' then return jsonb_build_object('pending', true, 'name', f ->> 'name'); end if;
  delete from public.crm_sessions where expires_at < now();
  insert into public.crm_sessions(token, user_id, role, expires_at, dev_hash)
  values (tok, uid, r, now() + case when uid = 0 then interval '12 hours' else interval '365 days' end, public.crm_h(p_dev));
  if uid = 0 then update public.crm_auth_admin set pin_fail = 0, q_fail = 0 where id = 1;
  else update public.crm_users set pin_fail = 0, q_fail = 0, last_seen = now() where id = uid; end if;
  insert into public.crm_activity(user_id, user_name, role, action, summary) values (uid, f ->> 'name', r, 'login', 'Login (' || p_app || ')');
  return jsonb_build_object('token', tok, 'uid', uid, 'role', r, 'name', f ->> 'name', 'need_q', not coalesce((f ->> 'has_q')::boolean, false), 'admin', uid = 0);
end $$;

create or replace function public.crm_auth_ticket_ok(p_uid bigint, p_ticket text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(p_ticket, '') <> '' and exists (select 1 from public.crm_otps where user_id = p_uid and ticket_hash = public.crm_h(p_ticket) and ticket_expires > now()) $$;

create or replace function public.crm_auth_mode(p jsonb) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('otp', true, 'legacy', coalesce((select (data #>> '{auth,legacy_password}')::boolean from public.crm_settings where id = 1), false)) $$;

-- 1) start: trusted device → PIN, otherwise e-mail OTP
create or replace function public.crm_auth_start(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare f jsonb := public.crm_auth_find(p ->> 'app', p ->> 'id');
begin
  perform public.crm_auth_status_ok(f, false);
  if f ->> 'role' = 'marketing' then return jsonb_build_object('step', 'password', 'name', f ->> 'name'); end if;
  if (f ->> 'has_pin')::boolean and public.crm_auth_trusted((f ->> 'uid')::bigint, p ->> 'device') and coalesce((p ->> 'otp')::boolean, false) = false then
    return jsonb_build_object('step', 'pin', 'pin_len', f -> 'pin_len', 'name', f ->> 'name', 'locked', (f ->> 'pin_fail')::int >= 5);
  end if;
  return public.crm_auth_send_otp(public.crm_auth_backup(f, p), 'login');
end $$;

create or replace function public.crm_auth_resend(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare f jsonb := public.crm_auth_find(p ->> 'app', p ->> 'id');
begin
  perform public.crm_auth_status_ok(f, true);
  return public.crm_auth_send_otp(public.crm_auth_backup(f, p), 'login');
end $$;

-- 2) verify OTP → ticket (15 min) to set / enter PIN on this device
create or replace function public.crm_auth_otp(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare f jsonb := public.crm_auth_find(p ->> 'app', p ->> 'id'); uid bigint := (f ->> 'uid')::bigint; o public.crm_otps; tk text;
begin
  perform public.crm_auth_status_ok(f, true);
  select * into o from public.crm_otps where user_id = uid and not used and expires_at > now() order by id desc limit 1;
  if o.id is null then raise exception 'OTP ka samay khatam — "Dobara bhejein" dabayein'; end if;
  if o.tries >= 5 then raise exception 'Bahut baar galat OTP — naya OTP maangein'; end if;
  if crypt(regexp_replace(coalesce(p ->> 'code', ''), '\D', '', 'g'), o.code_hash) <> o.code_hash then
    update public.crm_otps set tries = tries + 1 where id = o.id;
    perform pg_sleep(0.5);
    return jsonb_build_object('error', case when o.tries >= 4 then 'Bahut baar galat OTP — naya OTP maangein' else 'OTP galat hai' end);
  end if;
  tk := encode(gen_random_bytes(24), 'hex');
  update public.crm_otps set used = true, ticket_hash = public.crm_h(tk), ticket_expires = now() + interval '15 minutes' where id = o.id;
  if uid <> 0 then update public.crm_users set email_ok = true where id = uid; end if;
  return jsonb_build_object('ticket', tk, 'has_pin', f -> 'has_pin', 'has_q', f -> 'has_q', 'pin_len', f -> 'pin_len', 'name', f ->> 'name', 'locked', (f ->> 'pin_fail')::int >= 5);
end $$;

-- master password (Admin only) instead of e-mail OTP — emergency when e-mail is not working
create or replace function public.crm_auth_master(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare f jsonb := public.crm_auth_find(p ->> 'app', p ->> 'id'); h text; tk text; recent int;
begin
  if (f ->> 'uid')::bigint <> 0 then raise exception 'Ye sirf Admin ke liye hai'; end if;
  select count(*) into recent from public.crm_activity where action = 'master_fail' and at > now() - interval '1 hour';
  if recent >= 5 then raise exception 'Bahut baar galat — 1 ghante baad koshish karein'; end if;
  select pass_hash into h from public.sp_admin where id = 1;
  if h is null or crypt(coalesce(p ->> 'password', ''), h) <> h then
    insert into public.crm_activity(user_id, user_name, role, action, summary) values (0, 'Admin', 'admin', 'master_fail', 'Master password galat');
    perform pg_sleep(1); return jsonb_build_object('error', 'Master password galat hai');
  end if;
  tk := encode(gen_random_bytes(24), 'hex');
  insert into public.crm_otps(user_id, purpose, code_hash, expires_at, used, ticket_hash, ticket_expires) values (0, 'master', '', now(), true, public.crm_h(tk), now() + interval '15 minutes');
  return jsonb_build_object('ticket', tk, 'has_pin', f -> 'has_pin', 'has_q', f -> 'has_q', 'pin_len', 6, 'name', 'Admin', 'locked', (f ->> 'pin_fail')::int >= 5);
end $$;

drop function if exists public.crm_auth_pin_check(jsonb, text);
create or replace function public.crm_auth_pin_check(f jsonb, p_pin text) returns text language plpgsql security definer set search_path = public, extensions as $$
-- returns NULL when the PIN is right, otherwise the error text (counters must not be rolled back, so no exception here)
declare uid bigint := (f ->> 'uid')::bigint; h text; fails int;
begin
  if uid = 0 then select pin_hash, pin_fail into h, fails from public.crm_auth_admin where id = 1;
  else select pin_hash, pin_fail into h, fails from public.crm_users where id = uid; end if;
  if coalesce(h, '') = '' then return 'PIN abhi bana nahi hai'; end if;
  if fails >= 5 then return 'PIN lock ho gaya. "PIN bhool gaye?" se naya PIN banayein'; end if;
  if crypt(coalesce(p_pin, ''), h) <> h then
    if uid = 0 then update public.crm_auth_admin set pin_fail = pin_fail + 1 where id = 1; else update public.crm_users set pin_fail = pin_fail + 1 where id = uid; end if;
    perform pg_sleep(0.6);
    if fails + 1 >= 5 then return 'PIN lock ho gaya. "PIN bhool gaye?" se naya PIN banayein'; end if;
    return 'PIN galat hai';
  end if;
  return null;
end $$;