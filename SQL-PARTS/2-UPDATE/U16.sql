-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 16 of 30
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U30). Safe to re-run.
-- ============================================================================

-- =====================================================================================================
-- ROUND 38 — Online order seedha Customer + (CRM screens) customer details sirf Conversation se
-- Staging pe pehle chalayein, phir live (backup ke baad). Dobara chalana safe hai.
-- Badlav:
--   1) Store / online order: Leads me NAHI jata. Hamesha Customers me (stage = customer, path = Online Store).
--      Pata / shahar / pincode adhura ho to bhi customer banta hai — CRM me "Details adhuri" dikhega, Conversation me bharna hai.
--   2) Purane customer (same mobile) ka naya order: naya customer / lead nahi — uske record ke "Dobara sampark" me order judta hai.
--   3) Purana raasta (adhura order -> Lead) hata diya.
-- =====================================================================================================

CREATE OR REPLACE FUNCTION public.crm_rules_trg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    -- Round 38: online (store) order = customer even if address is incomplete; it is marked 'Details adhuri' and completed in Conversation
    if TG_OP = 'INSERT' and coalesce(d ->> 'type', 'customer') <> 'supplier' and coalesce(current_setting('sp.order', true), '') <> '1' then
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
end $function$;

create or replace function public.crm_order_customer(p_data jsonb, p_oid bigint) returns bigint language plpgsql security definer set search_path = public as $$
declare mob text := public.crm_mobile(coalesce(p_data ->> 'phone', p_data ->> 'mobile', '')); nm text := left(trim(coalesce(p_data ->> 'name', '')), 120); pid bigint; items text;
        ad text := trim(coalesce(p_data ->> 'address', '')); ct text := trim(coalesce(p_data ->> 'city', '')); pin text := regexp_replace(coalesce(p_data ->> 'pincode', ''), '\D', '', 'g');
        em text := nullif(lower(trim(coalesce(p_data ->> 'email', ''))), '');
begin
  if mob !~ '^[6-9][0-9]{9}$' then return null; end if;
  if nm = '' then nm := 'Online customer ' || right(mob, 4); end if;
  select left(string_agg(coalesce(i ->> 'title', ''), ', '), 180) into items from jsonb_array_elements(case when jsonb_typeof(p_data -> 'items') = 'array' then p_data -> 'items' else '[]'::jsonb end) i;
  select id into pid from public.crm_records where kind = 'party' and deleted_at is null and mobile = mob order by id limit 1;
  if pid is not null then
    -- purana customer: naya order usi ke record par (Dobara sampark) — kabhi doosra customer / lead nahi. Order = customer (stage).
    perform set_config('sp.stage_ok', '1', true);
    update public.crm_records set data = (case when coalesce(data -> 'inquiries', '[]'::jsonb) @> jsonb_build_array(jsonb_build_object('order_id', p_oid)) or jsonb_array_length(coalesce(data -> 'inquiries', '[]'::jsonb)) >= 60 then data
        else jsonb_set(data, '{inquiries}', coalesce(data -> 'inquiries', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('at', public.crm_iso_now(), 'source', 'Online Store order', 'order_id', p_oid,
          'note', 'Store order #' || p_oid || coalesce(' — ' || nullif(items, ''), '')))) end)
        || case when coalesce(data ->> 'type', 'customer') = 'supplier' then '{}'::jsonb else jsonb_build_object('stage', 'customer') end, updated_at = now()
      where id = pid;
    perform set_config('sp.stage_ok', '', true);
    return pid;
  end if;
  perform set_config('sp.order', '1', true);
  insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, due_at, data, search, created_by)
    values ('party', nm, mob, 'active', 0, null, null,
      jsonb_strip_nulls(jsonb_build_object('name', nm, 'mobile', mob, 'email', em, 'address', nullif(ad, ''), 'city', nullif(ct, ''), 'pincode', case when pin ~ '^[0-9]{6}$' then pin end,
        'type', 'customer', 'source', 'Online Store', 'cust_kind', 'product', 'segment', 'b2c', 'interest', coalesce(nullif(items, ''), 'Online Store order'),
        'store_order_id', p_oid, 'intake', 'store', 'stage', 'customer')),
      lower(concat_ws(' ', nm, mob, ct)), 0)
    returning id into pid;
  perform set_config('sp.order', '', true);
  return pid;
