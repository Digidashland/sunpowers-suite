-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 3 of 12
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U12). Safe to re-run.
-- ============================================================================

-- (2) accounts report: P&L + GST (output / input / net) + ITR summary + month-wise ----------
create or replace function public.crm_acct_report(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); fr date := (p ->> 'from')::date; t date := (p ->> 'to')::date;
  sales numeric; sdisc numeric; sgst numeric; scnt int; b2b numeric; b2c numeric; coll numeric; pur numeric; pgst numeric; pcnt int;
  ex numeric; exg numeric; rev numeric; gross numeric; net numeric; due numeric; payable numeric; cats jsonb; mon jsonb; rates jsonb;
begin
  if not (public.crm_can(s, 'accounts.manage') or public.crm_can(s, 'accounts.view')) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  if fr is null or t is null or t < fr or t - fr > 800 then raise exception 'Sahi tareekh range chunein (max 2 saal)'; end if;
  create temp table if not exists _inv(id bigint, d date, sub numeric, disc numeric, gst numeric, gstin text, lines jsonb) on commit drop;
  truncate _inv;
  insert into _inv select r.id, coalesce(nullif(r.data ->> 'date', '')::date, (r.created_at at time zone 'Asia/Kolkata')::date), public.crm_num(r.data -> 'subtotal'), public.crm_num(r.data -> 'discount'),
      public.crm_num(r.data -> 'gst_total'), coalesce((select nullif(trim(pp.data ->> 'gstin'), '') from public.crm_records pp where pp.id = r.party_id), ''), coalesce(r.data -> 'lines', '[]'::jsonb)
    from public.crm_records r where r.kind = 'invoice' and r.deleted_at is null and r.status <> 'cancelled';
  select coalesce(sum(sub), 0), coalesce(sum(disc), 0), coalesce(sum(gst), 0), count(*), coalesce(sum(sub - disc) filter (where gstin <> ''), 0), coalesce(sum(sub - disc) filter (where gstin = ''), 0)
    into sales, sdisc, sgst, scnt, b2b, b2c from _inv where d between fr and t;
  select coalesce(sum(r.amount), 0) into coll from public.crm_records r where r.kind = 'payment' and r.deleted_at is null
    and coalesce(nullif(r.data ->> 'date', '')::date, (r.created_at at time zone 'Asia/Kolkata')::date) between fr and t;
  select coalesce(sum(public.crm_num(r.data -> 'subtotal') - public.crm_num(r.data -> 'discount')), 0), coalesce(sum(public.crm_num(r.data -> 'gst_total')), 0), count(*) into pur, pgst, pcnt
    from public.crm_records r where r.kind = 'purchase' and r.deleted_at is null and r.status = 'received'
    and coalesce(nullif(r.data ->> 'date', '')::date, (r.created_at at time zone 'Asia/Kolkata')::date) between fr and t;
  select coalesce(sum(amount - gst_amount), 0), coalesce(sum(gst_amount), 0) into ex, exg from public.crm_expenses where deleted_at is null and spent_on between fr and t;
  select coalesce(jsonb_agg(jsonb_build_object('category', category, 'amount', a, 'gst', g) order by a desc), '[]') into cats
    from (select category, sum(amount) a, sum(gst_amount) g from public.crm_expenses where deleted_at is null and spent_on between fr and t group by category) x;
  rev := sales - sdisc; gross := rev - pur; net := gross - ex;
  select coalesce(sum(r.amount - public.crm_num(r.data -> 'paid')), 0) into due from public.crm_records r where r.kind = 'invoice' and r.deleted_at is null and r.status in ('due', 'partial');
  select coalesce(sum(r.amount), 0) into payable from public.crm_records r where r.kind = 'purchase' and r.deleted_at is null and r.status = 'open';
  select coalesce(jsonb_agg(jsonb_build_object('month', m, 'sales', sl, 'gst_out', go, 'purchase', pu, 'gst_in', gi, 'expense', e, 'profit', sl - pu - e) order by m), '[]') into mon from (
    select to_char(g, 'YYYY-MM') m,
      coalesce((select sum(sub - disc) from _inv where to_char(d, 'YYYY-MM') = to_char(g, 'YYYY-MM') and d between fr and t), 0) sl,
      coalesce((select sum(gst) from _inv where to_char(d, 'YYYY-MM') = to_char(g, 'YYYY-MM') and d between fr and t), 0) go,
      coalesce((select sum(public.crm_num(r.data -> 'subtotal') - public.crm_num(r.data -> 'discount')) from public.crm_records r where r.kind = 'purchase' and r.deleted_at is null and r.status = 'received'
        and to_char(coalesce(nullif(r.data ->> 'date', '')::date, (r.created_at at time zone 'Asia/Kolkata')::date), 'YYYY-MM') = to_char(g, 'YYYY-MM')
        and coalesce(nullif(r.data ->> 'date', '')::date, (r.created_at at time zone 'Asia/Kolkata')::date) between fr and t), 0) pu,
      coalesce((select sum(public.crm_num(r.data -> 'gst_total')) from public.crm_records r where r.kind = 'purchase' and r.deleted_at is null and r.status = 'received'
        and to_char(coalesce(nullif(r.data ->> 'date', '')::date, (r.created_at at time zone 'Asia/Kolkata')::date), 'YYYY-MM') = to_char(g, 'YYYY-MM')
        and coalesce(nullif(r.data ->> 'date', '')::date, (r.created_at at time zone 'Asia/Kolkata')::date) between fr and t), 0)
        + coalesce((select sum(gst_amount) from public.crm_expenses where deleted_at is null and to_char(spent_on, 'YYYY-MM') = to_char(g, 'YYYY-MM') and spent_on between fr and t), 0) gi,
      coalesce((select sum(amount - gst_amount) from public.crm_expenses where deleted_at is null and to_char(spent_on, 'YYYY-MM') = to_char(g, 'YYYY-MM') and spent_on between fr and t), 0) e
    from generate_series(date_trunc('month', fr)::date, date_trunc('month', t)::date, interval '1 month') g) q;
  select coalesce(jsonb_agg(jsonb_build_object('rate', rt, 'taxable', tx, 'gst', gs) order by rt), '[]') into rates from (
    select public.crm_num(l -> 'gst') rt, sum(public.crm_num(l -> 'qty') * public.crm_num(l -> 'price')) tx, sum(public.crm_num(l -> 'qty') * public.crm_num(l -> 'price') * public.crm_num(l -> 'gst') / 100) gs
    from _inv i, jsonb_array_elements(i.lines) l where i.d between fr and t group by 1) z;
  return jsonb_build_object('from', fr, 'to', t, 'sales_taxable', sales, 'discount', sdisc, 'revenue', rev, 'invoices', scnt, 'b2b', b2b, 'b2c', b2c, 'collected', coll,
    'purchase', pur, 'purchases', pcnt, 'expense', ex, 'expense_gst', exg, 'expense_by_category', cats,
    'gst_output', sgst, 'gst_input', pgst + exg, 'gst_net', sgst - pgst - exg, 'gross_profit', gross, 'net_profit', net,
    'receivable', due, 'payable', payable, 'months', mon, 'rates', rates,
    'itr', jsonb_build_object('turnover', rev, 'presumptive_6', round(rev * 0.06, 2), 'presumptive_8', round(rev * 0.08, 2), 'books_profit', net));
