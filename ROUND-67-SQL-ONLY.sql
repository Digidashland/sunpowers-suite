-- ROUND 67 — sirf ye ek SQL chalana hai (Round 66 ke baad). Supabase SQL Editor me poora paste karke Run.

-- =====================================================================================================
-- ROUND 67 (U34) — MASTER BACKUP: CRM ke ek click me ab poora data (website/shop/store/admin settings, CRM, team+HR, delivery, sell rules).
--   crm_backup  : 13 ki jagah ~32 hisse (sirf Admin + PIN). Password / PIN-hash / login-OTP / session / analytics log backup me NAHI jaate.
--   crm_restore : naye hisse bhi wapas ho sakte hain (primary key se update; naya data delete nahi hota).
--   Dobara chalana safe hai. Koi table / data nahi badalta.
-- =====================================================================================================
create or replace function public.crm_backup(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pe text; part text := coalesce(p ->> 'part', 'meta');
  off int := greatest(coalesce((p ->> 'offset')::int, 0), 0); lim int; r jsonb; cnt jsonb := '{}'::jsonb; t text;
  parts text[] := array[
    'crm_settings', 'crm_auth_admin', 'crm_roles', 'crm_users', 'crm_records', 'crm_counters', 'crm_activity', 'crm_files', 'crm_expenses',
    'crm_services', 'crm_checkup', 'crm_decl', 'crm_flow_rec', 'crm_consumer_plants',
    'crm_staff_hr', 'crm_leave', 'crm_attendance', 'crm_salary_pay', 'crm_staff_adv',
    'sp_store', 'sp_orders', 'sp_enquiries', 'sp_design_pay', 'sp_shares',
    'sp_sell', 'sp_sell_cfg', 'sp_sub_cfg', 'sp_sub_state', 'sp_pin_areas', 'sp_pin_modes', 'sp_pin_rules', 'sp_ship_rules'];
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  pe := public.crm_auth_pin_check(public.crm_auth_find('admin', 'admin'), p ->> 'pin');
  if pe is not null then return jsonb_build_object('error', pe); end if;
  if part = 'meta' then
    foreach t in array parts loop
      if to_regclass('public.' || t) is not null then execute format('select count(*) from public.%I', t) into lim; cnt := cnt || jsonb_build_object(t, lim); end if;
    end loop;
    perform public.crm_log(s, 'backup', null, null, 'Poora backup download kiya');
    return jsonb_build_object('app', 'sunpowers-suite', 'format', 2, 'at', now(), 'by', (s).name, 'parts', to_jsonb(parts), 'counts', cnt);
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
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from (select * from public.%I order by ctid offset %s limit %s) x', part, off, lim) into r;
  end if;
  return jsonb_build_object('part', part, 'rows', r, 'next', case when jsonb_array_length(r) = lim and part not in ('crm_settings', 'crm_auth_admin') then off + lim end);
end $$;

create or replace function public.crm_restore(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pe text; part text := coalesce(p ->> 'part', ''); rows jsonb := coalesce(p -> 'rows', '[]'::jsonb);
  allowed text[] := array['crm_records', 'crm_counters', 'crm_expenses', 'sp_orders', 'sp_enquiries', 'sp_store', 'crm_files', 'sp_design_pay',
    'crm_services', 'crm_checkup', 'crm_decl', 'crm_flow_rec', 'crm_consumer_plants', 'crm_staff_hr', 'crm_leave', 'crm_attendance', 'crm_salary_pay', 'crm_staff_adv',
    'sp_shares', 'sp_sell', 'sp_sell_cfg', 'sp_sub_cfg', 'sp_sub_state', 'sp_pin_areas', 'sp_pin_modes', 'sp_pin_rules', 'sp_ship_rules'];
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
  /* backup ka data pehle se sahi tha: business-rule triggers (duplicate quotation, lead dedupe…) restore ko na rokein. Galti par poora transaction wapas hota hai, trigger apne-aap chalu rehta hai. */
  execute format('alter table public.%I disable trigger user', part);
  if part = 'crm_files' then
    insert into public.crm_files(id, rec_id, mime, size, data)
    select (x ->> 'id')::bigint, (x ->> 'rec_id')::bigint, coalesce(x ->> 'mime', 'application/octet-stream'), coalesce((x ->> 'size')::int, 0), decode(x ->> 'b64', 'base64')
    from jsonb_array_elements(rows) x
    on conflict (id) do update set rec_id = excluded.rec_id, mime = excluded.mime, size = excluded.size, data = excluded.data;
    get diagnostics n = row_count;
  else
    select string_agg(format('%I', a.attname), ', ' order by a.attnum) into pk
      from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any (i.indkey) where i.indrelid = ('public.' || part)::regclass and i.indisprimary;
    if pk is null then raise exception 'Is hisse ki key nahi mili: %', part; end if;
    select string_agg(format('%I', column_name), ', ' order by ordinal_position),
           string_agg(case when format('%I', column_name) = any (string_to_array(pk, ', ')) then null when part = 'crm_counters' and column_name = 'n' then 'n = greatest(public.crm_counters.n, excluded.n)' else format('%1$I = excluded.%1$I', column_name) end, ', ' order by ordinal_position)
      into cols, setl from information_schema.columns where table_schema = 'public' and table_name = part;
    if setl is null then
      execute format('insert into public.%1$I (%2$s) select %2$s from jsonb_populate_recordset(null::public.%1$I, $1) on conflict (%3$s) do nothing', part, cols, pk) using rows;
    else
      execute format('insert into public.%1$I (%2$s) select %2$s from jsonb_populate_recordset(null::public.%1$I, $1) on conflict (%3$s) do update set %4$s', part, cols, pk, setl) using rows;
    end if;
    get diagnostics n = row_count;
  end if;
  execute format('alter table public.%I enable trigger user', part);
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = part and column_name = 'id') and pg_get_serial_sequence('public.' || part, 'id') is not null then
    execute format('select setval(pg_get_serial_sequence(%L, ''id''), greatest((select coalesce(max(id), 1) from public.%I), 1))', 'public.' || part, part);
  end if;
  perform public.crm_log(s, 'restore', part, null, 'Backup se wapas laya: ' || part || ' (' || n || ' rows)');
  return jsonb_build_object('part', part, 'restored', n);
end $$;
