-- ============================================================================
-- SUNPOWERS — NAYA PROJECT SETUP — part 2 of 18
-- Naya (khali) Supabase project: pehle F01..F06, phir 2-UPDATE ke U01..U12.
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (F01 -> F06, phir U01 -> U12). Safe to re-run.
-- ============================================================================

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
 {"g":"Billing","k":"accounts.manage","l":"Accounts: kharcha, P&L, GST, ITR report"},
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
 {"g":"Marketing","k":"marketing.leads","l":"Lead kahan se aayi (source report) dekhe"},
 {"g":"Dashboard & Analytics","k":"dashboard.money","l":"Dashboard par kamai, baki aur collection ke aankde dekhe"},
 {"g":"Dashboard & Analytics","k":"dashboard.team","l":"Dashboard par poori team ka kaam dekhe (warna sirf apna)"},
 {"g":"Dashboard & Analytics","k":"analytics.view","l":"Analytics menu dekhe"},
 {"g":"Dashboard & Analytics","k":"analytics.all","l":"Poori company ka analytics dekhe (warna sirf apna)"},
 {"g":"Accounts & Reports","k":"accounts.view","l":"Accounts dekhe (ledger, baki, kharcha) - sirf padhna"},
 {"g":"Accounts & Reports","k":"reports.download","l":"Reports download kare"},
 {"g":"Download / Upload","k":"sheets.download","l":"Edit ke liye sheet download kare"},
 {"g":"Download / Upload","k":"sheets.upload","l":"Edit ki hui sheet upload kare"},
 {"g":"Download / Upload","k":"sheets.manage","l":"Sabki sheet ke code dekhe aur band kare"},
 {"g":"Download / Upload","k":"items.export","l":"Inventory / stock Excel nikale"},
 {"g":"Products","k":"stock.view","l":"Stock, reserve aur expiry report dekhe"},
 {"g":"Customer flow","k":"flow.step.1","l":"Step 1: Add Customer — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.2","l":"Step 2: Conversation — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.3","l":"Step 3: Quotation — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.4","l":"Step 4: Site Visit — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.5","l":"Step 5: Blueprint — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.6","l":"Step 6: Confirmation — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.7","l":"Step 7: Apply Process — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.8","l":"Step 8: Hand Over Technician — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.9","l":"Step 9: Start Installation — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.10","l":"Step 10: Verification / Commissioning — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.11","l":"Step 11: Net Metering — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.12","l":"Step 12: Finish Work — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.13","l":"Step 13: Subsidy Redeem — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.14","l":"Step 14: Send Demo / Files — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.15","l":"Step 15: Loan / Finance — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.16","l":"Step 16: Suggest / Referral — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.17","l":"Step 17: AMC / Maintenance — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.18","l":"Step 18: Complaint Status — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.19","l":"Step 19: Leads — dekhe aur badle"},
 {"g":"Projects","k":"projects.netmetering","l":"Projects me Net Metering step khole (customer ka)"}
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