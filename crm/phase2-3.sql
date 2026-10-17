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
  allowed := array['name', 'title', 'category', 'subcategory', 'price', 'mrp', 'gst', 'hsn', 'unit', 'desc', 'more', 'brand', 'mpn', 'image_link', 'stock', 'warranty', 'cost_price', 'min_price', 'specs'];
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
      data = (data || (patch - 'specs')) || case when patch ? 'specs' and jsonb_typeof(patch -> 'specs') = 'object' then jsonb_build_object('specs', coalesce(data -> 'specs', '{}'::jsonb) || (patch -> 'specs')) else '{}'::jsonb end,
      search = lower(nm || ' ' || coalesce(patch ->> 'brand', data ->> 'brand', '') || ' ' || coalesce(data ->> 'sku', '') || ' ' || coalesce(patch ->> 'category', data ->> 'category', '') || ' ' || coalesce(patch ->> 'subcategory', data ->> 'subcategory', '')), updated_at = now() where id = r.id;
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
notify pgrst, 'reload schema';
