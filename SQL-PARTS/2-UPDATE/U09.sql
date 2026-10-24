-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 9 of 12
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U12). Safe to re-run.
-- ============================================================================

create or replace function public.sp_cust_login(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare m text := public.crm_mobile(p ->> 'mobile'); pin text := coalesce(p ->> 'pin', ''); u public.crm_users; lk timestamptz;
begin
  if m !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein'; end if;
  select * into u from public.crm_users where role = 'consumer' and mobile = m order by id limit 1;
  if u.id is null then perform pg_sleep(0.6); return jsonb_build_object('error', 'Mobile ya PIN galat hai'); end if;
  if u.status = 'blocked' then raise exception 'Ye ID band hai — Admin se sampark karein'; end if;
  if coalesce(u.pin_hash, '') = '' then return jsonb_build_object('error', 'Is ID me PIN nahi hai — "Create ID with PIN" dabayein ya Email OTP se login karein'); end if;
  lk := nullif(u.meta ->> 'lock_until', '')::timestamptz;
  if lk is not null and lk > now() then return jsonb_build_object('error', 'PIN lock hai — ' || greatest(1, ceil(extract(epoch from lk - now()) / 60))::int || ' minute baad koshish karein'); end if;
  if crypt(pin, u.pin_hash) <> u.pin_hash then
    if u.pin_fail + 1 >= 5 then update public.crm_users set pin_fail = 0, meta = coalesce(meta, '{}'::jsonb) || jsonb_build_object('lock_until', (now() + interval '15 minutes')) where id = u.id;
      perform pg_sleep(0.6); return jsonb_build_object('error', 'Bahut baar galat PIN — 15 minute baad koshish karein');
    end if;
    update public.crm_users set pin_fail = pin_fail + 1 where id = u.id;
    perform pg_sleep(0.6); return jsonb_build_object('error', 'Mobile ya PIN galat hai');
  end if;
  update public.crm_users set meta = coalesce(meta, '{}'::jsonb) - 'lock_until' where id = u.id and meta ? 'lock_until';
  return public.crm_auth_session(jsonb_build_object('uid', u.id, 'name', u.name, 'role', 'consumer', 'status', 'active', 'has_q', true, 'dev_name', p ->> 'dev_name'), p ->> 'device', 'store');
end $$;

create or replace function public.sp_cust_avatar(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); av text := coalesce(p ->> 'avatar', '');
begin
  if av <> '' and (av !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' or length(av) > 9000) then raise exception 'Photo bahut badi hai — chhoti photo chunein'; end if;
  update public.crm_users set meta = case when av = '' then coalesce(meta, '{}'::jsonb) - 'avatar' else coalesce(meta, '{}'::jsonb) || jsonb_build_object('avatar', av) end where id = u.id;
  return jsonb_build_object('ok', true);
end $$;

-- account page: an ID without a verified mobile sees only its own orders / enquiries
create or replace function public.crm_consumer_me(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); ok boolean := coalesce((u.meta ->> 'mob_ok')::boolean, true);
begin
  return jsonb_build_object('id', u.id, 'name', u.name, 'mobile', u.mobile, 'email', u.email, 'username', u.username, 'meta', coalesce(u.meta, '{}'::jsonb) - 'lock_until', 'created_at', u.created_at,
    'orders', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'order_no', o.data ->> 'order_no', 'created_at', o.created_at, 'status', o.status, 'total', o.data -> 'total', 'advance', o.data -> 'advance', 'payment', o.data ->> 'payment',
        'items', (select coalesce(jsonb_agg(jsonb_build_object('title', i ->> 'title', 'qty', i -> 'qty', 'amount', i -> 'amount')), '[]'::jsonb) from jsonb_array_elements(coalesce(o.data -> 'items', '[]'::jsonb)) i)) order by o.id desc)
      from (select * from public.sp_orders where (ok and (data ->> 'phone') = u.mobile) or (data ->> 'customer_id') = u.id::text order by id desc limit 100) o), '[]'::jsonb),
    'enquiries', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'created_at', e.created_at, 'status', e.status, 'type', e.data ->> 'type', 'subject', e.data ->> 'subject', 'message', e.data ->> 'message') order by e.id desc)
      from (select * from public.sp_enquiries where (ok and (data ->> 'phone') = u.mobile) or (data ->> 'customer_id') = u.id::text order by id desc limit 50) e), '[]'::jsonb));
end $$;

do $$ begin
  grant execute on function public.sp_cust_signup(jsonb) to anon, authenticated;
  grant execute on function public.sp_cust_login(jsonb) to anon, authenticated;
  grant execute on function public.sp_cust_avatar(jsonb) to anon, authenticated;
exception when undefined_object then null; end $$;

notify pgrst, 'reload schema';

