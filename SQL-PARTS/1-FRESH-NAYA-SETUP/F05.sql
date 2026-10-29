-- ============================================================================
-- SUNPOWERS — NAYA PROJECT SETUP — part 5 of 36
-- Naya (khali) Supabase project: pehle F01..F06, phir 2-UPDATE ke U01..U30.
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (F01 -> F06, phir U01 -> U30). Safe to re-run.
-- ============================================================================

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