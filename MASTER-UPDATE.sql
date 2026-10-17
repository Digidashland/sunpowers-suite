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
  if coalesce(r.data ->> 'type', 'product') not in ('product', 'project') then raise exception 'Sirf product ya project store par bheja ja sakta hai'; end if;
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
create or replace function public.crm_bp_role_ok(s public.crm_ses) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select coalesce(data #> '{blueprint,visible_roles}', '["admin","manager"]'::jsonb) ? (s).role from public.crm_settings where id = 1),
    (s).role in ('admin', 'manager'));
$$;

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
  -- a lead is created ONLY the first time this account uses any Sunpowers tool; later use never makes another lead
  select id into lid from public.crm_records where kind = 'lead' and deleted_at is null and data ->> 'tools_uid' = u.id::text order by id limit 1;
  if lid is null then
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

  o := o || jsonb_build_object('order_no', public.crm_next_no('order'));
  insert into public.sp_orders(data) values (o) returning id into new_id;
  perform public.sp_notify_admin('Naya order ' || (o->>'order_no') || ' — ' || (o->>'name'),
    '<p>Naya order aaya hai: <b>' || (o->>'order_no') || '</b></p><p>' || (o->>'name') || ' · ' || (o->>'phone') || '</p><p>Total: ₹' || (o->>'total') || ' — payment ka UTR aane par dobara notification milega. Admin panel mein dekhein.</p>');
  return new_id;
end $$;

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
      allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm']
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
  pe := public.crm_auth_pin_check(public.crm_auth_find('crm', 'admin'), p ->> 'pin');
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
 {"g":"Products","k":"items.cost","l":"Kharid rate aur minimum rate dekhe"},
 {"g":"Products","k":"items.to_store","l":"Online Store ko bheje"},
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

create or replace function public.crm_exp_list(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); fr date := coalesce(nullif(p ->> 'from', '')::date, date '2000-01-01'); t date := coalesce(nullif(p ->> 'to', '')::date, date '2999-12-31');
begin
  if not (public.crm_can(s, 'accounts.manage') or public.crm_can(s, 'accounts.view')) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  return coalesce((select jsonb_agg(to_jsonb(e) - 'deleted_at' - 'deleted_by' - 'delete_reason' order by e.spent_on desc, e.id desc)
    from public.crm_expenses e where e.deleted_at is null and e.spent_on between fr and t), '[]'::jsonb);
end $$;

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
  select array['Customer Connect','Starting Conversation','Quotation','Site Visit','Blueprint','Confirmation','Apply Process','Hand Over Technician','Start Installation','Commissioning','Net Metering','Finish Work','Subsidy Redeem'] $$;

create or replace function public.crm_ctypes() returns text[] language sql immutable as $$ select array['Residential','Commercial','Industrial','VFD','Items only'] $$;

create or replace function public.crm_iso_now() returns text language sql stable as $$
  select to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS"+05:30"') $$;

-- sets step n inside data.wf when it is not there yet
create or replace function public.crm_wf_mark(d jsonb, n int, by text, at_ text default null, auto boolean default true) returns jsonb language sql stable as $$
  select case when coalesce(d -> 'wf', '{}'::jsonb) ? n::text then d
    else d || jsonb_build_object('wf', coalesce(d -> 'wf', '{}'::jsonb) || jsonb_build_object(n::text, jsonb_build_object('at', coalesce(at_, public.crm_iso_now()), 'by', coalesce(by, ''), 'auto', auto))) end $$;

-- ---------- rules enforced on every write (cannot be bypassed from the browser) ---------------------
create or replace function public.crm_rules_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare pt public.crm_records; ex public.crm_records; miss text[] := '{}'; nm text; d jsonb; bypass boolean := coalesce(current_setting('sp.wf', true), '') = '1'; ct text;
begin
  if new.deleted_at is not null then return new; end if;
  d := coalesce(new.data, '{}'::jsonb);

  if new.kind = 'lead' then
    nm := trim(coalesce(d ->> 'name', new.title, ''));
    if TG_OP = 'INSERT' or new.mobile is distinct from old.mobile then
      if coalesce(new.mobile, '') !~ '^[6-9][0-9]{9}$' then raise exception 'Lead ke liye sahi 10 ank ka mobile zaroori hai'; end if;
    end if;
    -- forms / signups / ads (inbound): name AND mobile are mandatory.  Manual add / Excel / contacts import: mobile alone is enough.
    if coalesce(d ->> 'intake', '') = 'inbound' and (nm = '' or nm ~* '^lead [0-9]') then raise exception 'Form / signup / ad se aayi lead me naam aur mobile dono zaroori hain'; end if;
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
declare names text[] := public.crm_wf_names(); out jsonb := '[]'::jsonb; i int; w jsonb := coalesce(q.data -> 'wf', '{}'::jsonb); st jsonb; v boolean; e boolean; resid boolean := (q.data ->> 'ctype') = 'Residential';
begin
  for i in 1..13 loop
    continue when i = 13 and not resid;
    st := w -> i::text; v := public.crm_wf_can(s, i, 'view'); e := public.crm_wf_can(s, i, 'edit');
    out := out || jsonb_build_array(jsonb_build_object('n', i, 'name', names[i], 'done', st is not null, 'at', st ->> 'at', 'auto', coalesce((st ->> 'auto')::boolean, false),
      'locked', not v, 'can_edit', e and i not in (1, 2, 3, 6, 12) and (i <> 13 or public.crm_is_admin(s) or (s).role = 'manager'),
      'by', case when v then st ->> 'by' end, 'note', case when v then st ->> 'note' end));
  end loop;
  return out;