end $$;
create or replace function public.crm_order_customer(p_data jsonb, p_oid bigint) returns bigint language plpgsql security definer set search_path = public as $$
declare mob text := public.crm_mobile(coalesce(p_data ->> 'phone', p_data ->> 'mobile', '')); nm text := left(trim(coalesce(p_data ->> 'name', '')), 120); pid bigint; items text;
        ad text := trim(coalesce(p_data ->> 'address', '')); ct text := trim(coalesce(p_data ->> 'city', '')); pin text := regexp_replace(coalesce(p_data ->> 'pincode', ''), '\D', '', 'g');
        em text := nullif(lower(trim(coalesce(p_data ->> 'email', ''))), '');
        tpl public.crm_records; ck text := 'product'; ptyp text; kwv text;
begin
  if mob !~ '^[6-9][0-9]{9}$' then return null; end if;
  if nm = '' then nm := 'Online customer ' || right(mob, 4); end if;
  select left(string_agg(coalesce(i ->> 'title', ''), ', '), 180) into items from jsonb_array_elements(case when jsonb_typeof(p_data -> 'items') = 'array' then p_data -> 'items' else '[]'::jsonb end) i;
  select c.* into tpl from jsonb_array_elements(case when jsonb_typeof(p_data -> 'items') = 'array' then p_data -> 'items' else '[]'::jsonb end) i
    join public.crm_records c on c.kind = 'item' and c.deleted_at is null and c.data ->> 'type' = 'project' and (c.data #>> '{store,store_id}') = (i ->> 'id') order by c.id limit 1;
  if tpl.id is not null then
    ck := 'project'; kwv := nullif(tpl.data ->> 'kw', '');
    ptyp := case when tpl.data ->> 'category' in ('Residential', 'Commercial', 'Industrial') then tpl.data ->> 'category' when tpl.data ->> 'category' like 'VFD%' then 'VFD' else null end;
  end if;
  select id into pid from public.crm_records where kind = 'party' and deleted_at is null and mobile = mob order by id limit 1;
  if pid is not null then
    -- purana customer: naya order usi ke record par (Dobara sampark) — kabhi doosra customer / lead nahi. Order = customer (stage).
    perform set_config('sp.stage_ok', '1', true);
    update public.crm_records set data = (case when coalesce(data -> 'inquiries', '[]'::jsonb) @> jsonb_build_array(jsonb_build_object('order_id', p_oid)) or jsonb_array_length(coalesce(data -> 'inquiries', '[]'::jsonb)) >= 60 then data
        else jsonb_set(data, '{inquiries}', coalesce(data -> 'inquiries', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('at', public.crm_iso_now(), 'source', 'Online Store order', 'order_id', p_oid,
          'note', 'Store order #' || p_oid || coalesce(' — ' || nullif(items, ''), '')))) end)
        || case when coalesce(data ->> 'type', 'customer') = 'supplier' then '{}'::jsonb else jsonb_build_object('stage', 'customer') end
        || case when ck = 'project' and coalesce(data ->> 'cust_kind', '') in ('', 'product') then jsonb_strip_nulls(jsonb_build_object('cust_kind', 'project', 'project_type', ptyp, 'kw', kwv)) else '{}'::jsonb end, updated_at = now()
      where id = pid;
    perform set_config('sp.stage_ok', '', true);
    return pid;
  end if;
  perform set_config('sp.order', '1', true);
  insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, due_at, data, search, created_by)
    values ('party', nm, mob, 'active', 0, null, null,
      jsonb_strip_nulls(jsonb_build_object('name', nm, 'mobile', mob, 'email', em, 'address', nullif(ad, ''), 'city', nullif(ct, ''), 'pincode', case when pin ~ '^[0-9]{6}$' then pin end,
        'type', 'customer', 'source', 'Online Store', 'cust_kind', ck, 'project_type', ptyp, 'kw', kwv, 'segment', 'b2c', 'interest', coalesce(nullif(items, ''), 'Online Store order'),
        'store_order_id', p_oid, 'intake', 'store', 'stage', 'customer')),
      lower(concat_ws(' ', nm, mob, ct)), 0)
    returning id into pid;
  perform set_config('sp.order', '', true);
  return pid;
