-- =====================================================================
--  SUNPOWERS CRM — Supabase setup
--  1) Pehle Online Store wala setup.sql chal chuka ho (admin password wahi rahega)
--  2) Ye file Supabase → SQL Editor me paste karke Run karein. Dobara chalane se data nahi mitta.
--  Admin login: username "admin" + Store Admin wala password
-- =====================================================================

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------- tables
create table if not exists public.crm_users (
  id          bigserial primary key,
  role        text not null check (role in ('admin','manager','staff','dealer','influencer','consumer')),
  username    text not null unique,
  name        text not null,
  mobile      text not null default '',
  email       text not null default '',
  pass_hash   text not null,
  q1 text not null default '', a1 text not null default '',
  q2 text not null default '', a2 text not null default '',
  status      text not null default 'active' check (status in ('active','pending','blocked')),
  ref_code    text unique,
  perms       jsonb not null default '{}'::jsonb,
  meta        jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  last_seen   timestamptz
);
create table if not exists public.crm_sessions (
  token       text primary key,
  user_id     bigint not null,
  role        text not null,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null
);
create table if not exists public.crm_roles (
  role   text primary key,
  perms  jsonb not null default '{}'::jsonb
);
create table if not exists public.crm_records (
  id            bigserial primary key,
  kind          text not null,
  ref           text,
  title         text not null default '',
  mobile        text,
  status        text not null default '',
  owner_id      bigint not null default 0,
  assigned_to   bigint,
  party_id      bigint,
  amount        numeric(14,2) not null default 0,
  due_at        date,
  data          jsonb not null default '{}'::jsonb,
  search        text not null default '',
  created_by    bigint,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  deleted_by    bigint,
  delete_reason text
);
create index if not exists crm_rec_kind on public.crm_records(kind) where deleted_at is null;
create index if not exists crm_rec_owner on public.crm_records(owner_id);
create index if not exists crm_rec_assigned on public.crm_records(assigned_to);
create index if not exists crm_rec_party on public.crm_records(party_id);
create index if not exists crm_rec_mobile on public.crm_records(mobile);
create index if not exists crm_rec_due on public.crm_records(due_at);
create unique index if not exists crm_party_mobile_uq on public.crm_records(mobile) where kind = 'party' and deleted_at is null and mobile is not null and mobile <> '';

create table if not exists public.crm_files (
  id      bigserial primary key,
  rec_id  bigint not null,
  mime    text not null default 'application/octet-stream',
  size    int not null default 0,
  data    bytea not null
);
create index if not exists crm_files_rec on public.crm_files(rec_id);
create table if not exists public.crm_counters (
  key text primary key,
  n   int not null default 0
);
create table if not exists public.crm_activity (
  id        bigserial primary key,
  at        timestamptz not null default now(),
  user_id   bigint,
  user_name text,
  role      text,
  action    text not null,
  kind      text,
  rec_id    bigint,
  summary   text
);
create index if not exists crm_act_at on public.crm_activity(at desc);
create index if not exists crm_act_user on public.crm_activity(user_id);
create table if not exists public.crm_settings (
  id       int primary key default 1 check (id = 1),
  data     jsonb not null default '{}'::jsonb,
  secrets  jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
insert into public.crm_settings(id) values (1) on conflict (id) do nothing;

alter table public.crm_users    enable row level security;
alter table public.crm_sessions enable row level security;
alter table public.crm_roles    enable row level security;
alter table public.crm_records  enable row level security;
alter table public.crm_files    enable row level security;
alter table public.crm_counters enable row level security;
alter table public.crm_activity enable row level security;
alter table public.crm_settings enable row level security;
do $$ begin
  revoke all on public.crm_users, public.crm_sessions, public.crm_roles, public.crm_records, public.crm_files,
    public.crm_counters, public.crm_activity, public.crm_settings from anon, authenticated;
exception when undefined_object then null; end $$;

do $$ begin
  create type public.crm_ses as (uid bigint, role text, name text, perms jsonb, ref text, mobile text);
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------- permission catalog + role defaults
create or replace function public.crm_perm_catalog() returns jsonb language sql immutable as $$
select '[
 {"g":"Customers","k":"customers.view_all","l":"Sabke customers dekhe"},
 {"g":"Customers","k":"customers.create","l":"Customer jode"},
 {"g":"Customers","k":"customers.edit","l":"Customer badle"},
 {"g":"Customers","k":"customers.delete","l":"Customer hataye"},
 {"g":"Customers","k":"customers.assign","l":"Customer kisi aur ko de"},
 {"g":"Customers","k":"customers.export","l":"Customers Excel nikale"},
 {"g":"Products","k":"items.view","l":"Products / Projects dekhe"},
 {"g":"Products","k":"items.create","l":"Product / Project jode"},
 {"g":"Products","k":"items.edit","l":"Product / Project badle"},
 {"g":"Products","k":"items.delete","l":"Product / Project hataye"},
 {"g":"Products","k":"items.categories","l":"Nayi category / sub-category jode ya naam badle"},
 {"g":"Products","k":"items.cost","l":"Kharid rate aur minimum rate dekhe"},
 {"g":"Products","k":"items.to_store","l":"Online Store ko bheje"},
 {"g":"Products","k":"stock.reserve","l":"Stock reserve / hold kare (direct, online, anya)"},
 {"g":"Products","k":"stock.override","l":"Stock kam hone par bhi quotation banaye (Admin jaisa)"},
 {"g":"Quotation","k":"quotes.view_all","l":"Sabki quotation dekhe"},
 {"g":"Quotation","k":"quotes.create","l":"Quotation banaye"},
 {"g":"Quotation","k":"quotes.edit","l":"Quotation badle"},
 {"g":"Quotation","k":"quotes.delete","l":"Quotation hataye"},
 {"g":"Quotation","k":"quotes.discount_any","l":"Discount limit se upar de sake"},
 {"g":"Billing","k":"invoices.view_all","l":"Sabke bill dekhe"},
 {"g":"Billing","k":"invoices.create","l":"Bill banaye"},
 {"g":"Billing","k":"invoices.edit","l":"Bill badle"},
 {"g":"Billing","k":"invoices.delete","l":"Bill hataye"},
 {"g":"Billing","k":"payments.record","l":"Payment jode"},
 {"g":"Billing","k":"payments.delete","l":"Payment hataye"},
 {"g":"Billing","k":"purchase.manage","l":"Purchase order banaye"},
 {"g":"Leads","k":"leads.view_all","l":"Sabki leads dekhe"},
 {"g":"Leads","k":"leads.create","l":"Lead jode"},
 {"g":"Leads","k":"leads.import","l":"Leads import kare"},
 {"g":"Leads","k":"leads.assign","l":"Leads kisi ko de (company leads)"},
 {"g":"Leads","k":"leads.delete","l":"Lead hataye"},
 {"g":"Leads","k":"leads.export","l":"Leads Excel nikale"},
 {"g":"Reminders","k":"reminders.view_all","l":"Sabke reminder dekhe"},
 {"g":"Reminders","k":"reminders.assign","l":"Doosron ko kaam / reminder de"},
 {"g":"Plants","k":"plants.view_all","l":"Saare plants dekhe"},
 {"g":"Plants","k":"plants.create","l":"Plant jode"},
 {"g":"Plants","k":"plants.verify","l":"Plant verify kare"},
 {"g":"Plants","k":"plants.delete","l":"Plant hataye"},
 {"g":"Commission","k":"earnings.view_all","l":"Sabka commission dekhe"},
 {"g":"Commission","k":"earnings.manage","l":"Commission jode / paid kare"},
 {"g":"Documents","k":"docs.view","l":"Documents dekhe"},
 {"g":"Documents","k":"docs.upload","l":"Document upload kare"},
 {"g":"Documents","k":"docs.folders","l":"Folder banaye / lock kare"},
 {"g":"Documents","k":"docs.delete","l":"Kisi ka bhi document hataye"},
 {"g":"Orders","k":"orders.view","l":"Store ke order + website enquiry dekhe"},
 {"g":"Orders","k":"orders.manage","l":"Order / enquiry ka status badle"},
 {"g":"Team","k":"team.stats","l":"Team ka kaam (performance) dekhe"},
 {"g":"Team","k":"users.manage","l":"Users + permission sambhale"},
 {"g":"Admin","k":"settings.manage","l":"Company settings badle"},
 {"g":"Admin","k":"activity.view","l":"Activity record dekhe"},
 {"g":"Admin","k":"reports.view","l":"Reports dekhe"},
 {"g":"Privacy","k":"privacy.see_mobile","l":"Customer ka poora mobile number dekhe"},
 {"g":"Marketing","k":"marketing.view","l":"Marketing & Grow section dekhe"},
 {"g":"Marketing","k":"marketing.manage","l":"Marketing channels / agency badle"},
 {"g":"Marketing","k":"marketing.leads","l":"Lead kahan se aayi (source report) dekhe"}
]'::jsonb $$;

insert into public.crm_roles(role, perms) values
 ('manager', '{"customers.view_all":true,"customers.create":true,"customers.edit":true,"customers.assign":true,"customers.export":true,"items.view":true,"items.create":true,"items.edit":true,"items.cost":true,"items.to_store":true,"items.categories":true,"stock.reserve":true,"quotes.view_all":true,"quotes.create":true,"quotes.edit":true,"invoices.view_all":true,"invoices.create":true,"invoices.edit":true,"payments.record":true,"purchase.manage":true,"leads.view_all":true,"leads.create":true,"leads.import":true,"leads.assign":true,"leads.export":true,"reminders.view_all":true,"reminders.assign":true,"plants.view_all":true,"plants.create":true,"plants.verify":true,"earnings.view_all":true,"docs.view":true,"docs.upload":true,"docs.folders":true,"orders.view":true,"orders.manage":true,"team.stats":true,"reports.view":true,"privacy.see_mobile":true}'),
 ('staff', '{"customers.create":true,"customers.edit":true,"items.view":true,"quotes.create":true,"quotes.edit":true,"invoices.create":true,"payments.record":true,"leads.create":true,"leads.import":true,"plants.create":true,"docs.view":true,"docs.upload":true,"orders.view":true,"privacy.see_mobile":true}'),
 ('dealer', '{"customers.create":true,"customers.edit":true,"items.view":true,"quotes.create":true,"quotes.edit":true,"leads.create":true,"leads.import":true,"plants.create":true,"docs.view":true,"privacy.see_mobile":true}'),
 ('influencer', '{"customers.create":true,"items.view":true,"quotes.create":true,"leads.create":true,"leads.import":true,"plants.create":true,"docs.view":true,"privacy.see_mobile":true}'),
 ('consumer', '{}')
on conflict (role) do nothing;

-- ---------------------------------------------------------------- helpers
create or replace function public.crm_mobile(p text) returns text language sql immutable as $$
  select case when length(d) = 12 and left(d, 2) = '91' then right(d, 10) when length(d) = 11 and left(d, 1) = '0' then right(d, 10) else d end
  from (select regexp_replace(coalesce(p, ''), '\D', '', 'g') d) x;
$$;
create or replace function public.crm_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Kolkata')::date $$;
create or replace function public.crm_fy(d date) returns text language sql immutable as $$
  select case when extract(month from d) >= 4 then to_char(d, 'YY') || '-' || to_char(d + interval '1 year', 'YY')
              else to_char(d - interval '1 year', 'YY') || '-' || to_char(d, 'YY') end $$;