end $$;

-- (3) restore (merge by id) — Admin + PIN. Settings, users, login data and history are NEVER touched. ----


create or replace function public.crm_restore(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pe text; part text := coalesce(p ->> 'part', ''); rows jsonb := coalesce(p -> 'rows', '[]'::jsonb);
  allowed text[] := array['crm_records', 'crm_counters', 'crm_expenses', 'sp_orders', 'sp_enquiries', 'sp_store', 'crm_files', 'sp_design_pay'];
  cols text; setl text; n int := 0; pk text;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  pe := public.crm_auth_pin_check(public.crm_auth_find('admin', 'admin'), p ->> 'pin');
  if pe is not null then return jsonb_build_object('error', pe); end if;
  if not (part = any (allowed)) or to_regclass('public.' || part) is null then raise exception 'Ye hissa wapas nahi laya ja sakta: %', part; end if;
  if jsonb_typeof(rows) <> 'array' then raise exception 'Backup file galat hai'; end if;
  if jsonb_array_length(rows) > 600 then raise exception 'Ek baar me bahut zyada rows'; end if;
  if jsonb_array_length(rows) = 0 then return jsonb_build_object('part', part, 'restored', 0); end if;
  perform set_config('sp.restoring', 'on', true);
  pk := case part when 'crm_counters' then 'key' when 'sp_store' then 'id' else 'id' end;
  if part = 'crm_files' then
    insert into public.crm_files(id, rec_id, mime, size, data)
    select (x ->> 'id')::bigint, (x ->> 'rec_id')::bigint, coalesce(x ->> 'mime', 'application/octet-stream'), coalesce((x ->> 'size')::int, 0), decode(x ->> 'b64', 'base64')
    from jsonb_array_elements(rows) x
    on conflict (id) do update set rec_id = excluded.rec_id, mime = excluded.mime, size = excluded.size, data = excluded.data;
    get diagnostics n = row_count;
  else
    select string_agg(format('%I', column_name), ', ' order by ordinal_position),
           string_agg(case when column_name = pk then null when part = 'crm_counters' and column_name = 'n' then 'n = greatest(public.crm_counters.n, excluded.n)' else format('%1$I = excluded.%1$I', column_name) end, ', ' order by ordinal_position)
      into cols, setl from information_schema.columns where table_schema = 'public' and table_name = part;
    if part = 'crm_records' then
      -- never bring back a row that was removed for good on purpose: deleted rows stay as the backup has them
      null;
    end if;
    execute format('insert into public.%1$I (%2$s) select %2$s from jsonb_populate_recordset(null::public.%1$I, $1) on conflict (%3$I) do update set %4$s', part, cols, pk, setl) using rows;
    get diagnostics n = row_count;
  end if;
  if part in ('crm_records', 'crm_expenses', 'sp_orders', 'sp_enquiries', 'crm_files', 'sp_design_pay') and pg_get_serial_sequence('public.' || part, 'id') is not null then
    execute format('select setval(pg_get_serial_sequence(%L, ''id''), greatest((select coalesce(max(id), 1) from public.%I), 1))', 'public.' || part, part);
  end if;
  perform public.crm_log(s, 'restore', part, null, 'Backup se wapas laya: ' || part || ' (' || n || ' rows)');
  return jsonb_build_object('part', part, 'restored', n);
end $$;

-- permission list shows the new Accounts permission
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

do $$ declare f text; begin
  foreach f in array array['public.crm_exp_list(jsonb)', 'public.crm_exp_save(jsonb)', 'public.crm_exp_del(jsonb)', 'public.crm_acct_report(jsonb)', 'public.crm_restore(jsonb)', 'public.crm_backup(jsonb)'] loop
    execute 'revoke all on function ' || f || ' from public';
    execute 'grant execute on function ' || f || ' to anon, authenticated';
  end loop;
end $$;

notify pgrst, 'reload schema';

-- ============================================================================
-- ROUND 10 (database) — Pincode-wise product availability. Run AFTER everything above. Safe to re-run.
-- ============================================================================
-- ============================================================================
-- ROUND 10 (database) — Pincode-wise availability.  Run AFTER phase1..phase6.  Safe to re-run.
--   * sp_pin_master : India Post pincode -> state / district (aap Store Admin se ek baar upload karte hain)
--   * sp_pin_rules  : product x (all / state / district / area / pincode) x (out / in)
--   * sp_pin_areas  : aapke custom areas (naam + pincodes)
--   * sp_pin_modes  : "sirf in pincodes par online dikhao" (only-mode) per product
--   * sp_pin_check  : customer ke pincode par kaun se products available nahi (public, sirf padhta hai)
--   * sp_place_order: order ke time bhi server dobara check karta hai (browser bypass nahi kar sakta)
-- Rule jeetne ka kram (sabse specific jeetta hai):  pincode > custom area > district > state > all ;
--   barabari par "product ka apna rule" > "sab products (*)" rule ; phir bhi barabari ho to OUT jeetta hai.
-- ============================================================================

create table if not exists public.sp_pin_master (
  pincode    text primary key check (pincode ~ '^[1-9][0-9]{5}$'),
  office     text not null default '',
  district   text not null default '',
  state      text not null default '',
  district_u text not null default '',
  state_u    text not null default ''
);
create index if not exists sp_pin_master_sd on public.sp_pin_master (state_u, district_u);

create table if not exists public.sp_pin_areas (
  name       text primary key,                 -- UPPER(trim(label))
  label      text not null,
  pins       text[] not null default '{}',
  updated_at timestamptz not null default now()
);

create table if not exists public.sp_pin_rules (
  id         bigserial primary key,
  product_id text not null,                    -- store product id, or '*' = sab products
  scope      text not null check (scope in ('all','state','district','area','pin')),
  value      text not null,                    -- all='*' | state='UTTAR PRADESH' | district='UTTAR PRADESH|LUCKNOW' | area='NAAM' | pin='226001'
  status     text not null check (status in ('out','in')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (product_id, scope, value)
);
create index if not exists sp_pin_rules_sv on public.sp_pin_rules (scope, value);
create index if not exists sp_pin_rules_p on public.sp_pin_rules (product_id);

create table if not exists public.sp_pin_modes (
  product_id text primary key,                 -- product id or '*'
  mode       text not null check (mode in ('only','default'))
);

alter table public.sp_pin_master enable row level security;
alter table public.sp_pin_areas  enable row level security;
alter table public.sp_pin_rules  enable row level security;
alter table public.sp_pin_modes  enable row level security;
do $$ begin
  revoke all on public.sp_pin_master, public.sp_pin_areas, public.sp_pin_rules, public.sp_pin_modes from anon, authenticated;
  revoke all on sequence public.sp_pin_rules_id_seq from anon, authenticated;
exception when undefined_object then null; end $$;

-- ---------- helpers -------------------------------------------------------------------------
create or replace function public.sp_pin_norm(p text) returns text language sql immutable as $$
  select upper(btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g')))
$$;

-- scope + value ko ek hi roop me badalta hai (galat ho to NULL)
create or replace function public.sp_pin_val(p_scope text, p_value text) returns text language plpgsql immutable as $$
declare v text; a text; b text;
begin
  if p_scope = 'all' then return '*'; end if;
  if p_scope = 'pin' then v := regexp_replace(coalesce(p_value, ''), '\D', '', 'g'); return case when v ~ '^[1-9][0-9]{5}$' then v end; end if;
  if p_scope in ('state', 'area') then v := public.sp_pin_norm(p_value); return nullif(v, ''); end if;
  if p_scope = 'district' then
    a := public.sp_pin_norm(split_part(coalesce(p_value, ''), '|', 1)); b := public.sp_pin_norm(split_part(coalesce(p_value, ''), '|', 2));
    if a = '' or b = '' then return null; end if;
    return a || '|' || b;
  end if;
  return null;
end $$;

-- kya koi niyam laga hai? (nahi to storefront par kuch bhi nahi dikhta)
create or replace function public.sp_pin_enabled() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.sp_pin_rules) or exists (select 1 from public.sp_pin_modes where mode = 'only')
$$;

-- core: in products me se jo is pincode par available NAHI hain unki id
create or replace function public.sp_pin_unavail(p_pin text, p_ids text[]) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare st text; di text; res text[];
begin
  select state_u, district_u into st, di from public.sp_pin_master where pincode = p_pin;
  with ids as (select distinct x as id from unnest(coalesce(p_ids, '{}'::text[])) x where x is not null),
  cand as (
    select i.id, r.status,
      (case r.scope when 'pin' then 5 when 'area' then 4 when 'district' then 3 when 'state' then 2 else 1 end) * 10
        + (case when r.product_id = '*' then 0 else 1 end) as rk
    from ids i
    join public.sp_pin_rules r on r.product_id in (i.id, '*')
    where r.scope = 'all'
       or (r.scope = 'pin' and r.value = p_pin)
       or (r.scope = 'state' and st is not null and r.value = st)
       or (r.scope = 'district' and st is not null and r.value = st || '|' || di)
       or (r.scope = 'area' and exists (select 1 from public.sp_pin_areas a where a.name = r.value and p_pin = any (a.pins)))
  ),
  best as (select distinct on (id) id, status from cand order by id, rk desc, (status = 'out') desc)
  select coalesce(array_agg(i.id order by i.id), '{}') into res
  from ids i
  left join best b on b.id = i.id
  where case
          when coalesce((select mode from public.sp_pin_modes m where m.product_id = i.id),
                        (select mode from public.sp_pin_modes m where m.product_id = '*'), 'default') = 'only'
            then b.status is distinct from 'in'
          else b.status = 'out'
        end;
  return res;
end $$;

-- ---------- public (customer) ---------------------------------------------------------------
create or replace function public.sp_pin_check(p_pin text, p_ids jsonb default '[]'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pin text := regexp_replace(coalesce(p_pin, ''), '\D', '', 'g'); ids text[]; en boolean := public.sp_pin_enabled(); m record; kn boolean;
begin
  if jsonb_typeof(coalesce(p_ids, '[]'::jsonb)) <> 'array' then raise exception 'Invalid list'; end if;
  if jsonb_array_length(coalesce(p_ids, '[]'::jsonb)) > 2000 then raise exception 'Too many products'; end if;
  if pin !~ '^[1-9][0-9]{5}$' then return jsonb_build_object('enabled', en, 'valid', false, 'bad', '[]'::jsonb); end if;
  select * into m from public.sp_pin_master where pincode = pin; kn := found;
  if not en then
    return jsonb_build_object('enabled', false, 'valid', true, 'pin', pin, 'known', kn, 'state', coalesce(m.state, ''), 'district', coalesce(m.district, ''), 'bad', '[]'::jsonb);
  end if;
  select coalesce(array_agg(x), '{}') into ids from jsonb_array_elements_text(coalesce(p_ids, '[]'::jsonb)) x;
  return jsonb_build_object('enabled', true, 'valid', true, 'pin', pin, 'known', kn, 'state', coalesce(m.state, ''), 'district', coalesce(m.district, ''),
                            'bad', to_jsonb(public.sp_pin_unavail(pin, ids)));
end $$;

-- order ke time: cart ke koi product is pincode par available na ho to order nahi banega
create or replace function public.sp_pin_guard(p_pin text, p_items jsonb) returns void
language plpgsql stable security definer set search_path = public as $$
declare pin text := regexp_replace(coalesce(p_pin, ''), '\D', '', 'g'); ids text[]; bad text[]; names text;
begin
  if not public.sp_pin_enabled() then return; end if;
  if pin !~ '^[1-9][0-9]{5}$' then raise exception 'Pincode (6 ank) dalna zaruri hai'; end if;
  select coalesce(array_agg(i ->> 'id'), '{}') into ids from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) i where coalesce(i ->> 'id', '') <> '';
  bad := public.sp_pin_unavail(pin, ids);
  if coalesce(array_length(bad, 1), 0) > 0 then
    select string_agg(coalesce(nullif(i ->> 'title', ''), i ->> 'id'), ', ') into names from jsonb_array_elements(p_items) i where (i ->> 'id') = any (bad);
    raise exception 'NOT_AVAILABLE_AT_PIN: Pincode % par ye product available nahi hain: %. Pincode badlein ya inhe cart se hata dein.', pin, left(coalesce(names, ''), 300);
  end if;
end $$;

-- ---------- order: Round 8 wala order + pincode guard ---------------------------------------

-- "sirf chuncho pincode" mode tabhi rakho jab uske liye koi "available" niyam bacha ho (warna product kahin bhi nahi dikhega)
create or replace function public.sp_pin_modes_gc() returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  delete from public.sp_pin_modes m
   where m.mode = 'only'
     and not exists (select 1 from public.sp_pin_rules r where r.status = 'in' and (m.product_id = '*' or r.product_id in (m.product_id, '*')));
  get diagnostics n = row_count; return n;
end $$;

-- ---------- admin (Store Admin: sp_check) ----------------------------------------------------
create or replace function public.sp_pin_admin_info(p_pass text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  perform public.sp_check(p_pass);
  return jsonb_build_object(
    'master', (select count(*) from public.sp_pin_master),
    'states', coalesce((select jsonb_agg(jsonb_build_object('s', s.state_u, 'd', s.ds) order by s.state_u)
                from (select state_u, array_agg(distinct district_u order by district_u) as ds from public.sp_pin_master where state_u <> '' group by state_u) s), '[]'::jsonb),
    'rules', (select count(*) from public.sp_pin_rules),
    'areas', (select count(*) from public.sp_pin_areas),
    'modes', coalesce((select jsonb_agg(jsonb_build_object('product_id', product_id, 'mode', mode)) from public.sp_pin_modes), '[]'::jsonb));
end $$;

create or replace function public.sp_pin_master_load(p_pass text, p_rows jsonb, p_clear boolean default false) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare ok int := 0; bad int := 0; r jsonb; pin text;
begin
  perform public.sp_check(p_pass);
  if jsonb_typeof(p_rows) <> 'array' then raise exception 'Invalid rows'; end if;
  if jsonb_array_length(p_rows) > 6000 then raise exception 'Ek baar me 6000 se zyada rows nahi'; end if;
  if p_clear then delete from public.sp_pin_master; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    pin := regexp_replace(coalesce(r ->> 'p', ''), '\D', '', 'g');
    if pin !~ '^[1-9][0-9]{5}$' or public.sp_pin_norm(r ->> 's') = '' then bad := bad + 1; continue; end if;
    insert into public.sp_pin_master(pincode, office, district, state, district_u, state_u)
    values (pin, left(coalesce(r ->> 'o', ''), 120), left(btrim(coalesce(r ->> 'd', '')), 80), left(btrim(coalesce(r ->> 's', '')), 80),
            left(public.sp_pin_norm(r ->> 'd'), 80), left(public.sp_pin_norm(r ->> 's'), 80))
    on conflict (pincode) do update set office = excluded.office, district = excluded.district, state = excluded.state,
      district_u = excluded.district_u, state_u = excluded.state_u;
    ok := ok + 1;
  end loop;
  return jsonb_build_object('ok', ok, 'bad', bad);
end $$;

create or replace function public.sp_pin_master_clear(p_pass text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare n int;
begin
  perform public.sp_check(p_pass);
  delete from public.sp_pin_master; get diagnostics n = row_count;
  return jsonb_build_object('deleted', n);
end $$;

-- niyamon ka saar: product x scope x status  (bade data me bhi chhota rehta hai)
create or replace function public.sp_pin_rules_summary(p_pass text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  perform public.sp_check(p_pass);
  return coalesce((select jsonb_agg(jsonb_build_object('product_id', product_id, 'scope', scope, 'status', status, 'n', n, 'sample', sample) order by product_id, scope, status)
    from (select product_id, scope, status, count(*) as n, (array_agg(value order by value))[1:6] as sample from public.sp_pin_rules group by product_id, scope, status) g), '[]'::jsonb);
end $$;

-- filter: product_id, scope, status, q (value me dhundho), limit (<=1000), offset
create or replace function public.sp_pin_rules_list(p_pass text, p_f jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare lim int := least(greatest(coalesce((p_f ->> 'limit')::int, 200), 1), 1000); off int := greatest(coalesce((p_f ->> 'offset')::int, 0), 0); tot bigint; rows jsonb;
begin
  perform public.sp_check(p_pass);
  select count(*) into tot from public.sp_pin_rules r
   where (coalesce(p_f ->> 'product_id', '') = '' or r.product_id = p_f ->> 'product_id')
     and (coalesce(p_f ->> 'scope', '') = '' or r.scope = p_f ->> 'scope')
     and (coalesce(p_f ->> 'status', '') = '' or r.status = p_f ->> 'status')
     and (coalesce(p_f ->> 'q', '') = '' or r.value ilike '%' || (p_f ->> 'q') || '%');
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'product_id', x.product_id, 'scope', x.scope, 'value', x.value, 'status', x.status) order by x.product_id, x.scope, x.value), '[]'::jsonb) into rows
  from (select * from public.sp_pin_rules r
         where (coalesce(p_f ->> 'product_id', '') = '' or r.product_id = p_f ->> 'product_id')
           and (coalesce(p_f ->> 'scope', '') = '' or r.scope = p_f ->> 'scope')
           and (coalesce(p_f ->> 'status', '') = '' or r.status = p_f ->> 'status')
           and (coalesce(p_f ->> 'q', '') = '' or r.value ilike '%' || (p_f ->> 'q') || '%')
         order by r.product_id, r.scope, r.value limit lim offset off) x;
  return jsonb_build_object('total', tot, 'rows', rows);
end $$;

-- Excel ke liye poora export
create or replace function public.sp_pin_rules_export(p_pass text, p_f jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  perform public.sp_check(p_pass);
  return coalesce((select jsonb_agg(jsonb_build_array(x.product_id, x.scope, x.value, x.status) order by x.product_id, x.scope, x.value)
    from (select * from public.sp_pin_rules r
           where (coalesce(p_f ->> 'product_id', '') = '' or r.product_id = p_f ->> 'product_id')
           order by r.product_id, r.scope, r.value limit 200000) x), '[]'::jsonb);
end $$;

-- rows: [{product_id, scope, value, status, action}]  action = 'delete' ho to wo niyam hat jata hai, warna jud/badal jata hai (dobara upload par clone nahi banta)
-- p_replace_products: in products ke purane sab niyam pehle hata do (sheet hi sach ban jaye)
create or replace function public.sp_pin_rules_apply(p_pass text, p_rows jsonb, p_replace_products jsonb default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r jsonb; i int := 0; added int := 0; upd int := 0; del int := 0; bad int := 0; errs jsonb := '[]'::jsonb;
  pid text; sc text; val text; stt text; act text; n int; pids text[]; existed boolean; rep int := 0;
  have_master boolean := exists (select 1 from public.sp_pin_master);
begin
  perform public.sp_check(p_pass);
  if jsonb_typeof(p_rows) <> 'array' then raise exception 'Invalid rows'; end if;
  if jsonb_array_length(p_rows) > 5000 then raise exception 'Ek baar me 5000 se zyada rows nahi'; end if;
  select coalesce(array_agg(x ->> 'id'), '{}') into pids from jsonb_array_elements(coalesce((select data -> 'products' from public.sp_store where id = 'main'), '[]'::jsonb)) x;
  if p_replace_products is not null and jsonb_typeof(p_replace_products) = 'array' and jsonb_array_length(p_replace_products) > 0 then
    delete from public.sp_pin_rules where product_id in (select jsonb_array_elements_text(p_replace_products));
    get diagnostics rep = row_count;
  end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    i := i + 1;
    pid := btrim(coalesce(r ->> 'product_id', '')); sc := lower(btrim(coalesce(r ->> 'scope', ''))); stt := lower(btrim(coalesce(r ->> 'status', 'out'))); act := lower(btrim(coalesce(r ->> 'action', '')));
    if stt in ('out of stock', 'out_of_stock', 'unavailable', 'no', 'not available') then stt := 'out'; end if;
    if stt in ('in stock', 'in_stock', 'available', 'yes') then stt := 'in'; end if;
    val := public.sp_pin_val(sc, r ->> 'value');
    if pid = '' or (pid <> '*' and not (pid = any (pids))) then bad := bad + 1; if jsonb_array_length(errs) < 40 then errs := errs || to_jsonb('Row ' || i || ': product "' || left(pid, 40) || '" store me nahi mila'); end if; continue; end if;
    if sc not in ('all', 'state', 'district', 'area', 'pin') then bad := bad + 1; if jsonb_array_length(errs) < 40 then errs := errs || to_jsonb('Row ' || i || ': scope galat ("' || left(sc, 20) || '")'); end if; continue; end if;
    if val is null then bad := bad + 1; if jsonb_array_length(errs) < 40 then errs := errs || to_jsonb('Row ' || i || ': value galat ("' || left(coalesce(r ->> 'value', ''), 40) || '")'); end if; continue; end if;
    if act in ('delete', 'del', 'remove', 'hatao') then
      delete from public.sp_pin_rules where product_id = pid and scope = sc and value = val; get diagnostics n = row_count; del := del + n; continue;
    end if;
    if stt not in ('out', 'in') then bad := bad + 1; if jsonb_array_length(errs) < 40 then errs := errs || to_jsonb('Row ' || i || ': status "out" ya "in" hona chahiye'); end if; continue; end if;
    if sc in ('state', 'district') then
      if not have_master then bad := bad + 1; if jsonb_array_length(errs) < 40 then errs := errs || to_jsonb('Row ' || i || ': state/district ke liye pehle Pincode Master upload karein'); end if; continue; end if;
      if sc = 'state' and not exists (select 1 from public.sp_pin_master where state_u = val) then bad := bad + 1; if jsonb_array_length(errs) < 40 then errs := errs || to_jsonb('Row ' || i || ': state "' || left(val, 40) || '" master me nahi mila'); end if; continue; end if;
      if sc = 'district' and not exists (select 1 from public.sp_pin_master where state_u || '|' || district_u = val) then bad := bad + 1; if jsonb_array_length(errs) < 40 then errs := errs || to_jsonb('Row ' || i || ': district "' || left(val, 50) || '" master me nahi mila (format: STATE | DISTRICT)'); end if; continue; end if;
    end if;
    if sc = 'area' and not exists (select 1 from public.sp_pin_areas where name = val) then bad := bad + 1; if jsonb_array_length(errs) < 40 then errs := errs || to_jsonb('Row ' || i || ': area "' || left(val, 40) || '" nahi bana hai'); end if; continue; end if;
    select exists (select 1 from public.sp_pin_rules where product_id = pid and scope = sc and value = val) into existed;
    insert into public.sp_pin_rules(product_id, scope, value, status) values (pid, sc, val, stt)
    on conflict (product_id, scope, value) do update set status = excluded.status, updated_at = now();
    if existed then upd := upd + 1; else added := added + 1; end if;
  end loop;
  perform public.sp_pin_modes_gc();
  return jsonb_build_object('added', added, 'updated', upd, 'deleted', del, 'replaced', rep, 'bad', bad, 'errors', errs);
end $$;

-- filter: {all:true} | {ids:[..]} | {product_id, scope, status, value}
create or replace function public.sp_pin_rules_delete(p_pass text, p_f jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare n int;
begin
  perform public.sp_check(p_pass);
  if p_f is null or jsonb_typeof(p_f) <> 'object' then raise exception 'Invalid filter'; end if;
  if coalesce((p_f ->> 'all')::boolean, false) then
    delete from public.sp_pin_rules; get diagnostics n = row_count;
  elsif jsonb_typeof(p_f -> 'ids') = 'array' then
    delete from public.sp_pin_rules where id in (select (jsonb_array_elements_text(p_f -> 'ids'))::bigint); get diagnostics n = row_count;
  elsif coalesce(p_f ->> 'product_id', '') <> '' or coalesce(p_f ->> 'scope', '') <> '' or coalesce(p_f ->> 'status', '') <> '' then
    delete from public.sp_pin_rules r
     where (coalesce(p_f ->> 'product_id', '') = '' or r.product_id = p_f ->> 'product_id')
       and (coalesce(p_f ->> 'scope', '') = '' or r.scope = p_f ->> 'scope')
       and (coalesce(p_f ->> 'status', '') = '' or r.status = p_f ->> 'status');
    get diagnostics n = row_count;
  else
    raise exception 'Kya delete karna hai ye batayein';
  end if;
  perform public.sp_pin_modes_gc();
  return jsonb_build_object('deleted', n);
end $$;

-- areas -------------------------------------------------------------------------------------
create or replace function public.sp_pin_area_list(p_pass text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  perform public.sp_check(p_pass);
  return coalesce((select jsonb_agg(jsonb_build_object('name', name, 'label', label, 'n', coalesce(array_length(pins, 1), 0),
      'rules', (select count(*) from public.sp_pin_rules r where r.scope = 'area' and r.value = a.name)) order by label) from public.sp_pin_areas a), '[]'::jsonb);
end $$;