-- ================================================================= Round 23: fast "has anything changed?" check (tiny reply) so open apps / pages refresh themselves
-- Every change of the store / website data stamps updated_at (also when the data is changed by another SQL function), and sp_store_ver() returns those stamps.
create or replace function public.sp_touch_store() returns trigger language plpgsql as $$
begin new.updated_at := clock_timestamp(); return new; end $$;
drop trigger if exists sp_store_touch on public.sp_store;
create trigger sp_store_touch before insert or update of data on public.sp_store for each row execute function public.sp_touch_store();

create or replace function public.sp_store_ver() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(id, (extract(epoch from updated_at) * 1000000)::bigint), '{}'::jsonb) from public.sp_store where id in ('main', 'web') $$;
do $$ begin grant execute on function public.sp_store_ver() to anon, authenticated; exception when undefined_object then null; end $$;
notify pgrst, 'reload schema';

-- ============================================================================
-- ROUND 24 — Last-unit hold: Store App + Website Shop share ONE stock. First order holds the quantity.
--   * only products that are linked to a CRM item (CRM item.data.store.store_id = store product id) AND whose CRM stock is tracked are checked
--   * free = CRM stock - quotation reserves - offline holds - quantity of OPEN online orders (status new/paid; unpaid-online orders release after 48 h,
--     COD and submitted/verified payments keep the hold; rejected payment / cancelled / shipped / delivered release it — shipped means the bill has reduced stock)
--   * projects sold online check every sub-item (qty x project qty)
--   * rows of the CRM item are locked while checking, so two simultaneous orders cannot both take the last unit
-- ============================================================================
create or replace function public.sp_order_need(p_items jsonb) returns table(item_id bigint, qty numeric)
language sql stable security definer set search_path = public as $$
  select m.iid, sum(m.q) from (
    select ci.id as iid, greatest(public.crm_num(i -> 'qty'), 1) as q
      from jsonb_array_elements(case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end) i
      cross join lateral (select c.id from public.crm_records c where c.kind = 'item' and c.deleted_at is null and coalesce(c.data ->> 'type', 'product') <> 'project'
                            and (c.data #>> '{store,store_id}') = (i ->> 'id') order by c.id limit 1) ci
    union all
    select (x ->> 'item_id')::bigint, public.crm_num(x -> 'qty') * greatest(public.crm_num(i -> 'qty'), 1)
      from jsonb_array_elements(case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end) i
      cross join lateral (select c.data from public.crm_records c where c.kind = 'item' and c.deleted_at is null and c.data ->> 'type' = 'project'
                            and (c.data #>> '{store,store_id}') = (i ->> 'id') order by c.id limit 1) pr
      cross join lateral jsonb_array_elements(case when jsonb_typeof(pr.data -> 'proj_items') = 'array' then pr.data -> 'proj_items' else '[]'::jsonb end) x
      where coalesce(x ->> 'item_id', '') ~ '^[0-9]+$'
  ) m group by m.iid $$;

create or replace function public.sp_online_held(p_item bigint, p_exclude bigint default null) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(n.qty), 0) from public.sp_orders o
    cross join lateral public.sp_order_need(o.data -> 'items') n
   where n.item_id = p_item and o.status in ('new', 'paid') and o.id <> coalesce(p_exclude, 0)
     and coalesce(o.data ->> 'payment_status', '') <> 'rejected'
     and (coalesce(o.data ->> 'payment_status', '') <> 'awaiting_payment' or coalesce(o.data ->> 'payment', '') = 'cod' or o.created_at > now() - interval '48 hours') $$;

create or replace function public.sp_stock_guard(p_items jsonb) returns void language plpgsql security definer set search_path = public as $$
declare r record; it public.crm_records; res numeric; fr numeric; msg text := '';
begin
  for r in select * from public.sp_order_need(p_items) order by item_id loop
    select * into it from public.crm_records where id = r.item_id and kind = 'item' and deleted_at is null for update;
    if it.id is null or not (it.data ? 'stock') or coalesce(it.data ->> 'stock', '') = '' then continue; end if;
    select coalesce(sum(z.qty), 0) into res from public.crm_reserves(null) z where z.item_id = it.id;
    fr := public.crm_num(it.data -> 'stock') - res - public.crm_holds_sum(it.data, false) - public.sp_online_held(it.id, null);
    if r.qty > fr + 0.0001 then
      msg := msg || coalesce(nullif(it.data ->> 'titleEn', ''), nullif(it.data ->> 'title', ''), nullif(it.data ->> 'name', ''), it.title, 'item') || ' (' || case when fr >= 1 then 'sirf ' || floor(fr) || ' bacha' else 'abhi stock mein nahi' end || '); ';
    end if;
  end loop;
  if msg <> '' then raise exception 'OUT_OF_STOCK: %', left(msg, 300); end if;
end $$;
revoke all on function public.sp_order_need(jsonb), public.sp_online_held(bigint, bigint), public.sp_stock_guard(jsonb) from public, anon, authenticated;

create or replace function public.sp_place_order(p_order jsonb)
returns bigint language plpgsql security definer
set search_path = public as $$
declare new_id bigint; u public.crm_users; o jsonb;
begin
  if p_order is null or jsonb_typeof(p_order) <> 'object' then raise exception 'Invalid order'; end if;
  if length(p_order::text) > 30000 then raise exception 'Order too large'; end if;

  -- login is mandatory
  u := public.crm_csession(p_order ->> 'token');   -- raises if not logged in / expired

  if jsonb_typeof(p_order->'items') <> 'array' or jsonb_array_length(p_order->'items') = 0 then
    raise exception 'Cart is empty';
  end if;

  -- pincode-wise availability (server-side, cannot be bypassed from the browser)
  perform public.sp_pin_guard(p_order ->> 'pincode', p_order -> 'items');

  -- Round 24: same stock for Store App + Website Shop — last unit is held for the first order (server-side, cannot be bypassed)
  perform public.sp_stock_guard(p_order -> 'items');

  -- identity always comes from the account, never from the browser
  o := (p_order - 'token' - 'customer_id')
       || jsonb_build_object(
            'name', left(coalesce(nullif(trim(u.name), ''), trim(p_order->>'name')), 80),
            'phone', coalesce(u.mobile, ''),
            'customer_id', u.id::text,
            'login_method', 'email_otp',
            'payment_status', 'awaiting_payment');

  if coalesce(trim(o->>'name'), '') = '' or coalesce(trim(o->>'phone'), '') = '' then
    raise exception 'Naam aur mobile account mein save karein';
  end if;

  o := o || jsonb_build_object('order_no', public.crm_next_no('order'));
  insert into public.sp_orders(data) values (o) returning id into new_id;
  perform public.sp_notify_admin('Naya order ' || (o->>'order_no') || ' — ' || (o->>'name'),
    '<p>Naya order aaya hai: <b>' || (o->>'order_no') || '</b></p><p>' || (o->>'name') || ' · ' || (o->>'phone') || '</p><p>Total: ₹' || (o->>'total') || ' — payment ka UTR aane par dobara notification milega. Admin panel mein dekhein.</p>');
  return new_id;
end $$;
revoke all on function public.sp_place_order(jsonb) from public;
grant execute on function public.sp_place_order(jsonb) to anon, authenticated;
notify pgrst, 'reload schema';

-- ============================================================================
-- ROUND 25 — Overwrite guard for Store/Shop admin saves.
--   Admin sends the version (sp_store_ver main) it loaded; if the database row changed in between (another window / phone / person saved),
--   the save is refused with STORE_CHANGED and the admin asks what to do. p_expect = null → save without the check ("phir bhi save").
--   The old 2-argument sp_save_store stays, so an old admin screen keeps working.
-- ============================================================================
create or replace function public.sp_save_store2(p_pass text, p_data jsonb, p_expect bigint default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare cur bigint; nv bigint; t timestamptz := now();
begin
  perform public.sp_check(p_pass);
  if p_data is null or jsonb_typeof(p_data) <> 'object' then raise exception 'Invalid data'; end if;
  select (extract(epoch from updated_at) * 1000000)::bigint into cur from public.sp_store where id = 'main' for update;
  if p_expect is not null and cur is not null and cur <> p_expect then
    raise exception 'STORE_CHANGED: kisi aur ne abhi Store/Shop me badlav save kiya hai';
  end if;
  insert into public.sp_store(id, data, updated_at) values ('main', p_data, t)
  on conflict (id) do update set data = excluded.data, updated_at = excluded.updated_at;
  select (extract(epoch from updated_at) * 1000000)::bigint into nv from public.sp_store where id = 'main';
  return jsonb_build_object('t', t, 'ver', nv);
end $$;
revoke all on function public.sp_save_store2(text, jsonb, bigint) from public;
grant execute on function public.sp_save_store2(text, jsonb, bigint) to anon, authenticated;
notify pgrst, 'reload schema';

-- =================================================================
-- ROUND 26: CRM sirf Admin panel ke darwaze se (admin ke liye CRM me seedha login band)
-- Admin panel (apne login ke baad) 60 second ka ek-baar chalne wala ticket banata hai; CRM use server par verify karke hi Admin session deta hai.
-- CRM staff (Manager / Staff / Dealer / Influencer) pehle jaise apni ID + PIN se login karte hain.
-- =================================================================
create or replace function public.crm_auth_find(p_app text, p_id text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare x text := lower(trim(coalesce(p_id, ''))); m text := public.crm_mobile(p_id); u public.crm_users; a public.crm_auth_admin;
begin
  if p_app not in ('crm', 'store', 'admin') then raise exception 'Galat app'; end if;
  if x = '' then raise exception 'Mobile / Email / Username likhein'; end if;
  if p_app = 'crm' and x = 'admin' then raise exception 'Ye ID nahi mili — mobile / email check karein'; end if;
  if p_app = 'admin' then
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

create or replace function public.sp_admin_crm_ticket(p_pass text) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare tk text := encode(gen_random_bytes(24), 'hex');
begin
  perform public.sp_check(p_pass);
  delete from public.crm_otps where purpose = 'handoff' and (used or coalesce(ticket_expires, now()) <= now());
  insert into public.crm_otps(user_id, purpose, code_hash, expires_at, used, ticket_hash, ticket_expires)
  values (0, 'handoff', '', now() + interval '60 seconds', false, public.crm_h(tk), now() + interval '60 seconds');
  return jsonb_build_object('ticket', tk);
end $$;

create or replace function public.crm_auth_handoff(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare o public.crm_otps; f jsonb;
begin
  select * into o from public.crm_otps where purpose = 'handoff' and used = false and ticket_hash = public.crm_h(coalesce(p ->> 'ticket', '')) and ticket_expires > now() for update;
  if o.id is null then raise exception 'Link expire ho gaya — Admin panel se CRM dobara kholein'; end if;
  update public.crm_otps set used = true, ticket_expires = now() where id = o.id;
  f := public.crm_auth_find('admin', 'admin') || jsonb_build_object('dev_name', 'Admin panel');
  return public.crm_auth_session(f, coalesce(p ->> 'device', ''), 'crm');
end $$;
revoke all on function public.sp_admin_crm_ticket(text), public.crm_auth_handoff(jsonb) from public;
grant execute on function public.sp_admin_crm_ticket(text), public.crm_auth_handoff(jsonb) to anon, authenticated;
notify pgrst, 'reload schema';

-- ===== Round 27: Admin panel -> CRM entry shows Admin + all CRM users (read-only list; no hashes ever leave the database) =====
create or replace function public.sp_admin_crm_users(p_pass text) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.sp_check(p_pass);
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'role', role, 'name', name, 'username', username, 'mobile', mobile, 'email', email, 'status', status,
           'pin_set', (pin_hash <> ''), 'last_seen', last_seen) order by (role = 'admin') desc, role, name)
           from public.crm_users where role <> 'consumer'), '[]'::jsonb);
end $$;
revoke all on function public.sp_admin_crm_users(text) from public;
grant execute on function public.sp_admin_crm_users(text) to anon, authenticated;
notify pgrst, 'reload schema';

-- ============================================================================
-- ROUND 29 — Designer paid model (Rs 49, GST invoice), shop-order GST invoice ("genuine" button), CRM PDF link token
-- ============================================================================
-- (1) CRM staff: short-lived upload token so a PDF can be put in the public bucket and sent as a link -----------------
create table if not exists public.sp_upload_tokens (token text primary key, exp timestamptz not null);
alter table public.sp_upload_tokens enable row level security;
revoke all on public.sp_upload_tokens from anon, authenticated;

create or replace function public.crm_upload_token(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); t text := encode(gen_random_bytes(12), 'hex');
begin
  delete from public.sp_upload_tokens where exp < now();
  insert into public.sp_upload_tokens(token, exp) values (t, now() + interval '2 hours');
  return jsonb_build_object('token', t);
end $$;
revoke all on function public.crm_upload_token(jsonb) from public;
grant execute on function public.crm_upload_token(jsonb) to anon, authenticated;

-- (2) Designer payments (public users) ---------------------------------------------------------------------------------
create table if not exists public.sp_design_pay (
  id            bigserial primary key,
  created_at    timestamptz not null default now(),
  customer_id   text not null,
  name          text, mobile text, email text,
  order_no      text,
  amount        numeric not null,          -- total the customer pays (GST included)
  gst_pct       numeric not null default 5,
  taxable       numeric not null,
  gst_amt       numeric not null,
  status        text not null default 'awaiting_payment',   -- awaiting_payment | submitted | verified | rejected
  utr           text, utr_at timestamptz,
  location      jsonb not null default '{}'::jsonb,
  summary       jsonb not null default '{}'::jsonb,
  invoice_no    text, invoice_at timestamptz, verified_at timestamptz,
  design_fp     text, downloads int not null default 0, first_download_at timestamptz
);
alter table public.sp_design_pay enable row level security;
revoke all on public.sp_design_pay from anon, authenticated;

create or replace function public.sp_design_fee() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'amount', coalesce(nullif(data #>> '{settings,designFee}', '')::numeric, 49),
    'gst_pct', coalesce(nullif(data #>> '{settings,designGst}', '')::numeric, 5))
  from (select coalesce((select data from public.sp_store where id = 'main'), '{}'::jsonb) as data) x;
$$;
revoke all on function public.sp_design_fee() from public;

create or replace function public.sp_design_json(r public.sp_design_pay) returns jsonb
language sql immutable as $$
  select jsonb_build_object('id', r.id, 'order_no', r.order_no, 'amount', r.amount, 'gst_pct', r.gst_pct, 'taxable', r.taxable, 'gst_amt', r.gst_amt,
    'status', r.status, 'utr', r.utr, 'created_at', r.created_at, 'invoice_no', r.invoice_no, 'invoice_at', r.invoice_at, 'downloads', r.downloads,
    'used', r.first_download_at is not null, 'location', r.location, 'name', r.name, 'mobile', r.mobile);
$$;

-- customer starts (or resumes) the one payment for one design
create or replace function public.sp_design_start(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); r public.sp_design_pay; fee jsonb := public.sp_design_fee(); a numeric; g numeric; tx numeric;
begin
  -- resume the customer's open payment (not yet used for a download)
  select * into r from public.sp_design_pay
   where customer_id = u.id::text and status in ('awaiting_payment', 'submitted', 'verified') and first_download_at is null
   order by id desc limit 1;
  if r.id is not null then
    if p ? 'location' and jsonb_typeof(p -> 'location') = 'object' then update public.sp_design_pay set location = p -> 'location' where id = r.id returning * into r; end if;
    return public.sp_design_json(r);
  end if;
  a := (fee ->> 'amount')::numeric; g := (fee ->> 'gst_pct')::numeric; tx := round(a / (1 + g / 100), 2);
  insert into public.sp_design_pay(customer_id, name, mobile, email, amount, gst_pct, taxable, gst_amt, location, summary)
  values (u.id::text, u.name, u.mobile, u.email, a, g, tx, round(a - tx, 2),
          case when jsonb_typeof(p -> 'location') = 'object' then p -> 'location' else '{}'::jsonb end,
          case when jsonb_typeof(p -> 'summary') = 'object' then p -> 'summary' else '{}'::jsonb end)
  returning * into r;
  update public.sp_design_pay set order_no = 'DSN-' || to_char(now() at time zone 'Asia/Kolkata', 'YYMM') || '-' || lpad(r.id::text, 4, '0') where id = r.id returning * into r;
  return public.sp_design_json(r);
end $$;

-- "I have paid" (UTR / slip are optional)
create or replace function public.sp_design_submit(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); r public.sp_design_pay; utr_ text := upper(regexp_replace(coalesce(p ->> 'utr', ''), '\s', '', 'g'));
begin
  select * into r from public.sp_design_pay where id = nullif(p ->> 'id', '')::bigint and customer_id = u.id::text;
  if r.id is null then raise exception 'Ye payment aapke account me nahi hai'; end if;
  if utr_ <> '' and utr_ !~ '^[A-Z0-9]{6,30}$' then raise exception 'UTR / transaction ID sahi nahi hai (6 se 30 akshar/ank)'; end if;
  if r.status = 'awaiting_payment' or r.status = 'rejected' then
    update public.sp_design_pay set status = 'submitted', utr = nullif(utr_, ''), utr_at = now(),
           location = case when jsonb_typeof(p -> 'location') = 'object' then p -> 'location' else location end,
           summary = case when jsonb_typeof(p -> 'summary') = 'object' then p -> 'summary' else summary end
     where id = r.id returning * into r;
    perform public.sp_notify_admin('Designer payment ' || r.order_no || ' — ' || coalesce(r.name, ''),
      '<p>Solar Designer ka payment <b>Rs ' || r.amount || '</b> (' || r.order_no || ') — ' || coalesce(r.name, '') || ' · ' || coalesce(r.mobile, '') || '</p><p>Location: ' || coalesce(r.location ->> 'addr', '') || ' (' || coalesce(r.location ->> 'lat', '') || ', ' || coalesce(r.location ->> 'lng', '') || ')</p><p>UTR: ' || coalesce(r.utr, '—') || '</p><p>Admin panel me <b>Payment &amp; Location genuine — Invoice bhejein</b> dabayein.</p>');
  end if;
  return public.sp_design_json(r);
end $$;

create or replace function public.sp_design_status(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); r public.sp_design_pay;
begin
  select * into r from public.sp_design_pay where id = nullif(p ->> 'id', '')::bigint and customer_id = u.id::text;
  if r.id is null then return jsonb_build_object('status', 'none'); end if;
  return public.sp_design_json(r);
end $$;

-- a verified payment unlocks ONE design (identified by its map location); a different location needs a new payment
create or replace function public.sp_design_consume(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); r public.sp_design_pay; fp text := left(coalesce(p ->> 'fp', ''), 60);
begin
  select * into r from public.sp_design_pay where id = nullif(p ->> 'id', '')::bigint and customer_id = u.id::text for update;
  if r.id is null or r.status <> 'verified' then raise exception 'PAYMENT_NOT_VERIFIED: payment verify hone par download khulega'; end if;
  if r.design_fp is not null and fp <> '' and r.design_fp <> fp then raise exception 'NEW_DESIGN_NEEDS_PAYMENT: ek payment me ek hi design — naye design ke liye dobara payment karein'; end if;
  if r.downloads >= 30 then raise exception 'NEW_DESIGN_NEEDS_PAYMENT: is payment ki download limit poori ho gayi'; end if;
  update public.sp_design_pay set downloads = downloads + 1, first_download_at = coalesce(first_download_at, now()), design_fp = coalesce(design_fp, nullif(fp, ''))
   where id = r.id returning * into r;
  return public.sp_design_json(r);
end $$;
do $$ begin
  grant execute on function public.sp_design_start(jsonb), public.sp_design_submit(jsonb), public.sp_design_status(jsonb), public.sp_design_consume(jsonb) to anon, authenticated;
exception when undefined_object then null; end $$;

-- admin: list + "genuine" (verifies payment and location, makes the GST invoice)
create or replace function public.sp_admin_design_list(p_pass text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.sp_check(p_pass);
  return coalesce((select jsonb_agg(public.sp_design_json(d) order by d.id desc) from (select * from public.sp_design_pay order by id desc limit 300) d), '[]'::jsonb);
end $$;

create or replace function public.sp_admin_design_genuine(p_pass text, p_id bigint, p_ok boolean default true) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r public.sp_design_pay; n int; fy text;
begin
  perform public.sp_check(p_pass);
  select * into r from public.sp_design_pay where id = p_id for update;
  if r.id is null then raise exception 'Payment nahi mila'; end if;
  if not coalesce(p_ok, true) then
    update public.sp_design_pay set status = 'rejected' where id = r.id returning * into r; return public.sp_design_json(r);
  end if;
  if r.invoice_no is null then
    select count(*) + 1 into n from public.sp_design_pay where invoice_no is not null;
    fy := case when extract(month from now() at time zone 'Asia/Kolkata') >= 4 then to_char(now() at time zone 'Asia/Kolkata', 'YY') || to_char((now() at time zone 'Asia/Kolkata') + interval '1 year', 'YY')
               else to_char((now() at time zone 'Asia/Kolkata') - interval '1 year', 'YY') || to_char(now() at time zone 'Asia/Kolkata', 'YY') end;
    update public.sp_design_pay set invoice_no = 'SPD/' || fy || '/' || lpad(n::text, 4, '0'), invoice_at = now() where id = r.id;
  end if;
  update public.sp_design_pay set status = 'verified', verified_at = coalesce(verified_at, now()) where id = r.id returning * into r;
  return public.sp_design_json(r);
end $$;
revoke all on function public.sp_admin_design_list(text), public.sp_admin_design_genuine(text, bigint, boolean) from public;
grant execute on function public.sp_admin_design_list(text), public.sp_admin_design_genuine(text, bigint, boolean) to anon, authenticated;

-- (3) Shop orders: admin sends the GST invoice after "Payment & Location genuine" --------------------------------------
create or replace function public.sp_admin_send_invoice(p_pass text, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare o public.sp_orders; st jsonb; sett jsonb; prods jsonb; it jsonb; lines jsonb := '[]'::jsonb; g numeric; amt numeric; tx numeric;
        t_tax numeric := 0; t_gst numeric := 0; ship numeric; n int; fy text; no_ text; inv jsonb; pid text; pr jsonb;
begin
  perform public.sp_check(p_pass);
  select * into o from public.sp_orders where id = p_id for update;
  if o.id is null then raise exception 'Order nahi mila'; end if;
  if o.data ->> 'invoice_no' is not null then return o.data -> 'invoice'; end if;
  select data into st from public.sp_store where id = 'main';
  sett := coalesce(st -> 'settings', '{}'::jsonb); prods := coalesce(st -> 'products', '[]'::jsonb);
  for it in select * from jsonb_array_elements(coalesce(o.data -> 'items', '[]'::jsonb)) loop
    pid := it ->> 'id'; g := null;
    select p into pr from jsonb_array_elements(prods) p where p ->> 'id' = pid limit 1;
    if pr is not null and nullif(pr ->> 'gst', '') is not null then g := (pr ->> 'gst')::numeric;
    elsif nullif(it ->> 'gst', '') is not null then g := (it ->> 'gst')::numeric; end if;
    g := coalesce(g, 0); amt := coalesce(nullif(it ->> 'amount', '')::numeric, 0); tx := round(amt / (1 + g / 100), 2);
    lines := lines || jsonb_build_array(jsonb_build_object('title', it ->> 'title', 'sku', it ->> 'sku', 'qty', it -> 'qty', 'rate', it -> 'price', 'amount', amt, 'gst_pct', g, 'taxable', tx, 'gst_amt', round(amt - tx, 2)));
    t_tax := t_tax + tx; t_gst := t_gst + round(amt - tx, 2);
  end loop;
  ship := coalesce(nullif(o.data ->> 'shipping', '')::numeric, 0);
  select count(*) + 1 into n from public.sp_orders where data ->> 'invoice_no' is not null;
  fy := case when extract(month from now() at time zone 'Asia/Kolkata') >= 4 then to_char(now() at time zone 'Asia/Kolkata', 'YY') || to_char((now() at time zone 'Asia/Kolkata') + interval '1 year', 'YY')
             else to_char((now() at time zone 'Asia/Kolkata') - interval '1 year', 'YY') || to_char(now() at time zone 'Asia/Kolkata', 'YY') end;
  no_ := 'SP/' || fy || '/' || lpad(n::text, 4, '0');
  inv := jsonb_build_object('no', no_, 'date', to_char(now() at time zone 'Asia/Kolkata', 'DD Mon YYYY'), 'order_no', o.data ->> 'order_no',
    'lines', lines, 'taxable', round(t_tax, 2), 'gst', round(t_gst, 2), 'shipping', ship, 'total', round(t_tax + t_gst + ship, 2),
    'buyer', jsonb_build_object('name', o.data ->> 'name', 'phone', o.data ->> 'phone', 'address', o.data ->> 'address', 'city', o.data ->> 'city', 'pincode', o.data ->> 'pincode'),
    'seller', jsonb_build_object('name', coalesce(sett ->> 'legalName', sett ->> 'storeName'), 'gstin', sett ->> 'gstin', 'address', sett ->> 'address', 'phone', sett ->> 'phone', 'email', sett ->> 'email'));
  update public.sp_orders set status = 'paid',
     data = data || jsonb_build_object('invoice_no', no_, 'invoice', inv, 'payment_status', 'verified', 'payment_verified_at', now()::text, 'invoice_at', now()::text)
   where id = o.id;
  return inv;
end $$;
revoke all on function public.sp_admin_send_invoice(text, bigint) from public;
grant execute on function public.sp_admin_send_invoice(text, bigint) to anon, authenticated;

-- (4) Customer's account: orders carry payment status + invoice (only after admin sent it); designer payments listed ----
create or replace function public.crm_consumer_me(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); ok boolean := coalesce((u.meta ->> 'mob_ok')::boolean, true);
begin
  return jsonb_build_object('id', u.id, 'name', u.name, 'mobile', u.mobile, 'email', u.email, 'username', u.username, 'meta', coalesce(u.meta, '{}'::jsonb) - 'lock_until', 'created_at', u.created_at,
    'orders', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'order_no', o.data ->> 'order_no', 'created_at', o.created_at, 'status', o.status, 'total', o.data -> 'total', 'advance', o.data -> 'advance', 'payment', o.data ->> 'payment',
        'payment_status', o.data ->> 'payment_status', 'invoice_no', o.data ->> 'invoice_no', 'invoice', o.data -> 'invoice',
        'items', (select coalesce(jsonb_agg(jsonb_build_object('title', i ->> 'title', 'qty', i -> 'qty', 'amount', i -> 'amount')), '[]'::jsonb) from jsonb_array_elements(coalesce(o.data -> 'items', '[]'::jsonb)) i)) order by o.id desc)
      from (select * from public.sp_orders where (ok and (data ->> 'phone') = u.mobile) or (data ->> 'customer_id') = u.id::text order by id desc limit 100) o), '[]'::jsonb),
    'designs', coalesce((select jsonb_agg(public.sp_design_json(d) order by d.id desc) from (select * from public.sp_design_pay where customer_id = u.id::text order by id desc limit 50) d), '[]'::jsonb),
    'enquiries', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'created_at', e.created_at, 'status', e.status, 'type', e.data ->> 'type', 'subject', e.data ->> 'subject', 'message', e.data ->> 'message') order by e.id desc)
      from (select * from public.sp_enquiries where (ok and (data ->> 'phone') = u.mobile) or (data ->> 'customer_id') = u.id::text order by id desc limit 50) e), '[]'::jsonb));