create or replace function public.crm_num(v jsonb) returns numeric language sql immutable as $$
  select case when v is null then 0 when jsonb_typeof(v) = 'number' then (v #>> '{}')::numeric
              when jsonb_typeof(v) = 'string' and (v #>> '{}') ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' then trim(v #>> '{}')::numeric else 0 end $$;
create or replace function public.crm_err(msg text) returns void language plpgsql as $$ begin raise exception '%', msg; end $$;

create or replace function public.crm_session(p_token text) returns public.crm_ses
language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses; se record; u public.crm_users; rp jsonb;
begin
  select * into se from public.crm_sessions where token = coalesce(p_token, '') and expires_at > now();
  if se.token is null then raise exception 'Login expired — dobara login karein'; end if;
  if se.role = 'consumer' then raise exception 'Ye login sirf Online Store ke liye hai'; end if;
  if se.user_id <> 0 and se.expires_at < now() + interval '330 days' then update public.crm_sessions set expires_at = now() + interval '365 days' where token = se.token; end if;
  if se.user_id = 0 then
    s := row(0::bigint, 'admin', 'Admin', '{"*":true}'::jsonb, null::text, null::text)::public.crm_ses; return s;
  end if;
  select * into u from public.crm_users where id = se.user_id;
  if u.id is null or u.status <> 'active' then raise exception 'Account active nahi hai — Admin se sampark karein'; end if;
  select perms into rp from public.crm_roles where role = u.role;
  s := row(u.id, u.role, u.name, coalesce(rp, '{}'::jsonb) || coalesce(u.perms, '{}'::jsonb), u.ref_code, u.mobile)::public.crm_ses;
  if u.role = 'admin' then s.perms := '{"*":true}'::jsonb; end if;
  if u.last_seen is null or u.last_seen < now() - interval '5 minutes' then update public.crm_users set last_seen = now() where id = u.id; end if;
  return s;
end $$;

create or replace function public.crm_can(s public.crm_ses, k text) returns boolean language sql immutable as $$
  select coalesce((s).perms ? '*', false) or coalesce(((s).perms ->> k)::boolean, false) $$;
create or replace function public.crm_is_admin(s public.crm_ses) returns boolean language sql immutable as $$ select coalesce((s).perms ? '*', false) $$;

create or replace function public.crm_need(s public.crm_ses, k text) returns void language plpgsql as $$
begin if not public.crm_can(s, k) then raise exception 'Aapko is kaam ki permission nahi hai'; end if; end $$;

create or replace function public.crm_uname(p_id bigint) returns text language sql stable security definer set search_path = public as $$
  select case when p_id is null then null when p_id = 0 then 'Company' else (select name from public.crm_users where id = p_id) end $$;

create or replace function public.crm_log(s public.crm_ses, p_action text, p_kind text, p_rec bigint, p_summary text) returns void
language sql security definer set search_path = public as $$
  insert into public.crm_activity(user_id, user_name, role, action, kind, rec_id, summary)
  values ((s).uid, (s).name, (s).role, p_action, p_kind, p_rec, left(coalesce(p_summary, ''), 300));
$$;

create or replace function public.crm_folder_ok(s public.crm_ses, p_fid bigint) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare f public.crm_records; fid bigint := p_fid; i int := 0;
begin
  if public.crm_is_admin(s) then return true; end if;
  while fid is not null and fid > 0 and i < 15 loop
    select * into f from public.crm_records where id = fid and kind = 'folder' and deleted_at is null;
    if f.id is null then return true; end if;
    if coalesce((f.data ->> 'locked')::boolean, false) then
      if not (coalesce(f.data -> 'roles', '[]'::jsonb) ? (s).role or coalesce(f.data -> 'users', '[]'::jsonb) @> to_jsonb((s).uid)) then return false; end if;
    end if;
    fid := nullif(f.data ->> 'parent_id', '')::bigint; i := i + 1;
  end loop;
  return true;
end $$;

create or replace function public.crm_vis(s public.crm_ses, r public.crm_records) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare vk text;
begin
  if r.id is null or r.deleted_at is not null then return false; end if;
  if public.crm_is_admin(s) then return true; end if;
  if r.kind = 'item' then return public.crm_can(s, 'items.view'); end if;
  if r.kind = 'folder' then return public.crm_can(s, 'docs.view') and public.crm_folder_ok(s, r.id); end if;
  if r.kind = 'doc' and coalesce(r.data ->> 'attach_kind', '') <> '' then
    if r.owner_id = (s).uid then return true; end if;
    if r.party_id is null then return false; end if;
    return exists (select 1 from public.crm_records p where p.id = r.party_id and p.kind = 'party' and p.deleted_at is null and (public.crm_can(s, 'customers.view_all') or p.owner_id = (s).uid or p.assigned_to = (s).uid));
  end if;
  if r.kind = 'doc' then return (public.crm_can(s, 'docs.view') or r.owner_id = (s).uid) and public.crm_folder_ok(s, nullif(r.data ->> 'folder_id', '')::bigint); end if;
  if r.kind = 'notice' then return true; end if;
  vk := case r.kind when 'party' then 'customers.view_all' when 'quote' then 'quotes.view_all' when 'invoice' then 'invoices.view_all'
          when 'payment' then 'invoices.view_all' when 'purchase' then 'purchase.manage' when 'lead' then 'leads.view_all'
          when 'reminder' then 'reminders.view_all' when 'plant' then 'plants.view_all' when 'earning' then 'earnings.view_all' when 'note' then 'customers.view_all' else null end;
  if vk is not null and public.crm_can(s, vk) then return true; end if;
  if r.owner_id = (s).uid or r.assigned_to = (s).uid then return true; end if;
  if r.kind in ('earning', 'lead', 'reminder', 'note', 'purchase') then return false; end if;
  if r.party_id is not null and exists (select 1 from public.crm_records p where p.id = r.party_id and p.kind = 'party' and p.deleted_at is null and (p.owner_id = (s).uid or p.assigned_to = (s).uid)) then return true; end if;
  if r.kind = 'plant' and (s).ref is not null and upper(coalesce(r.data ->> 'ref', '')) = (s).ref then return true; end if;
  return false;
end $$;

create or replace function public.crm_row(s public.crm_ses, r public.crm_records) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare j jsonb;
begin
  j := to_jsonb(r) - 'search' - 'deleted_at' - 'deleted_by' - 'delete_reason';
  j := j || jsonb_build_object('owner_name', public.crm_uname(r.owner_id), 'assigned_name', public.crm_uname(r.assigned_to));
  if r.kind = 'item' and not public.crm_can(s, 'items.cost') then j := jsonb_set(j, '{data}', (r.data - 'cost_price' - 'min_price')); end if;
  if r.party_id is not null and r.kind <> 'party' then
    j := j || jsonb_build_object('party_name', (select title from public.crm_records where id = r.party_id));
  end if;
  if r.kind in ('party', 'lead') and not public.crm_can(s, 'privacy.see_mobile') and r.owner_id <> (s).uid and coalesce(r.assigned_to, -1) <> (s).uid and coalesce(r.mobile, '') <> '' then
    j := j || jsonb_build_object('mobile', left(r.mobile, 2) || '******' || right(r.mobile, 2));
  end if;
  return j;
end $$;

create or replace function public.crm_next_no(p_kind text) returns text
language plpgsql security definer set search_path = public as $$
declare pre text; fy text := public.crm_fy(public.crm_today()); k text; n int; st jsonb;
begin
  select data into st from public.crm_settings where id = 1;
  pre := coalesce(nullif(st #>> array['prefix', p_kind], ''),
    case p_kind when 'quote' then 'QT' when 'invoice' then 'INV' when 'payment' then 'RCPT' when 'purchase' then 'PO' when 'plant' then 'PL' else upper(left(p_kind, 3)) end);
  k := p_kind || ':' || fy;
  insert into public.crm_counters(key, n) values (k, 1) on conflict (key) do update set n = public.crm_counters.n + 1 returning public.crm_counters.n into n;
  return pre || '/' || fy || '/' || lpad(n::text, 4, '0');
end $$;

-- totals of a quotation / invoice / purchase
create or replace function public.crm_doc_calc(d jsonb) returns jsonb language plpgsql immutable as $$
declare l jsonb; sub numeric := 0; g numeric := 0; q numeric; pr numeric; disc numeric;
begin
  for l in select * from jsonb_array_elements(coalesce(d -> 'lines', '[]'::jsonb)) loop
    q := greatest(public.crm_num(l -> 'qty'), 0); pr := greatest(public.crm_num(l -> 'price'), 0);
    sub := sub + q * pr; g := g + q * pr * greatest(public.crm_num(l -> 'gst'), 0) / 100;
  end loop;
  disc := greatest(public.crm_num(d -> 'discount'), 0);
  return jsonb_build_object('subtotal', round(sub, 2), 'gst_total', round(g, 2), 'discount', round(disc, 2), 'grand', round(sub + g - disc, 2));
end $$;

-- stock move for product lines (sign -1 = sale, +1 = return / purchase received)
create or replace function public.crm_stock(d jsonb, sgn int) returns void language plpgsql security definer set search_path = public as $$
declare l jsonb; x jsonb; iid bigint;
begin
  for l in select * from jsonb_array_elements(coalesce(d -> 'lines', '[]'::jsonb)) loop
    if coalesce(l ->> 'kind', 'product') = 'project' then
      for x in select * from jsonb_array_elements(coalesce(l -> 'proj_items', '[]'::jsonb)) loop
        iid := nullif(x ->> 'item_id', '')::bigint;
        if iid is not null then update public.crm_records set data = jsonb_set(data, '{stock}', to_jsonb(public.crm_num(data -> 'stock') + sgn * public.crm_num(x -> 'qty') * greatest(public.crm_num(l -> 'qty'), 1))) where id = iid and kind = 'item' and data ? 'stock'; end if;
      end loop;
    else
      iid := nullif(l ->> 'item_id', '')::bigint;
      if iid is not null then update public.crm_records set data = jsonb_set(data, '{stock}', to_jsonb(public.crm_num(data -> 'stock') + sgn * public.crm_num(l -> 'qty'))) where id = iid and kind = 'item' and data ? 'stock'; end if;
    end if;
  end loop;
end $$;

create or replace function public.crm_inv_recalc(p_inv bigint) returns void language plpgsql security definer set search_path = public as $$
declare paid numeric; tot numeric;
begin
  select coalesce(sum(amount), 0) into paid from public.crm_records where kind = 'payment' and deleted_at is null and (data ->> 'invoice_id') = p_inv::text;
  select amount into tot from public.crm_records where id = p_inv;
  update public.crm_records set data = data || jsonb_build_object('paid', paid, 'balance', greatest(tot - paid, 0)),
    status = case when tot - paid <= 0.009 then 'paid' when paid > 0 then 'partial' else 'due' end, updated_at = now()
  where id = p_inv and kind = 'invoice';
end $$;

-- commission for a verified plant
create or replace function public.crm_commission(p_plant bigint, s public.crm_ses) returns void language plpgsql security definer set search_path = public as $$
declare pl public.crm_records; u public.crm_users; rule jsonb; amt numeric := 0; kw numeric; ex bigint;
begin
  select * into pl from public.crm_records where id = p_plant;
  select * into u from public.crm_users where id = pl.owner_id and role in ('dealer', 'influencer', 'staff', 'manager');
  if u.id is null and coalesce(pl.data ->> 'ref', '') <> '' then select * into u from public.crm_users where ref_code = upper(pl.data ->> 'ref'); end if;
  select id into ex from public.crm_records where kind = 'earning' and deleted_at is null and (data ->> 'plant_id') = p_plant::text limit 1;
  if pl.status <> 'verified' or u.id is null then
    if ex is not null then update public.crm_records set deleted_at = now(), delete_reason = 'Plant verified nahi' where id = ex and status <> 'paid'; end if;
    return;
  end if;
  if ex is not null then return; end if;
  rule := coalesce(u.meta -> 'commission', '{}'::jsonb); kw := public.crm_num(pl.data -> 'kw');
  amt := case rule ->> 'mode' when 'per_kw' then public.crm_num(rule -> 'value') * kw
                               when 'fixed' then public.crm_num(rule -> 'value')
                               when 'percent' then public.crm_num(rule -> 'value') * public.crm_num(pl.data -> 'deal_value') / 100 else 0 end;
  if amt <= 0 then return; end if;
  insert into public.crm_records(kind, title, status, owner_id, party_id, amount, data, created_by, search)
  values ('earning', 'Commission — ' || pl.title, 'due', u.id, pl.party_id, round(amt, 2),
    jsonb_build_object('plant_id', pl.id, 'kw', kw, 'rule', rule, 'auto', true, 'date', public.crm_today()), (s).uid, lower(pl.title));
  perform public.crm_log(s, 'commission', 'earning', p_plant, 'Commission ' || round(amt, 2) || ' → ' || u.name);
end $$;

-- ---------------------------------------------------------------- accounts
create or replace function public.crm_register(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r text := lower(coalesce(p ->> 'role', '')); un text := lower(trim(coalesce(p ->> 'username', ''))); m text := public.crm_mobile(p ->> 'mobile');
        st text; code text; i int := 0;
begin
  perform public.crm_legacy();
  if r not in ('dealer', 'influencer', 'consumer') then raise exception 'Is role ki ID sirf Admin bana sakta hai'; end if;
  if m !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein'; end if;
  if r = 'consumer' and un = '' then un := m; end if;
  if un !~ '^[a-z0-9_.@-]{3,40}$' then raise exception 'Username 3-40 akshar ka ho (a-z, 0-9, _ . - @)'; end if;
  if un = 'admin' then raise exception 'Ye username nahi le sakte'; end if;
  if length(coalesce(p ->> 'password', '')) < 6 then raise exception 'Password kam se kam 6 akshar ka ho'; end if;
  if coalesce(trim(p ->> 'name'), '') = '' then raise exception 'Naam likhein'; end if;
  if coalesce(p ->> 'q1', '') = '' or coalesce(p ->> 'q2', '') = '' or p ->> 'q1' = p ->> 'q2' or coalesce(trim(p ->> 'a1'), '') = '' or coalesce(trim(p ->> 'a2'), '') = '' then
    raise exception '2 alag security sawal aur unke jawab zaroori hain'; end if;
  if exists (select 1 from public.crm_users where username = un) then raise exception 'Ye username pehle se liya hua hai'; end if;
  if r = 'consumer' and exists (select 1 from public.crm_users where role = 'consumer' and mobile = m) then raise exception 'Is mobile se ID pehle se bani hai — login karein'; end if;
  st := case when r = 'consumer' then 'active' else 'pending' end;
  if r in ('dealer', 'influencer') then
    loop code := upper(left(r, 1)) || 'SP' || (100000 + floor(random() * 900000))::int::text;
      exit when not exists (select 1 from public.crm_users where ref_code = code); i := i + 1; if i > 20 then raise exception 'Dobara koshish karein'; end if; end loop;
  end if;
  insert into public.crm_users(role, username, name, mobile, email, pass_hash, q1, a1, q2, a2, status, ref_code)
  values (r, un, left(trim(p ->> 'name'), 80), m, left(coalesce(p ->> 'email', ''), 120), crypt(p ->> 'password', gen_salt('bf')),
    left(p ->> 'q1', 120), crypt(lower(trim(p ->> 'a1')), gen_salt('bf')), left(p ->> 'q2', 120), crypt(lower(trim(p ->> 'a2')), gen_salt('bf')), st, code);
  insert into public.crm_activity(user_id, user_name, role, action, summary) values (null, trim(p ->> 'name'), r, 'register', 'Nayi ID: ' || un);
  return jsonb_build_object('username', un, 'status', st, 'ref_code', code);
end $$;

create or replace function public.crm_login(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u public.crm_users; tok text; h text; x text := lower(trim(coalesce(p ->> 'user', ''))); pw text := coalesce(p ->> 'pass', ''); wantc boolean := coalesce((p ->> 'consumer')::boolean, false);
begin
  perform public.crm_legacy();
  delete from public.crm_sessions where expires_at < now();
  if x = 'admin' and not wantc then
    select pass_hash into h from public.sp_admin where id = 1;
    if h is null or crypt(pw, h) <> h then perform pg_sleep(1); raise exception 'Galat username ya password'; end if;
    tok := encode(gen_random_bytes(24), 'hex');
    insert into public.crm_sessions(token, user_id, role, expires_at) values (tok, 0, 'admin', now() + interval '12 hours');
    insert into public.crm_activity(user_id, user_name, role, action, summary) values (0, 'Admin', 'admin', 'login', 'Admin login');
    return jsonb_build_object('token', tok, 'id', 0, 'role', 'admin', 'name', 'Admin', 'username', 'admin');
  end if;
  select * into u from public.crm_users where (username = x or (mobile = public.crm_mobile(x) and length(public.crm_mobile(x)) = 10))
    and ((wantc and role = 'consumer') or (not wantc and role <> 'consumer')) order by id limit 1;
  if u.id is null or coalesce(u.pass_hash, '') = '' or crypt(pw, u.pass_hash) <> u.pass_hash then perform pg_sleep(1); raise exception 'Galat username ya password'; end if;
  if u.status = 'pending' then raise exception 'Aapki ID abhi verify nahi hui — Admin se sampark karein'; end if;
  if u.status <> 'active' then raise exception 'Ye ID band hai — Admin se sampark karein'; end if;
  tok := encode(gen_random_bytes(24), 'hex');
  insert into public.crm_sessions(token, user_id, role, expires_at) values (tok, u.id, u.role, now() + interval '30 days');
  update public.crm_users set last_seen = now() where id = u.id;
  insert into public.crm_activity(user_id, user_name, role, action, summary) values (u.id, u.name, u.role, 'login', 'Login');
  return jsonb_build_object('token', tok, 'id', u.id, 'role', u.role, 'name', u.name, 'username', u.username, 'mobile', u.mobile, 'ref_code', u.ref_code);
end $$;

create or replace function public.crm_logout(p jsonb) returns jsonb language sql security definer set search_path = public as $$
  with d as (delete from public.crm_sessions where token = p ->> 'token' returning 1) select jsonb_build_object('ok', true) $$;

create or replace function public.crm_me(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); u public.crm_users;
begin
  select * into u from public.crm_users where id = (s).uid;
  return jsonb_build_object('id', (s).uid, 'role', (s).role, 'name', (s).name, 'perms', (s).perms, 'ref_code', (s).ref, 'mobile', (s).mobile,
    'username', case when (s).uid = 0 then 'admin' else u.username end, 'email', u.email, 'meta', coalesce(u.meta, '{}'::jsonb), 'catalog', public.crm_perm_catalog());
end $$;

create or replace function public.crm_questions(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users; x text := lower(trim(coalesce(p ->> 'user', '')));
begin
  perform public.crm_legacy();
  select * into u from public.crm_users where (username = x or mobile = public.crm_mobile(x)) and (coalesce((p ->> 'consumer')::boolean, false) = (role = 'consumer')) and q1 <> '' order by id limit 1;
  if u.id is null then perform pg_sleep(1); raise exception 'Ye username nahi mila'; end if;
  return jsonb_build_object('q1', u.q1, 'q2', u.q2);
end $$;

create or replace function public.crm_reset(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u public.crm_users; x text := lower(trim(coalesce(p ->> 'user', '')));
begin
  perform public.crm_legacy();
  select * into u from public.crm_users where (username = x or mobile = public.crm_mobile(x)) and (coalesce((p ->> 'consumer')::boolean, false) = (role = 'consumer')) and q1 <> '' order by id limit 1;
  if u.id is null or crypt(lower(trim(coalesce(p ->> 'a1', ''))), u.a1) <> u.a1 or crypt(lower(trim(coalesce(p ->> 'a2', ''))), u.a2) <> u.a2 then
    perform pg_sleep(1); raise exception 'Jawab sahi nahi hain'; end if;
  if length(coalesce(p ->> 'new', '')) < 6 then raise exception 'Naya password kam se kam 6 akshar ka ho'; end if;
  update public.crm_users set pass_hash = crypt(p ->> 'new', gen_salt('bf')) where id = u.id;
  delete from public.crm_sessions where user_id = u.id;
  insert into public.crm_activity(user_id, user_name, role, action, summary) values (u.id, u.name, u.role, 'password', 'Password reset (security sawal)');
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.crm_password(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); h text;
begin
  perform public.crm_legacy();
  if (s).uid = 0 then raise exception 'Admin password Online Store Admin → Settings se badlein'; end if;
  select pass_hash into h from public.crm_users where id = (s).uid;
  if crypt(coalesce(p ->> 'old', ''), h) <> h then perform pg_sleep(1); raise exception 'Purana password galat hai'; end if;
  if length(coalesce(p ->> 'new', '')) < 6 then raise exception 'Naya password kam se kam 6 akshar ka ho'; end if;
  update public.crm_users set pass_hash = crypt(p ->> 'new', gen_salt('bf')) where id = (s).uid;
  perform public.crm_log(s, 'password', null, null, 'Password badla');
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------- users / roles (admin)
create or replace function public.crm_users_list(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); full_ boolean;
begin
  full_ := public.crm_can(s, 'users.manage');
  if not full_ and not (public.crm_can(s, 'leads.assign') or public.crm_can(s, 'reminders.assign') or public.crm_can(s, 'customers.assign') or public.crm_can(s, 'earnings.manage') or public.crm_can(s, 'team.stats') or public.crm_can(s, 'docs.folders')) then
    return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(case when full_ then jsonb_build_object('id', id, 'role', role, 'username', username, 'name', name, 'mobile', mobile, 'email', email, 'status', status,
      'ref_code', ref_code, 'perms', perms, 'meta', meta, 'created_at', created_at, 'last_seen', last_seen)
    else jsonb_build_object('id', id, 'role', role, 'name', name, 'status', status, 'ref_code', ref_code) end order by role, name)
    from public.crm_users where role <> 'consumer' or full_), '[]'::jsonb);
end $$;

create or replace function public.crm_user_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); u public.crm_users; d jsonb := coalesce(p -> 'user', '{}'::jsonb); id_ bigint := nullif(d ->> 'id', '')::bigint;
        r text := lower(coalesce(d ->> 'role', '')); un text := lower(trim(coalesce(d ->> 'username', ''))); m text := public.crm_mobile(d ->> 'mobile'); code text; i int := 0;
begin
  perform public.crm_need(s, 'users.manage');
  if r <> '' and r not in ('admin', 'manager', 'staff', 'dealer', 'influencer', 'consumer', 'marketing') then raise exception 'Role galat hai'; end if;
  if r = 'admin' and not public.crm_is_admin(s) then raise exception 'Admin role sirf Admin de sakta hai'; end if;
  if id_ is null then
    if un !~ '^[a-z0-9_.@-]{3,40}$' or un = 'admin' then raise exception 'Username 3-40 akshar ka ho (a-z, 0-9, _ . - @)'; end if;
    if exists (select 1 from public.crm_users where username = un) then raise exception 'Ye username pehle se liya hua hai'; end if;
    if coalesce(d ->> 'password', '') <> '' and length(d ->> 'password') < 6 then raise exception 'Password kam se kam 6 akshar ka ho'; end if;
    if coalesce(trim(d ->> 'name'), '') = '' then raise exception 'Naam likhein'; end if;
    if coalesce(d ->> 'password', '') = '' and lower(trim(coalesce(d ->> 'email', ''))) !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Sahi email likhein — login ka OTP isi par jayega'; end if;
    if coalesce(d ->> 'email', '') <> '' and exists (select 1 from public.crm_users where lower(email) = lower(trim(d ->> 'email')) and role <> 'consumer') then raise exception 'Ye email pehle se kisi aur user ka hai'; end if;
    if r = '' then raise exception 'Role chunein'; end if;
    if r in ('dealer', 'influencer') then
      loop code := upper(left(r, 1)) || 'SP' || (100000 + floor(random() * 900000))::int::text;
        exit when not exists (select 1 from public.crm_users where ref_code = code); i := i + 1; if i > 20 then raise exception 'Dobara koshish karein'; end if; end loop;
    end if;
    insert into public.crm_users(role, username, name, mobile, email, pass_hash, status, ref_code, perms, meta)
    values (r, un, left(trim(d ->> 'name'), 80), m, lower(left(trim(coalesce(d ->> 'email', '')), 120)), case when coalesce(d ->> 'password', '') = '' then '' else crypt(d ->> 'password', gen_salt('bf')) end, coalesce(nullif(d ->> 'status', ''), 'active'), code,
      coalesce(d -> 'perms', '{}'::jsonb), coalesce(d -> 'meta', '{}'::jsonb)) returning * into u;
    perform public.crm_log(s, 'user_create', 'user', u.id, 'Naya user: ' || u.name || ' (' || u.role || ')');
  else
    select * into u from public.crm_users where id = id_;
    if u.id is null then raise exception 'User nahi mila'; end if;
    if u.role = 'admin' and not public.crm_is_admin(s) then raise exception 'Admin ko sirf Admin badal sakta hai'; end if;
    update public.crm_users set
      name = coalesce(nullif(trim(d ->> 'name'), ''), name),
      mobile = case when d ? 'mobile' then m else mobile end,
      email = case when d ? 'email' then lower(left(trim(coalesce(d ->> 'email', '')), 120)) else email end,
      email_ok = case when d ? 'email' and lower(trim(coalesce(d ->> 'email', ''))) <> lower(email) then false else email_ok end,
      role = case when r <> '' then r else role end,
      status = case when d ->> 'status' in ('active', 'pending', 'blocked') then d ->> 'status' else status end,
      perms = case when d ? 'perms' then coalesce(d -> 'perms', '{}'::jsonb) else perms end,
      meta = case when d ? 'meta' then coalesce(d -> 'meta', '{}'::jsonb) else meta end,
      pass_hash = case when length(coalesce(d ->> 'password', '')) >= 6 then crypt(d ->> 'password', gen_salt('bf')) else pass_hash end
    where id = id_ returning * into u;
    if coalesce(d ->> 'password', '') <> '' and length(d ->> 'password') < 6 then raise exception 'Password kam se kam 6 akshar ka ho'; end if;
    if u.status <> 'active' or length(coalesce(d ->> 'password', '')) >= 6 then delete from public.crm_sessions where user_id = u.id; end if;
    if u.ref_code is null and u.role in ('dealer', 'influencer') then
      loop code := upper(left(u.role, 1)) || 'SP' || (100000 + floor(random() * 900000))::int::text;
        exit when not exists (select 1 from public.crm_users where ref_code = code); end loop;
      update public.crm_users set ref_code = code where id = u.id returning * into u;
    end if;
    perform public.crm_log(s, 'user_edit', 'user', u.id, 'User badla: ' || u.name || ' (' || u.role || ', ' || u.status || ')');
  end if;
  return jsonb_build_object('id', u.id, 'username', u.username, 'role', u.role, 'status', u.status, 'ref_code', u.ref_code);
end $$;

create or replace function public.crm_user_delete(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); u public.crm_users; to_ bigint := nullif(p ->> 'transfer_to', '')::bigint;
begin
  perform public.crm_need(s, 'users.manage');
  select * into u from public.crm_users where id = (p ->> 'id')::bigint;
  if u.id is null then raise exception 'User nahi mila'; end if;
  if u.role = 'admin' and not public.crm_is_admin(s) then raise exception 'Admin ko sirf Admin hata sakta hai'; end if;
  update public.crm_records set owner_id = coalesce(to_, 0) where owner_id = u.id and kind <> 'earning';
  update public.crm_records set assigned_to = to_ where assigned_to = u.id;
  delete from public.crm_sessions where user_id = u.id;
  delete from public.crm_users where id = u.id;
  perform public.crm_log(s, 'user_delete', 'user', u.id, 'User hataya: ' || u.name || ' — data ' || coalesce(public.crm_uname(to_), 'Company') || ' ko diya');
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.crm_roles_get(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token');
begin
  perform public.crm_need(s, 'users.manage');
  return jsonb_build_object('catalog', public.crm_perm_catalog(), 'roles', (select jsonb_object_agg(role, perms) from public.crm_roles));
end $$;

create or replace function public.crm_role_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r text := p ->> 'role';
begin
  if not public.crm_is_admin(s) then raise exception 'Role permission sirf Admin badal sakta hai'; end if;
  if r not in ('manager', 'staff', 'dealer', 'influencer') then raise exception 'Role galat hai'; end if;
  if jsonb_typeof(p -> 'perms') <> 'object' then raise exception 'Data galat hai'; end if;
  insert into public.crm_roles(role, perms) values (r, p -> 'perms') on conflict (role) do update set perms = excluded.perms;
  perform public.crm_log(s, 'role_edit', 'role', null, 'Role permission badli: ' || r);
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------- settings
create or replace function public.crm_settings_get(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); st public.crm_settings; ss jsonb; d jsonb;
begin
  select * into st from public.crm_settings where id = 1;
  d := coalesce(st.data, '{}'::jsonb);
  if not (d ? 'company') then
    select data -> 'settings' into ss from public.sp_store where id = 'main';
    d := d || jsonb_build_object('company', jsonb_build_object(
      'name', coalesce(ss ->> 'storeName', 'Sunpowers'), 'legal', coalesce(ss ->> 'legalName', ''), 'gstin', coalesce(ss ->> 'gstin', ''),
      'phone', coalesce(ss ->> 'phone', ''), 'email', coalesce(ss ->> 'email', ''), 'address', coalesce(ss ->> 'address', ''),
      'website', coalesce(ss ->> 'mainSite', ''), 'store_url', case when coalesce(ss ->> 'siteUrl', '') ~* '^https?://((www\.)?sunpowers\.in|shop\.sunpowers\.in)/?$' then 'https://store.sunpowers.in' else coalesce(ss ->> 'siteUrl', '') end, 'state', 'Uttar Pradesh', 'upi', coalesce(ss #>> '{payments,upi,upiId}', '')));
  end if;
  if public.crm_can(s, 'settings.manage') then d := d || jsonb_build_object('secrets', coalesce(st.secrets, '{}'::jsonb) - 'resend_api_key'); end if;
  d := d - 'auth';
  return d;
end $$;

create or replace function public.crm_settings_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); d jsonb := p -> 'data';
begin
  perform public.crm_need(s, 'settings.manage');
  if jsonb_typeof(d) <> 'object' or length(d::text) > 400000 then raise exception 'Data galat hai'; end if;
  update public.crm_settings set data = (d - 'secrets' - 'auth') || jsonb_build_object('auth', coalesce(data -> 'auth', '{}'::jsonb)),
    secrets = case when d ? 'secrets' and jsonb_typeof(d -> 'secrets') = 'object' then ((d -> 'secrets') - 'resend_api_key') || jsonb_strip_nulls(jsonb_build_object('resend_api_key', secrets -> 'resend_api_key')) else secrets end,
    updated_at = now() where id = 1;
  perform public.crm_log(s, 'settings', null, null, 'Company settings badli');
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------- records
create or replace function public.crm_list(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); k text := p ->> 'kind'; lim int := least(greatest(coalesce((p ->> 'limit')::int, 500), 1), 3000);
        q text := lower(trim(coalesce(p ->> 'q', ''))); st text := nullif(p ->> 'status', ''); pid bigint := nullif(p ->> 'party_id', '')::bigint;
        mine boolean := coalesce((p ->> 'mine')::boolean, false); fid text := p ->> 'folder_id'; fr date := nullif(p ->> 'from', '')::date; t date := nullif(p ->> 'to', '')::date;
        uidf bigint := nullif(p ->> 'user_id', '')::bigint;
begin
  if k is null or k !~ '^[a-z_]{2,20}$' then raise exception 'Galat list'; end if;
  if k = 'quote' then perform public.crm_quote_expire_daily(); end if;
  return coalesce((select jsonb_agg(public.crm_row(s, r) order by r.id desc) from (
    select * from public.crm_records r where r.kind = k and r.deleted_at is null
      and (st is null or r.status = st) and (pid is null or r.party_id = pid)
      and (q = '' or r.search like '%' || q || '%')
      and (not mine or r.owner_id = (s).uid or r.assigned_to = (s).uid)
      and (uidf is null or r.owner_id = uidf or r.assigned_to = uidf)
      and (fid is null or (coalesce(r.data ->> 'folder_id', r.data ->> 'parent_id', '') = fid and coalesce(r.data ->> 'attach_kind', '') = ''))
      and (fr is null or coalesce(r.due_at, (r.created_at at time zone 'Asia/Kolkata')::date) >= fr)
      and (t is null or coalesce(r.due_at, (r.created_at at time zone 'Asia/Kolkata')::date) <= t)
      and public.crm_vis(s, r)
    order by r.id desc limit lim) r), '[]'::jsonb);
end $$;

create or replace function public.crm_get(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records;
begin
  perform public.crm_quote_expire_daily();
  select * into r from public.crm_records where id = (p ->> 'id')::bigint;
  if not public.crm_vis(s, r) then raise exception 'Record nahi mila'; end if;
  return public.crm_row(s, r);
end $$;

create or replace function public.crm_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); k text := p ->> 'kind'; id_ bigint := nullif(p ->> 'id', '')::bigint;
        d jsonb := coalesce(p -> 'data', '{}'::jsonb); old public.crm_records; r public.crm_records; isnew boolean := id_ is null or id_ = 0;
        mob text; ttl text; st text := coalesce(p ->> 'status', ''); asg bigint := nullif(p ->> 'assigned_to', '')::bigint; pid bigint := nullif(p ->> 'party_id', '')::bigint;
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
  ttl := left(trim(coalesce(d ->> 'name', d ->> 'title', '')), 200);
  owner_ := case when isnew then (s).uid else old.owner_id end;
  if not isnew and pid is null and not (p ? 'party_id') then pid := old.party_id; end if;
  if not isnew and not (p ? 'assigned_to') then asg := old.assigned_to; end if;
  if not isnew and not (p ? 'due_at') then due := old.due_at; end if;

  -- ---------------- per kind rules
  if k = 'party' then
    perform public.crm_need(s, case when isnew then 'customers.create' else 'customers.edit' end);
    if ttl = '' then raise exception 'Customer ka naam likhein'; end if;
    if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein'; end if;
    select * into ex from public.crm_records where kind = 'party' and deleted_at is null and mobile = mob and id <> coalesce(id_, 0) limit 1;
    if ex.id is not null then
      if public.crm_vis(s, ex) then raise exception 'Ye customer pehle se list me hai: % (#%)', ex.title, ex.id;
      else raise exception 'Ye customer pehle se % ke paas hai — Admin se transfer karwayein', coalesce(public.crm_uname(ex.owner_id), 'kisi aur'); end if;
    end if;
    if (p ? 'assigned_to') and asg is distinct from (case when isnew then null else old.assigned_to end) then perform public.crm_need(s, 'customers.assign'); end if;
    pid := null; st := coalesce(nullif(st, ''), case when isnew then 'active' else old.status end);
  elsif k = 'item' then
    perform public.crm_need(s, case when isnew then 'items.create' else 'items.edit' end);
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
    if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein'; end if;
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
    if pid is null then select id into pid from public.crm_records where kind = 'party' and mobile = mob and deleted_at is null limit 1; end if;
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

  srch := lower(concat_ws(' ', ttl, ref_, mob, d ->> 'city', d ->> 'company', d ->> 'gstin', d ->> 'note', d ->> 'type', d ->> 'brand', d ->> 'qtitle', d ->> 'category', d ->> 'subcategory', d ->> 'sku', d ->> 'mpn', d ->> 'source'));
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
end $$;

-- quick status change (lead stage, reminder done, plant verify, order etc.)
create or replace function public.crm_status(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records; st text := p ->> 'status'; d jsonb;
begin
  select * into r from public.crm_records where id = (p ->> 'id')::bigint;
  if not public.crm_vis(s, r) then raise exception 'Record nahi mila'; end if;
  d := jsonb_build_object('token', p ->> 'token', 'kind', r.kind, 'id', r.id, 'status', st, 'data', r.data || coalesce(p -> 'patch', '{}'::jsonb));
  if r.kind in ('quote', 'invoice', 'purchase') then
    if r.kind = 'quote' and st not in ('draft', 'sent', 'accepted', 'rejected') then raise exception 'Galat status'; end if;
    if r.kind = 'quote' and r.status = 'expired' then raise exception 'Expired quotation ko pehle Renew karein'; end if;
    if r.kind = 'quote' and r.status = 'converted' then raise exception 'Bill ban chuka hai'; end if;
    if r.kind = 'quote' and st in ('draft', 'sent', 'accepted') and r.status = 'rejected' and not public.crm_can(s, 'stock.override') then
      perform public.crm_need(s, 'quotes.edit');
      if public.crm_quote_shortage(r.data -> 'lines', r.id) is not null then raise exception 'Stock kam hai — is quotation ko dobara active nahi kar sakte'; end if;
    end if;
    if r.kind = 'purchase' and st not in ('open', 'received', 'cancelled') then raise exception 'Galat status'; end if;
    if r.kind = 'invoice' then raise exception 'Bill ka status payment se apne aap badalta hai'; end if;
    perform public.crm_need(s, case r.kind when 'purchase' then 'purchase.manage' else 'quotes.edit' end);
    update public.crm_records set status = st, data = d -> 'data', updated_at = now() where id = r.id;
    if r.kind = 'purchase' and st = 'received' and r.status <> 'received' then perform public.crm_stock(r.data, 1); end if;
    perform public.crm_log(s, 'status', r.kind, r.id, coalesce(r.ref, '') || ' → ' || st);
    select * into r from public.crm_records where id = r.id; return public.crm_row(s, r);
  end if;
  if r.kind = 'plant' and st in ('verified', 'rejected') then perform public.crm_need(s, 'plants.verify'); end if;
  return public.crm_save(d || jsonb_build_object('party_id', r.party_id, 'assigned_to', r.assigned_to, 'due_at', r.due_at));
end $$;

create or replace function public.crm_convert(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; inv jsonb;
begin
  perform public.crm_need(s, 'invoices.create');
  select * into q from public.crm_records where id = (p ->> 'id')::bigint and kind = 'quote';
  if not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if q.status = 'converted' then raise exception 'Is quotation ka bill pehle ban chuka hai'; end if;
  if q.status = 'expired' then raise exception 'Quotation expire ho chuki hai — pehle Renew karein'; end if;
  inv := public.crm_save(jsonb_build_object('token', p ->> 'token', 'kind', 'invoice', 'party_id', q.party_id,
    'data', (q.data - 'send_on' - 'valid_till') || jsonb_build_object('quote_id', q.id, 'quote_ref', q.ref, 'date', public.crm_today(), 'due_date', coalesce(p ->> 'due_date', ''))));
  update public.crm_records set status = 'converted', data = data || jsonb_build_object('invoice_id', inv ->> 'id', 'invoice_ref', inv ->> 'ref'), updated_at = now() where id = q.id;
  perform public.crm_stock(q.data, -1);
  return inv;
end $$;

create or replace function public.crm_delete(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records; why text := left(trim(coalesce(p ->> 'reason', '')), 300); need text; own boolean;
begin
  select * into r from public.crm_records where id = (p ->> 'id')::bigint;
  if not public.crm_vis(s, r) then raise exception 'Record nahi mila'; end if;
  own := r.owner_id = (s).uid;
  need := case r.kind when 'party' then 'customers.delete' when 'item' then 'items.delete' when 'quote' then 'quotes.delete' when 'invoice' then 'invoices.delete'
    when 'payment' then 'payments.delete' when 'purchase' then 'purchase.manage' when 'lead' then 'leads.delete' when 'earning' then 'earnings.manage'
    when 'folder' then 'docs.folders' when 'doc' then 'docs.delete' when 'notice' then 'settings.manage' else null end;
  if r.kind = 'plant' then
    if not (public.crm_can(s, 'plants.delete') or (own and r.status = 'pending')) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  elsif r.kind in ('reminder', 'note') then
    if not (own or public.crm_can(s, 'reminders.assign')) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  elsif r.kind = 'doc' then
    if not (own or public.crm_can(s, 'docs.delete')) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  elsif r.kind = 'lead' then
    if not (public.crm_can(s, 'leads.delete') or (own and r.owner_id <> 0)) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  elsif need is not null then perform public.crm_need(s, need);
  end if;
  if r.kind in ('party', 'quote', 'invoice', 'payment', 'plant', 'earning') and length(why) < 3 then raise exception 'Hatane ki wajah likhein'; end if;
  if r.kind = 'invoice' and exists (select 1 from public.crm_records where kind = 'payment' and deleted_at is null and data ->> 'invoice_id' = r.id::text) then raise exception 'Pehle is bill ke payments hatayein'; end if;
  if r.kind = 'party' and exists (select 1 from public.crm_records where party_id = r.id and deleted_at is null and kind in ('invoice', 'payment')) then raise exception 'Is customer ke bill / payment hain — pehle unhe hatayein'; end if;
  if r.kind = 'folder' and exists (select 1 from public.crm_records where kind in ('folder', 'doc') and deleted_at is null and coalesce(data ->> 'parent_id', data ->> 'folder_id') = r.id::text) then raise exception 'Folder khaali nahi hai'; end if;
  if r.kind = 'earning' and r.status = 'paid' and not public.crm_is_admin(s) then raise exception 'Paid commission sirf Admin hata sakta hai'; end if;
  update public.crm_records set deleted_at = now(), deleted_by = (s).uid, delete_reason = why where id = r.id;
  if r.kind = 'payment' and coalesce(r.data ->> 'invoice_id', '') <> '' then perform public.crm_inv_recalc((r.data ->> 'invoice_id')::bigint); end if;
  if r.kind = 'invoice' then
    perform public.crm_stock(r.data, 1);
    update public.crm_records set status = 'accepted', data = data - 'invoice_id' - 'invoice_ref' where id = nullif(r.data ->> 'quote_id', '')::bigint;
  end if;
  if r.kind = 'plant' then perform public.crm_commission(r.id, s); end if;
  if r.kind = 'doc' then delete from public.crm_files where rec_id = r.id; end if;
  perform public.crm_log(s, 'delete', r.kind, r.id, coalesce(r.ref || ' ', '') || r.title || case when why <> '' then ' — Wajah: ' || why else '' end);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.crm_assign(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); k text := p ->> 'kind'; to_ bigint := nullif(p ->> 'user_id', '')::bigint; n int := 0; rid jsonb; r public.crm_records;
begin
  if k = 'lead' then perform public.crm_need(s, 'leads.assign');
  elsif k = 'party' then perform public.crm_need(s, 'customers.assign');
  elsif k = 'reminder' then perform public.crm_need(s, 'reminders.assign');
  else raise exception 'Galat record'; end if;
  if to_ is not null and not exists (select 1 from public.crm_users where id = to_ and status = 'active') then raise exception 'User nahi mila'; end if;
  for rid in select * from jsonb_array_elements(coalesce(p -> 'ids', '[]'::jsonb)) loop
    select * into r from public.crm_records where id = (rid #>> '{}')::bigint and kind = k;
    if public.crm_vis(s, r) then
      if k = 'party' then update public.crm_records set owner_id = coalesce(to_, 0), assigned_to = null, updated_at = now() where id = r.id;
      else update public.crm_records set assigned_to = to_, data = data || jsonb_build_object('assigned_on', public.crm_today())
             || case when k = 'lead' and to_ is not null and to_ <> r.owner_id then '{"company":true}'::jsonb else '{}'::jsonb end, updated_at = now() where id = r.id; end if;
      n := n + 1;
    end if;
  end loop;
  perform public.crm_log(s, 'assign', k, null, n || ' ' || k || ' → ' || coalesce(public.crm_uname(to_), 'Company'));
  return jsonb_build_object('count', n);
end $$;

create or replace function public.crm_lead_import(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
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
    if exists (select 1 from public.crm_records where kind = 'lead' and deleted_at is null and mobile = m and (assigned_to = coalesce(to_, (s).uid) or owner_id = coalesce(to_, (s).uid))) then sk := sk + 1; continue; end if;
    insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, due_at, data, search, created_by)
    values ('lead', left(coalesce(nullif(trim(r ->> 'name'), ''), 'Lead ' || m), 120), m, 'new', own, coalesce(to_, (s).uid),
      case when coalesce(r ->> 'followup', '') ~ '^\d{4}-\d{2}-\d{2}$' then (r ->> 'followup')::date else null end,
      (r - 'mobile') || jsonb_build_object('mobile', m, 'source', coalesce(nullif(r ->> 'source', ''), case when company then 'Company' else 'Import' end), 'company', company),
      lower(concat_ws(' ', r ->> 'name', m, r ->> 'city', r ->> 'source')), (s).uid);
    n := n + 1;
  end loop;
  perform public.crm_log(s, 'import', 'lead', null, n || ' leads import' || case when company then ' → ' || public.crm_uname(to_) else '' end || ' (' || sk || ' chhodi)');
  return jsonb_build_object('added', n, 'skipped', sk);
end $$;

-- ---------------------------------------------------------------- files (documents)
create or replace function public.crm_file_put(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); b bytea; fid bigint := nullif(p ->> 'folder_id', '')::bigint; r public.crm_records; nm text := left(trim(coalesce(p ->> 'name', 'file')), 160);
begin
  if not (public.crm_can(s, 'docs.upload') or coalesce(p ->> 'attach_kind', '') <> '') then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  if fid is not null and not public.crm_folder_ok(s, fid) then raise exception 'Folder nahi mila'; end if;
  if coalesce(p ->> 'attach_kind', '') <> '' then
    if nullif(p ->> 'party_id', '') is null then raise exception 'Customer chunein'; end if;
    select * into r from public.crm_records where id = (p ->> 'party_id')::bigint and kind = 'party';
    if not public.crm_vis(s, r) then raise exception 'Customer nahi mila'; end if;
    fid := null;
  end if;
  begin b := decode(coalesce(p ->> 'b64', ''), 'base64'); exception when others then raise exception 'File padh nahi paye'; end;
  if octet_length(b) = 0 then raise exception 'File khaali hai'; end if;
  if octet_length(b) > 3 * 1024 * 1024 then raise exception 'File 3 MB se badi hai'; end if;
  insert into public.crm_records(kind, title, status, owner_id, party_id, data, search, created_by)
  values ('doc', nm, 'ok', (s).uid, nullif(p ->> 'party_id', '')::bigint,
    jsonb_build_object('folder_id', fid, 'mime', left(coalesce(p ->> 'mime', 'application/octet-stream'), 80), 'size', octet_length(b), 'note', left(coalesce(p ->> 'note', ''), 500),
      'attach_kind', nullif(p ->> 'attach_kind', ''), 'attach_id', nullif(p ->> 'attach_id', '')),
    lower(nm || ' ' || coalesce(p ->> 'note', '')), (s).uid) returning * into r;
  insert into public.crm_files(rec_id, mime, size, data) values (r.id, left(coalesce(p ->> 'mime', 'application/octet-stream'), 80), octet_length(b), b);
  perform public.crm_log(s, 'upload', 'doc', r.id, 'Document: ' || nm);
  return public.crm_row(s, r);
end $$;

create or replace function public.crm_file_get(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records; f public.crm_files;
begin
  select * into r from public.crm_records where id = (p ->> 'id')::bigint and kind = 'doc';
  if not public.crm_vis(s, r) then raise exception 'Document nahi mila'; end if;
  select * into f from public.crm_files where rec_id = r.id limit 1;
  if f.id is null then raise exception 'File nahi mili'; end if;
  perform public.crm_log(s, 'open', 'doc', r.id, 'Document khola: ' || r.title);
  return jsonb_build_object('name', r.title, 'mime', f.mime, 'b64', encode(f.data, 'base64'));
end $$;

-- ---------------------------------------------------------------- search / today / dashboards
create or replace function public.crm_search(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q text := lower(trim(coalesce(p ->> 'q', '')));
begin
  if length(q) < 2 then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'title', title, 'ref', ref, 'mobile', mobile, 'status', status, 'amount', amount, 'data',
      case when kind = 'doc' then jsonb_build_object('folder_id', data -> 'folder_id', 'mime', data -> 'mime') when kind = 'item' then jsonb_build_object('type', data -> 'type') else '{}'::jsonb end))
    from (select * from public.crm_records r where r.deleted_at is null and r.kind in ('party', 'lead', 'quote', 'invoice', 'item', 'doc', 'folder', 'plant', 'payment')
      and r.search like '%' || q || '%' and public.crm_vis(s, r) order by r.updated_at desc limit 40) x), '[]'::jsonb);
end $$;

create or replace function public.crm_today_list(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); u bigint := coalesce(nullif(p ->> 'user_id', '')::bigint, (s).uid); dt date := coalesce(nullif(p ->> 'date', '')::date, public.crm_today());
        allu boolean := coalesce((p ->> 'all')::boolean, false);
begin
  if (u <> (s).uid or allu) and not (public.crm_can(s, 'reminders.view_all') or public.crm_can(s, 'team.stats')) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  return jsonb_build_object('date', dt, 'items', coalesce((select jsonb_agg(x order by x ->> 'due_at', x ->> 'kind') from (
    select jsonb_build_object('src', 'reminder', 'id', r.id, 'kind', coalesce(r.data ->> 'type', 'other'), 'title', r.title, 'note', r.data ->> 'note', 'time', r.data ->> 'time', 'due_at', r.due_at,
      'overdue', r.due_at < dt, 'party_id', r.party_id, 'mobile', r.mobile, 'user', public.crm_uname(coalesce(r.assigned_to, r.owner_id)), 'user_id', coalesce(r.assigned_to, r.owner_id)) x
    from public.crm_records r where r.kind = 'reminder' and r.deleted_at is null and r.status = 'open' and r.due_at <= dt and (allu or coalesce(r.assigned_to, r.owner_id) = u)
    union all
    select jsonb_build_object('src', 'lead', 'id', r.id, 'kind', 'followup', 'title', r.title, 'note', r.data ->> 'note', 'due_at', r.due_at, 'overdue', r.due_at < dt, 'mobile', r.mobile, 'status', r.status,
      'user', public.crm_uname(coalesce(r.assigned_to, r.owner_id)), 'user_id', coalesce(r.assigned_to, r.owner_id))
    from public.crm_records r where r.kind = 'lead' and r.deleted_at is null and r.status not in ('won', 'lost') and r.due_at <= dt and (allu or coalesce(r.assigned_to, r.owner_id) = u)
    union all
    select jsonb_build_object('src', 'invoice', 'id', r.id, 'kind', 'payment_in', 'title', r.title || ' — ' || coalesce(r.ref, ''), 'due_at', r.due_at, 'overdue', r.due_at < dt, 'mobile', r.mobile,
      'amount', r.data -> 'balance', 'user', public.crm_uname(r.owner_id), 'user_id', r.owner_id)
    from public.crm_records r where r.kind = 'invoice' and r.deleted_at is null and r.status <> 'paid' and r.due_at <= dt and (allu or r.owner_id = u)
    union all
    select jsonb_build_object('src', 'quote', 'id', r.id, 'kind', 'quote_send', 'title', r.title || ' — ' || coalesce(r.ref, ''), 'due_at', r.due_at, 'overdue', r.due_at < dt, 'mobile', r.mobile,
      'amount', r.amount, 'user', public.crm_uname(r.owner_id), 'user_id', r.owner_id)
    from public.crm_records r where r.kind = 'quote' and r.deleted_at is null and r.status = 'draft' and r.due_at <= dt and (allu or r.owner_id = u)
    union all
    select jsonb_build_object('src', 'earning', 'id', r.id, 'kind', 'payment_out', 'title', r.title || ' → ' || coalesce(public.crm_uname(r.owner_id), ''), 'due_at', r.due_at, 'overdue', r.due_at < dt,
      'amount', r.amount, 'user', 'Admin', 'user_id', 0)
    from public.crm_records r where r.kind = 'earning' and r.deleted_at is null and r.status = 'due' and r.due_at <= dt and (allu or u = 0) and public.crm_can(s, 'earnings.manage')
  ) q), '[]'::jsonb));
end $$;

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

create or replace function public.crm_auth_pin_valid(f jsonb, p_pin text) returns void language plpgsql immutable as $$
begin
  if coalesce(p_pin, '') !~ ('^\d{' || (f ->> 'pin_len') || '}$') then raise exception 'PIN % ank ka hona chahiye', f ->> 'pin_len'; end if;
  if p_pin ~ '^(\d)\1+$' or p_pin in ('1234', '4321', '123456', '654321', '012345', '0123') then raise exception 'Itna aasaan PIN nahi — doosra PIN chunein'; end if;
end $$;

create or replace function public.crm_auth_set_q(f jsonb, p jsonb) returns void language plpgsql security definer set search_path = public, extensions as $$
declare uid bigint := (f ->> 'uid')::bigint;
begin
  if coalesce(p ->> 'q1', '') = '' or coalesce(p ->> 'q2', '') = '' or p ->> 'q1' = p ->> 'q2' or coalesce(trim(p ->> 'a1'), '') = '' or coalesce(trim(p ->> 'a2'), '') = '' then
    raise exception '2 alag security sawal aur unke jawab likhein'; end if;
  if uid = 0 then
    update public.crm_auth_admin set q1 = left(p ->> 'q1', 120), a1 = crypt(lower(trim(p ->> 'a1')), gen_salt('bf')), q2 = left(p ->> 'q2', 120), a2 = crypt(lower(trim(p ->> 'a2')), gen_salt('bf')), q_fail = 0, updated_at = now() where id = 1;
  else
    update public.crm_users set q1 = left(p ->> 'q1', 120), a1 = crypt(lower(trim(p ->> 'a1')), gen_salt('bf')), q2 = left(p ->> 'q2', 120), a2 = crypt(lower(trim(p ->> 'a2')), gen_salt('bf')), q_fail = 0 where id = uid;
  end if;
end $$;

create or replace function public.crm_auth_store_pin(f jsonb, p_pin text) returns void language plpgsql security definer set search_path = public, extensions as $$
declare uid bigint := (f ->> 'uid')::bigint;
begin
  perform public.crm_auth_pin_valid(f, p_pin);
  if uid = 0 then update public.crm_auth_admin set pin_hash = crypt(p_pin, gen_salt('bf')), pin_fail = 0, updated_at = now() where id = 1;
  else update public.crm_users set pin_hash = crypt(p_pin, gen_salt('bf')), pin_fail = 0 where id = uid; end if;
end $$;

-- 3) PIN login: trusted device, or new device with an OTP ticket
create or replace function public.crm_auth_pin(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare f jsonb := public.crm_auth_find(p ->> 'app', p ->> 'id'); uid bigint := (f ->> 'uid')::bigint; e text;
begin
  perform public.crm_auth_status_ok(f, true);
  if not (public.crm_auth_trusted(uid, p ->> 'device') or public.crm_auth_ticket_ok(uid, p ->> 'ticket')) then
    raise exception 'Is phone / browser par pehle Email OTP se login karein'; end if;
  e := public.crm_auth_pin_check(f, p ->> 'pin');
  if e is not null then return jsonb_build_object('error', e); end if;
  return public.crm_auth_session(f || jsonb_build_object('dev_name', p ->> 'dev_name'), p ->> 'device', p ->> 'app');
end $$;

-- 4) first time: create PIN (+ security questions) after OTP
create or replace function public.crm_auth_setpin(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare f jsonb := public.crm_auth_find(p ->> 'app', p ->> 'id'); uid bigint := (f ->> 'uid')::bigint;
begin
  perform public.crm_auth_status_ok(f, true);
  if not public.crm_auth_ticket_ok(uid, p ->> 'ticket') then raise exception 'Samay khatam — dobara OTP se shuru karein'; end if;
  if (f ->> 'has_pin')::boolean and (f ->> 'pin_fail')::int < 5 then raise exception 'PIN pehle se bana hai — PIN daalein'; end if;
  perform public.crm_auth_pin_valid(f, p ->> 'pin');
  if not (f ->> 'has_q')::boolean or coalesce(p ->> 'q1', '') <> '' then perform public.crm_auth_set_q(f, p); end if;
  perform public.crm_auth_store_pin(f, p ->> 'pin');
  update public.crm_otps set ticket_expires = now() where user_id = uid and ticket_hash = public.crm_h(p ->> 'ticket');
  return public.crm_auth_session(f || jsonb_build_object('has_q', true, 'dev_name', p ->> 'dev_name'), p ->> 'device', p ->> 'app');
end $$;

-- 5) forgot PIN → security questions; after 5 wrong answers an e-mail reset link is sent
create or replace function public.crm_auth_send_link(f jsonb, p_app text) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare uid bigint := (f ->> 'uid')::bigint; tk text := encode(gen_random_bytes(24), 'hex'); base text; lnk text; tos text[]; last timestamptz;
begin
  select max(created_at) into last from public.crm_resets where user_id = uid;
  if last is not null and last > now() - interval '2 minutes' then
    return jsonb_build_object('link', true, 'email', (select string_agg(public.crm_mask_email(e), ', ') from jsonb_array_elements_text(f -> 'emails') e where e <> ''), 'again', true);
  end if;
  select array_agg(e) into tos from jsonb_array_elements_text(f -> 'emails') e where e <> '';
  if tos is null then raise exception 'Is ID me email nahi hai — Admin se PIN reset karwayein'; end if;
  select nullif(data #>> array['auth', 'urls', p_app], '') into base from public.crm_settings where id = 1;
  if base is null then raise exception 'Reset link ka address set nahi hai — Admin se sampark karein'; end if;
  update public.crm_resets set used = true where user_id = uid and not used;
  insert into public.crm_resets(token_hash, user_id, app, expires_at) values (public.crm_h(tk), uid, p_app, now() + interval '15 minutes');
  lnk := rtrim(base, '/') || '/?reset=' || tk;
  perform public.crm_mail(tos, 'PIN reset link — Sunpowers', public.crm_mail_tpl('Naya PIN banayein',
    'Namaste ' || coalesce(f ->> 'name', '') || ',<br>Neeche button dabakar naya PIN banayein. Ye link <b>15 minute</b> tak aur sirf ek baar chalega.<p style="margin:20px 0"><a href="' || lnk || '" style="background:#1e8e3e;color:#fff;padding:12px 22px;border-radius:10px;text-decoration:none;font-weight:bold;display:inline-block">Naya PIN banayein</a></p><span style="font-size:12px;color:#5f6f64">Button na chale to ye link kholein:<br>' || lnk || '</span>'));
  insert into public.crm_activity(user_id, user_name, role, action, summary) values (uid, f ->> 'name', f ->> 'role', 'reset_link', 'PIN reset link email par bheja');
  return jsonb_build_object('link', true, 'email', (select string_agg(public.crm_mask_email(e), ', ') from unnest(tos) e));
end $$;

create or replace function public.crm_auth_forgot(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare f jsonb := public.crm_auth_find(p ->> 'app', p ->> 'id');
begin
  if f ->> 'role' = 'marketing' then return public.crm_auth_mkt_forgot(p) || jsonb_build_object('mkt', true); end if;
  perform public.crm_auth_status_ok(f, true);
  if not (f ->> 'has_q')::boolean or (f ->> 'q_fail')::int >= 5 then
    return public.crm_auth_send_link(public.crm_auth_backup(f, p), p ->> 'app');
  end if;
  return jsonb_build_object('q1', f ->> 'q1', 'q2', f ->> 'q2', 'left', 5 - (f ->> 'q_fail')::int, 'pin_len', f -> 'pin_len', 'name', f ->> 'name');
end $$;

create or replace function public.crm_auth_answer(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare f jsonb := public.crm_auth_find(p ->> 'app', p ->> 'id'); uid bigint := (f ->> 'uid')::bigint; h1 text; h2 text; ok boolean; fails int;
begin
  perform public.crm_auth_status_ok(f, true);
  if (f ->> 'q_fail')::int >= 5 then return public.crm_auth_send_link(public.crm_auth_backup(f, p), p ->> 'app'); end if;
  perform public.crm_auth_pin_valid(f, p ->> 'pin');
  if uid = 0 then select a1, a2 into h1, h2 from public.crm_auth_admin where id = 1; else select a1, a2 into h1, h2 from public.crm_users where id = uid; end if;
  ok := coalesce(h1, '') <> '' and crypt(lower(trim(coalesce(p ->> 'a1', ''))), h1) = h1 and crypt(lower(trim(coalesce(p ->> 'a2', ''))), h2) = h2;
  if not ok then
    if uid = 0 then update public.crm_auth_admin set q_fail = q_fail + 1 where id = 1 returning q_fail into fails;
    else update public.crm_users set q_fail = q_fail + 1 where id = uid returning q_fail into fails; end if;
    perform pg_sleep(0.6);
    if fails >= 5 then return public.crm_auth_send_link(public.crm_auth_backup(f, p), p ->> 'app') || jsonb_build_object('failed', true); end if;
    return jsonb_build_object('error', 'Jawab sahi nahi hain');
  end if;
  perform public.crm_auth_store_pin(f, p ->> 'pin');
  insert into public.crm_activity(user_id, user_name, role, action, summary) values (uid, f ->> 'name', f ->> 'role', 'pin_reset', 'PIN badla (security sawal)');
  return public.crm_auth_session(f || jsonb_build_object('dev_name', p ->> 'dev_name'), p ->> 'device', p ->> 'app');
end $$;

-- 6) reset link from e-mail
create or replace function public.crm_auth_reset_info(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.crm_resets; n text;
begin
  select * into r from public.crm_resets where token_hash = public.crm_h(p ->> 'token') and not used and expires_at > now();
  if r.token_hash is null then raise exception 'Ye link purana ho gaya ya pehle use ho chuka — dobara "PIN bhool gaye?" dabayein'; end if;
  n := case when r.user_id = 0 then 'Admin' else (select name from public.crm_users where id = r.user_id) end;
  return jsonb_build_object('name', n, 'app', r.app, 'pin_len', case when r.user_id = 0 then 6 else 4 end, 'id', case when r.user_id = 0 then 'admin' else (select coalesce(nullif(mobile, ''), username) from public.crm_users where id = r.user_id) end);
end $$;

create or replace function public.crm_auth_reset(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.crm_resets; f jsonb; idv text;
begin
  select * into r from public.crm_resets where token_hash = public.crm_h(p ->> 'token') and not used and expires_at > now();
  if r.token_hash is null then raise exception 'Ye link purana ho gaya ya pehle use ho chuka — dobara "PIN bhool gaye?" dabayein'; end if;
  idv := case when r.user_id = 0 then 'admin' else (select coalesce(nullif(mobile, ''), username) from public.crm_users where id = r.user_id) end;
  f := public.crm_auth_find(r.app, idv);
  perform public.crm_auth_status_ok(f, true);
  perform public.crm_auth_store_pin(f, p ->> 'pin');
  update public.crm_resets set used = true where token_hash = r.token_hash;
  if r.user_id = 0 then update public.crm_auth_admin set q_fail = 0 where id = 1; else update public.crm_users set q_fail = 0 where id = r.user_id; end if;
  insert into public.crm_activity(user_id, user_name, role, action, summary) values (r.user_id, f ->> 'name', f ->> 'role', 'pin_reset', 'PIN badla (email link)');
  return public.crm_auth_session(f || jsonb_build_object('dev_name', p ->> 'dev_name'), p ->> 'device', r.app);
end $$;

-- 7) self registration: Dealer / Influencer (CRM) and Customers (store) — e-mail is verified by OTP
create or replace function public.crm_auth_register(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare app text := p ->> 'app'; r text := lower(coalesce(p ->> 'role', '')); m text := public.crm_mobile(p ->> 'mobile'); em text := lower(trim(coalesce(p ->> 'email', '')));
        nm text := left(trim(coalesce(p ->> 'name', '')), 80); ex public.crm_users; code text; i int := 0; un text; st text;
begin
  if app = 'store' then r := 'consumer'; elsif app = 'crm' then if r not in ('dealer', 'influencer') then raise exception 'Is role ki ID sirf Admin bana sakta hai'; end if; else raise exception 'Galat app'; end if;
  if nm = '' then raise exception 'Naam likhein'; end if;
  if m !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein'; end if;
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Sahi email likhein (OTP isi par aayega)'; end if;
  if coalesce(p ->> 'q1', '') = '' or coalesce(p ->> 'q2', '') = '' or p ->> 'q1' = p ->> 'q2' or coalesce(trim(p ->> 'a1'), '') = '' or coalesce(trim(p ->> 'a2'), '') = '' then
    raise exception '2 alag security sawal aur unke jawab likhein'; end if;
  select * into ex from public.crm_users where ((app = 'store' and role = 'consumer') or (app = 'crm' and role <> 'consumer')) and (mobile = m or lower(email) = em) order by id limit 1;
  if ex.id is not null and (ex.pin_hash <> '' or ex.email_ok or coalesce(ex.pass_hash, '') <> '' or ex.role <> r or (r <> 'consumer' and ex.status <> 'pending')) then
    raise exception 'Is mobile / email se ID pehle se bani hai — Login karein'; end if;
  st := case when r = 'consumer' then 'active' else 'pending' end;
  if ex.id is null then
    un := case when r = 'consumer' then m else 'u' || m end;
    while exists (select 1 from public.crm_users where username = un) loop un := un || floor(random() * 10)::int::text; end loop;
    if r in ('dealer', 'influencer') then
      loop code := upper(left(r, 1)) || 'SP' || (100000 + floor(random() * 900000))::int::text;
        exit when not exists (select 1 from public.crm_users where ref_code = code); i := i + 1; if i > 20 then raise exception 'Dobara koshish karein'; end if; end loop;
    end if;
    insert into public.crm_users(role, username, name, mobile, email, pass_hash, status, ref_code) values (r, un, nm, m, em, '', st, code) returning * into ex;
    insert into public.crm_activity(user_id, user_name, role, action, summary) values (null, nm, r, 'register', 'Nayi ID: ' || m);
  else
    update public.crm_users set name = nm, mobile = m, email = em where id = ex.id returning * into ex;
  end if;
  perform public.crm_auth_set_q(jsonb_build_object('uid', ex.id), p);
  return public.crm_auth_send_otp(jsonb_build_object('uid', ex.id, 'name', ex.name, 'emails', jsonb_build_array(ex.email), 'pin_len', 4), 'register')
    || jsonb_build_object('id', m, 'ref_code', ex.ref_code, 'pending', st = 'pending');
end $$;

-- 8) logged-in: my security (devices, PIN, questions), logout everywhere
create or replace function public.crm_auth_who(p_token text) returns jsonb language plpgsql security definer set search_path = public as $$
declare se public.crm_sessions;
begin
  select * into se from public.crm_sessions where token = coalesce(p_token, '') and expires_at > now();
  if se.token is null then raise exception 'Login expired — dobara login karein'; end if;
  return jsonb_build_object('uid', se.user_id, 'role', se.role, 'dev', se.dev_hash, 'app', case when se.role = 'consumer' then 'store' else 'crm' end);
end $$;

create or replace function public.crm_auth_me(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb := public.crm_auth_who(p ->> 'token'); uid bigint := (w ->> 'uid')::bigint; em text; e2 text; hq boolean;
begin
  if uid = 0 then select email, email2, q1 <> '' into em, e2, hq from public.crm_auth_admin where id = 1;
  else select email, '', q1 <> '' into em, e2, hq from public.crm_users where id = uid; end if;
  return jsonb_build_object('email', public.crm_mask_email(em), 'email2', public.crm_mask_email(e2), 'has_q', hq, 'pin_len', case when uid = 0 then 6 else 4 end,
    'devices', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name, 'created_at', d.created_at, 'last_seen', d.last_seen, 'current', d.dev_hash = w ->> 'dev') order by d.last_seen desc)
      from public.crm_devices d where d.user_id = uid), '[]'::jsonb));
end $$;

create or replace function public.crm_auth_device_remove(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb := public.crm_auth_who(p ->> 'token'); d public.crm_devices;
begin
  select * into d from public.crm_devices where id = (p ->> 'id')::bigint and user_id = (w ->> 'uid')::bigint;
  if d.id is null then raise exception 'Device nahi mila'; end if;
  delete from public.crm_sessions where user_id = d.user_id and dev_hash = d.dev_hash;
  delete from public.crm_devices where id = d.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.crm_auth_logout_all(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb := public.crm_auth_who(p ->> 'token'); uid bigint := (w ->> 'uid')::bigint; n int;
begin
  delete from public.crm_sessions where user_id = uid and token <> (p ->> 'token');
  get diagnostics n = row_count;
  delete from public.crm_devices where user_id = uid and dev_hash is distinct from (w ->> 'dev');
  insert into public.crm_activity(user_id, user_name, role, action, summary) values (uid, null, w ->> 'role', 'logout_all', 'Baaki sab phone / browser se logout');
  return jsonb_build_object('ok', true, 'sessions', n);
end $$;

create or replace function public.crm_auth_change_pin(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb := public.crm_auth_who(p ->> 'token'); f jsonb; e text;
begin
  f := public.crm_auth_find(w ->> 'app', case when (w ->> 'uid')::bigint = 0 then 'admin' else (select coalesce(nullif(mobile, ''), username) from public.crm_users where id = (w ->> 'uid')::bigint) end);
  e := public.crm_auth_pin_check(f, p ->> 'old');
  if e is not null then return jsonb_build_object('error', e); end if;
  perform public.crm_auth_store_pin(f, p ->> 'new');
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.crm_auth_questions(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb := public.crm_auth_who(p ->> 'token'); f jsonb; e text;
begin
  f := public.crm_auth_find(w ->> 'app', case when (w ->> 'uid')::bigint = 0 then 'admin' else (select coalesce(nullif(mobile, ''), username) from public.crm_users where id = (w ->> 'uid')::bigint) end);
  if (f ->> 'has_q')::boolean then e := public.crm_auth_pin_check(f, p ->> 'pin'); if e is not null then return jsonb_build_object('error', e); end if; end if;
  perform public.crm_auth_set_q(f, p);
  return jsonb_build_object('ok', true);
end $$;

-- 9) Admin: e-mail + link settings, test mail, mail log, reset a user's login
create or replace function public.crm_auth_admin_get(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); a public.crm_auth_admin; ready boolean;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  select * into a from public.crm_auth_admin where id = 1;
  ready := to_regclass('net._http_response') is not null or exists (select 1 from pg_proc where proname = 'http_post' and pronamespace = (select oid from pg_namespace where nspname = 'net'));
  return jsonb_build_object('email', a.email, 'email2', a.email2, 'auth', (select coalesce(data -> 'auth', '{}'::jsonb) from public.crm_settings where id = 1),
    'key_set', public.crm_resend_key() is not null, 'pg_net', ready,
    'log', coalesce((select jsonb_agg(jsonb_build_object('at', at, 'to', to_list, 'subject', subject, 'request_id', request_id, 'note', note) order by id desc) from (select * from public.crm_mail_log order by id desc limit 20) l), '[]'::jsonb));
end $$;

create or replace function public.crm_auth_admin_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); au jsonb := coalesce(p -> 'auth', '{}'::jsonb); pe text; e1 text := lower(trim(coalesce(p ->> 'email', ''))); e2 text := lower(trim(coalesce(p ->> 'email2', '')));
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  pe := public.crm_auth_pin_check(public.crm_auth_find('crm', 'admin'), p ->> 'pin');
  if pe is not null then return jsonb_build_object('error', pe); end if;
  if e1 !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Admin ka sahi email likhein'; end if;
  if e2 <> '' and e2 !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Doosra email sahi nahi hai'; end if;
  update public.crm_auth_admin set email = e1, email2 = e2, updated_at = now() where id = 1;
  update public.crm_settings set data = jsonb_set(data, '{auth}', coalesce(data -> 'auth', '{}'::jsonb) || jsonb_build_object(
      'from', left(coalesce(au ->> 'from', 'Sunpowers <no-reply@sunpowers.in>'), 120),
      'urls', jsonb_build_object('store', coalesce(au #>> '{urls,store}', ''), 'crm', coalesce(au #>> '{urls,crm}', ''), 'admin', coalesce(au #>> '{urls,admin}', ''))))
  where id = 1;
  if coalesce(p ->> 'resend_key', '') <> '' then
    update public.crm_settings set secrets = coalesce(secrets, '{}'::jsonb) || jsonb_build_object('resend_api_key', trim(p ->> 'resend_key')) where id = 1;
  end if;
  perform public.crm_log(s, 'settings', null, null, 'Login / email settings badli');
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.crm_auth_test_mail(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); tos text[];
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  select array[email] into tos from public.crm_auth_admin where id = 1;
  if coalesce(p ->> 'to', '') <> '' then tos := array[p ->> 'to']; end if;
  return jsonb_build_object('request_id', public.crm_mail(tos, 'Test email — Sunpowers', public.crm_mail_tpl('Email chal raha hai ✔', 'Ye test email hai. Ab OTP aur PIN reset link isi tarah aayenge.')));
end $$;

create or replace function public.crm_auth_mail_status(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r jsonb;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  begin
    execute 'select to_jsonb(x) from (select id, status_code, left(coalesce(content::text, ''''), 300) as content, error_msg, created from net._http_response where id = $1) x' into r using (p ->> 'request_id')::bigint;
  exception when others then r := jsonb_build_object('error_msg', sqlerrm); end;
  return coalesce(r, jsonb_build_object('pending', true));
end $$;

create or replace function public.crm_auth_user_reset(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); u public.crm_users;
begin
  perform public.crm_need(s, 'users.manage');
  select * into u from public.crm_users where id = (p ->> 'id')::bigint;
  if u.id is null then raise exception 'User nahi mila'; end if;
  update public.crm_users set pin_hash = '', pin_fail = 0, q_fail = 0 where id = u.id;
  delete from public.crm_devices where user_id = u.id;
  delete from public.crm_sessions where user_id = u.id;
  perform public.crm_log(s, 'user_edit', 'user', u.id, 'Login reset (PIN + devices): ' || u.name);
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------- full backup (Admin + PIN, page by page)
create or replace function public.crm_backup(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pe text; part text := coalesce(p ->> 'part', 'meta');
  off int := greatest(coalesce((p ->> 'offset')::int, 0), 0); lim int; r jsonb; cnt jsonb := '{}'::jsonb; t text;
  parts text[] := array['crm_settings', 'crm_auth_admin', 'crm_roles', 'crm_users', 'crm_records', 'crm_counters', 'crm_activity', 'sp_store', 'sp_orders', 'sp_enquiries', 'crm_files'];
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  pe := public.crm_auth_pin_check(public.crm_auth_find('crm', 'admin'), p ->> 'pin');
  if pe is not null then return jsonb_build_object('error', pe); end if;
  if part = 'meta' then
    foreach t in array parts loop
      if to_regclass('public.' || t) is not null then execute format('select count(*) from public.%I', t) into lim; cnt := cnt || jsonb_build_object(t, lim); end if;
    end loop;
    perform public.crm_log(s, 'backup', null, null, 'Poora backup download kiya');
    return jsonb_build_object('app', 'sunpowers-suite', 'format', 1, 'at', now(), 'by', (s).name, 'parts', to_jsonb(parts), 'counts', cnt);
  end if;
  if not (part = any (parts)) or to_regclass('public.' || part) is null then raise exception 'Galat hissa: %', part; end if;
  lim := case when part = 'crm_files' then 4 else 500 end;
  if part = 'crm_users' then
    select coalesce(jsonb_agg(to_jsonb(x) - 'pass_hash' - 'pin_hash' - 'a1' - 'a2' - 'pin_fail' - 'q_fail' order by x.id), '[]') into r from (select * from public.crm_users order by id offset off limit lim) x;
  elsif part = 'crm_auth_admin' then
    select coalesce(jsonb_agg(jsonb_build_object('email', email, 'email2', email2, 'q1', q1, 'q2', q2)), '[]') into r from public.crm_auth_admin where off = 0;
  elsif part = 'crm_settings' then
    select coalesce(jsonb_agg(jsonb_build_object('data', data, 'updated_at', updated_at)), '[]') into r from public.crm_settings where off = 0;
  elsif part = 'crm_files' then
    select coalesce(jsonb_agg(jsonb_build_object('id', id, 'rec_id', rec_id, 'mime', mime, 'size', size, 'b64', encode(data, 'base64')) order by id), '[]') into r from (select * from public.crm_files order by id offset off limit lim) x;
  else
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from (select * from public.%I order by 1 offset %s limit %s) x', part, off, lim) into r;
  end if;
  return jsonb_build_object('part', part, 'rows', r, 'next', case when jsonb_array_length(r) = lim and part not in ('crm_settings', 'crm_auth_admin') then off + lim end);
end $$;

-- ---------------------------------------------------------------- Round 2: Marketing team (password + security sawal, bina OTP)
do $$ begin
  alter table public.crm_users drop constraint if exists crm_users_role_check;
  alter table public.crm_users add constraint crm_users_role_check check (role in ('admin','manager','staff','dealer','influencer','consumer','marketing'));
end $$;
insert into public.crm_roles(role, perms) values ('marketing', '{"marketing.view":true,"marketing.leads":true,"leads.create":true,"leads.import":true}') on conflict (role) do nothing;

-- marketing user: ID se password wala raasta
create or replace function public.crm_auth_mkt_find(p jsonb) returns public.crm_users language plpgsql stable security definer set search_path = public as $$
declare x text := lower(trim(coalesce(p ->> 'id', ''))); m text := public.crm_mobile(p ->> 'id'); u public.crm_users;
begin
  select * into u from public.crm_users where role = 'marketing' and (username = x or (x <> '' and lower(email) = x) or (length(m) = 10 and mobile = m)) order by id limit 1;
  if u.id is null then raise exception 'Ye ID nahi mili'; end if;
  if u.status = 'blocked' then raise exception 'Ye ID band hai — Admin se sampark karein'; end if;
  if u.status = 'pending' then raise exception 'Aapki ID abhi verify nahi hui — Admin se sampark karein'; end if;
  return u;
end $$;

create or replace function public.crm_auth_mkt_login(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u public.crm_users := public.crm_auth_mkt_find(p); f jsonb; tk text;
begin
  if u.pin_fail >= 5 then return jsonb_build_object('error', 'ID lock ho gayi — Admin se password reset karwayein', 'locked', true); end if;
  if coalesce(u.pass_hash, '') = '' or crypt(coalesce(p ->> 'password', ''), u.pass_hash) <> u.pass_hash then
    update public.crm_users set pin_fail = pin_fail + 1 where id = u.id; perform pg_sleep(0.6);
    return jsonb_build_object('error', case when u.pin_fail + 1 >= 5 then 'ID lock ho gayi — Admin se password reset karwayein' else 'Password galat hai' end);
  end if;
  f := jsonb_build_object('uid', u.id, 'name', u.name, 'role', u.role, 'status', u.status, 'has_q', u.q1 <> '' and u.q2 <> '', 'dev_name', p ->> 'dev_name');
  if not (u.q1 <> '' and u.q2 <> '') then
    tk := encode(gen_random_bytes(24), 'hex');
    insert into public.crm_otps(user_id, purpose, code_hash, expires_at, used, ticket_hash, ticket_expires) values (u.id, 'mkt_q', '', now(), true, public.crm_h(tk), now() + interval '15 minutes');
    update public.crm_users set pin_fail = 0 where id = u.id;
    return jsonb_build_object('need_q', true, 'ticket', tk, 'name', u.name);
  end if;
  return public.crm_auth_session(f, p ->> 'device', 'crm');
end $$;

create or replace function public.crm_auth_mkt_setq(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u public.crm_users := public.crm_auth_mkt_find(p); f jsonb;
begin
  if not public.crm_auth_ticket_ok(u.id, p ->> 'ticket') then raise exception 'Samay khatam — dobara login karein'; end if;
  f := jsonb_build_object('uid', u.id, 'name', u.name, 'role', u.role, 'status', u.status, 'has_q', true, 'dev_name', p ->> 'dev_name');
  perform public.crm_auth_set_q(f, p);
  update public.crm_otps set ticket_expires = now() where user_id = u.id and ticket_hash = public.crm_h(p ->> 'ticket');
  return public.crm_auth_session(f, p ->> 'device', 'crm');
end $$;

-- password bhool gaye: security sawal → naya password (5 galat = lock, phir Admin reset)
create or replace function public.crm_auth_mkt_forgot(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_auth_mkt_find(p);
begin
  if not (u.q1 <> '' and u.q2 <> '') or u.q_fail >= 5 then return jsonb_build_object('error', 'Admin se password reset karwayein'); end if;
  return jsonb_build_object('q1', u.q1, 'q2', u.q2, 'name', u.name);
end $$;

create or replace function public.crm_auth_mkt_answer(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u public.crm_users := public.crm_auth_mkt_find(p); fails int; f jsonb;
begin
  if u.q_fail >= 5 then return jsonb_build_object('error', 'Admin se password reset karwayein'); end if;
  if length(coalesce(p ->> 'password', '')) < 8 then raise exception 'Password kam se kam 8 akshar ka ho'; end if;
  if not (coalesce(u.a1, '') <> '' and crypt(lower(trim(coalesce(p ->> 'a1', ''))), u.a1) = u.a1 and crypt(lower(trim(coalesce(p ->> 'a2', ''))), u.a2) = u.a2) then
    update public.crm_users set q_fail = q_fail + 1 where id = u.id returning q_fail into fails; perform pg_sleep(0.6);
    return jsonb_build_object('error', case when fails >= 5 then 'Admin se password reset karwayein' else 'Jawab sahi nahi hain' end);
  end if;
  update public.crm_users set pass_hash = crypt(p ->> 'password', gen_salt('bf')), q_fail = 0, pin_fail = 0 where id = u.id;
  insert into public.crm_activity(user_id, user_name, role, action, summary) values (u.id, u.name, u.role, 'pass_reset', 'Password badla (security sawal)');
  f := jsonb_build_object('uid', u.id, 'name', u.name, 'role', u.role, 'status', u.status, 'has_q', true, 'dev_name', p ->> 'dev_name');
  return public.crm_auth_session(f, p ->> 'device', 'crm');
end $$;

-- Admin: marketing user banaye / password reset / sawal reset
create or replace function public.crm_mkt_user(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); d jsonb := coalesce(p -> 'user', '{}'::jsonb); id_ bigint := nullif(d ->> 'id', '')::bigint;
        un text := lower(trim(coalesce(d ->> 'username', ''))); pw text := coalesce(d ->> 'password', ''); u public.crm_users; act text := coalesce(p ->> 'action', 'save');
begin
  if not (public.crm_is_admin(s) or public.crm_can(s, 'users.manage')) then raise exception 'Sirf Admin'; end if;
  if pw <> '' and length(pw) < 8 then raise exception 'Password kam se kam 8 akshar ka ho'; end if;
  if id_ is null then
    if un !~ '^[a-z0-9_.@-]{3,40}$' or un = 'admin' then raise exception 'Username 3-40 akshar ka ho (a-z, 0-9, _ . - @)'; end if;
    if exists (select 1 from public.crm_users where username = un) then raise exception 'Ye username pehle se liya hua hai'; end if;
    if coalesce(trim(d ->> 'name'), '') = '' then raise exception 'Naam likhein'; end if;
    if pw = '' then raise exception 'Password likhein (kam se kam 8 akshar)'; end if;
    insert into public.crm_users(role, username, name, mobile, email, pass_hash, status, perms, meta)
    values ('marketing', un, left(trim(d ->> 'name'), 80), public.crm_mobile(d ->> 'mobile'), lower(left(trim(coalesce(d ->> 'email', '')), 120)), crypt(pw, gen_salt('bf')), 'active',
      coalesce(d -> 'perms', '{}'::jsonb), jsonb_build_object('agency', left(coalesce(d ->> 'agency', ''), 120))) returning * into u;
    perform public.crm_log(s, 'user_create', 'user', u.id, 'Marketing user: ' || u.name);
    return jsonb_build_object('id', u.id, 'username', u.username);
  end if;
  select * into u from public.crm_users where id = id_ and role = 'marketing';
  if u.id is null then raise exception 'Marketing user nahi mila'; end if;
  if act = 'reset_q' then update public.crm_users set q1 = '', a1 = '', q2 = '', a2 = '', q_fail = 0 where id = u.id;
  elsif act = 'unlock' then update public.crm_users set pin_fail = 0, q_fail = 0 where id = u.id;
  else
    update public.crm_users set name = coalesce(nullif(trim(d ->> 'name'), ''), name), mobile = case when d ? 'mobile' then public.crm_mobile(d ->> 'mobile') else mobile end,
      email = case when d ? 'email' then lower(left(trim(coalesce(d ->> 'email', '')), 120)) else email end,
      status = case when d ->> 'status' in ('active', 'blocked') then d ->> 'status' else status end,
      perms = case when d ? 'perms' then coalesce(d -> 'perms', '{}'::jsonb) else perms end,
      meta = case when d ? 'agency' then meta || jsonb_build_object('agency', left(coalesce(d ->> 'agency', ''), 120)) else meta end,
      pass_hash = case when pw <> '' then crypt(pw, gen_salt('bf')) else pass_hash end,
      pin_fail = case when pw <> '' then 0 else pin_fail end, q_fail = case when pw <> '' then 0 else q_fail end
    where id = u.id returning * into u;
  end if;
  if pw <> '' or act <> 'save' or u.status <> 'active' then delete from public.crm_sessions where user_id = u.id; end if;
  perform public.crm_log(s, 'user_edit', 'user', u.id, 'Marketing user (' || act || '): ' || u.name);
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------- Round 2: Marketing & Grow (channels, agency, lead source report)
create or replace function public.crm_mkt_get(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); st public.crm_settings; m jsonb;
begin
  if not (public.crm_can(s, 'marketing.view') or public.crm_can(s, 'marketing.manage') or public.crm_can(s, 'marketing.leads')) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  select * into st from public.crm_settings where id = 1;
  m := coalesce(st.data -> 'marketing', '{}'::jsonb);
  if public.crm_can(s, 'marketing.manage') then m := m || jsonb_build_object('keys', coalesce(st.secrets -> 'mkt_keys', '{}'::jsonb)); end if;
  return m || jsonb_build_object('can_manage', public.crm_can(s, 'marketing.manage'), 'can_leads', public.crm_can(s, 'marketing.leads'));
end $$;

create or replace function public.crm_mkt_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); d jsonb := coalesce(p -> 'data', '{}'::jsonb); k jsonb := p -> 'keys';
begin
  perform public.crm_need(s, 'marketing.manage');
  if jsonb_typeof(d) <> 'object' or length(d::text) > 200000 then raise exception 'Data galat hai'; end if;
  d := d - 'keys' - 'can_manage' - 'can_leads';
  update public.crm_settings set data = jsonb_set(coalesce(data, '{}'::jsonb), '{marketing}', d),
    secrets = case when jsonb_typeof(k) = 'object' then jsonb_set(coalesce(secrets, '{}'::jsonb), '{mkt_keys}', k) else secrets end, updated_at = now() where id = 1;
  perform public.crm_log(s, 'settings', null, null, 'Marketing & Grow badla');
  return jsonb_build_object('ok', true);
end $$;

-- lead kahan se aayi: sirf ginti (naam / mobile nahi)
create or replace function public.crm_mkt_stats(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); m0 date := date_trunc('month', public.crm_today())::date; src jsonb; mon jsonb; enq jsonb;
begin
  if not public.crm_can(s, 'marketing.leads') then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('source', src_, 'leads', n, 'month', nm, 'won', w, 'lost', l, 'open', n - w - l) order by n desc), '[]') into src from (
    select coalesce(nullif(trim(data ->> 'source'), ''), 'Pata nahi') src_, count(*) n, count(*) filter (where created_at >= m0) nm,
      count(*) filter (where status = 'won') w, count(*) filter (where status = 'lost') l
    from public.crm_records where kind = 'lead' and deleted_at is null group by 1) x;
  select coalesce(jsonb_agg(jsonb_build_object('month', mo, 'leads', n, 'won', w) order by mo), '[]') into mon from (
    select to_char(created_at at time zone 'Asia/Kolkata', 'YYYY-MM') mo, count(*) n, count(*) filter (where status = 'won') w
    from public.crm_records where kind = 'lead' and deleted_at is null and created_at > now() - interval '12 months' group by 1) y;
  select coalesce(jsonb_agg(jsonb_build_object('source', c, 'enquiries', n) order by n desc), '[]') into enq from (
    select coalesce(nullif(trim(data ->> 'channel'), ''), nullif(trim(data ->> 'source'), ''), 'website') c, count(*) n from public.sp_enquiries group by 1) z;
  return jsonb_build_object('sources', src, 'months', mon, 'enquiries', enq, 'month_start', m0);
end $$;

-- ---------------------------------------------------------------- Round 2: purane galat store link theek (store link = store.sunpowers.in)
update public.crm_settings set data = jsonb_set(data, '{company,store_url}', '"https://store.sunpowers.in"')
  where id = 1 and data #>> '{company,store_url}' ~* '^https?://((www\.)?sunpowers\.in|shop\.sunpowers\.in)/?$';
update public.crm_settings set data = jsonb_set(data, '{auth,urls,store}', '"https://store.sunpowers.in"')
  where id = 1 and data #>> '{auth,urls,store}' ~* 'shop\.sunpowers\.in';
do $$ begin
  update public.sp_store set data = jsonb_set(data, '{settings,siteUrl}', '"https://store.sunpowers.in"')
    where data #>> '{settings,siteUrl}' ~* '^https?://((www\.)?sunpowers\.in|shop\.sunpowers\.in)/?$';
exception when undefined_table then null; end $$;

-- ---------------------------------------------------------------- permissions
revoke all on function public.crm_session(text), public.crm_vis(public.crm_ses, public.crm_records), public.crm_row(public.crm_ses, public.crm_records),
    public.crm_log(public.crm_ses, text, text, bigint, text), public.crm_folder_ok(public.crm_ses, bigint), public.crm_next_no(text), public.crm_stock(jsonb, int),
    public.crm_inv_recalc(bigint), public.crm_commission(bigint, public.crm_ses), public.crm_uname(bigint), public.crm_csession(text),
    public.crm_resend_key(), public.crm_mail(text[], text, text), public.crm_mail_tpl(text, text), public.crm_auth_find(text, text), public.crm_auth_status_ok(jsonb, boolean),
    public.crm_auth_send_otp(jsonb, text), public.crm_auth_backup(jsonb, jsonb), public.crm_auth_trusted(bigint, text), public.crm_auth_session(jsonb, text, text), public.crm_auth_ticket_ok(bigint, text),
    public.crm_auth_pin_check(jsonb, text), public.crm_auth_pin_valid(jsonb, text), public.crm_auth_set_q(jsonb, jsonb), public.crm_auth_store_pin(jsonb, text),
    public.crm_auth_send_link(jsonb, text), public.crm_auth_mkt_find(jsonb), public.crm_auth_who(text), public.crm_legacy(), public.crm_h(text), public.crm_mask_email(text) from public, anon, authenticated;

do $$ begin
  grant execute on function public.crm_register(jsonb), public.crm_login(jsonb), public.crm_logout(jsonb), public.crm_me(jsonb), public.crm_questions(jsonb), public.crm_reset(jsonb),
    public.crm_password(jsonb), public.crm_users_list(jsonb), public.crm_user_save(jsonb), public.crm_user_delete(jsonb), public.crm_roles_get(jsonb), public.crm_role_save(jsonb),
    public.crm_settings_get(jsonb), public.crm_settings_save(jsonb), public.crm_list(jsonb), public.crm_get(jsonb), public.crm_save(jsonb), public.crm_status(jsonb),
    public.crm_convert(jsonb), public.crm_delete(jsonb), public.crm_assign(jsonb), public.crm_lead_import(jsonb), public.crm_file_put(jsonb), public.crm_file_get(jsonb),
    public.crm_search(jsonb), public.crm_today_list(jsonb), public.crm_team_stats(jsonb), public.crm_dashboard(jsonb), public.crm_pulse(jsonb), public.crm_activity_list(jsonb),
    public.crm_orders(jsonb), public.crm_order_status(jsonb), public.crm_to_store(jsonb), public.crm_consumer_me(jsonb), public.crm_consumer_save(jsonb), public.crm_consumers(jsonb),
    public.crm_auth_mode(jsonb), public.crm_auth_start(jsonb), public.crm_auth_resend(jsonb), public.crm_auth_otp(jsonb), public.crm_auth_master(jsonb), public.crm_auth_pin(jsonb), public.crm_auth_setpin(jsonb),
    public.crm_auth_forgot(jsonb), public.crm_auth_answer(jsonb), public.crm_auth_reset_info(jsonb), public.crm_auth_reset(jsonb), public.crm_auth_register(jsonb),
    public.crm_auth_me(jsonb), public.crm_auth_device_remove(jsonb), public.crm_auth_logout_all(jsonb), public.crm_auth_change_pin(jsonb), public.crm_auth_questions(jsonb),
    public.crm_auth_admin_get(jsonb), public.crm_auth_admin_save(jsonb), public.crm_auth_test_mail(jsonb), public.crm_auth_mail_status(jsonb), public.crm_auth_user_reset(jsonb), public.crm_backup(jsonb), public.crm_auth_mkt_login(jsonb), public.crm_auth_mkt_setq(jsonb), public.crm_auth_mkt_forgot(jsonb), public.crm_auth_mkt_answer(jsonb), public.crm_mkt_user(jsonb), public.crm_mkt_get(jsonb), public.crm_mkt_save(jsonb), public.crm_mkt_stats(jsonb), public.sp_admin_crm_items(text), public.sp_admin_crm_item_set(text, bigint, text, text, text)
  to anon, authenticated;
exception when undefined_object then null; end $$;

notify pgrst, 'reload schema';
select 'Sunpowers CRM setup complete ✔' as status;
