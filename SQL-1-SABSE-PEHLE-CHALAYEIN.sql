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

  -- pincode-wise availability (server-side, cannot be bypassed from the browser)
  perform public.sp_pin_guard(p_order ->> 'pincode', p_order -> 'items');

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
-- ============================================================================
-- PHASE 2 + 3 (database): blueprint, connections, bulk product tools, project -> store
-- Run ONCE in Supabase SQL Editor AFTER: app/setup.sql, crm/crm-setup.sql, app/phase1-login-orders.sql
-- Safe to re-run.
-- ============================================================================

-- (1) Visibility: blueprint records / blueprint leads follow Settings (who can see them)
-- (2) Projects can be sent to the Online Store (admin verifies there)
create or replace function public.crm_bp_role_ok(s public.crm_ses) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select coalesce(data #> '{blueprint,visible_roles}', '["admin","manager"]'::jsonb) ? (s).role from public.crm_settings where id = 1),
    (s).role in ('admin', 'manager'));
$$;

create or replace function public.crm_vis(s public.crm_ses, r public.crm_records) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare vk text;
begin
  if r.id is null or r.deleted_at is not null then return false; end if;
  if public.crm_is_admin(s) then return true; end if;
  if r.kind = 'item' then return public.crm_can(s, 'items.view'); end if;
  if r.kind = 'blueprint' then
    if r.owner_id = (s).uid or r.assigned_to = (s).uid then return true; end if;
    return public.crm_bp_role_ok(s);
  end if;
  if r.kind = 'lead' and coalesce(r.data ->> 'source', '') = 'Leads from project blueprint' then
    if r.owner_id = (s).uid or r.assigned_to = (s).uid then return true; end if;
    return public.crm_bp_role_ok(s);
  end if;
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
-- Settings load/save must never expose or wipe the stored connection keys
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
  if public.crm_can(s, 'settings.manage') then d := d || jsonb_build_object('secrets', coalesce(st.secrets, '{}'::jsonb) - 'resend_api_key' - 'conn'); end if;
  d := d - 'auth';
  return d;
end $$;

create or replace function public.crm_settings_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); d jsonb := p -> 'data';
begin
  perform public.crm_need(s, 'settings.manage');
  if jsonb_typeof(d) <> 'object' or length(d::text) > 400000 then raise exception 'Data galat hai'; end if;
  update public.crm_settings set data = (d - 'secrets' - 'auth') || jsonb_build_object('auth', coalesce(data -> 'auth', '{}'::jsonb)),
    secrets = case when d ? 'secrets' and jsonb_typeof(d -> 'secrets') = 'object' then ((d -> 'secrets') - 'resend_api_key' - 'conn') || jsonb_strip_nulls(jsonb_build_object('resend_api_key', secrets -> 'resend_api_key', 'conn', secrets -> 'conn')) else secrets end,
    updated_at = now() where id = 1;
  perform public.crm_log(s, 'settings', null, null, 'Company settings badli');
  return jsonb_build_object('ok', true);
end $$;

-- ============================================================================
-- (3) Blueprint — role check used by crm_vis (Settings → Project blueprint → "Kaun dekh sakta hai")
-- ============================================================================

-- Public (Store / Website) customer sends a blueprint and asks for a quotation → becomes a CRM lead
create or replace function public.sp_blueprint_submit(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token');      -- login is mandatory
        bp jsonb := p -> 'blueprint'; nm text; mob text;
        city text := left(trim(coalesce(p ->> 'city', '')), 80); note text := left(trim(coalesce(p ->> 'note', '')), 500);
        asg bigint; bid bigint; lid bigint; kw numeric; summary text; src text := coalesce(nullif(p ->> 'from', ''), 'web'); pc int := 0; newlead boolean := false;
begin
  if bp is null or jsonb_typeof(bp) <> 'object' then raise exception 'Blueprint adhura hai'; end if;
  -- photos and video stay on the customer's phone: they are never stored here
  if jsonb_typeof(bp -> 'photos') = 'array' then pc := jsonb_array_length(bp -> 'photos'); end if;
  begin pc := greatest(pc, coalesce(nullif(bp ->> 'photo_count', '')::int, 0)); exception when others then null; end;
  pc := least(pc, 50);
  bp := (bp - 'photos' - 'video') || jsonb_build_object('photo_count', pc);
  if length(bp::text) > 200000 then raise exception 'Blueprint bahut bada hai'; end if;
  nm := left(trim(coalesce(nullif(trim(u.name), ''), p ->> 'name', '')), 80);
  mob := public.crm_mobile(coalesce(nullif(u.mobile, ''), p ->> 'mobile', ''));
  if length(nm) < 2 then raise exception 'Naam likhein'; end if;
  if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Account me sahi 10 ank ka mobile save karein'; end if;
  if (select count(*) from public.crm_records where kind = 'blueprint' and data ->> 'user_id' = u.id::text and created_at > now() - interval '1 hour') >= 10 then raise exception 'Bahut zyada requests — thodi der baad try karein'; end if;
  kw := public.crm_num(bp #> '{result,kw}');
  select nullif(data #>> '{blueprint,assign_to}', '')::bigint into asg from public.crm_settings where id = 1;
  summary := 'Blueprint: ' || coalesce(bp #>> '{site,type}', '-') || ', ' || coalesce(bp #>> '{result,panels}', '0') || ' panels, ' || coalesce(kw::text, '0') || ' kW, structure ' || coalesce(bp #>> '{structure,type}', '-')
             || case when note <> '' then ' | ' || note else '' end;
  insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, data, search, created_by)
    values ('blueprint', nm, mob, 'new', 0, asg, (bp - 'customer') || jsonb_build_object('customer', jsonb_build_object('name', nm, 'mobile', mob, 'city', city, 'note', note), 'from', src, 'user_id', u.id), lower(nm || ' ' || mob), 0)
    returning id into bid;
  -- (Round 16) one person = one lead.  A lead is created ONLY the first time this account uses any Sunpowers tool; later use never makes another lead
  select id into lid from public.crm_records where kind = 'lead' and deleted_at is null and data ->> 'tools_uid' = u.id::text order by id limit 1;
  if lid is null then
    -- the same person may already have a lead from signing up: use that one (one person = one lead)
    select id into lid from public.crm_records where kind = 'lead' and deleted_at is null and data ->> 'signup_uid' = u.id::text and not (data ? 'tools_uid') order by id limit 1;
  end if;
  if lid is not null and not newlead and not exists (select 1 from public.crm_records where id = lid and data ? 'tools_uid') then
    update public.crm_records set assigned_to = coalesce(assigned_to, asg), data = data || jsonb_build_object('email', u.email, 'city', city, 'source', 'Leads from project blueprint', 'kw', kw, 'note', summary, 'company', true, 'blueprint_id', bid, 'tools_uid', u.id::text, 'tool', 'blueprint',
          'address', coalesce(bp #>> '{location,addr}', ''), 'map', 'https://www.google.com/maps?q=' || coalesce(bp #>> '{location,lat}', '') || ',' || coalesce(bp #>> '{location,lng}', ''))
      where id = lid;
    newlead := true;
  elsif lid is null then
    insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, due_at, data, search, created_by)
      values ('lead', nm, mob, 'new', 0, asg, public.crm_today(),
        jsonb_build_object('name', nm, 'mobile', mob, 'email', u.email, 'city', city, 'source', 'Leads from project blueprint', 'kw', kw, 'note', summary, 'company', true, 'blueprint_id', bid, 'tools_uid', u.id::text, 'tool', 'blueprint',
          'address', coalesce(bp #>> '{location,addr}', ''), 'map', 'https://www.google.com/maps?q=' || coalesce(bp #>> '{location,lat}', '') || ',' || coalesce(bp #>> '{location,lng}', '')),
        lower(nm || ' ' || mob), 0)
      returning id into lid;
    newlead := true;
    begin perform public.sp_notify_admin('Naya blueprint lead — ' || nm, '<p>' || nm || ' · ' || mob || '</p><p>' || summary || '</p><p>CRM → Leads mein dekhein.</p>'); exception when others then null; end;
  end if;
  update public.crm_records set data = data || jsonb_build_object('lead_id', lid) where id = bid;
  return jsonb_build_object('ok', true, 'id', bid, 'lead_id', lid, 'new_lead', newlead);
end $$;

-- Solar Error Detector (and any other Sunpowers tool): login required; lead only on the first use of the account
create or replace function public.sp_tool_use(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); tool text := coalesce(p ->> 'tool', ''); info text := left(trim(coalesce(p ->> 'info', '')), 500);
        asg bigint; lid bigint; mob text; src text;
begin
  if tool not in ('detector', 'blueprint') then raise exception 'Galat tool'; end if;
  select id into lid from public.crm_records where kind = 'lead' and deleted_at is null and data ->> 'tools_uid' = u.id::text order by id limit 1;
  if lid is not null then return jsonb_build_object('ok', true, 'new_lead', false, 'lead_id', lid); end if;
  mob := public.crm_mobile(coalesce(u.mobile, ''));
  if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Account me sahi 10 ank ka mobile save karein'; end if;
  src := case tool when 'detector' then 'Solar Error Detector' else 'Leads from project blueprint' end;
  select nullif(data #>> '{blueprint,assign_to}', '')::bigint into asg from public.crm_settings where id = 1;
  select id into lid from public.crm_records where kind = 'lead' and deleted_at is null and data ->> 'signup_uid' = u.id::text and not (data ? 'tools_uid') order by id limit 1;
  if lid is not null then
    update public.crm_records set assigned_to = coalesce(assigned_to, asg),
      data = data || jsonb_build_object('email', u.email, 'source', src, 'tool', tool, 'tools_uid', u.id::text, 'company', true, 'note', coalesce(nullif(info, ''), 'Used ' || tool)), updated_at = now()
      where id = lid;
    return jsonb_build_object('ok', true, 'new_lead', false, 'lead_id', lid);
  end if;
  insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, due_at, data, search, created_by)
    values ('lead', u.name, mob, 'new', 0, asg, public.crm_today(),
      jsonb_build_object('name', u.name, 'mobile', mob, 'email', u.email, 'source', src, 'tool', tool, 'tools_uid', u.id::text, 'company', true, 'note', coalesce(nullif(info, ''), 'Used ' || tool)),
      lower(u.name || ' ' || mob), 0)
    returning id into lid;
  begin perform public.sp_notify_admin('Naya lead (' || src || ') — ' || u.name, '<p>' || u.name || ' · ' || mob || '</p><p>' || info || '</p><p>CRM → Leads mein dekhein.</p>'); exception when others then null; end;
  return jsonb_build_object('ok', true, 'new_lead', true, 'lead_id', lid);
end $$;

-- CRM staff: save a blueprint (and optionally make the lead)
create or replace function public.crm_blueprint_save(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); bp jsonb := p -> 'blueprint'; id_ bigint := nullif(p ->> 'id', '')::bigint; old public.crm_records;
        nm text := left(trim(coalesce(p ->> 'name', '')), 80); mob text := public.crm_mobile(coalesce(p ->> 'mobile', '')); city text := left(trim(coalesce(p ->> 'city', '')), 80);
        mk boolean := coalesce((p ->> 'make_lead')::boolean, false); bid bigint; lid bigint; kw numeric; summary text; ex public.crm_records;
begin
  perform public.crm_need(s, 'leads.create');
  if bp is null or jsonb_typeof(bp) <> 'object' then raise exception 'Blueprint adhura hai'; end if;
  bp := (bp - 'photos' - 'video') || jsonb_build_object('photo_count', case when jsonb_typeof(bp -> 'photos') = 'array' then jsonb_array_length(bp -> 'photos') else coalesce(nullif(bp ->> 'photo_count', '')::int, 0) end);
  if length(bp::text) > 200000 then raise exception 'Blueprint bahut bada hai'; end if;
  if nm = '' then nm := 'Blueprint'; end if;
  if mk and mob !~ '^[6-9][0-9]{9}$' then raise exception 'Lead ke liye sahi 10 ank ka mobile likhein'; end if;
  kw := public.crm_num(bp #> '{result,kw}');
  if id_ is null then
    insert into public.crm_records(kind, title, mobile, status, owner_id, data, search, created_by)
      values ('blueprint', nm, nullif(mob, ''), 'new', (s).uid, (bp - 'customer') || jsonb_build_object('customer', jsonb_build_object('name', nm, 'mobile', mob, 'city', city), 'from', 'crm'), lower(nm || ' ' || coalesce(mob, '')), (s).uid) returning id into bid;
    perform public.crm_log(s, 'create', 'blueprint', bid, nm);
  else
    select * into old from public.crm_records where id = id_ and kind = 'blueprint' and deleted_at is null;
    if old.id is null or not public.crm_vis(s, old) then raise exception 'Blueprint nahi mila'; end if;
    update public.crm_records set title = nm, mobile = nullif(mob, ''), data = (bp - 'customer') || jsonb_build_object('customer', jsonb_build_object('name', nm, 'mobile', mob, 'city', city), 'lead_id', old.data -> 'lead_id', 'from', old.data -> 'from'),
      search = lower(nm || ' ' || coalesce(mob, '')), updated_at = now() where id = id_;
    bid := id_;
    perform public.crm_log(s, 'update', 'blueprint', bid, nm);
  end if;
  if mk then
    summary := 'Blueprint: ' || coalesce(bp #>> '{site,type}', '-') || ', ' || coalesce(bp #>> '{result,panels}', '0') || ' panels, ' || coalesce(kw::text, '0') || ' kW, structure ' || coalesce(bp #>> '{structure,type}', '-');
    select * into ex from public.crm_records where kind = 'lead' and deleted_at is null and mobile = mob and data ->> 'source' = 'Leads from project blueprint' order by id desc limit 1;
    if ex.id is not null then
      update public.crm_records set data = data || jsonb_build_object('blueprint_id', bid, 'kw', kw, 'note', summary), updated_at = now() where id = ex.id; lid := ex.id;
    else
      insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, due_at, data, search, created_by)
        values ('lead', nm, mob, 'new', (s).uid, (s).uid, public.crm_today(),
          jsonb_build_object('name', nm, 'mobile', mob, 'city', city, 'source', 'Leads from project blueprint', 'kw', kw, 'note', summary, 'blueprint_id', bid, 'address', coalesce(bp #>> '{location,addr}', '')),
          lower(nm || ' ' || mob), (s).uid) returning id into lid;
      perform public.crm_log(s, 'create', 'lead', lid, nm || ' (blueprint)');
    end if;
    update public.crm_records set data = data || jsonb_build_object('lead_id', lid) where id = bid;
  end if;
  return jsonb_build_object('ok', true, 'id', bid, 'lead_id', lid);
end $$;

create or replace function public.crm_blueprint_list(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token');
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'title', r.title, 'mobile', r.mobile, 'status', r.status, 'created_at', r.created_at, 'owner_id', r.owner_id,
      'data', jsonb_build_object('location', r.data -> 'location', 'area', r.data #- '{area,points}' -> 'area', 'site', r.data -> 'site', 'result', r.data -> 'result', 'structure', r.data -> 'structure', 'panel', r.data -> 'panel',
        'customer', r.data -> 'customer', 'lead_id', r.data -> 'lead_id', 'from', r.data -> 'from', 'photos', coalesce(case when jsonb_typeof(r.data -> 'photos') = 'array' then jsonb_array_length(r.data -> 'photos') end, nullif(r.data ->> 'photo_count', '')::int, 0))) order by r.id desc)
    from (select * from public.crm_records where kind = 'blueprint' and deleted_at is null order by id desc limit 300) r where public.crm_vis(s, r)), '[]'::jsonb);
end $$;

create or replace function public.crm_blueprint_get(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records;
begin
  select * into r from public.crm_records where id = (p ->> 'id')::bigint and kind = 'blueprint' and deleted_at is null;
  if r.id is null or not public.crm_vis(s, r) then raise exception 'Blueprint nahi mila'; end if;
  return jsonb_build_object('id', r.id, 'title', r.title, 'mobile', r.mobile, 'status', r.status, 'created_at', r.created_at, 'data', r.data);
end $$;

create or replace function public.crm_blueprint_delete(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records;
begin
  select * into r from public.crm_records where id = (p ->> 'id')::bigint and kind = 'blueprint' and deleted_at is null;
  if r.id is null or not public.crm_vis(s, r) then raise exception 'Blueprint nahi mila'; end if;
  if not (public.crm_is_admin(s) or r.owner_id = (s).uid) then raise exception 'Sirf banane wala ya Admin hata sakta hai'; end if;
  update public.crm_records set deleted_at = now(), deleted_by = (s).uid, delete_reason = 'Blueprint hataya' where id = r.id;
  perform public.crm_log(s, 'delete', 'blueprint', r.id, r.title);
  return jsonb_build_object('ok', true);
end $$;

-- Admin: who can see blueprint leads (Settings)
create or replace function public.crm_blueprint_cfg(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); roles jsonb; asg text;
begin
  if p ? 'visible_roles' then
    if not public.crm_is_admin(s) then raise exception 'Sirf Admin badal sakta hai'; end if;
    roles := coalesce(p -> 'visible_roles', '[]'::jsonb);
    if jsonb_typeof(roles) <> 'array' then raise exception 'Galat roles'; end if;
    asg := coalesce(p ->> 'assign_to', '');
    update public.crm_settings set data = jsonb_set(coalesce(data, '{}'::jsonb), '{blueprint}', jsonb_build_object('visible_roles', roles, 'assign_to', asg)) where id = 1;
    perform public.crm_log(s, 'settings', 'blueprint', 0, 'Blueprint visibility badli');
  end if;
  return coalesce((select jsonb_build_object('visible_roles', coalesce(data #> '{blueprint,visible_roles}', '["admin","manager"]'::jsonb), 'assign_to', coalesce(data #>> '{blueprint,assign_to}', '')) from public.crm_settings where id = 1),
                  '{"visible_roles":["admin","manager"],"assign_to":""}'::jsonb);
end $$;

-- ============================================================================
-- (4) Connections — API keys / links (stored server-side, never sent back to the browser)
-- ============================================================================
create or replace function public.crm_conn_get(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); c jsonb;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin connections dekh sakta hai'; end if;
  select coalesce(secrets -> 'conn', '{}'::jsonb) into c from public.crm_settings where id = 1;
  return coalesce((select jsonb_object_agg(pk, (select coalesce(jsonb_object_agg(fk,
      case when coalesce((fv ->> 'sec')::boolean, true) then jsonb_build_object('set', coalesce(fv ->> 'v', '') <> '', 'hint', case when length(coalesce(fv ->> 'v', '')) > 4 then '••••' || right(fv ->> 'v', 4) else '' end)
           else jsonb_build_object('set', coalesce(fv ->> 'v', '') <> '', 'value', fv ->> 'v') end), '{}'::jsonb) from jsonb_each(pv) f(fk, fv)))
    from jsonb_each(c) x(pk, pv)), '{}'::jsonb);
end $$;

create or replace function public.crm_conn_save(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); prov text := p ->> 'provider'; k text; v jsonb; cur jsonb; val text; sec boolean;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin connections badal sakta hai'; end if;
  if prov !~ '^[a-z0-9_]{2,30}$' then raise exception 'Galat provider'; end if;
  if jsonb_typeof(p -> 'values') <> 'object' then raise exception 'Galat data'; end if;
  select coalesce(secrets #> array['conn', prov], '{}'::jsonb) into cur from public.crm_settings where id = 1;
  for k, v in select * from jsonb_each(p -> 'values') loop
    if k !~ '^[a-z0-9_]{2,40}$' then raise exception 'Galat field'; end if;
    val := left(coalesce(v ->> 'v', ''), 10000); sec := coalesce((v ->> 'sec')::boolean, true);
    if coalesce(v ->> 'clear', '') = 'true' then cur := cur - k;
    elsif val <> '' then cur := cur || jsonb_build_object(k, jsonb_build_object('v', val, 'sec', sec));
    end if; -- blank = keep existing
  end loop;
  update public.crm_settings set secrets = jsonb_set(jsonb_set(coalesce(secrets, '{}'::jsonb), '{conn}', coalesce(secrets -> 'conn', '{}'::jsonb), true), array['conn', prov], cur, true) where id = 1;
  perform public.crm_log(s, 'settings', 'connection', 0, 'Connection badla: ' || prov);
  return jsonb_build_object('ok', true);
end $$;

-- server-side helper for other functions / edge code: read a saved connection value (not granted to the browser)
create or replace function public.crm_conn_val(prov text, fld text) returns text
language sql stable security definer set search_path = public as $$
  select secrets #>> array['conn', prov, fld, 'v'] from public.crm_settings where id = 1 $$;


-- ============================================================================
-- (4b) Connection ON/OFF + instant alerts (Telegram / Slack / Webhook) for new leads and orders
-- ============================================================================
create or replace function public.crm_conn_on(prov text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(secrets #>> array['conn', prov, 'enabled', 'v'], '1') <> '0'
     and exists (select 1 from jsonb_each(coalesce(secrets #> array['conn', prov], '{}'::jsonb)) e(k, v)
                 where e.k <> 'enabled' and coalesce(e.v ->> 'v', '') <> '')
  from public.crm_settings where id = 1 $$;

create or replace function public.crm_alert(p_text text, p_data jsonb default '{}'::jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare tok text; chat text; hook text;
begin
  if coalesce(public.crm_conn_on('telegram'), false) then
    tok := public.crm_conn_val('telegram', 'bot_token'); chat := public.crm_conn_val('telegram', 'chat_id');
    if coalesce(tok, '') <> '' and coalesce(chat, '') <> '' then
      begin execute 'select net.http_post(url := $1, body := $2, headers := $3)' using 'https://api.telegram.org/bot' || tok || '/sendMessage', jsonb_build_object('chat_id', chat, 'text', p_text), '{"Content-Type":"application/json"}'::jsonb;
      exception when others then null; end;
    end if;
  end if;
  if coalesce(public.crm_conn_on('slack'), false) then
    hook := public.crm_conn_val('slack', 'webhook_url');
    if coalesce(hook, '') <> '' then
      begin execute 'select net.http_post(url := $1, body := $2, headers := $3)' using hook, jsonb_build_object('text', p_text), '{"Content-Type":"application/json"}'::jsonb;
      exception when others then null; end;
    end if;
  end if;
  if coalesce(public.crm_conn_on('webhook'), false) then
    hook := public.crm_conn_val('webhook', 'url');
    if coalesce(hook, '') ~* '^https://' then
      begin execute 'select net.http_post(url := $1, body := $2, headers := $3)' using hook, jsonb_build_object('text', p_text, 'data', p_data), '{"Content-Type":"application/json"}'::jsonb;
      exception when others then null; end;
    end if;
  end if;
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
drop trigger if exists crm_lead_alert on public.crm_records;
create trigger crm_lead_alert after insert on public.crm_records for each row when (new.kind = 'lead') execute function public.crm_lead_alert_trg();

-- ============================================================================
-- (5) Products: bulk delete (all / by category) and sheet upload (update existing only)
-- ============================================================================
create or replace function public.crm_items_bulk_delete(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); sc text := coalesce(p ->> 'scope', ''); cat text := trim(coalesce(p ->> 'category', '')); tp text := coalesce(nullif(p ->> 'type', ''), 'product'); n int;
begin
  perform public.crm_need(s, 'items.delete');
  if tp not in ('product', 'project', 'maintenance') then raise exception 'Galat type'; end if;
  if sc not in ('all', 'category') then raise exception 'Galat scope'; end if;
  if sc = 'category' and cat = '' then raise exception 'Category chunein'; end if;
  update public.crm_records set deleted_at = now(), deleted_by = (s).uid, delete_reason = 'Bulk delete (' || sc || coalesce(': ' || nullif(cat, ''), '') || ')'
   where kind = 'item' and deleted_at is null and coalesce(data ->> 'type', 'product') = tp
     and (sc = 'all' or data ->> 'category' = cat or coalesce(data -> 'categories', '[]'::jsonb) ? cat);
  get diagnostics n = row_count;
  perform public.crm_log(s, 'delete', 'item', 0, 'Bulk delete ' || n || ' ' || tp || ' (' || sc || coalesce(': ' || nullif(cat, ''), '') || ')');
  return jsonb_build_object('ok', true, 'deleted', n);
end $$;

create or replace function public.crm_items_bulk_update(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); row_ jsonb; r public.crm_records; patch jsonb; k text; allowed text[];
        upd int := 0; skipped jsonb := '[]'::jsonb; costok boolean; nm text;
begin
  perform public.crm_need(s, 'items.edit');
  if jsonb_typeof(p -> 'rows') <> 'array' then raise exception 'Sheet khaali hai'; end if;
  if jsonb_array_length(p -> 'rows') > 5000 then raise exception 'Ek baar me 5000 se zyada rows nahi'; end if;
  costok := public.crm_can(s, 'items.cost');
  allowed := array['name', 'title', 'category', 'price', 'mrp', 'gst', 'hsn', 'unit', 'desc', 'more', 'brand', 'sku', 'stock', 'warranty', 'cost_price', 'min_price'];
  for row_ in select * from jsonb_array_elements(p -> 'rows') loop
    select * into r from public.crm_records where id = nullif(row_ ->> 'id', '')::bigint and kind = 'item' and deleted_at is null;
    if r.id is null then skipped := skipped || to_jsonb(coalesce(row_ ->> 'id', '?')); continue; end if;   -- update only: unknown id is never created
    patch := '{}'::jsonb;
    for k in select jsonb_object_keys(coalesce(row_ -> 'set', '{}'::jsonb)) loop
      if k = any(allowed) and (costok or k not in ('cost_price', 'min_price')) then patch := patch || jsonb_build_object(k, row_ -> 'set' -> k); end if;
    end loop;
    if patch = '{}'::jsonb then continue; end if;
    nm := coalesce(patch ->> 'name', r.title);
    update public.crm_records set title = left(nm, 200), amount = case when patch ? 'price' then public.crm_num(patch -> 'price') else amount end,
      data = data || patch, search = lower(nm || ' ' || coalesce(patch ->> 'brand', data ->> 'brand', '') || ' ' || coalesce(patch ->> 'sku', data ->> 'sku', '')), updated_at = now() where id = r.id;
    upd := upd + 1;
  end loop;
  perform public.crm_log(s, 'update', 'item', 0, 'Sheet upload: ' || upd || ' items update');
  return jsonb_build_object('ok', true, 'updated', upd, 'skipped', skipped);
end $$;

-- ============================================================================
-- Grants
-- ============================================================================
do $g$
declare f text;
begin
  foreach f in array array['public.sp_blueprint_submit(jsonb)', 'public.sp_tool_use(jsonb)', 'public.crm_blueprint_save(jsonb)', 'public.crm_blueprint_list(jsonb)', 'public.crm_blueprint_get(jsonb)', 'public.crm_blueprint_delete(jsonb)',
    'public.crm_blueprint_cfg(jsonb)', 'public.crm_conn_get(jsonb)', 'public.crm_conn_save(jsonb)', 'public.crm_items_bulk_delete(jsonb)', 'public.crm_items_bulk_update(jsonb)', 'public.crm_to_store(jsonb)']
  loop
    execute 'revoke all on function ' || f || ' from public';
    execute 'grant execute on function ' || f || ' to anon, authenticated';
  end loop;
  execute 'revoke all on function public.crm_conn_val(text, text) from public, anon, authenticated';
  execute 'revoke all on function public.crm_conn_on(text) from public, anon, authenticated';
  execute 'revoke all on function public.crm_alert(text, jsonb) from public, anon, authenticated';
  execute 'revoke all on function public.crm_bp_role_ok(public.crm_ses) from public, anon, authenticated';
end $g$;
-- ============================================================
-- Sunpowers — Website Admin (edit the website without code)
-- Safe to run more than once. Stores everything in ONE extra row (id = 'web') of sp_store;
-- the Online Store data (id = 'main') is never touched.
-- ============================================================
create or replace function public.sp_get_web()
returns jsonb language sql stable security definer
set search_path = public as $$
  select data from public.sp_store where id = 'web';
$$;

create or replace function public.sp_save_web(p_pass text, p_data jsonb)
returns timestamptz language plpgsql security definer
set search_path = public, extensions as $$
declare t timestamptz := now();
begin
  perform public.sp_check(p_pass);
  if p_data is null or jsonb_typeof(p_data) <> 'object' then raise exception 'Invalid data'; end if;
  if length(p_data::text) > 1500000 then raise exception 'Website data too large'; end if;
  insert into public.sp_store(id, data, updated_at) values ('web', p_data, t)
  on conflict (id) do update set data = excluded.data, updated_at = excluded.updated_at;
  return t;
end $$;

do $$ begin
  grant execute on function public.sp_get_web(), public.sp_save_web(text, jsonb) to anon, authenticated;
exception when undefined_object then null; end $$;

-- ============================================================================
-- ROUND 8 (database) — run AFTER crm-setup.sql, phase1, phase2-3, phase4. Safe to re-run.
--  1) Store order gets a number from the SAME server series (ORD/2026-27/0001)
--  2) Quotation / Bill / Purchase lines MUST come from Inventory (guard)
--  3) Safe uploads: only an admin-issued short-lived token can upload to storage
--  4) Clean-up (old quotations / closed enquiries) + storage meter
--  5) Dashboard graph data (business / leads / marketing / store / maintenance)
--  6) Maintenance & Audit: contracts, visit-done (stock + next date), default checklist + plans
-- ============================================================================

-- (1) --------------------------------------------------------------------------------

create or replace function public.sp_order_no(p_id bigint, p_token text) returns text
language plpgsql stable security definer set search_path = public as $$
declare u public.crm_users; o public.sp_orders;
begin
  u := public.crm_csession(p_token);
  select * into o from public.sp_orders where id = p_id and data ->> 'customer_id' = u.id::text;
  return o.data ->> 'order_no';
end $$;
do $$ begin grant execute on function public.sp_order_no(bigint, text) to anon, authenticated; exception when undefined_object then null; end $$;

-- consumer account shows the same order number
create or replace function public.crm_consumer_me(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token');
begin
  return jsonb_build_object('id', u.id, 'name', u.name, 'mobile', u.mobile, 'email', u.email, 'username', u.username, 'meta', coalesce(u.meta, '{}'::jsonb), 'created_at', u.created_at,
    'orders', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'order_no', o.data ->> 'order_no', 'created_at', o.created_at, 'status', o.status, 'total', o.data -> 'total', 'advance', o.data -> 'advance', 'payment', o.data ->> 'payment',
        'items', (select coalesce(jsonb_agg(jsonb_build_object('title', i ->> 'title', 'qty', i -> 'qty', 'amount', i -> 'amount')), '[]'::jsonb) from jsonb_array_elements(coalesce(o.data -> 'items', '[]'::jsonb)) i)) order by o.id desc)
      from (select * from public.sp_orders where (data ->> 'phone') = u.mobile or (data ->> 'customer_id') = u.id::text order by id desc limit 100) o), '[]'::jsonb),
    'enquiries', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'created_at', e.created_at, 'status', e.status, 'type', e.data ->> 'type', 'subject', e.data ->> 'subject', 'message', e.data ->> 'message') order by e.id desc)
      from (select * from public.sp_enquiries where (data ->> 'phone') = u.mobile or (data ->> 'customer_id') = u.id::text order by id desc limit 50) e), '[]'::jsonb));
end $$;

-- (2) --------------------------------------------------------------------------------
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
drop trigger if exists crm_lines_guard on public.crm_records;
create trigger crm_lines_guard before insert or update of data on public.crm_records for each row execute function public.crm_lines_guard();

-- (3) --------------------------------------------------------------------------------
create table if not exists public.sp_upload_tokens (token text primary key, exp timestamptz not null);
alter table public.sp_upload_tokens enable row level security;
revoke all on public.sp_upload_tokens from anon, authenticated;

create or replace function public.sp_admin_upload_token(p_pass text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare t text := encode(gen_random_bytes(12), 'hex');
begin
  perform public.sp_check(p_pass);
  delete from public.sp_upload_tokens where exp < now();
  insert into public.sp_upload_tokens(token, exp) values (t, now() + interval '8 hours');
  return t;
end $$;

create or replace function public.sp_upload_ok(p_name text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.sp_upload_tokens where token = split_part(p_name, '/', 2) and exp > now());
$$;
do $$ begin
  grant execute on function public.sp_admin_upload_token(text), public.sp_upload_ok(text) to anon, authenticated;
exception when undefined_object then null; end $$;

do $$ begin
  begin
    update storage.buckets set file_size_limit = 52428800,
      allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm','application/pdf']
    where id = 'sp-images';
  exception when others then null; end;
  begin
    drop policy if exists "sp images upload" on storage.objects;
    create policy "sp images upload" on storage.objects
      for insert to anon, authenticated with check (bucket_id = 'sp-images' and public.sp_upload_ok(name));
  exception when others then raise notice 'Storage policy skipped: %', sqlerrm; end;
exception when others then null; end $$;

-- (4) --------------------------------------------------------------------------------
create or replace function public.crm_storage_stats(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token');
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  return jsonb_build_object(
    'db_bytes', pg_database_size(current_database()),
    'files_bytes', coalesce((select sum(size) from public.crm_files), 0), 'files_n', (select count(*) from public.crm_files),
    'quotes_n', (select count(*) from public.crm_records where kind = 'quote' and deleted_at is null),
    'invoices_n', (select count(*) from public.crm_records where kind = 'invoice' and deleted_at is null),
    'enquiries_n', (select count(*) from public.sp_enquiries),
    'orders_n', (select count(*) from public.sp_orders));
end $$;

create or replace function public.crm_purge(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); days int := least(greatest(coalesce(nullif(p ->> 'days', '')::int, 90), 7), 3650);
        run boolean := coalesce(p ->> 'run', '') = 'true'; cut timestamptz; nq int; ne int; nd int := 0;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin safai kar sakta hai'; end if;
  cut := now() - make_interval(days => days);
  -- old quotations that never became a bill (bills, payments and customers are NEVER touched)
  select count(*) into nq from public.crm_records q where q.kind = 'quote' and q.created_at < cut and q.status in ('draft', 'sent', 'rejected')
    and not exists (select 1 from public.crm_records i where i.kind = 'invoice' and i.deleted_at is null and i.data ->> 'quote_id' = q.id::text);
  select count(*) into ne from public.sp_enquiries where status in ('closed', 'cancelled') and created_at < cut;
  if run then
    delete from public.crm_records q where q.kind = 'quote' and q.created_at < cut and q.status in ('draft', 'sent', 'rejected')
      and not exists (select 1 from public.crm_records i where i.kind = 'invoice' and i.deleted_at is null and i.data ->> 'quote_id' = q.id::text);
    delete from public.sp_enquiries where status in ('closed', 'cancelled') and created_at < cut;
    delete from public.crm_otps where created_at < now() - interval '7 days';
    delete from public.crm_mail_log where at < now() - interval '60 days';
    perform public.crm_log(s, 'purge', 'quote', 0, 'Safai: ' || nq || ' purani quotation, ' || ne || ' band enquiry (' || days || ' din se purani)');
  end if;
  return jsonb_build_object('quotes', nq, 'enquiries', ne, 'days', days, 'done', run);
end $$;

-- (5) --------------------------------------------------------------------------------
create or replace function public.crm_series(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); n int := least(greatest(coalesce(nullif(p ->> 'months', '')::int, 12), 3), 24);
        m_end date := date_trunc('month', public.crm_today())::date; m0 date; mk jsonb; res jsonb;
        mkt text := 'insta|face|fb|meta|google|justdial|^jd|indiamart|trade|sulekha|youtube|website|online|ads|whatsapp|exporters';
begin
  m0 := (m_end - make_interval(months => n - 1))::date;
  select jsonb_agg(to_char(g, 'YYYY-MM') order by g) into mk from generate_series(m0::timestamp, m_end::timestamp, interval '1 month') g;
  res := jsonb_build_object('months', mk);
  if public.crm_can(s, 'invoices.view_all') or public.crm_can(s, 'invoices.create') then
    res := res || jsonb_build_object('business', (select jsonb_agg(jsonb_build_object('m', mo,
      'sales', (select coalesce(sum(r.amount), 0) from public.crm_records r where r.kind = 'invoice' and r.deleted_at is null and to_char(r.created_at at time zone 'Asia/Kolkata', 'YYYY-MM') = mo and public.crm_vis(s, r)),
      'collected', (select coalesce(sum(r.amount), 0) from public.crm_records r where r.kind = 'payment' and r.deleted_at is null and to_char(r.due_at, 'YYYY-MM') = mo and public.crm_vis(s, r)),
      'quotes', (select coalesce(sum(r.amount), 0) from public.crm_records r where r.kind = 'quote' and r.deleted_at is null and to_char(r.created_at at time zone 'Asia/Kolkata', 'YYYY-MM') = mo and public.crm_vis(s, r))
    ) order by mo) from jsonb_array_elements_text(mk) mo));
  end if;
  if public.crm_can(s, 'leads.view_all') or public.crm_can(s, 'leads.create') then
    res := res || jsonb_build_object('leads', (select jsonb_agg(jsonb_build_object('m', mo,
      'new', (select count(*) from public.crm_records r where r.kind = 'lead' and r.deleted_at is null and to_char(r.created_at at time zone 'Asia/Kolkata', 'YYYY-MM') = mo and public.crm_vis(s, r)),
      'won', (select count(*) from public.crm_records r where r.kind = 'lead' and r.status = 'won' and r.deleted_at is null and to_char(r.created_at at time zone 'Asia/Kolkata', 'YYYY-MM') = mo and public.crm_vis(s, r))
    ) order by mo) from jsonb_array_elements_text(mk) mo));
  end if;
  if public.crm_can(s, 'marketing.leads') then
    res := res || jsonb_build_object('marketing', (select jsonb_agg(jsonb_build_object('m', mo,
      'leads', (select count(*) from public.crm_records r where r.kind = 'lead' and r.deleted_at is null and lower(coalesce(r.data ->> 'source', '')) ~ mkt and to_char(r.created_at at time zone 'Asia/Kolkata', 'YYYY-MM') = mo),
      'won', (select count(*) from public.crm_records r where r.kind = 'lead' and r.status = 'won' and r.deleted_at is null and lower(coalesce(r.data ->> 'source', '')) ~ mkt and to_char(r.created_at at time zone 'Asia/Kolkata', 'YYYY-MM') = mo)
    ) order by mo) from jsonb_array_elements_text(mk) mo));
  end if;
  if public.crm_can(s, 'orders.view') then
    res := res || jsonb_build_object('store', (select jsonb_agg(jsonb_build_object('m', mo,
      'orders', (select count(*) from public.sp_orders o where to_char(o.created_at at time zone 'Asia/Kolkata', 'YYYY-MM') = mo and o.status <> 'cancelled'),
      'amount', (select coalesce(sum(public.crm_num(o.data -> 'total')), 0) from public.sp_orders o where to_char(o.created_at at time zone 'Asia/Kolkata', 'YYYY-MM') = mo and o.status <> 'cancelled'),
      'enquiries', (select count(*) from public.sp_enquiries e where to_char(e.created_at at time zone 'Asia/Kolkata', 'YYYY-MM') = mo)
    ) order by mo) from jsonb_array_elements_text(mk) mo));
  end if;
  if public.crm_can(s, 'items.view') or public.crm_can(s, 'reminders.view_all') then
    res := res || jsonb_build_object('maintenance', (select jsonb_agg(jsonb_build_object('m', mo,
      'planned', (select count(*) from public.crm_records r where r.kind = 'reminder' and r.deleted_at is null and r.data ->> 'maint' = 'true' and to_char(r.due_at, 'YYYY-MM') = mo and public.crm_vis(s, r)),
      'done', (select count(*) from public.crm_records r where r.kind = 'reminder' and r.deleted_at is null and r.data ->> 'maint' = 'true' and r.status = 'done' and to_char(r.due_at, 'YYYY-MM') = mo and public.crm_vis(s, r))
    ) order by mo) from jsonb_array_elements_text(mk) mo));
  end if;
  return res;
end $$;

-- (6) --------------------------------------------------------------------------------
create or replace function public.crm_months_of(p_period text) returns int language sql immutable as $$
  select case lower(coalesce(p_period, '')) when 'monthly' then 1 when 'quarterly' then 3 when 'half' then 6 when 'halfyearly' then 6 when 'yearly' then 12 else 6 end $$;

create or replace function public.crm_maint_contract(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); ex public.crm_records; pl public.crm_records; months int; yrs int; total int; i int;
        cid text := 'MC-' || encode(gen_random_bytes(4), 'hex'); start_ date; checks jsonb := '[]'::jsonb; pname text; cost numeric := 0; asg bigint := coalesce(nullif(p ->> 'assigned_to', '')::bigint, (s).uid); c jsonb; ck public.crm_records;
begin
  if not (public.crm_can(s, 'customers.create') or public.crm_can(s, 'customers.edit') or public.crm_can(s, 'items.view') or public.crm_is_admin(s)) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  select * into ex from public.crm_records where id = (p ->> 'party_id')::bigint and kind = 'party';
  if not public.crm_vis(s, ex) then raise exception 'Customer nahi mila'; end if;
  begin start_ := (p ->> 'start')::date; exception when others then raise exception 'Sahi tareekh chunein'; end;
  if start_ is null then raise exception 'Pehli visit ki tareekh chunein'; end if;
  select * into pl from public.crm_records where id = nullif(p ->> 'plan_id', '')::bigint and kind = 'item' and deleted_at is null and data ->> 'type' = 'maintenance';
  if pl.id is null then raise exception 'Plan chunein (Maintenance & Audit Packages me plan banayein)'; end if;
  pname := pl.title; months := public.crm_months_of(pl.data ->> 'period');
  yrs := least(greatest(coalesce(nullif(pl.data ->> 'years', '')::int, 1), 1), 10);
  total := least(greatest(ceil(12.0 / months * yrs)::int, 1), 120);
  for c in select * from jsonb_array_elements(coalesce(pl.data -> 'checklist', '[]'::jsonb)) loop
    select * into ck from public.crm_records where id = nullif(c #>> '{}', '')::bigint and kind = 'item' and deleted_at is null and data ->> 'type' = 'mcheck';
    if ck.id is not null then
      checks := checks || jsonb_build_array(jsonb_build_object('id', ck.id, 'name', ck.title, 'cost', public.crm_num(ck.data -> 'cost'),
        'mat_id', nullif(ck.data ->> 'material_item_id', ''), 'mat_qty', public.crm_num(ck.data -> 'material_qty')));
      cost := cost + public.crm_num(ck.data -> 'cost');
    end if;
  end loop;
  for i in 0 .. total - 1 loop
    insert into public.crm_records(kind, title, status, owner_id, assigned_to, party_id, mobile, due_at, data, search, created_by)
    values ('reminder', 'Solar service — ' || ex.title, 'open', (s).uid, asg, ex.id, ex.mobile, (start_ + make_interval(months => i * months))::date,
      jsonb_build_object('type', 'amc', 'maint', true, 'contract_id', cid, 'plan_id', pl.id, 'plan_name', pname, 'free', coalesce((pl.data ->> 'free')::boolean, false), 'months', months,
        'visit_no', i + 1, 'visits_total', total, 'checks', checks, 'visit_cost', cost, 'mobile', coalesce(ex.mobile, ''), 'party_name', ex.title, 'title', 'Solar service — ' || ex.title),
      lower('solar service ' || ex.title || ' ' || pname), (s).uid);
  end loop;
  perform public.crm_log(s, 'create', 'maintenance', ex.id, 'Maintenance & Audit: ' || pname || ' → ' || ex.title || ' (' || total || ' visits)');
  return jsonb_build_object('ok', true, 'contract_id', cid, 'visits', total, 'first_due', start_);
end $$;

create or replace function public.crm_maint_done(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records; done_on date; ticked jsonb; c jsonb; tot numeric := 0; months int; k int := 0; nxt public.crm_records; nd date; first_next date; mats int := 0;
begin
  select * into r from public.crm_records where id = (p ->> 'id')::bigint and kind = 'reminder' and data ->> 'maint' = 'true';
  if r.id is null or not public.crm_vis(s, r) then raise exception 'Visit nahi mili'; end if;
  if r.status = 'done' then raise exception 'Ye visit pehle hi ho chuki hai'; end if;
  begin done_on := coalesce(nullif(p ->> 'done_on', '')::date, public.crm_today()); exception when others then raise exception 'Sahi tareekh chunein'; end;
  ticked := case when jsonb_typeof(p -> 'ticked') = 'array' then p -> 'ticked' else null end;
  for c in select * from jsonb_array_elements(coalesce(r.data -> 'checks', '[]'::jsonb)) loop
    if ticked is null or ticked @> to_jsonb((c ->> 'id')::text) or ticked @> to_jsonb((c ->> 'id')::bigint) then
      tot := tot + public.crm_num(c -> 'cost');
      if nullif(c ->> 'mat_id', '') is not null and public.crm_num(c -> 'mat_qty') > 0 then
        update public.crm_records set data = jsonb_set(data, '{stock}', to_jsonb(public.crm_num(data -> 'stock') - public.crm_num(c -> 'mat_qty'))), updated_at = now()
          where id = (c ->> 'mat_id')::bigint and kind = 'item' and data ? 'stock';
        mats := mats + 1;
      end if;
    end if;
  end loop;
  update public.crm_records set status = 'done', updated_at = now(),
    data = data || jsonb_build_object('done_on', done_on, 'done_cost', tot, 'done_ticked', coalesce(ticked, '[]'::jsonb), 'done_note', left(coalesce(p ->> 'note', ''), 500), 'done_by', (s).name)
    where id = r.id;
  -- next visits move forward from the actual service date
  months := coalesce(nullif(r.data ->> 'months', '')::int, 6);
  for nxt in select * from public.crm_records x where x.kind = 'reminder' and x.deleted_at is null and x.status = 'open' and x.data ->> 'contract_id' = r.data ->> 'contract_id'
      and coalesce((x.data ->> 'visit_no')::int, 0) > coalesce((r.data ->> 'visit_no')::int, 0) order by (x.data ->> 'visit_no')::int loop
    k := k + 1; nd := (done_on + make_interval(months => k * months))::date;
    update public.crm_records set due_at = nd, updated_at = now() where id = nxt.id;
    if k = 1 then first_next := nd; end if;
  end loop;
  perform public.crm_log(s, 'done', 'maintenance', r.id, 'Visit ho gayi: ' || r.title || ' (' || coalesce(r.data ->> 'plan_name', '') || ')');
  return jsonb_build_object('ok', true, 'cost', tot, 'next_due', first_next, 'materials', mats);
end $$;

-- default Maintenance & Audit checklist + plans (inserted once; afterwards fully controlled from Inventory)
create or replace function public.crm_seed_maint() returns void language plpgsql security definer set search_path = public as $$
declare ids jsonb := '{}'::jsonb; rec record; nid bigint; ck jsonb;
begin
  if coalesce((select (data ->> 'seeded_maint')::boolean from public.crm_settings where id = 1), false) then return; end if;
  if exists (select 1 from public.crm_records where kind = 'item' and data ->> 'type' = 'mcheck' and deleted_at is null) then return; end if;
  for rec in select * from (values
    ('clean',  'Solar panel cleaning',                         300, 'Panels ki safai (pani / brush)'),
    ('visual', 'Visual & physical inspection',                 100, 'Panel, structure, nut-bolt, crack / hot-spot ki nazar se jaanch'),
    ('inv',    'Inverter check (error log, display, firmware)',200, 'Inverter ka error log, display aur firmware'),
    ('earth',  'Earthing resistance test',                     300, 'Earthing pit ka resistance naapna'),
    ('acdb',   'ACDB check & tightening',                      200, 'AC distribution box, MCB, tightening'),
    ('dcdb',   'DCDB check & tightening',                      200, 'DC distribution box, fuse, SPD, tightening'),
    ('cable',  'Cable & MC4 connector check',                  200, 'Cable, MC4 connector aur joint ki jaanch'),
    ('shadow', 'Shadow & structure check',                     100, 'Naye shadow / structure ka jhukaav'),
    ('lightn', 'Lightning arrestor check',                     150, 'Lightning arrestor aur grounding'),
    ('report', 'Generation report',                            100, 'Meter / app se generation ka report'),
    ('iv',     'IV curve / thermography audit',                800, 'Performance audit (advanced)')
  ) as t(code, nm, cost, descr) loop
    insert into public.crm_records(kind, title, status, owner_id, amount, data, search)
    values ('item', rec.nm, 'active', 0, rec.cost, jsonb_build_object('type', 'mcheck', 'name', rec.nm, 'title', '', 'cost', rec.cost, 'price', rec.cost, 'unit', 'Visit', 'gst', 18, 'category', 'Maintenance & Audit', 'desc', rec.descr, 'material_item_id', '', 'material_qty', 0), lower(rec.nm))
    returning id into nid;
    ids := ids || jsonb_build_object(rec.code, nid);
  end loop;
  -- plans: name, period, years, price (0 = free), checklist codes
  for rec in select * from (values
    ('Free Basic Check (1 visit / saal)',      'yearly',    1,    0, 'visual,report',                                 true,  'Free: saal me 1 baar nazar se jaanch aur generation report'),
    ('Silver AMC (Half-yearly)',               'half',      1, 1600, 'clean,visual,inv,report',                       false, 'Saal me 2 visits: safai, jaanch, inverter, report'),
    ('Gold AMC (Quarterly)',                   'quarterly', 1, 4800, 'clean,visual,inv,earth,acdb,dcdb,cable,report', false, 'Saal me 4 visits: safai + poora electrical check'),
    ('Platinum Audit (Quarterly + IV audit)',  'quarterly', 1, 7200, 'clean,visual,inv,earth,acdb,dcdb,cable,shadow,lightn,report,iv', false, 'Saal me 4 visits + performance audit')
  ) as t(nm, per, yrs, price, codes, fr, descr) loop
    select jsonb_agg((ids ->> c)::bigint) into ck from unnest(string_to_array(rec.codes, ',')) c;
    insert into public.crm_records(kind, title, status, owner_id, amount, data, search)
    values ('item', rec.nm, 'active', 0, rec.price, jsonb_build_object('type', 'maintenance', 'name', rec.nm, 'title', '', 'category', 'Maintenance', 'price', rec.price, 'gst', 18, 'unit', 'Plan', 'period', rec.per, 'years', rec.yrs,
      'visits', case rec.per when 'quarterly' then 4 when 'half' then 2 when 'monthly' then 12 else 1 end, 'free', rec.fr, 'checklist', ck, 'desc', rec.descr), lower(rec.nm));
  end loop;
  update public.crm_settings set data = data || '{"seeded_maint": true}'::jsonb where id = 1;
end $$;
select public.crm_seed_maint();

do $g$
declare f text;
begin
  foreach f in array array['public.crm_storage_stats(jsonb)', 'public.crm_purge(jsonb)', 'public.crm_series(jsonb)', 'public.crm_maint_contract(jsonb)', 'public.crm_maint_done(jsonb)']
  loop
    execute 'revoke all on function ' || f || ' from public';
    execute 'grant execute on function ' || f || ' to anon, authenticated';
  end loop;
  execute 'revoke all on function public.crm_seed_maint() from public, anon, authenticated';
  execute 'revoke all on function public.crm_months_of(text) from public, anon, authenticated';
exception when undefined_object then null; end $g$;

-- (7) Admin: "Is device par login yaad rakhein" (opt-in, needs the Admin PIN; stays until Logout)
alter table public.crm_sessions add column if not exists keep boolean not null default false;
create or replace function public.crm_session(p_token text) returns public.crm_ses
language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses; se record; u public.crm_users; rp jsonb;
begin
  select * into se from public.crm_sessions where token = coalesce(p_token, '') and expires_at > now();
  if se.token is null then raise exception 'Login expired — dobara login karein'; end if;
  if se.role = 'consumer' then raise exception 'Ye login sirf Online Store ke liye hai'; end if;
  if (se.user_id <> 0 or se.keep) and se.expires_at < now() + interval '330 days' then update public.crm_sessions set expires_at = now() + interval '365 days' where token = se.token; end if;
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

create or replace function public.crm_admin_keep(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pe text; on_ boolean := coalesce((p ->> 'on')::boolean, false);
begin
  if not public.crm_is_admin(s) or (s).uid <> 0 then raise exception 'Ye option sirf Admin ke liye hai'; end if;
  pe := public.crm_auth_pin_check(public.crm_auth_find('admin', 'admin'), p ->> 'pin');
  if pe is not null then return jsonb_build_object('error', pe); end if;
  update public.crm_sessions set keep = on_, expires_at = now() + case when on_ then interval '365 days' else interval '12 hours' end where token = p ->> 'token' and user_id = 0;
  perform public.crm_log(s, 'settings', null, null, case when on_ then 'Admin login is device par yaad rakha' else 'Admin login yaad rakhna band' end);
  return jsonb_build_object('ok', true, 'keep', on_);
end $$;
do $g$ begin
  execute 'revoke all on function public.crm_admin_keep(jsonb) from public';
  execute 'grant execute on function public.crm_admin_keep(jsonb) to anon, authenticated';
exception when undefined_object then null; end $g$;

notify pgrst, 'reload schema';

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
  if not (public.crm_can(s, 'accounts.manage') or public.crm_can(s, 'accounts.view')) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
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
 {"g":"Products","k":"stock.view","l":"Stock, reserve aur expiry report dekhe"}
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
  if p_clear then delete from public.sp_pin_master where true; end if;
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
  delete from public.sp_pin_master where true; get diagnostics n = row_count;
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
    delete from public.sp_pin_rules where true; get diagnostics n = row_count;
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

create or replace function public.sp_pin_area_get(p_pass text, p_name text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare a public.sp_pin_areas;
begin
  perform public.sp_check(p_pass);
  select * into a from public.sp_pin_areas where name = public.sp_pin_norm(p_name);
  if not found then raise exception 'Area nahi mila'; end if;
  return jsonb_build_object('name', a.name, 'label', a.label, 'pins', to_jsonb(a.pins));
end $$;

-- p_pins: ["226001","226010-226020", ...]  (range bhi chalegi) ; p_add=true ho to purane pincodes me jodta hai
create or replace function public.sp_pin_area_save(p_pass text, p_label text, p_pins jsonb, p_add boolean default false) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare nm text := public.sp_pin_norm(p_label); t text; a int; b int; arr text[] := '{}'; k int; bad int := 0; cur text[];
begin
  perform public.sp_check(p_pass);
  if nm = '' or length(nm) > 60 or position('|' in nm) > 0 then raise exception 'Area ka naam likhein (60 akshar tak, | nahi)'; end if;
  if jsonb_typeof(p_pins) <> 'array' then raise exception 'Invalid pincodes'; end if;
  if jsonb_array_length(p_pins) > 40000 then raise exception 'Ek baar me 40000 se zyada entries nahi'; end if;
  for t in select jsonb_array_elements_text(p_pins) loop
    t := btrim(t);
    if t ~ '^[1-9][0-9]{5}$' then arr := arr || t;
    elsif t ~ '^[1-9][0-9]{5}\s*[-–]\s*[1-9][0-9]{5}$' then
      a := substring(t from '^([0-9]{6})')::int; b := substring(t from '([0-9]{6})$')::int;
      if b < a or b - a > 3000 then bad := bad + 1; else for k in a..b loop arr := arr || k::text; end loop; end if;
    elsif t <> '' then bad := bad + 1; end if;
  end loop;
  select coalesce(array_agg(distinct x order by x), '{}') into arr from unnest(arr) x;
  if p_add then select pins into cur from public.sp_pin_areas where name = nm; if cur is not null then select coalesce(array_agg(distinct x order by x), '{}') into arr from unnest(cur || arr) x; end if; end if;
  if coalesce(array_length(arr, 1), 0) = 0 then raise exception 'Ek bhi sahi pincode nahi mila'; end if;
  insert into public.sp_pin_areas(name, label, pins) values (nm, left(btrim(p_label), 60), arr)
  on conflict (name) do update set pins = excluded.pins, label = excluded.label, updated_at = now();
  return jsonb_build_object('name', nm, 'n', array_length(arr, 1), 'bad', bad);
end $$;

create or replace function public.sp_pin_area_delete(p_pass text, p_name text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare nm text := public.sp_pin_norm(p_name); n int; r int;
begin
  perform public.sp_check(p_pass);
  delete from public.sp_pin_rules where scope = 'area' and value = nm; get diagnostics r = row_count;
  delete from public.sp_pin_areas where name = nm; get diagnostics n = row_count;
  perform public.sp_pin_modes_gc();
  return jsonb_build_object('deleted', n, 'rules_deleted', r);
end $$;

-- only-mode ------------------------------------------------------------------------------------
create or replace function public.sp_pin_mode_set(p_pass text, p_product_id text, p_mode text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare pid text := btrim(coalesce(p_product_id, ''));
begin
  perform public.sp_check(p_pass);
  if pid = '' then raise exception 'Product chunein'; end if;
  if pid <> '*' and not exists (select 1 from public.sp_store s, jsonb_array_elements(coalesce(s.data -> 'products', '[]'::jsonb)) x where s.id = 'main' and x ->> 'id' = pid) then raise exception 'Product store me nahi mila'; end if;
  if p_mode = 'only' then insert into public.sp_pin_modes(product_id, mode) values (pid, 'only') on conflict (product_id) do update set mode = 'only';
  elsif p_mode = 'default' then delete from public.sp_pin_modes where product_id = pid;
  else raise exception 'Mode galat'; end if;
  return true;
end $$;

-- grants ------------------------------------------------------------------------------------------
do $$ begin
  revoke all on function public.sp_pin_unavail(text, text[]) from public, anon, authenticated;
  revoke all on function public.sp_pin_guard(text, jsonb) from public, anon, authenticated;
  revoke all on function public.sp_pin_modes_gc() from public, anon, authenticated;
  grant execute on function
    public.sp_pin_check(text, jsonb), public.sp_place_order(jsonb),
    public.sp_pin_admin_info(text), public.sp_pin_master_load(text, jsonb, boolean), public.sp_pin_master_clear(text),
    public.sp_pin_rules_summary(text), public.sp_pin_rules_list(text, jsonb), public.sp_pin_rules_export(text, jsonb),
    public.sp_pin_rules_apply(text, jsonb, jsonb), public.sp_pin_rules_delete(text, jsonb),
    public.sp_pin_area_list(text), public.sp_pin_area_get(text, text), public.sp_pin_area_save(text, text, jsonb, boolean),
    public.sp_pin_area_delete(text, text), public.sp_pin_mode_set(text, text, text)
  to anon, authenticated;
exception when undefined_object then null; end $$;

notify pgrst, 'reload schema';


-- ============================================================================
-- ROUND 11: CRM projects can now be sent to the Online Store (bulk send + Approved-for-Publish queue)
-- Run once in Supabase SQL Editor. Safe to re-run.
-- ============================================================================

-- ============================================================================
-- ROUND 13 (database) — Catalog + auto SKU, sheet codes (privacy), permissions, Dashboard/Analytics/Reports/Accounts.
-- Run AFTER everything above (ek baar). Dobara chalana safe hai.
-- ============================================================================
-- ============================================================================
-- ROUND 13 (database) — Catalog (11 categories + sub-categories), auto SKU serial, bulk add. Run AFTER phase7. Safe to re-run.
-- ============================================================================
create or replace function public.crm_catalog_default() returns jsonb language sql immutable as $$ select '[{"code": "PNL", "name": "Solar Panel/Solar Modules", "subs": [{"code": "BDC", "name": "Mono Bifacial DCR"}, {"code": "TDC", "name": "Mono Bifacial TOPCon DCR"}, {"code": "BND", "name": "Mono Bifacial Non-DCR"}, {"code": "TND", "name": "Mono Bifacial TOPCon Non-DCR"}, {"code": "SML", "name": "Small-size Panels"}]}, {"code": "INV", "name": "Solar Inverter", "subs": [{"code": "ONG", "name": "On-Grid Solar Inverters"}, {"code": "HYB", "name": "Hybrid Solar Inverters"}, {"code": "OFG", "name": "Off-Grid Solar Inverters"}, {"code": "DDC", "name": "Direct DC to AC Inverters"}]}, {"code": "BAT", "name": "Solar Batteries", "subs": [{"code": "LAB", "name": "Solar Lead-Acid Batteries"}, {"code": "LIB", "name": "Solar Lithium-ion Batteries"}]}, {"code": "STR", "name": "Solar Structure", "subs": [{"code": "GIS", "name": "GI Solar Structure"}, {"code": "HDG", "name": "HDGI Solar Structure"}, {"code": "SPR", "name": "Sunpowers Recommended Solar Structure"}]}, {"code": "ADB", "name": "Solar ACDB/DCDB", "subs": [{"code": "SDB", "name": "Single String DCDB"}, {"code": "MDB", "name": "Multi String DCDB"}, {"code": "SAC", "name": "Single Phase ACDB"}, {"code": "TAC", "name": "Triple Phase ACDB"}]}, {"code": "ERT", "name": "Chemical Earthings & LA", "subs": [{"code": "GIE", "name": "GI Earthing & LA"}, {"code": "CBE", "name": "Copper Bonded Earthing & LA"}]}, {"code": "LGT", "name": "Solar Lights", "subs": [{"code": "STL", "name": "Solar Street Lights"}, {"code": "GDL", "name": "Solar Garden Lights"}, {"code": "WLP", "name": "Solar Wall Lamps"}, {"code": "WLT", "name": "Solar Wall Lights"}]}, {"code": "CAM", "name": "Solar Cameras", "subs": [{"code": "SSC", "name": "Solar Street Cameras"}, {"code": "SCL", "name": "Solar Cameras with Street Lights"}]}, {"code": "HAP", "name": "Home Appliances", "subs": [{"code": "HIS", "name": "Home Inverters Complete Set"}, {"code": "HIN", "name": "Home Inverters"}, {"code": "HBT", "name": "Home Batteries"}]}, {"code": "BOS", "name": "Solar BOS Materials", "subs": [{"code": "DCC", "name": "DC Solar Cables"}, {"code": "ACC", "name": "AC Cables"}, {"code": "MC4", "name": "MC4 Connectors & Lugs"}, {"code": "CND", "name": "Conduits & Cable Trays"}, {"code": "PRT", "name": "Protection (MCB/MCCB/SPD/Fuse)"}, {"code": "ISO", "name": "Isolators & Switches"}, {"code": "MTR", "name": "Meters, CT & Monitoring"}, {"code": "JBX", "name": "Junction Boxes & Glands"}, {"code": "HDW", "name": "Hardware & Fasteners"}, {"code": "ACS", "name": "Installation Accessories"}]}, {"code": "MNT", "name": "Solar Maintenance & Package", "subs": [{"code": "FCM", "name": "Free Comprehensive Maintenance Plan"}, {"code": "MAU", "name": "Solar Maintenance & Audit Plan"}, {"code": "CLN", "name": "Solar Cleaning Package"}, {"code": "SFT", "name": "Solar Shifting Package"}]}]'::jsonb $$;

create or replace function public.crm_catalog() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select data -> 'catalog' from public.crm_settings where id = 1), public.crm_catalog_default()) $$;

create or replace function public.crm_pad3(t text) returns text language sql immutable as $$
  select rpad(upper(left(regexp_replace(coalesce(t, ''), '[^A-Za-z]', '', 'g'), 3)), 3, 'X') $$;

-- category / sub-category -> 3 letter codes (legacy category names are mapped too)
create or replace function public.crm_cat_codes(p_cat text, p_sub text) returns text[] language plpgsql stable security definer set search_path = public as $$
declare cat jsonb; sb jsonb; c text; s text; leg jsonb := '{"Solar Panel": "PNL", "Inverter": "INV", "Battery": "BAT", "Structure": "STR", "Cable": "BOS", "Accessories": "BOS", "Street Light": "LGT"}'::jsonb;
begin
  select x into cat from jsonb_array_elements(public.crm_catalog()) x where lower(x ->> 'name') = lower(coalesce(p_cat, '')) limit 1;
  if cat is null then
    c := coalesce(leg ->> coalesce(p_cat, ''), case when nullif(trim(coalesce(p_cat, '')), '') is null then 'GEN' else public.crm_pad3(p_cat) end);
    s := case when nullif(trim(coalesce(p_sub, '')), '') is null then 'GEN' else public.crm_pad3(p_sub) end;
  else
    c := cat ->> 'code';
    select y into sb from jsonb_array_elements(cat -> 'subs') y where lower(y ->> 'name') = lower(coalesce(p_sub, '')) limit 1;
    s := case when sb is not null then sb ->> 'code' when nullif(trim(coalesce(p_sub, '')), '') is null then 'GEN' else public.crm_pad3(p_sub) end;
  end if;
  return array[c, s];
end $$;

-- ONE global serial for every product + project item (gap-free, never re-used):  SP-PNL-BDC-00012
create or replace function public.crm_sku_gen(p_type text, p_cat text, p_sub text) returns text language plpgsql security definer set search_path = public as $$
declare cs text[]; n int;
begin
  if p_type = 'project' then cs := array['PRJ', public.crm_pad3(coalesce(nullif(p_cat, ''), 'GEN'))]; else cs := public.crm_cat_codes(p_cat, p_sub); end if;
  insert into public.crm_counters(key, n) values ('sku', 1) on conflict (key) do update set n = public.crm_counters.n + 1 returning public.crm_counters.n into n;
  return 'SP-' || cs[1] || '-' || cs[2] || '-' || lpad(n::text, 5, '0');
end $$;

-- called from crm_save for kind='item': keeps SKU immutable, moves old free-text SKU to "mpn", syncs SKU into project lines
create or replace function public.crm_item_prep(p_isnew boolean, p_old jsonb, d jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare typ text := coalesce(nullif(d ->> 'type', ''), 'product'); osku text := coalesce(p_old ->> 'sku', '');
begin
  if typ not in ('product', 'project') then return d; end if;
  if osku ~ '^SP-' then
    d := d || jsonb_build_object('sku', osku);
  else
    if coalesce(d ->> 'sku', '') <> '' and coalesce(d ->> 'sku', '') !~ '^SP-' then d := d || jsonb_build_object('mpn', coalesce(nullif(d ->> 'mpn', ''), d ->> 'sku')); end if;
    d := d || jsonb_build_object('sku', public.crm_sku_gen(typ, d ->> 'category', d ->> 'subcategory'));
  end if;
  if typ = 'project' and jsonb_typeof(d -> 'proj_items') = 'array' then
    d := jsonb_set(d, '{proj_items}', coalesce((
      select jsonb_agg(case when coalesce(x ->> 'item_id', '') ~ '^[0-9]+$' and exists (select 1 from public.crm_records r where r.id = (x ->> 'item_id')::bigint and r.kind = 'item')
                       then x || jsonb_build_object('sku', coalesce((select r.data ->> 'sku' from public.crm_records r where r.id = (x ->> 'item_id')::bigint), '')) else x end order by o)
      from jsonb_array_elements(d -> 'proj_items') with ordinality t(x, o)), '[]'::jsonb));
  end if;
  return d;
end $$;

create or replace function public.crm_catalog_get(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token');
begin perform public.crm_need(s, 'items.view'); return jsonb_build_object('ok', true, 'catalog', public.crm_catalog()); end $$;

-- ops: add_cat{name} | add_sub{cat,name} | rename_cat{code,name} | rename_sub{cat,code,name}   (cat = category code)
create or replace function public.crm_catalog_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); cur jsonb := public.crm_catalog(); op text := p ->> 'op'; nm text := left(trim(coalesce(p ->> 'name', '')), 60);
        code text; base text; i int := 0; cc jsonb; idx int; oldn text; sidx int;
begin
  perform public.crm_need(s, 'items.categories');
  if nm = '' then raise exception 'Naam likhein'; end if;
  if op = 'add_cat' then
    if exists (select 1 from jsonb_array_elements(cur) x where lower(x ->> 'name') = lower(nm)) then raise exception 'Ye category pehle se hai'; end if;
    base := public.crm_pad3(nm); code := base;
    while exists (select 1 from jsonb_array_elements(cur) x where x ->> 'code' = code) loop i := i + 1; code := left(base, 2) || i::text; end loop;
    cur := cur || jsonb_build_array(jsonb_build_object('code', code, 'name', nm, 'subs', '[]'::jsonb));
  elsif op in ('add_sub', 'rename_sub', 'rename_cat') then
    select ord - 1 into idx from jsonb_array_elements(cur) with ordinality t(x, ord) where x ->> 'code' = coalesce(p ->> 'cat', p ->> 'code') limit 1;
    if idx is null then raise exception 'Category nahi mili'; end if;
    cc := cur -> idx;
    if op = 'rename_cat' then
      oldn := cc ->> 'name'; cc := jsonb_set(cc, '{name}', to_jsonb(nm)); cur := jsonb_set(cur, array[idx::text], cc);
      update public.crm_records set data = jsonb_set(data, '{category}', to_jsonb(nm)) where kind = 'item' and data ->> 'category' = oldn;
    elsif op = 'add_sub' then
      if exists (select 1 from jsonb_array_elements(cc -> 'subs') x where lower(x ->> 'name') = lower(nm)) then raise exception 'Ye sub-category pehle se hai'; end if;
      base := public.crm_pad3(nm); code := base;
      while exists (select 1 from jsonb_array_elements(cc -> 'subs') x where x ->> 'code' = code) loop i := i + 1; code := left(base, 2) || i::text; end loop;
      cc := jsonb_set(cc, '{subs}', (cc -> 'subs') || jsonb_build_array(jsonb_build_object('code', code, 'name', nm)));
      cur := jsonb_set(cur, array[idx::text], cc);
    else
      select ord - 1 into sidx from jsonb_array_elements(cc -> 'subs') with ordinality t(x, ord) where x ->> 'code' = p ->> 'code' limit 1;
      if sidx is null then raise exception 'Sub-category nahi mili'; end if;
      oldn := cc -> 'subs' -> sidx ->> 'name';
      cc := jsonb_set(cc, array['subs', sidx::text, 'name'], to_jsonb(nm)); cur := jsonb_set(cur, array[idx::text], cc);
      update public.crm_records set data = jsonb_set(data, '{subcategory}', to_jsonb(nm)) where kind = 'item' and data ->> 'category' = cc ->> 'name' and data ->> 'subcategory' = oldn;
    end if;
  else raise exception 'Galat kaam'; end if;
  update public.crm_settings set data = jsonb_set(coalesce(data, '{}'::jsonb), '{catalog}', cur) where id = 1;
  perform public.crm_log(s, 'settings', 'item', 0, 'Catalog: ' || op || ' ' || nm);
  return jsonb_build_object('ok', true, 'catalog', cur);
end $$;

-- bulk add (Excel import + Starter Catalog). Skips rows whose seed_key already exists. Every row goes through crm_save (SKU, rules, log).
create or replace function public.crm_items_bulk_add(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r jsonb; added int := 0; skipped int := 0; bad jsonb := '[]'::jsonb; sk text;
begin
  perform public.crm_need(s, 'items.create');
  if jsonb_typeof(p -> 'rows') <> 'array' then raise exception 'Rows nahi mili'; end if;
  if jsonb_array_length(p -> 'rows') > 600 then raise exception 'Ek baar me 600 se zyada nahi'; end if;
  for r in select * from jsonb_array_elements(p -> 'rows') loop
    sk := nullif(r ->> 'seed_key', '');
    if sk is not null and exists (select 1 from public.crm_records where kind = 'item' and deleted_at is null and data ->> 'seed_key' = sk) then skipped := skipped + 1; continue; end if;
    begin
      perform public.crm_save(jsonb_build_object('token', p ->> 'token', 'kind', 'item', 'data', r));
      added := added + 1;
    exception when others then bad := bad || to_jsonb(coalesce(r ->> 'name', '?') || ': ' || sqlerrm);
    end;
  end loop;
  perform public.crm_log(s, 'import', 'item', 0, 'Bulk add: ' || added || ' items, skipped ' || skipped);
  return jsonb_build_object('ok', true, 'added', added, 'skipped', skipped, 'failed', bad);
end $$;

create or replace function public.crm_sku_backfill() returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0; d jsonb;
begin
  for r in select id, data from public.crm_records where kind = 'item' and deleted_at is null and coalesce(data ->> 'type', 'product') in ('product', 'project') and coalesce(data ->> 'sku', '') !~ '^SP-' order by id loop
    d := public.crm_item_prep(false, null, r.data);
    update public.crm_records set data = d, search = search || ' ' || lower(coalesce(d ->> 'sku', '')) where id = r.id; n := n + 1;
  end loop;
  return n;
end $$;
do $$ begin revoke execute on function public.crm_sku_backfill() from public, anon, authenticated; exception when others then null; end $$;
do $$ begin revoke execute on function public.crm_item_prep(boolean, jsonb, jsonb) from public, anon, authenticated; revoke execute on function public.crm_sku_gen(text, text, text) from public, anon, authenticated; exception when others then null; end $$;

do $g$
declare f text;
begin
  foreach f in array array['public.crm_catalog_get(jsonb)', 'public.crm_catalog_save(jsonb)', 'public.crm_items_bulk_add(jsonb)']
  loop begin execute 'grant execute on function ' || f || ' to anon, authenticated'; exception when others then null; end; end loop;
end $g$;


-- ============================================================================
-- ROUND 13 — Inventory/Stock: reserve (quotation / direct / online 20%), expiry, renew, dashboard + alerts
-- ============================================================================
create or replace function public.crm_online_pct() returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(nullif((select data #>> '{stock,online_pct}' from public.crm_settings where id = 1), '')::numeric, 20) $$;

-- every active (draft / sent / accepted, not expired) offline quotation reserves its item qty (project sub-items x project qty)
create or replace function public.crm_reserves(p_exclude bigint default null)
returns table(item_id bigint, qty numeric, quote_id bigint, ref text, customer text, valid_till text, qstatus text, qtitle text)
language sql stable security definer set search_path = public as $$
  select (l ->> 'item_id')::bigint, public.crm_num(l -> 'qty'), q.id, q.ref, q.title, q.data ->> 'valid_till', q.status, q.data ->> 'qtitle'
  from public.crm_records q, jsonb_array_elements(coalesce(q.data -> 'lines', '[]'::jsonb)) l
  where q.kind = 'quote' and q.deleted_at is null and q.status in ('draft', 'sent', 'accepted') and q.id <> coalesce(p_exclude, 0)
    and coalesce(l ->> 'kind', 'product') <> 'project' and coalesce(l ->> 'item_id', '') ~ '^[0-9]+$'
  union all
  select (x ->> 'item_id')::bigint, public.crm_num(x -> 'qty') * greatest(public.crm_num(l -> 'qty'), 1), q.id, q.ref, q.title, q.data ->> 'valid_till', q.status, q.data ->> 'qtitle'
  from public.crm_records q, jsonb_array_elements(coalesce(q.data -> 'lines', '[]'::jsonb)) l, jsonb_array_elements(coalesce(l -> 'proj_items', '[]'::jsonb)) x
  where q.kind = 'quote' and q.deleted_at is null and q.status in ('draft', 'sent', 'accepted') and q.id <> coalesce(p_exclude, 0)
    and coalesce(l ->> 'kind', 'product') = 'project' and coalesce(x ->> 'item_id', '') ~ '^[0-9]+$' $$;

-- manual holds (direct sale / online sale / other) live inside the item: data.holds = [{id,type,qty,for,until,note,by}]
create or replace function public.crm_holds_sum(p_data jsonb, p_online boolean) returns numeric language sql stable as $$
  select coalesce(sum(public.crm_num(h -> 'qty')), 0) from jsonb_array_elements(coalesce(p_data -> 'holds', '[]'::jsonb)) h
  where ((h ->> 'type') = 'online') = p_online and (coalesce(h ->> 'until', '') = '' or (h ->> 'until') >= public.crm_today()::text) $$;

-- once a day: offline quotations past their valid_till become "expired" (never deleted; reserve is released)
create or replace function public.crm_quote_expire_daily() returns void language plpgsql security definer set search_path = public as $$
declare td text := public.crm_today()::text;
begin
  if coalesce((select data #>> '{stock,expire_day}' from public.crm_settings where id = 1), '') = td then return; end if;
  update public.crm_records set status = 'expired', data = data || jsonb_build_object('pre_expire', status, 'expired_on', td), updated_at = now()
  where kind = 'quote' and deleted_at is null and status in ('draft', 'sent', 'accepted') and coalesce(data ->> 'valid_till', '') ~ '^\d{4}-\d{2}-\d{2}$' and (data ->> 'valid_till') < td;
  update public.crm_settings set data = jsonb_set(coalesce(data, '{}'::jsonb), '{stock,expire_day}', to_jsonb(td), true) where id = 1;
end $$;

-- returns NULL if the lines fit in the offline share (80%) of free stock, else a readable shortage message
create or replace function public.crm_quote_shortage(p_lines jsonb, p_exclude bigint) returns text language plpgsql stable security definer set search_path = public as $$
declare r record; it public.crm_records; pct numeric := public.crm_online_pct(); onh numeric; res numeric; hd numeric; fr numeric; msg text := '';
begin
  for r in select n.item_id, sum(n.qty) need from (
      select (l ->> 'item_id')::bigint item_id, public.crm_num(l -> 'qty') qty from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) l
        where coalesce(l ->> 'kind', 'product') <> 'project' and coalesce(l ->> 'item_id', '') ~ '^[0-9]+$'
      union all
      select (x ->> 'item_id')::bigint, public.crm_num(x -> 'qty') * greatest(public.crm_num(l -> 'qty'), 1)
        from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) l, jsonb_array_elements(coalesce(l -> 'proj_items', '[]'::jsonb)) x
        where coalesce(l ->> 'kind', 'product') = 'project' and coalesce(x ->> 'item_id', '') ~ '^[0-9]+$') n group by n.item_id
  loop
    select * into it from public.crm_records where id = r.item_id and kind = 'item' and deleted_at is null and data ? 'stock';
    if it.id is null then continue; end if;
    onh := public.crm_num(it.data -> 'stock');
    select coalesce(sum(qty), 0) into res from public.crm_reserves(p_exclude) z where z.item_id = it.id;
    hd := public.crm_holds_sum(it.data, false);
    fr := (onh - floor(onh * pct / 100)) - res - hd;
    if r.need > fr + 0.0001 then msg := msg || it.title || ' (chahiye ' || r.need || ', offline ke liye bacha ' || greatest(fr, 0) || '); '; end if;
  end loop;
  return nullif(msg, '');
end $$;

create or replace function public.crm_quote_renew(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; days int := least(greatest(coalesce(nullif(p ->> 'days', '')::int, 15), 1), 365); msg text;
begin
  perform public.crm_need(s, 'quotes.edit');
  select * into q from public.crm_records where id = (p ->> 'id')::bigint and kind = 'quote' and deleted_at is null;
  if not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if q.status <> 'expired' then raise exception 'Sirf expired quotation renew hoti hai'; end if;
  msg := public.crm_quote_shortage(q.data -> 'lines', q.id);
  if msg is not null and not public.crm_can(s, 'stock.override') then raise exception 'Renew nahi ho sakti — stock kam hai: %', msg; end if;
  update public.crm_records set status = coalesce(nullif(data ->> 'pre_expire', ''), 'sent'), data = (data - 'pre_expire' - 'expired_on') || jsonb_build_object('valid_till', (public.crm_today() + days)::text, 'renewed_on', public.crm_today()::text, 'renewals', public.crm_num(data -> 'renewals') + 1), updated_at = now() where id = q.id;
  perform public.crm_log(s, 'status', 'quote', q.id, coalesce(q.ref, '') || ' renew (' || days || ' din)');
  select * into q from public.crm_records where id = q.id; return public.crm_row(s, q);
end $$;

create or replace function public.crm_stock_hold(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); it public.crm_records; op text := p ->> 'op'; qty numeric := public.crm_num(p -> 'qty'); tp text := coalesce(nullif(p ->> 'type', ''), 'direct');
        onh numeric; res numeric; fr numeric; hid text; hs jsonb;
begin
  perform public.crm_need(s, 'stock.reserve');
  select * into it from public.crm_records where id = (p ->> 'item_id')::bigint and kind = 'item' and deleted_at is null;
  if it.id is null then raise exception 'Item nahi mila'; end if;
  hs := coalesce(it.data -> 'holds', '[]'::jsonb);
  if op = 'add' then
    if tp not in ('direct', 'online', 'other') then raise exception 'Galat prakar'; end if;
    if qty <= 0 then raise exception 'Qty likhein'; end if;
    if not (it.data ? 'stock') then raise exception 'Is item ka stock track nahi hota — pehle Stock bharein'; end if;
    onh := public.crm_num(it.data -> 'stock'); select coalesce(sum(z.qty), 0) into res from public.crm_reserves(null) z where z.item_id = it.id;
    fr := onh - res - public.crm_holds_sum(it.data, false) - public.crm_holds_sum(it.data, true);
    if qty > fr + 0.0001 then raise exception 'Itna stock free nahi hai (free: %)', greatest(fr, 0); end if;
    if length(trim(coalesce(p ->> 'for', ''))) < 2 then raise exception 'Kiske liye reserve hai — naam likhein'; end if;
    hid := 'h' || extract(epoch from clock_timestamp())::bigint::text || floor(random() * 1000)::int::text;
    hs := hs || jsonb_build_array(jsonb_build_object('id', hid, 'type', tp, 'qty', qty, 'for', left(trim(p ->> 'for'), 120), 'until', coalesce(nullif(p ->> 'until', ''), ''), 'note', left(coalesce(p ->> 'note', ''), 200), 'by', public.crm_uname((s).uid), 'on', public.crm_today()::text));
  elsif op = 'release' then
    hs := coalesce((select jsonb_agg(h) from jsonb_array_elements(hs) h where h ->> 'id' <> coalesce(p ->> 'hold_id', '')), '[]'::jsonb);
  else raise exception 'Galat kaam'; end if;
  update public.crm_records set data = jsonb_set(data, '{holds}', hs), updated_at = now() where id = it.id;
  perform public.crm_log(s, 'edit', 'item', it.id, 'Stock ' || case when op = 'add' then 'reserve ' || qty || ' (' || tp || ')' else 'reserve release' end || ': ' || it.title);
  return jsonb_build_object('ok', true, 'holds', hs);
end $$;

-- Inventory / Stock dashboard data
create or replace function public.crm_stock_report(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pct numeric := public.crm_online_pct(); rows jsonb; projs jsonb; tot jsonb;
begin
  perform public.crm_need(s, 'stock.view');
  perform public.crm_quote_expire_daily();
  with it as (
    select r.id, r.title, r.data d, public.crm_num(r.data -> 'stock') onh from public.crm_records r
    where r.kind = 'item' and r.deleted_at is null and coalesce(r.data ->> 'type', 'product') = 'product' and r.data ? 'stock' and r.status <> 'inactive'
  ), rs as (select item_id, sum(qty) q from public.crm_reserves(null) group by item_id),
  sold as (
    select i.item_id, sum(i.qty) q from (
      select (l ->> 'item_id')::bigint item_id, public.crm_num(l -> 'qty') qty from public.crm_records v, jsonb_array_elements(coalesce(v.data -> 'lines', '[]'::jsonb)) l
        where v.kind = 'invoice' and v.deleted_at is null and coalesce(l ->> 'kind', 'product') <> 'project' and coalesce(l ->> 'item_id', '') ~ '^[0-9]+$'
      union all
      select (x ->> 'item_id')::bigint, public.crm_num(x -> 'qty') * greatest(public.crm_num(l -> 'qty'), 1) from public.crm_records v, jsonb_array_elements(coalesce(v.data -> 'lines', '[]'::jsonb)) l, jsonb_array_elements(coalesce(l -> 'proj_items', '[]'::jsonb)) x
        where v.kind = 'invoice' and v.deleted_at is null and coalesce(l ->> 'kind', 'product') = 'project' and coalesce(x ->> 'item_id', '') ~ '^[0-9]+$') i group by i.item_id
  ), calc as (
    select it.id, it.title, it.d, it.onh, coalesce(rs.q, 0) rq, coalesce(sold.q, 0) sq, public.crm_holds_sum(it.d, false) hoff, public.crm_holds_sum(it.d, true) hon from it left join rs on rs.item_id = it.id left join sold on sold.item_id = it.id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'sku', d ->> 'sku', 'name', title, 'brand', d ->> 'brand', 'category', d ->> 'category', 'subcategory', d ->> 'subcategory', 'unit', coalesce(d ->> 'unit', 'Nos'),
      'on_hand', onh, 'sold', sq, 'total', onh + sq, 'reserved_quote', rq, 'hold_offline', hoff, 'hold_online', hon,
      'offline_cap', onh - floor(onh * pct / 100), 'free_offline', greatest((onh - floor(onh * pct / 100)) - rq - hoff, 0), 'free_total', greatest(onh - rq - hoff - hon, 0),
      'online_left_pct', case when onh > 0 then round(100 * greatest(onh - rq - hoff, 0) / onh, 1) else 0 end,
      'level', case when onh <= 0 then 'out' when 100 * (onh - rq - hoff) / onh < pct then 'low' else 'ok' end,
      'price', public.crm_num(d -> 'price'),
      'for', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select jsonb_build_object('t', 'quote', 'ref', z.ref, 'who', z.customer, 'title', z.qtitle, 'qty', z.qty, 'till', z.valid_till, 'qid', z.quote_id, 'st', z.qstatus) x from public.crm_reserves(null) z where z.item_id = calc.id
          union all select jsonb_build_object('t', 'hold', 'hid', h ->> 'id', 'type', h ->> 'type', 'who', h ->> 'for', 'qty', public.crm_num(h -> 'qty'), 'till', h ->> 'until', 'note', h ->> 'note')
            from jsonb_array_elements(coalesce(d -> 'holds', '[]'::jsonb)) h where coalesce(h ->> 'until', '') = '' or (h ->> 'until') >= public.crm_today()::text) q)
    ) order by (d ->> 'category'), title), '[]'::jsonb) into rows from calc;
  select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'sku', r.data ->> 'sku', 'name', r.title, 'live', (r.data #>> '{store,status}') = 'published', 'qty', public.crm_num(r.data -> 'price'),
      'buildable', (select min(floor(public.crm_num(i2.data -> 'stock') / greatest(public.crm_num(x -> 'qty'), 0.0001))) from jsonb_array_elements(coalesce(r.data -> 'proj_items', '[]'::jsonb)) x join public.crm_records i2 on i2.id = nullif(x ->> 'item_id', '')::bigint and i2.kind = 'item' and i2.data ? 'stock'),
      'risky', (select coalesce(jsonb_agg(i2.title), '[]'::jsonb) from jsonb_array_elements(coalesce(r.data -> 'proj_items', '[]'::jsonb)) x join public.crm_records i2 on i2.id = nullif(x ->> 'item_id', '')::bigint and i2.kind = 'item' and i2.data ? 'stock'
          where public.crm_num(i2.data -> 'stock') <= 0 or 100 * (public.crm_num(i2.data -> 'stock') - coalesce((select sum(z.qty) from public.crm_reserves(null) z where z.item_id = i2.id), 0) - public.crm_holds_sum(i2.data, false)) / nullif(public.crm_num(i2.data -> 'stock'), 0) < pct))
    order by r.id desc), '[]'::jsonb) into projs from public.crm_records r where r.kind = 'item' and r.deleted_at is null and r.data ->> 'type' = 'project' and r.status <> 'inactive';
  return jsonb_build_object('ok', true, 'pct', pct, 'rows', rows, 'projects', projs,
    'untracked', (select count(*) from public.crm_records r where r.kind = 'item' and r.deleted_at is null and coalesce(r.data ->> 'type', 'product') = 'product' and not (r.data ? 'stock')),
    'alerts', (select count(*) from jsonb_array_elements(rows) x where x ->> 'level' in ('low', 'out')));
end $$;

-- Store Admin dashboard banner (same database): items whose online share fell under 20% / out of stock
create or replace function public.sp_admin_stock_alerts(p_pass text) returns jsonb language plpgsql security definer set search_path = public as $$
declare pct numeric := public.crm_online_pct(); res jsonb;
begin
  perform public.sp_check(p_pass);
  select coalesce(jsonb_agg(jsonb_build_object('name', t.nm, 'sku', t.sku, 'on_hand', t.onh, 'level', t.lv, 'left_pct', t.leftp) order by (t.lv = 'out') desc, t.nm), '[]'::jsonb) into res from (
    select r.title nm, r.data ->> 'sku' sku, public.crm_num(r.data -> 'stock') onh,
      case when public.crm_num(r.data -> 'stock') <= 0 then 'out' else 'low' end lv,
      coalesce(round(100 * greatest(public.crm_num(r.data -> 'stock') - coalesce((select sum(z.qty) from public.crm_reserves(null) z where z.item_id = r.id), 0) - public.crm_holds_sum(r.data, false), 0) / nullif(public.crm_num(r.data -> 'stock'), 0), 1), 0) leftp
    from public.crm_records r where r.kind = 'item' and r.deleted_at is null and r.status <> 'inactive' and coalesce(r.data ->> 'type', 'product') = 'product' and r.data ? 'stock'
  ) t where t.lv = 'out' or t.leftp < pct;
  return jsonb_build_object('pct', pct, 'count', jsonb_array_length(res), 'items', res);
end $$;

do $g$
declare f text;
begin
  foreach f in array array['public.crm_quote_renew(jsonb)', 'public.crm_stock_hold(jsonb)', 'public.crm_stock_report(jsonb)']
  loop begin execute 'grant execute on function ' || f || ' to anon, authenticated'; exception when others then null; end; end loop;
  begin execute 'grant execute on function public.sp_admin_stock_alerts(text) to anon, authenticated'; exception when others then null; end;
  begin revoke execute on function public.crm_reserves(bigint), public.crm_quote_shortage(jsonb, bigint), public.crm_quote_expire_daily(), public.crm_holds_sum(jsonb, boolean), public.crm_online_pct() from public, anon, authenticated; exception when others then null; end;
end $g$;

-- existing databases: manager role default gets the new permissions (admin can untick later)
update public.crm_roles set perms = perms || '{"items.categories":true,"stock.reserve":true}'::jsonb where role = 'manager' and not (perms ? 'stock.reserve');


-- ============================================================================
-- Round 13-3: sheet scopes (download for edit -> upload edited sheet) + export log
-- A sheet that will be uploaded back must come from "Download sheet for edit": the server remembers
-- WHICH rows (ids) and WHICH columns were exported under a secret code (embedded in the sheet).
-- An upload may only touch those rows/columns, only until it expires, and everything is logged.
-- ============================================================================
create table if not exists public.crm_sheets (
  code text primary key, kind text not null, ids jsonb not null default '[]'::jsonb, cols jsonb not null default '[]'::jsonb, filt jsonb,
  n int not null default 0, issuer_uid bigint, issuer_name text, created_at timestamptz not null default now(), expires_at timestamptz not null,
  uses int not null default 0, last_used timestamptz, revoked boolean not null default false
);
alter table public.crm_sheets enable row level security;
do $r$ begin revoke all on public.crm_sheets from anon, authenticated; exception when others then null; end $r$;

create or replace function public.crm_sheet_issue(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); kind_ text := coalesce(nullif(p ->> 'kind', ''), 'item'); ids_ jsonb; cols_ jsonb := coalesce(p -> 'cols', '[]'::jsonb); c text;
        ok_ids jsonb; code_ text; allowed text[] := array['name', 'title', 'category', 'subcategory', 'price', 'mrp', 'gst', 'hsn', 'unit', 'desc', 'more', 'brand', 'mpn', 'image_link', 'stock', 'warranty', 'cost_price', 'min_price'];
        days int := 30;
begin
  if kind_ <> 'item' then raise exception 'Galat sheet'; end if;
  perform public.crm_need(s, 'items.edit'); perform public.crm_need(s, 'sheets.download');
  if jsonb_typeof(p -> 'ids') <> 'array' or jsonb_array_length(p -> 'ids') = 0 then raise exception 'Koi row nahi chuni'; end if;
  if jsonb_array_length(p -> 'ids') > 5000 then raise exception 'Ek sheet me 5000 se zyada rows nahi'; end if;
  if jsonb_typeof(cols_) <> 'array' or jsonb_array_length(cols_) = 0 then raise exception 'Koi column nahi chuna'; end if;
  for c in select jsonb_array_elements_text(cols_) loop
    if not (c = any(allowed) or c like 'spec:%') then raise exception 'Column "%" sheet me nahi ja sakta', c; end if;
    if c in ('cost_price', 'min_price') and not public.crm_can(s, 'items.cost') then raise exception 'Kharid / minimum rate dekhne ki permission nahi hai'; end if;
  end loop;
  select coalesce(jsonb_agg(r.id), '[]'::jsonb) into ok_ids from public.crm_records r
   where r.kind = 'item' and r.deleted_at is null and r.id::text in (select jsonb_array_elements_text(p -> 'ids')) and public.crm_vis(s, r);
  if jsonb_array_length(ok_ids) = 0 then raise exception 'Chuni hui rows aapko dikhane ki permission nahi hai'; end if;
  code_ := 'SH' || upper(substr(md5(random()::text || clock_timestamp()::text || (s).uid::text), 1, 12));
  insert into public.crm_sheets(code, kind, ids, cols, filt, n, issuer_uid, issuer_name, expires_at)
  values (code_, kind_, ok_ids, cols_, p -> 'filt', jsonb_array_length(ok_ids), (s).uid, (s).name, now() + make_interval(days => days));
  perform public.crm_log(s, 'export', 'item', 0, 'Sheet download for edit ' || code_ || ': ' || jsonb_array_length(ok_ids) || ' rows' || coalesce(' · filter ' || left(p ->> 'fdesc', 160), ''));
  return jsonb_build_object('ok', true, 'code', code_, 'n', jsonb_array_length(ok_ids), 'expires_at', now() + make_interval(days => days));
end $$;

create or replace function public.crm_sheet_list(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token');
begin
  perform public.crm_need(s, 'items.edit');
  return coalesce((select jsonb_agg(jsonb_build_object('code', code, 'kind', kind, 'n', n, 'issuer', issuer_name, 'created_at', created_at, 'expires_at', expires_at, 'uses', uses, 'last_used', last_used,
      'revoked', revoked, 'live', (not revoked and expires_at > now()), 'filt', filt, 'cols', cols) order by created_at desc)
    from (select * from public.crm_sheets where public.crm_is_admin(s) or public.crm_can(s, 'sheets.manage') or issuer_uid = (s).uid order by created_at desc limit 100) z), '[]'::jsonb);
end $$;

create or replace function public.crm_sheet_revoke(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); sh public.crm_sheets;
begin
  perform public.crm_need(s, 'items.edit');
  select * into sh from public.crm_sheets where code = p ->> 'code';
  if sh.code is null or not (public.crm_is_admin(s) or public.crm_can(s, 'sheets.manage') or sh.issuer_uid = (s).uid) then raise exception 'Sheet nahi mili'; end if;
  update public.crm_sheets set revoked = true where code = sh.code;
  perform public.crm_log(s, 'update', 'item', 0, 'Sheet ' || sh.code || ' band ki gayi');
  return jsonb_build_object('ok', true);
end $$;

-- upload edited sheet: only rows+columns that were exported under the sheet code
create or replace function public.crm_items_bulk_update(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); row_ jsonb; r public.crm_records; patch jsonb; k text; allowed text[]; sh public.crm_sheets; code_ text := nullif(trim(coalesce(p ->> 'code', '')), '');
        upd int := 0; skipped jsonb := '[]'::jsonb; blocked int := 0; outscope int := 0; costok boolean; nm text; sp jsonb; sk text; sset jsonb;
begin
  perform public.crm_need(s, 'items.edit'); perform public.crm_need(s, 'sheets.upload');
  if jsonb_typeof(p -> 'rows') <> 'array' then raise exception 'Sheet khaali hai'; end if;
  if jsonb_array_length(p -> 'rows') > 5000 then raise exception 'Ek baar me 5000 se zyada rows nahi'; end if;
  if code_ is null then
    if not public.crm_is_admin(s) then raise exception 'Ye sheet "Download sheet for edit" se nahi bani — upload nahi ho sakti'; end if;
  else
    select * into sh from public.crm_sheets where code = code_ and kind = 'item';
    if sh.code is null then raise exception 'Sheet ka code galat hai — dobara "Download sheet for edit" karein'; end if;
    if sh.revoked then raise exception 'Ye sheet band kar di gayi hai'; end if;
    if sh.expires_at < now() then raise exception 'Ye sheet expire ho gayi (30 din) — nayi sheet download karein'; end if;
  end if;
  costok := public.crm_can(s, 'items.cost');
  allowed := array['name', 'title', 'category', 'subcategory', 'price', 'mrp', 'gst', 'hsn', 'unit', 'desc', 'more', 'brand', 'mpn', 'image_link', 'stock', 'warranty', 'cost_price', 'min_price', 'specs'];
  for row_ in select * from jsonb_array_elements(p -> 'rows') loop
    select * into r from public.crm_records where id = nullif(row_ ->> 'id', '')::bigint and kind = 'item' and deleted_at is null;
    if r.id is null then skipped := skipped || to_jsonb(coalesce(row_ ->> 'id', '?')); continue; end if;   -- update only: unknown id is never created
    if code_ is not null and not (sh.ids ? r.id::text or sh.ids @> to_jsonb(r.id)) then outscope := outscope + 1; skipped := skipped || to_jsonb(r.id::text); continue; end if;
    if not public.crm_vis(s, r) then skipped := skipped || to_jsonb(r.id::text); continue; end if;
    patch := '{}'::jsonb;
    for k in select jsonb_object_keys(coalesce(row_ -> 'set', '{}'::jsonb)) loop
      if k = 'specs' then
        sset := '{}'::jsonb;
        if jsonb_typeof(row_ -> 'set' -> 'specs') = 'object' then
          for sk in select jsonb_object_keys(row_ -> 'set' -> 'specs') loop
            if code_ is null or sh.cols ? ('spec:' || sk) then sset := sset || jsonb_build_object(sk, row_ -> 'set' -> 'specs' -> sk); else blocked := blocked + 1; end if;
          end loop;
        end if;
        if sset <> '{}'::jsonb then patch := patch || jsonb_build_object('specs', sset); end if;
      elsif k = any(allowed) and (costok or k not in ('cost_price', 'min_price')) then
        if code_ is null or sh.cols ? k then patch := patch || jsonb_build_object(k, row_ -> 'set' -> k); else blocked := blocked + 1; end if;
      end if;
    end loop;
    if patch = '{}'::jsonb then continue; end if;
    nm := coalesce(patch ->> 'name', r.title);
    update public.crm_records set title = left(nm, 200), amount = case when patch ? 'price' then public.crm_num(patch -> 'price') else amount end,
      data = (data || (patch - 'specs')) || case when patch ? 'specs' and jsonb_typeof(patch -> 'specs') = 'object' then jsonb_build_object('specs', coalesce(data -> 'specs', '{}'::jsonb) || (patch -> 'specs')) else '{}'::jsonb end,
      search = lower(nm || ' ' || coalesce(patch ->> 'brand', data ->> 'brand', '') || ' ' || coalesce(data ->> 'sku', '') || ' ' || coalesce(patch ->> 'mpn', data ->> 'mpn', '') || ' ' || coalesce(patch ->> 'category', data ->> 'category', '') || ' ' || coalesce(patch ->> 'subcategory', data ->> 'subcategory', '')), updated_at = now() where id = r.id;
    upd := upd + 1;
  end loop;
  if code_ is not null then update public.crm_sheets set uses = uses + 1, last_used = now() where code = code_; end if;
  perform public.crm_log(s, 'update', 'item', 0, 'Sheet upload' || coalesce(' ' || code_, '') || ': ' || upd || ' items update' || case when outscope > 0 then ', ' || outscope || ' row sheet ke bahar (roki)' else '' end || case when blocked > 0 then ', ' || blocked || ' cell roke' else '' end);
  return jsonb_build_object('ok', true, 'updated', upd, 'skipped', skipped, 'outside', outscope, 'blocked', blocked);
end $$;

-- every download from the CRM is written to the Activity Record (who, what, how many rows, which filter)
create or replace function public.crm_export_log(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token');
begin
  perform public.crm_log(s, 'export', coalesce(nullif(p ->> 'kind', ''), 'report'), 0, 'Download ' || left(coalesce(p ->> 'name', '?'), 60) || ': ' || coalesce(nullif(p ->> 'rows', ''), '0') || ' rows' || coalesce(' · ' || nullif(left(p ->> 'filters', 200), ''), ''));
  return jsonb_build_object('ok', true);
end $$;

do $g$
declare f text;
begin
  foreach f in array array['public.crm_sheet_issue(jsonb)', 'public.crm_sheet_list(jsonb)', 'public.crm_sheet_revoke(jsonb)', 'public.crm_items_bulk_update(jsonb)', 'public.crm_export_log(jsonb)']
  loop begin execute 'revoke all on function ' || f || ' from public'; execute 'grant execute on function ' || f || ' to anon, authenticated'; exception when others then null; end; end loop;
end $g$;


-- ============================================================================
-- Round 13-3b: the same sheet-scope + download log for the Store Admin / Website Admin
-- (products sheet, full Excel, pincode rules). Table crm_sheets is shared with the CRM.
-- ============================================================================
create or replace function public.sp_sheet_issue(p_pass text, p_kind text, p_ids jsonb, p_cols jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare code_ text; n_ int;
begin
  perform public.sp_check(p_pass);
  if p_kind not in ('sp_product', 'sp_excel', 'sp_pin') then raise exception 'Galat sheet'; end if;
  if jsonb_typeof(coalesce(p_ids, '[]'::jsonb)) <> 'array' or jsonb_typeof(coalesce(p_cols, '[]'::jsonb)) <> 'array' then raise exception 'Galat data'; end if;
  n_ := jsonb_array_length(coalesce(p_ids, '[]'::jsonb));
  if n_ > 30000 or jsonb_array_length(coalesce(p_cols, '[]'::jsonb)) > 400 then raise exception 'Sheet bahut badi hai'; end if;
  code_ := 'SS' || upper(substr(md5(random()::text || clock_timestamp()::text || p_kind), 1, 12));
  insert into public.crm_sheets(code, kind, ids, cols, filt, n, issuer_uid, issuer_name, expires_at)
  values (code_, p_kind, coalesce(p_ids, '[]'::jsonb), coalesce(p_cols, '[]'::jsonb), jsonb_build_object('note', left(coalesce(p_note, ''), 300)), n_, null, 'Store Admin', now() + interval '30 days');
  insert into public.crm_activity(user_id, user_name, role, action, kind, rec_id, summary) values (null, 'Store Admin', 'admin', 'export', 'store', 0, left('Sheet download for edit ' || code_ || ' (' || p_kind || '): ' || n_ || ' rows' || coalesce(' · ' || nullif(p_note, ''), ''), 300));
  return jsonb_build_object('ok', true, 'code', code_, 'n', n_, 'expires_at', now() + interval '30 days');
end $$;

create or replace function public.sp_sheet_check(p_pass text, p_code text, p_kind text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sh public.crm_sheets;
begin
  perform public.sp_check(p_pass);
  select * into sh from public.crm_sheets where code = nullif(trim(coalesce(p_code, '')), '') and kind = p_kind;
  if sh.code is null then raise exception 'Sheet ka code galat hai — dobara "Edit ke liye sheet download" karein'; end if;
  if sh.revoked then raise exception 'Ye sheet band kar di gayi hai'; end if;
  if sh.expires_at < now() then raise exception 'Ye sheet expire ho gayi (30 din) — nayi sheet download karein'; end if;
  update public.crm_sheets set uses = uses + 1, last_used = now() where code = sh.code;
  insert into public.crm_activity(user_id, user_name, role, action, kind, rec_id, summary) values (null, 'Store Admin', 'admin', 'update', 'store', 0, left('Sheet upload ' || sh.code || ' (' || p_kind || ')', 300));
  return jsonb_build_object('ok', true, 'ids', sh.ids, 'cols', sh.cols, 'n', sh.n, 'filt', sh.filt);
end $$;

create or replace function public.sp_admin_export_log(p_pass text, p_name text, p_rows int, p_filters text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public.sp_check(p_pass);
  insert into public.crm_activity(user_id, user_name, role, action, kind, rec_id, summary) values (null, 'Store Admin', 'admin', 'export', 'store', 0, left('Download ' || coalesce(p_name, '?') || ': ' || coalesce(p_rows, 0) || ' rows' || coalesce(' · ' || nullif(p_filters, ''), ''), 300));
  return jsonb_build_object('ok', true);
end $$;

do $g$
declare f text;
begin
  foreach f in array array['public.sp_sheet_issue(text, text, jsonb, jsonb, text)', 'public.sp_sheet_check(text, text, text)', 'public.sp_admin_export_log(text, text, int, text)']
  loop begin execute 'revoke all on function ' || f || ' from public'; execute 'grant execute on function ' || f || ' to anon, authenticated'; exception when others then null; end; end loop;
end $g$;

-- ============================================================================
-- Round 13-4: permission points (tick / untick per user) — new points + sensible role defaults
-- Existing role settings are never overwritten (existing key wins), so any change the Admin made stays.
-- ============================================================================

update public.crm_roles set perms = '{"dashboard.money":true,"dashboard.team":true,"analytics.view":true,"analytics.all":true,"accounts.view":true,"reports.download":true,"sheets.download":true,"sheets.upload":true,"items.export":true,"stock.view":true}'::jsonb || coalesce(perms, '{}'::jsonb) where role = 'manager';
update public.crm_roles set perms = '{"stock.view":true,"analytics.view":true}'::jsonb || coalesce(perms, '{}'::jsonb) where role = 'staff';
update public.crm_roles set perms = '{"stock.view":true}'::jsonb || coalesce(perms, '{}'::jsonb) where role in ('dealer');

-- ============================================================================
-- Round 13-5: role-wise dashboard data, Analytics, Accounts (ledger / receivable / payable / payments out) and Reports
-- Everything is scoped by crm_vis (what the user may see) and by the permission points added in 13-4.
-- ============================================================================
create or replace function public.crm_rdate(r public.crm_records) returns date language sql stable as $$
  select coalesce(case when (r.data ->> 'date') ~ '^\d{4}-\d{2}-\d{2}' then left(r.data ->> 'date', 10)::date end, (r.created_at at time zone 'Asia/Kolkata')::date) $$;
create or replace function public.crm_pdate(r public.crm_records) returns date language sql stable as $$
  select coalesce(r.due_at, public.crm_rdate(r)) $$;
create or replace function public.crm_money_ok(s public.crm_ses) returns boolean language sql stable as $$
  select public.crm_can(s, 'dashboard.money') or public.crm_can(s, 'accounts.view') or public.crm_can(s, 'accounts.manage') $$;
create or replace function public.crm_mine(s public.crm_ses, r public.crm_records) returns boolean language sql stable as $$
  select public.crm_can(s, 'analytics.all') or r.owner_id = (s).uid or r.assigned_to = (s).uid $$;

-- ---------------------------------------------------------------- dashboard (extra data for the role-wise Home)
create or replace function public.crm_dash2(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); today_ date := public.crm_today(); m0 date := date_trunc('month', public.crm_today())::date; pm0 date := (date_trunc('month', public.crm_today()) - interval '1 month')::date;
        money boolean := public.crm_can(s, 'dashboard.money'); team boolean := public.crm_can(s, 'dashboard.team'); cur jsonb; prev jsonb; res jsonb;
begin
  create temp table if not exists _dv(kind text, status text, d date, amount numeric, kw numeric, src text, owner_id bigint, party_id bigint) on commit drop;
  truncate _dv;
  insert into _dv select r.kind, r.status, case r.kind when 'payment' then public.crm_pdate(r) else public.crm_rdate(r) end, r.amount, public.crm_num(r.data -> 'kw'), coalesce(nullif(r.data ->> 'source', ''), 'Other'), coalesce(r.assigned_to, r.owner_id), r.party_id
    from public.crm_records r where r.deleted_at is null and r.kind in ('lead', 'quote', 'invoice', 'payment', 'plant', 'party') and r.status <> 'cancelled'
      and (r.created_at >= pm0 - interval '40 days' or r.kind in ('lead', 'quote')) and public.crm_vis(s, r);
  select jsonb_build_object('leads_new', count(*) filter (where kind = 'lead'), 'leads_won', count(*) filter (where kind = 'lead' and status = 'won'),
      'quotes_n', count(*) filter (where kind = 'quote'), 'customers_new', count(*) filter (where kind = 'party'),
      'plants_n', count(*) filter (where kind = 'plant'), 'kw', coalesce(sum(kw) filter (where kind = 'plant'), 0),
      'bills_n', count(*) filter (where kind = 'invoice'),
      'quotes_amt', case when money then coalesce(sum(amount) filter (where kind = 'quote'), 0) end,
      'sales', case when money then coalesce(sum(amount) filter (where kind = 'invoice'), 0) end,
      'collected', case when money then coalesce(sum(amount) filter (where kind = 'payment'), 0) end)
    into cur from _dv where d >= m0 and d <= today_;
  select jsonb_build_object('leads_new', count(*) filter (where kind = 'lead'), 'leads_won', count(*) filter (where kind = 'lead' and status = 'won'),
      'quotes_n', count(*) filter (where kind = 'quote'), 'customers_new', count(*) filter (where kind = 'party'),
      'plants_n', count(*) filter (where kind = 'plant'), 'kw', coalesce(sum(kw) filter (where kind = 'plant'), 0),
      'bills_n', count(*) filter (where kind = 'invoice'),
      'quotes_amt', case when money then coalesce(sum(amount) filter (where kind = 'quote'), 0) end,
      'sales', case when money then coalesce(sum(amount) filter (where kind = 'invoice'), 0) end,
      'collected', case when money then coalesce(sum(amount) filter (where kind = 'payment'), 0) end)
    into prev from _dv where d >= pm0 and d < m0;
  res := jsonb_build_object('scope', case when team then 'all' else 'own' end, 'money', money, 'cur', cur, 'prev', prev,
    'leads_by_status', (select coalesce(jsonb_agg(jsonb_build_object('s', status, 'n', n) order by n desc), '[]'::jsonb) from (select status, count(*) n from _dv where kind = 'lead' group by status) x),
    'quotes_by_status', (select coalesce(jsonb_agg(jsonb_build_object('s', status, 'n', n, 'amt', case when money then a end) order by n desc), '[]'::jsonb) from (select status, count(*) n, sum(amount) a from _dv where kind = 'quote' group by status) x),
    'sources', (select coalesce(jsonb_agg(jsonb_build_object('s', src, 'n', n, 'won', w) order by n desc), '[]'::jsonb) from (select src, count(*) n, count(*) filter (where status = 'won') w from _dv where kind = 'lead' and d >= today_ - 90 group by src order by count(*) desc limit 6) x),
    'daily', (select coalesce(jsonb_agg(jsonb_build_object('d', to_char(g, 'YYYY-MM-DD'),
        'leads', (select count(*) from _dv where kind = 'lead' and d = g::date), 'quotes', (select count(*) from _dv where kind = 'quote' and d = g::date),
        'sales', case when money then (select coalesce(sum(amount), 0) from _dv where kind = 'invoice' and d = g::date) end) order by g), '[]'::jsonb)
        from generate_series((today_ - 13)::timestamp, today_::timestamp, interval '1 day') g));
  if money then
    res := res || jsonb_build_object('top_customers', (select coalesce(jsonb_agg(jsonb_build_object('name', coalesce((select title from public.crm_records pp where pp.id = z.party_id), 'Walk-in'), 'amt', z.a) order by z.a desc), '[]'::jsonb)
        from (select party_id, sum(amount) a from _dv where kind = 'invoice' group by party_id order by sum(amount) desc limit 5) z));
    res := res || jsonb_build_object('aging', (select jsonb_build_object('b0', coalesce(sum(bal) filter (where age <= 30), 0), 'b30', coalesce(sum(bal) filter (where age between 31 and 60), 0), 'b60', coalesce(sum(bal) filter (where age between 61 and 90), 0), 'b90', coalesce(sum(bal) filter (where age > 90), 0), 'total', coalesce(sum(bal), 0))
        from (select r.amount - public.crm_num(r.data -> 'paid') bal, today_ - public.crm_rdate(r) age from public.crm_records r where r.kind = 'invoice' and r.deleted_at is null and r.status in ('due', 'partial') and public.crm_vis(s, r)) q where bal > 0));
  end if;
  if team then
    res := res || jsonb_build_object('team', (select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'role', u.role,
        'leads_open', (select count(*) from public.crm_records r where r.kind = 'lead' and r.deleted_at is null and r.status not in ('won', 'lost') and coalesce(r.assigned_to, r.owner_id) = u.id),
        'overdue', (select count(*) from public.crm_records r where r.deleted_at is null and coalesce(r.assigned_to, r.owner_id) = u.id and r.due_at < today_ and ((r.kind = 'reminder' and r.status = 'open') or (r.kind = 'lead' and r.status not in ('won', 'lost')))),
        'quotes_m', (select count(*) from public.crm_records r where r.kind = 'quote' and r.deleted_at is null and r.owner_id = u.id and public.crm_rdate(r) >= m0),
        'sales_m', case when money then (select coalesce(sum(r.amount), 0) from public.crm_records r where r.kind = 'invoice' and r.deleted_at is null and r.status <> 'cancelled' and r.owner_id = u.id and public.crm_rdate(r) >= m0) end,
        'target', u.meta -> 'target_monthly') order by u.name), '[]'::jsonb)
      from public.crm_users u where u.status = 'active' and u.role in ('manager', 'staff', 'dealer', 'influencer')));
  end if;
  return res;
end $$;

-- ---------------------------------------------------------------- analytics
create or replace function public.crm_analytics(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); fr date := coalesce(nullif(p ->> 'from', '')::date, (date_trunc('month', public.crm_today()) - interval '11 months')::date); t date := coalesce(nullif(p ->> 'to', '')::date, public.crm_today());
        money boolean := public.crm_money_ok(s); uid_ bigint := nullif(p ->> 'user_id', '')::bigint; res jsonb;
begin
  perform public.crm_need(s, 'analytics.view');
  if t < fr or t - fr > 1100 then raise exception 'Sahi tareekh range chunein (max 3 saal)'; end if;
  if uid_ is not null and not public.crm_can(s, 'analytics.all') then uid_ := (s).uid; end if;
  create temp table if not exists _av(id bigint, kind text, status text, d date, amount numeric, kw numeric, src text, uid bigint, party_id bigint, lines jsonb, paid numeric) on commit drop;
  truncate _av;
  insert into _av select r.id, r.kind, r.status, case r.kind when 'payment' then public.crm_pdate(r) else public.crm_rdate(r) end, r.amount, public.crm_num(r.data -> 'kw'), coalesce(nullif(r.data ->> 'source', ''), 'Other'),
      coalesce(r.assigned_to, r.owner_id), r.party_id, case when r.kind = 'invoice' then coalesce(r.data -> 'lines', '[]'::jsonb) end, public.crm_num(r.data -> 'paid')
    from public.crm_records r where r.deleted_at is null and r.kind in ('lead', 'quote', 'invoice', 'payment', 'plant') and r.status <> 'cancelled' and public.crm_vis(s, r) and public.crm_mine(s, r)
      and (uid_ is null or r.owner_id = uid_ or r.assigned_to = uid_);
  delete from _av where d < fr or d > t;
  res := jsonb_build_object('from', fr, 'to', t, 'money', money, 'all', public.crm_can(s, 'analytics.all'),
    'months', (select coalesce(jsonb_agg(jsonb_build_object('m', to_char(g, 'YYYY-MM'),
        'leads', (select count(*) from _av where kind = 'lead' and to_char(d, 'YYYY-MM') = to_char(g, 'YYYY-MM')),
        'won', (select count(*) from _av where kind = 'lead' and status = 'won' and to_char(d, 'YYYY-MM') = to_char(g, 'YYYY-MM')),
        'quotes', (select count(*) from _av where kind = 'quote' and to_char(d, 'YYYY-MM') = to_char(g, 'YYYY-MM')),
        'bills', (select count(*) from _av where kind = 'invoice' and to_char(d, 'YYYY-MM') = to_char(g, 'YYYY-MM')),
        'kw', (select coalesce(sum(kw), 0) from _av where kind = 'plant' and to_char(d, 'YYYY-MM') = to_char(g, 'YYYY-MM')),
        'sales', case when money then (select coalesce(sum(amount), 0) from _av where kind = 'invoice' and to_char(d, 'YYYY-MM') = to_char(g, 'YYYY-MM')) end,
        'collected', case when money then (select coalesce(sum(amount), 0) from _av where kind = 'payment' and to_char(d, 'YYYY-MM') = to_char(g, 'YYYY-MM')) end) order by g), '[]'::jsonb)
      from generate_series(date_trunc('month', fr)::timestamp, date_trunc('month', t)::timestamp, interval '1 month') g),
    'sources', (select coalesce(jsonb_agg(jsonb_build_object('s', src, 'leads', n, 'won', w, 'rate', case when n > 0 then round(100.0 * w / n, 1) else 0 end) order by n desc), '[]'::jsonb) from (select src, count(*) n, count(*) filter (where status = 'won') w from _av where kind = 'lead' group by src) x),
    'funnel', jsonb_build_object('leads', (select count(*) from _av where kind = 'lead'), 'leads_won', (select count(*) from _av where kind = 'lead' and status = 'won'), 'leads_lost', (select count(*) from _av where kind = 'lead' and status = 'lost'),
        'quotes', (select count(*) from _av where kind = 'quote'), 'quotes_accepted', (select count(*) from _av where kind = 'quote' and status in ('accepted', 'converted')),
        'bills', (select count(*) from _av where kind = 'invoice'), 'bills_paid', (select count(*) from _av where kind = 'invoice' and status = 'paid')),
    'lead_status', (select coalesce(jsonb_agg(jsonb_build_object('s', status, 'n', n) order by n desc), '[]'::jsonb) from (select status, count(*) n from _av where kind = 'lead' group by status) x),
    'quote_status', (select coalesce(jsonb_agg(jsonb_build_object('s', status, 'n', n, 'amt', case when money then a end) order by n desc), '[]'::jsonb) from (select status, count(*) n, sum(amount) a from _av where kind = 'quote' group by status) x),
    'by_user', (select coalesce(jsonb_agg(jsonb_build_object('name', coalesce(u.name, 'Company'), 'leads', x.l, 'won', x.w, 'quotes', x.q, 'bills', x.b, 'kw', x.k, 'sales', case when money then x.sa end) order by x.sa desc nulls last), '[]'::jsonb)
        from (select uid, count(*) filter (where kind = 'lead') l, count(*) filter (where kind = 'lead' and status = 'won') w, count(*) filter (where kind = 'quote') q, count(*) filter (where kind = 'invoice') b,
              coalesce(sum(kw) filter (where kind = 'plant'), 0) k, coalesce(sum(amount) filter (where kind = 'invoice'), 0) sa from _av group by uid) x left join public.crm_users u on u.id = x.uid));
  if money then
    res := res || jsonb_build_object(
      'by_category', (select coalesce(jsonb_agg(jsonb_build_object('c', c, 'amt', a, 'qty', q) order by a desc), '[]'::jsonb) from (
          select coalesce(nullif(it.data ->> 'category', ''), 'Other') c, sum(public.crm_num(l -> 'qty') * public.crm_num(l -> 'price')) a, sum(public.crm_num(l -> 'qty')) q
          from _av v cross join lateral jsonb_array_elements(coalesce(v.lines, '[]'::jsonb)) l left join public.crm_records it on it.id = nullif(case when coalesce(l ->> 'item_id', '') ~ '^[0-9]+$' then l ->> 'item_id' end, '')::bigint
          where v.kind = 'invoice' group by 1) z),
      'by_item', (select coalesce(jsonb_agg(jsonb_build_object('name', nm, 'amt', a, 'qty', q) order by a desc), '[]'::jsonb) from (
          select coalesce(nullif(l ->> 'name', ''), '?') nm, sum(public.crm_num(l -> 'qty') * public.crm_num(l -> 'price')) a, sum(public.crm_num(l -> 'qty')) q
          from _av v cross join lateral jsonb_array_elements(coalesce(v.lines, '[]'::jsonb)) l where v.kind = 'invoice' group by 1 order by 2 desc limit 10) z),
      'top_customers', (select coalesce(jsonb_agg(jsonb_build_object('name', coalesce((select title from public.crm_records pp where pp.id = z.party_id), 'Walk-in'), 'amt', z.a, 'bills', z.n) order by z.a desc), '[]'::jsonb)
          from (select party_id, sum(amount) a, count(*) n from _av where kind = 'invoice' group by party_id order by sum(amount) desc limit 10) z),
      'aging', (select jsonb_build_object('b0', coalesce(sum(bal) filter (where age <= 30), 0), 'b30', coalesce(sum(bal) filter (where age between 31 and 60), 0), 'b60', coalesce(sum(bal) filter (where age between 61 and 90), 0), 'b90', coalesce(sum(bal) filter (where age > 90), 0), 'total', coalesce(sum(bal), 0))
          from (select amount - paid bal, public.crm_today() - d age from _av where kind = 'invoice' and status in ('due', 'partial')) q where bal > 0),
      'totals', (select jsonb_build_object('sales', coalesce(sum(amount) filter (where kind = 'invoice'), 0), 'collected', coalesce(sum(amount) filter (where kind = 'payment'), 0), 'quotes', coalesce(sum(amount) filter (where kind = 'quote'), 0)) from _av));
  end if;
  return res;
end $$;

-- ---------------------------------------------------------------- purchase payments (money paid OUT to suppliers)
create or replace function public.crm_purchase_pay(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records; amt numeric := public.crm_num(p -> 'amount'); paid numeric; pays jsonb; dt date := coalesce(nullif(p ->> 'date', '')::date, public.crm_today());
begin
  perform public.crm_need(s, 'purchase.manage');
  select * into r from public.crm_records where id = nullif(p ->> 'id', '')::bigint and kind = 'purchase' and deleted_at is null;
  if r.id is null then raise exception 'Purchase nahi mila'; end if;
  if r.status not in ('open', 'received') then raise exception 'Is purchase par payment nahi ho sakti'; end if;
  if amt <= 0 then raise exception 'Amount likhein'; end if;
  paid := public.crm_num(r.data -> 'paid');
  if paid + amt > r.amount + 0.005 then raise exception 'Baaki sirf % hai', round(r.amount - paid, 2); end if;
  pays := coalesce(r.data -> 'pays', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('date', dt, 'amount', amt, 'mode', coalesce(nullif(p ->> 'mode', ''), 'bank'), 'note', left(coalesce(p ->> 'note', ''), 200), 'by', (s).name));
  update public.crm_records set data = data || jsonb_build_object('pays', pays, 'paid', paid + amt), updated_at = now() where id = r.id;
  perform public.crm_log(s, 'update', 'purchase', r.id, 'Supplier ko payment ' || amt || ' (' || coalesce(r.ref, r.id::text) || ')');
  return jsonb_build_object('ok', true, 'paid', paid + amt, 'balance', r.amount - paid - amt);
end $$;

-- ---------------------------------------------------------------- receivable / payable (who owes whom)
create or replace function public.crm_receivable(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); side text := coalesce(nullif(p ->> 'side', ''), 'receivable'); today_ date := public.crm_today(); rows jsonb;
begin
  if not (public.crm_can(s, 'accounts.view') or public.crm_can(s, 'accounts.manage') or public.crm_can(s, 'invoices.view_all') or (side = 'receivable' and public.crm_can(s, 'invoices.create'))) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  if side = 'payable' then
    if not (public.crm_can(s, 'purchase.manage') or public.crm_can(s, 'accounts.view') or public.crm_can(s, 'accounts.manage')) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
    select coalesce(jsonb_agg(jsonb_build_object('party_id', party_id, 'name', coalesce((select title from public.crm_records pp where pp.id = z.party_id), '?'), 'mobile', (select mobile from public.crm_records pp where pp.id = z.party_id), 'n', n, 'total', tot, 'b0', b0, 'b30', b30, 'b60', b60, 'b90', b90, 'oldest', oldest,
        'docs', docs) order by tot desc), '[]'::jsonb) into rows from (
      select party_id, count(*) n, sum(bal) tot, sum(bal) filter (where age <= 30) b0, sum(bal) filter (where age between 31 and 60) b30, sum(bal) filter (where age between 61 and 90) b60, sum(bal) filter (where age > 90) b90, min(d) oldest,
        jsonb_agg(jsonb_build_object('id', id, 'ref', ref, 'date', d, 'amount', amt, 'paid', amt - bal, 'balance', bal, 'status', status) order by d) docs
      from (select r.id, r.ref, r.party_id, r.status, r.amount amt, r.amount - public.crm_num(r.data -> 'paid') bal, public.crm_rdate(r) d, today_ - public.crm_rdate(r) age
            from public.crm_records r where r.kind = 'purchase' and r.deleted_at is null and r.status = 'received' and public.crm_vis(s, r)) q where bal > 0.004 group by party_id) z;
  else
    select coalesce(jsonb_agg(jsonb_build_object('party_id', party_id, 'name', coalesce((select title from public.crm_records pp where pp.id = z.party_id), 'Walk-in'), 'mobile', (select mobile from public.crm_records pp where pp.id = z.party_id), 'n', n, 'total', tot, 'b0', b0, 'b30', b30, 'b60', b60, 'b90', b90, 'oldest', oldest,
        'docs', docs) order by tot desc), '[]'::jsonb) into rows from (
      select party_id, count(*) n, sum(bal) tot, sum(bal) filter (where age <= 30) b0, sum(bal) filter (where age between 31 and 60) b30, sum(bal) filter (where age between 61 and 90) b60, sum(bal) filter (where age > 90) b90, min(d) oldest,
        jsonb_agg(jsonb_build_object('id', id, 'ref', ref, 'date', d, 'amount', amt, 'paid', amt - bal, 'balance', bal, 'status', status) order by d) docs
      from (select r.id, r.ref, r.party_id, r.status, r.amount amt, r.amount - public.crm_num(r.data -> 'paid') bal, public.crm_rdate(r) d, today_ - public.crm_rdate(r) age
            from public.crm_records r where r.kind = 'invoice' and r.deleted_at is null and r.status in ('due', 'partial') and public.crm_vis(s, r)) q where bal > 0.004 group by party_id) z;
  end if;
  return jsonb_build_object('side', side, 'rows', rows, 'total', (select coalesce(sum((x ->> 'total')::numeric), 0) from jsonb_array_elements(rows) x));
end $$;

-- ---------------------------------------------------------------- ledger (party statement or day book)
create or replace function public.crm_ledger(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pid bigint := nullif(p ->> 'party_id', '')::bigint; fr date := coalesce(nullif(p ->> 'from', '')::date, (date_trunc('month', public.crm_today()))::date); t date := coalesce(nullif(p ->> 'to', '')::date, public.crm_today());
        opening numeric := 0; lines jsonb; pname text;
begin
  if not (public.crm_can(s, 'accounts.view') or public.crm_can(s, 'accounts.manage') or public.crm_can(s, 'invoices.view_all')) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  if t < fr or t - fr > 1100 then raise exception 'Sahi tareekh range chunein (max 3 saal)'; end if;
  create temp table if not exists _lg(d date, typ text, ref text, party_id bigint, party text, note text, debit numeric, credit numeric, cash_in numeric, cash_out numeric, sk bigint) on commit drop;
  truncate _lg;
  insert into _lg select public.crm_rdate(r), 'Bill', r.ref, r.party_id, coalesce((select title from public.crm_records pp where pp.id = r.party_id), ''), r.status, r.amount, 0, 0, 0, r.id
    from public.crm_records r where r.kind = 'invoice' and r.deleted_at is null and r.status <> 'cancelled' and public.crm_vis(s, r) and (pid is null or r.party_id = pid);
  insert into _lg select public.crm_pdate(r), 'Payment mila', r.ref, r.party_id, coalesce((select title from public.crm_records pp where pp.id = r.party_id), ''), coalesce(r.data ->> 'mode', ''), 0, r.amount, r.amount, 0, r.id
    from public.crm_records r where r.kind = 'payment' and r.deleted_at is null and public.crm_vis(s, r) and (pid is null or r.party_id = pid);
  if public.crm_can(s, 'purchase.manage') or public.crm_can(s, 'accounts.view') or public.crm_can(s, 'accounts.manage') or public.crm_is_admin(s) then
    insert into _lg select public.crm_rdate(r), 'Purchase', r.ref, r.party_id, coalesce((select title from public.crm_records pp where pp.id = r.party_id), ''), r.status, 0, r.amount, 0, 0, r.id
      from public.crm_records r where r.kind = 'purchase' and r.deleted_at is null and r.status = 'received' and (pid is null or r.party_id = pid) and public.crm_vis(s, r);
    insert into _lg select (pz ->> 'date')::date, 'Supplier ko payment', r.ref, r.party_id, coalesce((select title from public.crm_records pp where pp.id = r.party_id), ''), coalesce(pz ->> 'mode', ''), public.crm_num(pz -> 'amount'), 0, 0, public.crm_num(pz -> 'amount'), r.id
      from public.crm_records r cross join lateral jsonb_array_elements(coalesce(r.data -> 'pays', '[]'::jsonb)) pz where r.kind = 'purchase' and r.deleted_at is null and (pid is null or r.party_id = pid) and public.crm_vis(s, r);
    if pid is null then
      insert into _lg select e.spent_on, 'Kharcha', e.category, null, e.vendor, e.mode, 0, 0, 0, case when e.mode = 'credit' then 0 else e.amount end, e.id from public.crm_expenses e where e.deleted_at is null;
    end if;
  end if;
  select coalesce(sum(debit - credit), 0) into opening from _lg where d < fr and pid is not null;
  select coalesce(jsonb_agg(jsonb_build_object('d', d, 'typ', typ, 'ref', ref, 'party', party, 'note', note, 'debit', debit, 'credit', credit, 'cash_in', cash_in, 'cash_out', cash_out, 'bal', bal) order by d, typ, sk), '[]'::jsonb) into lines
    from (select z.*, opening + sum(debit - credit) over (order by d, typ, sk rows unbounded preceding) bal from _lg z where d between fr and t) y;
  select title into pname from public.crm_records where id = pid;
  return jsonb_build_object('from', fr, 'to', t, 'party_id', pid, 'party', pname, 'opening', opening, 'lines', lines,
    'tot', (select jsonb_build_object('debit', coalesce(sum(debit), 0), 'credit', coalesce(sum(credit), 0), 'cash_in', coalesce(sum(cash_in), 0), 'cash_out', coalesce(sum(cash_out), 0)) from _lg where d between fr and t));
end $$;

-- ---------------------------------------------------------------- one generic report engine (filters: from/to, user, status, party, category, text)
create or replace function public.crm_report(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); rep text := p ->> 'report'; fr date := coalesce(nullif(p ->> 'from', '')::date, (date_trunc('month', public.crm_today()) - interval '2 months')::date); t date := coalesce(nullif(p ->> 'to', '')::date, public.crm_today());
        uid_ bigint := nullif(p ->> 'user_id', '')::bigint; st text := nullif(p ->> 'status', ''); pid bigint := nullif(p ->> 'party_id', '')::bigint; cat text := nullif(p ->> 'category', ''); q text := lower(nullif(trim(coalesce(p ->> 'q', '')), ''));
        money boolean := public.crm_can(s, 'accounts.view') or public.crm_can(s, 'accounts.manage') or public.crm_can(s, 'invoices.view_all'); head jsonb; rows jsonb; title_ text;
begin
  perform public.crm_need(s, 'reports.view');
  if t < fr or t - fr > 1100 then raise exception 'Sahi tareekh range chunein (max 3 saal)'; end if;
  if uid_ is not null and not public.crm_can(s, 'analytics.all') and not public.crm_is_admin(s) and uid_ <> (s).uid then uid_ := (s).uid; end if;
  if rep in ('sales', 'gst_sale', 'collections', 'receivable', 'expenses', 'purchase', 'payable', 'stock_value') and not (money or (rep = 'stock_value' and public.crm_can(s, 'items.cost'))) then raise exception 'Aapko is report ki permission nahi hai'; end if;
  if rep = 'sales' then
    title_ := 'Sales register'; head := '["Date","Bill no","Customer","GSTIN","Taxable","Discount","GST","Total","Paid","Balance","Status","Banaya"]'::jsonb;
    select coalesce(jsonb_agg(jsonb_build_array(public.crm_rdate(r), r.ref, pt.title, coalesce(pt.data ->> 'gstin', ''), public.crm_num(r.data -> 'subtotal') - public.crm_num(r.data -> 'discount'), public.crm_num(r.data -> 'discount'), public.crm_num(r.data -> 'gst_total'), r.amount,
        public.crm_num(r.data -> 'paid'), r.amount - public.crm_num(r.data -> 'paid'), r.status, coalesce(u.name, 'Company')) order by public.crm_rdate(r), r.id), '[]'::jsonb) into rows
      from public.crm_records r left join public.crm_records pt on pt.id = r.party_id left join public.crm_users u on u.id = r.owner_id
      where r.kind = 'invoice' and r.deleted_at is null and public.crm_vis(s, r) and public.crm_rdate(r) between fr and t and (uid_ is null or r.owner_id = uid_ or r.assigned_to = uid_) and (st is null or r.status = st) and (pid is null or r.party_id = pid)
        and (q is null or lower(coalesce(r.ref, '') || ' ' || coalesce(pt.title, '')) like '%' || q || '%');
  elsif rep = 'gst_sale' then
    title_ := 'GST sale (rate-wise)'; head := '["Date","Bill no","Customer","GSTIN","GST %","Taxable","GST","Total"]'::jsonb;
    select coalesce(jsonb_agg(jsonb_build_array(d, ref, cust, gstin, rt, tx, gs, tx + gs) order by d, ref, rt), '[]'::jsonb) into rows from (
      select public.crm_rdate(r) d, r.ref, coalesce(pt.title, '') cust, coalesce(pt.data ->> 'gstin', '') gstin, public.crm_num(l -> 'gst') rt,
        round(sum(public.crm_num(l -> 'qty') * public.crm_num(l -> 'price')), 2) tx, round(sum(public.crm_num(l -> 'qty') * public.crm_num(l -> 'price') * public.crm_num(l -> 'gst') / 100), 2) gs
      from public.crm_records r left join public.crm_records pt on pt.id = r.party_id cross join lateral jsonb_array_elements(coalesce(r.data -> 'lines', '[]'::jsonb)) l
      where r.kind = 'invoice' and r.deleted_at is null and r.status <> 'cancelled' and public.crm_vis(s, r) and public.crm_rdate(r) between fr and t and (pid is null or r.party_id = pid) and (q is null or lower(coalesce(r.ref, '') || ' ' || coalesce(pt.title, '')) like '%' || q || '%')
      group by r.id, r.ref, pt.title, pt.data, public.crm_num(l -> 'gst')) z;
  elsif rep = 'collections' then
    title_ := 'Collection (payments mile)'; head := '["Date","Receipt","Customer","Bill","Mode","Amount","Liya"]'::jsonb;
    select coalesce(jsonb_agg(jsonb_build_array(public.crm_pdate(r), r.ref, pt.title, (select i.ref from public.crm_records i where i.id = nullif(r.data ->> 'invoice_id', '')::bigint), coalesce(r.data ->> 'mode', ''), r.amount, coalesce(u.name, 'Company')) order by public.crm_pdate(r), r.id), '[]'::jsonb) into rows
      from public.crm_records r left join public.crm_records pt on pt.id = r.party_id left join public.crm_users u on u.id = r.owner_id
      where r.kind = 'payment' and r.deleted_at is null and public.crm_vis(s, r) and public.crm_pdate(r) between fr and t and (uid_ is null or r.owner_id = uid_) and (st is null or coalesce(r.data ->> 'mode', '') = st) and (pid is null or r.party_id = pid)
        and (q is null or lower(coalesce(r.ref, '') || ' ' || coalesce(pt.title, '')) like '%' || q || '%');
  elsif rep = 'receivable' then
    title_ := 'Lena baaki (aging)'; head := '["Customer","Mobile","Bill no","Bill date","Din","Bill amount","Mila","Baaki","Bucket"]'::jsonb;
    select coalesce(jsonb_agg(jsonb_build_array(cust, mob, ref, d, age, amt, paid, bal, case when age <= 30 then '0-30' when age <= 60 then '31-60' when age <= 90 then '61-90' else '90+' end) order by age desc), '[]'::jsonb) into rows from (
      select coalesce(pt.title, 'Walk-in') cust, pt.mobile mob, r.ref, public.crm_rdate(r) d, public.crm_today() - public.crm_rdate(r) age, r.amount amt, public.crm_num(r.data -> 'paid') paid, r.amount - public.crm_num(r.data -> 'paid') bal
      from public.crm_records r left join public.crm_records pt on pt.id = r.party_id
      where r.kind = 'invoice' and r.deleted_at is null and r.status in ('due', 'partial') and public.crm_vis(s, r) and (uid_ is null or r.owner_id = uid_ or r.assigned_to = uid_) and (pid is null or r.party_id = pid)
        and (q is null or lower(coalesce(r.ref, '') || ' ' || coalesce(pt.title, '')) like '%' || q || '%')) z where bal > 0.004;
  elsif rep = 'purchase' then
    title_ := 'Purchase register'; head := '["Date","PO no","Supplier","Taxable","GST","Total","Diya","Baaki","Status"]'::jsonb;
    select coalesce(jsonb_agg(jsonb_build_array(public.crm_rdate(r), r.ref, pt.title, public.crm_num(r.data -> 'subtotal') - public.crm_num(r.data -> 'discount'), public.crm_num(r.data -> 'gst_total'), r.amount, public.crm_num(r.data -> 'paid'), r.amount - public.crm_num(r.data -> 'paid'), r.status) order by public.crm_rdate(r), r.id), '[]'::jsonb) into rows
      from public.crm_records r left join public.crm_records pt on pt.id = r.party_id
      where r.kind = 'purchase' and r.deleted_at is null and public.crm_vis(s, r) and public.crm_rdate(r) between fr and t and (st is null or r.status = st) and (pid is null or r.party_id = pid) and (q is null or lower(coalesce(r.ref, '') || ' ' || coalesce(pt.title, '')) like '%' || q || '%');
  elsif rep = 'payable' then
    title_ := 'Dena baaki (suppliers)'; head := '["Supplier","Mobile","PO no","PO date","Din","PO amount","Diya","Baaki"]'::jsonb;
    select coalesce(jsonb_agg(jsonb_build_array(cust, mob, ref, d, age, amt, paid, bal) order by age desc), '[]'::jsonb) into rows from (
      select coalesce(pt.title, '?') cust, pt.mobile mob, r.ref, public.crm_rdate(r) d, public.crm_today() - public.crm_rdate(r) age, r.amount amt, public.crm_num(r.data -> 'paid') paid, r.amount - public.crm_num(r.data -> 'paid') bal
      from public.crm_records r left join public.crm_records pt on pt.id = r.party_id where r.kind = 'purchase' and r.deleted_at is null and r.status = 'received' and public.crm_vis(s, r) and (pid is null or r.party_id = pid)
        and (q is null or lower(coalesce(r.ref, '') || ' ' || coalesce(pt.title, '')) like '%' || q || '%')) z where bal > 0.004;
  elsif rep = 'expenses' then
    title_ := 'Kharcha report'; head := '["Date","Category","Vendor","Amount","GST","Mode","Note"]'::jsonb;
    select coalesce(jsonb_agg(jsonb_build_array(e.spent_on, e.category, e.vendor, e.amount, e.gst_amount, e.mode, e.note) order by e.spent_on, e.id), '[]'::jsonb) into rows from public.crm_expenses e
      where e.deleted_at is null and e.spent_on between fr and t and (cat is null or e.category = cat) and (st is null or e.mode = st) and (q is null or lower(e.category || ' ' || e.vendor || ' ' || e.note) like '%' || q || '%');
  elsif rep = 'quotes' then
    title_ := 'Quotation register'; head := '["Date","Quotation no","Title","Customer","Amount","Valid till","Status","Banaya"]'::jsonb;
    select coalesce(jsonb_agg(jsonb_build_array(public.crm_rdate(r), r.ref, coalesce(r.data ->> 'qtitle', ''), pt.title, case when money or r.owner_id = (s).uid then r.amount end, r.data ->> 'valid_till', r.status, coalesce(u.name, 'Company')) order by public.crm_rdate(r), r.id), '[]'::jsonb) into rows
      from public.crm_records r left join public.crm_records pt on pt.id = r.party_id left join public.crm_users u on u.id = r.owner_id
      where r.kind = 'quote' and r.deleted_at is null and public.crm_vis(s, r) and public.crm_rdate(r) between fr and t and (uid_ is null or r.owner_id = uid_ or r.assigned_to = uid_) and (st is null or r.status = st) and (pid is null or r.party_id = pid)
        and (q is null or lower(coalesce(r.ref, '') || ' ' || coalesce(pt.title, '') || ' ' || coalesce(r.data ->> 'qtitle', '')) like '%' || q || '%');
  elsif rep = 'leads' then
    title_ := 'Leads report'; head := '["Date","Lead","Mobile","Source","Status","Owner","Next follow-up"]'::jsonb;
    select coalesce(jsonb_agg(jsonb_build_array(public.crm_rdate(r), r.title, case when public.crm_can(s, 'privacy.see_mobile') then r.mobile else left(coalesce(r.mobile, ''), 2) || 'XXXXXX' || right(coalesce(r.mobile, ''), 2) end, coalesce(r.data ->> 'source', ''), r.status, coalesce(u.name, 'Company'), r.due_at) order by public.crm_rdate(r), r.id), '[]'::jsonb) into rows
      from public.crm_records r left join public.crm_users u on u.id = coalesce(r.assigned_to, r.owner_id)
      where r.kind = 'lead' and r.deleted_at is null and public.crm_vis(s, r) and public.crm_rdate(r) between fr and t and (uid_ is null or r.owner_id = uid_ or r.assigned_to = uid_) and (st is null or r.status = st) and (cat is null or coalesce(r.data ->> 'source', '') = cat)
        and (q is null or lower(r.title || ' ' || coalesce(r.data ->> 'source', '')) like '%' || q || '%');
  elsif rep = 'plants' then
    title_ := 'Plants report'; head := '["Date","Plant","Customer","kW","City","Status","Owner"]'::jsonb;
    select coalesce(jsonb_agg(jsonb_build_array(public.crm_rdate(r), r.title, pt.title, public.crm_num(r.data -> 'kw'), coalesce(r.data ->> 'city', ''), r.status, coalesce(u.name, 'Company')) order by public.crm_rdate(r), r.id), '[]'::jsonb) into rows
      from public.crm_records r left join public.crm_records pt on pt.id = r.party_id left join public.crm_users u on u.id = r.owner_id
      where r.kind = 'plant' and r.deleted_at is null and public.crm_vis(s, r) and public.crm_rdate(r) between fr and t and (uid_ is null or r.owner_id = uid_ or r.assigned_to = uid_) and (st is null or r.status = st) and (q is null or lower(r.title || ' ' || coalesce(pt.title, '')) like '%' || q || '%');
  elsif rep = 'commission' then
    if not (public.crm_can(s, 'earnings.view_all') or public.crm_can(s, 'earnings.manage')) then raise exception 'Aapko is report ki permission nahi hai'; end if;
    title_ := 'Commission report'; head := '["Date","Kisko","Plant / Kaam","Amount","Status"]'::jsonb;
    select coalesce(jsonb_agg(jsonb_build_array(public.crm_rdate(r), coalesce(u.name, '?'), r.title, r.amount, r.status) order by public.crm_rdate(r), r.id), '[]'::jsonb) into rows
      from public.crm_records r left join public.crm_users u on u.id = r.owner_id
      where r.kind = 'earning' and r.deleted_at is null and public.crm_vis(s, r) and public.crm_rdate(r) between fr and t and (uid_ is null or r.owner_id = uid_) and (st is null or r.status = st) and (q is null or lower(r.title) like '%' || q || '%');
  elsif rep = 'stock_value' then
    title_ := 'Stock valuation'; head := '["SKU","Item","Category","Sub-category","Brand","Stock","Unit","Kharid rate","Stock value","Bikri rate"]'::jsonb;
    select coalesce(jsonb_agg(jsonb_build_array(r.data ->> 'sku', r.title, r.data ->> 'category', r.data ->> 'subcategory', r.data ->> 'brand', public.crm_num(r.data -> 'stock'), coalesce(r.data ->> 'unit', 'Nos'),
        case when public.crm_can(s, 'items.cost') then public.crm_num(r.data -> 'cost_price') end, case when public.crm_can(s, 'items.cost') then round(public.crm_num(r.data -> 'stock') * public.crm_num(r.data -> 'cost_price'), 2) end, public.crm_num(r.data -> 'price')) order by r.data ->> 'category', r.title), '[]'::jsonb) into rows
      from public.crm_records r where r.kind = 'item' and r.deleted_at is null and coalesce(r.data ->> 'type', 'product') = 'product' and r.data ? 'stock' and public.crm_vis(s, r) and (cat is null or r.data ->> 'category' = cat)
        and (q is null or lower(r.title || ' ' || coalesce(r.data ->> 'sku', '') || ' ' || coalesce(r.data ->> 'brand', '')) like '%' || q || '%');
  else raise exception 'Report nahi mili';
  end if;
  perform public.crm_log(s, 'view', 'report', 0, 'Report ' || rep || ' ' || fr || '..' || t || ': ' || jsonb_array_length(rows) || ' rows');
  return jsonb_build_object('report', rep, 'title', title_, 'from', fr, 'to', t, 'head', head, 'rows', rows);
end $$;

do $g$
declare f text;
begin
  foreach f in array array['public.crm_dash2(jsonb)', 'public.crm_analytics(jsonb)', 'public.crm_purchase_pay(jsonb)', 'public.crm_receivable(jsonb)', 'public.crm_ledger(jsonb)', 'public.crm_report(jsonb)']
  loop begin execute 'revoke all on function ' || f || ' from public'; execute 'grant execute on function ' || f || ' to anon, authenticated'; exception when others then null; end; end loop;
end $g$;

-- Round 13-5b: Accounts is readable with the new "accounts.view" point (changes still need accounts.manage)




select public.crm_sku_backfill() as skus_assigned;
notify pgrst, 'reload schema';

-- ---- ROUND 13: changed core CRM functions (full redefinitions; safe to re-run) ----
CREATE OR REPLACE FUNCTION public.crm_save(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); k text := p ->> 'kind'; id_ bigint := nullif(p ->> 'id', '')::bigint;
        d jsonb := coalesce(p -> 'data', '{}'::jsonb); old public.crm_records; r public.crm_records; isnew boolean := id_ is null or id_ = 0;
        mob text; em text; ttl text; st text := coalesce(p ->> 'status', ''); asg bigint := nullif(p ->> 'assigned_to', '')::bigint; pid bigint := nullif(p ->> 'party_id', '')::bigint;
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
  em := lower(left(trim(coalesce(d ->> 'email', '')), 160));
  ttl := left(trim(coalesce(d ->> 'name', d ->> 'title', '')), 200);
  owner_ := case when isnew then (s).uid else old.owner_id end;
  if not isnew and pid is null and not (p ? 'party_id') then pid := old.party_id; end if;
  if not isnew and not (p ? 'assigned_to') then asg := old.assigned_to; end if;
  if not isnew and not (p ? 'due_at') then due := old.due_at; end if;

  -- ---------------- per kind rules
  if k = 'party' then
    perform public.crm_need(s, case when isnew then 'customers.create' else 'customers.edit' end);
    if ttl = '' then raise exception 'Customer ka naam likhein'; end if;
    if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein (mobile zaroori hai)'; end if;
    if em <> '' and em !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'Sahi email likhein (ya khali chhodein)'; end if;
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
    if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein (mobile zaroori hai)'; end if;
    if em <> '' and em !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'Sahi email likhein (ya khali chhodein)'; end if;
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
    if pid is null and mob <> '' then select id into pid from public.crm_records where kind = 'party' and mobile = mob and deleted_at is null limit 1; end if;
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

  srch := lower(concat_ws(' ', ttl, ref_, mob, em, d ->> 'city', d ->> 'company', d ->> 'gstin', d ->> 'note', d ->> 'type', d ->> 'brand', d ->> 'qtitle', d ->> 'category', d ->> 'subcategory', d ->> 'sku', d ->> 'mpn', d ->> 'source'));
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
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_status(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_convert(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_list(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_get(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records;
begin
  perform public.crm_quote_expire_daily();
  select * into r from public.crm_records where id = (p ->> 'id')::bigint;
  if not public.crm_vis(s, r) then raise exception 'Record nahi mila'; end if;
  return public.crm_row(s, r);
end $function$
;


-- ============================================================================
-- ROUND 15 (database) — visits/clicks tracking, Admin analytics, colour themes + greeting banner. Safe to re-run.
-- ============================================================================
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

-- Admin may allow old (final) projects to be added to Projects
create or replace function public.crm_project_import(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; allow boolean;
begin
  select coalesce((data -> 'wf' ->> 'allow_old')::boolean, false) into allow from public.crm_settings where id = 1;
  if not (public.crm_is_admin(s) or allow) then raise exception 'Purane project jodne ki permission Admin ne nahi di'; end if;
  select * into q from public.crm_records where id = (p ->> 'id')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if coalesce(q.data ->> 'ctype', '') not in ('Residential', 'Commercial', 'Industrial', 'VFD') then raise exception 'Pehle quotation me Customer type chunein (Residential / Commercial / Industrial / VFD)'; end if;
  perform set_config('sp.wf', '1', true);
  update public.crm_records set data = public.crm_wf_mark(public.crm_wf_mark(public.crm_wf_mark(data || jsonb_build_object('old_project', true), 6, (s).name), 7, (s).name), 3, (s).name), updated_at = now() where id = q.id;
  perform set_config('sp.wf', '', true);
  perform public.crm_log(s, 'workflow', 'quote', q.id, coalesce(q.ref, '') || ' — purana project Projects me joda');
  return jsonb_build_object('ok', true);
end $$;

-- ---------- Leads → Customer list (only after a conversation) ------------------------------------------------------------
create or replace function public.crm_lead_transfer(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); l public.crm_records; pd jsonb := coalesce(p -> 'party', '{}'::jsonb); mob text; ex public.crm_records; pr jsonb; pid bigint; nm text;
begin
  select * into l from public.crm_records where id = (p ->> 'id')::bigint and kind = 'lead' and deleted_at is null;
  if l.id is null or not public.crm_vis(s, l) then raise exception 'Lead nahi mili'; end if;
  if not (public.crm_is_admin(s) or l.owner_id = (s).uid or l.assigned_to = (s).uid) then raise exception 'Sirf is lead ka user ya Admin ise customer list me bhej sakta hai'; end if;
  if jsonb_array_length(coalesce(l.data -> 'log', '[]'::jsonb)) = 0 then raise exception 'Pehle customer se baat karke "Baat-cheet" me remark likhein, phir Customer list me bhejein'; end if;
  mob := public.crm_mobile(coalesce(pd ->> 'mobile', l.mobile, ''));
  if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Customer ka sahi 10 ank ka mobile zaroori hai'; end if;
  nm := trim(coalesce(nullif(pd ->> 'name', ''), nullif(l.data ->> 'name', ''), l.title, ''));
  if nm = '' then raise exception 'Customer ka naam likhein'; end if;
  select * into ex from public.crm_records where kind = 'party' and deleted_at is null and mobile = mob limit 1;
  if ex.id is not null then
    if not public.crm_vis(s, ex) then raise exception 'Ye customer pehle se kisi aur ke paas hai — Admin se transfer karwayein'; end if;
    pid := ex.id;
  else
    pr := public.crm_save(jsonb_build_object('token', p ->> 'token', 'kind', 'party', 'data',
      (pd || jsonb_build_object('name', nm, 'mobile', mob, 'source', coalesce(nullif(pd ->> 'source', ''), l.data ->> 'source', ''), 'lead_id', l.id, 'type', 'customer')), 'assigned_to', l.assigned_to));
    pid := (pr ->> 'id')::bigint;
  end if;
  update public.crm_records set status = 'won', party_id = pid, data = data || jsonb_build_object('transferred_party', pid, 'transferred_at', public.crm_iso_now()), updated_at = now() where id = l.id;
  perform public.crm_log(s, 'lead', 'lead', l.id, 'Customer list me bheja → #' || pid);
  return jsonb_build_object('party_id', pid);
end $$;

-- ---------- inbound leads: website / store enquiry and consumer sign-up become CRM leads (name + mobile mandatory) --------
create or replace function public.crm_inbound_lead(p_name text, p_mobile text, p_source text, p_note text, p_extra jsonb default '{}'::jsonb) returns bigint language plpgsql security definer set search_path = public as $$
declare mob text := public.crm_mobile(coalesce(p_mobile, '')); nm text := left(trim(coalesce(p_name, '')), 120); lid bigint; asg bigint;
begin
  if mob !~ '^[6-9][0-9]{9}$' or nm = '' then return null; end if;
  if exists (select 1 from public.crm_records where kind = 'party' and deleted_at is null and mobile = mob) then return null; end if;
  select id into lid from public.crm_records where kind = 'lead' and deleted_at is null and mobile = mob and status not in ('won', 'lost') order by id limit 1;
  if lid is not null then
    update public.crm_records set data = jsonb_set(data, '{log}', coalesce(data -> 'log', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('t', 'Dobara sampark: ' || coalesce(p_source, '') || case when coalesce(p_note, '') <> '' then ' — ' || left(p_note, 300) else '' end, 'at', public.crm_iso_now(), 'by', 'System')), true), updated_at = now() where id = lid;
    return lid;
  end if;
  select nullif(data #>> '{blueprint,assign_to}', '')::bigint into asg from public.crm_settings where id = 1;
  insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, due_at, data, search, created_by)
    values ('lead', nm, mob, 'new', 0, asg, public.crm_today(), jsonb_build_object('name', nm, 'mobile', mob, 'source', coalesce(p_source, 'Website'), 'note', left(coalesce(p_note, ''), 500), 'company', true, 'intake', 'inbound') || coalesce(p_extra, '{}'::jsonb), lower(nm || ' ' || mob), 0)
    returning id into lid;
  return lid;
end $$;

create or replace function public.crm_enq_lead_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare dd jsonb := coalesce(new.data, '{}'::jsonb); src text; intr text; hint text;
begin
  begin
    src := coalesce(public.crm_channel_name(dd ->> 'channel'), case when coalesce(dd ->> 'source', '') = 'website' then 'Website' else 'Online Store' end);
    intr := left(trim(concat_ws(' ', nullif(dd ->> 'subject', ''), nullif(dd ->> 'type', ''), nullif(dd ->> 'product', ''))), 200);
    hint := case when lower(concat_ws(' ', dd ->> 'subject', dd ->> 'type')) ~ '(clean|maintenance|amc|repair|shift|audit|service|error)' then 'service'
                 when lower(concat_ws(' ', dd ->> 'subject', dd ->> 'type', dd ->> 'product')) ~ '(shop|product|buy|order|inverter|panel|battery|cable|structure)' then 'product' else 'project' end;
    perform public.crm_inbound_lead(coalesce(dd ->> 'name', ''), coalesce(dd ->> 'phone', dd ->> 'mobile', ''), src,
      coalesce(dd ->> 'subject', dd ->> 'type', '') || ' ' || coalesce(dd ->> 'message', ''),
      jsonb_strip_nulls(jsonb_build_object('enquiry_id', new.id, 'email', nullif(dd ->> 'email', ''), 'city', nullif(dd ->> 'city', ''), 'address', nullif(dd ->> 'address', ''), 'pincode', nullif(dd ->> 'pincode', ''),
        'kw', nullif(dd ->> 'kw', ''), 'bill', nullif(dd ->> 'bill', ''), 'interest', nullif(intr, ''), 'kind_hint', hint, 'channel', nullif(dd ->> 'channel', ''))));
  exception when others then null; end;
  return new;
end $$;
do $$ begin
  if to_regclass('public.sp_enquiries') is not null then
    drop trigger if exists crm_enq_lead on public.sp_enquiries;
    create trigger crm_enq_lead after insert on public.sp_enquiries for each row execute function public.crm_enq_lead_trg();
  end if;
end $$;

create or replace function public.crm_signup_lead_trg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.role = 'consumer' then begin perform public.crm_inbound_lead(new.name, new.mobile, 'Online Store', 'Online Store par signup kiya', jsonb_build_object('signup_uid', new.id)); exception when others then null; end; end if;
  return new;
end $$;
drop trigger if exists crm_signup_lead on public.crm_users;
create trigger crm_signup_lead after insert on public.crm_users for each row execute function public.crm_signup_lead_trg();

grant execute on function public.crm_wf_get(jsonb), public.crm_wf_set(jsonb), public.crm_wf_perm(jsonb), public.crm_projects(jsonb), public.crm_project_import(jsonb), public.crm_lead_transfer(jsonb) to anon, authenticated;

-- ---------- Documents & Gallery → send a stamped copy to a customer's plant (Plant ID = quotation number) ------------------
create or replace function public.crm_doc_share(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; b bytea; r public.crm_records; nm text := left(trim(coalesce(p ->> 'name', 'file')), 160); note text := left(trim(coalesce(p ->> 'note', '')), 300);
begin
  if not (public.crm_can(s, 'docs.view') or public.crm_can(s, 'docs.upload')) then raise exception 'Aapko documents bhejne ki permission nahi hai'; end if;
  select * into q from public.crm_records where id = (p ->> 'quote_id')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  begin b := decode(coalesce(p ->> 'b64', ''), 'base64'); exception when others then raise exception 'File padh nahi paye'; end;
  if octet_length(b) = 0 then raise exception 'File khaali hai'; end if;
  if octet_length(b) > 3 * 1024 * 1024 then raise exception 'File 3 MB se badi hai'; end if;
  insert into public.crm_records(kind, title, status, owner_id, party_id, data, search, created_by)
  values ('doc', nm, 'ok', (s).uid, q.party_id,
    jsonb_build_object('mime', left(coalesce(p ->> 'mime', 'application/octet-stream'), 80), 'size', octet_length(b), 'note', note, 'attach_kind', 'party', 'attach_id', q.party_id::text,
      'shared_quote', q.id, 'shared_ref', q.ref, 'shared_at', public.crm_iso_now(), 'shared_by', (s).name, 'stamped', coalesce((p ->> 'stamped')::boolean, false)),
    lower(nm || ' ' || coalesce(q.ref, '')), (s).uid) returning * into r;
  insert into public.crm_files(rec_id, mime, size, data) values (r.id, left(coalesce(p ->> 'mime', 'application/octet-stream'), 80), octet_length(b), b);
  perform public.crm_log(s, 'share', 'doc', r.id, 'Customer ko bheja: ' || nm || ' → ' || coalesce(q.ref, ''));
  return public.crm_row(s, r);
end $$;
grant execute on function public.crm_doc_share(jsonb) to anon, authenticated;

-- =====================================================================
-- Customer "My Plant": a logged-in customer links Plant IDs (= confirmed quotation numbers) that belong to THEIR OWN mobile.
-- Nothing else is exposed: only the whitelist below (no cost, margin, notes, other customers).
-- =====================================================================
create table if not exists public.crm_consumer_plants (user_id bigint not null, quote_id bigint not null, linked_at timestamptz not null default now(), primary key (user_id, quote_id));
create table if not exists public.crm_plant_try (id bigserial primary key, user_id bigint not null, at timestamptz not null default now());
alter table public.crm_consumer_plants enable row level security; alter table public.crm_plant_try enable row level security;
revoke all on public.crm_consumer_plants, public.crm_plant_try from anon, authenticated;

-- the quotation must (a) exist, (b) be confirmed, (c) belong to a customer whose mobile equals the logged-in mobile
create or replace function public.crm_plant_owned(u public.crm_users, q public.crm_records) returns boolean language sql stable security definer set search_path = public as $$
  select q.id is not null and q.kind = 'quote' and q.deleted_at is null and q.status in ('accepted', 'converted')
     and exists (select 1 from public.crm_records pt where pt.id = q.party_id and pt.kind = 'party' and pt.deleted_at is null and pt.mobile = u.mobile and u.mobile ~ '^[6-9][0-9]{9}$') $$;

create or replace function public.crm_plant_card(q public.crm_records) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare pt public.crm_records; inv public.crm_records; w jsonb := coalesce(q.data -> 'wf', '{}'::jsonb); nxt date; lastd text; visits jsonb; pay jsonb; docs jsonb; names text[] := public.crm_wf_names(); i int; tl jsonb := '[]'::jsonb;
        instd text;
begin
  select * into pt from public.crm_records where id = q.party_id;
  select * into inv from public.crm_records where id = nullif(q.data ->> 'invoice_id', '')::bigint and kind = 'invoice' and deleted_at is null;
  select min(due_at) into nxt from public.crm_records where kind = 'reminder' and deleted_at is null and party_id = q.party_id and data ->> 'maint' = 'true' and status <> 'done';
  select max(coalesce(data ->> 'done_on', due_at::text)) into lastd from public.crm_records where kind = 'reminder' and deleted_at is null and party_id = q.party_id and data ->> 'maint' = 'true' and status = 'done';
  select coalesce(jsonb_agg(jsonb_build_object('visit', data ->> 'visit_no', 'plan', data ->> 'plan', 'due', due_at, 'done', status = 'done', 'done_on', data ->> 'done_on') order by due_at), '[]'::jsonb) into visits
    from public.crm_records where kind = 'reminder' and deleted_at is null and party_id = q.party_id and data ->> 'maint' = 'true';
  if inv.id is null then pay := jsonb_build_object('state', 'waiting');
  elsif coalesce((inv.data ->> 'balance')::numeric, inv.amount) <= 0.009 then pay := jsonb_build_object('state', 'paid', 'amount', inv.amount, 'bill', inv.ref);
  else pay := jsonb_build_object('state', 'due', 'amount', inv.amount, 'paid', coalesce((inv.data ->> 'paid')::numeric, 0), 'balance', coalesce((inv.data ->> 'balance')::numeric, inv.amount), 'due_date', coalesce(nullif(inv.data ->> 'due_date', ''), inv.due_at::text), 'bill', inv.ref); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'name', d.title, 'mime', d.data ->> 'mime', 'size', d.data -> 'size', 'at', d.data ->> 'shared_at', 'note', d.data ->> 'note') order by d.id desc), '[]'::jsonb) into docs
    from public.crm_records d where d.kind = 'doc' and d.deleted_at is null and (d.data ->> 'shared_quote') = q.id::text;
  foreach i in array public.crm_wf_flow_of(q) loop
    continue when i = 19;
    tl := tl || jsonb_build_array(jsonb_build_object('n', i, 'name', names[i], 'done', w ? i::text, 'at', w -> i::text ->> 'at'));
  end loop;
  instd := coalesce(w -> '10' ->> 'at', w -> '9' ->> 'at');
  return jsonb_build_object('id', q.id, 'plant_id', q.ref, 'customer', pt.title, 'ctype', q.data ->> 'ctype', 'kw', nullif(q.data ->> 'kw', ''), 'title', coalesce(q.data ->> 'qtitle', q.title),
    'install_date', left(instd, 10), 'installed', instd is not null, 'confirmed_at', w -> '6' ->> 'at',
    'maintenance', jsonb_build_object('next_due', nxt, 'last_done', lastd, 'visits', visits),
    'payment', pay, 'bill_ref', inv.ref, 'has_bill', inv.id is not null, 'files', docs, 'timeline', tl, 'finished', w ? '12', 'subsidy_done', w ? '13');
end $$;

create or replace function public.crm_consumer_link_plant(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); pid text := upper(regexp_replace(coalesce(p ->> 'plant_id', ''), '\s', '', 'g')); q public.crm_records;
begin
  if length(pid) < 4 or length(pid) > 40 then raise exception 'Plant ID likhein (jaise QT/...)'; end if;
  if (select count(*) from public.crm_plant_try where user_id = u.id and at > now() - interval '15 minutes') >= 8 then raise exception 'Bahut zyada koshish — 15 minute baad phir try karein'; end if;
  select * into q from public.crm_records where kind = 'quote' and deleted_at is null and upper(regexp_replace(coalesce(ref, ''), '\s', '', 'g')) = pid limit 1;
  if q.id is null or not public.crm_plant_owned(u, q) then
    insert into public.crm_plant_try(user_id) values (u.id);    -- returned (not raised) so the attempt is really stored
    return jsonb_build_object('error', 'Ye Plant ID aapke mobile number se juda nahi hai ya abhi confirm nahi hui. Sunpowers se sampark karein.');
  end if;
  insert into public.crm_consumer_plants(user_id, quote_id) values (u.id, q.id) on conflict do nothing;
  return public.crm_plant_card(q);
end $$;


create or replace function public.crm_consumer_plants(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token');
begin
  return coalesce((select jsonb_agg(public.crm_plant_card(q) order by cp.linked_at) from public.crm_consumer_plants cp join public.crm_records q on q.id = cp.quote_id
    where cp.user_id = u.id and public.crm_plant_owned(u, q)), '[]'::jsonb);
end $$;

-- printable data for the customer's own quotation / bill / maintenance summary (whitelisted fields only)
create or replace function public.crm_consumer_plant_doc(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); q public.crm_records; dk text := coalesce(p ->> 'kind', 'quotation'); src public.crm_records; pt public.crm_records; co jsonb; pays jsonb;
begin
  select q2.* into q from public.crm_records q2 join public.crm_consumer_plants cp on cp.quote_id = q2.id and cp.user_id = u.id where q2.id = nullif(p ->> 'id', '')::bigint;
  if q.id is null or not public.crm_plant_owned(u, q) then raise exception 'Plant nahi mila'; end if;
  select * into pt from public.crm_records where id = q.party_id;
  select data -> 'company' into co from public.crm_settings where id = 1;
  if dk = 'bill' then
    select * into src from public.crm_records where id = nullif(q.data ->> 'invoice_id', '')::bigint and kind = 'invoice' and deleted_at is null;
    if src.id is null then raise exception 'Bill abhi nahi bana'; end if;
    select coalesce(jsonb_agg(jsonb_build_object('date', py.due_at, 'amount', py.amount, 'mode', py.data ->> 'mode') order by py.due_at), '[]'::jsonb) into pays from public.crm_records py where py.kind = 'payment' and py.deleted_at is null and py.data ->> 'invoice_id' = src.id::text;
  else src := q; pays := '[]'::jsonb; end if;
  return jsonb_build_object('kind', dk, 'ref', src.ref, 'date', src.data ->> 'date', 'valid_till', case when dk = 'quotation' then src.data ->> 'valid_till' end, 'title', src.data ->> 'qtitle',
    'customer', jsonb_build_object('name', pt.title, 'mobile', pt.mobile, 'address', pt.data ->> 'address', 'city', pt.data ->> 'city', 'gstin', pt.data ->> 'gstin'),
    'company', jsonb_build_object('name', co ->> 'name', 'legal', co ->> 'legal', 'gstin', co ->> 'gstin', 'phone', co ->> 'phone', 'address', co ->> 'address'),
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('name', l ->> 'name', 'qty', l -> 'qty', 'price', l -> 'price', 'gst', l -> 'gst', 'hsn', l ->> 'hsn')), '[]'::jsonb) from jsonb_array_elements(coalesce(src.data -> 'lines', '[]'::jsonb)) l),
    'subtotal', src.data -> 'subtotal', 'gst_total', src.data -> 'gst_total', 'discount', src.data -> 'discount', 'grand', src.amount, 'paid', src.data -> 'paid', 'balance', src.data -> 'balance', 'payments', pays,
    'notes', src.data ->> 'notes', 'maintenance', public.crm_plant_card(q) -> 'maintenance');
end $$;

create or replace function public.crm_consumer_file(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); d public.crm_records; q public.crm_records; f public.crm_files;
begin
  select * into d from public.crm_records where id = nullif(p ->> 'id', '')::bigint and kind = 'doc' and deleted_at is null and data ? 'shared_quote';
  if d.id is null then raise exception 'File nahi mili'; end if;
  select q2.* into q from public.crm_records q2 join public.crm_consumer_plants cp on cp.quote_id = q2.id and cp.user_id = u.id where q2.id = (d.data ->> 'shared_quote')::bigint;
  if q.id is null or not public.crm_plant_owned(u, q) then raise exception 'File nahi mili'; end if;
  select * into f from public.crm_files where rec_id = d.id limit 1;
  if f.id is null then raise exception 'File nahi mili'; end if;
  return jsonb_build_object('name', d.title, 'mime', f.mime, 'b64', encode(f.data, 'base64'));
end $$;
grant execute on function public.crm_consumer_link_plant(jsonb), public.crm_consumer_plants(jsonb), public.crm_consumer_plant_doc(jsonb), public.crm_consumer_file(jsonb) to anon, authenticated;

-- ---------- blueprint tool: reuse the sign-up lead of the same person (one person = one lead) ----------

-- (Round 17 fix) Tools (Blueprint / Error Detector): if this person already has a lead from signing up, use THAT lead (one person = one lead)
grant execute on function public.sp_tool_use(jsonb) to anon, authenticated;


-- =====================================================================================================
-- ROUND 21 — Customer kinds (Project / Product, B2C / B2B) + 18-step flow
--   * Step keys 1..13 are UNCHANGED (live data stays valid). New keys: 14 Send Demo/Files, 15 Loan/Finance,
--     16 Suggest/Referral, 17 AMC/Maintenance, 18 Complaint Status, 19 Leads (computed, never stored).
--   * What a customer sees is decided by crm_wf_flow(): Project customer = full flow, Product customer = short flow.
--   * Safe to run more than once (create or replace only; no data is deleted or rewritten here).
-- =====================================================================================================

-- ---------- step names, indexed by step key ----------

-- ---------- which steps (in which order) a customer type sees. 6 (Confirmation) is internal and never shown ----------
create or replace function public.crm_wf_flow(ct text) returns int[] language sql immutable as $$
  select case
    when ct = 'Items only'  then array[19,1,2,14,3,12,16,18]                               -- Product customer
    when ct = 'Service'     then array[19,1,2,3,4,12,17,16,18]                             -- Service customer (cleaning, AMC, repair, shifting, audit)
    when ct = 'Residential' then array[19,1,2,14,3,4,5,7,15,8,9,10,11,12,13,16,17,18]      -- Project, subsidy applies
    else                         array[19,1,2,14,3,4,5,7,15,8,9,10,11,12,16,17,18] end $$;  -- Project (Commercial / Industrial / VFD / not chosen yet)

create or replace function public.crm_wf_flow_of(q public.crm_records) returns int[] language plpgsql stable security definer set search_path = public as $$
declare ct text := coalesce(q.data ->> 'ctype', ''); ck text;
begin
  if ct = '' and q.party_id is not null then
    select data ->> 'cust_kind' into ck from public.crm_records where id = q.party_id;
    if ck = 'product' then ct := 'Items only'; elsif ck = 'service' then ct := 'Service'; end if;
  end if;
  return public.crm_wf_flow(ct);
end $$;

-- ---------- details collected at each step (server whitelist; the CRM screen draws the same fields) ----------
-- req = mandatory when the step is completed from the new screen (old screens send no "info", so they are not blocked)
create or replace function public.crm_wf_fields() returns jsonb language sql immutable as $$
  select '{
   "4":  [{"k":"roof_type","l":"Chhat ka prakar"},{"k":"roof_area","l":"Chhat ka area (sq ft)"},{"k":"shadow","l":"Chhaya / shadow"},{"k":"phase","l":"Connection (1 / 3 phase)"},{"k":"structure_ht","l":"Structure ki height (ft)"}],
   "5":  [{"k":"kw_final","l":"Final plant size (kW)"},{"k":"panels","l":"Panels (sankhya)"}],
   "7":  [{"k":"discom","l":"DISCOM","req":true},{"k":"consumer_no","l":"Consumer number","req":true},{"k":"sanctioned_load","l":"Sanctioned load (kW)"},{"k":"category","l":"Category (LMV-1 etc.)"},{"k":"portal_app_no","l":"Portal application no."},{"k":"apply_date","l":"Apply ki tareekh"}],
   "8":  [{"k":"tech_name","l":"Technician ka naam","req":true},{"k":"tech_mobile","l":"Technician ka mobile"},{"k":"handover_date","l":"Hand over ki tareekh"}],
   "9":  [{"k":"start_date","l":"Installation shuru hui"},{"k":"team_size","l":"Team (log)"}],
   "10": [{"k":"inverter_sn","l":"Inverter serial no."},{"k":"panel_count","l":"Panels (sankhya)"},{"k":"jcr","l":"Joint Commissioning Report"},{"k":"comm_date","l":"Commissioning ki tareekh"}],
   "11": [{"k":"nm_app_no","l":"Net metering application no."},{"k":"meter_no","l":"Meter number"},{"k":"meter_date","l":"Meter lagne ki tareekh"},{"k":"discom_je","l":"DISCOM JE / contact"}],
   "13": [{"k":"sub_app_no","l":"Subsidy application no."},{"k":"sub_amount","l":"Subsidy amount (Rs)"},{"k":"sub_status","l":"Subsidy status"}],
   "14": [{"k":"sent_what","l":"Kya bheja (demo / datasheet / photo)"},{"k":"sent_mode","l":"Kaise bheja (WhatsApp / Email / Milkar)"}],
   "15": [{"k":"pay_mode","l":"Payment tarika (Cash / Loan / Mixed)","req":true},{"k":"bank","l":"Bank"},{"k":"loan_amount","l":"Loan amount (Rs)"},{"k":"loan_status","l":"Loan status"},{"k":"loan_ref","l":"Loan reference no."}],
   "16": [{"k":"ref_name","l":"Refer kiya (naam)"},{"k":"ref_mobile","l":"Refer kiya (mobile)"}],
   "17": [{"k":"amc_plan","l":"AMC / maintenance plan"},{"k":"amc_start","l":"Shuru ki tareekh"}],
   "18": [{"k":"c_status","l":"Complaint status (None / Open / In progress / Resolved)"},{"k":"c_issue","l":"Samasya"},{"k":"c_ticket","l":"Ticket / complaint no."},{"k":"c_handler","l":"Kisne sambhali (Installer / Dealer / Manufacturer)"},{"k":"c_brand","l":"Brand / product"},{"k":"c_serial","l":"Serial number"},{"k":"c_date","l":"Complaint ki tareekh"}]
  }'::jsonb $$;

-- steps that cannot be ticked by hand (they come from the quotation, the bill, or the lead itself)
create or replace function public.crm_wf_is_auto(n int) returns boolean language sql immutable as $$ select n in (1, 2, 3, 6, 12, 19) $$;
-- steps that may be marked "Lagu nahi" (not applicable for this customer)
create or replace function public.crm_wf_can_skip(n int) returns boolean language sql immutable as $$ select n in (4, 5, 11, 13, 14, 15, 16, 17, 18) $$;

-- marks a step on a quotation by the system (never overwrites, never leaves the bypass flag on)
create or replace function public.crm_wf_auto_q(p_qid bigint, n int, p_by text) returns void language plpgsql security definer set search_path = public as $$
declare q public.crm_records; prev text := coalesce(current_setting('sp.wf', true), '');
begin
  select * into q from public.crm_records where id = p_qid and kind = 'quote' and deleted_at is null;
  if q.id is null or not (n = any (public.crm_wf_flow_of(q))) or (q.data -> 'wf') ? n::text then return; end if;
  perform set_config('sp.wf', '1', true);
  update public.crm_records set data = public.crm_wf_mark(data, n, p_by), updated_at = now() where id = q.id;
  perform set_config('sp.wf', prev, true);
end $$;

-- same, for the customer's latest live quotation
create or replace function public.crm_wf_auto_p(p_party bigint, n int, p_by text) returns void language plpgsql security definer set search_path = public as $$
declare qid bigint;
begin
  if p_party is null then return; end if;
  select id into qid from public.crm_records where kind = 'quote' and deleted_at is null and party_id = p_party and status not in ('rejected', 'expired') order by id desc limit 1;
  if qid is not null then perform public.crm_wf_auto_q(qid, n, p_by); end if;
end $$;

-- ---------- rules on every write (same trigger as before + party checks, project upgrade, auto steps) ----------

drop trigger if exists crm_rules on public.crm_records;
create trigger crm_rules before insert or update on public.crm_records for each row execute function public.crm_rules_trg();

-- ---------- the steps one customer / quotation shows, in flow order ----------

-- the workflow of one quotation (or of a customer who has no quotation yet)

-- confirm / skip / undo one manual step (with its details)

-- Admin: who can see / change which step (names now cover all 19 keys; the screen shows them in flow order)

-- Projects list: progress counts the steps this customer actually has

-- the customer's own "My Plant" tracker (Store / Website): same names and flow, without the internal Leads step

grant execute on function public.crm_wf_get(jsonb), public.crm_wf_set(jsonb), public.crm_wf_perm(jsonb), public.crm_projects(jsonb) to anon, authenticated;

-- ---------- one-time backfill: existing customers that already have a quotation get their kind (adds one key, changes nothing else) ----------
--   project quotation (Residential / Commercial / Industrial / VFD) => 'project'; only "Items only" quotations => 'product'.
--   Customers without any quotation stay unset (the CRM shows "Set nahi" until you choose). Running it again changes nothing.
update public.crm_records p set data = p.data || jsonb_build_object('cust_kind',
    case when exists (select 1 from public.crm_records q where q.kind = 'quote' and q.deleted_at is null and q.party_id = p.id and coalesce(q.data ->> 'ctype', '') in ('Residential', 'Commercial', 'Industrial', 'VFD'))
         then 'project' else 'product' end)
  where p.kind = 'party' and p.deleted_at is null and coalesce(p.data ->> 'cust_kind', '') = ''
    and exists (select 1 from public.crm_records q where q.kind = 'quote' and q.deleted_at is null and q.party_id = p.id and coalesce(q.data ->> 'ctype', '') <> '');

-- ======================================================================================================
-- ROUND 21b — Mobile number is mandatory EVERYWHERE (email is optional and never enough on its own),
--             every lead / customer carries its PATH (source), and a "Service" customer type.
-- ======================================================================================================

-- Lead -> Customer: mobile mandatory; the details come from the customer form (the trigger checks them)

-- name of an ad / marketing channel from its code (Settings → Marketing → channels)
create or replace function public.crm_channel_name(p_code text) returns text language sql stable security definer set search_path = public as $$
  select c ->> 'name' from public.crm_settings s, jsonb_array_elements(coalesce(s.data #> '{marketing,channels}', '[]'::jsonb)) c
   where s.id = 1 and coalesce(p_code, '') <> '' and upper(coalesce(c ->> 'code', '')) = upper(p_code) and coalesce(c ->> 'name', '') <> '' limit 1 $$;

-- Website / Store enquiry -> Lead.  Path (source) is filled by itself: ad channel > Website > Online Store; what he asked for travels along

-- Online Store order: the buyer is a PRODUCT / B2C customer when the order carries everything a customer needs (name, mobile, address, city, pincode);
-- otherwise he enters Leads (path "Online Store") and is made a customer by staff.  Either way a lead with its path exists.
create or replace function public.crm_order_customer(p_data jsonb, p_oid bigint) returns bigint language plpgsql security definer set search_path = public as $$
declare mob text := public.crm_mobile(coalesce(p_data ->> 'phone', p_data ->> 'mobile', '')); nm text := left(trim(coalesce(p_data ->> 'name', '')), 120); pid bigint; items text; ad text := trim(coalesce(p_data ->> 'address', ''));
        ct text := trim(coalesce(p_data ->> 'city', '')); pin text := regexp_replace(coalesce(p_data ->> 'pincode', ''), '\D', '', 'g');
begin
  if mob !~ '^[6-9][0-9]{9}$' or nm = '' then return null; end if;
  select id into pid from public.crm_records where kind = 'party' and deleted_at is null and mobile = mob order by id limit 1;
  if pid is not null then return pid; end if;
  if ad = '' or ct = '' or pin !~ '^[0-9]{6}$' then
    perform public.crm_inbound_lead(nm, mob, 'Online Store', 'Store order #' || p_oid, jsonb_strip_nulls(jsonb_build_object('email', nullif(p_data ->> 'email', ''), 'city', nullif(ct, ''), 'address', nullif(ad, ''), 'order_id', p_oid, 'kind_hint', 'product')));
    return null;
  end if;
  select left(string_agg(coalesce(i ->> 'title', ''), ', '), 180) into items from jsonb_array_elements(case when jsonb_typeof(p_data -> 'items') = 'array' then p_data -> 'items' else '[]'::jsonb end) i;
  insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, due_at, data, search, created_by)
    values ('party', nm, mob, 'active', 0, null, null,
      jsonb_strip_nulls(jsonb_build_object('name', nm, 'mobile', mob, 'email', nullif(lower(trim(coalesce(p_data ->> 'email', ''))), ''), 'address', ad, 'city', ct, 'pincode', pin, 'type', 'customer', 'source', 'Online Store',
        'cust_kind', 'product', 'segment', 'b2c', 'interest', coalesce(nullif(items, ''), 'Online Store order'), 'store_order_id', p_oid, 'intake', 'store')),
      lower(concat_ws(' ', nm, mob, ct)), 0)
    returning id into pid;
  return pid;
end $$;

-- every customer added directly (no lead behind it) gets a lead record with the same path, so Leads really is "all enquiries from everywhere"
create or replace function public.crm_party_lead_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare lid bigint; src text;
begin
  if new.kind <> 'party' or new.deleted_at is not null or coalesce(new.data ->> 'type', 'customer') = 'supplier' or (new.data ? 'lead_id') or coalesce(new.mobile, '') = '' then return new; end if;
  begin
    src := coalesce(nullif(trim(new.data ->> 'source'), ''), 'Purana / Unknown');
    select id into lid from public.crm_records where kind = 'lead' and deleted_at is null and mobile = new.mobile and status not in ('won', 'lost') order by id limit 1;
    if lid is not null then
      update public.crm_records set status = 'won', party_id = new.id, data = data || jsonb_build_object('transferred_party', new.id, 'transferred_at', public.crm_iso_now()), updated_at = now() where id = lid;
    else
      insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, due_at, party_id, data, search, created_by)
        values ('lead', new.title, new.mobile, 'won', coalesce(new.owner_id, 0), new.assigned_to, null, new.id,
          jsonb_build_object('name', new.title, 'mobile', new.mobile, 'source', src, 'city', coalesce(new.data ->> 'city', ''), 'intake', 'customer-add', 'transferred_party', new.id, 'transferred_at', public.crm_iso_now()),
          lower(concat_ws(' ', new.title, new.mobile)), 0);
    end if;
  exception when others then null; end;
  return new;
end $$;
drop trigger if exists crm_party_lead on public.crm_records;
create trigger crm_party_lead after insert on public.crm_records for each row when (new.kind = 'party') execute function public.crm_party_lead_trg();

create or replace function public.crm_order_customer_trg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin perform public.crm_order_customer(new.data, new.id); exception when others then null; end;
  return new;
end $$;

-- old store orders: buyers that are not in the CRM yet (complete ones become customers, the rest become leads)
do $$ begin
  if to_regclass('public.sp_orders') is not null then
    drop trigger if exists crm_order_customer on public.sp_orders;
    create trigger crm_order_customer after insert on public.sp_orders for each row execute function public.crm_order_customer_trg();
    perform public.crm_order_customer(o.data, o.id) from public.sp_orders o;
  end if;
end $$;

-- ================================================================= Round 22 cleanup: old, never-used functions are removed from live databases too
drop function if exists public.crm_register(jsonb);
drop function if exists public.crm_questions(jsonb);
drop function if exists public.crm_reset(jsonb);
drop function if exists public.crm_err(text);
drop function if exists public.crm_consumer_unlink_plant(jsonb);
drop function if exists public.sp_admin_pending_payments(text);

-- ================================================================= Round 22: Store App "Create ID with PIN" (mobile + PIN, no OTP) + small profile photo
-- A customer can create an ID with name + mobile + 4-digit PIN (optional photo, compressed to ~5 KB on the phone) and log in later with mobile + PIN.
-- Because the mobile is not verified by OTP, such an account sees only the orders placed under its OWN ID (not old orders that only share the mobile number).
create or replace function public.sp_cust_signup(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare m text := public.crm_mobile(p ->> 'mobile'); nm text := left(trim(coalesce(p ->> 'name', '')), 80); pin text := coalesce(p ->> 'pin', ''); av text := coalesce(p ->> 'avatar', '');
        ex public.crm_users; u public.crm_users; un text; recent int;
begin
  if nm = '' then raise exception 'Naam likhein'; end if;
  if m !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein'; end if;
  perform public.crm_auth_pin_valid(jsonb_build_object('pin_len', 4), pin);
  if av <> '' and (av !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' or length(av) > 9000) then av := ''; end if;
  select count(*) into recent from public.crm_activity where action = 'register' and role = 'consumer' and at > now() - interval '1 hour';
  if recent >= 60 then raise exception 'Abhi bahut ID ban rahi hain — thodi der baad koshish karein'; end if;
  select * into ex from public.crm_users where role = 'consumer' and mobile = m order by id limit 1;
  if ex.id is not null and (ex.pin_hash <> '' or ex.email_ok or coalesce(ex.pass_hash, '') <> '') then
    raise exception 'Is mobile se ID pehle se bani hai — "Login with PIN" dabayein'; end if;
  if ex.id is null then
    un := m;
    while exists (select 1 from public.crm_users where username = un) loop un := un || floor(random() * 10)::int::text; end loop;
    insert into public.crm_users(role, username, name, mobile, email, pass_hash, status, pin_hash, meta)
    values ('consumer', un, nm, m, '', '', 'active', crypt(pin, gen_salt('bf')), jsonb_build_object('mob_ok', false, 'quick', true) || case when av <> '' then jsonb_build_object('avatar', av) else '{}'::jsonb end)
    returning * into u;
    insert into public.crm_activity(user_id, user_name, role, action, summary) values (u.id, nm, 'consumer', 'register', 'Nayi ID (PIN): ' || m);
  else
    update public.crm_users set name = nm, pin_hash = crypt(pin, gen_salt('bf')), pin_fail = 0, status = case when status = 'blocked' then status else 'active' end,
      meta = coalesce(meta, '{}'::jsonb) || jsonb_build_object('mob_ok', false, 'quick', true) || case when av <> '' then jsonb_build_object('avatar', av) else '{}'::jsonb end
    where id = ex.id returning * into u;
  end if;
  if u.status = 'blocked' then raise exception 'Ye ID band hai — Admin se sampark karein'; end if;
  return public.crm_auth_session(jsonb_build_object('uid', u.id, 'name', u.name, 'role', 'consumer', 'status', 'active', 'has_q', false, 'dev_name', p ->> 'dev_name'), p ->> 'device', 'store');
end $$;

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


-- STORE-IMAGES-APPLY.sql — Store App + Website Shop me placeholder (illustration) images lagata hai. SIRF KHALI image wali jagah par lagta hai; jahan aapne real photo daali hai wahan kuch nahi badalta.
-- Safe to re-run. Supabase -> SQL Editor me chalayein (MASTER-UPDATE ke baad).
do $do$
declare m jsonb := $j${"p":{"p_pnl_1":"/img/p/p_pnl_1.webp","p_pnl_2":"/img/p/p_pnl_2.webp","p_pnl_3":"/img/p/p_pnl_3.webp","p_pnl_4":"/img/p/p_pnl_4.webp","p_pnl_5":"/img/p/p_pnl_5.webp","p_pnl_6":"/img/p/p_pnl_6.webp","p_pnl_7":"/img/p/p_pnl_7.webp","p_pnl_8":"/img/p/p_pnl_8.webp","p_pnl_9":"/img/p/p_pnl_9.webp","p_pnl_10":"/img/p/p_pnl_10.webp","p_pnl_11":"/img/p/p_pnl_11.webp","p_pnl_12":"/img/p/p_pnl_12.webp","p_pnl_13":"/img/p/p_pnl_13.webp","p_pnl_14":"/img/p/p_pnl_14.webp","p_pnl_15":"/img/p/p_pnl_15.webp","p_pnl_16":"/img/p/p_pnl_16.webp","p_pnl_17":"/img/p/p_pnl_17.webp","p_pnl_18":"/img/p/p_pnl_18.webp","p_pnl_19":"/img/p/p_pnl_19.webp","p_pnl_20":"/img/p/p_pnl_20.webp","p_pnl_21":"/img/p/p_pnl_21.webp","p_pnl_22":"/img/p/p_pnl_22.webp","p_inv_23":"/img/p/p_inv_23.webp","p_inv_24":"/img/p/p_inv_24.webp","p_inv_25":"/img/p/p_inv_25.webp","p_inv_26":"/img/p/p_inv_26.webp","p_inv_27":"/img/p/p_inv_27.webp","p_inv_28":"/img/p/p_inv_28.webp","p_inv_29":"/img/p/p_inv_29.webp","p_inv_30":"/img/p/p_inv_30.webp","p_inv_31":"/img/p/p_inv_31.webp","p_inv_32":"/img/p/p_inv_32.webp","p_inv_33":"/img/p/p_inv_33.webp","p_inv_34":"/img/p/p_inv_34.webp","p_inv_35":"/img/p/p_inv_35.webp","p_inv_36":"/img/p/p_inv_36.webp","p_inv_37":"/img/p/p_inv_37.webp","p_inv_38":"/img/p/p_inv_38.webp","p_inv_39":"/img/p/p_inv_39.webp","p_inv_40":"/img/p/p_inv_40.webp","p_inv_41":"/img/p/p_inv_41.webp","p_inv_42":"/img/p/p_inv_42.webp","p_bat_43":"/img/p/p_bat_43.webp","p_bat_44":"/img/p/p_bat_44.webp","p_bat_45":"/img/p/p_bat_45.webp","p_bat_46":"/img/p/p_bat_46.webp","p_bat_47":"/img/p/p_bat_47.webp","p_bat_48":"/img/p/p_bat_48.webp","p_bat_49":"/img/p/p_bat_49.webp","p_bat_50":"/img/p/p_bat_50.webp","p_bat_51":"/img/p/p_bat_51.webp","p_bat_52":"/img/p/p_bat_52.webp","p_bat_53":"/img/p/p_bat_53.webp","p_bat_54":"/img/p/p_bat_54.webp","p_bat_55":"/img/p/p_bat_55.webp","p_str_56":"/img/p/p_str_56.webp","p_str_57":"/img/p/p_str_57.webp","p_str_58":"/img/p/p_str_58.webp","p_str_59":"/img/p/p_str_59.webp","p_str_60":"/img/p/p_str_60.webp","p_adb_61":"/img/p/p_adb_61.webp","p_adb_62":"/img/p/p_adb_62.webp","p_adb_63":"/img/p/p_adb_63.webp","p_adb_64":"/img/p/p_adb_64.webp","p_adb_65":"/img/p/p_adb_65.webp","p_adb_66":"/img/p/p_adb_66.webp","p_adb_67":"/img/p/p_adb_67.webp","p_adb_68":"/img/p/p_adb_68.webp","p_adb_69":"/img/p/p_adb_69.webp","p_ert_70":"/img/p/p_ert_70.webp","p_ert_71":"/img/p/p_ert_71.webp","p_ert_72":"/img/p/p_ert_72.webp","p_ert_73":"/img/p/p_ert_73.webp","p_ert_74":"/img/p/p_ert_74.webp","p_ert_75":"/img/p/p_ert_75.webp","p_lgt_76":"/img/p/p_lgt_76.webp","p_lgt_77":"/img/p/p_lgt_77.webp","p_lgt_78":"/img/p/p_lgt_78.webp","p_lgt_79":"/img/p/p_lgt_79.webp","p_lgt_80":"/img/p/p_lgt_80.webp","p_lgt_81":"/img/p/p_lgt_81.webp","p_lgt_82":"/img/p/p_lgt_82.webp","p_lgt_83":"/img/p/p_lgt_83.webp","p_lgt_84":"/img/p/p_lgt_84.webp","p_lgt_85":"/img/p/p_lgt_85.webp","p_cam_86":"/img/p/p_cam_86.webp","p_cam_87":"/img/p/p_cam_87.webp","p_cam_88":"/img/p/p_cam_88.webp","p_cam_89":"/img/p/p_cam_89.webp","p_cam_90":"/img/p/p_cam_90.webp","p_hap_91":"/img/p/p_hap_91.webp","p_hap_92":"/img/p/p_hap_92.webp","p_hap_93":"/img/p/p_hap_93.webp","p_hap_94":"/img/p/p_hap_94.webp","p_hap_95":"/img/p/p_hap_95.webp","p_hap_96":"/img/p/p_hap_96.webp","p_hap_97":"/img/p/p_hap_97.webp","p_hap_98":"/img/p/p_hap_98.webp","p_hap_99":"/img/p/p_hap_99.webp","p_hap_100":"/img/p/p_hap_100.webp","p_hap_101":"/img/p/p_hap_101.webp","p_hap_102":"/img/p/p_hap_102.webp","p_hap_103":"/img/p/p_hap_103.webp","p_bos_104":"/img/p/p_bos_104.webp","p_bos_105":"/img/p/p_bos_105.webp","p_bos_106":"/img/p/p_bos_106.webp","p_bos_107":"/img/p/p_bos_107.webp","p_bos_108":"/img/p/p_bos_108.webp","p_bos_109":"/img/p/p_bos_109.webp","p_bos_110":"/img/p/p_bos_110.webp","p_bos_111":"/img/p/p_bos_111.webp","p_bos_112":"/img/p/p_bos_112.webp","p_bos_113":"/img/p/p_bos_113.webp","p_bos_114":"/img/p/p_bos_114.webp","p_bos_115":"/img/p/p_bos_115.webp","p_bos_116":"/img/p/p_bos_116.webp","p_bos_117":"/img/p/p_bos_117.webp","p_bos_118":"/img/p/p_bos_118.webp","p_bos_119":"/img/p/p_bos_119.webp","p_bos_120":"/img/p/p_bos_120.webp","p_bos_121":"/img/p/p_bos_121.webp","p_bos_122":"/img/p/p_bos_122.webp","p_bos_123":"/img/p/p_bos_123.webp","p_bos_124":"/img/p/p_bos_124.webp","p_bos_125":"/img/p/p_bos_125.webp","p_bos_126":"/img/p/p_bos_126.webp","p_bos_127":"/img/p/p_bos_127.webp","p_bos_128":"/img/p/p_bos_128.webp","p_bos_129":"/img/p/p_bos_129.webp","p_bos_130":"/img/p/p_bos_130.webp","p_bos_131":"/img/p/p_bos_131.webp","p_bos_132":"/img/p/p_bos_132.webp","p_bos_133":"/img/p/p_bos_133.webp","p_mnt_134":"/img/p/p_mnt_134.webp","p_mnt_135":"/img/p/p_mnt_135.webp","p_mnt_136":"/img/p/p_mnt_136.webp","p_mnt_137":"/img/p/p_mnt_137.webp","p_mnt_138":"/img/p/p_mnt_138.webp","p_mnt_139":"/img/p/p_mnt_139.webp","p_mnt_140":"/img/p/p_mnt_140.webp","p_mnt_141":"/img/p/p_mnt_141.webp","p_mnt_142":"/img/p/p_mnt_142.webp","p_mnt_143":"/img/p/p_mnt_143.webp","p_mnt_144":"/img/p/p_mnt_144.webp","prj_1":"/img/p/prj_1.webp","prj_2":"/img/p/prj_2.webp","prj_3":"/img/p/prj_3.webp","prj_4":"/img/p/prj_4.webp","prj_5":"/img/p/prj_5.webp","prj_6":"/img/p/prj_6.webp"},"s":{"sec_u1":"/img/p/p_pnl_1.webp","sec_u2":"/img/p/p_pnl_1.webp","sec_PNL":"/img/p/p_pnl_1.webp","sec_PNL_BDC":"/img/p/p_pnl_1.webp","sec_PNL_TDC":"/img/p/p_pnl_5.webp","sec_PNL_BND":"/img/p/p_pnl_9.webp","sec_PNL_TND":"/img/p/p_pnl_13.webp","sec_PNL_SML":"/img/p/p_pnl_17.webp","sec_INV":"/img/p/p_inv_23.webp","sec_INV_ONG":"/img/p/p_inv_23.webp","sec_INV_HYB":"/img/p/p_inv_31.webp","sec_INV_OFG":"/img/p/p_inv_36.webp","sec_INV_DDC":"/img/p/p_inv_40.webp","sec_BAT":"/img/p/p_bat_43.webp","sec_BAT_LAB":"/img/p/p_bat_43.webp","sec_BAT_LIB":"/img/p/p_bat_50.webp","sec_STR":"/img/p/p_str_56.webp","sec_STR_GIS":"/img/p/p_str_56.webp","sec_STR_HDG":"/img/p/p_str_58.webp","sec_STR_SPR":"/img/p/p_str_60.webp","sec_ADB":"/img/p/p_adb_61.webp","sec_ADB_SDB":"/img/p/p_adb_61.webp","sec_ADB_MDB":"/img/p/p_adb_63.webp","sec_ADB_SAC":"/img/p/p_adb_66.webp","sec_ADB_TAC":"/img/p/p_adb_68.webp","sec_ERT":"/img/p/p_ert_70.webp","sec_ERT_GIE":"/img/p/p_ert_70.webp","sec_ERT_CBE":"/img/p/p_ert_73.webp","sec_LGT":"/img/p/p_lgt_76.webp","sec_LGT_STL":"/img/p/p_lgt_76.webp","sec_LGT_GDL":"/img/p/p_lgt_80.webp","sec_LGT_WLP":"/img/p/p_lgt_82.webp","sec_LGT_WLT":"/img/p/p_lgt_84.webp","sec_CAM":"/img/p/p_cam_86.webp","sec_CAM_SSC":"/img/p/p_cam_86.webp","sec_CAM_SCL":"/img/p/p_cam_89.webp","sec_HAP":"/img/p/p_hap_91.webp","sec_HAP_HIS":"/img/p/p_hap_100.webp","sec_HAP_HIN":"/img/p/p_hap_91.webp","sec_HAP_HBT":"/img/p/p_hap_96.webp","sec_BOS":"/img/p/p_bos_104.webp","sec_BOS_DCC":"/img/p/p_bos_104.webp","sec_BOS_ACC":"/img/p/p_bos_107.webp","sec_BOS_MC4":"/img/p/p_bos_110.webp","sec_BOS_CND":"/img/p/p_bos_114.webp","sec_BOS_PRT":"/img/p/p_bos_116.webp","sec_BOS_ISO":"/img/p/p_bos_122.webp","sec_BOS_MTR":"/img/p/p_bos_124.webp","sec_BOS_JBX":"/img/p/p_bos_127.webp","sec_BOS_HDW":"/img/p/p_bos_129.webp","sec_BOS_ACS":"/img/p/p_bos_131.webp","sec_MNT":"/img/p/p_mnt_134.webp","sec_MNT_FCM":"/img/p/p_mnt_134.webp","sec_MNT_MAU":"/img/p/p_mnt_136.webp","sec_MNT_CLN":"/img/p/p_mnt_139.webp","sec_MNT_SFT":"/img/p/p_mnt_142.webp","sec_PRJ":"/img/p/prj_1.webp"},"ss":{"ss_1":["/img/b/ban-home.webp","/img/b/ban-pmsurya.webp","/img/b/ban-festive.webp"],"ss_2":["/img/b/ban-lithium.webp","/img/b/ban-hybrid.webp"],"ss_3":["/img/b/ban-farmer.webp","/img/b/ban-heater.webp"],"ss_4":["/img/b/ban-install.webp","/img/b/ban-dealer.webp"]},"bs":["/img/b/ban-home.webp","/img/b/ban-store.webp","/img/b/ban-lithium.webp","/img/b/ban-install.webp"],"cs":"/img/b/ban-custom.webp"}$j$; cur jsonb;
begin
  select data into cur from public.sp_store where id = 'main';
  if cur is null then return; end if;
  cur := jsonb_set(cur, '{products}', coalesce((select jsonb_agg(case when (m->'p'->>(x->>'id')) is not null and coalesce(x->>'image','')='' then x||jsonb_build_object('image',m->'p'->>(x->>'id')) else x end order by o) from jsonb_array_elements(coalesce(cur->'products','[]'::jsonb)) with ordinality t(x,o)), '[]'::jsonb));
  cur := jsonb_set(cur, '{sections}', coalesce((select jsonb_agg(case when (m->'s'->>(x->>'id')) is not null and coalesce(x->>'image','')='' then x||jsonb_build_object('image',m->'s'->>(x->>'id')) else x end order by o) from jsonb_array_elements(coalesce(cur->'sections','[]'::jsonb)) with ordinality t(x,o)), '[]'::jsonb));
  cur := jsonb_set(cur, '{slideshows}', coalesce((select jsonb_agg(case when jsonb_typeof(s->'slides')='array' then s||jsonb_build_object('slides',(select coalesce(jsonb_agg(case when ((m->'ss'->(s->>'id'))->>((o2-1)::int)) is not null and coalesce(y->>'image','')='' then y||jsonb_build_object('image',(m->'ss'->(s->>'id'))->>((o2-1)::int)) else y end order by o2),'[]'::jsonb) from jsonb_array_elements(s->'slides') with ordinality t2(y,o2))) else s end order by o) from jsonb_array_elements(coalesce(cur->'slideshows','[]'::jsonb)) with ordinality t(s,o)), '[]'::jsonb));
  if jsonb_typeof(cur#>'{builder,comps}')='object' then
    cur := jsonb_set(cur, '{builder,comps}', coalesce((select jsonb_object_agg(k, case
      when c->>'type'='raw_category' and jsonb_typeof(c#>'{cfg,boxes}')='array' then jsonb_set(c,'{cfg,boxes}',(select coalesce(jsonb_agg(case when (m->'s'->>(y->>'sec')) is not null and coalesce(y->>'image','')='' then y||jsonb_build_object('image',m->'s'->>(y->>'sec')) else y end order by o2),'[]'::jsonb) from jsonb_array_elements(c#>'{cfg,boxes}') with ordinality t2(y,o2)))
      when c->>'type'='slideshow_banner' and jsonb_typeof(c#>'{cfg,slides}')='array' then jsonb_set(c,'{cfg,slides}',(select coalesce(jsonb_agg(case when (m->'bs'->>((o2-1)::int)) is not null and coalesce(y->>'image','')='' then y||jsonb_build_object('image',m->'bs'->>((o2-1)::int)) else y end order by o2),'[]'::jsonb) from jsonb_array_elements(c#>'{cfg,slides}') with ordinality t2(y,o2)))
      when c->>'type'='custom_section' and jsonb_typeof(c->'cfg')='object' then jsonb_set(c,'{cfg}',case when (m->>'cs') is not null and coalesce(c->'cfg'->>'img','')='' then c->'cfg'||jsonb_build_object('img',m->>'cs') else c->'cfg' end)
      else c end) from jsonb_each(cur#>'{builder,comps}') e(k,c)), '{}'::jsonb));
  end if;
  update public.sp_store set data = cur where id = 'main';
end $do$;


-- CRM-STOCK-STARTER.sql — CRM Inventory (Stock) me starter items ki quantity bharta hai, taaki Inventory khali na dikhe.
-- SIRF un starter items par jo 'Starter catalog' se aaye hain (seed_key) aur jinka stock khali hai. Aapka bhara hua stock kabhi nahi badalta.
-- Quantity andaza hai — apni asli quantity CRM -> Products me badal lein. Safe to re-run.
do $do$
declare m jsonb := $j${"sp13-001":85,"sp13-002":55,"sp13-003":50,"sp13-004":40,"sp13-005":25,"sp13-006":60,"sp13-007":95,"sp13-008":70,"sp13-009":105,"sp13-010":50,"sp13-011":105,"sp13-012":45,"sp13-013":30,"sp13-014":30,"sp13-015":80,"sp13-016":20,"sp13-017":100,"sp13-018":110,"sp13-019":105,"sp13-020":55,"sp13-021":105,"sp13-022":25,"sp13-023":7,"sp13-024":13,"sp13-025":6,"sp13-026":10,"sp13-027":8,"sp13-028":6,"sp13-029":10,"sp13-030":4,"sp13-031":13,"sp13-032":8,"sp13-033":5,"sp13-034":12,"sp13-035":7,"sp13-036":8,"sp13-037":4,"sp13-038":13,"sp13-039":12,"sp13-040":12,"sp13-041":4,"sp13-042":8,"sp13-043":8,"sp13-044":20,"sp13-045":20,"sp13-046":6,"sp13-047":16,"sp13-048":8,"sp13-049":7,"sp13-050":11,"sp13-051":18,"sp13-052":9,"sp13-053":16,"sp13-054":16,"sp13-055":16,"sp13-056":50,"sp13-057":120,"sp13-058":50,"sp13-059":135,"sp13-060":125,"sp13-061":27,"sp13-062":19,"sp13-063":17,"sp13-064":16,"sp13-065":12,"sp13-066":8,"sp13-067":23,"sp13-068":18,"sp13-069":9,"sp13-070":18,"sp13-071":12,"sp13-072":6,"sp13-073":16,"sp13-074":23,"sp13-075":9,"sp13-076":18,"sp13-077":16,"sp13-078":20,"sp13-079":19,"sp13-080":31,"sp13-081":35,"sp13-082":34,"sp13-083":38,"sp13-084":17,"sp13-085":40,"sp13-086":14,"sp13-087":8,"sp13-088":11,"sp13-089":9,"sp13-090":8,"sp13-091":8,"sp13-092":10,"sp13-093":8,"sp13-094":7,"sp13-095":9,"sp13-096":11,"sp13-097":9,"sp13-098":4,"sp13-099":6,"sp13-100":7,"sp13-101":5,"sp13-102":3,"sp13-103":9,"sp13-104":370,"sp13-105":805,"sp13-106":7,"sp13-107":360,"sp13-108":725,"sp13-109":910,"sp13-110":50,"sp13-111":65,"sp13-112":70,"sp13-113":22,"sp13-114":660,"sp13-115":570,"sp13-116":100,"sp13-117":155,"sp13-118":65,"sp13-119":110,"sp13-120":185,"sp13-121":190,"sp13-122":170,"sp13-123":170,"sp13-124":110,"sp13-125":85,"sp13-126":17,"sp13-127":50,"sp13-128":23,"sp13-129":25,"sp13-130":25,"sp13-131":58,"sp13-132":21,"sp13-133":60}$j$; n int;
begin
  update public.crm_records r set data = r.data || jsonb_build_object('stock', (m ->> (r.data ->> 'seed_key'))::numeric)
   where r.kind = 'item' and r.deleted_at is null and m ? (r.data ->> 'seed_key') and coalesce(r.data ->> 'stock', '') = '';
  get diagnostics n = row_count; raise notice 'CRM starter stock filled for % items', n;
end $do$;

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
grant execute on function public.crm_share_create(jsonb) to anon, authenticated;

create or replace function public.crm_share_list(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token');
begin
  return coalesce((select jsonb_agg(jsonb_build_object('token', x.token, 'kind', x.kind, 'title', x.title, 'at', x.created_at, 'by', x.by_name, 'views', x.views,
            'last_view', x.last_view, 'revoked', x.revoked, 'expired', x.expires_at < now()) order by x.id desc)
     from (select * from public.sp_shares where ref = btrim(coalesce(p ->> 'ref', '')) and btrim(coalesce(p ->> 'ref', '')) <> '' order by id desc limit 20) x), '[]'::jsonb);
end $$;
revoke all on function public.crm_share_list(jsonb) from public;
grant execute on function public.crm_share_list(jsonb) to anon, authenticated;

create or replace function public.crm_share_revoke(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); n int;
begin
  update public.sp_shares set revoked = coalesce((p ->> 'on')::boolean, true) where token = btrim(coalesce(p ->> 'code', ''));
  get diagnostics n = row_count;
  return jsonb_build_object('ok', n > 0);
end $$;
revoke all on function public.crm_share_revoke(jsonb) from public;
grant execute on function public.crm_share_revoke(jsonb) to anon, authenticated;

-- customers on Website / Store (no login): short upload token + create, both rate-limited per IP ---------------------------
create or replace function public.sp_share_rate(p_max int) returns void
language plpgsql security definer set search_path = public as $$
declare v_ip text := coalesce(nullif(split_part(coalesce(current_setting('request.headers', true), '{}')::json ->> 'x-forwarded-for', ',', 1), ''), 'local');
begin
  delete from public.sp_share_rl where at < now() - interval '1 day';
  if (select count(*) from public.sp_share_rl where ip = v_ip and at > now() - interval '1 hour') >= p_max
     or (select count(*) from public.sp_share_rl where at > now() - interval '1 hour') >= 400 then
    raise exception 'Bahut zyada koshish — thodi der baad dobara karein';
  end if;
  insert into public.sp_share_rl(ip) values (v_ip);
end $$;
revoke all on function public.sp_share_rate(int) from public, anon, authenticated;

create or replace function public.sp_share_pub_token(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare t text := encode(gen_random_bytes(12), 'hex');
begin
  perform public.sp_share_rate(20);
  delete from public.sp_upload_tokens where exp < now();
  insert into public.sp_upload_tokens(token, exp) values (t, now() + interval '20 minutes');
  return jsonb_build_object('token', t);
end $$;
revoke all on function public.sp_share_pub_token(jsonb) from public;
grant execute on function public.sp_share_pub_token(jsonb) to anon, authenticated;

create or replace function public.sp_share_pub_create(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare t text;
begin
  perform public.sp_share_rate(20);
  t := public.sp_share_insert(p, null, 'Customer', 'public');
  return jsonb_build_object('token', t);
end $$;
revoke all on function public.sp_share_pub_create(jsonb) from public;
grant execute on function public.sp_share_pub_create(jsonb) to anon, authenticated;

-- the public link page (Vercel function /api/d) reads one share by its code; counts a view only for real people ------------
create or replace function public.sp_share_open(p_token text, p_count boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.sp_shares;
begin
  select * into r from public.sp_shares where token = btrim(coalesce(p_token, '')) and not revoked and expires_at > now();
  if r.id is null then return null; end if;
  if p_count then update public.sp_shares set views = views + 1, first_view = coalesce(first_view, now()), last_view = now() where id = r.id; end if;
  return jsonb_build_object('kind', r.kind, 'title', r.title, 'subtitle', r.subtitle, 'amount', r.amount, 'valid_till', r.valid_till, 'details', r.details,
    'pdf_url', r.pdf_url, 'view_url', r.view_url, 'file_name', r.file_name, 'brand', r.brand, 'phone', r.phone, 'created_at', r.created_at);
end $$;
revoke all on function public.sp_share_open(text, boolean) from public;
grant execute on function public.sp_share_open(text, boolean) to anon, authenticated;

notify pgrst, 'reload schema';

-- ============================================================================
-- ROUND 34 — Maintenance & AMC: visit cycle (one-time / quarterly / half-yearly / yearly / 5 years) and visit time
-- ============================================================================
create or replace function public.crm_maint_contract(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); ex public.crm_records; pl public.crm_records; months int; yrs int; total int; i int;
        cid text := 'MC-' || encode(gen_random_bytes(4), 'hex'); start_ date; checks jsonb := '[]'::jsonb; pname text; cost numeric := 0; asg bigint := coalesce(nullif(p ->> 'assigned_to', '')::bigint, (s).uid); c jsonb; ck public.crm_records; cyc text := lower(coalesce(nullif(p ->> 'cycle', ''), '')); vt text := left(coalesce(p ->> 'time', ''), 5);
begin
  if not (public.crm_can(s, 'customers.create') or public.crm_can(s, 'customers.edit') or public.crm_can(s, 'items.view') or public.crm_is_admin(s)) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  select * into ex from public.crm_records where id = (p ->> 'party_id')::bigint and kind = 'party';
  if not public.crm_vis(s, ex) then raise exception 'Customer nahi mila'; end if;
  begin start_ := (p ->> 'start')::date; exception when others then raise exception 'Sahi tareekh chunein'; end;
  if start_ is null then raise exception 'Pehli visit ki tareekh chunein'; end if;
  select * into pl from public.crm_records where id = nullif(p ->> 'plan_id', '')::bigint and kind = 'item' and deleted_at is null and data ->> 'type' = 'maintenance';
  if pl.id is null then raise exception 'Plan chunein (Maintenance & Audit Packages me plan banayein)'; end if;
  pname := pl.title; months := public.crm_months_of(coalesce(nullif(cyc, ''), pl.data ->> 'period'));
  if cyc = 'one' then months := 0; elsif cyc = 'five' then months := 60; elsif cyc = 'monthly' then months := 1; end if;
  if vt <> '' and vt !~ '^[0-2][0-9]:[0-5][0-9]$' then raise exception 'Sahi time chunein'; end if;
  yrs := least(greatest(coalesce(nullif(pl.data ->> 'years', '')::int, 1), 1), 10);
  total := case when months = 0 then 1 else least(greatest(ceil(12.0 / months * yrs)::int, 1), 120) end;
  for c in select * from jsonb_array_elements(coalesce(pl.data -> 'checklist', '[]'::jsonb)) loop
    select * into ck from public.crm_records where id = nullif(c #>> '{}', '')::bigint and kind = 'item' and deleted_at is null and data ->> 'type' = 'mcheck';
    if ck.id is not null then
      checks := checks || jsonb_build_array(jsonb_build_object('id', ck.id, 'name', ck.title, 'cost', public.crm_num(ck.data -> 'cost'),
        'mat_id', nullif(ck.data ->> 'material_item_id', ''), 'mat_qty', public.crm_num(ck.data -> 'material_qty')));
      cost := cost + public.crm_num(ck.data -> 'cost');
    end if;
  end loop;
  for i in 0 .. total - 1 loop
    insert into public.crm_records(kind, title, status, owner_id, assigned_to, party_id, mobile, due_at, data, search, created_by)
    values ('reminder', 'Solar service — ' || ex.title, 'open', (s).uid, asg, ex.id, ex.mobile, (start_ + make_interval(months => i * months))::date,
      jsonb_build_object('type', 'amc', 'maint', true, 'contract_id', cid, 'plan_id', pl.id, 'plan_name', pname, 'free', coalesce((pl.data ->> 'free')::boolean, false), 'months', months, 'cycle', coalesce(nullif(cyc, ''), pl.data ->> 'period'), 'visit_time', vt,
        'visit_no', i + 1, 'visits_total', total, 'checks', checks, 'visit_cost', cost, 'mobile', coalesce(ex.mobile, ''), 'party_name', ex.title, 'title', 'Solar service — ' || ex.title),
      lower('solar service ' || ex.title || ' ' || pname), (s).uid);
  end loop;
  perform public.crm_log(s, 'create', 'maintenance', ex.id, 'Maintenance & Audit: ' || pname || ' → ' || ex.title || ' (' || total || ' visits)');
  return jsonb_build_object('ok', true, 'contract_id', cid, 'visits', total, 'first_due', start_);
end $$;

-- ============================================================================
-- ROUND 34 — single-service jobs: 'AMC only' and 'Site visit only' customer types (Lead / Customer / Conversation filled, then straight to that step)
-- ============================================================================
create or replace function public.crm_ctypes() returns text[] language sql immutable as $$ select array['Residential','Commercial','Industrial','VFD','Items only','Service','AMC only','Site visit only'] $$;

create or replace function public.crm_wf_flow(ct text) returns int[] language sql immutable as $$
  select case
    when ct = 'Items only'  then array[19,1,2,14,3,12,16,18]                               -- Product customer
    when ct = 'Service'     then array[19,1,2,3,4,12,17,16,18]                             -- Service customer (cleaning, AMC, repair, shifting, audit)
    when ct = 'AMC only'        then array[19,1,2,17]                                      -- only a Maintenance / AMC plan: Lead, Customer, Conversation filled, then AMC
    when ct = 'Site visit only' then array[19,1,2,4]                                       -- only a Site Visit: Lead, Customer, Conversation filled, then Site Visit
    when ct = 'Residential' then array[19,1,2,14,3,4,5,7,15,8,9,10,11,12,13,16,17,18]      -- Project, subsidy applies
    else                         array[19,1,2,14,3,4,5,7,15,8,9,10,11,12,16,17,18] end $$;

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
end $$;

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
  fk := case coalesce(q.data ->> 'ctype', '') when 'Items only' then 'product' when 'Service' then 'service' when 'AMC only' then 'service' when 'Site visit only' then 'service' else 'project' end;
  return jsonb_build_object('party_id', q.party_id, 'quote_id', q.id, 'ref', q.ref, 'title', coalesce(q.data ->> 'qtitle', q.title), 'ctype', q.data ->> 'ctype', 'status', q.status, 'plants', plants,
    'project', (q.data -> 'wf') ? '7', 'kind', fk, 'bill_state', q.data ->> 'bill_state', 'steps', public.crm_wf_steps(s, q));
end $$;

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
    raise exception 'Ye step is customer ke liye nahi hai (% — %)', case ct when 'Items only' then 'Product customer' when 'Service' then 'Service customer' when 'AMC only' then 'AMC customer' when 'Site visit only' then 'Site visit customer' else 'Project customer' end, (public.crm_wf_names())[n];
  end if;
  if n = 13 and not (public.crm_is_admin(s) or (s).role = 'manager') then raise exception 'Subsidy sirf Admin ya Manager green kar sakte hain'; end if;
  if not public.crm_wf_can(s, n, 'edit') then raise exception 'Is step ko badalne ki permission nahi hai — Admin se allow karwayein'; end if;
  w := coalesce(q.data -> 'wf', '{}'::jsonb);
  if done then
    if n = 7 and not (w ? '6') then raise exception 'Pehle quotation Confirm hona chahiye'; end if;
    if (n in (8, 9, 10, 11, 13) or (n = 17 and ct not in ('Service', 'AMC only'))) and not (w ? '7') then raise exception 'Pehle Apply Process confirm karein — tabhi customer Projects me aata hai'; end if;
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

-- ============================================================================
-- ROUND 34 — Naya Kaam for AMC-only / Site-visit-only (no inventory item needed)
-- ============================================================================
-- Naya Kaam for a customer who only wants one service: creates a light job record (no inventory items needed)
create or replace function public.crm_job_new(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); ex public.crm_records; ct text := coalesce(p ->> 'ctype', ''); nm text; r public.crm_records;
begin
  if ct not in ('AMC only', 'Site visit only') then raise exception 'Kaam ka prakar galat hai'; end if;
  if not (public.crm_can(s, 'customers.edit') or public.crm_can(s, 'customers.create') or public.crm_can(s, 'quotes.create') or public.crm_is_admin(s)) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  select * into ex from public.crm_records where id = (p ->> 'party_id')::bigint and kind = 'party' and deleted_at is null;
  if ex.id is null or not public.crm_vis(s, ex) then raise exception 'Customer nahi mila'; end if;
  nm := case ct when 'AMC only' then 'AMC' else 'Site Visit' end;
  insert into public.crm_records(kind, ref, title, status, owner_id, assigned_to, party_id, mobile, data, search, created_by)
  values ('quote', public.crm_next_no('quote'), ex.title, 'accepted', (s).uid, (s).uid, ex.id, ex.mobile,
          jsonb_build_object('ctype', ct, 'qtitle', nm || ' — ' || ex.title, 'lines', '[]'::jsonb, 'discount', 0, 'date', to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM-DD'), 'job_only', true,
                             'party', jsonb_build_object('name', ex.title, 'mobile', coalesce(ex.mobile, ''))),
          lower(nm || ' ' || ex.title), (s).uid)
  returning * into r;
  perform public.crm_log(s, 'create', 'quote', r.id, 'Naya kaam: ' || nm || ' → ' || ex.title);
  return jsonb_build_object('ok', true, 'id', r.id, 'ref', r.ref);
end $$;
do $g$ begin
  execute 'revoke all on function public.crm_job_new(jsonb) from public';
  execute 'grant execute on function public.crm_job_new(jsonb) to anon, authenticated';
exception when undefined_object then null; end $g$;

-- ============================================================================
-- ROUND 34b — 5 FIXED Maintenance & AMC plans (Random, Recommended, Valuable, Tension Free, Best Value): only Admin can change price + what is included; cycle / duration are locked.
-- ============================================================================
create or replace function public.crm_save(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); k text := p ->> 'kind'; id_ bigint := nullif(p ->> 'id', '')::bigint;
        d jsonb := coalesce(p -> 'data', '{}'::jsonb); old public.crm_records; r public.crm_records; isnew boolean := id_ is null or id_ = 0;
        mob text; em text; ttl text; st text := coalesce(p ->> 'status', ''); asg bigint := nullif(p ->> 'assigned_to', '')::bigint; pid bigint := nullif(p ->> 'party_id', '')::bigint;
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
  em := lower(left(trim(coalesce(d ->> 'email', '')), 160));
  ttl := left(trim(coalesce(d ->> 'name', d ->> 'title', '')), 200);
  owner_ := case when isnew then (s).uid else old.owner_id end;
  if not isnew and pid is null and not (p ? 'party_id') then pid := old.party_id; end if;
  if not isnew and not (p ? 'assigned_to') then asg := old.assigned_to; end if;
  if not isnew and not (p ? 'due_at') then due := old.due_at; end if;

  -- ---------------- per kind rules
  if k = 'party' then
    perform public.crm_need(s, case when isnew then 'customers.create' else 'customers.edit' end);
    if ttl = '' then raise exception 'Customer ka naam likhein'; end if;
    if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein (mobile zaroori hai)'; end if;
    if em <> '' and em !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'Sahi email likhein (ya khali chhodein)'; end if;
    select * into ex from public.crm_records where kind = 'party' and deleted_at is null and mobile = mob and id <> coalesce(id_, 0) limit 1;
    if ex.id is not null then
      if public.crm_vis(s, ex) then raise exception 'Ye customer pehle se list me hai: % (#%)', ex.title, ex.id;
      else raise exception 'Ye customer pehle se % ke paas hai — Admin se transfer karwayein', coalesce(public.crm_uname(ex.owner_id), 'kisi aur'); end if;
    end if;
    if (p ? 'assigned_to') and asg is distinct from (case when isnew then null else old.assigned_to end) then perform public.crm_need(s, 'customers.assign'); end if;
    pid := null; st := coalesce(nullif(st, ''), case when isnew then 'active' else old.status end);
  elsif k = 'item' then
    perform public.crm_need(s, case when isnew then 'items.create' else 'items.edit' end);
    if not isnew and old.data ->> 'fixed' = 'true' and not public.crm_is_admin(s) then raise exception 'Ye Fixed plan hai — sirf Admin iski keemat / kaam ki list badal sakta hai'; end if;
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
    if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein (mobile zaroori hai)'; end if;
    if em <> '' and em !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'Sahi email likhein (ya khali chhodein)'; end if;
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
    if pid is null and mob <> '' then select id into pid from public.crm_records where kind = 'party' and mobile = mob and deleted_at is null limit 1; end if;
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

  srch := lower(concat_ws(' ', ttl, ref_, mob, em, d ->> 'city', d ->> 'company', d ->> 'gstin', d ->> 'note', d ->> 'type', d ->> 'brand', d ->> 'qtitle', d ->> 'category', d ->> 'subcategory', d ->> 'sku', d ->> 'mpn', d ->> 'source'));
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
end $function$
;

create or replace function public.crm_maint_contract(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); ex public.crm_records; pl public.crm_records; months int; yrs int; total int; i int;
        cid text := 'MC-' || encode(gen_random_bytes(4), 'hex'); start_ date; checks jsonb := '[]'::jsonb; pname text; cost numeric := 0; asg bigint := coalesce(nullif(p ->> 'assigned_to', '')::bigint, (s).uid); c jsonb; ck public.crm_records; cyc text := ''; vt text := left(coalesce(p ->> 'time', ''), 5);
begin
  if not (public.crm_can(s, 'customers.create') or public.crm_can(s, 'customers.edit') or public.crm_can(s, 'items.view') or public.crm_is_admin(s)) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  select * into ex from public.crm_records where id = (p ->> 'party_id')::bigint and kind = 'party';
  if not public.crm_vis(s, ex) then raise exception 'Customer nahi mila'; end if;
  begin start_ := (p ->> 'start')::date; exception when others then raise exception 'Sahi tareekh chunein'; end;
  if start_ is null then raise exception 'Pehli visit ki tareekh chunein'; end if;
  select * into pl from public.crm_records where id = nullif(p ->> 'plan_id', '')::bigint and kind = 'item' and deleted_at is null and data ->> 'type' = 'maintenance';
  if pl.id is null then raise exception 'Plan chunein (Maintenance & Audit Packages me plan banayein)'; end if;
  cyc := lower(coalesce(nullif(p ->> 'cycle', ''), pl.data ->> 'period', ''));
  pname := pl.title; months := public.crm_months_of(coalesce(nullif(cyc, ''), pl.data ->> 'period'));
  if cyc = 'one' then months := 0; elsif cyc = 'five' then months := 60; elsif cyc = 'monthly' then months := 1; end if;
  if vt <> '' and vt !~ '^[0-2][0-9]:[0-5][0-9]$' then raise exception 'Sahi time chunein'; end if;
  yrs := least(greatest(coalesce(nullif(pl.data ->> 'years', '')::int, 1), 1), 10);
  total := case when months = 0 then 1 else least(greatest(ceil(12.0 / months * yrs)::int, 1), 120) end;
  for c in select * from jsonb_array_elements(coalesce(pl.data -> 'checklist', '[]'::jsonb)) loop
    select * into ck from public.crm_records where id = nullif(c #>> '{}', '')::bigint and kind = 'item' and deleted_at is null and data ->> 'type' = 'mcheck';
    if ck.id is not null then
      checks := checks || jsonb_build_array(jsonb_build_object('id', ck.id, 'name', ck.title, 'cost', public.crm_num(ck.data -> 'cost'),
        'mat_id', nullif(ck.data ->> 'material_item_id', ''), 'mat_qty', public.crm_num(ck.data -> 'material_qty')));
      cost := cost + public.crm_num(ck.data -> 'cost');
    end if;
  end loop;
  for i in 0 .. total - 1 loop
    insert into public.crm_records(kind, title, status, owner_id, assigned_to, party_id, mobile, due_at, data, search, created_by)
    values ('reminder', 'Solar service — ' || ex.title, 'open', (s).uid, asg, ex.id, ex.mobile, (start_ + make_interval(months => i * months))::date,
      jsonb_build_object('type', 'amc', 'maint', true, 'contract_id', cid, 'plan_id', pl.id, 'plan_name', pname, 'free', coalesce((pl.data ->> 'free')::boolean, false), 'months', months, 'cycle', coalesce(nullif(cyc, ''), pl.data ->> 'period'), 'visit_time', vt, 'plan_code', coalesce(pl.data ->> 'plan_code', ''), 'plan_price', public.crm_num(pl.data -> 'price'), 'plan_gst', public.crm_num(pl.data -> 'gst'), 'prev_contract', coalesce(p ->> 'prev_contract', ''),
        'visit_no', i + 1, 'visits_total', total, 'checks', checks, 'visit_cost', cost, 'mobile', coalesce(ex.mobile, ''), 'party_name', ex.title, 'title', 'Solar service — ' || ex.title),
      lower('solar service ' || ex.title || ' ' || pname), (s).uid);
  end loop;
  perform public.crm_log(s, 'create', 'maintenance', ex.id, 'Maintenance & Audit: ' || pname || ' → ' || ex.title || ' (' || total || ' visits)');
  return jsonb_build_object('ok', true, 'contract_id', cid, 'visits', total, 'first_due', start_);
end $$;

-- structure of a fixed plan can never change (not even by Admin); it cannot be deleted
create or replace function public.crm_plan_lock() returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('sp.restoring', true), '') = 'on' then return new; end if;
  if old.kind = 'item' and old.data ->> 'fixed' = 'true' then
    if new.deleted_at is not null and old.deleted_at is null then raise exception 'Fixed plan hataya nahi ja sakta'; end if;
    new.title := old.title; new.kind := old.kind;
    new.data := new.data || jsonb_build_object('fixed', true, 'type', 'maintenance', 'plan_code', old.data -> 'plan_code', 'name', old.data -> 'name', 'period', old.data -> 'period', 'years', old.data -> 'years', 'visits', old.data -> 'visits', 'unit', old.data -> 'unit', 'category', old.data -> 'category');
  end if;
  return new;
end $$;
drop trigger if exists crm_plan_lock on public.crm_records;
create trigger crm_plan_lock before update on public.crm_records for each row when (old.kind = 'item') execute function public.crm_plan_lock();

-- the 5 fixed plans (old test plans are removed; nobody was assigned to them)
create or replace function public.crm_seed_plans() returns void language plpgsql security definer set search_path = public as $$
declare rec record; ids jsonb := '{}'::jsonb; c record; ck jsonb;
begin
  update public.crm_records set deleted_at = now(), delete_reason = 'Purane plan hataye — 5 Fixed plans aaye'
    where kind = 'item' and data ->> 'type' = 'maintenance' and coalesce(data ->> 'fixed', '') <> 'true' and deleted_at is null;
  for c in select id, title from public.crm_records where kind = 'item' and data ->> 'type' = 'mcheck' and deleted_at is null loop ids := ids || jsonb_build_object(c.title, c.id); end loop;
  for rec in select * from (values
    ('random',      'Random Plan',        'one',       1,  1, 1500, 'Solar panel cleaning|Visual & physical inspection|Inverter check (error log, display, firmware)|Generation report', 'Sirf ek baar ki service — agli due date nahi'),
    ('recommended', 'Recommended Plan',   'quarterly', 1,  4, 4800, 'Solar panel cleaning|Visual & physical inspection|Inverter check (error log, display, firmware)|Earthing resistance test|ACDB check & tightening|DCDB check & tightening|Cable & MC4 connector check|Generation report', 'Quarterly: saal me 4 services (har 3 mahine)'),
    ('valuable',    'Valuable Plan',      'yearly',    1,  1, 1600, 'Solar panel cleaning|Visual & physical inspection|Inverter check (error log, display, firmware)|Generation report', 'Yearly: saal me 1 service'),
    ('tension',     'Tension Free Plan',  'quarterly', 5, 20, 20000, 'Solar panel cleaning|Visual & physical inspection|Inverter check (error log, display, firmware)|Earthing resistance test|ACDB check & tightening|DCDB check & tightening|Cable & MC4 connector check|Shadow & structure check|Lightning arrestor check|Generation report', 'Quarterly: saal me 4, 5 saal me 20 services'),
    ('best',        'Best Value Plan',    'yearly',    5,  5, 7000, 'Solar panel cleaning|Visual & physical inspection|Inverter check (error log, display, firmware)|Earthing resistance test|ACDB check & tightening|DCDB check & tightening|Cable & MC4 connector check|Generation report', 'Yearly: 5 saal me 5 services')
  ) as t(code, nm, per, yrs, vis, price, names, descr) loop
    if exists (select 1 from public.crm_records where kind = 'item' and data ->> 'plan_code' = rec.code and deleted_at is null) then continue; end if;
    select coalesce(jsonb_agg(ids -> n), '[]'::jsonb) into ck from unnest(string_to_array(rec.names, '|')) n where ids ? n;
    insert into public.crm_records(kind, title, status, owner_id, amount, data, search)
    values ('item', rec.nm, 'active', 0, rec.price, jsonb_build_object('type', 'maintenance', 'fixed', true, 'plan_code', rec.code, 'name', rec.nm, 'title', '', 'category', 'Maintenance', 'price', rec.price, 'gst', 18, 'unit', 'Plan',
      'period', rec.per, 'years', rec.yrs, 'visits', rec.vis, 'free', false, 'checklist', ck, 'desc', rec.descr), lower(rec.nm));
  end loop;
end $$;
select public.crm_seed_plans();
do $g$ begin execute 'revoke all on function public.crm_seed_plans() from public, anon, authenticated'; exception when undefined_object then null; end $g$;

-- Change plan for a customer who already has one: open visits of the old plan are cancelled, the new plan is scheduled from the next due date (or today)
create or replace function public.crm_maint_change(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records; old_cid text := p ->> 'contract_id'; nxt date; res jsonb; pid bigint;
begin
  if not (public.crm_can(s, 'customers.edit') or public.crm_can(s, 'items.view') or public.crm_is_admin(s)) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  if coalesce(old_cid, '') = '' then raise exception 'Purana plan nahi mila'; end if;
  select * into r from public.crm_records where kind = 'reminder' and data ->> 'contract_id' = old_cid and deleted_at is null order by id limit 1;
  if r.id is null or not public.crm_vis(s, r) then raise exception 'Purana plan nahi mila'; end if;
  pid := r.party_id;
  select min(due_at) into nxt from public.crm_records where kind = 'reminder' and data ->> 'contract_id' = old_cid and deleted_at is null and status = 'open';
  update public.crm_records set deleted_at = now(), delete_reason = 'Plan badal diya', updated_at = now()
    where kind = 'reminder' and data ->> 'contract_id' = old_cid and deleted_at is null and status = 'open';
  res := public.crm_maint_contract(jsonb_build_object('token', p ->> 'token', 'party_id', pid, 'plan_id', p -> 'plan_id', 'assigned_to', p -> 'assigned_to',
           'start', coalesce(nullif(p ->> 'start', ''), greatest(coalesce(nxt, public.crm_today()), public.crm_today())::text), 'time', coalesce(p ->> 'time', ''), 'prev_contract', old_cid));
  return res || jsonb_build_object('changed_from', old_cid);
end $$;
do $g$ begin
  execute 'revoke all on function public.crm_maint_change(jsonb) from public';
  execute 'grant execute on function public.crm_maint_change(jsonb) to anon, authenticated';
exception when undefined_object then null; end $g$;


-- ============================================================================
-- ROUND 35 — one permanent Customer ID (SP-C-000123) per person + stage: Lead -> Pending Inquiry -> Customer (on first bill)
-- ============================================================================
create or replace function public.crm_cust_id_next() returns text language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into public.crm_counters(key, n) values ('custid', 1) on conflict (key) do update set n = public.crm_counters.n + 1 returning public.crm_counters.n into n;
  return 'SP-C-' || lpad(n::text, 6, '0');
end $$;

-- BEFORE INSERT: every lead / customer gets the ID (same mobile = same ID); a new customer starts as a Pending Inquiry
create or replace function public.crm_custid_ins() returns trigger language plpgsql security definer set search_path = public as $$
declare cid text; d jsonb := coalesce(new.data, '{}'::jsonb);
begin
  if new.kind = 'party' and coalesce(d ->> 'type', 'customer') = 'supplier' then return new; end if;
  cid := nullif(d ->> 'cust_id', '');
  if cid is null and coalesce(new.mobile, '') <> '' then
    select data ->> 'cust_id' into cid from public.crm_records where kind in ('party', 'lead') and mobile = new.mobile and coalesce(data ->> 'cust_id', '') <> '' and deleted_at is null and coalesce(data ->> 'type', 'customer') <> 'supplier' order by id limit 1;
  end if;
  if cid is null then cid := public.crm_cust_id_next(); end if;
  d := d || jsonb_build_object('cust_id', cid);
  if new.kind = 'party' and coalesce(d ->> 'stage', '') not in ('inquiry', 'customer') then d := d || jsonb_build_object('stage', 'inquiry'); end if;
  new.data := d;
  new.search := trim(coalesce(new.search, '') || ' ' || lower(cid));
  return new;
end $$;
drop trigger if exists crm_custid_ins on public.crm_records;
create trigger crm_custid_ins before insert on public.crm_records for each row when (new.kind in ('party', 'lead')) execute function public.crm_custid_ins();

-- BEFORE UPDATE: the ID never changes; the stage changes only through the bill (never from a form)
create or replace function public.crm_custid_upd() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(old.data ->> 'cust_id', '') <> '' then new.data := new.data || jsonb_build_object('cust_id', old.data ->> 'cust_id'); end if;
  if new.kind = 'party' and coalesce(current_setting('sp.stage_ok', true), '') <> '1' and coalesce(current_setting('sp.restoring', true), '') <> 'on' then
    if coalesce(old.data ->> 'stage', '') <> '' then new.data := new.data || jsonb_build_object('stage', old.data ->> 'stage'); end if;
  end if;
  return new;
end $$;
drop trigger if exists crm_custid_upd on public.crm_records;
create trigger crm_custid_upd before update on public.crm_records for each row when (old.kind in ('party', 'lead')) execute function public.crm_custid_upd();

-- first bill => the Pending Inquiry becomes a Customer (stays there for life)
create or replace function public.crm_stage_bill() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.party_id is null then return new; end if;
  perform set_config('sp.stage_ok', '1', true);
  update public.crm_records set data = data || jsonb_build_object('stage', 'customer', 'billed_at', public.crm_iso_now()), updated_at = now()
    where id = new.party_id and kind = 'party' and coalesce(data ->> 'stage', '') = 'inquiry';
  perform set_config('sp.stage_ok', '', true);
  return new;
end $$;
drop trigger if exists crm_stage_bill on public.crm_records;
create trigger crm_stage_bill after insert on public.crm_records for each row when (new.kind = 'invoice') execute function public.crm_stage_bill();

-- backfill: IDs for everyone already there (one ID per mobile), stage = Customer when a bill exists, else Pending Inquiry
do $b$
declare r record; cid text; m text;
begin
  perform set_config('sp.restoring', 'on', true);
  for r in select id, kind, mobile, data from public.crm_records
           where kind in ('party', 'lead') and coalesce(data ->> 'cust_id', '') = '' and coalesce(data ->> 'type', 'customer') <> 'supplier' order by id loop
    cid := null; m := coalesce(r.mobile, '');
    if m <> '' then select data ->> 'cust_id' into cid from public.crm_records where kind in ('party', 'lead') and mobile = m and coalesce(data ->> 'cust_id', '') <> '' and coalesce(data ->> 'type', 'customer') <> 'supplier' order by id limit 1; end if;
    if cid is null then cid := public.crm_cust_id_next(); end if;
    update public.crm_records set data = data || jsonb_build_object('cust_id', cid), search = trim(coalesce(search, '') || ' ' || lower(cid)) where id = r.id;
  end loop;
  update public.crm_records p set data = data || jsonb_build_object('stage', case when exists (select 1 from public.crm_records i where i.kind = 'invoice' and i.party_id = p.id) then 'customer' else 'inquiry' end)
    where p.kind = 'party' and coalesce(p.data ->> 'type', 'customer') <> 'supplier' and coalesce(p.data ->> 'stage', '') not in ('inquiry', 'customer');
end $b$;


-- Customer app / shop page: one profile by mobile login — Customer ID, projects (+warranty, AMC), products (+warranty), services (+status), pending quotations
create or replace function public.crm_consumer_profile(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); pt public.crm_records; q public.crm_records; inv public.crm_records; l jsonb; k text; card jsonb; wl jsonb;
        projects jsonb := '[]'::jsonb; services jsonb := '[]'::jsonb; inquiries jsonb := '[]'::jsonb; products jsonb := '[]'::jsonb; cid text; it public.crm_records; qk text;
begin
  select * into pt from public.crm_records where kind = 'party' and deleted_at is null and mobile = u.mobile and u.mobile ~ '^[6-9][0-9]{9}$' and coalesce(data ->> 'type', 'customer') <> 'supplier' order by id limit 1;
  if pt.id is null then
    select data ->> 'cust_id' into cid from public.crm_records where kind = 'lead' and deleted_at is null and mobile = u.mobile order by id limit 1;
    return jsonb_build_object('cust_id', cid, 'stage', 'lead', 'name', u.name, 'mobile', u.mobile, 'projects', projects, 'services', services, 'products', products, 'inquiries', inquiries);
  end if;
  for q in select * from public.crm_records where kind = 'quote' and party_id = pt.id and deleted_at is null order by id loop
    k := case when q.data ->> 'ctype' in ('Residential', 'Commercial', 'Industrial', 'VFD') then 'project' when q.data ->> 'ctype' = 'Items only' then 'product' when coalesce(q.data ->> 'ctype', '') = '' then 'project' else 'service' end;
    if q.status in ('accepted', 'converted') then
      if k = 'product' then continue; end if;
      insert into public.crm_consumer_plants(user_id, quote_id) values (u.id, q.id) on conflict do nothing;
      card := public.crm_plant_card(q);
      wl := '[]'::jsonb;
      for l in select * from jsonb_array_elements(coalesce(q.data -> 'lines', '[]'::jsonb)) loop
        select * into it from public.crm_records where id = nullif(l ->> 'item_id', '')::bigint and kind = 'item';
        if it.id is not null and coalesce(it.data ->> 'warranty', '') <> '' then wl := wl || jsonb_build_array(jsonb_build_object('name', coalesce(l ->> 'name', it.title), 'warranty', it.data ->> 'warranty')); end if;
      end loop;
      card := card || jsonb_build_object('kind', k, 'warranty', wl, 'job_status', case when (q.data ->> 'closed') = 'true' then 'Poora hua' else 'Chal raha hai' end);
      if k = 'project' then projects := projects || jsonb_build_array(card); else services := services || jsonb_build_array(card); end if;
    elsif q.status in ('draft', 'sent') then
      inquiries := inquiries || jsonb_build_array(jsonb_build_object('id', q.id, 'ref', q.ref, 'title', coalesce(q.data ->> 'qtitle', q.title), 'kind', k, 'status', case q.status when 'sent' then 'Quotation bheji gayi' else 'Taiyaar ho rahi hai' end));
    end if;
  end loop;
  for inv in select i.* from public.crm_records i where i.kind = 'invoice' and i.party_id = pt.id and i.deleted_at is null order by i.id loop
    qk := null;
    select case when q2.data ->> 'ctype' = 'Items only' then 'product' else 'other' end into qk from public.crm_records q2 where q2.id = nullif(inv.data ->> 'quote_id', '')::bigint;
    if qk = 'other' then continue; end if;
    for l in select * from jsonb_array_elements(coalesce(inv.data -> 'lines', '[]'::jsonb)) loop
      select * into it from public.crm_records where id = nullif(l ->> 'item_id', '')::bigint and kind = 'item';
      products := products || jsonb_build_array(jsonb_build_object('name', coalesce(l ->> 'name', it.title), 'qty', l -> 'qty', 'bill', inv.ref, 'date', inv.data ->> 'date', 'brand', it.data ->> 'brand', 'warranty', nullif(it.data ->> 'warranty', ''), 'paid', coalesce((inv.data ->> 'balance')::numeric, inv.amount) <= 0.009));
    end loop;
  end loop;
  return jsonb_build_object('cust_id', pt.data ->> 'cust_id', 'stage', coalesce(pt.data ->> 'stage', 'customer'), 'name', pt.title, 'mobile', pt.mobile,
    'projects', projects, 'services', services, 'products', products, 'inquiries', inquiries);
end $$;
grant execute on function public.crm_consumer_profile(jsonb) to anon, authenticated;


-- ============================================================================
-- ROUND 36 — Bills are non-refundable; a bill can be cancelled ("Cancelled – non refundable"); only Admin can allow a refund exception
-- ============================================================================
create or replace function public.crm_bill_cancel(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records; act text := coalesce(p ->> 'action', 'cancel'); why text := left(trim(coalesce(p ->> 'reason', '')), 300);
begin
  select * into r from public.crm_records where id = (p ->> 'id')::bigint and kind = 'invoice' and deleted_at is null;
  if r.id is null or not public.crm_vis(s, r) then raise exception 'Bill nahi mila'; end if;
  perform set_config('sp.restoring', 'on', true);   -- only a flag is changed here: skip the item-line guard of old bills
  if act = 'refund_ok' or act = 'refund_no' then
    if not public.crm_is_admin(s) then raise exception 'Refund ka exception sirf Admin laga sakta hai'; end if;
    update public.crm_records set data = data || jsonb_build_object('refund_ok', act = 'refund_ok', 'refund_note', why), updated_at = now() where id = r.id;
    perform public.crm_log(s, 'update', 'invoice', r.id, case when act = 'refund_ok' then 'Refund exception allowed: ' else 'Refund exception removed: ' end || r.ref);
    return jsonb_build_object('ok', true);
  end if;
  if not (public.crm_can(s, 'invoices.delete') or public.crm_can(s, 'invoices.edit') or public.crm_is_admin(s)) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  if length(why) < 3 then raise exception 'Cancel ka reason likhein'; end if;
  if act = 'restore' then
    if not public.crm_is_admin(s) then raise exception 'Bill dobara sirf Admin chalu kar sakta hai'; end if;
    update public.crm_records set data = (data - 'cancelled' - 'cancel_reason' - 'cancelled_at'), updated_at = now() where id = r.id;
    perform public.crm_log(s, 'update', 'invoice', r.id, 'Bill dobara chalu: ' || r.ref);
    return jsonb_build_object('ok', true);
  end if;
  update public.crm_records set data = data || jsonb_build_object('cancelled', true, 'cancel_reason', why, 'cancelled_at', public.crm_iso_now(), 'cancelled_by', (s).name), updated_at = now() where id = r.id;
  perform public.crm_log(s, 'update', 'invoice', r.id, 'Bill cancel (non-refundable): ' || r.ref || ' — ' || why);
  return jsonb_build_object('ok', true);
end $$;
do $g$ begin execute 'revoke all on function public.crm_bill_cancel(jsonb) from public'; execute 'grant execute on function public.crm_bill_cancel(jsonb) to anon, authenticated'; exception when undefined_object then null; end $g$;

-- customer app profile now also lists all bills (Pending / Paid / Cancelled)

-- Customer app / shop page: one profile by mobile login — Customer ID, projects (+warranty, AMC), products (+warranty), services (+status), pending quotations
create or replace function public.crm_consumer_profile(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); pt public.crm_records; q public.crm_records; inv public.crm_records; l jsonb; k text; card jsonb; wl jsonb;
        bills jsonb := '[]'::jsonb; projects jsonb := '[]'::jsonb; services jsonb := '[]'::jsonb; inquiries jsonb := '[]'::jsonb; products jsonb := '[]'::jsonb; cid text; it public.crm_records; qk text;
begin
  select * into pt from public.crm_records where kind = 'party' and deleted_at is null and mobile = u.mobile and u.mobile ~ '^[6-9][0-9]{9}$' and coalesce(data ->> 'type', 'customer') <> 'supplier' order by id limit 1;
  if pt.id is null then
    select data ->> 'cust_id' into cid from public.crm_records where kind = 'lead' and deleted_at is null and mobile = u.mobile order by id limit 1;
    return jsonb_build_object('cust_id', cid, 'stage', 'lead', 'name', u.name, 'mobile', u.mobile, 'projects', projects, 'services', services, 'products', products, 'inquiries', inquiries, 'bills', bills);
  end if;
  for q in select * from public.crm_records where kind = 'quote' and party_id = pt.id and deleted_at is null order by id loop
    k := case when q.data ->> 'ctype' in ('Residential', 'Commercial', 'Industrial', 'VFD') then 'project' when q.data ->> 'ctype' = 'Items only' then 'product' when coalesce(q.data ->> 'ctype', '') = '' then 'project' else 'service' end;
    if q.status in ('accepted', 'converted') then
      if k = 'product' then continue; end if;
      insert into public.crm_consumer_plants(user_id, quote_id) values (u.id, q.id) on conflict do nothing;
      card := public.crm_plant_card(q);
      wl := '[]'::jsonb;
      for l in select * from jsonb_array_elements(coalesce(q.data -> 'lines', '[]'::jsonb)) loop
        select * into it from public.crm_records where id = nullif(l ->> 'item_id', '')::bigint and kind = 'item';
        if it.id is not null and coalesce(it.data ->> 'warranty', '') <> '' then wl := wl || jsonb_build_array(jsonb_build_object('name', coalesce(l ->> 'name', it.title), 'warranty', it.data ->> 'warranty')); end if;
      end loop;
      card := card || jsonb_build_object('kind', k, 'warranty', wl, 'job_status', case when (q.data ->> 'closed') = 'true' then 'Poora hua' else 'Chal raha hai' end);
      if k = 'project' then projects := projects || jsonb_build_array(card); else services := services || jsonb_build_array(card); end if;
    elsif q.status in ('draft', 'sent') then
      inquiries := inquiries || jsonb_build_array(jsonb_build_object('id', q.id, 'ref', q.ref, 'title', coalesce(q.data ->> 'qtitle', q.title), 'kind', k, 'status', case q.status when 'sent' then 'Quotation bheji gayi' else 'Taiyaar ho rahi hai' end));
    end if;
  end loop;
  for inv in select i.* from public.crm_records i where i.kind = 'invoice' and i.party_id = pt.id and i.deleted_at is null order by i.id loop
    bills := bills || jsonb_build_array(jsonb_build_object('id', inv.id, 'ref', inv.ref, 'date', inv.data ->> 'date', 'title', coalesce(inv.data ->> 'qtitle', inv.title), 'amount', inv.amount, 'paid', coalesce((inv.data ->> 'paid')::numeric, 0), 'balance', coalesce((inv.data ->> 'balance')::numeric, inv.amount), 'due_date', nullif(coalesce(inv.data ->> 'due_date', inv.due_at::text), ''),
      'state', case when (inv.data ->> 'cancelled') = 'true' then 'cancelled' when coalesce((inv.data ->> 'balance')::numeric, inv.amount) <= 0.009 then 'paid' else 'pending' end, 'nonrefundable', coalesce((inv.data ->> 'refund_ok')::boolean, false) = false));
    qk := null;
    select case when q2.data ->> 'ctype' = 'Items only' then 'product' else 'other' end into qk from public.crm_records q2 where q2.id = nullif(inv.data ->> 'quote_id', '')::bigint;
    if qk = 'other' then continue; end if;
    for l in select * from jsonb_array_elements(coalesce(inv.data -> 'lines', '[]'::jsonb)) loop
      select * into it from public.crm_records where id = nullif(l ->> 'item_id', '')::bigint and kind = 'item';
      products := products || jsonb_build_array(jsonb_build_object('name', coalesce(l ->> 'name', it.title), 'qty', l -> 'qty', 'bill', inv.ref, 'date', inv.data ->> 'date', 'brand', it.data ->> 'brand', 'warranty', nullif(it.data ->> 'warranty', ''), 'paid', coalesce((inv.data ->> 'balance')::numeric, inv.amount) <= 0.009));
    end loop;
  end loop;
  return jsonb_build_object('cust_id', pt.data ->> 'cust_id', 'stage', coalesce(pt.data ->> 'stage', 'customer'), 'name', pt.title, 'mobile', pt.mobile,
    'projects', projects, 'services', services, 'products', products, 'inquiries', inquiries, 'bills', bills);
end $$;
grant execute on function public.crm_consumer_profile(jsonb) to anon, authenticated;

-- ================= ROUND 37 — ek customer = ek hi record (clone band) =================
-- Pehle STAGING me chalayein, phir backup ke baad LIVE me.

CREATE OR REPLACE FUNCTION public.crm_inbound_lead(p_name text, p_mobile text, p_source text, p_note text, p_extra jsonb DEFAULT '{}'::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pid_ bigint; mob text := public.crm_mobile(coalesce(p_mobile, '')); nm text := left(trim(coalesce(p_name, '')), 120); lid bigint; asg bigint;
begin
  if mob !~ '^[6-9][0-9]{9}$' or nm = '' then return null; end if;
  select id into pid_ from public.crm_records where kind = 'party' and deleted_at is null and mobile = mob order by id limit 1;
  if pid_ is not null then /* purana customer: naya lead nahi, par inquiry customer ke page par jud jaati hai */
    update public.crm_records set data = jsonb_set(data, '{inquiries}', coalesce(data -> 'inquiries', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('at', public.crm_iso_now(), 'source', coalesce(p_source, ''), 'note', left(coalesce(p_note, ''), 300))), true), updated_at = now()
      where id = pid_ and jsonb_array_length(coalesce(data -> 'inquiries', '[]'::jsonb)) < 60;
    return null;
  end if;
  select id into lid from public.crm_records where kind = 'lead' and deleted_at is null and mobile = mob and status not in ('won', 'lost') order by id limit 1;
  if lid is not null then
    update public.crm_records set data = jsonb_set(data, '{log}', coalesce(data -> 'log', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('t', 'Dobara sampark: ' || coalesce(p_source, '') || case when coalesce(p_note, '') <> '' then ' — ' || left(p_note, 300) else '' end, 'at', public.crm_iso_now(), 'by', 'System')), true), updated_at = now() where id = lid;
    return lid;
  end if;
  select nullif(data #>> '{blueprint,assign_to}', '')::bigint into asg from public.crm_settings where id = 1;
  insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, due_at, data, search, created_by)
    values ('lead', nm, mob, 'new', 0, asg, public.crm_today(), jsonb_build_object('name', nm, 'mobile', mob, 'source', coalesce(p_source, 'Website'), 'note', left(coalesce(p_note, ''), 500), 'company', true, 'intake', 'inbound') || coalesce(p_extra, '{}'::jsonb), lower(nm || ' ' || mob), 0)
    returning id into lid;
  return lid;
end $function$

;

CREATE OR REPLACE FUNCTION public.crm_lead_import(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    if exists (select 1 from public.crm_records where kind = 'party' and deleted_at is null and mobile = m) or exists (select 1 from public.crm_records where kind = 'lead' and deleted_at is null and mobile = m and status not in ('won', 'lost')) then sk := sk + 1; continue; end if;
    insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, due_at, data, search, created_by)
    values ('lead', left(coalesce(nullif(trim(r ->> 'name'), ''), 'Lead ' || m), 120), m, 'new', own, coalesce(to_, (s).uid),
      case when coalesce(r ->> 'followup', '') ~ '^\d{4}-\d{2}-\d{2}$' then (r ->> 'followup')::date else null end,
      (r - 'mobile') || jsonb_build_object('mobile', m, 'source', coalesce(nullif(r ->> 'source', ''), case when company then 'Company' else 'Import' end), 'company', company),
      lower(concat_ws(' ', r ->> 'name', m, r ->> 'city', r ->> 'source')), (s).uid);
    n := n + 1;
  end loop;
  perform public.crm_log(s, 'import', 'lead', null, n || ' leads import' || case when company then ' → ' || public.crm_uname(to_) else '' end || ' (' || sk || ' chhodi)');
  return jsonb_build_object('added', n, 'skipped', sk);
end $function$

;

CREATE OR REPLACE FUNCTION public.crm_blueprint_save(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); bp jsonb := p -> 'blueprint'; id_ bigint := nullif(p ->> 'id', '')::bigint; old public.crm_records;
        nm text := left(trim(coalesce(p ->> 'name', '')), 80); mob text := public.crm_mobile(coalesce(p ->> 'mobile', '')); city text := left(trim(coalesce(p ->> 'city', '')), 80);
        mk boolean := coalesce((p ->> 'make_lead')::boolean, false); bid bigint; lid bigint; pid bigint := nullif(p ->> 'party_id', '')::bigint; pty public.crm_records; kw numeric; summary text; ex public.crm_records;
begin
  perform public.crm_need(s, 'leads.create');
  if bp is null or jsonb_typeof(bp) <> 'object' then raise exception 'Blueprint adhura hai'; end if;
  bp := (bp - 'photos' - 'video') || jsonb_build_object('photo_count', case when jsonb_typeof(bp -> 'photos') = 'array' then jsonb_array_length(bp -> 'photos') else coalesce(nullif(bp ->> 'photo_count', '')::int, 0) end);
  if length(bp::text) > 200000 then raise exception 'Blueprint bahut bada hai'; end if;
  if nm = '' then nm := 'Blueprint'; end if;
  if pid is not null then select * into pty from public.crm_records where id = pid and kind = 'party' and deleted_at is null; if pty.id is null or not public.crm_vis(s, pty) then raise exception 'Customer nahi mila'; end if; if mob = '' then mob := coalesce(pty.mobile, ''); end if;
  elsif mob ~ '^[6-9][0-9]{9}$' then select * into pty from public.crm_records where kind = 'party' and deleted_at is null and mobile = mob order by id limit 1; if pty.id is not null and not public.crm_vis(s, pty) then pty := null; end if; end if;
  pid := pty.id;
  if mk and mob !~ '^[6-9][0-9]{9}$' then raise exception 'Lead ke liye sahi 10 ank ka mobile likhein'; end if;
  kw := public.crm_num(bp #> '{result,kw}');
  if id_ is null then
    insert into public.crm_records(kind, title, mobile, status, owner_id, data, search, created_by)
      values ('blueprint', nm, nullif(mob, ''), 'new', (s).uid, (bp - 'customer') || jsonb_build_object('customer', jsonb_build_object('name', nm, 'mobile', mob, 'city', city), 'from', 'crm'), lower(nm || ' ' || coalesce(mob, '')), (s).uid) returning id into bid;
    perform public.crm_log(s, 'create', 'blueprint', bid, nm);
  else
    select * into old from public.crm_records where id = id_ and kind = 'blueprint' and deleted_at is null;
    if old.id is null or not public.crm_vis(s, old) then raise exception 'Blueprint nahi mila'; end if;
    update public.crm_records set title = nm, mobile = nullif(mob, ''), data = (bp - 'customer') || jsonb_build_object('customer', jsonb_build_object('name', nm, 'mobile', mob, 'city', city), 'lead_id', old.data -> 'lead_id', 'from', old.data -> 'from'),
      search = lower(nm || ' ' || coalesce(mob, '')), updated_at = now() where id = id_;
    bid := id_;
    perform public.crm_log(s, 'update', 'blueprint', bid, nm);
  end if;
  if pid is not null then /* customer pehle se hai: blueprint usi se judta hai, naya lead NAHI banta, flow ka Blueprint step apne aap */
    update public.crm_records set party_id = pid where id = bid;
    perform public.crm_wf_auto_p(pid, 5, 'Blueprint (system)');
    mk := false;
  end if;
  if mk then
    summary := 'Blueprint: ' || coalesce(bp #>> '{site,type}', '-') || ', ' || coalesce(bp #>> '{result,panels}', '0') || ' panels, ' || coalesce(kw::text, '0') || ' kW, structure ' || coalesce(bp #>> '{structure,type}', '-');
    select * into ex from public.crm_records where kind = 'lead' and deleted_at is null and mobile = mob and status not in ('won', 'lost') order by id desc limit 1;
    if ex.id is not null then
      update public.crm_records set data = data || jsonb_build_object('blueprint_id', bid, 'kw', kw, 'note', summary), updated_at = now() where id = ex.id; lid := ex.id;
    else
      insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, due_at, data, search, created_by)
        values ('lead', nm, mob, 'new', (s).uid, (s).uid, public.crm_today(),
          jsonb_build_object('name', nm, 'mobile', mob, 'city', city, 'source', 'Leads from project blueprint', 'kw', kw, 'note', summary, 'blueprint_id', bid, 'address', coalesce(bp #>> '{location,addr}', '')),
          lower(nm || ' ' || mob), (s).uid) returning id into lid;
      perform public.crm_log(s, 'create', 'lead', lid, nm || ' (blueprint)');
    end if;
    update public.crm_records set data = data || jsonb_build_object('lead_id', lid) where id = bid;
  end if;
  return jsonb_build_object('ok', true, 'id', bid, 'lead_id', lid, 'party_id', pid);
end $function$

;

-- 4 koi bhi naya lead: customer ya khuli lead ke mobile par nahi ban sakta (kisi bhi raaste se: form, Excel, manual, blueprint)
create or replace function public.crm_lead_dedupe_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare pt public.crm_records; ex public.crm_records;
begin
  if new.kind <> 'lead' or new.deleted_at is not null or new.status in ('won', 'lost') or coalesce(new.mobile, '') = '' then return new; end if;
  if coalesce(new.data ->> 'intake', '') = 'customer-add' then return new; end if;
  select * into pt from public.crm_records where kind = 'party' and deleted_at is null and mobile = new.mobile and coalesce(data ->> 'type', 'customer') <> 'supplier' order by id limit 1;
  if pt.id is not null then raise exception 'Ye customer pehle se hai: % (ID %) — Customers me jaakar usi ka kaam karein, nayi lead nahi banegi', pt.title, coalesce(pt.data ->> 'cust_id', '#' || pt.id); end if;
  select * into ex from public.crm_records where kind = 'lead' and deleted_at is null and mobile = new.mobile and status not in ('won', 'lost') and id <> coalesce(new.id, 0) order by id limit 1;
  if ex.id is not null then raise exception 'Ye lead pehle se hai: % (ID %) — usi ko kholein', ex.title, coalesce(ex.data ->> 'cust_id', '#' || ex.id); end if;
  return new;
end $$;
drop trigger if exists crm_lead_dedupe on public.crm_records;
create trigger crm_lead_dedupe before insert on public.crm_records for each row when (new.kind = 'lead') execute function public.crm_lead_dedupe_trg();

-- 5 site visit hamesha kisi customer se judti hai (mobile se apne aap judti hai; customer na ho to visit nahi banti)
create or replace function public.crm_visit_party_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare pid bigint;
begin
  if new.kind <> 'reminder' or coalesce(new.data ->> 'type', '') <> 'sitevisit' or new.deleted_at is not null or new.party_id is not null then return new; end if;
  select id into pid from public.crm_records where kind = 'party' and deleted_at is null and mobile = public.crm_mobile(coalesce(new.data ->> 'mobile', new.mobile, '')) order by id limit 1;
  if pid is not null then new.party_id := pid; return new; end if;
  if TG_OP = 'INSERT' then raise exception 'Site visit sirf customer ki hoti hai — pehle Customers me us customer ko jodein / chunein'; end if;
  return new;
end $$;
drop trigger if exists crm_visit_party on public.crm_records;
create trigger crm_visit_party before insert or update on public.crm_records for each row when (new.kind = 'reminder') execute function public.crm_visit_party_trg();

-- 6 Referral plant: customer system me nahi hai to wo bhi ek lead ban kar flow me aata hai (alag "bhoot" customer nahi rehta)
create or replace function public.crm_plant_lead_trg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.kind <> 'plant' or new.deleted_at is not null or new.party_id is not null or coalesce(new.mobile, '') = '' then return new; end if;
  begin
    perform public.crm_inbound_lead(coalesce(new.data ->> 'name', new.title, ''), new.mobile, 'Referral plant', 'Referral plant: ' || coalesce(new.data ->> 'kw', '') || ' kW', jsonb_strip_nulls(jsonb_build_object('city', nullif(new.data ->> 'city', ''), 'address', nullif(new.data ->> 'address', ''), 'kw', nullif(new.data ->> 'kw', ''), 'kind_hint', 'project')));
  exception when others then null; end;
  return new;
end $$;
drop trigger if exists crm_plant_lead on public.crm_records;
create trigger crm_plant_lead after insert on public.crm_records for each row when (new.kind = 'plant') execute function public.crm_plant_lead_trg();

-- 7 crm_save: purani 'won/lost' lead ab nayi lead ko nahi rokti (asli wajah wala saaf message milta hai)
CREATE OR REPLACE FUNCTION public.crm_save(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); k text := p ->> 'kind'; id_ bigint := nullif(p ->> 'id', '')::bigint;
        d jsonb := coalesce(p -> 'data', '{}'::jsonb); old public.crm_records; r public.crm_records; isnew boolean := id_ is null or id_ = 0;
        mob text; em text; ttl text; st text := coalesce(p ->> 'status', ''); asg bigint := nullif(p ->> 'assigned_to', '')::bigint; pid bigint := nullif(p ->> 'party_id', '')::bigint;
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
  em := lower(left(trim(coalesce(d ->> 'email', '')), 160));
  ttl := left(trim(coalesce(d ->> 'name', d ->> 'title', '')), 200);
  owner_ := case when isnew then (s).uid else old.owner_id end;
  if not isnew and pid is null and not (p ? 'party_id') then pid := old.party_id; end if;
  if not isnew and not (p ? 'assigned_to') then asg := old.assigned_to; end if;
  if not isnew and not (p ? 'due_at') then due := old.due_at; end if;

  -- ---------------- per kind rules
  if k = 'party' then
    perform public.crm_need(s, case when isnew then 'customers.create' else 'customers.edit' end);
    if ttl = '' then raise exception 'Customer ka naam likhein'; end if;
    if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein (mobile zaroori hai)'; end if;
    if em <> '' and em !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'Sahi email likhein (ya khali chhodein)'; end if;
    select * into ex from public.crm_records where kind = 'party' and deleted_at is null and mobile = mob and id <> coalesce(id_, 0) limit 1;
    if ex.id is not null then
      if public.crm_vis(s, ex) then raise exception 'Ye customer pehle se list me hai: % (#%)', ex.title, ex.id;
      else raise exception 'Ye customer pehle se % ke paas hai — Admin se transfer karwayein', coalesce(public.crm_uname(ex.owner_id), 'kisi aur'); end if;
    end if;
    if (p ? 'assigned_to') and asg is distinct from (case when isnew then null else old.assigned_to end) then perform public.crm_need(s, 'customers.assign'); end if;
    pid := null; st := coalesce(nullif(st, ''), case when isnew then 'active' else old.status end);
  elsif k = 'item' then
    perform public.crm_need(s, case when isnew then 'items.create' else 'items.edit' end);
    if not isnew and old.data ->> 'fixed' = 'true' and not public.crm_is_admin(s) then raise exception 'Ye Fixed plan hai — sirf Admin iski keemat / kaam ki list badal sakta hai'; end if;
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
    if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein (mobile zaroori hai)'; end if;
    if em <> '' and em !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'Sahi email likhein (ya khali chhodein)'; end if;
    if ttl = '' then ttl := 'Lead ' || mob; end if;
    if (p ? 'assigned_to') and asg is distinct from (case when isnew then null else old.assigned_to end) and asg is distinct from (s).uid then perform public.crm_need(s, 'leads.assign'); end if;
    if isnew and exists (select 1 from public.crm_records where kind = 'lead' and deleted_at is null and status not in ('won', 'lost') and mobile = mob and (owner_id = (s).uid or assigned_to = coalesce(asg, (s).uid))) then
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
    if pid is null and mob <> '' then select id into pid from public.crm_records where kind = 'party' and mobile = mob and deleted_at is null limit 1; end if;
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

  srch := lower(concat_ws(' ', ttl, ref_, mob, em, d ->> 'city', d ->> 'company', d ->> 'gstin', d ->> 'note', d ->> 'type', d ->> 'brand', d ->> 'qtitle', d ->> 'category', d ->> 'subcategory', d ->> 'sku', d ->> 'mpn', d ->> 'source'));
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
end $function$

;


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

-- purane online orders jinka customer nahi bana tha (adhura pata -> lead ban gaye the): ab customer banenge (lead apne aap "won" ho jati hai)
do $$ begin
  if to_regclass('public.sp_orders') is not null then
    perform public.crm_order_customer(o.data, o.id) from public.sp_orders o
      where not exists (select 1 from public.crm_records p where p.kind = 'party' and p.deleted_at is null and p.mobile = public.crm_mobile(coalesce(o.data ->> 'phone', o.data ->> 'mobile', '')))
      order by o.id;
  end if;
end $$;

-- ============================================================================
-- ROUND 43 — purchase price zaroori, role-wise discount, online qty, template reserve (staging only)
-- ============================================================================
create or replace function public.crm_role_discount(r text) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(nullif((select data #>> array['disc_defaults', r] from public.crm_settings where id = 1), '')::numeric,
    case lower(coalesce(r, '')) when 'manager' then 5 when 'staff' then 2.5 else 0 end) $$;

CREATE OR REPLACE FUNCTION public.crm_save(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); k text := p ->> 'kind'; id_ bigint := nullif(p ->> 'id', '')::bigint;
        d jsonb := coalesce(p -> 'data', '{}'::jsonb); old public.crm_records; r public.crm_records; isnew boolean := id_ is null or id_ = 0;
        mob text; em text; ttl text; st text := coalesce(p ->> 'status', ''); asg bigint := nullif(p ->> 'assigned_to', '')::bigint; pid bigint := nullif(p ->> 'party_id', '')::bigint;
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
  em := lower(left(trim(coalesce(d ->> 'email', '')), 160));
  ttl := left(trim(coalesce(d ->> 'name', d ->> 'title', '')), 200);
  owner_ := case when isnew then (s).uid else old.owner_id end;
  if not isnew and pid is null and not (p ? 'party_id') then pid := old.party_id; end if;
  if not isnew and not (p ? 'assigned_to') then asg := old.assigned_to; end if;
  if not isnew and not (p ? 'due_at') then due := old.due_at; end if;

  -- ---------------- per kind rules
  if k = 'party' then
    perform public.crm_need(s, case when isnew then 'customers.create' else 'customers.edit' end);
    if ttl = '' then raise exception 'Customer ka naam likhein'; end if;
    if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein (mobile zaroori hai)'; end if;
    if em <> '' and em !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'Sahi email likhein (ya khali chhodein)'; end if;
    select * into ex from public.crm_records where kind = 'party' and deleted_at is null and mobile = mob and id <> coalesce(id_, 0) limit 1;
    if ex.id is not null then
      if public.crm_vis(s, ex) then raise exception 'Ye customer pehle se list me hai: % (#%)', ex.title, ex.id;
      else raise exception 'Ye customer pehle se % ke paas hai — Admin se transfer karwayein', coalesce(public.crm_uname(ex.owner_id), 'kisi aur'); end if;
    end if;
    if (p ? 'assigned_to') and asg is distinct from (case when isnew then null else old.assigned_to end) then perform public.crm_need(s, 'customers.assign'); end if;
    pid := null; st := coalesce(nullif(st, ''), case when isnew then 'active' else old.status end);
  elsif k = 'item' then
    perform public.crm_need(s, case when isnew then 'items.create' else 'items.edit' end);
    if not isnew and old.data ->> 'fixed' = 'true' and not public.crm_is_admin(s) then raise exception 'Ye Fixed plan hai — sirf Admin iski keemat / kaam ki list badal sakta hai'; end if;
    if ttl = '' then raise exception 'Item ka naam likhein'; end if;
    amt := public.crm_num(d -> 'price'); mob := null; pid := null;
    if not public.crm_can(s, 'items.cost') and not isnew then d := d || jsonb_build_object('cost_price', old.data -> 'cost_price', 'min_price', old.data -> 'min_price'); end if;
    -- online store status: only the review flow can publish
    if not isnew then d := jsonb_set(d, '{store}', coalesce(old.data -> 'store', '{}'::jsonb) || (coalesce(d -> 'store', '{}'::jsonb) - 'status' - 'store_id' - 'reviewed_at')); end if;
    if isnew then d := jsonb_set(d, '{store}', (coalesce(d -> 'store', '{}'::jsonb) - 'store_id' - 'reviewed_at') || '{"status":"none"}'::jsonb); end if;
    d := public.crm_item_prep(isnew, case when isnew then null else old.data end, d);   -- Round 13: auto SKU (immutable), project line SKUs
    if coalesce(d ->> 'type', 'product') = 'product' then   -- Round 43: kharid rate (purchase price) zaroori
      if public.crm_num(d -> 'cost_price') > 0 then d := d - 'cost_missing';
      elsif isnew and public.crm_can(s, 'items.cost') and coalesce(d ->> 'cost_ok', '') <> 'true' then raise exception 'Kharid rate (purchase price) zaroori hai — pehle likhein';
      else d := d || '{"cost_missing":true}'::jsonb; end if;
    end if;
    d := d - 'cost_ok';
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
          if it.id is not null and public.crm_num(it.data -> 'cost_price') > 0 and public.crm_num(l -> 'price') < public.crm_num(it.data -> 'cost_price') - 0.009 then
            raise exception '"%" ka rate kharid rate (%) se kam nahi ho sakta', it.title, public.crm_num(it.data -> 'cost_price'); end if;
          if it.id is not null and public.crm_num(it.data -> 'min_price') > 0 and public.crm_num(l -> 'price') < public.crm_num(it.data -> 'min_price') then
            raise exception '"%" ka rate minimum rate se kam hai — Admin se permission lein', it.title; end if;
        end if;
      end loop;
      select coalesce(nullif(public.crm_num(meta -> 'max_discount_pct'), 0), public.crm_role_discount(role)) into lim from public.crm_users where id = (s).uid;
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
    if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein (mobile zaroori hai)'; end if;
    if em <> '' and em !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'Sahi email likhein (ya khali chhodein)'; end if;
    if ttl = '' then ttl := 'Lead ' || mob; end if;
    if (p ? 'assigned_to') and asg is distinct from (case when isnew then null else old.assigned_to end) and asg is distinct from (s).uid then perform public.crm_need(s, 'leads.assign'); end if;
    if isnew and exists (select 1 from public.crm_records where kind = 'lead' and deleted_at is null and status not in ('won', 'lost') and mobile = mob and (owner_id = (s).uid or assigned_to = coalesce(asg, (s).uid))) then
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
    if pid is null and mob <> '' then select id into pid from public.crm_records where kind = 'party' and mobile = mob and deleted_at is null limit 1; end if;
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

  srch := lower(concat_ws(' ', ttl, ref_, mob, em, d ->> 'city', d ->> 'company', d ->> 'gstin', d ->> 'note', d ->> 'type', d ->> 'brand', d ->> 'qtitle', d ->> 'category', d ->> 'subcategory', d ->> 'sku', d ->> 'mpn', d ->> 'source'));
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
end $function$

;


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
create or replace function public.crm_items_bulk_add(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r jsonb; added int := 0; skipped int := 0; bad jsonb := '[]'::jsonb; sk text;
begin
  perform public.crm_need(s, 'items.create');
  if jsonb_typeof(p -> 'rows') <> 'array' then raise exception 'Rows nahi mili'; end if;
  if jsonb_array_length(p -> 'rows') > 600 then raise exception 'Ek baar me 600 se zyada nahi'; end if;
  for r in select * from jsonb_array_elements(p -> 'rows') loop
    sk := nullif(r ->> 'seed_key', '');
    if sk is not null and exists (select 1 from public.crm_records where kind = 'item' and deleted_at is null and data ->> 'seed_key' = sk) then skipped := skipped + 1; continue; end if;
    begin
      perform public.crm_save(jsonb_build_object('token', p ->> 'token', 'kind', 'item', 'data', r || '{"cost_ok":"true"}'::jsonb));
      added := added + 1;
    exception when others then bad := bad || to_jsonb(coalesce(r ->> 'name', '?') || ': ' || sqlerrm);
    end;
  end loop;
  perform public.crm_log(s, 'import', 'item', 0, 'Bulk add: ' || added || ' items, skipped ' || skipped);
  return jsonb_build_object('ok', true, 'added', added, 'skipped', skipped, 'failed', bad);
end $$;
create or replace function public.crm_to_store(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records; q numeric := public.crm_num(p -> 'qty'); onh numeric; res numeric; fr numeric; hs jsonb; typ text;
begin
  perform public.crm_need(s, 'items.to_store');
  select * into r from public.crm_records where id = (p ->> 'id')::bigint and kind = 'item' and deleted_at is null;
  if r.id is null then raise exception 'Item nahi mila'; end if;
  typ := coalesce(r.data ->> 'type', 'product');
  if typ not in ('product', 'project') then raise exception 'Sirf product ya project online store ko bheja ja sakta hai'; end if;
  if typ = 'product' and public.crm_num(r.data -> 'cost_price') <= 0 then raise exception '"%": pehle Kharid rate (purchase price) likhein, tabhi online bhej sakte hain', r.title; end if;
  hs := coalesce(r.data -> 'holds', '[]'::jsonb);
  if typ = 'product' and q > 0 then
    if not (r.data ? 'stock') then raise exception '"%": stock track nahi hota — pehle Stock bharein', r.title; end if;
    hs := coalesce((select jsonb_agg(h) from jsonb_array_elements(hs) h where h ->> 'id' <> 'auto-store'), '[]'::jsonb);
    onh := public.crm_num(r.data -> 'stock'); select coalesce(sum(z.qty), 0) into res from public.crm_reserves(null) z where z.item_id = r.id;
    fr := onh - res - (select coalesce(sum(public.crm_num(h -> 'qty')), 0) from jsonb_array_elements(hs) h where coalesce(h ->> 'until', '') = '' or (h ->> 'until') >= public.crm_today()::text);
    if q > fr + 0.0001 then raise exception '"%": itna stock free nahi hai (free: %)', r.title, greatest(fr, 0); end if;
    hs := hs || jsonb_build_array(jsonb_build_object('id', 'auto-store', 'type', 'online', 'qty', q, 'for', 'Online Store (auto)', 'until', '', 'note', 'CRM se online ke liye diya', 'by', (s).name, 'on', public.crm_today()::text));
  end if;
  update public.crm_records set data = jsonb_set(jsonb_set(data, '{store}', coalesce(data -> 'store', '{}'::jsonb) || jsonb_build_object('status', 'pending', 'sent_at', now(), 'sent_by', (s).name, 'online_qty', case when q > 0 then q else null end)), '{holds}', hs), updated_at = now() where id = r.id;
  perform public.crm_log(s, 'to_store', 'item', r.id, 'Online Store Admin ko bheja: ' || r.title || case when q > 0 then ' (online qty ' || q || ')' else '' end);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.crm_tpl_reserves() returns table(item_id bigint, qty numeric, tpl_id bigint, tpl text)
language sql stable security definer set search_path = public as $$
  select (x ->> 'item_id')::bigint, public.crm_num(x -> 'qty'), t.id, t.title
  from public.crm_records t, jsonb_array_elements(coalesce(t.data -> 'proj_items', '[]'::jsonb)) x
  where t.kind = 'item' and t.deleted_at is null and t.status <> 'inactive' and t.data ->> 'type' = 'project' and coalesce(x ->> 'item_id', '') ~ '^[0-9]+$' $$;

create or replace function public.crm_stock_report(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pct numeric := public.crm_online_pct(); rows jsonb; projs jsonb; tot jsonb;
begin
  perform public.crm_need(s, 'stock.view');
  perform public.crm_quote_expire_daily();
  with it as (
    select r.id, r.title, r.data d, public.crm_num(r.data -> 'stock') onh from public.crm_records r
    where r.kind = 'item' and r.deleted_at is null and coalesce(r.data ->> 'type', 'product') = 'product' and r.data ? 'stock' and r.status <> 'inactive'
  ), rs as (select item_id, sum(qty) q from public.crm_reserves(null) group by item_id),
  tr as (select item_id, sum(qty) q from public.crm_tpl_reserves() group by item_id),
  sold as (
    select i.item_id, sum(i.qty) q from (
      select (l ->> 'item_id')::bigint item_id, public.crm_num(l -> 'qty') qty from public.crm_records v, jsonb_array_elements(coalesce(v.data -> 'lines', '[]'::jsonb)) l
        where v.kind = 'invoice' and v.deleted_at is null and coalesce(l ->> 'kind', 'product') <> 'project' and coalesce(l ->> 'item_id', '') ~ '^[0-9]+$'
      union all
      select (x ->> 'item_id')::bigint, public.crm_num(x -> 'qty') * greatest(public.crm_num(l -> 'qty'), 1) from public.crm_records v, jsonb_array_elements(coalesce(v.data -> 'lines', '[]'::jsonb)) l, jsonb_array_elements(coalesce(l -> 'proj_items', '[]'::jsonb)) x
        where v.kind = 'invoice' and v.deleted_at is null and coalesce(l ->> 'kind', 'product') = 'project' and coalesce(x ->> 'item_id', '') ~ '^[0-9]+$') i group by i.item_id
  ), calc as (
    select it.id, it.title, it.d, it.onh, coalesce(rs.q, 0) rq, coalesce(tr.q, 0) tq, coalesce(sold.q, 0) sq, public.crm_holds_sum(it.d, false) hoff, public.crm_holds_sum(it.d, true) hon from it left join rs on rs.item_id = it.id left join tr on tr.item_id = it.id left join sold on sold.item_id = it.id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'sku', d ->> 'sku', 'name', title, 'brand', d ->> 'brand', 'category', d ->> 'category', 'subcategory', d ->> 'subcategory', 'unit', coalesce(d ->> 'unit', 'Nos'),
      'on_hand', onh, 'sold', sq, 'total', onh + sq, 'reserved_quote', rq, 'reserved_tpl', tq, 'cost_missing', (d ->> 'cost_price') is null or public.crm_num(d -> 'cost_price') <= 0, 'online_qty', hon, 'free_after_tpl', greatest(onh - rq - hoff - hon - tq, 0), 'hold_offline', hoff, 'hold_online', hon,
      'offline_cap', onh - floor(onh * pct / 100), 'free_offline', greatest((onh - floor(onh * pct / 100)) - rq - hoff, 0), 'free_total', greatest(onh - rq - hoff - hon, 0),
      'online_left_pct', case when onh > 0 then round(100 * greatest(onh - rq - hoff, 0) / onh, 1) else 0 end,
      'level', case when onh <= 0 then 'out' when 100 * (onh - rq - hoff) / onh < pct then 'low' else 'ok' end,
      'price', public.crm_num(d -> 'price'),
      'for', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select jsonb_build_object('t', 'quote', 'ref', z.ref, 'who', z.customer, 'title', z.qtitle, 'qty', z.qty, 'till', z.valid_till, 'qid', z.quote_id, 'st', z.qstatus) x from public.crm_reserves(null) z where z.item_id = calc.id
          union all select jsonb_build_object('t', 'tpl', 'tid', z.tpl_id, 'who', z.tpl, 'qty', z.qty) from public.crm_tpl_reserves() z where z.item_id = calc.id
          union all select jsonb_build_object('t', 'hold', 'hid', h ->> 'id', 'type', h ->> 'type', 'who', h ->> 'for', 'qty', public.crm_num(h -> 'qty'), 'till', h ->> 'until', 'note', h ->> 'note')
            from jsonb_array_elements(coalesce(d -> 'holds', '[]'::jsonb)) h where coalesce(h ->> 'until', '') = '' or (h ->> 'until') >= public.crm_today()::text) q)
    ) order by (d ->> 'category'), title), '[]'::jsonb) into rows from calc;
  select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'sku', r.data ->> 'sku', 'name', r.title, 'live', (r.data #>> '{store,status}') = 'published', 'qty', public.crm_num(r.data -> 'price'),
      'buildable', (select min(floor(public.crm_num(i2.data -> 'stock') / greatest(public.crm_num(x -> 'qty'), 0.0001))) from jsonb_array_elements(coalesce(r.data -> 'proj_items', '[]'::jsonb)) x join public.crm_records i2 on i2.id = nullif(x ->> 'item_id', '')::bigint and i2.kind = 'item' and i2.data ? 'stock'),
      'risky', (select coalesce(jsonb_agg(i2.title), '[]'::jsonb) from jsonb_array_elements(coalesce(r.data -> 'proj_items', '[]'::jsonb)) x join public.crm_records i2 on i2.id = nullif(x ->> 'item_id', '')::bigint and i2.kind = 'item' and i2.data ? 'stock'
          where public.crm_num(i2.data -> 'stock') <= 0 or 100 * (public.crm_num(i2.data -> 'stock') - coalesce((select sum(z.qty) from public.crm_reserves(null) z where z.item_id = i2.id), 0) - public.crm_holds_sum(i2.data, false)) / nullif(public.crm_num(i2.data -> 'stock'), 0) < pct))
    order by r.id desc), '[]'::jsonb) into projs from public.crm_records r where r.kind = 'item' and r.deleted_at is null and r.data ->> 'type' = 'project' and r.status <> 'inactive';
  return jsonb_build_object('ok', true, 'pct', pct, 'rows', rows, 'projects', projs,
    'untracked', (select count(*) from public.crm_records r where r.kind = 'item' and r.deleted_at is null and coalesce(r.data ->> 'type', 'product') = 'product' and not (r.data ? 'stock')),
    'alerts', (select count(*) from jsonb_array_elements(rows) x where x ->> 'level' in ('low', 'out')));
end $$;
do $$ begin revoke execute on function public.crm_role_discount(text), public.crm_tpl_reserves() from public, anon, authenticated; exception when others then null; end $$;

-- ============================================================================
-- ROUND 44 — Online pool (Web Shop + Store App), channel-wise qty, last-unit guard, add more qty, template lock (staging only)
--   Model: item.data.store.online = {web, app, since, show_stock?}. pool = web + app (cumulative allocation).
--   Left(channel) = allocation - open orders - shipped/delivered orders since `since`. Inventory hold ("auto-store" / "auto-t<template id>") = pool - sold.
-- ============================================================================
create or replace function public.sp_order_channel(d jsonb) returns text language sql immutable as $$
  select case when coalesce(d ->> 'channel', '') = 'shop' or coalesce(d ->> 'src', '') = 'shop' then 'web' else 'app' end $$;

create or replace function public.sp_online_counts(p_store_id text, p_since timestamptz)
returns table(open_web numeric, open_app numeric, sold_web numeric, sold_app numeric)
language sql stable security definer set search_path = public as $$
  select coalesce(sum(m.q) filter (where m.opn and m.ch = 'web'), 0), coalesce(sum(m.q) filter (where m.opn and m.ch = 'app'), 0),
         coalesce(sum(m.q) filter (where m.sld and m.ch = 'web'), 0), coalesce(sum(m.q) filter (where m.sld and m.ch = 'app'), 0)
  from (
    select greatest(public.crm_num(i -> 'qty'), 1) q, public.sp_order_channel(o.data) ch,
           (o.status in ('new', 'paid', 'confirmed') and coalesce(o.data ->> 'payment_status', '') <> 'rejected'
             and (coalesce(o.data ->> 'payment_status', '') <> 'awaiting_payment' or coalesce(o.data ->> 'payment', '') = 'cod' or o.created_at > now() - interval '48 hours')) opn,
           (o.status in ('shipped', 'delivered')) sld
      from public.sp_orders o, jsonb_array_elements(case when jsonb_typeof(o.data -> 'items') = 'array' then o.data -> 'items' else '[]'::jsonb end) i
     where (i ->> 'id') = p_store_id and o.created_at >= p_since
  ) m $$;

-- free quantity of one CRM item (stock - quotation reserves - holds), ignoring the hold with id p_skip
create or replace function public.crm_item_free(p_item bigint, p_skip text default null) returns numeric language sql stable security definer set search_path = public as $$
  select case when not (r.data ? 'stock') or coalesce(r.data ->> 'stock', '') = '' then null
    else public.crm_num(r.data -> 'stock') - coalesce((select sum(z.qty) from public.crm_reserves(null) z where z.item_id = r.id), 0)
         - (select coalesce(sum(public.crm_num(h -> 'qty')), 0) from jsonb_array_elements(coalesce(r.data -> 'holds', '[]'::jsonb)) h
             where (h ->> 'id') is distinct from p_skip and (coalesce(h ->> 'until', '') = '' or (h ->> 'until') >= public.crm_today()::text)) end
  from public.crm_records r where r.id = p_item and r.kind = 'item' $$;

create or replace function public.crm_hold_put(p_item bigint, p_id text, p_qty numeric, p_for text) returns void language plpgsql security definer set search_path = public as $$
declare hs jsonb;
begin
  select coalesce(data -> 'holds', '[]'::jsonb) into hs from public.crm_records where id = p_item and kind = 'item' for update;
  if not found then return; end if;
  hs := coalesce((select jsonb_agg(h) from jsonb_array_elements(hs) h where h ->> 'id' <> p_id), '[]'::jsonb);
  if p_qty > 0 then hs := hs || jsonb_build_array(jsonb_build_object('id', p_id, 'type', 'online', 'qty', p_qty, 'for', p_for, 'until', '', 'note', 'Online Store (auto)', 'by', 'system', 'on', public.crm_today()::text)); end if;
  update public.crm_records set data = jsonb_set(data, '{holds}', hs) where id = p_item;
end $$;

create or replace function public.crm_online_state(p_item bigint) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare it public.crm_records; o jsonb; sid text; w numeric; a numeric; c record; lw numeric; la numeric;
begin
  select * into it from public.crm_records where id = p_item and kind = 'item';
  o := it.data #> '{store,online}'; if o is null then return null; end if;
  sid := coalesce(it.data #>> '{store,store_id}', '__none__'); w := public.crm_num(o -> 'web'); a := public.crm_num(o -> 'app');
  select * into c from public.sp_online_counts(sid, coalesce(nullif(o ->> 'since', '')::timestamptz, '-infinity'::timestamptz));
  lw := greatest(w - c.open_web - c.sold_web, 0); la := greatest(a - c.open_app - c.sold_app, 0);
  return jsonb_build_object('web', w, 'app', a, 'pool', w + a, 'open_web', c.open_web, 'open_app', c.open_app, 'sold_web', c.sold_web, 'sold_app', c.sold_app,
    'left_web', lw, 'left_app', la, 'left_total', lw + la, 'sold', c.sold_web + c.sold_app, 'remaining', greatest(w + a - c.sold_web - c.sold_app, 0));
end $$;

-- makes the inventory holds equal to what is still reserved for online (products: own hold; templates: one hold on every sub-item)
create or replace function public.crm_online_sync(p_item bigint) returns void language plpgsql security definer set search_path = public as $$
declare it public.crm_records; st jsonb; rem numeric := 0; x jsonb;
begin
  select * into it from public.crm_records where id = p_item and kind = 'item'; if it.id is null then return; end if;
  st := public.crm_online_state(p_item); if st is not null then rem := (st ->> 'remaining')::numeric; end if;
  if coalesce(it.data ->> 'type', 'product') = 'project' then
    for x in select * from jsonb_array_elements(coalesce(it.data -> 'proj_items', '[]'::jsonb)) loop
      if coalesce(x ->> 'item_id', '') ~ '^[0-9]+$' then perform public.crm_hold_put((x ->> 'item_id')::bigint, 'auto-t' || p_item, rem * public.crm_num(x -> 'qty'), 'Template: ' || it.title); end if;
    end loop;
  else
    perform public.crm_hold_put(p_item, 'auto-store', rem, 'Online Store (auto)');
  end if;
end $$;

-- mode: set (absolute web / app) | add (increase) | off (remove from online pool). Checks free inventory.
create or replace function public.crm__online_apply(p_item bigint, p_mode text, p_web numeric, p_app numeric) returns jsonb language plpgsql security definer set search_path = public as $$
declare it public.crm_records; o jsonb; st jsonb; w numeric; a numeric; sold numeric; used_w numeric; used_a numeric; newrem numeric; x jsonb; fr numeric; typ text; sid text; nm text;
begin
  select * into it from public.crm_records where id = p_item and kind = 'item' and deleted_at is null for update;
  if it.id is null then raise exception 'Item nahi mila'; end if;
  typ := coalesce(it.data ->> 'type', 'product'); if typ not in ('product', 'project') then raise exception 'Sirf product ya template online ja sakta hai'; end if;
  o := it.data #> '{store,online}'; st := public.crm_online_state(p_item);
  if p_mode = 'off' then
    update public.crm_records set data = jsonb_set(data, '{store}', coalesce(data -> 'store', '{}'::jsonb) - 'online') where id = p_item;
    perform public.crm_online_sync(p_item); return jsonb_build_object('ok', true);
  end if;
  w := case when p_mode = 'add' then coalesce(public.crm_num(o -> 'web'), 0) + greatest(coalesce(p_web, 0), 0) else greatest(coalesce(p_web, 0), 0) end;
  a := case when p_mode = 'add' then coalesce(public.crm_num(o -> 'app'), 0) + greatest(coalesce(p_app, 0), 0) else greatest(coalesce(p_app, 0), 0) end;
  if p_mode not in ('set', 'add') then raise exception 'Galat kaam'; end if;
  if w + a <= 0 then raise exception 'Web Shop ya Store App ke liye qty likhein'; end if;
  if w <> floor(w) or a <> floor(a) then raise exception 'Qty poori sankhya me likhein'; end if;
  if st is not null then
    used_w := (st ->> 'open_web')::numeric + (st ->> 'sold_web')::numeric; used_a := (st ->> 'open_app')::numeric + (st ->> 'sold_app')::numeric;
    if w < used_w then raise exception 'Web Shop ki qty % se kam nahi ho sakti (itna bik chuka / order me hai)', used_w; end if;
    if a < used_a then raise exception 'Store App ki qty % se kam nahi ho sakti (itna bik chuka / order me hai)', used_a; end if;
    sold := (st ->> 'sold')::numeric;
  else sold := 0; end if;
  newrem := w + a - sold; nm := it.title;
  if typ = 'product' then
    if (it.data ? 'stock') and coalesce(it.data ->> 'stock', '') <> '' then
      fr := public.crm_item_free(p_item, 'auto-store');
      if newrem > fr + 0.0001 then raise exception '"%": itna free stock nahi hai (free: %). Pehle Inventory me stock badhayein.', nm, greatest(fr, 0); end if;
    end if;
  else
    for x in select * from jsonb_array_elements(coalesce(it.data -> 'proj_items', '[]'::jsonb)) loop
      if coalesce(x ->> 'item_id', '') ~ '^[0-9]+$' then
        fr := public.crm_item_free((x ->> 'item_id')::bigint, 'auto-t' || p_item);
        if fr is not null and newrem * public.crm_num(x -> 'qty') > fr + 0.0001 then
          raise exception 'Template "%": "%" ka free stock kam hai (chahiye %, free %). Pehle Inventory me stock badhayein.', nm, coalesce(x ->> 'name', '?'), newrem * public.crm_num(x -> 'qty'), greatest(fr, 0); end if;
      end if;
    end loop;
  end if;
  update public.crm_records set data = jsonb_set(data, '{store}', coalesce(data -> 'store', '{}'::jsonb)
      || jsonb_build_object('online', coalesce(o, '{}'::jsonb) || jsonb_build_object('web', w, 'app', a, 'since', coalesce(o ->> 'since', now()::text)))), updated_at = now() where id = p_item;
  perform public.crm_online_sync(p_item);
  return jsonb_build_object('ok', true, 'state', public.crm_online_state(p_item));
end $$;
do $$ begin revoke execute on function public.crm__online_apply(bigint, text, numeric, numeric), public.crm_online_sync(bigint), public.crm_hold_put(bigint, text, numeric, text), public.crm_item_free(bigint, text), public.crm_online_state(bigint), public.sp_online_counts(text, timestamptz) from public, anon, authenticated; exception when others then null; end $$;

-- CRM: send to Online Store with web / app qty (products with tracked stock and templates need qty)
create or replace function public.crm_to_store(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records; typ text; w numeric; a numeric; tracked boolean; has_o boolean; res jsonb;
begin
  perform public.crm_need(s, 'items.to_store');
  select * into r from public.crm_records where id = (p ->> 'id')::bigint and kind = 'item' and deleted_at is null;
  if r.id is null then raise exception 'Item nahi mila'; end if;
  typ := coalesce(r.data ->> 'type', 'product');
  if typ not in ('product', 'project') then raise exception 'Sirf product ya project online store ko bheja ja sakta hai'; end if;
  if typ = 'product' and public.crm_num(r.data -> 'cost_price') <= 0 then raise exception '"%": pehle Kharid rate (purchase price) likhein, tabhi online bhej sakte hain', r.title; end if;
  tracked := typ = 'project' or ((r.data ? 'stock') and coalesce(r.data ->> 'stock', '') <> '');
  has_o := r.data #> '{store,online}' is not null;
  w := public.crm_num(p -> 'web'); a := public.crm_num(p -> 'app');
  if w + a = 0 and public.crm_num(p -> 'qty') > 0 then w := public.crm_num(p -> 'qty'); end if;
  if w + a > 0 then res := public.crm__online_apply(r.id, 'set', w, a);
  elsif tracked and not has_o then raise exception '"%": Web Shop / Store App ke liye qty likhein (kitna online bechna hai)', r.title; end if;
  update public.crm_records set data = jsonb_set(data, '{store}', coalesce(data -> 'store', '{}'::jsonb) || jsonb_build_object('status', 'pending', 'sent_at', now(), 'sent_by', (s).name)), updated_at = now() where id = r.id;
  perform public.crm_log(s, 'to_store', 'item', r.id, 'Online Store Admin ko bheja: ' || r.title || case when w + a > 0 then ' (web ' || w || ', app ' || a || ')' else '' end);
  return jsonb_build_object('ok', true);
end $$;

-- CRM Online list: set / add / move / off
create or replace function public.crm_online_set(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); op text := coalesce(p ->> 'op', 'set'); it public.crm_records; st jsonb; q numeric; res jsonb; fromc text; toc text;
begin
  perform public.crm_need(s, 'items.to_store');
  select * into it from public.crm_records where id = (p ->> 'id')::bigint and kind = 'item' and deleted_at is null;
  if it.id is null then raise exception 'Item nahi mila'; end if;
  if op = 'move' then
    st := public.crm_online_state(it.id); if st is null then raise exception 'Ye item online pool me nahi hai'; end if;
    fromc := case when p ->> 'from' = 'web' then 'web' else 'app' end; toc := case when fromc = 'web' then 'app' else 'web' end; q := public.crm_num(p -> 'qty');
    if q <= 0 then raise exception 'Qty likhein'; end if;
    if q > (st ->> ('left_' || fromc))::numeric then raise exception '% me sirf % bacha hai — utna hi hissa badla ja sakta hai', case when fromc = 'web' then 'Web Shop' else 'Store App' end, st ->> ('left_' || fromc); end if;
    res := public.crm__online_apply(it.id, 'set', (st ->> 'web')::numeric + case when toc = 'web' then q else -q end, (st ->> 'app')::numeric + case when toc = 'app' then q else -q end);
  elsif op = 'add' then res := public.crm__online_apply(it.id, 'add', public.crm_num(p -> 'web'), public.crm_num(p -> 'app'));
  elsif op = 'set' then res := public.crm__online_apply(it.id, 'set', public.crm_num(p -> 'web'), public.crm_num(p -> 'app'));
  elsif op = 'off' then res := public.crm__online_apply(it.id, 'off', 0, 0);
  else raise exception 'Galat kaam'; end if;
  perform public.crm_log(s, 'edit', 'item', it.id, 'Online qty (' || op || '): ' || it.title);
  return res;
end $$;

create or replace function public.crm_online_list(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); rows jsonb;
begin
  perform public.crm_need(s, 'items.view');
  select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'sku', r.data ->> 'sku', 'name', r.title, 'type', coalesce(r.data ->> 'type', 'product'), 'status', coalesce(r.data #>> '{store,status}', 'none'),
      'store_id', r.data #>> '{store,store_id}', 'price', public.crm_num(r.data -> 'price'), 'gst', public.crm_num(r.data -> 'gst'), 'kw', r.data ->> 'kw', 'inactive', r.status = 'inactive',
      'online', public.crm_online_state(r.id), 'cost_missing', coalesce(r.data ->> 'type', 'product') = 'product' and public.crm_num(r.data -> 'cost_price') <= 0,
      'stock', r.data -> 'stock',
      'free', case when coalesce(r.data ->> 'type', 'product') = 'project'
                then (select min(floor(f / greatest(public.crm_num(x -> 'qty'), 0.0001))) from (select x, public.crm_item_free((x ->> 'item_id')::bigint, 'auto-t' || r.id) f from jsonb_array_elements(coalesce(r.data -> 'proj_items', '[]'::jsonb)) x where coalesce(x ->> 'item_id', '') ~ '^[0-9]+$') q where f is not null)
                else public.crm_item_free(r.id, 'auto-store') end,
      'items', case when coalesce(r.data ->> 'type', 'product') = 'project' then jsonb_array_length(coalesce(r.data -> 'proj_items', '[]'::jsonb)) end,
      'sent_at', r.data #>> '{store,sent_at}') order by r.updated_at desc), '[]'::jsonb) into rows
  from public.crm_records r where r.kind = 'item' and r.deleted_at is null and coalesce(r.data ->> 'type', 'product') in ('product', 'project')
    and (coalesce(r.data #>> '{store,status}', 'none') in ('pending', 'published', 'rejected') or r.data #> '{store,online}' is not null);
  return jsonb_build_object('ok', true, 'rows', rows);
end $$;
grant execute on function public.crm_online_set(jsonb), public.crm_online_list(jsonb) to anon, authenticated;
grant execute on function public.crm_to_store(jsonb) to anon, authenticated;

-- public: what is left online for the given store product ids (Web Shop shows left_web, Store App shows left_app)
create or replace function public.sp_online_left(p_ids jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r record; out jsonb := '{}'::jsonb; st jsonb;
begin
  if jsonb_typeof(p_ids) <> 'array' or jsonb_array_length(p_ids) > 400 then return '{}'::jsonb; end if;
  for r in select c.id, c.data #>> '{store,store_id}' sid from public.crm_records c
            where c.kind = 'item' and c.deleted_at is null and c.data #> '{store,online}' is not null and (c.data #>> '{store,store_id}') in (select jsonb_array_elements_text(p_ids)) loop
    st := public.crm_online_state(r.id);
    out := out || jsonb_build_object(r.sid, jsonb_build_object('web', st -> 'left_web', 'app', st -> 'left_app'));
  end loop;
  return out;
end $$;
grant execute on function public.sp_online_left(jsonb) to anon, authenticated;

-- Admin panel: state of every online item + add more qty from inventory
create or replace function public.sp_admin_online_state(p_pass text) returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare r record; out jsonb := '{}'::jsonb; st jsonb;
begin
  perform public.sp_check(p_pass);
  for r in select c.id, c.data #>> '{store,store_id}' sid, c.title, coalesce(c.data ->> 'type', 'product') typ from public.crm_records c
            where c.kind = 'item' and c.deleted_at is null and c.data #> '{store,online}' is not null and coalesce(c.data #>> '{store,store_id}', '') <> '' loop
    st := public.crm_online_state(r.id);
    out := out || jsonb_build_object(r.sid, st || jsonb_build_object('crm_id', r.id, 'type', r.typ, 'name', r.title, 'free', case when r.typ = 'project' then null else public.crm_item_free(r.id, 'auto-store') end));
  end loop;
  return out;
end $$;
create or replace function public.sp_admin_online_add(p_pass text, p_store_id text, p_web numeric, p_app numeric) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare it public.crm_records;
begin
  perform public.sp_check(p_pass);
  select * into it from public.crm_records where kind = 'item' and deleted_at is null and (data #>> '{store,store_id}') = p_store_id and data #> '{store,online}' is not null order by id limit 1;
  if it.id is null then raise exception 'Ye product CRM ki online list me nahi hai'; end if;
  return public.crm__online_apply(it.id, 'add', p_web, p_app);
end $$;
revoke all on function public.sp_admin_online_state(text), public.sp_admin_online_add(text, text, numeric, numeric) from public;
grant execute on function public.sp_admin_online_state(text), public.sp_admin_online_add(text, text, numeric, numeric) to anon, authenticated;

-- shipped / cancelled orders change what is left: keep inventory holds in step
create or replace function public.sp_orders_online_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if new.status is distinct from old.status then
    for r in select distinct c.id from jsonb_array_elements(case when jsonb_typeof(new.data -> 'items') = 'array' then new.data -> 'items' else '[]'::jsonb end) i
              join public.crm_records c on c.kind = 'item' and c.deleted_at is null and (c.data #>> '{store,store_id}') = (i ->> 'id') and c.data #> '{store,online}' is not null loop
      perform public.crm_online_sync(r.id);
    end loop;
  end if;
  return new;
end $$;
drop trigger if exists sp_orders_online on public.sp_orders;
create trigger sp_orders_online after update of status on public.sp_orders for each row execute function public.sp_orders_online_trg();

-- deleting an item releases its online holds
create or replace function public.crm_item_online_cleanup_trg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.kind = 'item' and new.deleted_at is not null and old.deleted_at is null and new.data #> '{store,online}' is not null then
    update public.crm_records set data = jsonb_set(data, '{store}', coalesce(data -> 'store', '{}'::jsonb) - 'online') where id = new.id;
    perform public.crm_online_sync(new.id);
  end if;
  return null;
end $$;
drop trigger if exists crm_item_online_cleanup on public.crm_records;
create trigger crm_item_online_cleanup after update of deleted_at on public.crm_records for each row execute function public.crm_item_online_cleanup_trg();

drop function if exists public.sp_stock_guard(jsonb);
create or replace function public.sp_stock_guard(p_items jsonb, p_channel text default null) returns void language plpgsql security definer set search_path = public as $$
declare r record; it public.crm_records; res numeric; fr numeric; msg text := ''; i jsonb; oi public.crm_records; st jsonb; need numeric; lc numeric;
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
  -- Round 44: online pool (web / app allocation) — products and templates linked to CRM with an online qty
  for i in select * from jsonb_array_elements(case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end) loop
    select * into oi from public.crm_records c where c.kind = 'item' and c.deleted_at is null and (c.data #>> '{store,store_id}') = (i ->> 'id') and c.data #> '{store,online}' is not null order by c.id limit 1 for update;
    if oi.id is null then continue; end if;
    st := public.crm_online_state(oi.id); need := greatest(public.crm_num(i -> 'qty'), 1);
    lc := case when p_channel = 'web' then (st ->> 'left_web')::numeric when p_channel = 'app' then (st ->> 'left_app')::numeric else (st ->> 'left_total')::numeric end;
    if need > lc + 0.0001 then
      msg := msg || coalesce(nullif(oi.data ->> 'titleEn', ''), nullif(oi.data ->> 'title', ''), nullif(oi.data ->> 'name', ''), oi.title, 'item') || ' (' || case when lc >= 1 then 'sirf ' || floor(lc) || ' bacha' else 'abhi stock mein nahi' end || '); ';
    end if;
  end loop;
  if msg <> '' then raise exception 'OUT_OF_STOCK: %', left(msg, 300); end if;
end $$;
revoke all on function public.sp_stock_guard(jsonb, text) from public, anon, authenticated;

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
  perform public.sp_stock_guard(p_order -> 'items', public.sp_order_channel(p_order));

  -- identity always comes from the account, never from the browser
  o := (p_order - 'token' - 'customer_id')
       || jsonb_build_object(
            'name', left(coalesce(nullif(trim(u.name), ''), trim(p_order->>'name')), 80),
            'phone', coalesce(u.mobile, ''),
            'customer_id', u.id::text,
            'login_method', 'email_otp',
            'payment_status', 'awaiting_payment', 'channel', public.sp_order_channel(p_order));

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

create or replace function public.crm_stock_hold(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); it public.crm_records; op text := p ->> 'op'; qty numeric := public.crm_num(p -> 'qty'); tp text := coalesce(nullif(p ->> 'type', ''), 'direct');
        onh numeric; res numeric; fr numeric; hid text; hs jsonb;
begin
  perform public.crm_need(s, 'stock.reserve');
  select * into it from public.crm_records where id = (p ->> 'item_id')::bigint and kind = 'item' and deleted_at is null;
  if it.id is null then raise exception 'Item nahi mila'; end if;
  hs := coalesce(it.data -> 'holds', '[]'::jsonb);
  if op = 'add' then
    if tp not in ('direct', 'online', 'other') then raise exception 'Galat prakar'; end if;
    if qty <= 0 then raise exception 'Qty likhein'; end if;
    if not (it.data ? 'stock') then raise exception 'Is item ka stock track nahi hota — pehle Stock bharein'; end if;
    onh := public.crm_num(it.data -> 'stock'); select coalesce(sum(z.qty), 0) into res from public.crm_reserves(null) z where z.item_id = it.id;
    fr := onh - res - public.crm_holds_sum(it.data, false) - public.crm_holds_sum(it.data, true);
    if qty > fr + 0.0001 then raise exception 'Itna stock free nahi hai (free: %)', greatest(fr, 0); end if;
    if length(trim(coalesce(p ->> 'for', ''))) < 2 then raise exception 'Kiske liye reserve hai — naam likhein'; end if;
    hid := 'h' || extract(epoch from clock_timestamp())::bigint::text || floor(random() * 1000)::int::text;
    hs := hs || jsonb_build_array(jsonb_build_object('id', hid, 'type', tp, 'qty', qty, 'for', left(trim(p ->> 'for'), 120), 'until', coalesce(nullif(p ->> 'until', ''), ''), 'note', left(coalesce(p ->> 'note', ''), 200), 'by', public.crm_uname((s).uid), 'on', public.crm_today()::text));
  elsif op = 'release' then
    if coalesce(p ->> 'hold_id', '') like 'auto-%' then raise exception 'Ye reserve Online list se banta hai — wahin se hatayein / badlein'; end if;
    hs := coalesce((select jsonb_agg(h) from jsonb_array_elements(hs) h where h ->> 'id' <> coalesce(p ->> 'hold_id', '')), '[]'::jsonb);
  else raise exception 'Galat kaam'; end if;
  update public.crm_records set data = jsonb_set(data, '{holds}', hs), updated_at = now() where id = it.id;
  perform public.crm_log(s, 'edit', 'item', it.id, 'Stock ' || case when op = 'add' then 'reserve ' || qty || ' (' || tp || ')' else 'reserve release' end || ': ' || it.title);
  return jsonb_build_object('ok', true, 'holds', hs);
end $$;
CREATE OR REPLACE FUNCTION public.crm_save(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); k text := p ->> 'kind'; id_ bigint := nullif(p ->> 'id', '')::bigint;
        d jsonb := coalesce(p -> 'data', '{}'::jsonb); old public.crm_records; r public.crm_records; isnew boolean := id_ is null or id_ = 0;
        mob text; em text; ttl text; st text := coalesce(p ->> 'status', ''); asg bigint := nullif(p ->> 'assigned_to', '')::bigint; pid bigint := nullif(p ->> 'party_id', '')::bigint;
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
  em := lower(left(trim(coalesce(d ->> 'email', '')), 160));
  ttl := left(trim(coalesce(d ->> 'name', d ->> 'title', '')), 200);
  owner_ := case when isnew then (s).uid else old.owner_id end;
  if not isnew and pid is null and not (p ? 'party_id') then pid := old.party_id; end if;
  if not isnew and not (p ? 'assigned_to') then asg := old.assigned_to; end if;
  if not isnew and not (p ? 'due_at') then due := old.due_at; end if;

  -- ---------------- per kind rules
  if k = 'party' then
    perform public.crm_need(s, case when isnew then 'customers.create' else 'customers.edit' end);
    if ttl = '' then raise exception 'Customer ka naam likhein'; end if;
    if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein (mobile zaroori hai)'; end if;
    if em <> '' and em !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'Sahi email likhein (ya khali chhodein)'; end if;
    select * into ex from public.crm_records where kind = 'party' and deleted_at is null and mobile = mob and id <> coalesce(id_, 0) limit 1;
    if ex.id is not null then
      if public.crm_vis(s, ex) then raise exception 'Ye customer pehle se list me hai: % (#%)', ex.title, ex.id;
      else raise exception 'Ye customer pehle se % ke paas hai — Admin se transfer karwayein', coalesce(public.crm_uname(ex.owner_id), 'kisi aur'); end if;
    end if;
    if (p ? 'assigned_to') and asg is distinct from (case when isnew then null else old.assigned_to end) then perform public.crm_need(s, 'customers.assign'); end if;
    pid := null; st := coalesce(nullif(st, ''), case when isnew then 'active' else old.status end);
  elsif k = 'item' then
    perform public.crm_need(s, case when isnew then 'items.create' else 'items.edit' end);
    if not isnew and old.data ->> 'fixed' = 'true' and not public.crm_is_admin(s) then raise exception 'Ye Fixed plan hai — sirf Admin iski keemat / kaam ki list badal sakta hai'; end if;
    if ttl = '' then raise exception 'Item ka naam likhein'; end if;
    amt := public.crm_num(d -> 'price'); mob := null; pid := null;
    if not public.crm_can(s, 'items.cost') and not isnew then d := d || jsonb_build_object('cost_price', old.data -> 'cost_price', 'min_price', old.data -> 'min_price'); end if;
    -- online store status: only the review flow can publish
    if not isnew then d := jsonb_set(d, '{store}', coalesce(old.data -> 'store', '{}'::jsonb) || (coalesce(d -> 'store', '{}'::jsonb) - 'status' - 'store_id' - 'reviewed_at' - 'online' - 'sent_at')); end if;
    if not isnew then d := jsonb_set(d, '{holds}', coalesce(old.data -> 'holds', '[]'::jsonb)); elsif d ? 'holds' then d := d - 'holds'; end if;
    if isnew then d := jsonb_set(d, '{store}', (coalesce(d -> 'store', '{}'::jsonb) - 'store_id' - 'reviewed_at') || '{"status":"none"}'::jsonb); end if;
    d := public.crm_item_prep(isnew, case when isnew then null else old.data end, d);   -- Round 13: auto SKU (immutable), project line SKUs
    if coalesce(d ->> 'type', 'product') = 'product' then   -- Round 43: kharid rate (purchase price) zaroori
      if public.crm_num(d -> 'cost_price') > 0 then d := d - 'cost_missing';
      elsif isnew and public.crm_can(s, 'items.cost') and coalesce(d ->> 'cost_ok', '') <> 'true' then raise exception 'Kharid rate (purchase price) zaroori hai — pehle likhein';
      else d := d || '{"cost_missing":true}'::jsonb; end if;
    end if;
    d := d - 'cost_ok';
    if not isnew and coalesce(d ->> 'type', 'product') = 'project' and old.data #> '{store,online}' is not null
       and coalesce((select jsonb_agg(jsonb_build_object('i', x ->> 'item_id', 'q', public.crm_num(x -> 'qty')) order by o) from jsonb_array_elements(coalesce(d -> 'proj_items', '[]'::jsonb)) with ordinality t(x, o)), '[]'::jsonb)
          is distinct from coalesce((select jsonb_agg(jsonb_build_object('i', x ->> 'item_id', 'q', public.crm_num(x -> 'qty')) order by o) from jsonb_array_elements(coalesce(old.data -> 'proj_items', '[]'::jsonb)) with ordinality t(x, o)), '[]'::jsonb) then
      raise exception 'Ye template Online par hai — items / qty badalne ke liye pehle Online list me "Online se hatayein" karein (naam badal sakte hain)'; end if;
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
          if it.id is not null and public.crm_num(it.data -> 'cost_price') > 0 and public.crm_num(l -> 'price') < public.crm_num(it.data -> 'cost_price') - 0.009 then
            raise exception '"%" ka rate kharid rate (%) se kam nahi ho sakta', it.title, public.crm_num(it.data -> 'cost_price'); end if;
          if it.id is not null and public.crm_num(it.data -> 'min_price') > 0 and public.crm_num(l -> 'price') < public.crm_num(it.data -> 'min_price') then
            raise exception '"%" ka rate minimum rate se kam hai — Admin se permission lein', it.title; end if;
        end if;
      end loop;
      select coalesce(nullif(public.crm_num(meta -> 'max_discount_pct'), 0), public.crm_role_discount(role)) into lim from public.crm_users where id = (s).uid;
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
    if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein (mobile zaroori hai)'; end if;
    if em <> '' and em !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'Sahi email likhein (ya khali chhodein)'; end if;
    if ttl = '' then ttl := 'Lead ' || mob; end if;
    if (p ? 'assigned_to') and asg is distinct from (case when isnew then null else old.assigned_to end) and asg is distinct from (s).uid then perform public.crm_need(s, 'leads.assign'); end if;
    if isnew and exists (select 1 from public.crm_records where kind = 'lead' and deleted_at is null and status not in ('won', 'lost') and mobile = mob and (owner_id = (s).uid or assigned_to = coalesce(asg, (s).uid))) then
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
    if pid is null and mob <> '' then select id into pid from public.crm_records where kind = 'party' and mobile = mob and deleted_at is null limit 1; end if;
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

  srch := lower(concat_ws(' ', ttl, ref_, mob, em, d ->> 'city', d ->> 'company', d ->> 'gstin', d ->> 'note', d ->> 'type', d ->> 'brand', d ->> 'qtitle', d ->> 'category', d ->> 'subcategory', d ->> 'sku', d ->> 'mpn', d ->> 'source'));
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
end $function$

;


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

-- ---------------------------------------------------------------- staff HR details (job / personal / bank) + salary set
create or replace function public.crm_staff_get(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); id_ bigint := (p ->> 'id')::bigint; u public.crm_users; h public.crm_staff_hr;
        hr_ok boolean := public.crm_can(s, 'staff.hr'); sal_ok boolean := public.crm_can(s, 'salary.manage'); out jsonb;
begin
  if not (hr_ok or sal_ok or (s).uid = id_ or public.crm_can(s, 'staff.view') or public.crm_can(s, 'users.manage')) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  select * into u from public.crm_users where id = id_;
  if u.id is null or u.role in ('dealer', 'influencer', 'consumer') then raise exception 'Staff nahi mila'; end if;
  select * into h from public.crm_staff_hr where user_id = id_;
  out := jsonb_build_object('id', u.id, 'name', u.name, 'role', u.role, 'mobile', u.mobile, 'status', u.status,
    'hr', case when hr_ok then coalesce(h.hr, '{}'::jsonb) else jsonb_build_object('designation', coalesce(h.hr ->> 'designation', ''), 'reports_to', coalesce(h.hr ->> 'reports_to', ''), 'joining', coalesce(h.hr ->> 'joining', '')) end,
    'can_hr', hr_ok, 'can_sal', sal_ok);
  if hr_ok then out := out || jsonb_build_object('email', u.email, 'username', u.username, 'last_seen', u.last_seen); end if;
  if sal_ok then
    out := out || jsonb_build_object('sal', coalesce(h.sal, '{}'::jsonb),
      'adv_out', coalesce((select sum(amount) from public.crm_staff_adv where user_id = id_ and deleted_at is null), 0) - coalesce((select sum(adv_cut) from public.crm_salary_pay where user_id = id_ and deleted_at is null), 0),
      'pays', coalesce((select jsonb_agg(to_jsonb(z) - 'deleted_at' - 'deleted_by' - 'delete_reason' order by z.month desc) from (select * from public.crm_salary_pay where user_id = id_ and deleted_at is null order by month desc limit 12) z), '[]'::jsonb),
      'advs', coalesce((select jsonb_agg(to_jsonb(z) - 'deleted_at' - 'deleted_by' - 'delete_reason' order by z.given_on desc, z.id desc) from (select * from public.crm_staff_adv where user_id = id_ and deleted_at is null order by given_on desc, id desc limit 12) z), '[]'::jsonb));
  end if;
  return out;
end $$;

create or replace function public.crm_staff_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); id_ bigint := (p ->> 'id')::bigint; u public.crm_users; h public.crm_staff_hr;
        hk text[] := array['designation','department','reports_to','joining','emp_type','location','exit_date','qualification','experience','dob','gender','address','emergency_name','emergency_mobile','blood','bank_holder','bank_name','bank_acc','ifsc','upi','id_proof','notes'];
        nh jsonb := '{}'::jsonb; ns jsonb := '{}'::jsonb; k text; v numeric; sd jsonb := coalesce(p -> 'sal', '{}'::jsonb); hd jsonb := coalesce(p -> 'hr', '{}'::jsonb);
begin
  select * into u from public.crm_users where id = id_;
  if u.id is null or u.role in ('dealer', 'influencer', 'consumer') then raise exception 'Staff nahi mila'; end if;
  if u.role = 'admin' and not public.crm_is_admin(s) then raise exception 'Admin ki details sirf Admin badal sakta hai'; end if;
  select * into h from public.crm_staff_hr where user_id = id_;
  if p ? 'hr' then
    perform public.crm_need(s, 'staff.hr');
    foreach k in array hk loop if hd ? k then nh := nh || jsonb_build_object(k, left(trim(coalesce(hd ->> k, '')), 300)); end if; end loop;
    if coalesce(nh ->> 'joining', '') <> '' and (nh ->> 'joining') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Joining date galat hai'; end if;
    if coalesce(nh ->> 'emergency_mobile', '') <> '' then nh := nh || jsonb_build_object('emergency_mobile', public.crm_mobile(nh ->> 'emergency_mobile')); end if;
  end if;
  if p ? 'sal' then
    perform public.crm_need(s, 'salary.manage');
    foreach k in array array['monthly','allowance','deduction','pay_day'] loop
      if sd ? k then v := public.crm_num(sd -> k); if v < 0 or v > 10000000 then raise exception 'Amount galat hai'; end if;
        if k = 'pay_day' and (v < 0 or v > 31) then raise exception 'Pay day 1 se 31 ke beech ho'; end if;
        ns := ns || jsonb_build_object(k, v); end if;
    end loop;
    if sd ? 'note' then ns := ns || jsonb_build_object('note', left(trim(coalesce(sd ->> 'note', '')), 200)); end if;
  end if;
  insert into public.crm_staff_hr(user_id, hr, sal, updated_by) values (id_, coalesce(h.hr, '{}'::jsonb) || nh, coalesce(h.sal, '{}'::jsonb) || ns, (s).uid)
  on conflict (user_id) do update set hr = excluded.hr, sal = excluded.sal, updated_at = now(), updated_by = excluded.updated_by;
  if p ? 'hr' then perform public.crm_log(s, 'staff_hr', 'user', id_, 'HR details badli: ' || u.name); end if;
  if p ? 'sal' then perform public.crm_log(s, 'staff_salary', 'user', id_, 'Salary set / badli: ' || u.name); end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------- payroll (mahine ki salary) — pay karte hi Accounts > Kharcha me entry
create or replace function public.crm_payroll_list(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); m text := coalesce(nullif(p ->> 'month', ''), to_char(public.crm_today(), 'YYYY-MM'));
begin
  perform public.crm_need(s, 'salary.manage');
  if m !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Mahina galat hai'; end if;
  return jsonb_build_object('month', m, 'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'id', u.id, 'name', u.name, 'role', u.role, 'mobile', u.mobile, 'status', u.status, 'designation', h.hr ->> 'designation', 'joining', h.hr ->> 'joining', 'exit', h.hr ->> 'exit_date',
      'sal', coalesce(h.sal, '{}'::jsonb),
      'adv_out', coalesce((select sum(a.amount) from public.crm_staff_adv a where a.user_id = u.id and a.deleted_at is null), 0) - coalesce((select sum(z.adv_cut) from public.crm_salary_pay z where z.user_id = u.id and z.deleted_at is null), 0),
      'pay', (select to_jsonb(z) - 'deleted_at' - 'deleted_by' - 'delete_reason' from public.crm_salary_pay z where z.user_id = u.id and z.month = m and z.deleted_at is null)
    ) order by u.name)
    from public.crm_users u left join public.crm_staff_hr h on h.user_id = u.id
    where u.role in ('manager', 'staff', 'hr', 'marketing') and (u.status = 'active' or exists (select 1 from public.crm_salary_pay z where z.user_id = u.id and z.month = m and z.deleted_at is null))), '[]'::jsonb));
end $$;

create or replace function public.crm_salary_pay(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); uid_ bigint := (p ->> 'user_id')::bigint; m text := p ->> 'month'; u public.crm_users; h public.crm_staff_hr;
        basic numeric; allw numeric; ded numeric; bonus numeric := public.crm_num(p -> 'bonus'); xded numeric := public.crm_num(p -> 'deduction'); acut numeric := public.crm_num(p -> 'adv_cut');
        outst numeric; net numeric; d date; md text := left(coalesce(nullif(p ->> 'mode', ''), 'bank'), 20); ex public.crm_expenses; r public.crm_salary_pay;
begin
  perform public.crm_need(s, 'salary.manage');
  if m is null or m !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Mahina galat hai'; end if;
  select * into u from public.crm_users where id = uid_;
  if u.id is null or u.role not in ('manager', 'staff', 'hr', 'marketing') then raise exception 'Is ID ki salary yahan se nahi hoti'; end if;
  select * into h from public.crm_staff_hr where user_id = uid_;
  basic := public.crm_num(h.sal -> 'monthly'); allw := public.crm_num(h.sal -> 'allowance'); ded := public.crm_num(h.sal -> 'deduction');
  if basic <= 0 then raise exception 'Pehle is staff ki monthly salary set karein'; end if;
  if bonus < 0 or xded < 0 or acut < 0 then raise exception 'Amount galat hai'; end if;
  if exists (select 1 from public.crm_salary_pay where user_id = uid_ and month = m and deleted_at is null) then raise exception 'Is mahine ki salary pehle hi di ja chuki hai'; end if;
  outst := coalesce((select sum(amount) from public.crm_staff_adv where user_id = uid_ and deleted_at is null), 0) - coalesce((select sum(adv_cut) from public.crm_salary_pay where user_id = uid_ and deleted_at is null), 0);
  if acut > outst then raise exception 'Advance sirf % baaki hai', outst; end if;
  net := round(basic + allw + bonus - ded - xded - acut, 2);
  if net <= 0 then raise exception 'Net salary zero se zyada honi chahiye'; end if;
  begin d := coalesce(nullif(p ->> 'paid_on', '')::date, public.crm_today()); exception when others then raise exception 'Tareekh galat hai'; end;
  if d > public.crm_today() + 1 or d < date '2015-01-01' then raise exception 'Tareekh galat hai'; end if;
  insert into public.crm_expenses(spent_on, category, vendor, amount, gst_amount, mode, note, created_by)
  values (d, 'Salary', left(u.name, 120), net, 0, md, 'Salary ' || m || coalesce(nullif(' — ' || left(trim(coalesce(p ->> 'note', '')), 200), ' — '), ''), (s).uid) returning * into ex;
  insert into public.crm_salary_pay(user_id, month, basic, allowance, bonus, deduction, adv_cut, net, paid_on, mode, note, expense_id, created_by)
  values (uid_, m, basic, allw, bonus, ded + xded, acut, net, d, md, left(trim(coalesce(p ->> 'note', '')), 200), ex.id, (s).uid) returning * into r;
  perform public.crm_log(s, 'salary_pay', 'user', uid_, 'Salary di: ' || u.name || ' (' || m || ')');
  return to_jsonb(r) - 'deleted_at' - 'deleted_by' - 'delete_reason';
end $$;

create or replace function public.crm_salary_undo(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_salary_pay; why text := left(trim(coalesce(p ->> 'reason', '')), 200);
begin
  perform public.crm_need(s, 'salary.manage');
  if length(why) < 3 then raise exception 'Wajah likhein'; end if;
  select * into r from public.crm_salary_pay where id = (p ->> 'id')::bigint and deleted_at is null;
  if r.id is null then raise exception 'Salary entry nahi mili'; end if;
  update public.crm_salary_pay set deleted_at = now(), deleted_by = (s).uid, delete_reason = why where id = r.id;
  update public.crm_expenses set deleted_at = now(), deleted_by = (s).uid, delete_reason = 'Salary wapas: ' || why where id = r.expense_id and deleted_at is null;
  perform public.crm_log(s, 'salary_undo', 'user', r.user_id, 'Salary entry hata di: ' || public.crm_uname(r.user_id) || ' (' || r.month || ') — ' || why);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.crm_staff_advance(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); uid_ bigint := (p ->> 'user_id')::bigint; u public.crm_users; a numeric := public.crm_num(p -> 'amount'); d date;
        md text := left(coalesce(nullif(p ->> 'mode', ''), 'cash'), 20); ex public.crm_expenses; r public.crm_staff_adv;
begin
  perform public.crm_need(s, 'salary.manage');
  select * into u from public.crm_users where id = uid_;
  if u.id is null or u.role not in ('manager', 'staff', 'hr', 'marketing') then raise exception 'Is ID ko advance yahan se nahi milta'; end if;
  if a <= 0 or a > 10000000 then raise exception 'Advance amount likhein'; end if;
  begin d := coalesce(nullif(p ->> 'given_on', '')::date, public.crm_today()); exception when others then raise exception 'Tareekh galat hai'; end;
  if d > public.crm_today() + 1 or d < date '2015-01-01' then raise exception 'Tareekh galat hai'; end if;
  insert into public.crm_expenses(spent_on, category, vendor, amount, gst_amount, mode, note, created_by)
  values (d, 'Staff advance', left(u.name, 120), round(a, 2), 0, md, left(trim(coalesce(p ->> 'note', '')), 200), (s).uid) returning * into ex;
  insert into public.crm_staff_adv(user_id, given_on, amount, mode, note, expense_id, created_by) values (uid_, d, round(a, 2), md, left(trim(coalesce(p ->> 'note', '')), 200), ex.id, (s).uid) returning * into r;
  perform public.crm_log(s, 'staff_advance', 'user', uid_, 'Advance diya: ' || u.name);
  return to_jsonb(r) - 'deleted_at' - 'deleted_by' - 'delete_reason';
end $$;

create or replace function public.crm_my_pay(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token');
begin
  if (s).uid is null or (s).uid = 0 then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'month', z.month, 'basic', z.basic, 'allowance', z.allowance, 'bonus', z.bonus, 'deduction', z.deduction, 'adv_cut', z.adv_cut, 'net', z.net, 'paid_on', z.paid_on, 'mode', z.mode) order by z.month desc)
    from (select * from public.crm_salary_pay where user_id = (s).uid and deleted_at is null order by month desc limit 24) z), '[]'::jsonb);
end $$;

grant execute on function public.crm_staff_get(jsonb), public.crm_staff_save(jsonb), public.crm_payroll_list(jsonb), public.crm_salary_pay(jsonb), public.crm_salary_undo(jsonb), public.crm_staff_advance(jsonb), public.crm_my_pay(jsonb) to anon, authenticated;

-- ============================================================================
-- ROUND 46 — Customer flow: "Confirmation" (step 6) ab har flow me (Project, Product, Service) — pehle bar me hamesha grey dikhta tha (staging only)
--   Confirmation quotation Accept hote hi apne aap lagta hai (pehle jaisa). Bas ab wo flow ki list me hai, isliye bar me sahi dikhta hai.
--   AMC only / Site visit only me Confirmation nahi (wahan quotation hi nahi). Dobara chalana safe hai.
-- ============================================================================
create or replace function public.crm_wf_flow(ct text) returns int[] language sql immutable as $$
  select case
    when ct = 'Items only'  then array[19,1,2,14,3,6,12,16,18]                               -- Product customer
    when ct = 'Service'     then array[19,1,2,3,6,4,12,17,16,18]                             -- Service customer (cleaning, AMC, repair, shifting, audit)
    when ct = 'AMC only'        then array[19,1,2,17]                                        -- only a Maintenance / AMC plan
    when ct = 'Site visit only' then array[19,1,2,4]                                         -- only a Site Visit
    when ct = 'Residential' then array[19,1,2,14,3,4,5,6,7,15,8,9,10,11,12,13,16,17,18]      -- Project, subsidy applies
    else                         array[19,1,2,14,3,4,5,6,7,15,8,9,10,11,12,16,17,18] end $$;

-- ============================================================================
-- ROUND 47 — Customer flow steps 14-18 records, commission->salary, attendance+leave, store admin->CRM item, ek hi price har jagah.
--   Staging par chalayein. Dobara chalana safe hai (create or replace / if not exists).
-- ============================================================================

-- =====================================================================================================
-- ROUND 47 / A — Customer flow steps 15 (Loan), 16 (Referral), 18 (Complaint) ke apne records; 17 (AMC) renewal yaad
--   Table crm_flow_rec: ek job (quotation) ke loan / referral / complaint ticket. Sab RPC se (RLS band).
--   Loan Disbursed -> step 15 apne aap ✓, Cash -> "lagu nahi". Referral -> Lead banti hai + step 16 ✓.
--   Complaint ticket -> Aaj ke kaam me reminder; sab Resolved -> step 18 ✓. AMC plan -> renewal ki yaad.
-- Staging pe pehle chalayein. Dobara chalana safe.
-- =====================================================================================================
create table if not exists public.crm_flow_rec (
  id          bigserial primary key,
  kind        text not null check (kind in ('loan', 'referral', 'complaint')),
  quote_id    bigint not null,
  party_id    bigint,
  no          text,
  status      text not null default '',
  data        jsonb not null default '{}'::jsonb,
  hist        jsonb not null default '[]'::jsonb,
  rem_id      bigint,
  created_by  bigint,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz, deleted_by bigint
);
create index if not exists crm_flow_rec_q on public.crm_flow_rec (quote_id, kind) where deleted_at is null;
create index if not exists crm_flow_rec_p on public.crm_flow_rec (party_id) where deleted_at is null;
alter table public.crm_flow_rec enable row level security;

create or replace function public.crm_fr_step(k text) returns int language sql immutable as $$ select case k when 'loan' then 15 when 'referral' then 16 when 'complaint' then 18 else null end $$;

-- writes step n on a quotation (only when not there yet). Same switch as crm_wf_set (sp.wf)
create or replace function public.crm__wf_put(p_qid bigint, n int, p_by text, p_info jsonb, p_note text, p_skip boolean default false) returns void language plpgsql security definer set search_path = public as $$
declare q public.crm_records; prev text := coalesce(current_setting('sp.wf', true), ''); e jsonb;
begin
  select * into q from public.crm_records where id = p_qid and kind = 'quote' and deleted_at is null; if q.id is null then return; end if;
  if not (n = any (public.crm_wf_flow_of(q))) or (q.data -> 'wf') ? n::text then return; end if;
  e := jsonb_build_object('at', public.crm_iso_now(), 'by', coalesce(p_by, ''), 'auto', false, 'note', left(coalesce(p_note, ''), 500));
  if p_skip then e := e || jsonb_build_object('skip', true); end if;
  if p_info is not null and p_info <> '{}'::jsonb then e := e || jsonb_build_object('info', p_info); end if;
  perform set_config('sp.wf', '1', true);
  update public.crm_records set data = data || jsonb_build_object('wf', coalesce(data -> 'wf', '{}'::jsonb) || jsonb_build_object(n::text, e)), updated_at = now() where id = q.id;
  perform set_config('sp.wf', prev, true);
end $$;

create or replace function public.crm_fr_row(r public.crm_flow_rec) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', r.id, 'kind', r.kind, 'quote_id', r.quote_id, 'party_id', r.party_id, 'no', r.no, 'status', r.status, 'data', r.data, 'hist', r.hist,
    'by', public.crm_uname(r.created_by), 'created_at', r.created_at, 'updated_at', r.updated_at) $$;

create or replace function public.crm_fr_list(p jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; k text := nullif(p ->> 'kind', ''); out jsonb := '[]'::jsonb; r public.crm_flow_rec;
begin
  select * into q from public.crm_records where id = nullif(p ->> 'quote_id', '')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  for r in select * from public.crm_flow_rec where quote_id = q.id and deleted_at is null and (k is null or kind = k) order by id desc loop
    if public.crm_wf_can(s, public.crm_fr_step(r.kind), 'view') then out := out || jsonb_build_array(public.crm_fr_row(r)); end if;
  end loop;
  return out;
end $$;

create or replace function public.crm_fr_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; pt public.crm_records; r public.crm_flow_rec; k text := p ->> 'kind'; n int; d jsonb := coalesce(p -> 'data', '{}'::jsonb);
        st text := left(trim(coalesce(p ->> 'status', '')), 30); note text := left(trim(coalesce(p ->> 'note', '')), 300); isnew boolean; w jsonb; lid bigint; lerr text := ''; cnt int; asg bigint; remid bigint; mob text; ino jsonb; due date;
        amt numeric; open_n int;
begin
  if k not in ('loan', 'referral', 'complaint') then raise exception 'Galat prakar'; end if;
  n := public.crm_fr_step(k);
  select * into q from public.crm_records where id = nullif(p ->> 'quote_id', '')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if not (n = any (public.crm_wf_flow_of(q))) then raise exception 'Ye step is customer ke liye nahi hai'; end if;
  if not public.crm_wf_can(s, n, 'edit') then raise exception 'Is step ko badalne ki permission nahi hai — Admin se allow karwayein'; end if;
  w := coalesce(q.data -> 'wf', '{}'::jsonb);
  if not (w ? '6') then raise exception 'Pehle quotation Confirm hona chahiye'; end if;
  select * into pt from public.crm_records where id = q.party_id and kind = 'party';
  if nullif(p ->> 'id', '') is not null then
    select * into r from public.crm_flow_rec where id = (p ->> 'id')::bigint and quote_id = q.id and kind = k and deleted_at is null;
    if r.id is null then raise exception 'Record nahi mila'; end if;
    isnew := false;
  elsif k = 'loan' then
    select * into r from public.crm_flow_rec where quote_id = q.id and kind = 'loan' and deleted_at is null order by id desc limit 1;
    isnew := r.id is null;
  else isnew := true; end if;

  -- ---------------- LOAN: ek job ka ek loan record
  if k = 'loan' then
    d := jsonb_build_object('pay_mode', left(trim(coalesce(d ->> 'pay_mode', '')), 20), 'bank', left(trim(coalesce(d ->> 'bank', '')), 80), 'loan_amount', public.crm_num(d -> 'loan_amount'),
      'apply_date', left(coalesce(d ->> 'apply_date', ''), 10), 'sanction_amount', public.crm_num(d -> 'sanction_amount'), 'disbursed_amount', public.crm_num(d -> 'disbursed_amount'),
      'disbursed_on', left(coalesce(d ->> 'disbursed_on', ''), 10), 'loan_ref', left(trim(coalesce(d ->> 'loan_ref', '')), 60),
      'payment_id', coalesce(nullif(d ->> 'payment_id', ''), case when r.id is null then null else r.data ->> 'payment_id' end));
    if d ->> 'pay_mode' not in ('Cash', 'Loan', 'Mixed') then raise exception 'Payment tarika chunein (Cash / Loan / Mixed)'; end if;
    if d ->> 'pay_mode' = 'Cash' then st := 'cash';
    else
      if st not in ('Applied', 'Sanctioned', 'Disbursed', 'Rejected') then raise exception 'Loan ka stage chunein (Applied / Sanctioned / Disbursed / Rejected)'; end if;
      if (d ->> 'bank') = '' then raise exception 'Bank ka naam likhein'; end if;
      if public.crm_num(d -> 'loan_amount') <= 0 then raise exception 'Loan amount likhein'; end if;
      if st = 'Disbursed' and public.crm_num(d -> 'disbursed_amount') <= 0 then raise exception 'Disburse hui rakam likhein'; end if;
    end if;
  -- ---------------- REFERRAL
  elsif k = 'referral' then
    amt := public.crm_num(d -> 'reward_amount'); if amt < 0 then amt := 0; end if;
    mob := public.crm_mobile(coalesce(d ->> 'referred_mobile', ''));
    d := jsonb_build_object('ref_type', case when d ->> 'ref_type' in ('customer', 'partner', 'other') then d ->> 'ref_type' else 'other' end,
      'referrer_name', left(trim(coalesce(d ->> 'referrer_name', '')), 120), 'referrer_mobile', public.crm_mobile(coalesce(d ->> 'referrer_mobile', '')), 'referrer_party', nullif(d ->> 'referrer_party', ''), 'referrer_user', nullif(d ->> 'referrer_user', ''),
      'referred_name', left(trim(coalesce(d ->> 'referred_name', '')), 120), 'referred_mobile', mob, 'referred_note', left(trim(coalesce(d ->> 'referred_note', '')), 200),
      'reward_amount', amt, 'reward_note', left(trim(coalesce(d ->> 'reward_note', '')), 200), 'lead_id', case when isnew then null else r.data -> 'lead_id' end, 'earning_id', case when isnew then null else r.data -> 'earning_id' end);
    if (d ->> 'referrer_name') = '' then raise exception 'Refer karne wale ka naam likhein'; end if;
    if (d ->> 'referred_name') = '' then raise exception 'Jisko refer kiya uska naam likhein'; end if;
    if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Jisko refer kiya uska sahi 10 ank ka mobile likhein'; end if;
    if st not in ('none', 'due', 'paid') then st := case when amt > 0 then 'due' else 'none' end; end if;
    if amt <= 0 then st := 'none'; end if;
  -- ---------------- COMPLAINT
  else
    d := jsonb_build_object('issue', left(trim(coalesce(d ->> 'issue', '')), 300), 'brand', left(trim(coalesce(d ->> 'brand', '')), 80), 'serial', left(trim(coalesce(d ->> 'serial', '')), 60),
      'handler', case when d ->> 'handler' in ('Installer', 'Dealer', 'Manufacturer') then d ->> 'handler' else 'Installer' end, 'priority', case when d ->> 'priority' = 'Urgent' then 'Urgent' else 'Normal' end,
      'c_date', coalesce(nullif(left(coalesce(d ->> 'c_date', ''), 10), ''), public.crm_today()::text), 'assigned_to', nullif(d ->> 'assigned_to', ''), 'ticket_ref', left(trim(coalesce(d ->> 'ticket_ref', '')), 60),
      'resolution', left(trim(coalesce(d ->> 'resolution', '')), 300));
    if length(d ->> 'issue') < 3 then raise exception 'Samasya likhein (kam se kam 3 akshar)'; end if;
    if st not in ('Open', 'In progress', 'Resolved') then st := 'Open'; end if;
    if st = 'Resolved' and (d ->> 'resolution') = '' then raise exception 'Kaise solve hua — "Hal" likhein'; end if;
  end if;

  -- ---------------- save
  if isnew then
    if k = 'complaint' then
      perform pg_advisory_xact_lock(4747);
      select count(*) + 1 into cnt from public.crm_flow_rec where kind = 'complaint';
      insert into public.crm_flow_rec(kind, quote_id, party_id, no, status, data, hist, created_by)
        values (k, q.id, q.party_id, 'TKT-' || to_char(now() at time zone 'Asia/Kolkata', 'YY') || '-' || lpad(cnt::text, 4, '0'), st, d,
          jsonb_build_array(jsonb_build_object('at', public.crm_iso_now(), 'by', (s).name, 'status', st, 'note', coalesce(nullif(note, ''), 'Ticket bana'))), (s).uid) returning * into r;
    else
      insert into public.crm_flow_rec(kind, quote_id, party_id, no, status, data, hist, created_by)
        values (k, q.id, q.party_id, null, st, d, jsonb_build_array(jsonb_build_object('at', public.crm_iso_now(), 'by', (s).name, 'status', st, 'note', coalesce(nullif(note, ''), 'Jaankari darj'))), (s).uid) returning * into r;
    end if;
  else
    update public.crm_flow_rec set data = case when k = 'complaint' then d else d end, status = st, updated_at = now(),
      hist = case when status is distinct from st or note <> '' then hist || jsonb_build_array(jsonb_build_object('at', public.crm_iso_now(), 'by', (s).name, 'status', st, 'note', note)) else hist end
      where id = r.id returning * into r;
  end if;

  -- ---------------- side effects
  if k = 'loan' then
    -- Cash se Loan/Mixed par badla to purana "lagu nahi" hata do (tabhi stage ke hisab se step chalega)
    if st <> 'cash' and (w -> '15' ->> 'skip') = 'true' and (w -> '15' ->> 'note') like 'Cash payment%' then
      perform set_config('sp.wf', '1', true);
      update public.crm_records set data = jsonb_set(data, '{wf}', (data -> 'wf') - '15'), updated_at = now() where id = q.id;
      perform set_config('sp.wf', '', true);
    end if;
    if st = 'cash' then
      perform public.crm__wf_put(q.id, 15, (s).name, jsonb_build_object('pay_mode', 'Cash'), 'Cash payment — loan lagu nahi', true);
    elsif st = 'Disbursed' then
      perform public.crm__wf_put(q.id, 15, (s).name, jsonb_build_object('pay_mode', d ->> 'pay_mode', 'bank', d ->> 'bank', 'loan_amount', (d ->> 'loan_amount'), 'loan_status', 'Disbursed', 'loan_ref', d ->> 'loan_ref'), 'Loan disburse ho gaya', false);
    end if;
  elsif k = 'referral' then
    if isnew then
      begin
        lid := (public.crm_save(jsonb_build_object('token', p ->> 'token', 'kind', 'lead', 'data', jsonb_build_object('name', d ->> 'referred_name', 'mobile', d ->> 'referred_mobile', 'source', 'Referral',
                 'note', 'Refer kiya: ' || (d ->> 'referrer_name') || ' (customer: ' || coalesce(pt.title, '') || ')' || case when (d ->> 'referred_note') <> '' then ' — ' || (d ->> 'referred_note') else '' end)))
              ->> 'id')::bigint;
        update public.crm_flow_rec set data = data || jsonb_build_object('lead_id', lid) where id = r.id returning * into r;
      exception when others then
        lerr := sqlerrm;
        update public.crm_flow_rec set data = data || jsonb_build_object('lead_error', left(lerr, 160)) where id = r.id returning * into r;
      end;
    end if;
    perform public.crm__wf_put(q.id, 16, (s).name, jsonb_build_object('ref_name', d ->> 'referrer_name', 'ref_mobile', d ->> 'referrer_mobile'), 'Referral darj', false);
  else -- complaint: reminder in "Aaj ke kaam", step 18 when everything is resolved
    asg := coalesce(nullif(d ->> 'assigned_to', '')::bigint, nullif(q.assigned_to, 0), (s).uid);
    if st <> 'Resolved' then
      if r.rem_id is null or not exists (select 1 from public.crm_records where id = r.rem_id and status = 'open' and deleted_at is null) then
        insert into public.crm_records(kind, title, status, owner_id, assigned_to, party_id, mobile, due_at, data, search, created_by)
        values ('reminder', 'Complaint ' || r.no || ' — ' || coalesce(pt.title, '') || ': ' || left(d ->> 'issue', 60), 'open', (s).uid, asg, q.party_id, pt.mobile, public.crm_today(),
          jsonb_build_object('type', 'followup', 'complaint_id', r.id, 'ticket', r.no, 'party_name', coalesce(pt.title, ''), 'mobile', coalesce(pt.mobile, ''), 'note', left(d ->> 'issue', 200), 'priority', d ->> 'priority'),
          lower('complaint ' || r.no || ' ' || coalesce(pt.title, '')), (s).uid) returning id into remid;
        update public.crm_flow_rec set rem_id = remid where id = r.id returning * into r;
      end if;
    else
      if r.rem_id is not null then update public.crm_records set status = 'done', data = data || jsonb_build_object('done_on', public.crm_today()::text), updated_at = now() where id = r.rem_id and status = 'open'; end if;
      select count(*) into open_n from public.crm_flow_rec where quote_id = q.id and kind = 'complaint' and deleted_at is null and status <> 'Resolved';
      if open_n = 0 then
        perform public.crm__wf_put(q.id, 18, (s).name, jsonb_build_object('c_status', 'Resolved', 'c_issue', d ->> 'issue', 'c_ticket', r.no, 'c_handler', d ->> 'handler', 'c_brand', d ->> 'brand', 'c_serial', d ->> 'serial', 'c_date', d ->> 'c_date'), 'Saari complaint solve', false);
      end if;
    end if;
  end if;
  perform public.crm_log(s, 'workflow', 'quote', q.id, coalesce(q.ref, '') || ' — ' || (public.crm_wf_names())[n] || ': ' || k || coalesce(' ' || r.no, '') || ' (' || st || ')');
  return public.crm_fr_row(r);
end $$;

-- referral reward -> Commission page me entry (sirf Partner / staff user ko; Commission manage permission chahiye)
create or replace function public.crm_fr_reward(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_flow_rec; q public.crm_records; eid bigint; uid bigint := nullif(p ->> 'user_id', '')::bigint; e jsonb;
begin
  perform public.crm_need(s, 'earnings.manage');
  select * into r from public.crm_flow_rec where id = (p ->> 'id')::bigint and kind = 'referral' and deleted_at is null;
  if r.id is null then raise exception 'Record nahi mila'; end if;
  select * into q from public.crm_records where id = r.quote_id and kind = 'quote';
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if r.data ->> 'earning_id' is not null then raise exception 'Is referral ka commission pehle hi jud chuka hai'; end if;
  if public.crm_num(r.data -> 'reward_amount') <= 0 then raise exception 'Pehle reward ki rakam likhein'; end if;
  if uid is null or not exists (select 1 from public.crm_users where id = uid) then raise exception 'User chunein'; end if;
  e := public.crm_save(jsonb_build_object('token', p ->> 'token', 'kind', 'earning', 'owner_id', uid, 'party_id', r.party_id,
    'data', jsonb_build_object('title', 'Referral reward — ' || (r.data ->> 'referred_name') || ' (' || coalesce(q.ref, '') || ')', 'amount', public.crm_num(r.data -> 'reward_amount'), 'pay_on', public.crm_today() + 7,
      'note', 'Refer: ' || (r.data ->> 'referrer_name'), 'date', public.crm_today(), 'referral_id', r.id)));
  eid := (e ->> 'id')::bigint;
  update public.crm_flow_rec set data = data || jsonb_build_object('earning_id', eid), status = case when status = 'none' then 'due' else status end, updated_at = now(),
    hist = hist || jsonb_build_array(jsonb_build_object('at', public.crm_iso_now(), 'by', (s).name, 'status', 'due', 'note', 'Commission me jodi')) where id = r.id returning * into r;
  return public.crm_fr_row(r);
end $$;

create or replace function public.crm_fr_del(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_flow_rec; q public.crm_records;
begin
  select * into r from public.crm_flow_rec where id = (p ->> 'id')::bigint and deleted_at is null;
  if r.id is null then raise exception 'Record nahi mila'; end if;
  select * into q from public.crm_records where id = r.quote_id and kind = 'quote';
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if not (public.crm_is_admin(s) or (s).role = 'manager' or r.created_by = (s).uid) then raise exception 'Sirf Admin / Manager ya banane wala hata sakta hai'; end if;
  if length(trim(coalesce(p ->> 'reason', ''))) < 3 then raise exception 'Hatane ki wajah likhein'; end if;
  update public.crm_flow_rec set deleted_at = now(), deleted_by = (s).uid where id = r.id;
  if r.rem_id is not null then update public.crm_records set status = 'done', data = data || jsonb_build_object('done_on', public.crm_today()::text, 'cancelled', true), updated_at = now() where id = r.rem_id and status = 'open'; end if;
  perform public.crm_log(s, 'delete', 'quote', q.id, coalesce(q.ref, '') || ' — ' || r.kind || coalesce(' ' || r.no, '') || ' hataya: ' || left(p ->> 'reason', 120));
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.crm_fr_list(jsonb), public.crm_fr_save(jsonb), public.crm_fr_reward(jsonb), public.crm_fr_del(jsonb) from public;
grant execute on function public.crm_fr_list(jsonb), public.crm_fr_save(jsonb), public.crm_fr_reward(jsonb), public.crm_fr_del(jsonb) to anon, authenticated;


-- Round 47 / A2 — AMC plan dene par renewal ki yaad (Aaj ke kaam me)
CREATE OR REPLACE FUNCTION public.crm_maint_contract(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); ex public.crm_records; pl public.crm_records; months int; yrs int; total int; i int;
        cid text := 'MC-' || encode(gen_random_bytes(4), 'hex'); start_ date; checks jsonb := '[]'::jsonb; pname text; cost numeric := 0; asg bigint := coalesce(nullif(p ->> 'assigned_to', '')::bigint, (s).uid); c jsonb; ck public.crm_records; cyc text := ''; vt text := left(coalesce(p ->> 'time', ''), 5);
begin
  if not (public.crm_can(s, 'customers.create') or public.crm_can(s, 'customers.edit') or public.crm_can(s, 'items.view') or public.crm_is_admin(s)) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  select * into ex from public.crm_records where id = (p ->> 'party_id')::bigint and kind = 'party';
  if not public.crm_vis(s, ex) then raise exception 'Customer nahi mila'; end if;
  begin start_ := (p ->> 'start')::date; exception when others then raise exception 'Sahi tareekh chunein'; end;
  if start_ is null then raise exception 'Pehli visit ki tareekh chunein'; end if;
  select * into pl from public.crm_records where id = nullif(p ->> 'plan_id', '')::bigint and kind = 'item' and deleted_at is null and data ->> 'type' = 'maintenance';
  if pl.id is null then raise exception 'Plan chunein (Maintenance & Audit Packages me plan banayein)'; end if;
  cyc := lower(coalesce(nullif(p ->> 'cycle', ''), pl.data ->> 'period', ''));
  pname := pl.title; months := public.crm_months_of(coalesce(nullif(cyc, ''), pl.data ->> 'period'));
  if cyc = 'one' then months := 0; elsif cyc = 'five' then months := 60; elsif cyc = 'monthly' then months := 1; end if;
  if vt <> '' and vt !~ '^[0-2][0-9]:[0-5][0-9]$' then raise exception 'Sahi time chunein'; end if;
  yrs := least(greatest(coalesce(nullif(pl.data ->> 'years', '')::int, 1), 1), 10);
  total := case when months = 0 then 1 else least(greatest(ceil(12.0 / months * yrs)::int, 1), 120) end;
  for c in select * from jsonb_array_elements(coalesce(pl.data -> 'checklist', '[]'::jsonb)) loop
    select * into ck from public.crm_records where id = nullif(c #>> '{}', '')::bigint and kind = 'item' and deleted_at is null and data ->> 'type' = 'mcheck';
    if ck.id is not null then
      checks := checks || jsonb_build_array(jsonb_build_object('id', ck.id, 'name', ck.title, 'cost', public.crm_num(ck.data -> 'cost'),
        'mat_id', nullif(ck.data ->> 'material_item_id', ''), 'mat_qty', public.crm_num(ck.data -> 'material_qty')));
      cost := cost + public.crm_num(ck.data -> 'cost');
    end if;
  end loop;
  for i in 0 .. total - 1 loop
    insert into public.crm_records(kind, title, status, owner_id, assigned_to, party_id, mobile, due_at, data, search, created_by)
    values ('reminder', 'Solar service — ' || ex.title, 'open', (s).uid, asg, ex.id, ex.mobile, (start_ + make_interval(months => i * months))::date,
      jsonb_build_object('type', 'amc', 'maint', true, 'contract_id', cid, 'plan_id', pl.id, 'plan_name', pname, 'free', coalesce((pl.data ->> 'free')::boolean, false), 'months', months, 'cycle', coalesce(nullif(cyc, ''), pl.data ->> 'period'), 'visit_time', vt, 'plan_code', coalesce(pl.data ->> 'plan_code', ''), 'plan_price', public.crm_num(pl.data -> 'price'), 'plan_gst', public.crm_num(pl.data -> 'gst'), 'prev_contract', coalesce(p ->> 'prev_contract', ''),
        'visit_no', i + 1, 'visits_total', total, 'checks', checks, 'visit_cost', cost, 'mobile', coalesce(ex.mobile, ''), 'party_name', ex.title, 'title', 'Solar service — ' || ex.title),
      lower('solar service ' || ex.title || ' ' || pname), (s).uid);
  end loop;
  -- Round 47: purana renewal reminder band, naya contract ke liye 15 din pehle renewal yaad (one-time plan me nahi)
  update public.crm_records set status = 'done', data = data || jsonb_build_object('done_on', public.crm_today()::text, 'renewed', true), updated_at = now()
    where kind = 'reminder' and party_id = ex.id and status = 'open' and deleted_at is null and data ->> 'amc_renewal' = 'true';
  if months > 0 then
    insert into public.crm_records(kind, title, status, owner_id, assigned_to, party_id, mobile, due_at, data, search, created_by)
    values ('reminder', 'AMC renewal — ' || ex.title || ' (' || pname || ')', 'open', (s).uid, asg, ex.id, ex.mobile, ((start_ + make_interval(months => total * months))::date - 15),
      jsonb_build_object('type', 'call', 'amc_renewal', 'true', 'contract_id', cid, 'plan_name', pname, 'party_name', ex.title, 'mobile', coalesce(ex.mobile, ''), 'title', 'AMC renewal — ' || ex.title, 'note', 'Plan poora hone wala hai — renewal ke liye baat karein'),
      lower('amc renewal ' || ex.title || ' ' || pname), (s).uid);
  end if;
  perform public.crm_log(s, 'create', 'maintenance', ex.id, 'Maintenance & Audit: ' || pname || ' → ' || ex.title || ' (' || total || ' visits)');
  return jsonb_build_object('ok', true, 'contract_id', cid, 'visits', total, 'first_due', start_);
end $function$;


-- Round 47 (B): Commission -> Salary (apne aap). Staff ki "due" commission usi mahine ki salary me judti hai; pay par "paid", undo par wapas "due".
alter table public.crm_salary_pay add column if not exists commission numeric(12,2) not null default 0;
alter table public.crm_salary_pay add column if not exists comm_ids jsonb not null default '[]'::jsonb;

create or replace function public.crm_comm_due(uid_ bigint, m text) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('sum', coalesce(sum(r.amount), 0), 'n', count(r.id), 'ids', coalesce(jsonb_agg(r.id order by r.id), '[]'::jsonb),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'title', r.title, 'amount', r.amount, 'on', coalesce(r.due_at, r.created_at)::date) order by r.id), '[]'::jsonb))
  from public.crm_records r
  where r.kind = 'earning' and r.owner_id = uid_ and r.status = 'due' and r.deleted_at is null
    and coalesce(r.due_at, r.created_at)::date <= ((to_date(m || '-01', 'YYYY-MM-DD') + interval '1 month')::date - 1) $$;
revoke all on function public.crm_comm_due(bigint, text) from public;

create or replace function public.crm_payroll_list(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); m text := coalesce(nullif(p ->> 'month', ''), to_char(public.crm_today(), 'YYYY-MM'));
begin
  perform public.crm_need(s, 'salary.manage');
  if m !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Mahina galat hai'; end if;
  return jsonb_build_object('month', m, 'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'id', u.id, 'name', u.name, 'role', u.role, 'mobile', u.mobile, 'status', u.status, 'designation', h.hr ->> 'designation', 'joining', h.hr ->> 'joining', 'exit', h.hr ->> 'exit_date',
      'sal', coalesce(h.sal, '{}'::jsonb), 'comm', public.crm_comm_due(u.id, m),
      'adv_out', coalesce((select sum(a.amount) from public.crm_staff_adv a where a.user_id = u.id and a.deleted_at is null), 0) - coalesce((select sum(z.adv_cut) from public.crm_salary_pay z where z.user_id = u.id and z.deleted_at is null), 0),
      'pay', (select to_jsonb(z) - 'deleted_at' - 'deleted_by' - 'delete_reason' from public.crm_salary_pay z where z.user_id = u.id and z.month = m and z.deleted_at is null)
    ) order by u.name)
    from public.crm_users u left join public.crm_staff_hr h on h.user_id = u.id
    where u.role in ('manager', 'staff', 'hr', 'marketing') and (u.status = 'active' or exists (select 1 from public.crm_salary_pay z where z.user_id = u.id and z.month = m and z.deleted_at is null))), '[]'::jsonb));
end $$;

create or replace function public.crm_salary_pay(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); uid_ bigint := (p ->> 'user_id')::bigint; m text := p ->> 'month'; u public.crm_users; h public.crm_staff_hr;
        basic numeric; allw numeric; ded numeric; bonus numeric := public.crm_num(p -> 'bonus'); xded numeric := public.crm_num(p -> 'deduction'); acut numeric := public.crm_num(p -> 'adv_cut');
        outst numeric; net numeric; cm jsonb; cs numeric := 0; incl boolean := coalesce((p ->> 'include_comm')::boolean, true); d date; md text := left(coalesce(nullif(p ->> 'mode', ''), 'bank'), 20); ex public.crm_expenses; r public.crm_salary_pay;
begin
  perform public.crm_need(s, 'salary.manage');
  if m is null or m !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Mahina galat hai'; end if;
  select * into u from public.crm_users where id = uid_;
  if u.id is null or u.role not in ('manager', 'staff', 'hr', 'marketing') then raise exception 'Is ID ki salary yahan se nahi hoti'; end if;
  select * into h from public.crm_staff_hr where user_id = uid_;
  basic := public.crm_num(h.sal -> 'monthly'); allw := public.crm_num(h.sal -> 'allowance'); ded := public.crm_num(h.sal -> 'deduction');
  if basic <= 0 then raise exception 'Pehle is staff ki monthly salary set karein'; end if;
  if bonus < 0 or xded < 0 or acut < 0 then raise exception 'Amount galat hai'; end if;
  if exists (select 1 from public.crm_salary_pay where user_id = uid_ and month = m and deleted_at is null) then raise exception 'Is mahine ki salary pehle hi di ja chuki hai'; end if;
  outst := coalesce((select sum(amount) from public.crm_staff_adv where user_id = uid_ and deleted_at is null), 0) - coalesce((select sum(adv_cut) from public.crm_salary_pay where user_id = uid_ and deleted_at is null), 0);
  if acut > outst then raise exception 'Advance sirf % baaki hai', outst; end if;
  cm := public.crm_comm_due(uid_, m);
  if incl then cs := public.crm_num(cm -> 'sum'); end if;
  net := round(basic + allw + bonus + cs - ded - xded - acut, 2);
  if net <= 0 then raise exception 'Net salary zero se zyada honi chahiye'; end if;
  begin d := coalesce(nullif(p ->> 'paid_on', '')::date, public.crm_today()); exception when others then raise exception 'Tareekh galat hai'; end;
  if d > public.crm_today() + 1 or d < date '2015-01-01' then raise exception 'Tareekh galat hai'; end if;
  insert into public.crm_expenses(spent_on, category, vendor, amount, gst_amount, mode, note, created_by)
  values (d, 'Salary', left(u.name, 120), net, 0, md, 'Salary ' || m || case when cs > 0 then ' (commission ₹' || cs || ' sahit)' else '' end || coalesce(nullif(' — ' || left(trim(coalesce(p ->> 'note', '')), 200), ' — '), ''), (s).uid) returning * into ex;
  insert into public.crm_salary_pay(user_id, month, basic, allowance, bonus, deduction, adv_cut, net, paid_on, mode, note, expense_id, created_by, commission, comm_ids)
  values (uid_, m, basic, allw, bonus, ded + xded, acut, net, d, md, left(trim(coalesce(p ->> 'note', '')), 200), ex.id, (s).uid, cs, case when incl then coalesce(cm -> 'ids', '[]'::jsonb) else '[]'::jsonb end) returning * into r;
  if incl and cs > 0 then
    update public.crm_records set status = 'paid', data = data || jsonb_build_object('paid_on', public.crm_today()::text, 'salary_month', m, 'salary_id', r.id), updated_at = now()
      where kind = 'earning' and id in (select (x)::bigint from jsonb_array_elements_text(cm -> 'ids') x);
  end if;
  perform public.crm_log(s, 'salary_pay', 'user', uid_, 'Salary di: ' || u.name || ' (' || m || ')');
  return to_jsonb(r) - 'deleted_at' - 'deleted_by' - 'delete_reason';
end $$;

create or replace function public.crm_salary_undo(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_salary_pay; why text := left(trim(coalesce(p ->> 'reason', '')), 200);
begin
  perform public.crm_need(s, 'salary.manage');
  if length(why) < 3 then raise exception 'Wajah likhein'; end if;
  select * into r from public.crm_salary_pay where id = (p ->> 'id')::bigint and deleted_at is null;
  if r.id is null then raise exception 'Salary entry nahi mili'; end if;
  update public.crm_salary_pay set deleted_at = now(), deleted_by = (s).uid, delete_reason = why where id = r.id;
  update public.crm_records set status = 'due', data = (data - 'paid_on' - 'salary_month' - 'salary_id'), updated_at = now()
    where kind = 'earning' and status = 'paid' and (data ->> 'salary_id') = r.id::text;
  update public.crm_expenses set deleted_at = now(), deleted_by = (s).uid, delete_reason = 'Salary wapas: ' || why where id = r.expense_id and deleted_at is null;
  perform public.crm_log(s, 'salary_undo', 'user', r.user_id, 'Salary entry hata di: ' || public.crm_uname(r.user_id) || ' (' || r.month || ') — ' || why);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.crm_my_pay(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token');
begin
  if (s).uid is null or (s).uid = 0 then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'month', z.month, 'basic', z.basic, 'allowance', z.allowance, 'bonus', z.bonus, 'deduction', z.deduction, 'adv_cut', z.adv_cut, 'commission', z.commission, 'net', z.net, 'paid_on', z.paid_on, 'mode', z.mode) order by z.month desc)
    from (select * from public.crm_salary_pay where user_id = (s).uid and deleted_at is null order by month desc limit 24) z), '[]'::jsonb);
end $$;

grant execute on function public.crm_payroll_list(jsonb), public.crm_salary_pay(jsonb), public.crm_salary_undo(jsonb), public.crm_my_pay(jsonb) to anon, authenticated;


-- Round 47 (C): Attendance (hazri) + Leave. Staff khud check-in/out + leave maange; HR / Manager sabki hazri aur leave approve. Salary me sirf suggestion (deduction khud tay karein).
create table if not exists public.crm_attendance (
  id bigserial primary key, user_id bigint not null, day date not null,
  status text not null check (status in ('present', 'absent', 'half', 'leave', 'unpaid', 'holiday')),
  in_time text, out_time text, note text not null default '', leave_id bigint, marked_by bigint, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (user_id, day));
create table if not exists public.crm_leave (
  id bigserial primary key, user_id bigint not null, from_date date not null, to_date date not null, days numeric(5,1) not null default 1,
  kind text not null default 'Casual' check (kind in ('Casual', 'Sick', 'Paid', 'Unpaid')), reason text not null default '',
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  decided_by bigint, decided_at timestamptz, decision_note text not null default '', created_at timestamptz not null default now());
create index if not exists crm_leave_u on public.crm_leave (user_id, from_date);
create index if not exists crm_att_day on public.crm_attendance (day);
alter table public.crm_attendance enable row level security;
alter table public.crm_leave enable row level security;

create or replace function public.crm__att_mgr(s public.crm_ses) returns boolean language sql stable as $$ select public.crm_is_admin(s) or public.crm_can(s, 'staff.hr') or public.crm_can(s, 'staff.manage') $$;
create or replace function public.crm__att_staff(uid_ bigint) returns boolean language sql stable security definer set search_path = public as $$ select exists (select 1 from public.crm_users where id = uid_ and role in ('manager', 'staff', 'hr', 'marketing')) $$;
create or replace function public.crm__workdays(a date, b date) returns numeric language sql immutable as $$ select count(*)::numeric from generate_series(a, b, interval '1 day') g where extract(dow from g) <> 0 $$;

-- ek din ki hazri: self ('in' / 'out') ya manager ('set')
create or replace function public.crm_att_mark(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); act text := coalesce(nullif(p ->> 'action', ''), 'set'); uid_ bigint; d date; st text := coalesce(p ->> 'status', 'present'); r public.crm_attendance; nowt text := to_char(now() at time zone 'Asia/Kolkata', 'HH24:MI');
        it text := nullif(left(coalesce(p ->> 'in_time', ''), 5), ''); ot text := nullif(left(coalesce(p ->> 'out_time', ''), 5), ''); nt text := left(trim(coalesce(p ->> 'note', '')), 200);
begin
  if act in ('in', 'out') then
    uid_ := (s).uid;
    if uid_ is null or uid_ = 0 or not public.crm__att_staff(uid_) then raise exception 'Check-in sirf staff ID se hota hai'; end if;
    d := public.crm_today();
    select * into r from public.crm_attendance where user_id = uid_ and day = d;
    if act = 'in' then
      if r.id is not null and r.status in ('present', 'half') and r.in_time is not null then raise exception 'Aaj ka check-in ho chuka (%)', r.in_time; end if;
      if r.id is not null and r.status in ('leave', 'unpaid', 'holiday') then raise exception 'Aaj aapki % marked hai', r.status; end if;
      insert into public.crm_attendance(user_id, day, status, in_time, note, marked_by) values (uid_, d, 'present', nowt, nt, uid_)
        on conflict (user_id, day) do update set status = 'present', in_time = excluded.in_time, note = excluded.note, updated_at = now() returning * into r;
    else
      if r.id is null or r.in_time is null then raise exception 'Pehle check-in karein'; end if;
      if r.out_time is not null then raise exception 'Aaj ka check-out ho chuka (%)', r.out_time; end if;
      update public.crm_attendance set out_time = nowt, updated_at = now() where id = r.id returning * into r;
    end if;
    return to_jsonb(r);
  end if;
  -- manager marks
  if not public.crm__att_mgr(s) then raise exception 'Hazri lagane ki permission nahi hai'; end if;
  uid_ := nullif(p ->> 'user_id', '')::bigint;
  if uid_ is null or not public.crm__att_staff(uid_) then raise exception 'Staff chunein'; end if;
  begin d := (p ->> 'day')::date; exception when others then raise exception 'Tareekh galat hai'; end;
  if d is null or d > public.crm_today() or d < date '2020-01-01' then raise exception 'Tareekh galat hai (aage ki hazri nahi lagti)'; end if;
  if st = 'clear' then
    delete from public.crm_attendance where user_id = uid_ and day = d;
    perform public.crm_log(s, 'attendance', 'user', uid_, 'Hazri hatai: ' || public.crm_uname(uid_) || ' ' || d);
    return jsonb_build_object('ok', true, 'cleared', true);
  end if;
  if st not in ('present', 'absent', 'half', 'leave', 'unpaid', 'holiday') then raise exception 'Status galat hai'; end if;
  insert into public.crm_attendance(user_id, day, status, in_time, out_time, note, marked_by) values (uid_, d, st, it, ot, nt, (s).uid)
    on conflict (user_id, day) do update set status = excluded.status, in_time = excluded.in_time, out_time = excluded.out_time, note = excluded.note, marked_by = excluded.marked_by, updated_at = now() returning * into r;
  perform public.crm_log(s, 'attendance', 'user', uid_, 'Hazri: ' || public.crm_uname(uid_) || ' ' || d || ' — ' || st);
  return to_jsonb(r);
end $$;

-- aaj ki apni hazri + is mahine ka hisab (Profile card)
create or replace function public.crm_att_me(p jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); uid_ bigint := (s).uid; m text := to_char(public.crm_today(), 'YYYY-MM'); fr date; r public.crm_attendance;
begin
  if uid_ is null or uid_ = 0 or not public.crm__att_staff(uid_) then return jsonb_build_object('staff', false); end if;
  fr := to_date(m || '-01', 'YYYY-MM-DD');
  select * into r from public.crm_attendance where user_id = uid_ and day = public.crm_today();
  return jsonb_build_object('staff', true, 'today', case when r.id is null then null else to_jsonb(r) end, 'month', m,
    'sum', (select jsonb_build_object('present', count(*) filter (where status = 'present'), 'half', count(*) filter (where status = 'half'), 'absent', count(*) filter (where status = 'absent'),
        'leave', count(*) filter (where status = 'leave'), 'unpaid', count(*) filter (where status = 'unpaid')) from public.crm_attendance where user_id = uid_ and day >= fr and day < (fr + interval '1 month')::date));
end $$;

-- mahine ki poori hazri (manager: sab staff, staff: sirf apni)
create or replace function public.crm_att_month(p jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); m text := coalesce(nullif(p ->> 'month', ''), to_char(public.crm_today(), 'YYYY-MM')); fr date; mgr boolean := public.crm__att_mgr(s); me bigint := (s).uid;
begin
  if m !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Mahina galat hai'; end if;
  fr := to_date(m || '-01', 'YYYY-MM-DD');
  if not mgr and (me is null or me = 0) then raise exception 'Permission nahi hai'; end if;
  return jsonb_build_object('month', m, 'mgr', mgr, 'days', extract(day from (fr + interval '1 month' - interval '1 day'))::int, 'work', public.crm__workdays(fr, (fr + interval '1 month')::date - 1),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'role', u.role,
        'att', coalesce((select jsonb_object_agg(to_char(a.day, 'YYYY-MM-DD'), jsonb_build_object('s', a.status, 'in', a.in_time, 'out', a.out_time, 'n', a.note)) from public.crm_attendance a where a.user_id = u.id and a.day >= fr and a.day < (fr + interval '1 month')::date), '{}'::jsonb)) order by u.name)
      from public.crm_users u where u.role in ('manager', 'staff', 'hr', 'marketing') and (mgr or u.id = me) and (u.status = 'active' or exists (select 1 from public.crm_attendance a where a.user_id = u.id and a.day >= fr and a.day < (fr + interval '1 month')::date))), '[]'::jsonb));
end $$;

create or replace function public.crm_leave_apply(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); uid_ bigint := (s).uid; a date; b date; k text := coalesce(nullif(p ->> 'kind', ''), 'Casual'); dys numeric; r public.crm_leave; why text := left(trim(coalesce(p ->> 'reason', '')), 300);
begin
  if uid_ is null or uid_ = 0 or not public.crm__att_staff(uid_) then raise exception 'Leave sirf staff ID se maangi jaati hai'; end if;
  begin a := (p ->> 'from')::date; b := coalesce(nullif(p ->> 'to', '')::date, a); exception when others then raise exception 'Tareekh galat hai'; end;
  if a is null or b < a then raise exception 'Tareekh galat hai'; end if;
  if a < public.crm_today() - 7 then raise exception 'Itni purani tareekh ki leave nahi maangi ja sakti (7 din tak)'; end if;
  if b - a > 60 then raise exception 'Ek baar me 60 din se zyada ki leave nahi'; end if;
  if k not in ('Casual', 'Sick', 'Paid', 'Unpaid') then raise exception 'Leave ka prakar chunein'; end if;
  if length(why) < 3 then raise exception 'Leave ki wajah likhein'; end if;
  dys := public.crm__workdays(a, b);
  if dys <= 0 then raise exception 'In tareekhon me sirf Sunday (weekly off) hai'; end if;
  if exists (select 1 from public.crm_leave where user_id = uid_ and status in ('pending', 'approved') and from_date <= b and to_date >= a) then raise exception 'In tareekhon me aapki leave pehle se maangi hui hai'; end if;
  if p ? 'half' and (p ->> 'half') = 'true' and a = b then dys := 0.5; end if;
  insert into public.crm_leave(user_id, from_date, to_date, days, kind, reason) values (uid_, a, b, dys, k, why) returning * into r;
  perform public.crm_log(s, 'leave_apply', 'user', uid_, 'Leave maangi: ' || public.crm_uname(uid_) || ' ' || a || ' se ' || b || ' (' || k || ')');
  return to_jsonb(r);
end $$;

create or replace function public.crm_leave_list(p jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); mgr boolean := public.crm__att_mgr(s); me bigint := (s).uid; st text := nullif(p ->> 'status', ''); mine boolean := coalesce((p ->> 'mine')::boolean, false);
begin
  if not mgr and (me is null or me = 0) then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'user_id', l.user_id, 'name', public.crm_uname(l.user_id), 'from', l.from_date, 'to', l.to_date, 'days', l.days, 'kind', l.kind, 'reason', l.reason,
      'status', l.status, 'decided_by', public.crm_uname(l.decided_by), 'decided_at', l.decided_at, 'note', l.decision_note, 'created_at', l.created_at) order by (l.status = 'pending') desc, l.from_date desc, l.id desc)
    from (select * from public.crm_leave where (st is null or status = st) and ((mgr and not mine) or user_id = me) order by from_date desc, id desc limit 300) l), '[]'::jsonb);
end $$;

create or replace function public.crm_leave_decide(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_leave; act text := coalesce(p ->> 'action', ''); nt text := left(trim(coalesce(p ->> 'note', '')), 200); g date; stt text;
begin
  select * into r from public.crm_leave where id = (p ->> 'id')::bigint;
  if r.id is null then raise exception 'Leave nahi mili'; end if;
  if act = 'cancel' then
    if r.user_id <> (s).uid then raise exception 'Sirf apni leave cancel kar sakte hain'; end if;
    if r.status <> 'pending' then raise exception 'Sirf pending leave cancel hoti hai'; end if;
    update public.crm_leave set status = 'cancelled', decided_at = now() where id = r.id returning * into r;
    return to_jsonb(r);
  end if;
  if not public.crm__att_mgr(s) then raise exception 'Leave approve karne ki permission nahi hai'; end if;
  if r.status <> 'pending' then raise exception 'Ye leave pehle hi % ho chuki', r.status; end if;
  if r.user_id = (s).uid and not public.crm_is_admin(s) then raise exception 'Apni leave khud approve nahi kar sakte'; end if;
  if act = 'reject' and length(nt) < 3 then raise exception 'Reject karne ki wajah likhein'; end if;
  if act not in ('approve', 'reject') then raise exception 'Galat action'; end if;
  update public.crm_leave set status = case act when 'approve' then 'approved' else 'rejected' end, decided_by = (s).uid, decided_at = now(), decision_note = nt where id = r.id returning * into r;
  if act = 'approve' then
    stt := case when r.kind = 'Unpaid' then 'unpaid' else 'leave' end;
    for g in select x::date from generate_series(r.from_date, r.to_date, interval '1 day') x where extract(dow from x) <> 0 loop
      insert into public.crm_attendance(user_id, day, status, note, leave_id, marked_by) values (r.user_id, g, case when r.days = 0.5 then 'half' else stt end, r.kind || ' leave', r.id, (s).uid)
        on conflict (user_id, day) do update set status = excluded.status, note = excluded.note, leave_id = excluded.leave_id, marked_by = excluded.marked_by, updated_at = now() where public.crm_attendance.in_time is null;
    end loop;
  end if;
  perform public.crm_log(s, 'leave_' || act, 'user', r.user_id, 'Leave ' || act || ': ' || public.crm_uname(r.user_id) || ' ' || r.from_date || ' se ' || r.to_date);
  return to_jsonb(r);
end $$;

-- payroll list me hazri ka saar (salary pay ke time deduction suggest karne ke liye)
create or replace function public.crm_payroll_list(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); m text := coalesce(nullif(p ->> 'month', ''), to_char(public.crm_today(), 'YYYY-MM'));
begin
  perform public.crm_need(s, 'salary.manage');
  if m !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Mahina galat hai'; end if;
  return jsonb_build_object('month', m, 'work', public.crm__workdays(to_date(m || '-01', 'YYYY-MM-DD'), (to_date(m || '-01', 'YYYY-MM-DD') + interval '1 month')::date - 1), 'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'id', u.id, 'name', u.name, 'role', u.role, 'mobile', u.mobile, 'status', u.status, 'designation', h.hr ->> 'designation', 'joining', h.hr ->> 'joining', 'exit', h.hr ->> 'exit_date',
      'sal', coalesce(h.sal, '{}'::jsonb), 'comm', public.crm_comm_due(u.id, m),
      'att', (select jsonb_build_object('present', count(*) filter (where x.status = 'present'), 'half', count(*) filter (where x.status = 'half'), 'absent', count(*) filter (where x.status = 'absent'), 'leave', count(*) filter (where x.status = 'leave'), 'unpaid', count(*) filter (where x.status = 'unpaid'))
        from public.crm_attendance x where x.user_id = u.id and to_char(x.day, 'YYYY-MM') = m),
      'adv_out', coalesce((select sum(a.amount) from public.crm_staff_adv a where a.user_id = u.id and a.deleted_at is null), 0) - coalesce((select sum(z.adv_cut) from public.crm_salary_pay z where z.user_id = u.id and z.deleted_at is null), 0),
      'pay', (select to_jsonb(z) - 'deleted_at' - 'deleted_by' - 'delete_reason' from public.crm_salary_pay z where z.user_id = u.id and z.month = m and z.deleted_at is null)
    ) order by u.name)
    from public.crm_users u left join public.crm_staff_hr h on h.user_id = u.id
    where u.role in ('manager', 'staff', 'hr', 'marketing') and (u.status = 'active' or exists (select 1 from public.crm_salary_pay z where z.user_id = u.id and z.month = m and z.deleted_at is null))), '[]'::jsonb));
end $$;

grant execute on function public.crm_att_mark(jsonb), public.crm_att_me(jsonb), public.crm_att_month(jsonb), public.crm_leave_apply(jsonb), public.crm_leave_list(jsonb), public.crm_leave_decide(jsonb), public.crm_payroll_list(jsonb) to anon, authenticated;
revoke all on function public.crm__att_mgr(public.crm_ses), public.crm__att_staff(bigint), public.crm__workdays(date, date) from public;


-- Round 47 (D): Store Admin me naya product banate hi CRM Inventory me bhi (ek hi item, ek hi stock). Duplicate nahi banta.
create or replace function public.sp_admin_crm_cats(p_pass text) returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  perform public.sp_check(p_pass);
  return coalesce((select jsonb_agg(c order by c) from (select distinct trim(data ->> 'category') c from public.crm_records where kind = 'item' and deleted_at is null and coalesce(data ->> 'type', 'product') = 'product' and trim(coalesce(data ->> 'category', '')) <> '') z), '[]'::jsonb);
end $$;

create or replace function public.sp_admin_crm_item_add(p_pass text, p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare tok text := 'ADMADD-' || md5(random()::text || clock_timestamp()::text); r jsonb; iid bigint; ex public.crm_records;
        nm text := left(trim(coalesce(p ->> 'name', '')), 200); sid text := trim(coalesce(p ->> 'store_id', '')); gst numeric := coalesce(nullif(p ->> 'gst', '')::numeric, 18);
        incl numeric := public.crm_num(p -> 'price'); mrp numeric := public.crm_num(p -> 'mrp'); cost numeric := public.crm_num(p -> 'cost'); stk numeric := public.crm_num(p -> 'stock');
        w numeric := public.crm_num(p -> 'web'); a numeric := public.crm_num(p -> 'app'); cat text := left(trim(coalesce(p ->> 'category', '')), 80); dd jsonb;
begin
  perform public.sp_check(p_pass);
  if sid = '' then raise exception 'Store product id nahi mili'; end if;
  select * into ex from public.crm_records where kind = 'item' and deleted_at is null and (data #>> '{store,store_id}') = sid order by id limit 1;
  if ex.id is not null then return jsonb_build_object('ok', true, 'id', ex.id, 'existed', true); end if;
  if length(nm) < 3 then raise exception 'Product ka naam likhein (kam se kam 3 akshar)'; end if;
  if gst < 0 or gst > 40 then raise exception 'GST galat hai'; end if;
  if incl <= 0 then raise exception 'Selling price likhein'; end if;
  if cost <= 0 then raise exception 'Kharid rate (purchase price) zaroori hai — CRM Inventory ke liye'; end if;
  if cat = '' then raise exception 'CRM Category likhein / chunein'; end if;
  if stk < 0 or stk <> floor(stk) then raise exception 'Stock poori sankhya me likhein'; end if;
  if w < 0 or a < 0 or w <> floor(w) or a <> floor(a) then raise exception 'Online qty poori sankhya me likhein'; end if;
  if w + a > stk then raise exception 'Online qty (Web % + App %) stock % se zyada nahi ho sakti', w, a, stk; end if;
  dd := jsonb_build_object('type', 'product', 'name', nm, 'brand', left(trim(coalesce(p ->> 'brand', '')), 80), 'sku', left(trim(coalesce(p ->> 'sku', '')), 60), 'unit', coalesce(nullif(trim(p ->> 'unit'), ''), 'Nos'),
    'category', cat, 'price', round(incl / (1 + gst / 100), 2), 'gst', gst, 'mrp', case when mrp > incl then mrp else 0 end, 'cost_price', cost, 'stock', stk, 'desc', left(coalesce(p ->> 'desc', ''), 2000), 'hsn', left(trim(coalesce(p ->> 'hsn', '')), 10));
  insert into public.crm_sessions(token, user_id, role, expires_at) values (tok, 0, 'admin', now() + interval '2 minutes');
  begin
    r := public.crm_save(jsonb_build_object('token', tok, 'kind', 'item', 'data', dd));
  exception when others then delete from public.crm_sessions where token = tok; raise; end;
  delete from public.crm_sessions where token = tok;
  iid := (r ->> 'id')::bigint;
  update public.crm_records set data = jsonb_set(data, '{store}', coalesce(data -> 'store', '{}'::jsonb) || jsonb_build_object('status', 'published', 'store_id', sid, 'via', 'store_admin', 'reviewed_at', now(), 'note', '')), updated_at = now() where id = iid;
  if w + a > 0 then perform public.crm__online_apply(iid, 'set', w, a); end if;
  insert into public.crm_activity(user_id, user_name, role, action, kind, rec_id, summary) values (0, 'Store Admin', 'admin', 'store_add', 'item', iid, 'Store Admin se naya product CRM Inventory me juda: ' || nm || ' (stock ' || stk || ', online Web ' || w || ' + App ' || a || ')');
  return jsonb_build_object('ok', true, 'id', iid, 'ref', r ->> 'ref', 'sku', (select data ->> 'sku' from public.crm_records where id = iid));
end $$;
grant execute on function public.sp_admin_crm_cats(text), public.sp_admin_crm_item_add(text, jsonb) to anon, authenticated;


-- Round 47 (E): Ek hi price har jagah (CRM = Web Shop = Store App = order). CRM item hi authority; store product ka mrp / offer / gst CRM se hi tay hota hai.
create or replace function public.crm_price_incl(d jsonb) returns numeric language sql immutable as $$ select round(public.crm_num(d -> 'price') * (1 + public.crm_num(d -> 'gst') / 100)) $$;

-- store data me CRM se jude (published) products ke daam CRM ke hisab se laga do (admin ne kuch bhi bheja ho)
create or replace function public.sp__apply_crm_prices(d jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb; changed boolean := false;
begin
  if d is null or jsonb_typeof(d -> 'products') <> 'array' then return d; end if;
  select jsonb_agg(case when m.item_id is null then e.e else e.e || jsonb_build_object('mrp', m.nmrp, 'offer', m.noffer, 'gst', m.gst) end order by e.ord) into out_
  from jsonb_array_elements(d -> 'products') with ordinality as e(e, ord)
  left join lateral (
    select c.id as item_id, public.crm_num(c.data -> 'gst') as gst,
      case when public.crm_num(c.data -> 'mrp') > public.crm_price_incl(c.data) then public.crm_num(c.data -> 'mrp') else public.crm_price_incl(c.data) end as nmrp,
      case when public.crm_num(c.data -> 'mrp') > public.crm_price_incl(c.data) then public.crm_price_incl(c.data) else 0 end as noffer
    from public.crm_records c where c.kind = 'item' and c.deleted_at is null and (c.data #>> '{store,store_id}') = (e.e ->> 'id') and (c.data #>> '{store,status}') = 'published' and public.crm_price_incl(c.data) > 0
    order by c.id limit 1) m on true;
  return jsonb_set(d, '{products}', coalesce(out_, '[]'::jsonb));
end $$;

create or replace function public.sp_store_price_lock() returns trigger language plpgsql as $$
begin
  if NEW.id = 'main' then NEW.data := public.sp__apply_crm_prices(NEW.data); end if;
  return NEW;
end $$;
drop trigger if exists sp_store_price_lock on public.sp_store;
create trigger sp_store_price_lock before insert or update on public.sp_store for each row execute function public.sp_store_price_lock();

-- CRM me price / GST / MRP / store-link badalte hi store me turant wahi price (sirf jab kuch badla ho)
create or replace function public.crm_item_price_push_trg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (NEW.data #>> '{store,status}') = 'published' and coalesce(NEW.data #>> '{store,store_id}', '') <> '' and NEW.deleted_at is null
     and (TG_OP = 'INSERT' or (OLD.data -> 'price', OLD.data -> 'gst', OLD.data -> 'mrp', OLD.data #> '{store,store_id}', OLD.data #> '{store,status}') is distinct from (NEW.data -> 'price', NEW.data -> 'gst', NEW.data -> 'mrp', NEW.data #> '{store,store_id}', NEW.data #> '{store,status}')) then
    update public.sp_store set updated_at = now() where id = 'main';
  end if;
  return null;
end $$;
drop trigger if exists crm_item_price_push on public.crm_records;
create trigger crm_item_price_push after insert or update on public.crm_records for each row when (NEW.kind = 'item') execute function public.crm_item_price_push_trg();

-- order ke samay: browser jo daam bheje wo store / CRM ke daam se milna chahiye (purana ya galat daam nahi chalega)
create or replace function public.sp_price_guard(p_items jsonb, p_subtotal numeric default null) returns void language plpgsql stable security definer set search_path = public as $$
declare i jsonb; pr jsonb; exp_ numeric; got numeric; msg text := ''; sum_ numeric := 0; prods jsonb;
begin
  select data -> 'products' into prods from public.sp_store where id = 'main';
  if prods is null or jsonb_typeof(p_items) <> 'array' then return; end if;
  for i in select * from jsonb_array_elements(p_items) loop
    select e into pr from jsonb_array_elements(prods) e where e ->> 'id' = i ->> 'id' limit 1;
    if pr is null then continue; end if;
    exp_ := case when public.crm_num(pr -> 'offer') > 0 then public.crm_num(pr -> 'offer') else public.crm_num(pr -> 'mrp') end;
    got := public.crm_num(i -> 'price');
    sum_ := sum_ + exp_ * greatest(public.crm_num(i -> 'qty'), 1);
    if i ? 'price' and abs(got - exp_) > 0.5 then
      msg := msg || coalesce(nullif(pr ->> 'titleEn', ''), pr ->> 'title', 'item') || ' (ab ₹' || exp_ || '); ';
    end if;
  end loop;
  if msg <> '' then raise exception 'PRICE_CHANGED: %', left(msg, 300); end if;
  if p_subtotal is not null and p_subtotal > 0 and abs(p_subtotal - sum_) > 1.5 and sum_ > 0 and not exists (select 1 from jsonb_array_elements(p_items) x where not (x ? 'price')) then
    raise exception 'PRICE_CHANGED: Cart ka total badal gaya hai (ab ₹%)', sum_; end if;
end $$;
revoke all on function public.sp_price_guard(jsonb, numeric) from public;

CREATE OR REPLACE FUNCTION public.sp_place_order(p_order jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  perform public.sp_price_guard(p_order -> 'items', public.crm_num(p_order -> 'subtotal'));   -- Round 47: ek hi price har jagah
  perform public.sp_stock_guard(p_order -> 'items', public.sp_order_channel(p_order));

  -- identity always comes from the account, never from the browser
  o := (p_order - 'token' - 'customer_id')
       || jsonb_build_object(
            'name', left(coalesce(nullif(trim(u.name), ''), trim(p_order->>'name')), 80),
            'phone', coalesce(u.mobile, ''),
            'customer_id', u.id::text,
            'login_method', 'email_otp',
            'payment_status', 'awaiting_payment', 'channel', public.sp_order_channel(p_order));

  if coalesce(trim(o->>'name'), '') = '' or coalesce(trim(o->>'phone'), '') = '' then
    raise exception 'Naam aur mobile account mein save karein';
  end if;

  o := o || jsonb_build_object('order_no', public.crm_next_no('order'));
  insert into public.sp_orders(data) values (o) returning id into new_id;
  perform public.sp_notify_admin('Naya order ' || (o->>'order_no') || ' — ' || (o->>'name'),
    '<p>Naya order aaya hai: <b>' || (o->>'order_no') || '</b></p><p>' || (o->>'name') || ' · ' || (o->>'phone') || '</p><p>Total: ₹' || (o->>'total') || ' — payment ka UTR aane par dobara notification milega. Admin panel mein dekhein.</p>');
  return new_id;
end $function$;

-- ============================================================================
-- ROUND 48 — Pincode ke hisaab se delivery charge, Product / Service customer flow (4 naye step), customer ki ghoshna (OTP ki jagah), installation add-on.
--   Staging par chalayein. Dobara chalana safe hai (create or replace / if not exists).
-- ============================================================================

-- =====================================================================================================
-- ROUND 48 / A — Pincode ke hisaab se delivery charge (courier / khud), complete project par free, GST nahi.
--   Rules: sp_ship_rules (scope all / state / district / area / pin — pincode availability jaisa). Sabse khaas rule jeetta hai.
--   Charge = base_charge + (kg - base_kg ke upar har poore kg) x per_kg. Free: free_above se upar ya poora cart "complete project" (CRM template) ho.
--   Rule na mile to purani setting (settings.shipping: local / baaki / freeAbove) chalti hai. Order par server wapas hisaab karke check karta hai.
-- =====================================================================================================
create table if not exists public.sp_ship_rules (
  id          bigserial primary key,
  scope       text    not null check (scope in ('all', 'state', 'district', 'area', 'pin')),
  value       text    not null,
  mode        text    not null default 'courier' check (mode in ('self', 'courier')),
  courier     text    not null default '',
  base_charge numeric not null default 0 check (base_charge >= 0),
  base_kg     numeric not null default 5 check (base_kg >= 0),
  per_kg      numeric not null default 0 check (per_kg >= 0),
  free_above  numeric not null default 0 check (free_above >= 0),
  eta_min     int     not null default 0,
  eta_max     int     not null default 0,
  note        text    not null default '',
  updated_at  timestamptz not null default now(),
  unique (scope, value)
);
alter table public.sp_ship_rules enable row level security;

-- quote: public (anon bhi dekh sake: product page / cart). Sirf hisaab deta hai, kuch badalta nahi.
create or replace function public.sp_ship_quote(p_pin text, p_items jsonb, p_subtotal numeric default 0, p_pickup boolean default false)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare pin text := regexp_replace(coalesce(p_pin, ''), '\D', '', 'g'); st text; di text; r public.sp_ship_rules; sh jsonb; prods jsonb; it jsonb; pr jsonb;
        q numeric; kg numeric := 0; nsub numeric := 0; n_non int := 0; n_proj int := 0; ch numeric := 0; fr boolean := false; why text := 'rule'; known boolean := false;
        loc boolean; ct text; ok_pin boolean := pin ~ '^[1-9][0-9]{5}$';
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' then p_items := '[]'::jsonb; end if;
  if jsonb_array_length(p_items) > 300 then raise exception 'Cart bahut bada hai'; end if;
  select data -> 'products', data #> '{settings,shipping}' into prods, sh from public.sp_store where id = 'main';
  prods := coalesce(prods, '[]'::jsonb); sh := coalesce(sh, '{}'::jsonb);
  for it in select * from jsonb_array_elements(p_items) loop
    q := greatest(coalesce(public.crm_num(it -> 'qty'), 1), 0);
    select e into pr from jsonb_array_elements(prods) e where e ->> 'id' = it ->> 'id' limit 1;
    ct := null;
    if pr is not null and coalesce(pr ->> 'crm', '') ~ '^[0-9]+$' then
      select data ->> 'type' into ct from public.crm_records where id = (pr ->> 'crm')::bigint and kind = 'item';
    end if;
    if coalesce(ct, '') = 'project' or coalesce(pr ->> 'proj', '') = 'true' then n_proj := n_proj + 1;
    else
      n_non := n_non + 1; kg := kg + q * coalesce(public.crm_num(pr -> 'weight'), 0);
      nsub := nsub + q * coalesce(public.crm_num(it -> 'price'), 0);
    end if;
  end loop;
  if nsub <= 0 then nsub := greatest(coalesce(p_subtotal, 0), 0); end if;

  if p_pickup then
    return jsonb_build_object('ok', true, 'pin', pin, 'known', true, 'charge', 0, 'free', true, 'reason', 'pickup', 'mode', 'pickup', 'courier', '', 'eta_min', 0, 'eta_max', 0, 'kg', kg, 'gst', 0);
  end if;
  if n_non = 0 and n_proj > 0 then   -- poora cart complete project: delivery free (aur uspar GST bhi nahi)
    select * into r from public.sp_ship_rules where false;
    if ok_pin then
      select state_u, district_u into st, di from public.sp_pin_master where pincode = pin;
      select * into r from public.sp_ship_rules x where x.scope = 'all' or (x.scope = 'pin' and x.value = pin) or (x.scope = 'state' and st is not null and x.value = st)
         or (x.scope = 'district' and st is not null and x.value = st || '|' || di) or (x.scope = 'area' and exists (select 1 from public.sp_pin_areas a where a.name = x.value and pin = any (a.pins)))
       order by (case x.scope when 'pin' then 5 when 'area' then 4 when 'district' then 3 when 'state' then 2 else 1 end) desc limit 1;
    end if;
    return jsonb_build_object('ok', true, 'pin', pin, 'known', true, 'charge', 0, 'free', true, 'reason', 'project', 'mode', coalesce(r.mode, 'courier'), 'courier', coalesce(r.courier, ''),
                              'eta_min', coalesce(r.eta_min, 0), 'eta_max', coalesce(r.eta_max, 0), 'kg', 0, 'gst', 0);
  end if;

  if ok_pin then
    select state_u, district_u into st, di from public.sp_pin_master where pincode = pin;
    select * into r from public.sp_ship_rules x where x.scope = 'all' or (x.scope = 'pin' and x.value = pin) or (x.scope = 'state' and st is not null and x.value = st)
       or (x.scope = 'district' and st is not null and x.value = st || '|' || di) or (x.scope = 'area' and exists (select 1 from public.sp_pin_areas a where a.name = x.value and pin = any (a.pins)))
     order by (case x.scope when 'pin' then 5 when 'area' then 4 when 'district' then 3 when 'state' then 2 else 1 end) desc limit 1;
  end if;
  if r.id is not null then
    known := true; ch := r.base_charge + ceil(greatest(kg - r.base_kg, 0)) * r.per_kg;
    if r.free_above > 0 and nsub >= r.free_above then ch := 0; fr := true; why := 'above'; end if;
    if ch = 0 then fr := true; end if;
    return jsonb_build_object('ok', true, 'pin', pin, 'known', true, 'charge', round(ch), 'free', fr, 'reason', why, 'mode', r.mode, 'courier', r.courier, 'eta_min', r.eta_min, 'eta_max', r.eta_max, 'kg', kg, 'gst', 0, 'note', r.note);
  end if;
  -- koi rule nahi: purani setting (settings.shipping)
  if coalesce(sh ->> 'enabled', 'true') = 'false' then
    return jsonb_build_object('ok', true, 'pin', pin, 'known', true, 'charge', 0, 'free', true, 'reason', 'off', 'mode', 'courier', 'courier', '', 'eta_min', 0, 'eta_max', 0, 'kg', kg, 'gst', 0);
  end if;
  loc := ok_pin and exists (select 1 from regexp_split_to_table(coalesce(sh ->> 'localPins', ''), '[,\s]+') x where x <> '' and pin like x || '%');
  if coalesce(public.crm_num(sh -> 'freeAbove'), 0) > 0 and nsub >= public.crm_num(sh -> 'freeAbove') then
    ch := 0; fr := true; why := 'above'; known := ok_pin;
  elsif loc then ch := coalesce(public.crm_num(sh -> 'localCharge'), 0); known := true; why := 'local';
  else ch := coalesce(public.crm_num(sh -> 'otherCharge'), 0); known := ok_pin; why := 'other'; end if;
  return jsonb_build_object('ok', true, 'pin', pin, 'known', known, 'charge', round(ch), 'free', ch = 0, 'reason', why, 'mode', case when loc then 'self' else 'courier' end, 'courier', '', 'eta_min', 0, 'eta_max', 0, 'kg', kg, 'gst', 0);
end $$;

-- server guard: browser kam delivery charge bhej kar bach nahi sakta
create or replace function public.sp_ship_guard(p_order jsonb) returns void language plpgsql stable security definer set search_path = public as $$
declare qt jsonb; pick boolean := coalesce(p_order ->> 'pickup', 'false') = 'true'; pin text := regexp_replace(coalesce(p_order ->> 'pincode', ''), '\D', '', 'g'); cl numeric := coalesce(public.crm_num(p_order -> 'shipping'), 0);
begin
  if not pick and pin !~ '^[1-9][0-9]{5}$' then return; end if;
  qt := public.sp_ship_quote(pin, p_order -> 'items', public.crm_num(p_order -> 'subtotal'), pick);
  if cl < (qt ->> 'charge')::numeric - 0.5 then
    raise exception 'DELIVERY_CHANGED: Delivery charge badal gaya hai (ab Rs %). Cart dobara kholkar order karein.', qt ->> 'charge';
  end if;
end $$;

-- admin (password wala, pincode rules jaisa)
create or replace function public.sp_ship_rules_list(p_pass text) returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  perform public.sp_check(p_pass);
  return coalesce((select jsonb_agg(to_jsonb(r) - 'updated_at' order by (case r.scope when 'all' then 0 when 'state' then 1 when 'district' then 2 when 'area' then 3 else 4 end), r.value) from public.sp_ship_rules r), '[]'::jsonb);
end $$;
create or replace function public.sp_ship_rule_save(p_pass text, p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare sc text := coalesce(p ->> 'scope', ''); v text; id_ bigint := nullif(p ->> 'id', '')::bigint; md text := coalesce(nullif(p ->> 'mode', ''), 'courier'); r public.sp_ship_rules;
begin
  perform public.sp_check(p_pass);
  if sc not in ('all', 'state', 'district', 'area', 'pin') then raise exception 'Scope galat hai'; end if;
  v := public.sp_pin_val(sc, p ->> 'value');
  if v is null then raise exception 'Value sahi likhein (pin: 6 ank, state / area: naam, district: STATE|DISTRICT)'; end if;
  if md not in ('self', 'courier') then raise exception 'Mode galat hai'; end if;
  if coalesce(public.crm_num(p -> 'base_charge'), 0) < 0 or coalesce(public.crm_num(p -> 'per_kg'), 0) < 0 then raise exception 'Charge negative nahi ho sakta'; end if;
  if id_ is not null then
    update public.sp_ship_rules set scope = sc, value = v, mode = md, courier = left(coalesce(p ->> 'courier', ''), 60), base_charge = coalesce(public.crm_num(p -> 'base_charge'), 0), base_kg = coalesce(public.crm_num(p -> 'base_kg'), 5),
      per_kg = coalesce(public.crm_num(p -> 'per_kg'), 0), free_above = coalesce(public.crm_num(p -> 'free_above'), 0), eta_min = coalesce(public.crm_num(p -> 'eta_min'), 0)::int, eta_max = coalesce(public.crm_num(p -> 'eta_max'), 0)::int,
      note = left(coalesce(p ->> 'note', ''), 200), updated_at = now() where id = id_ returning * into r;
    if r.id is null then raise exception 'Rule nahi mila'; end if;
  else
    insert into public.sp_ship_rules(scope, value, mode, courier, base_charge, base_kg, per_kg, free_above, eta_min, eta_max, note)
    values (sc, v, md, left(coalesce(p ->> 'courier', ''), 60), coalesce(public.crm_num(p -> 'base_charge'), 0), coalesce(public.crm_num(p -> 'base_kg'), 5), coalesce(public.crm_num(p -> 'per_kg'), 0),
            coalesce(public.crm_num(p -> 'free_above'), 0), coalesce(public.crm_num(p -> 'eta_min'), 0)::int, coalesce(public.crm_num(p -> 'eta_max'), 0)::int, left(coalesce(p ->> 'note', ''), 200))
    on conflict (scope, value) do update set mode = excluded.mode, courier = excluded.courier, base_charge = excluded.base_charge, base_kg = excluded.base_kg, per_kg = excluded.per_kg,
      free_above = excluded.free_above, eta_min = excluded.eta_min, eta_max = excluded.eta_max, note = excluded.note, updated_at = now() returning * into r;
  end if;
  return to_jsonb(r) - 'updated_at';
exception when unique_violation then raise exception 'Is scope + value ka rule pehle se hai';
end $$;
create or replace function public.sp_ship_rule_delete(p_pass text, p_id bigint) returns void language plpgsql security definer set search_path = public, extensions as $$
begin perform public.sp_check(p_pass); delete from public.sp_ship_rules where id = p_id; end $$;

-- order par server guard + order me delivery ki jaankari (mode / courier / eta) save
create or replace function public.sp_place_order(p_order jsonb)
returns bigint language plpgsql security definer set search_path to 'public' as $$
declare new_id bigint; u public.crm_users; o jsonb; qt jsonb; inst jsonb := '[]'::jsonb;
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
  perform public.sp_price_guard(p_order -> 'items', public.crm_num(p_order -> 'subtotal'));   -- Round 47: ek hi price har jagah
  perform public.sp_ship_guard(p_order);                                                      -- Round 48: pincode ke hisaab se delivery charge
  perform public.sp_stock_guard(p_order -> 'items', public.sp_order_channel(p_order));

  -- identity always comes from the account, never from the browser
  o := (p_order - 'token' - 'customer_id')
       || jsonb_build_object(
            'name', left(coalesce(nullif(trim(u.name), ''), trim(p_order->>'name')), 80),
            'phone', coalesce(u.mobile, ''),
            'customer_id', u.id::text,
            'login_method', 'email_otp',
            'payment_status', 'awaiting_payment', 'channel', public.sp_order_channel(p_order));

  if coalesce(trim(o->>'name'), '') = '' or coalesce(trim(o->>'phone'), '') = '' then
    raise exception 'Naam aur mobile account mein save karein';
  end if;

  qt := public.sp_ship_quote(p_order ->> 'pincode', p_order -> 'items', public.crm_num(p_order -> 'subtotal'), coalesce(p_order ->> 'pickup', 'false') = 'true');
  o := o || jsonb_build_object('delivery', jsonb_build_object('mode', qt ->> 'mode', 'courier', qt ->> 'courier', 'eta_min', qt -> 'eta_min', 'eta_max', qt -> 'eta_max', 'reason', qt ->> 'reason', 'free', qt -> 'free', 'kg', qt -> 'kg'));
  -- Round 48: installation ek optional add-on hai (sirf installOk wale product; charge baad me Service kaam ke bill me — order total me nahi judta)
  if jsonb_typeof(p_order -> 'install') = 'array' then
    select coalesce(jsonb_agg(jsonb_build_object('id', pr ->> 'id', 'name', left(coalesce(pr ->> 'title', pr ->> 'name'), 80), 'price', public.crm_num(pr -> 'installPrice'))), '[]'::jsonb) into inst
      from jsonb_array_elements(coalesce((select data -> 'products' from public.sp_store where id = 'main'), '[]'::jsonb)) pr
     where (pr ->> 'installOk') = 'true'
       and (pr ->> 'id') in (select jsonb_array_elements_text(p_order -> 'install'))
       and (pr ->> 'id') in (select it ->> 'id' from jsonb_array_elements(p_order -> 'items') it);
  end if;
  o := (o - 'install') || case when jsonb_array_length(inst) > 0 then jsonb_build_object('install', inst) else '{}'::jsonb end;
  o := o || jsonb_build_object('order_no', public.crm_next_no('order'));
  insert into public.sp_orders(data) values (o) returning id into new_id;
  perform public.sp_notify_admin('Naya order ' || (o->>'order_no') || ' — ' || (o->>'name'),
    '<p>Naya order aaya hai: <b>' || (o->>'order_no') || '</b></p><p>' || (o->>'name') || ' · ' || (o->>'phone') || '</p><p>Total: ₹' || (o->>'total') || ' — payment ka UTR aane par dobara notification milega.</p>' || case when jsonb_array_length(inst) > 0 then '<p><b>🔧 Installation add-on chahiye</b> — Service kaam banayein.</p>' else '' end || '<p>Admin panel mein dekhein.</p>');
  return new_id;
end $$;

-- =====================================================================================================
-- ROUND 48 / B — Customer flow: Product (naya) aur Service (naya) kram. 4 naye steps: 20 Stock Reserve, 21 Dispatch / Delivery, 22 Warranty Registration, 23 Job Done Report.
--   Product : Lead > Customer > Demo/Files > Quotation > Confirmation > Stock Reserve > Billing > Dispatch > Warranty > Referral > Complaint
--   Service : Lead > Customer > Site Visit > Quotation > Confirmation > Schedule+Technician > Job Done Report > Billing > Service report/Docs > Referral > AMC (agli baar) > Complaint
--   Purane steps wahi (8 Technician, 12 Billing, 14 Docs, 16 Referral, 17 AMC, 18 Complaint) — dobara use hote hain. Dobara chalana safe hai.
-- =====================================================================================================
CREATE OR REPLACE FUNCTION public.crm_wf_names()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select array['Add Customer','Conversation','Quotation','Site Visit','Blueprint','Confirmation','Apply Process','Hand Over Technician','Start Installation',
               'Verification / Commissioning','Net Metering','Finish Work','Subsidy Redeem','Send Demo / Files','Loan / Finance','Suggest / Referral','AMC / Maintenance','Complaint Status','Leads','Stock Reserve','Dispatch / Delivery','Warranty Registration','Job Done Report'] $function$;
create or replace function public.crm_wf_flow(ct text) returns int[] language sql immutable as $$
  select case
    when ct = 'Items only'  then array[19,1,2,14,3,6,20,12,21,22,16,18]                       -- Product customer
    when ct = 'Service'     then array[19,1,2,4,3,6,8,23,12,14,16,17,18]                      -- Service customer (cleaning, repair, shifting, audit, installation add-on)
    when ct = 'AMC only'        then array[19,1,2,17]                                        -- only a Maintenance / AMC plan
    when ct = 'Site visit only' then array[19,1,2,4]                                         -- only a Site Visit
    when ct = 'Residential' then array[19,1,2,14,3,4,5,6,7,15,8,9,10,11,12,13,16,17,18]      -- Project, subsidy applies
    else                         array[19,1,2,14,3,4,5,6,7,15,8,9,10,11,12,16,17,18] end $$;
create or replace function public.crm_wf_can_skip(n integer) returns boolean language sql immutable as $$ select n in (4, 5, 11, 13, 14, 15, 16, 17, 18, 20) $$;
CREATE OR REPLACE FUNCTION public.crm_wf_fields()
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select '{
   "4":  [{"k":"roof_type","l":"Chhat ka prakar"},{"k":"roof_area","l":"Chhat ka area (sq ft)"},{"k":"shadow","l":"Chhaya / shadow"},{"k":"phase","l":"Connection (1 / 3 phase)"},{"k":"structure_ht","l":"Structure ki height (ft)"}],
   "5":  [{"k":"kw_final","l":"Final plant size (kW)"},{"k":"panels","l":"Panels (sankhya)"}],
   "7":  [{"k":"discom","l":"DISCOM","req":true},{"k":"consumer_no","l":"Consumer number","req":true},{"k":"sanctioned_load","l":"Sanctioned load (kW)"},{"k":"category","l":"Category (LMV-1 etc.)"},{"k":"portal_app_no","l":"Portal application no."},{"k":"apply_date","l":"Apply ki tareekh"}],
   "8":  [{"k":"tech_name","l":"Technician ka naam","req":true},{"k":"tech_mobile","l":"Technician ka mobile"},{"k":"handover_date","l":"Hand over ki tareekh"}],
   "9":  [{"k":"start_date","l":"Installation shuru hui"},{"k":"team_size","l":"Team (log)"}],
   "10": [{"k":"inverter_sn","l":"Inverter serial no."},{"k":"panel_count","l":"Panels (sankhya)"},{"k":"jcr","l":"Joint Commissioning Report"},{"k":"comm_date","l":"Commissioning ki tareekh"}],
   "11": [{"k":"nm_app_no","l":"Net metering application no."},{"k":"meter_no","l":"Meter number"},{"k":"meter_date","l":"Meter lagne ki tareekh"},{"k":"discom_je","l":"DISCOM JE / contact"}],
   "13": [{"k":"sub_app_no","l":"Subsidy application no."},{"k":"sub_amount","l":"Subsidy amount (Rs)"},{"k":"sub_status","l":"Subsidy status"}],
   "14": [{"k":"sent_what","l":"Kya bheja (demo / datasheet / photo)"},{"k":"sent_mode","l":"Kaise bheja (WhatsApp / Email / Milkar)"}],
   "15": [{"k":"pay_mode","l":"Payment tarika (Cash / Loan / Mixed)","req":true},{"k":"bank","l":"Bank"},{"k":"loan_amount","l":"Loan amount (Rs)"},{"k":"loan_status","l":"Loan status"},{"k":"loan_ref","l":"Loan reference no."}],
   "16": [{"k":"ref_name","l":"Refer kiya (naam)"},{"k":"ref_mobile","l":"Refer kiya (mobile)"}],
   "17": [{"k":"amc_plan","l":"AMC / maintenance plan"},{"k":"amc_start","l":"Shuru ki tareekh"}],
   "18": [{"k":"c_status","l":"Complaint status (None / Open / In progress / Resolved)"},{"k":"c_issue","l":"Samasya"},{"k":"c_ticket","l":"Ticket / complaint no."},{"k":"c_handler","l":"Kisne sambhali (Installer / Dealer / Manufacturer)"},{"k":"c_brand","l":"Brand / product"},{"k":"c_serial","l":"Serial number"},{"k":"c_date","l":"Complaint ki tareekh"}],
   "20": [{"k":"stock_status","l":"Stock (Hai / Purchase karna hai)"},{"k":"reserved_on","l":"Maal alag rakhne ki tareekh"}],
   "21": [{"k":"disp_mode","l":"Kaise gaya (Khud / Courier / Store se uthaya)","req":true},{"k":"courier","l":"Courier / transport ka naam"},{"k":"tracking_no","l":"Tracking / LR number"},{"k":"disp_date","l":"Bheja gaya (tareekh)"},{"k":"deliv_date","l":"Pahuncha (tareekh)"},{"k":"deliv_proof","l":"Delivery ka saboot (photo Documents me / receiver ka naam)"}],
   "22": [{"k":"serials","l":"Serial number(s)"},{"k":"warranty_months","l":"Warranty (mahine)"},{"k":"install_by","l":"Installation (Khud video dekh kar / Hamari team)"},{"k":"video_sent","l":"Demo / install video bheji (Haan / Nahi)"}],
   "23": [{"k":"job_summary","l":"Kaam ka saar (kya kiya)","req":true},{"k":"parts_used","l":"Lage hue parts"},{"k":"photos_done","l":"Before / After photo Documents me (Haan / Nahi)"},{"k":"done_date","l":"Kaam ki tareekh"}]
  }'::jsonb $function$;
CREATE OR REPLACE FUNCTION public.crm_wf_set(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; n int := (p ->> 'step')::int; done boolean := coalesce((p ->> 'done')::boolean, true); note text := left(trim(coalesce(p ->> 'note', '')), 500);
        skip boolean := coalesce((p ->> 'skip')::boolean, false); w jsonb; flow int[]; ct text; inf jsonb := '{}'::jsonb; f jsonb; v text; miss text[] := '{}'; entry jsonb; has_info boolean := p ? 'info';
begin
  select * into q from public.crm_records where id = (p ->> 'id')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if n is null or n < 1 or n > 23 then raise exception 'Step galat hai'; end if;
  if public.crm_wf_is_auto(n) then raise exception 'Ye step apne aap hota hai (quotation / bill / lead se)'; end if;
  ct := coalesce(q.data ->> 'ctype', ''); flow := public.crm_wf_flow_of(q);
  if not (n = any (flow)) then
    if n = 13 then raise exception 'Subsidy sirf Residential solar ke liye hai'; end if;
    raise exception 'Ye step is customer ke liye nahi hai (% — %)', case ct when 'Items only' then 'Product customer' when 'Service' then 'Service customer' when 'AMC only' then 'AMC customer' when 'Site visit only' then 'Site visit customer' else 'Project customer' end, (public.crm_wf_names())[n];
  end if;
  if n = 13 and not (public.crm_is_admin(s) or (s).role = 'manager') then raise exception 'Subsidy sirf Admin ya Manager green kar sakte hain'; end if;
  if not public.crm_wf_can(s, n, 'edit') then raise exception 'Is step ko badalne ki permission nahi hai — Admin se allow karwayein'; end if;
  w := coalesce(q.data -> 'wf', '{}'::jsonb);
  if done then
    if n = 7 and not (w ? '6') then raise exception 'Pehle quotation Confirm hona chahiye'; end if;
    if (n in (9, 10, 11, 13) or (n = 8 and ct <> 'Service') or (n = 17 and ct not in ('Service', 'AMC only'))) and not (w ? '7') then raise exception 'Pehle Apply Process confirm karein — tabhi customer Projects me aata hai'; end if;
    if (n in (15, 16, 18, 20, 21, 22, 23) or (n = 8 and ct = 'Service') or (n = 17 and ct = 'Service')) and not (w ? '6') then raise exception 'Pehle quotation Confirm hona chahiye'; end if;
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
end $function$;
CREATE OR REPLACE FUNCTION public.crm_wf_perm(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); cur jsonb;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  if p ? 'perm' then
    update public.crm_settings set data = jsonb_set(coalesce(data, '{}'::jsonb), '{wf}', coalesce(data -> 'wf', '{}'::jsonb) || jsonb_build_object('perm', coalesce(p -> 'perm', '{}'::jsonb), 'allow_old', coalesce((p ->> 'allow_old')::boolean, false))), updated_at = now() where id = 1;
    perform public.crm_log(s, 'settings', 'settings', 1, 'Workflow permission badli');
  end if;
  select data -> 'wf' into cur from public.crm_settings where id = 1;
  return jsonb_build_object('perm', coalesce(cur -> 'perm', '{}'::jsonb), 'allow_old', coalesce((cur ->> 'allow_old')::boolean, false), 'names', to_jsonb(public.crm_wf_names()),
    'manual', (select coalesce(jsonb_agg(k order by k), '[]'::jsonb) from (select generate_series(1, 18) k union all select generate_series(20, 23)) g(k) where not public.crm_wf_is_auto(k)), 'flow', to_jsonb(public.crm_wf_flow('Residential')));
end $function$;

-- =====================================================================================================
-- ROUND 48 / C — Customer DECLARATION (OTP ki jagah): link se "kaam poora hua / main khud lagaunga" ki ghoshna.
--   kind 'job'  : Service kaam poora (step 23 ke baad). Customer 48 ghante me kuch na kare to apne aap manzoor (auto).
--   kind 'self' : Product ko khud lagane ki ghoshna (step 22 Warranty ke saath). Auto-accept nahi hota.
--   Customer "Dikkat hai" dabaye to Complaint ticket + reminder bante hain. Dobara chalana safe hai.
-- =====================================================================================================
create table if not exists public.crm_decl (
  id bigserial primary key,
  token text not null unique,
  quote_id bigint not null,
  party_id bigint,
  kind text not null check (kind in ('job', 'self')),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'auto', 'issue')),
  signer text not null default '',
  issue text not null default '',
  note text not null default '',
  created_by bigint,
  created_at timestamptz not null default now(),
  due_at timestamptz not null default now() + interval '48 hours',
  done_at timestamptz
);
create index if not exists crm_decl_quote_idx on public.crm_decl(quote_id);
alter table public.crm_decl enable row level security;

-- wf step ki entry me declaration ki sthiti likh do (step 23 / 22)
create or replace function public.crm__decl_note(p_qid bigint, p_kind text, p_status text, p_signer text) returns void language plpgsql security definer set search_path to 'public' as $$
declare n int := case p_kind when 'job' then 23 else 22 end; prev text := coalesce(current_setting('sp.wf', true), ''); w jsonb;
begin
  select data -> 'wf' into w from public.crm_records where id = p_qid and kind = 'quote' and deleted_at is null;
  if w is null or not (w ? n::text) then return; end if;
  perform set_config('sp.wf', '1', true);
  update public.crm_records set data = jsonb_set(data, array['wf', n::text, 'info'],
      coalesce(data -> 'wf' -> n::text -> 'info', '{}'::jsonb) || jsonb_build_object('decl', p_status, 'decl_by', p_signer, 'decl_at', public.crm_iso_now()), true), updated_at = now()
    where id = p_qid;
  perform set_config('sp.wf', prev, true);
end $$;

-- 48 ghante beet gaye aur customer chup: "job" declaration apne aap manzoor
create or replace function public.crm_decl_sweep(p_qid bigint default null) returns int language plpgsql security definer set search_path to 'public' as $$
declare r public.crm_decl; c int := 0;
begin
  for r in select * from public.crm_decl where status = 'pending' and kind = 'job' and due_at <= now() and (p_qid is null or quote_id = p_qid) for update skip locked loop
    update public.crm_decl set status = 'auto', signer = 'Auto (48 ghante)', done_at = now() where id = r.id;
    perform public.crm__decl_note(r.quote_id, 'job', 'auto', 'Auto (48 ghante)');
    c := c + 1;
  end loop;
  return c;
end $$;

-- staff: link banao (ya purana pending wala wapas do)
create or replace function public.crm_decl_new(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; k text := p ->> 'kind'; n int; r public.crm_decl; w jsonb;
begin
  if k not in ('job', 'self') then raise exception 'Galat prakar'; end if;
  n := case k when 'job' then 23 else 22 end;
  select * into q from public.crm_records where id = nullif(p ->> 'quote_id', '')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if not (n = any (public.crm_wf_flow_of(q))) then raise exception 'Ye step is customer ke liye nahi hai'; end if;
  if not public.crm_wf_can(s, n, 'edit') then raise exception 'Is step ko badalne ki permission nahi hai — Admin se allow karwayein'; end if;
  w := coalesce(q.data -> 'wf', '{}'::jsonb);
  if k = 'job' and not (w ? '23') then raise exception 'Pehle "Job Done Report" bharein, phir customer ko confirmation bhejein'; end if;
  if k = 'self' and not (w ? '6') then raise exception 'Pehle quotation Confirm hona chahiye'; end if;
  perform public.crm_decl_sweep(q.id);
  select * into r from public.crm_decl where quote_id = q.id and kind = k and status = 'pending' order by id desc limit 1;
  if r.id is null then
    insert into public.crm_decl(token, quote_id, party_id, kind, created_by, note)
      values (md5(random()::text || clock_timestamp()::text || q.id::text) || substr(md5(random()::text), 1, 8), q.id, q.party_id, k, (s).uid, left(trim(coalesce(p ->> 'note', '')), 300)) returning * into r;
  end if;
  return jsonb_build_object('id', r.id, 'token', r.token, 'status', r.status, 'kind', r.kind, 'due_at', r.due_at);
end $$;

create or replace function public.crm_decl_list(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; out jsonb;
begin
  select * into q from public.crm_records where id = nullif(p ->> 'quote_id', '')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  perform public.crm_decl_sweep(q.id);
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'token', d.token, 'kind', d.kind, 'status', d.status, 'signer', d.signer, 'issue', d.issue, 'note', d.note,
           'created_at', d.created_at, 'due_at', d.due_at, 'done_at', d.done_at) order by d.id desc), '[]'::jsonb) into out from public.crm_decl d where d.quote_id = q.id;
  return out;
end $$;

-- staff: customer ne phone par bataya — haath se manzoor kar do
create or replace function public.crm_decl_mark(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_decl; q public.crm_records; n int; who text := left(trim(coalesce(p ->> 'signer', '')), 80);
begin
  select * into r from public.crm_decl where id = nullif(p ->> 'id', '')::bigint;
  if r.id is null then raise exception 'Declaration nahi mili'; end if;
  select * into q from public.crm_records where id = r.quote_id and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  n := case r.kind when 'job' then 23 else 22 end;
  if not public.crm_wf_can(s, n, 'edit') then raise exception 'Is step ko badalne ki permission nahi hai — Admin se allow karwayein'; end if;
  if r.status <> 'pending' then raise exception 'Ye declaration pehle hi ho chuki hai'; end if;
  if who = '' then who := 'Phone par — ' || (s).name; end if;
  update public.crm_decl set status = 'accepted', signer = who, done_at = now() where id = r.id;
  perform public.crm__decl_note(r.quote_id, r.kind, 'accepted', who);
  return jsonb_build_object('ok', true);
end $$;

-- customer (bina login): link kholne par jaankari
create or replace function public.sp_decl_get(p_token text) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r public.crm_decl; q public.crm_records; pt public.crm_records; inf jsonb; w jsonb;
begin
  if coalesce(length(p_token), 0) < 20 then return jsonb_build_object('ok', false, 'error', 'Link galat hai'); end if;
  select * into r from public.crm_decl where token = p_token;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'Link galat hai'); end if;
  perform public.crm_decl_sweep(r.quote_id);
  select * into r from public.crm_decl where id = r.id;
  select * into q from public.crm_records where id = r.quote_id;
  select * into pt from public.crm_records where id = r.party_id;
  w := coalesce(q.data -> 'wf', '{}'::jsonb);
  inf := coalesce(w -> (case r.kind when 'job' then '23' else '22' end) -> 'info', '{}'::jsonb);
  return jsonb_build_object('ok', true, 'kind', r.kind, 'status', r.status, 'signer', r.signer, 'due_at', r.due_at, 'done_at', r.done_at,
    'customer', coalesce(pt.title, ''), 'ref', q.ref, 'title', coalesce(q.data ->> 'qtitle', q.title),
    'summary', coalesce(inf ->> 'job_summary', ''), 'done_date', coalesce(inf ->> 'done_date', ''), 'parts', coalesce(inf ->> 'parts_used', ''), 'note', r.note);
end $$;

-- customer: "Sab theek hai" ya "Dikkat hai"
create or replace function public.sp_decl_submit(p_token text, p_name text, p_ok boolean, p_issue text default '') returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r public.crm_decl; q public.crm_records; pt public.crm_records; nm text := left(trim(coalesce(p_name, '')), 80); iss text := left(trim(coalesce(p_issue, '')), 300); cnt int; fid bigint; asg bigint; no_ text;
begin
  if coalesce(length(p_token), 0) < 20 then return jsonb_build_object('ok', false, 'error', 'Link galat hai'); end if;
  select * into r from public.crm_decl where token = p_token for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'Link galat hai'); end if;
  if r.status <> 'pending' then return jsonb_build_object('ok', true, 'status', r.status, 'already', true); end if;
  if length(nm) < 2 then return jsonb_build_object('ok', false, 'error', 'Apna naam likhein'); end if;
  select * into q from public.crm_records where id = r.quote_id and kind = 'quote' and deleted_at is null;
  if q.id is null then return jsonb_build_object('ok', false, 'error', 'Link galat hai'); end if;
  if p_ok then
    update public.crm_decl set status = 'accepted', signer = nm, done_at = now() where id = r.id;
    perform public.crm__decl_note(r.quote_id, r.kind, 'accepted', nm);
    return jsonb_build_object('ok', true, 'status', 'accepted');
  end if;
  if length(iss) < 3 then return jsonb_build_object('ok', false, 'error', 'Dikkat likhein (kam se kam 3 akshar)'); end if;
  update public.crm_decl set status = 'issue', signer = nm, issue = iss, done_at = now() where id = r.id;
  perform public.crm__decl_note(r.quote_id, r.kind, 'issue', nm);
  select * into pt from public.crm_records where id = q.party_id and kind = 'party';
  perform pg_advisory_xact_lock(4747);
  select count(*) + 1 into cnt from public.crm_flow_rec where kind = 'complaint';
  no_ := 'TKT-' || to_char(now() at time zone 'Asia/Kolkata', 'YY') || '-' || lpad(cnt::text, 4, '0');
  insert into public.crm_flow_rec(kind, quote_id, party_id, no, status, data, hist)
    values ('complaint', q.id, q.party_id, no_, 'Open',
      jsonb_build_object('issue', iss, 'brand', '', 'serial', '', 'handler', 'Installer', 'priority', 'Urgent', 'c_date', public.crm_today()::text, 'assigned_to', null, 'ticket_ref', '', 'resolution', '', 'from_decl', r.id),
      jsonb_build_array(jsonb_build_object('at', public.crm_iso_now(), 'by', nm, 'status', 'Open', 'note', 'Customer ne declaration link se dikkat batayi'))) returning id into fid;
  asg := coalesce(nullif(q.assigned_to, 0), q.owner_id, q.created_by);
  if asg is not null then
    insert into public.crm_records(kind, title, status, owner_id, assigned_to, party_id, mobile, due_at, data, search, created_by)
    values ('reminder', 'Complaint ' || no_ || ' — ' || coalesce(pt.title, '') || ': ' || left(iss, 60), 'open', asg, asg, q.party_id, pt.mobile, public.crm_today(),
      jsonb_build_object('type', 'followup', 'complaint_id', fid, 'ticket', no_, 'party_name', coalesce(pt.title, ''), 'mobile', coalesce(pt.mobile, ''), 'note', left(iss, 200), 'priority', 'Urgent'),
      lower('complaint ' || no_ || ' ' || coalesce(pt.title, '')), asg);
    update public.crm_flow_rec set rem_id = (select max(id) from public.crm_records where kind = 'reminder' and (data ->> 'complaint_id') = fid::text) where id = fid;
  end if;
  return jsonb_build_object('ok', true, 'status', 'issue', 'ticket', no_);
end $$;

-- crm_wf_get ab purani pending declarations bhi sweep karta hai (job screen kholte hi 48h wali apne aap manzoor)
do $$ begin
  if position('crm_decl_sweep' in pg_get_functiondef('public.crm_wf_get(jsonb)'::regprocedure)) = 0 then
    execute replace(replace(pg_get_functiondef('public.crm_wf_get(jsonb)'::regprocedure),
      E'begin\n  if qid is null and pid is not null then', E'begin\n  if qid is not null then perform public.crm_decl_sweep(qid); end if;\n  if qid is null and pid is not null then'), 'x', 'x');
  end if;
end $$;

grant execute on function public.crm_decl_new(jsonb), public.crm_decl_list(jsonb), public.crm_decl_mark(jsonb), public.sp_decl_get(text), public.sp_decl_submit(text, text, boolean, text) to anon, authenticated;
revoke execute on function public.crm_decl_sweep(bigint), public.crm__decl_note(bigint, text, text, text) from public, anon, authenticated;


-- =====================================================================================================
-- ROUND 49 — Customer Profile card (Meri Profile), customer Documents, Routine Checkup, order page, dispatch.
--   Dobara chalana safe hai. Pehle R48 wala block chal chuka hona chahiye (MASTER-UPDATE.sql me sab saath hai).
-- =====================================================================================================
-- =====================================================================================================
-- ROUND 48 / C — Customer DECLARATION (OTP ki jagah): link se "kaam poora hua / main khud lagaunga" ki ghoshna.
--   kind 'job'  : Service kaam poora (step 23 ke baad). Customer 48 ghante me kuch na kare to apne aap manzoor (auto).
--   kind 'self' : Product ko khud lagane ki ghoshna (step 22 Warranty ke saath). Auto-accept nahi hota.
--   Customer "Dikkat hai" dabaye to Complaint ticket + reminder bante hain. Dobara chalana safe hai.
-- =====================================================================================================
create table if not exists public.crm_decl (
  id bigserial primary key,
  token text not null unique,
  quote_id bigint not null,
  party_id bigint,
  kind text not null check (kind in ('job', 'self')),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'auto', 'issue')),
  signer text not null default '',
  issue text not null default '',
  note text not null default '',
  created_by bigint,
  created_at timestamptz not null default now(),
  due_at timestamptz not null default now() + interval '48 hours',
  done_at timestamptz
);
create index if not exists crm_decl_quote_idx on public.crm_decl(quote_id);
alter table public.crm_decl enable row level security;

-- wf step ki entry me declaration ki sthiti likh do (step 23 / 22)
create or replace function public.crm__decl_note(p_qid bigint, p_kind text, p_status text, p_signer text) returns void language plpgsql security definer set search_path to 'public' as $$
declare n int := case p_kind when 'job' then 23 else 22 end; prev text := coalesce(current_setting('sp.wf', true), ''); w jsonb;
begin
  select data -> 'wf' into w from public.crm_records where id = p_qid and kind = 'quote' and deleted_at is null;
  if w is null or not (w ? n::text) then return; end if;
  perform set_config('sp.wf', '1', true);
  update public.crm_records set data = jsonb_set(data, array['wf', n::text, 'info'],
      coalesce(data -> 'wf' -> n::text -> 'info', '{}'::jsonb) || jsonb_build_object('decl', p_status, 'decl_by', p_signer, 'decl_at', public.crm_iso_now()), true), updated_at = now()
    where id = p_qid;
  perform set_config('sp.wf', prev, true);
end $$;

-- 48 ghante beet gaye aur customer chup: "job" declaration apne aap manzoor
create or replace function public.crm_decl_sweep(p_qid bigint default null) returns int language plpgsql security definer set search_path to 'public' as $$
declare r public.crm_decl; c int := 0;
begin
  for r in select * from public.crm_decl where status = 'pending' and kind = 'job' and due_at <= now() and (p_qid is null or quote_id = p_qid) for update skip locked loop
    update public.crm_decl set status = 'auto', signer = 'Auto (48 ghante)', done_at = now() where id = r.id;
    perform public.crm__decl_note(r.quote_id, 'job', 'auto', 'Auto (48 ghante)');
    c := c + 1;
  end loop;
  return c;
end $$;

-- staff: link banao (ya purana pending wala wapas do)
create or replace function public.crm_decl_new(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; k text := p ->> 'kind'; n int; r public.crm_decl; w jsonb;
begin
  if k not in ('job', 'self') then raise exception 'Galat prakar'; end if;
  n := case k when 'job' then 23 else 22 end;
  select * into q from public.crm_records where id = nullif(p ->> 'quote_id', '')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if not (n = any (public.crm_wf_flow_of(q))) then raise exception 'Ye step is customer ke liye nahi hai'; end if;
  if not public.crm_wf_can(s, n, 'edit') then raise exception 'Is step ko badalne ki permission nahi hai — Admin se allow karwayein'; end if;
  w := coalesce(q.data -> 'wf', '{}'::jsonb);
  if k = 'job' and not (w ? '23') then raise exception 'Pehle "Job Done Report" bharein, phir customer ko confirmation bhejein'; end if;
  if k = 'self' and not (w ? '6') then raise exception 'Pehle quotation Confirm hona chahiye'; end if;
  perform public.crm_decl_sweep(q.id);
  select * into r from public.crm_decl where quote_id = q.id and kind = k and status = 'pending' order by id desc limit 1;
  if r.id is null then
    insert into public.crm_decl(token, quote_id, party_id, kind, created_by, note)
      values (md5(random()::text || clock_timestamp()::text || q.id::text) || substr(md5(random()::text), 1, 8), q.id, q.party_id, k, (s).uid, left(trim(coalesce(p ->> 'note', '')), 300)) returning * into r;
  end if;
  return jsonb_build_object('id', r.id, 'token', r.token, 'status', r.status, 'kind', r.kind, 'due_at', r.due_at);
end $$;

create or replace function public.crm_decl_list(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; out jsonb;
begin
  select * into q from public.crm_records where id = nullif(p ->> 'quote_id', '')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  perform public.crm_decl_sweep(q.id);
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'token', d.token, 'kind', d.kind, 'status', d.status, 'signer', d.signer, 'issue', d.issue, 'note', d.note,
           'created_at', d.created_at, 'due_at', d.due_at, 'done_at', d.done_at) order by d.id desc), '[]'::jsonb) into out from public.crm_decl d where d.quote_id = q.id;
  return out;
end $$;

-- staff: customer ne phone par bataya — haath se manzoor kar do
create or replace function public.crm_decl_mark(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_decl; q public.crm_records; n int; who text := left(trim(coalesce(p ->> 'signer', '')), 80);
begin
  select * into r from public.crm_decl where id = nullif(p ->> 'id', '')::bigint;
  if r.id is null then raise exception 'Declaration nahi mili'; end if;
  select * into q from public.crm_records where id = r.quote_id and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  n := case r.kind when 'job' then 23 else 22 end;
  if not public.crm_wf_can(s, n, 'edit') then raise exception 'Is step ko badalne ki permission nahi hai — Admin se allow karwayein'; end if;
  if r.status <> 'pending' then raise exception 'Ye declaration pehle hi ho chuki hai'; end if;
  if who = '' then who := 'Phone par — ' || (s).name; end if;
  update public.crm_decl set status = 'accepted', signer = who, done_at = now() where id = r.id;
  perform public.crm__decl_note(r.quote_id, r.kind, 'accepted', who);
  return jsonb_build_object('ok', true);
end $$;

-- Round 49: ek hi jagah complaint ticket banti hai (declaration link, customer hub, checkup — teeno yahin se). Ticket no + "Aaj ke kaam" reminder.
create or replace function public.crm__complaint_new(p_qid bigint, p_who text, p_issue text, p_prio text, p_extra jsonb, p_note text) returns text language plpgsql security definer set search_path to 'public' as $$
declare q public.crm_records; pt public.crm_records; cnt int; fid bigint; asg bigint; no_ text; iss text := left(trim(coalesce(p_issue, '')), 300);
begin
  select * into q from public.crm_records where id = p_qid and kind = 'quote' and deleted_at is null;
  if q.id is null then raise exception 'Kaam nahi mila'; end if;
  select * into pt from public.crm_records where id = q.party_id and kind = 'party';
  perform pg_advisory_xact_lock(4747);
  select count(*) + 1 into cnt from public.crm_flow_rec where kind = 'complaint';
  no_ := 'TKT-' || to_char(now() at time zone 'Asia/Kolkata', 'YY') || '-' || lpad(cnt::text, 4, '0');
  insert into public.crm_flow_rec(kind, quote_id, party_id, no, status, data, hist)
    values ('complaint', q.id, q.party_id, no_, 'Open',
      jsonb_build_object('issue', iss, 'brand', '', 'serial', '', 'handler', 'Installer', 'priority', case when p_prio = 'Urgent' then 'Urgent' else 'Normal' end, 'c_date', public.crm_today()::text, 'assigned_to', null, 'ticket_ref', '', 'resolution', '') || coalesce(p_extra, '{}'::jsonb),
      jsonb_build_array(jsonb_build_object('at', public.crm_iso_now(), 'by', coalesce(p_who, ''), 'status', 'Open', 'note', coalesce(p_note, 'Ticket bana')))) returning id into fid;
  asg := coalesce(nullif(q.assigned_to, 0), q.owner_id, q.created_by);
  if asg is not null then
    insert into public.crm_records(kind, title, status, owner_id, assigned_to, party_id, mobile, due_at, data, search, created_by)
    values ('reminder', 'Complaint ' || no_ || ' — ' || coalesce(pt.title, '') || ': ' || left(iss, 60), 'open', asg, asg, q.party_id, pt.mobile, public.crm_today(),
      jsonb_build_object('type', 'followup', 'complaint_id', fid, 'ticket', no_, 'party_name', coalesce(pt.title, ''), 'mobile', coalesce(pt.mobile, ''), 'note', left(iss, 200), 'priority', case when p_prio = 'Urgent' then 'Urgent' else 'Normal' end),
      lower('complaint ' || no_ || ' ' || coalesce(pt.title, '')), asg);
    update public.crm_flow_rec set rem_id = (select max(id) from public.crm_records where kind = 'reminder' and (data ->> 'complaint_id') = fid::text) where id = fid;
  end if;
  return no_;
end $$;
revoke execute on function public.crm__complaint_new(bigint, text, text, text, jsonb, text) from public, anon, authenticated;

-- customer (bina login): link kholne par jaankari
create or replace function public.sp_decl_get(p_token text) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r public.crm_decl; q public.crm_records; pt public.crm_records; inf jsonb; w jsonb;
begin
  if coalesce(length(p_token), 0) < 20 then return jsonb_build_object('ok', false, 'error', 'Link galat hai'); end if;
  select * into r from public.crm_decl where token = p_token;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'Link galat hai'); end if;
  perform public.crm_decl_sweep(r.quote_id);
  select * into r from public.crm_decl where id = r.id;
  select * into q from public.crm_records where id = r.quote_id;
  select * into pt from public.crm_records where id = r.party_id;
  w := coalesce(q.data -> 'wf', '{}'::jsonb);
  inf := coalesce(w -> (case r.kind when 'job' then '23' else '22' end) -> 'info', '{}'::jsonb);
  return jsonb_build_object('ok', true, 'kind', r.kind, 'status', r.status, 'signer', r.signer, 'due_at', r.due_at, 'done_at', r.done_at,
    'customer', coalesce(pt.title, ''), 'ref', q.ref, 'title', coalesce(q.data ->> 'qtitle', q.title),
    'summary', coalesce(inf ->> 'job_summary', ''), 'done_date', coalesce(inf ->> 'done_date', ''), 'parts', coalesce(inf ->> 'parts_used', ''), 'note', r.note);
end $$;

-- customer: "Sab theek hai" ya "Dikkat hai"
create or replace function public.sp_decl_submit(p_token text, p_name text, p_ok boolean, p_issue text default '') returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r public.crm_decl; q public.crm_records; nm text := left(trim(coalesce(p_name, '')), 80); iss text := left(trim(coalesce(p_issue, '')), 300); no_ text;
begin
  if coalesce(length(p_token), 0) < 20 then return jsonb_build_object('ok', false, 'error', 'Link galat hai'); end if;
  select * into r from public.crm_decl where token = p_token for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'Link galat hai'); end if;
  if r.status <> 'pending' then return jsonb_build_object('ok', true, 'status', r.status, 'already', true); end if;
  if length(nm) < 2 then return jsonb_build_object('ok', false, 'error', 'Apna naam likhein'); end if;
  select * into q from public.crm_records where id = r.quote_id and kind = 'quote' and deleted_at is null;
  if q.id is null then return jsonb_build_object('ok', false, 'error', 'Link galat hai'); end if;
  if p_ok then
    update public.crm_decl set status = 'accepted', signer = nm, done_at = now() where id = r.id;
    perform public.crm__decl_note(r.quote_id, r.kind, 'accepted', nm);
    return jsonb_build_object('ok', true, 'status', 'accepted');
  end if;
  if length(iss) < 3 then return jsonb_build_object('ok', false, 'error', 'Dikkat likhein (kam se kam 3 akshar)'); end if;
  update public.crm_decl set status = 'issue', signer = nm, issue = iss, done_at = now() where id = r.id;
  perform public.crm__decl_note(r.quote_id, r.kind, 'issue', nm);
  no_ := public.crm__complaint_new(q.id, nm, iss, 'Urgent', jsonb_build_object('from_decl', r.id), 'Customer ne declaration link se dikkat batayi');
  return jsonb_build_object('ok', true, 'status', 'issue', 'ticket', no_);
end $$;

-- crm_wf_get ab purani pending declarations bhi sweep karta hai (job screen kholte hi 48h wali apne aap manzoor)
do $$ begin
  if position('crm_decl_sweep' in pg_get_functiondef('public.crm_wf_get(jsonb)'::regprocedure)) = 0 then
    execute replace(replace(pg_get_functiondef('public.crm_wf_get(jsonb)'::regprocedure),
      E'begin\n  if qid is null and pid is not null then', E'begin\n  if qid is not null then perform public.crm_decl_sweep(qid); end if;\n  if qid is null and pid is not null then'), 'x', 'x');
  end if;
end $$;

grant execute on function public.crm_decl_new(jsonb), public.crm_decl_list(jsonb), public.crm_decl_mark(jsonb), public.sp_decl_get(text), public.sp_decl_submit(text, text, boolean, text) to anon, authenticated;
revoke execute on function public.crm_decl_sweep(bigint), public.crm__decl_note(bigint, text, text, text) from public, anon, authenticated;
-- =====================================================================================================
-- ROUND 49 / D — Customer Hub (store + shop "Meri Profile" card): checkup, complaints, orders page, referral, dispatch.
--   Sab customer ke apne mobile se (crm_csession). Dobara chalana safe hai.
-- =====================================================================================================

-- ---- monthly Routine Checkup (sirf Project) — jawab yahin; report PDF/HTML jawab se banti hai (file storage nahi)
create table if not exists public.crm_checkup (
  id bigserial primary key,
  quote_id bigint not null,
  party_id bigint,
  user_id bigint,
  ym text not null,
  items jsonb not null default '{}'::jsonb,
  gen_kwh numeric,
  note text not null default '',
  ticket text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (quote_id, ym)
);
alter table public.crm_checkup enable row level security;

create or replace function public.crm__checkup_keys() returns jsonb language sql immutable as $$
  select '{"panel_clean":"Solar panel saaf hain","inverter_ok":"Inverter theek chal raha hai (koi error / deactivation nahi)","wiring_ok":"Wiring sahi dikhti hai","acdb_dcdb_ok":"ACDB / DCDB sahi dikhte hain","wires_joined":"Wire sab jude hue hain","connectors_ok":"Connector tight / theek hain","structure_ok":"Structure ke bolt sahi hain","shadow_new":"Nayi chhaya / rukawat nahi hai","noise_heat":"Koi awaaz, garmi ya smell nahi","earthing_ok":"Earthing / lightning arrestor sahi dikhta hai"}'::jsonb $$;

-- customer ka apna party + (optional) apna job
create or replace function public.crm__cust_party(u public.crm_users) returns public.crm_records language sql stable security definer set search_path to 'public' as $$
  select * from public.crm_records where kind = 'party' and deleted_at is null and mobile = u.mobile and u.mobile ~ '^[6-9][0-9]{9}$' and coalesce(data ->> 'type', 'customer') <> 'supplier' order by id limit 1 $$;

create or replace function public.crm_checkup_save(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); pt public.crm_records := public.crm__cust_party(u); q public.crm_records; w jsonb; keys jsonb := public.crm__checkup_keys(); k text; v text; it jsonb := '{}'::jsonb;
        v_ym text := to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM'); bad text[] := '{}'; tk text; gen numeric;
begin
  select * into q from public.crm_records where id = nullif(p ->> 'quote_id', '')::bigint and kind = 'quote' and deleted_at is null and party_id = pt.id;
  if q.id is null or pt.id is null then raise exception 'Plant nahi mila'; end if;
  if coalesce(q.data ->> 'ctype', '') not in ('Residential', 'Commercial', 'Industrial', 'VFD') then raise exception 'Routine checkup sirf Project (plant) ke liye hai'; end if;
  w := coalesce(q.data -> 'wf', '{}'::jsonb);
  if not (w ? '9' or w ? '10') then raise exception 'Checkup install hone ke baad shuru hota hai'; end if;
  for k in select jsonb_object_keys(keys) loop
    v := p -> 'items' ->> k;
    if v is null or v not in ('ok', 'bad', 'na') then raise exception 'Har sawal ka jawab chunein (Theek / Dikkat / Lagu nahi)'; end if;
    it := it || jsonb_build_object(k, v);
    if v = 'bad' then bad := bad || (keys ->> k); end if;
  end loop;
  gen := nullif(regexp_replace(coalesce(p ->> 'gen_kwh', ''), '[^0-9.]', '', 'g'), '')::numeric;
  if gen is not null and (gen < 0 or gen > 1000000) then gen := null; end if;
  insert into public.crm_checkup(quote_id, party_id, user_id, ym, items, gen_kwh, note) values (q.id, pt.id, u.id, v_ym, it, gen, left(trim(coalesce(p ->> 'note', '')), 300))
    on conflict (quote_id, ym) do update set items = excluded.items, gen_kwh = excluded.gen_kwh, note = excluded.note, updated_at = now()
    returning ticket into tk;
  if array_length(bad, 1) > 0 and tk is null then
    tk := public.crm__complaint_new(q.id, u.name, 'Routine checkup me dikkat: ' || array_to_string(bad, '; '), 'Normal', jsonb_build_object('from_checkup', v_ym), 'Customer ke monthly checkup se');
    update public.crm_checkup set ticket = tk where quote_id = q.id and crm_checkup.ym = v_ym;
  end if;
  return jsonb_build_object('ok', true, 'ym', v_ym, 'bad', coalesce(array_length(bad, 1), 0), 'ticket', tk);
end $$;

-- ---- customer: nayi complaint (Support)
create or replace function public.crm_consumer_complaint_new(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); pt public.crm_records := public.crm__cust_party(u); q public.crm_records; iss text := left(trim(coalesce(p ->> 'issue', '')), 300); no_ text; open_n int;
begin
  if pt.id is null then raise exception 'Abhi aapka koi kaam / bill juda nahi hai — call ya WhatsApp karein'; end if;
  if length(iss) < 5 then raise exception 'Samasya thodi detail me likhein (kam se kam 5 akshar)'; end if;
  select count(*) into open_n from public.crm_flow_rec where party_id = pt.id and kind = 'complaint' and deleted_at is null and status <> 'Resolved';
  if open_n >= 5 then raise exception 'Aapki 5 complaint pehle se khuli hain — hum jaldi sampark karenge'; end if;
  select * into q from public.crm_records where id = nullif(p ->> 'quote_id', '')::bigint and kind = 'quote' and deleted_at is null and party_id = pt.id;
  if q.id is null then
    select * into q from public.crm_records where kind = 'quote' and deleted_at is null and party_id = pt.id and status in ('accepted', 'converted') order by id desc limit 1;
  end if;
  if q.id is null then raise exception 'Abhi aapka koi confirmed kaam nahi hai — call ya WhatsApp karein'; end if;
  no_ := public.crm__complaint_new(q.id, u.name, iss, case when p ->> 'priority' = 'Urgent' then 'Urgent' else 'Normal' end, jsonb_build_object('from_hub', true, 'brand', left(coalesce(p ->> 'brand', ''), 80)), 'Customer ne app se complaint ki');
  return jsonb_build_object('ok', true, 'ticket', no_);
end $$;

-- ---- customer: koi bhi apna bill (product bill ho ya plant ka) — printable data
create or replace function public.crm_consumer_bill_doc(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); pt public.crm_records := public.crm__cust_party(u); src public.crm_records; co jsonb; pays jsonb;
begin
  select * into src from public.crm_records where id = nullif(p ->> 'id', '')::bigint and kind = 'invoice' and deleted_at is null and party_id = pt.id;
  if src.id is null or pt.id is null then raise exception 'Bill nahi mila'; end if;
  select data -> 'company' into co from public.crm_settings where id = 1;
  select coalesce(jsonb_agg(jsonb_build_object('date', py.due_at, 'amount', py.amount, 'mode', py.data ->> 'mode') order by py.due_at), '[]'::jsonb) into pays from public.crm_records py where py.kind = 'payment' and py.deleted_at is null and py.data ->> 'invoice_id' = src.id::text;
  return jsonb_build_object('kind', 'bill', 'ref', src.ref, 'date', src.data ->> 'date', 'title', src.data ->> 'qtitle',
    'customer', jsonb_build_object('name', pt.title, 'mobile', pt.mobile, 'address', pt.data ->> 'address', 'city', pt.data ->> 'city', 'gstin', pt.data ->> 'gstin'),
    'company', jsonb_build_object('name', co ->> 'name', 'legal', co ->> 'legal', 'gstin', co ->> 'gstin', 'phone', co ->> 'phone', 'address', co ->> 'address'),
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('name', l ->> 'name', 'qty', l -> 'qty', 'price', l -> 'price', 'gst', l -> 'gst', 'hsn', l ->> 'hsn')), '[]'::jsonb) from jsonb_array_elements(coalesce(src.data -> 'lines', '[]'::jsonb)) l),
    'subtotal', src.data -> 'subtotal', 'gst_total', src.data -> 'gst_total', 'discount', src.data -> 'discount', 'grand', src.amount, 'paid', src.data -> 'paid', 'balance', src.data -> 'balance', 'payments', pays, 'notes', src.data ->> 'notes');
end $$;

-- ---- customer: seva ki maang (AMC / installation / call-back) — enquiry + lead banti hai
create or replace function public.crm_consumer_request(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); pt public.crm_records := public.crm__cust_party(u); k text := p ->> 'kind'; sub text; note text := left(trim(coalesce(p ->> 'note', '')), 200);
begin
  if k not in ('amc', 'install', 'callback') then raise exception 'Galat maang'; end if;
  sub := case k when 'amc' then 'AMC / Maintenance plan' when 'install' then 'Installation add-on' else 'Call back' end;
  perform public.sp_submit_enquiry(jsonb_build_object('name', coalesce(pt.title, u.name), 'phone', u.mobile, 'type', sub, 'subject', sub, 'source', 'customer-hub',
    'message', sub || ' chahiye — ' || coalesce(pt.data ->> 'cust_id', '') || case when note <> '' then ' — ' || note else '' end, 'customer_id', u.id::text));
  return jsonb_build_object('ok', true);
end $$;

-- ---- customer: kisi ko refer karein (lead banti hai, enquiry->lead trigger se)
create or replace function public.crm_consumer_refer(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); pt public.crm_records := public.crm__cust_party(u); nm text := left(trim(coalesce(p ->> 'name', '')), 80); mob text := public.crm_mobile(coalesce(p ->> 'mobile', ''));
begin
  if length(nm) < 2 then raise exception 'Dost ka naam likhein'; end if;
  if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Dost ka sahi 10 ank ka mobile likhein'; end if;
  if mob = u.mobile then raise exception 'Apna hi number refer nahi ho sakta'; end if;
  perform public.sp_submit_enquiry(jsonb_build_object('name', nm, 'phone', mob, 'type', 'Referral', 'subject', 'Referral', 'source', 'referral',
    'message', 'Refer kiya: ' || coalesce(pt.title, u.name) || ' (' || coalesce(pt.data ->> 'cust_id', '') || ', ' || u.mobile || ')' || case when coalesce(p ->> 'note', '') <> '' then ' — ' || left(p ->> 'note', 150) else '' end, 'customer_id', u.id::text));
  return jsonb_build_object('ok', true);
end $$;

-- ---- customer: ek order ka poora page (e-commerce jaisa)
create or replace function public.crm_consumer_order(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); o public.sp_orders; ok boolean := coalesce((u.meta ->> 'mob_ok')::boolean, true);
begin
  select * into o from public.sp_orders where id = nullif(p ->> 'id', '')::bigint and ((ok and (data ->> 'phone') = u.mobile) or (data ->> 'customer_id') = u.id::text);
  if o.id is null then raise exception 'Order nahi mila'; end if;
  return jsonb_build_object('id', o.id, 'order_no', o.data ->> 'order_no', 'created_at', o.created_at, 'status', o.status, 'name', o.data ->> 'name', 'phone', o.data ->> 'phone',
    'address', o.data ->> 'address', 'city', o.data ->> 'city', 'pincode', o.data ->> 'pincode', 'pickup', coalesce((o.data ->> 'pickup')::boolean, false),
    'items', (select coalesce(jsonb_agg(jsonb_build_object('title', i ->> 'title', 'qty', i -> 'qty', 'price', i -> 'price', 'amount', i -> 'amount')), '[]'::jsonb) from jsonb_array_elements(coalesce(o.data -> 'items', '[]'::jsonb)) i),
    'subtotal', o.data -> 'subtotal', 'shipping', o.data -> 'shipping', 'total', o.data -> 'total', 'advance', o.data -> 'advance', 'due', o.data -> 'due', 'payment', o.data ->> 'payment', 'payment_status', o.data ->> 'payment_status',
    'invoice_no', o.data ->> 'invoice_no', 'delivery', o.data -> 'delivery', 'dispatch', coalesce(o.data -> 'dispatch', '{}'::jsonb), 'install', coalesce(o.data -> 'install', '[]'::jsonb));
end $$;

-- ---- Admin (store): order ka dispatch (courier / tracking) — customer ke order page par dikhta hai
create or replace function public.sp_admin_order_dispatch(p_pass text, p_id bigint, p jsonb) returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $$
declare d jsonb; st text := nullif(p ->> 'status', ''); cur text;
begin
  perform public.sp_check(p_pass);
  d := jsonb_build_object('mode', case when p ->> 'mode' in ('courier', 'self', 'pickup') then p ->> 'mode' else 'courier' end, 'courier', left(coalesce(p ->> 'courier', ''), 80), 'tracking', left(coalesce(p ->> 'tracking', ''), 80),
    'track_url', case when coalesce(p ->> 'track_url', '') ~* '^https?://' then left(p ->> 'track_url', 300) else '' end, 'disp_date', left(coalesce(p ->> 'disp_date', ''), 10), 'eta_date', left(coalesce(p ->> 'eta_date', ''), 10),
    'deliv_date', left(coalesce(p ->> 'deliv_date', ''), 10), 'note', left(coalesce(p ->> 'note', ''), 200), 'at', public.crm_iso_now());
  select status into cur from public.sp_orders where id = p_id;
  if cur is null then raise exception 'Order nahi mila'; end if;
  if st is not null and st not in ('new', 'confirmed', 'paid', 'shipped', 'delivered', 'cancelled') then st := null; end if;
  update public.sp_orders set data = data || jsonb_build_object('dispatch', d), status = coalesce(st, status) where id = p_id;
  return jsonb_build_object('ok', true, 'dispatch', d, 'status', coalesce(st, cur));
end $$;

-- ---- HUB: ek hi call me customer ka poora card (profile + orders + complaints + checkups + savings settings)
create or replace function public.crm_consumer_hub(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); pt public.crm_records := public.crm__cust_party(u); prof jsonb; ok boolean := coalesce((u.meta ->> 'mob_ok')::boolean, true);
        orders jsonb; comps jsonb := '[]'::jsonb; chk jsonb := '[]'::jsonb; cats jsonb := '{}'::jsonb; st jsonb; co jsonb;
begin
  prof := public.crm_consumer_profile(p);
  select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'order_no', o.data ->> 'order_no', 'created_at', o.created_at, 'status', o.status, 'total', o.data -> 'total', 'payment_status', o.data ->> 'payment_status',
      'n', jsonb_array_length(coalesce(o.data -> 'items', '[]'::jsonb)), 'first', (o.data -> 'items' -> 0 ->> 'title'), 'courier', o.data -> 'dispatch' ->> 'courier', 'tracking', o.data -> 'dispatch' ->> 'tracking', 'pickup', coalesce((o.data ->> 'pickup')::boolean, false)) order by o.id desc), '[]'::jsonb) into orders
    from (select * from public.sp_orders where (ok and (data ->> 'phone') = u.mobile) or (data ->> 'customer_id') = u.id::text order by id desc limit 50) o;
  if pt.id is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'no', f.no, 'status', f.status, 'issue', f.data ->> 'issue', 'date', f.data ->> 'c_date', 'resolution', f.data ->> 'resolution', 'priority', f.data ->> 'priority', 'quote_id', f.quote_id) order by f.id desc), '[]'::jsonb) into comps
      from public.crm_flow_rec f where f.party_id = pt.id and f.kind = 'complaint' and f.deleted_at is null;
    select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'quote_id', c.quote_id, 'ym', c.ym, 'items', c.items, 'gen_kwh', c.gen_kwh, 'note', c.note, 'ticket', c.ticket, 'at', c.updated_at) order by c.ym desc), '[]'::jsonb) into chk
      from public.crm_checkup c where c.party_id = pt.id;
    select coalesce(jsonb_object_agg(d.id::text, d.data ->> 'cat'), '{}'::jsonb) into cats from public.crm_records d
      where d.kind = 'doc' and d.deleted_at is null and coalesce(d.data ->> 'cat', '') <> '' and (d.data ->> 'shared_quote') in (select id::text from public.crm_records where kind = 'quote' and party_id = pt.id);
  end if;
  select data into st from public.crm_settings where id = 1;
  co := coalesce(st -> 'company', '{}'::jsonb);
  return prof || jsonb_build_object('orders', orders, 'complaints', comps, 'checkups', chk, 'doc_cats', cats, 'checkup_keys', public.crm__checkup_keys(),
    'cfg', jsonb_build_object('tariff', coalesce(nullif(st -> 'hub' ->> 'tariff', '')::numeric, 7), 'gen', coalesce(nullif(st -> 'hub' ->> 'gen', '')::numeric, 4)),
    'company', jsonb_build_object('name', co ->> 'name', 'phone', co ->> 'phone', 'whatsapp', coalesce(nullif(co ->> 'whatsapp', ''), co ->> 'phone')));
end $$;

grant execute on function public.crm_checkup_save(jsonb), public.crm_consumer_complaint_new(jsonb), public.crm_consumer_refer(jsonb), public.crm_consumer_order(jsonb), public.crm_consumer_bill_doc(jsonb), public.crm_consumer_request(jsonb), public.sp_admin_order_dispatch(text, bigint, jsonb), public.crm_consumer_hub(jsonb) to anon, authenticated;
revoke execute on function public.crm__checkup_keys(), public.crm__cust_party(public.crm_users) from public, anon, authenticated;
-- ======================= Round 49: customer-wise Documents (CRM upload / replace / delete) =======================
-- Customer in files ko sirf dekh / download kar sakta hai. Company ka "Documents & Gallery" alag hai.
create or replace function public.crm_cdoc_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; b bytea; r public.crm_records; nm text := left(trim(coalesce(p ->> 'name', '')), 160);
        note text := left(trim(coalesce(p ->> 'note', '')), 300); cat text := coalesce(nullif(trim(p ->> 'cat'), ''), 'Other'); mm text := left(coalesce(nullif(p ->> 'mime', ''), 'application/octet-stream'), 80); rid bigint := nullif(p ->> 'replace_id', '')::bigint;
begin
  if not public.crm_can(s, 'docs.upload') then raise exception 'Aapko documents upload karne ki permission nahi hai'; end if;
  if cat not in ('Blueprint', 'Plant photo', 'Quotation', 'Bill', 'Certificate', 'Warranty', 'Agreement', 'Other') then cat := 'Other'; end if;
  select * into q from public.crm_records where id = nullif(p ->> 'quote_id', '')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Kaam (quotation) nahi mila'; end if;
  if coalesce(p ->> 'b64', '') <> '' then
    begin b := decode(p ->> 'b64', 'base64'); exception when others then raise exception 'File padh nahi paye'; end;
    if octet_length(b) = 0 then raise exception 'File khaali hai'; end if;
    if octet_length(b) > 3 * 1024 * 1024 then raise exception 'File 3 MB se badi hai — chhoti karke dalein'; end if;
  end if;
  if rid is not null then
    select * into r from public.crm_records where id = rid and kind = 'doc' and deleted_at is null and (data ->> 'shared_quote') = q.id::text;
    if r.id is null then raise exception 'Purani file nahi mili'; end if;
    update public.crm_records set title = coalesce(nullif(nm, ''), title), search = lower(coalesce(nullif(nm, ''), title) || ' ' || coalesce(q.ref, '')),
      data = data || jsonb_build_object('cat', cat, 'note', note) || case when b is not null then jsonb_build_object('mime', mm, 'size', octet_length(b), 'replaced_at', public.crm_iso_now(), 'replaced_by', (s).name) else '{}'::jsonb end
      where id = r.id returning * into r;
    if b is not null then update public.crm_files set data = b, mime = mm, size = octet_length(b) where rec_id = r.id; if not found then insert into public.crm_files(rec_id, mime, size, data) values (r.id, mm, octet_length(b), b); end if; end if;
    perform public.crm_log(s, 'edit', 'doc', r.id, 'Customer document ' || case when b is not null then 'badla: ' else 'update: ' end || r.title || ' (' || cat || ')');
    return jsonb_build_object('ok', true, 'id', r.id, 'replaced', b is not null);
  end if;
  if b is null then raise exception 'File chunein'; end if;
  if nm = '' then nm := 'file'; end if;
  insert into public.crm_records(kind, title, status, owner_id, party_id, data, search, created_by)
  values ('doc', nm, 'ok', (s).uid, q.party_id,
    jsonb_build_object('mime', mm, 'size', octet_length(b), 'note', note, 'cat', cat, 'attach_kind', 'party', 'attach_id', q.party_id::text, 'shared_quote', q.id, 'shared_ref', q.ref, 'shared_at', public.crm_iso_now(), 'shared_by', (s).name, 'cdoc', true),
    lower(nm || ' ' || coalesce(q.ref, '')), (s).uid) returning * into r;
  insert into public.crm_files(rec_id, mime, size, data) values (r.id, mm, octet_length(b), b);
  perform public.crm_log(s, 'share', 'doc', r.id, 'Customer document: ' || nm || ' (' || cat || ') → ' || coalesce(q.ref, ''));
  return jsonb_build_object('ok', true, 'id', r.id);
end $$;

create or replace function public.crm_cdoc_delete(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records; q public.crm_records;
begin
  if not public.crm_can(s, 'docs.delete') then raise exception 'Aapko document delete karne ki permission nahi hai'; end if;
  select * into r from public.crm_records where id = nullif(p ->> 'id', '')::bigint and kind = 'doc' and deleted_at is null and data ? 'shared_quote';
  if r.id is null then raise exception 'File nahi mili'; end if;
  select * into q from public.crm_records where id = (r.data ->> 'shared_quote')::bigint;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'File nahi mili'; end if;
  update public.crm_records set deleted_at = now() where id = r.id;
  delete from public.crm_files where rec_id = r.id;
  perform public.crm_log(s, 'delete', 'doc', r.id, 'Customer document hataya: ' || r.title);
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.crm_cdoc_save(jsonb), public.crm_cdoc_delete(jsonb) to anon, authenticated;