end $$;

-- (5) reload API schema
notify pgrst, 'reload schema';

-- ============================================================================
-- ROUND 32 — Share links: every document (quotation, bill, receipt, ledger, blueprint, design, error report ...) can be sent on
-- WhatsApp as a link  sunpowers.in/d/<code>  -> page with details + Download button + WhatsApp preview card. Views are counted.
-- ============================================================================
create table if not exists public.sp_shares (
  id          bigserial primary key,
  token       text not null unique,
  kind        text not null default 'doc',
  title       text not null,
  subtitle    text,
  amount      numeric,
  valid_till  date,
  details     jsonb not null default '[]'::jsonb,
  pdf_url     text,
  view_url    text,
  file_name   text,
  brand       text,
  phone       text,
  ref         text,
  src         text not null default 'crm',
  by_uid      bigint,
  by_name     text,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '120 days',
  revoked     boolean not null default false,
  views       int not null default 0,
  first_view  timestamptz,
  last_view   timestamptz
);
create index if not exists sp_shares_ref_idx on public.sp_shares (ref, id desc);
alter table public.sp_shares enable row level security;
revoke all on public.sp_shares from anon, authenticated;

create table if not exists public.sp_share_rl (ip text not null, at timestamptz not null default now());
create index if not exists sp_share_rl_idx on public.sp_share_rl (ip, at);
alter table public.sp_share_rl enable row level security;
revoke all on public.sp_share_rl from anon, authenticated;