end $$;

-- the workflow of one quotation (or the latest quotation of a customer)
create or replace function public.crm_wf_get(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; pt public.crm_records; qid bigint := nullif(p ->> 'id', '')::bigint; pid bigint := nullif(p ->> 'party_id', '')::bigint; plants jsonb;
begin
  if qid is null and pid is not null then
    select * into pt from public.crm_records where id = pid and kind = 'party';
    if pt.id is null or not public.crm_vis(s, pt) then raise exception 'Customer nahi mila'; end if;
    select * into q from public.crm_records where kind = 'quote' and deleted_at is null and party_id = pid order by id desc limit 1;
    select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'ref', x.ref, 'title', coalesce(x.data ->> 'qtitle', x.title), 'ctype', x.data ->> 'ctype', 'status', x.status) order by x.id desc), '[]'::jsonb) into plants
      from public.crm_records x where x.kind = 'quote' and x.deleted_at is null and x.party_id = pid;
    if q.id is null then
      return jsonb_build_object('party_id', pid, 'quote_id', null, 'plants', '[]'::jsonb, 'project', false, 'steps',
        jsonb_build_array(jsonb_build_object('n', 1, 'name', 'Customer Connect', 'done', true, 'at', to_char(pt.created_at at time zone 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS"+05:30"'), 'locked', false),
                          jsonb_build_object('n', 2, 'name', 'Starting Conversation', 'done', true, 'at', to_char(pt.created_at at time zone 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS"+05:30"'), 'locked', false)));
    end if;
  else
    select * into q from public.crm_records where id = qid and kind = 'quote' and deleted_at is null;
    if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
    plants := '[]'::jsonb;
  end if;
  if not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  return jsonb_build_object('party_id', q.party_id, 'quote_id', q.id, 'ref', q.ref, 'title', coalesce(q.data ->> 'qtitle', q.title), 'ctype', q.data ->> 'ctype', 'status', q.status, 'plants', plants,
    'project', (q.data -> 'wf') ? '7', 'bill_state', q.data ->> 'bill_state', 'steps', public.crm_wf_steps(s, q));
end $$;

-- confirm / undo one manual step
create or replace function public.crm_wf_set(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; n int := (p ->> 'step')::int; done boolean := coalesce((p ->> 'done')::boolean, true); note text := left(trim(coalesce(p ->> 'note', '')), 500); d jsonb; w jsonb;
begin
  select * into q from public.crm_records where id = (p ->> 'id')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if n is null or n < 1 or n > 13 then raise exception 'Step galat hai'; end if;
  if n in (1, 2, 3, 6, 12) then raise exception 'Ye step apne aap hota hai (quotation / bill se)'; end if;
  if n = 13 and (q.data ->> 'ctype') <> 'Residential' then raise exception 'Subsidy sirf Residential solar ke liye hai'; end if;
  if n = 13 and not (public.crm_is_admin(s) or (s).role = 'manager') then raise exception 'Subsidy sirf Admin ya Manager green kar sakte hain'; end if;
  if not public.crm_wf_can(s, n, 'edit') then raise exception 'Is step ko badalne ki permission nahi hai — Admin se allow karwayein'; end if;
  w := coalesce(q.data -> 'wf', '{}'::jsonb);
  if done then
    if (q.data ->> 'ctype') = 'Items only' or coalesce(q.data ->> 'ctype', '') = '' then raise exception 'Items-only customer ka process Confirmation par khatam hota hai'; end if;
    if n >= 7 and not (w ? '6') then raise exception 'Pehle quotation Confirm hona chahiye'; end if;
    if n > 7 and not (w ? '7') then raise exception 'Pehle Apply Process confirm karein — tabhi customer Projects me aata hai'; end if;
    w := w || jsonb_build_object(n::text, jsonb_build_object('at', public.crm_iso_now(), 'by', (s).name, 'by_id', (s).uid, 'note', note));
  else
    if not public.crm_is_admin(s) then raise exception 'Step wapas sirf Admin kar sakta hai'; end if;
    w := w - n::text;
  end if;
  perform set_config('sp.wf', '1', true);
  update public.crm_records set data = data || jsonb_build_object('wf', w), updated_at = now() where id = q.id;
  perform set_config('sp.wf', '', true);
  perform public.crm_log(s, 'workflow', 'quote', q.id, coalesce(q.ref, '') || ' — ' || (public.crm_wf_names())[n] || case when done then ' ✔' else ' ↩' end);
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
  return jsonb_build_object('perm', coalesce(cur -> 'perm', '{}'::jsonb), 'allow_old', coalesce((cur ->> 'allow_old')::boolean, false), 'names', to_jsonb(public.crm_wf_names()));
end $$;

-- Projects list (Apply Process confirmed, or an old project Admin allowed)
create or replace function public.crm_projects(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token');
begin
  return coalesce((select jsonb_agg(x order by (x ->> 'id')::bigint desc) from (
    select jsonb_build_object('id', q.id, 'ref', q.ref, 'party_id', q.party_id, 'customer', q.title, 'mobile', q.mobile, 'title', coalesce(q.data ->> 'qtitle', q.title), 'ctype', q.data ->> 'ctype',
      'kw', q.data ->> 'kw', 'amount', q.amount, 'status', q.status, 'bill_state', q.data ->> 'bill_state', 'closed', coalesce((q.data ->> 'closed')::boolean, false), 'old', coalesce((q.data ->> 'old_project')::boolean, false),
      'owner', public.crm_uname(q.owner_id), 'done', (select count(*) from jsonb_object_keys(coalesce(q.data -> 'wf', '{}'::jsonb))),
      'total', case when (q.data ->> 'ctype') = 'Residential' then 13 else 12 end,
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
declare s public.crm_ses := public.crm_session(p ->> 'token'); l public.crm_records; pd jsonb := coalesce(p -> 'party', '{}'::jsonb); mob text; ex public.crm_records; pr jsonb; pid bigint; miss text[] := '{}';
begin
  select * into l from public.crm_records where id = (p ->> 'id')::bigint and kind = 'lead' and deleted_at is null;
  if l.id is null or not public.crm_vis(s, l) then raise exception 'Lead nahi mili'; end if;
  if not (public.crm_is_admin(s) or l.owner_id = (s).uid or l.assigned_to = (s).uid) then raise exception 'Sirf is lead ka user ya Admin ise customer list me bhej sakta hai'; end if;
  if jsonb_array_length(coalesce(l.data -> 'log', '[]'::jsonb)) = 0 then raise exception 'Pehle customer se baat karke "Baat-cheet" me remark likhein, phir Customer list me bhejein'; end if;
  mob := public.crm_mobile(coalesce(pd ->> 'mobile', l.mobile, ''));
  if coalesce(trim(pd ->> 'name'), '') = '' then miss := miss || 'Naam'::text; end if;
  if mob !~ '^[6-9][0-9]{9}$' then miss := miss || 'Mobile'::text; end if;
  if coalesce(trim(pd ->> 'address'), '') = '' then miss := miss || 'Pata'::text; end if;
  if coalesce(trim(pd ->> 'city'), '') = '' then miss := miss || 'Shahar'::text; end if;
  if array_length(miss, 1) > 0 then raise exception 'Customer list me bhejne se pehle ye bharein: %', array_to_string(miss, ', '); end if;
  select * into ex from public.crm_records where kind = 'party' and deleted_at is null and mobile = mob limit 1;
  if ex.id is not null then
    if not public.crm_vis(s, ex) then raise exception 'Ye customer pehle se kisi aur ke paas hai — Admin se transfer karwayein'; end if;
    pid := ex.id;
  else
    pr := public.crm_save(jsonb_build_object('token', p ->> 'token', 'kind', 'party', 'data',
      (pd || jsonb_build_object('mobile', mob, 'source', coalesce(nullif(pd ->> 'source', ''), l.data ->> 'source', ''), 'lead_id', l.id, 'type', 'customer')), 'assigned_to', l.assigned_to));
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
begin
  begin
    perform public.crm_inbound_lead(coalesce(new.data ->> 'name', ''), coalesce(new.data ->> 'phone', new.data ->> 'mobile', ''), case when coalesce(new.data ->> 'source', '') = 'website' then 'Website' else 'Online Store' end,
      coalesce(new.data ->> 'subject', new.data ->> 'type', '') || ' ' || coalesce(new.data ->> 'message', ''), jsonb_build_object('enquiry_id', new.id));
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
        resid boolean := (q.data ->> 'ctype') = 'Residential'; instd text;
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
  for i in 1..13 loop
    continue when i = 13 and not resid;
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

create or replace function public.crm_consumer_unlink_plant(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token');
begin delete from public.crm_consumer_plants where user_id = u.id and quote_id = nullif(p ->> 'id', '')::bigint; return jsonb_build_object('ok', true); end $$;

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
grant execute on function public.crm_consumer_link_plant(jsonb), public.crm_consumer_unlink_plant(jsonb), public.crm_consumer_plants(jsonb), public.crm_consumer_plant_doc(jsonb), public.crm_consumer_file(jsonb) to anon, authenticated;

-- ---------- blueprint tool: reuse the sign-up lead of the same person (one person = one lead) ----------
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

-- (Round 17 fix) Tools (Blueprint / Error Detector): if this person already has a lead from signing up, use THAT lead (one person = one lead)
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
grant execute on function public.sp_tool_use(jsonb) to anon, authenticated;
