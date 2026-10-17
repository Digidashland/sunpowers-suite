-- ============================================================================
-- PHASE 1 (Orders): login required before placing an order + manual UTR payment
-- Run this ONCE in Supabase SQL Editor, AFTER app/setup.sql and crm/crm-setup.sql.
-- Safe to re-run (uses create or replace).
-- ============================================================================

-- 0) Best-effort admin notification (never blocks an order). Uses the company email
--    from CRM Settings -> Company -> Email.
create or replace function public.sp_notify_admin(p_subject text, p_html text)
returns void language plpgsql security definer
set search_path = public as $$
declare to_addr text;
begin
  select nullif(trim(data #>> '{company,email}'), '') into to_addr from public.crm_settings where id = 1;
  begin perform public.crm_alert(p_subject); exception when others then null; end;   -- Telegram / Slack / Webhook (if switched ON in CRM → Connections)
  if to_addr is null then return; end if;
  begin
    perform public.crm_mail(array[to_addr], p_subject, p_html);
  exception when others then
    null; -- mail problems are logged by crm_mail / ignored here so the customer's order still goes through
  end;
end $$;

-- 1) Order placement now requires a logged-in customer (email OTP login).
--    Guest orders are rejected on the server, not just hidden in the UI.
--    The customer token travels inside the order object as p_order->>'token'
--    and is never stored in the order row.
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

  insert into public.sp_orders(data) values (o) returning id into new_id;
  perform public.sp_notify_admin('Naya order #' || new_id || ' — ' || (o->>'name'),
    '<p>Naya order aaya hai: <b>#' || new_id || '</b></p><p>' || (o->>'name') || ' · ' || (o->>'phone') || '</p><p>Total: ₹' || (o->>'total') || ' — payment ka UTR aane par dobara notification milega. Admin panel mein dekhein.</p>');
  return new_id;
end $$;

-- 2) Customer submits the UTR (transaction reference) after paying.
--    Only the owner of the order (same customer account) can submit.
create or replace function public.sp_submit_utr(p jsonb)
returns jsonb language plpgsql security definer
set search_path = public as $$
declare u public.crm_users; oid bigint; utr text; rec public.sp_orders;
begin
  u := public.crm_csession(p ->> 'token');
  oid := nullif(p ->> 'id', '')::bigint;
  utr := upper(regexp_replace(coalesce(p ->> 'utr', ''), '\s', '', 'g'));
  if oid is null then raise exception 'Order number galat hai'; end if;
  if utr !~ '^[A-Z0-9]{6,30}$' then raise exception 'UTR / transaction ID sahi nahi hai (6 se 30 akshar/ank)'; end if;

  select * into rec from public.sp_orders where id = oid;
  if rec.id is null or (rec.data ->> 'customer_id') is distinct from u.id::text then
    raise exception 'Ye order aapke account mein nahi hai';
  end if;

  update public.sp_orders
     set data = data || jsonb_build_object('utr', utr, 'utr_at', now()::text, 'payment_status', 'submitted')
   where id = oid;

  perform public.sp_notify_admin('Payment submitted — order #' || oid,
    '<p>Order <b>#' || oid || '</b> ke liye customer ne UTR diya: <b>' || utr || '</b></p><p>Bank statement se check karke Admin panel mein Verify karein.</p>');
  return jsonb_build_object('id', oid, 'payment_status', 'submitted',
    'message', 'Payment verify hone ke baad aapka final receipt bheja jayega. Aapka order verification ke baad dispatch ke liye ready hoga. Dhanyavaad, Sunpowers se jude rahne ke liye.');
end $$;

-- 3) Admin verifies (or rejects) the payment after checking the bank statement.
create or replace function public.sp_admin_verify_payment(p_pass text, p_id bigint, p_ok boolean)
returns void language plpgsql security definer
set search_path = public as $$
begin
  perform public.sp_check(p_pass);
  update public.sp_orders
     set data = data || jsonb_build_object(
           'payment_status', case when p_ok then 'verified' else 'rejected' end,
           'payment_verified_at', now()::text),
         status = case when p_ok then 'paid' else status end
   where id = p_id;
  if not found then raise exception 'Order nahi mila'; end if;
end $$;

-- 4) Admin dashboard counter: orders waiting for payment verification.
create or replace function public.sp_admin_pending_payments(p_pass text)
returns integer language plpgsql stable security definer
set search_path = public as $$
begin
  perform public.sp_check(p_pass);
  return (select count(*)::int from public.sp_orders where data ->> 'payment_status' = 'submitted');
end $$;

-- 4b) Dashboard counts now also include payments waiting for verification.
create or replace function public.sp_admin_counts(p_pass text)
returns jsonb language plpgsql security definer
set search_path = public, extensions as $$
declare crm int := 0;
begin
  perform public.sp_check(p_pass);
  if to_regclass('public.crm_records') is not null then
    execute $q$select count(*) from public.crm_records where kind = 'item' and deleted_at is null and data #>> '{store,status}' = 'pending'$q$ into crm;
  end if;
  return jsonb_build_object(
    'orders_new', (select count(*) from public.sp_orders where status = 'new'),
    'enquiries_new', (select count(*) from public.sp_enquiries where status = 'new'),
    'last_order', (select coalesce(max(id), 0) from public.sp_orders),
    'last_enquiry', (select coalesce(max(id), 0) from public.sp_enquiries),
    'pay_pending', (select count(*) from public.sp_orders where data ->> 'payment_status' = 'submitted'),
    'crm_pending', crm, 'crm_ready', to_regclass('public.crm_records') is not null);
end $$;
revoke all on function public.sp_admin_counts(text) from public;
grant execute on function public.sp_admin_counts(text) to anon, authenticated;

-- 5) Grants: customers (anon key + their token) may place orders and submit UTR.
--    Admin-only functions are NOT granted to anon/authenticated for the admin tasks
--    (they check the admin password inside; grant to anon only as the front end calls them with the key).
revoke all on function public.sp_place_order(jsonb) from public;
grant execute on function public.sp_place_order(jsonb) to anon, authenticated;
revoke all on function public.sp_submit_utr(jsonb) from public;
grant execute on function public.sp_submit_utr(jsonb) to anon, authenticated;
revoke all on function public.sp_admin_verify_payment(text, bigint, boolean) from public;
grant execute on function public.sp_admin_verify_payment(text, bigint, boolean) to anon, authenticated;
revoke all on function public.sp_admin_pending_payments(text) from public;
grant execute on function public.sp_admin_pending_payments(text) to anon, authenticated;