-- one place that checks and stores a share (staff and public calls both use it) ----------------------------------------
create or replace function public.sp_share_insert(p jsonb, p_uid bigint, p_name text, p_src text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare t text := encode(gen_random_bytes(10), 'hex'); k text; ti text; dt jsonb; pu text; vu text; am numeric; vt date;
begin
  ti := left(btrim(coalesce(p ->> 'title', '')), 200);
  if ti = '' then raise exception 'Title khaali hai'; end if;
  k := lower(left(coalesce(nullif(btrim(p ->> 'kind'), ''), 'doc'), 24));
  if k !~ '^[a-z_]+$' then k := 'doc'; end if;
  if p_src = 'public' and k not in ('design', 'blueprint', 'doctor', 'invoice', 'plan', 'report', 'doc') then raise exception 'Is type ka link nahi ban sakta'; end if;
  pu := nullif(btrim(coalesce(p ->> 'pdf_url', '')), '');
  if pu is not null and pu !~ '^https://[A-Za-z0-9.-]+/storage/v1/object/public/sp-images/u/[A-Za-z0-9_./%~+-]{1,250}$' then raise exception 'PDF ka link sahi nahi'; end if;
  vu := nullif(btrim(coalesce(p ->> 'view_url', '')), '');
  if vu is not null and (vu !~ '^https?://' or length(vu) > 12000) then raise exception 'View link sahi nahi'; end if;
  begin am := nullif(p ->> 'amount', '')::numeric; exception when others then am := null; end;
  begin vt := nullif(p ->> 'valid_till', '')::date; exception when others then vt := null; end;
  select coalesce(jsonb_agg(jsonb_build_array(left(btrim(coalesce(e ->> 0, '')), 80), left(btrim(coalesce(e ->> 1, '')), 240))), '[]'::jsonb) into dt
    from (select e from jsonb_array_elements(case when jsonb_typeof(p -> 'details') = 'array' then p -> 'details' else '[]'::jsonb end) with ordinality x(e, n)
           where jsonb_typeof(e) = 'array' and btrim(coalesce(e ->> 0, '')) <> '' order by n limit 30) q;
  insert into public.sp_shares (token, kind, title, subtitle, amount, valid_till, details, pdf_url, view_url, file_name, brand, phone, ref, src, by_uid, by_name, expires_at)
  values (t, k, ti, left(nullif(btrim(coalesce(p ->> 'subtitle', '')), ''), 240), am, vt, dt, pu, vu,
          left(nullif(regexp_replace(coalesce(p ->> 'file_name', ''), '[^A-Za-z0-9_.() -]+', '-', 'g'), ''), 120),
          left(nullif(btrim(coalesce(p ->> 'brand', '')), ''), 80), left(regexp_replace(coalesce(p ->> 'phone', ''), '\D', '', 'g'), 15),
          left(nullif(btrim(coalesce(p ->> 'ref', '')), ''), 80), p_src, p_uid, left(p_name, 80),
          now() + (case when p_src = 'public' then interval '30 days' else interval '120 days' end));
  return t;
end $$;
revoke all on function public.sp_share_insert(jsonb, bigint, text, text) from public, anon, authenticated;

-- staff (CRM login) -----------------------------------------------------------------------------------------------------
create or replace function public.crm_share_create(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); t text;
begin
  t := public.sp_share_insert(p, s.uid, s.name, 'crm');
  return jsonb_build_object('token', t);
end $$;
revoke all on function public.crm_share_create(jsonb) from public;