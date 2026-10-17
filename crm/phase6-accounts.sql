-- ============================================================================
-- ROUND 9 (database) — Accounts (Kharcha + P&L + GST + ITR summary) and Backup RESTORE.
-- Run AFTER crm-setup.sql, phase1, phase2-3, phase4, phase5. Safe to re-run.
-- Note: this is a report for your CA — it is not GST / ITR filing.
-- ============================================================================

-- (1) expenses ledger ----------------------------------------------------------------
create table if not exists public.crm_expenses (
  id         bigserial primary key,
  spent_on   date not null,
  category   text not null default 'Other',
  vendor     text not null default '',
  amount     numeric(14,2) not null check (amount > 0),
  gst_amount numeric(14,2) not null default 0 check (gst_amount >= 0),
  mode       text not null default 'cash',
  note       text not null default '',
  created_by bigint,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  deleted_by bigint,
  delete_reason text
);
create index if not exists crm_expenses_on on public.crm_expenses(spent_on);
alter table public.crm_expenses enable row level security;
revoke all on public.crm_expenses from anon, authenticated;

create or replace function public.crm_exp_list(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); fr date := coalesce(nullif(p ->> 'from', '')::date, date '2000-01-01'); t date := coalesce(nullif(p ->> 'to', '')::date, date '2999-12-31');
begin
  perform public.crm_need(s, 'accounts.manage');
  return coalesce((select jsonb_agg(to_jsonb(e) - 'deleted_at' - 'deleted_by' - 'delete_reason' order by e.spent_on desc, e.id desc)
    from public.crm_expenses e where e.deleted_at is null and e.spent_on between fr and t), '[]'::jsonb);
end $$;

create or replace function public.crm_exp_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); id_ bigint := nullif(p ->> 'id', '')::bigint; d date; a numeric; g numeric; r public.crm_expenses;
  cat text := left(trim(coalesce(nullif(p ->> 'category', ''), 'Other')), 40);
begin
  perform public.crm_need(s, 'accounts.manage');
  begin d := (p ->> 'spent_on')::date; exception when others then raise exception 'Sahi tareekh likhein'; end;
  if d is null or d > public.crm_today() + 1 or d < date '2015-01-01' then raise exception 'Tareekh galat hai'; end if;
  a := public.crm_num(p -> 'amount'); g := public.crm_num(p -> 'gst_amount');
  if a <= 0 then raise exception 'Amount likhein'; end if;
  if g < 0 or g > a then raise exception 'GST amount kul amount se zyada nahi ho sakta'; end if;
  if id_ is null then
    insert into public.crm_expenses(spent_on, category, vendor, amount, gst_amount, mode, note, created_by)
    values (d, cat, left(trim(coalesce(p ->> 'vendor', '')), 120), round(a, 2), round(g, 2), left(coalesce(nullif(p ->> 'mode', ''), 'cash'), 20), left(trim(coalesce(p ->> 'note', '')), 300), (s).uid) returning * into r;
    perform public.crm_log(s, 'create', 'expense', r.id, 'Kharcha ' || r.category || ' ' || r.amount);
  else
    update public.crm_expenses set spent_on = d, category = cat, vendor = left(trim(coalesce(p ->> 'vendor', '')), 120), amount = round(a, 2), gst_amount = round(g, 2),
      mode = left(coalesce(nullif(p ->> 'mode', ''), 'cash'), 20), note = left(trim(coalesce(p ->> 'note', '')), 300) where id = id_ and deleted_at is null returning * into r;
    if r.id is null then raise exception 'Kharcha nahi mila'; end if;
    perform public.crm_log(s, 'edit', 'expense', r.id, 'Kharcha badla ' || r.category || ' ' || r.amount);
  end if;
  return to_jsonb(r) - 'deleted_at' - 'deleted_by' - 'delete_reason';
end $$;

create or replace function public.crm_exp_del(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); why text := trim(coalesce(p ->> 'why', '')); r public.crm_expenses;
begin
  perform public.crm_need(s, 'accounts.manage');
  if length(why) < 3 then raise exception 'Hatane ki wajah likhein'; end if;
  update public.crm_expenses set deleted_at = now(), deleted_by = (s).uid, delete_reason = why where id = (p ->> 'id')::bigint and deleted_at is null returning * into r;
  if r.id is null then raise exception 'Kharcha nahi mila'; end if;
  perform public.crm_log(s, 'delete', 'expense', r.id, 'Kharcha hataya (' || why || ') ' || r.category || ' ' || r.amount);
  return jsonb_build_object('ok', true);