end $$;

-- ============================================================================
-- ROUND 45 — HR role, All Staffs (HR details), Salary & Pay (-> Accounts Kharcha), Partners ke liye alag menu (staging only)
--   Naye permission: staff.view (directory), staff.manage (staff ID jode/badle, permission ke bina), staff.hr (HR details), salary.manage (salary/advance/pay)
--   Naya role: hr. Salary / bank / ID sirf staff.hr / salary.manage / Admin ko; baaki sirf directory (naam, role, mobile, designation).
-- ============================================================================
do $$ begin
  alter table public.crm_users drop constraint if exists crm_users_role_check;
  alter table public.crm_users add constraint crm_users_role_check check (role in ('admin','manager','staff','dealer','influencer','consumer','marketing','hr'));
end $$;
insert into public.crm_roles(role, perms) values ('hr', '{"staff.view":true,"staff.manage":true,"staff.hr":true,"salary.manage":true,"team.stats":true,"docs.view":true,"docs.upload":true}') on conflict (role) do nothing;
update public.crm_roles set perms = perms || '{"staff.view":true}'::jsonb where role in ('manager', 'staff') and not (perms ? 'staff.view');

create table if not exists public.crm_staff_hr (
  user_id    bigint primary key,
  hr         jsonb not null default '{}'::jsonb,
  sal        jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by bigint
);
create table if not exists public.crm_salary_pay (
  id         bigserial primary key,
  user_id    bigint not null,
  month      text not null check (month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  basic      numeric(12,2) not null default 0,
  allowance  numeric(12,2) not null default 0,
  bonus      numeric(12,2) not null default 0,
  deduction  numeric(12,2) not null default 0,
  adv_cut    numeric(12,2) not null default 0,
  net        numeric(12,2) not null check (net > 0),
  paid_on    date not null,
  mode       text not null default 'bank',
  note       text not null default '',
  expense_id bigint,
  created_by bigint,
  created_at timestamptz not null default now(),
  deleted_at timestamptz, deleted_by bigint, delete_reason text
);
create unique index if not exists crm_salary_pay_um on public.crm_salary_pay(user_id, month) where deleted_at is null;
create table if not exists public.crm_staff_adv (
  id         bigserial primary key,
  user_id    bigint not null,
  given_on   date not null,
  amount     numeric(12,2) not null check (amount > 0),
  mode       text not null default 'cash',
  note       text not null default '',
  expense_id bigint,
  created_by bigint,
  created_at timestamptz not null default now(),
  deleted_at timestamptz, deleted_by bigint, delete_reason text
);
alter table public.crm_staff_hr enable row level security;
alter table public.crm_salary_pay enable row level security;
alter table public.crm_staff_adv enable row level security;
revoke all on public.crm_staff_hr, public.crm_salary_pay, public.crm_staff_adv from anon, authenticated;

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
 {"g":"Projects","k":"projects.netmetering","l":"Projects me Net Metering step khole (customer ka)"},
 {"g":"Staff & HR","k":"staff.view","l":"All Staffs list dekhe (naam, role, mobile)"},
 {"g":"Staff & HR","k":"staff.manage","l":"Staff ID jode / badle (Manager, Staff) — permission badle bina"},
 {"g":"Staff & HR","k":"staff.hr","l":"Staff ki HR details dekhe / badle (job, qualification, bank, ID)"},
 {"g":"Staff & HR","k":"salary.manage","l":"Salary set kare, advance de, salary pay kare"}
]'::jsonb $$;