end $$;

-- (2) accounts report: P&L + GST (output / input / net) + ITR summary + month-wise ----------
create or replace function public.crm_acct_report(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); fr date := (p ->> 'from')::date; t date := (p ->> 'to')::date;
  sales numeric; sdisc numeric; sgst numeric; scnt int; b2b numeric; b2c numeric; coll numeric; pur numeric; pgst numeric; pcnt int;
  ex numeric; exg numeric; rev numeric; gross numeric; net numeric; due numeric; payable numeric; cats jsonb; mon jsonb; rates jsonb;
begin
  perform public.crm_need(s, 'accounts.manage');
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
create or replace function public.crm_lines_guard() returns trigger language plpgsql as $$
declare l jsonb;
begin
  if coalesce(current_setting('sp.restoring', true), '') = 'on' then return new; end if;
  if new.kind in ('quote', 'invoice', 'purchase') and new.deleted_at is null and jsonb_typeof(new.data -> 'lines') = 'array' then
    for l in select * from jsonb_array_elements(new.data -> 'lines') loop
      if coalesce(l ->> 'kind', 'product') <> 'project' and coalesce(l ->> 'item_id', '') = '' then
        raise exception 'Har item Inventory se hi chunna hoga — "%" Inventory me nahi hai. Pehle Inventory me jodein.', coalesce(nullif(l ->> 'name', ''), '?');
      end if;
      if coalesce(l ->> 'item_id', '') <> '' and not exists (select 1 from public.crm_records i where i.id = (l ->> 'item_id')::bigint and i.kind = 'item') then
        raise exception '"%" Inventory me nahi mila (delete ho gaya?). Item dobara chunein.', coalesce(nullif(l ->> 'name', ''), '?');
      end if;
    end loop;
  end if;
  return new;
end $$;

create or replace function public.crm_lead_alert_trg() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('sp.restoring', true), '') = 'on' then return new; end if;
  begin
    perform public.crm_alert('Naya lead: ' || coalesce(new.title, '') || ' · ' || coalesce(new.mobile, '') || ' · ' || coalesce(new.data ->> 'source', ''),
      jsonb_build_object('event', 'lead.created', 'id', new.id, 'name', new.title, 'mobile', new.mobile, 'source', new.data ->> 'source'));
  exception when others then null;
  end;
  return new;
end $$;

create or replace function public.crm_restore(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pe text; part text := coalesce(p ->> 'part', ''); rows jsonb := coalesce(p -> 'rows', '[]'::jsonb);
  allowed text[] := array['crm_records', 'crm_counters', 'crm_expenses', 'sp_orders', 'sp_enquiries', 'sp_store', 'crm_files'];
  cols text; setl text; n int := 0; pk text;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  pe := public.crm_auth_pin_check(public.crm_auth_find('crm', 'admin'), p ->> 'pin');
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
  if part in ('crm_records', 'crm_expenses', 'sp_orders', 'sp_enquiries', 'crm_files') and pg_get_serial_sequence('public.' || part, 'id') is not null then
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
 {"g":"Marketing","k":"marketing.leads","l":"Lead kahan se aayi (source report) dekhe"}
]'::jsonb $$;

-- backup now includes the expenses ledger
create or replace function public.crm_backup(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pe text; part text := coalesce(p ->> 'part', 'meta');
  off int := greatest(coalesce((p ->> 'offset')::int, 0), 0); lim int; r jsonb; cnt jsonb := '{}'::jsonb; t text;
  parts text[] := array['crm_settings', 'crm_auth_admin', 'crm_roles', 'crm_users', 'crm_records', 'crm_counters', 'crm_activity', 'sp_store', 'sp_orders', 'sp_enquiries', 'crm_files', 'crm_expenses'];
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

do $$ declare f text; begin
  foreach f in array array['public.crm_exp_list(jsonb)', 'public.crm_exp_save(jsonb)', 'public.crm_exp_del(jsonb)', 'public.crm_acct_report(jsonb)', 'public.crm_restore(jsonb)', 'public.crm_backup(jsonb)'] loop
    execute 'revoke all on function ' || f || ' from public';
    execute 'grant execute on function ' || f || ' to anon, authenticated';
  end loop;
end $$;