-- backup now includes the expenses ledger
create or replace function public.crm_backup(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pe text; part text := coalesce(p ->> 'part', 'meta');
  off int := greatest(coalesce((p ->> 'offset')::int, 0), 0); lim int; r jsonb; cnt jsonb := '{}'::jsonb; t text;
  parts text[] := array['crm_settings', 'crm_auth_admin', 'crm_roles', 'crm_users', 'crm_records', 'crm_counters', 'crm_activity', 'sp_store', 'sp_orders', 'sp_enquiries', 'crm_files', 'crm_expenses', 'sp_design_pay'];
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  pe := public.crm_auth_pin_check(public.crm_auth_find('admin', 'admin'), p ->> 'pin');
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

create or replace function public.crm_role_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r text := p ->> 'role';
begin
  if not public.crm_is_admin(s) then raise exception 'Role permission sirf Admin badal sakta hai'; end if;
  if r not in ('manager', 'staff', 'dealer', 'influencer', 'hr') then raise exception 'Role galat hai'; end if;
  if jsonb_typeof(p -> 'perms') <> 'object' then raise exception 'Data galat hai'; end if;
  insert into public.crm_roles(role, perms) values (r, p -> 'perms') on conflict (role) do update set perms = excluded.perms;
  perform public.crm_log(s, 'role_edit', 'role', null, 'Role permission badli: ' || r);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.crm_user_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); u public.crm_users; full_ boolean; d jsonb := coalesce(p -> 'user', '{}'::jsonb); id_ bigint := nullif(d ->> 'id', '')::bigint;
        r text := lower(coalesce(d ->> 'role', '')); un text := lower(trim(coalesce(d ->> 'username', ''))); m text := public.crm_mobile(d ->> 'mobile'); code text; i int := 0;
begin
  full_ := public.crm_can(s, 'users.manage');
  if not full_ then perform public.crm_need(s, 'staff.manage'); end if;
  if r <> '' and r not in ('admin', 'manager', 'staff', 'dealer', 'influencer', 'consumer', 'marketing', 'hr') then raise exception 'Role galat hai'; end if;
  if not full_ then
    /* HR / staff.manage: sirf Manager & Staff ID; permission, commission, discount, password nahi badal sakte */
    if r <> '' and r not in ('manager', 'staff') then raise exception 'Aap sirf Manager ya Staff ID bana / badal sakte hain'; end if;
    d := d - 'perms' - 'meta' - 'password';
    if id_ is not null and coalesce((select role from public.crm_users where id = id_), '') not in ('manager', 'staff', 'marketing') then raise exception 'Is ID ko aap nahi badal sakte'; end if;
  end if;
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

create or replace function public.crm_users_list(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); full_ boolean; hrv boolean; dir_ boolean;
begin
  full_ := public.crm_can(s, 'users.manage');
  hrv := public.crm_can(s, 'staff.manage') or public.crm_can(s, 'staff.hr') or public.crm_can(s, 'salary.manage');
  dir_ := hrv or public.crm_can(s, 'staff.view');
  if not full_ and not dir_ and not (public.crm_can(s, 'leads.assign') or public.crm_can(s, 'reminders.assign') or public.crm_can(s, 'customers.assign') or public.crm_can(s, 'earnings.manage') or public.crm_can(s, 'team.stats') or public.crm_can(s, 'docs.folders')) then
    return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(case when full_ then jsonb_build_object('id', u.id, 'role', u.role, 'username', u.username, 'name', u.name, 'mobile', u.mobile, 'email', u.email, 'status', u.status,
        'ref_code', u.ref_code, 'perms', u.perms, 'meta', u.meta, 'created_at', u.created_at, 'last_seen', u.last_seen, 'designation', h.hr ->> 'designation')
      else jsonb_build_object('id', u.id, 'role', u.role, 'name', u.name, 'status', u.status, 'ref_code', u.ref_code)
        || case when dir_ and u.role in ('admin', 'manager', 'staff', 'hr', 'marketing') then jsonb_build_object('mobile', u.mobile, 'designation', h.hr ->> 'designation') else '{}'::jsonb end
        || case when hrv and u.role in ('admin', 'manager', 'staff', 'hr', 'marketing') then jsonb_build_object('email', u.email, 'username', u.username, 'last_seen', u.last_seen, 'created_at', u.created_at) else '{}'::jsonb end
      end order by u.role, u.name)
    from public.crm_users u left join public.crm_staff_hr h on h.user_id = u.id where u.role <> 'consumer' or full_), '[]'::jsonb);
end $$;