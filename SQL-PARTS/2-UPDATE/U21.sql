-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 21 of 30
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U30). Safe to re-run.
-- ============================================================================

-- ---------- evaluate (auto + manual -> % / status) ----------
create or replace function public.crm__svc_eval() returns jsonb language plpgsql stable security definer set search_path = public as $f$
declare auto jsonb; out jsonb := '[]'::jsonb; r record; m jsonb; ms jsonb; v numeric; lim numeric; pct numeric; st text; d date; dl int; sbytes numeric := 0;
begin
  if to_regclass('storage.objects') is not null then
    begin execute 'select coalesce(sum((metadata->>''size'')::numeric),0) from storage.objects' into sbytes; exception when others then sbytes := 0; end;
  end if;
  auto := jsonb_build_object(
    'db_mb', round(pg_database_size(current_database()) / 1048576.0, 1),
    'files_mb', round((coalesce((select sum(size) from public.crm_files), 0) + sbytes) / 1048576.0, 1),
    'mail_day', (select count(*) from public.crm_mail_log where at >= date_trunc('day', now())),
    'mail_month', (select count(*) from public.crm_mail_log where at >= date_trunc('month', now())));
  for r in select * from public.crm_services where id <> '_meta' order by sort, id loop
    ms := '[]'::jsonb;
    for m in select * from jsonb_array_elements(coalesce(r.data -> 'metrics', '[]'::jsonb)) loop
      v := null; pct := null; st := 'none';
      if coalesce(m ->> 'type', 'num') = 'date' then
        d := nullif(m ->> 'used', '')::date; 
        if d is not null then dl := d - (now() at time zone 'Asia/Kolkata')::date;
          st := case when dl <= 0 then 'over' when dl <= 30 then 'warn' else 'ok' end;
          m := m || jsonb_build_object('days_left', dl); end if;
      else
        lim := nullif(m ->> 'limit', '')::numeric;
        if nullif(m ->> 'auto', '') is not null and auto ? (m ->> 'auto') then v := (auto ->> (m ->> 'auto'))::numeric; m := m || jsonb_build_object('is_auto', true);
        else v := nullif(m ->> 'used', '')::numeric; end if;
        if v is not null and lim is not null and lim > 0 then pct := round(v * 100.0 / lim, 1); st := case when pct >= 100 then 'over' when pct >= 80 then 'warn' else 'ok' end; end if;
        m := m || jsonb_build_object('val', v, 'pct', pct);
      end if;
      ms := ms || jsonb_build_array(m || jsonb_build_object('state', st));
    end loop;
    out := out || jsonb_build_array((r.data - 'metrics') || jsonb_build_object('metrics', ms, 'sort', r.sort));
  end loop;
  return out;
end $f$;

create or replace function public.crm__svc_alerts() returns int language sql stable security definer set search_path = public as $f$
  select count(*)::int from jsonb_array_elements(public.crm__svc_eval()) s, jsonb_array_elements(s -> 'metrics') m where m ->> 'state' in ('warn', 'over') $f$;
revoke all on function public.crm__svc_eval() from public, anon, authenticated;
revoke all on function public.crm__svc_alerts() from public, anon, authenticated;

create or replace function public.crm_services_get(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); d jsonb; i int := 0;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  if not exists (select 1 from public.crm_services where id = '_meta') then
    for d in select * from jsonb_array_elements(public.crm__svc_defaults()) loop
      i := i + 1; insert into public.crm_services(id, sort, data) values (d ->> 'id', i * 10, d) on conflict (id) do nothing;
    end loop;
    insert into public.crm_services(id, sort, data) values ('_meta', -1, '{}'::jsonb);
  end if;
  return jsonb_build_object('services', public.crm__svc_eval(), 'defaults', public.crm__svc_defaults(), 'today', (now() at time zone 'Asia/Kolkata')::date);
end $f$;

create or replace function public.crm_services_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); arr jsonb := p -> 'services'; x jsonb; mx jsonb; ms jsonb; links jsonb; l jsonb; i int := 0; sid text; old jsonb; om text; used text; oused text; today text := ((now() at time zone 'Asia/Kolkata')::date)::text; k text;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  if jsonb_typeof(arr) <> 'array' or jsonb_array_length(arr) > 30 then raise exception 'Services list galat ya bahut badi'; end if;
  create temp table if not exists _svc_new(id text, sort int, data jsonb) on commit drop;
  truncate _svc_new;
  for x in select * from jsonb_array_elements(arr) loop
    i := i + 1;
    sid := lower(regexp_replace(coalesce(x ->> 'id', ''), '[^a-zA-Z0-9_-]', '', 'g'));
    if sid = '' or sid = '_meta' then sid := 'svc' || (extract(epoch from clock_timestamp()) * 1000)::bigint::text || i; end if;
    if length(left(trim(coalesce(x ->> 'name', '')), 60)) < 2 then raise exception 'Service ka naam likhein'; end if;
    select data into old from public.crm_services where id = sid;
    links := '[]'::jsonb;
    for l in select * from jsonb_array_elements(coalesce(x -> 'links', '[]'::jsonb)) loop
      if (l ->> 'u') ~* '^https://[^ ]{4,255}$' and length(coalesce(l ->> 't', '')) between 1 and 40 then links := links || jsonb_build_array(jsonb_build_object('t', l ->> 't', 'u', l ->> 'u')); end if;
    end loop;
    ms := '[]'::jsonb;
    for mx in select * from jsonb_array_elements(coalesce(x -> 'metrics', '[]'::jsonb)) loop
      exit when jsonb_array_length(ms) >= 12;
      k := lower(regexp_replace(coalesce(mx ->> 'k', ''), '[^a-zA-Z0-9_-]', '', 'g'));
      if k = '' then k := 'm' || jsonb_array_length(ms); end if;
      used := left(coalesce(mx ->> 'used', ''), 30);
      if coalesce(mx ->> 'type', 'num') = 'date' then
        if used <> '' and used !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Date galat: %', used; end if;
      elsif used <> '' and used !~ '^-?\d+(\.\d+)?$' then raise exception 'Sirf number likhein: %', left(used, 20); end if;
      oused := null;
      select o ->> 'used' into oused from jsonb_array_elements(coalesce(old -> 'metrics', '[]'::jsonb)) o where o ->> 'k' = k limit 1;
      select o ->> 'at' into om from jsonb_array_elements(coalesce(old -> 'metrics', '[]'::jsonb)) o where o ->> 'k' = k limit 1;
      ms := ms || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'k', k, 'label', left(trim(coalesce(mx ->> 'label', k)), 120), 'unit', left(coalesce(mx ->> 'unit', ''), 20),
        'type', case when mx ->> 'type' = 'date' then 'date' end,
        'limit', case when coalesce(mx ->> 'limit', '') ~ '^\d+(\.\d+)?$' then (mx ->> 'limit')::numeric end,
        'auto', case when mx ->> 'auto' in ('db_mb', 'files_mb', 'mail_day', 'mail_month') then mx ->> 'auto' end,
        'hint', nullif(left(coalesce(mx ->> 'hint', ''), 160), ''),
        'used', nullif(used, ''),
        'at', case when used = '' then null when oused is distinct from used then today else coalesce(om, today) end)));
    end loop;
    insert into _svc_new values (sid, i * 10, jsonb_strip_nulls(jsonb_build_object('id', sid, 'name', left(trim(x ->> 'name'), 60), 'what', nullif(left(coalesce(x ->> 'what', ''), 160), ''),
      'plan', nullif(left(coalesce(x ->> 'plan', ''), 60), ''), 'note', nullif(left(coalesce(x ->> 'note', ''), 400), ''), 'links', links, 'metrics', ms)));
  end loop;
  delete from public.crm_services where id <> '_meta';
  insert into public.crm_services(id, sort, data) select id, sort, data from _svc_new on conflict (id) do update set sort = excluded.sort, data = excluded.data, updated_at = now();
  insert into public.crm_services(id, sort, data) values ('_meta', -1, '{}'::jsonb) on conflict (id) do nothing;
  perform public.crm_log(s, 'update', 'services', null, 'Services & Limits badle (' || i || ' services)');
  return jsonb_build_object('ok', true, 'services', public.crm__svc_eval());
end $f$;
grant execute on function public.crm_services_get(jsonb), public.crm_services_save(jsonb) to anon, authenticated;

-- ---------- (A) CUSTOMER HIDE / ERASE ----------
-- bills (invoice + payment) KABHI nahi chhute. Customer ki row sirf naam / mobile / pata / GST ke saath rehti hai (bill par chhapne ke liye).
create or replace function public.crm__cust_scope(pid bigint) returns jsonb language plpgsql stable security definer set search_path = public as $f$
declare pr public.crm_records; u bigint[]; keepq bigint[];
begin
  select * into pr from public.crm_records where id = pid and kind = 'party';
  if pr.id is null then raise exception 'Customer nahi mila'; end if;
  select array_agg(id) into u from public.crm_users where role = 'consumer' and mobile = pr.mobile and pr.mobile is not null and pr.mobile <> '';
  select array_agg(distinct nullif(data ->> 'quote_id', '')::bigint) into keepq from public.crm_records where kind = 'invoice' and party_id = pid;
  return jsonb_build_object(
    'party', pr.id, 'name', pr.title, 'mobile', pr.mobile, 'users', coalesce(to_jsonb(u), '[]'::jsonb), 'keep_quotes', coalesce(to_jsonb(keepq), '[]'::jsonb),
    'bills', (select count(*) from public.crm_records where party_id = pid and kind = 'invoice'),
    'payments', (select count(*) from public.crm_records where party_id = pid and kind = 'payment'),
    'bill_amount', (select coalesce(sum(amount), 0) from public.crm_records where party_id = pid and kind = 'invoice' and deleted_at is null));
end $f$;

create or replace function public.crm_cust_erase_preview(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); sc jsonb; pid bigint := (p ->> 'id')::bigint; keepq bigint[]; mob text;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  sc := public.crm__cust_scope(pid); mob := sc ->> 'mobile';
  select coalesce(array_agg(x::bigint), '{}') into keepq from jsonb_array_elements_text(sc -> 'keep_quotes') x;
  return sc || jsonb_build_object(
    'leads', (select count(*) from public.crm_records where kind = 'lead' and (party_id = pid or (mob is not null and mob <> '' and mobile = mob))),
    'quotes', (select count(*) from public.crm_records where kind = 'quote' and party_id = pid and not (id = any (keepq))),
    'quotes_kept', (select count(*) from public.crm_records where kind = 'quote' and party_id = pid and id = any (keepq)),
    'docs', (select count(*) from public.crm_records where kind = 'doc' and party_id = pid),
    'files_bytes', coalesce((select sum(f.size) from public.crm_files f join public.crm_records d on d.id = f.rec_id where d.party_id = pid), 0),
    'plants', (select count(*) from public.crm_records where kind = 'plant' and party_id = pid),
    'reminders', (select count(*) from public.crm_records where kind in ('reminder', 'note') and party_id = pid),
    'other', (select count(*) from public.crm_records where party_id = pid and kind not in ('invoice', 'payment', 'lead', 'quote', 'doc', 'plant', 'reminder', 'note')),
    'flows', (select count(*) from public.crm_flow_rec where party_id = pid),
    'decls', (select count(*) from public.crm_decl where party_id = pid),
    'checkups', (select count(*) from public.crm_checkup where party_id = pid),
    'logins', jsonb_array_length(sc -> 'users'),
    'enquiries', (select count(*) from public.sp_enquiries where mob is not null and mob <> '' and (data ->> 'mobile' = mob or data ->> 'phone' = mob)));
end $f$;

create or replace function public.crm_cust_erase_backup(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); sc jsonb; pid bigint := (p ->> 'id')::bigint; mob text; fsum bigint; out jsonb;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  sc := public.crm__cust_scope(pid); mob := sc ->> 'mobile';
  select coalesce(sum(f.size), 0) into fsum from public.crm_files f join public.crm_records d on d.id = f.rec_id where d.party_id = pid;
  out := jsonb_build_object('kind', 'sunpowers-customer-backup', 'at', now(), 'customer', sc ->> 'name', 'mobile', mob,
    'records', coalesce((select jsonb_agg(to_jsonb(r) - 'search') from public.crm_records r where r.id = pid or r.party_id = pid or (r.kind = 'lead' and mob is not null and mob <> '' and r.mobile = mob)), '[]'::jsonb),
    'flows', coalesce((select jsonb_agg(to_jsonb(f)) from public.crm_flow_rec f where f.party_id = pid), '[]'::jsonb),
    'decls', coalesce((select jsonb_agg(to_jsonb(d) - 'token') from public.crm_decl d where d.party_id = pid), '[]'::jsonb),
    'checkups', coalesce((select jsonb_agg(to_jsonb(c)) from public.crm_checkup c where c.party_id = pid), '[]'::jsonb),
    'logins', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'mobile', u.mobile, 'email', u.email, 'created_at', u.created_at)) from public.crm_users u where u.role = 'consumer' and u.mobile = mob and mob <> ''), '[]'::jsonb),
    'enquiries', coalesce((select jsonb_agg(to_jsonb(e)) from public.sp_enquiries e where mob is not null and mob <> '' and (e.data ->> 'mobile' = mob or e.data ->> 'phone' = mob)), '[]'::jsonb),
    'files_bytes', fsum);
  if fsum <= 15 * 1024 * 1024 then
    out := out || jsonb_build_object('files', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'rec_id', f.rec_id, 'mime', f.mime, 'size', f.size, 'b64', encode(f.data, 'base64')))
      from public.crm_files f join public.crm_records d on d.id = f.rec_id where d.party_id = pid), '[]'::jsonb));
  else
    out := out || jsonb_build_object('files_skipped', true, 'files_note', 'Files 15 MB se zyada hain — pehle CRM me customer ke Documents se alag download kar lein');
  end if;
  perform public.crm_log(s, 'backup', 'party', pid, 'Customer ka backup nikala: ' || (sc ->> 'name'));
  return out;
end $f$;

create or replace function public.crm_cust_hide(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pr public.crm_records; why text := left(trim(coalesce(p ->> 'reason', '')), 300);
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  select * into pr from public.crm_records where id = (p ->> 'id')::bigint and kind = 'party';
  if pr.id is null then raise exception 'Customer nahi mila'; end if;
  if pr.deleted_at is not null then raise exception 'Ye customer pehle se hata hua hai'; end if;
  update public.crm_records set deleted_at = now(), deleted_by = (s).uid, delete_reason = 'HIDDEN: ' || why, data = data || jsonb_build_object('hidden', true, 'hidden_at', now()) where id = pr.id;
  perform public.crm_log(s, 'hide', 'party', pr.id, 'Customer chhupaya: ' || pr.title || case when why <> '' then ' — ' || why else '' end);
  return jsonb_build_object('ok', true);
end $f$;

create or replace function public.crm_cust_unhide(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pr public.crm_records;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  select * into pr from public.crm_records where id = (p ->> 'id')::bigint and kind = 'party';
  if pr.id is null or coalesce(pr.data ->> 'hidden', '') <> 'true' or coalesce(pr.data ->> 'erased', '') = 'true' then raise exception 'Ye chhupa hua customer nahi hai'; end if;
  update public.crm_records set deleted_at = null, deleted_by = null, delete_reason = null, data = data - 'hidden' - 'hidden_at' where id = pr.id;
  perform public.crm_log(s, 'unhide', 'party', pr.id, 'Customer wapas dikhaya: ' || pr.title);
  return jsonb_build_object('ok', true);
end $f$;

create or replace function public.crm_cust_erase(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pid bigint := (p ->> 'id')::bigint; pr public.crm_records; pe text; sc jsonb; keepq bigint[]; mob text; uids bigint[]; did bigint[]; n jsonb;
        why text := left(trim(coalesce(p ->> 'reason', '')), 300); keep jsonb; cnt_f bigint;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  select * into pr from public.crm_records where id = pid and kind = 'party';
  if pr.id is null then raise exception 'Customer nahi mila'; end if;
  if coalesce(pr.data ->> 'erased', '') = 'true' then raise exception 'Ye customer pehle hi hamesha ke liye hata diya gaya hai'; end if;
  if coalesce((p ->> 'backup_done')::boolean, false) is not true then raise exception 'Pehle backup download karein'; end if;
  if lower(trim(coalesce(p ->> 'confirm_name', ''))) <> lower(trim(pr.title)) then raise exception 'Customer ka naam bilkul wahi likhein jo upar hai'; end if;
  pe := public.crm_auth_pin_check(public.crm_auth_find('admin', 'admin'), p ->> 'pin');
  if pe is not null then return jsonb_build_object('error', pe); end if;
  sc := public.crm__cust_scope(pid); mob := pr.mobile;
  select coalesce(array_agg(x::bigint), '{}') into keepq from jsonb_array_elements_text(sc -> 'keep_quotes') x;
  select coalesce(array_agg(x::bigint), '{}') into uids from jsonb_array_elements_text(sc -> 'users') x;
  n := public.crm_cust_erase_preview(p);
  -- documents + files
  select coalesce(array_agg(id), '{}') into did from public.crm_records where party_id = pid and kind = 'doc';
  delete from public.crm_files where rec_id = any (did);
  -- children (invoice / payment / bill ki quote chhodkar)
  delete from public.crm_records where party_id = pid and kind not in ('invoice', 'payment') and not (id = any (keepq));
  delete from public.crm_records where kind = 'lead' and mob is not null and mob <> '' and mobile = mob;
  delete from public.crm_flow_rec where party_id = pid;
  delete from public.crm_decl where party_id = pid;
  delete from public.crm_checkup where party_id = pid;
  delete from public.crm_consumer_plants where user_id = any (uids);
  delete from public.crm_sessions where user_id = any (uids);
  delete from public.crm_devices where user_id = any (uids);
  delete from public.crm_users where id = any (uids) and role = 'consumer';
  if mob is not null and mob <> '' then delete from public.sp_enquiries where data ->> 'mobile' = mob or data ->> 'phone' = mob; end if;
  -- customer ki row: sirf bill par chhapne layak details
  keep := jsonb_strip_nulls(jsonb_build_object('name', pr.data -> 'name', 'type', coalesce(pr.data -> 'type', '"customer"'::jsonb), 'cust_id', pr.data -> 'cust_id', 'mobile', pr.data -> 'mobile',
    'address', pr.data -> 'address', 'city', pr.data -> 'city', 'state', pr.data -> 'state', 'pincode', pr.data -> 'pincode', 'gstin', pr.data -> 'gstin', 'gst', pr.data -> 'gst',
    'erased', true, 'erased_at', now()));
  update public.crm_records set data = keep, status = '', assigned_to = null, due_at = null, deleted_at = now(), deleted_by = (s).uid, delete_reason = 'ERASED: ' || why where id = pid;
  perform public.crm_log(s, 'erase', 'party', pid, 'Customer hamesha ke liye hataya (bill rakhe): ' || pr.title || ' — ' || why);
  return jsonb_build_object('ok', true, 'removed', n);
end $f$;

create or replace function public.crm_cust_gone_list(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token');
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'name', r.title, 'mobile', r.mobile, 'cust_id', r.data ->> 'cust_id',
      'mode', case when r.data ->> 'erased' = 'true' then 'erased' else 'hidden' end, 'at', r.deleted_at, 'reason', r.delete_reason, 'by', public.crm_uname(r.deleted_by),
      'bills', (select count(*) from public.crm_records b where b.party_id = r.id and b.kind = 'invoice')) order by r.deleted_at desc)
    from public.crm_records r where r.kind = 'party' and r.deleted_at is not null and (r.data ->> 'hidden' = 'true' or r.data ->> 'erased' = 'true')), '[]'::jsonb);
end $f$;
grant execute on function public.crm_cust_erase_preview(jsonb), public.crm_cust_erase_backup(jsonb), public.crm_cust_hide(jsonb), public.crm_cust_unhide(jsonb), public.crm_cust_erase(jsonb), public.crm_cust_gone_list(jsonb) to anon, authenticated;
revoke all on function public.crm__cust_scope(bigint) from public, anon, authenticated;


-- ---------- BUG FIX: Admin PIN check (Restore / Login-settings save / Admin-keep) purane 'crm','admin' lookup se "Ye ID nahi mili" deta tha ----------
CREATE OR REPLACE FUNCTION public.crm_restore(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pe text; part text := coalesce(p ->> 'part', ''); rows jsonb := coalesce(p -> 'rows', '[]'::jsonb);
  allowed text[] := array['crm_records', 'crm_counters', 'crm_expenses', 'sp_orders', 'sp_enquiries', 'sp_store', 'crm_files'];
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
  if part in ('crm_records', 'crm_expenses', 'sp_orders', 'sp_enquiries', 'crm_files') and pg_get_serial_sequence('public.' || part, 'id') is not null then
    execute format('select setval(pg_get_serial_sequence(%L, ''id''), greatest((select coalesce(max(id), 1) from public.%I), 1))', 'public.' || part, part);
  end if;
  perform public.crm_log(s, 'restore', part, null, 'Backup se wapas laya: ' || part || ' (' || n || ' rows)');
  return jsonb_build_object('part', part, 'restored', n);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_auth_admin_save(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); au jsonb := coalesce(p -> 'auth', '{}'::jsonb); pe text; e1 text := lower(trim(coalesce(p ->> 'email', ''))); e2 text := lower(trim(coalesce(p ->> 'email2', '')));
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  pe := public.crm_auth_pin_check(public.crm_auth_find('admin', 'admin'), p ->> 'pin');
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
end $function$;

CREATE OR REPLACE FUNCTION public.crm_admin_keep(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pe text; on_ boolean := coalesce((p ->> 'on')::boolean, false);
begin
  if not public.crm_is_admin(s) or (s).uid <> 0 then raise exception 'Ye option sirf Admin ke liye hai'; end if;
  pe := public.crm_auth_pin_check(public.crm_auth_find('admin', 'admin'), p ->> 'pin');
  if pe is not null then return jsonb_build_object('error', pe); end if;
  update public.crm_sessions set keep = on_, expires_at = now() + case when on_ then interval '365 days' else interval '12 hours' end where token = p ->> 'token' and user_id = 0;
  perform public.crm_log(s, 'settings', null, null, case when on_ then 'Admin login is device par yaad rakha' else 'Admin login yaad rakhna band' end);
  return jsonb_build_object('ok', true, 'keep', on_);
end $function$;

-- ---------- bell: Admin ko service alert ----------
CREATE OR REPLACE FUNCTION public.crm_pulse(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); since timestamptz := coalesce(nullif(p ->> 'since', '')::timestamptz, now() - interval '3 days'); items jsonb := '[]'::jsonb;
begin
  if public.crm_can(s, 'orders.view') then
    items := items || coalesce((select jsonb_agg(jsonb_build_object('type', 'order', 'id', id, 'at', created_at, 'title', 'Naya order #' || id || ' — ' || coalesce(data ->> 'name', ''), 'amount', data -> 'total'))
      from (select * from public.sp_orders where created_at > since order by id desc limit 20) o), '[]'::jsonb);
    items := items || coalesce((select jsonb_agg(jsonb_build_object('type', 'enquiry', 'id', id, 'at', created_at, 'title', 'Nayi enquiry — ' || coalesce(data ->> 'name', '') || ' (' || coalesce(data ->> 'source', 'store') || ')'))
      from (select * from public.sp_enquiries where created_at > since order by id desc limit 20) e), '[]'::jsonb);
  end if;
  items := items || coalesce((select jsonb_agg(jsonb_build_object('type', 'lead', 'id', id, 'at', updated_at, 'title', 'Lead mili: ' || title))
    from (select * from public.crm_records where kind = 'lead' and deleted_at is null and assigned_to = (s).uid and owner_id <> (s).uid and updated_at > since order by id desc limit 20) l), '[]'::jsonb);
  items := items || coalesce((select jsonb_agg(jsonb_build_object('type', 'reminder', 'id', id, 'at', created_at, 'title', 'Naya kaam: ' || title || ' (' || to_char(due_at, 'DD-MM') || ')'))
    from (select * from public.crm_records where kind = 'reminder' and deleted_at is null and assigned_to = (s).uid and owner_id <> (s).uid and created_at > since order by id desc limit 20) l), '[]'::jsonb);
  if public.crm_can(s, 'plants.verify') then
    items := items || coalesce((select jsonb_agg(jsonb_build_object('type', 'plant', 'id', id, 'at', created_at, 'title', 'Plant verify karna hai: ' || title))
      from (select * from public.crm_records where kind = 'plant' and deleted_at is null and status = 'pending' and created_at > since order by id desc limit 20) l), '[]'::jsonb);
  end if;
  if public.crm_can(s, 'users.manage') then
    items := items || coalesce((select jsonb_agg(jsonb_build_object('type', 'user', 'id', id, 'at', created_at, 'title', 'Nayi ID verify karni hai: ' || name || ' (' || role || ')'))
      from (select * from public.crm_users where status = 'pending' and created_at > since order by id desc limit 20) l), '[]'::jsonb);
  end if;
  if public.crm_is_admin(s) then
    declare n int := public.crm__svc_alerts();
    begin
      if n > 0 then items := items || jsonb_build_array(jsonb_build_object('type', 'svc', 'id', 0, 'at', date_trunc('day', now()), 'title', 'Services & Limits: ' || n || ' service ki limit / date paas hai — Settings me dekhein')); end if;
    end;
  end if;
  return jsonb_build_object('now', now(), 'items', items);
end $function$;
-- =====================================================================================================
-- ROUND 52 — Quotation: ek link, andar OPTIONS (brand), final par LOCK, link se Accept / Badlav chahiye / Call back,
--            link expiry (+ / - / pause), accepted quotation ka expire hona band, quotation PDF me bank box setting.
--   Sirf MANUAL quotations ke liye (Online Store ka flow nahi badla). Link se koi payment nahi.
--   Dobara chalana safe hai. Naye column: sp_shares.quote_id / live / expiry_manual / bad_tries / bad_at.
-- =====================================================================================================
alter table public.sp_shares add column if not exists quote_id bigint;
alter table public.sp_shares add column if not exists live boolean not null default false;
alter table public.sp_shares add column if not exists expiry_manual boolean not null default false;
alter table public.sp_shares add column if not exists bad_tries int not null default 0;
alter table public.sp_shares add column if not exists bad_at timestamptz;
create index if not exists sp_shares_quote_idx on public.sp_shares(quote_id) where quote_id is not null;

-- ---------- link ki auto expiry: Valid till + 7 din; lock ke baad lamba; rejected par chhota ----------
create or replace function public.crm__quote_link_expiry(q public.crm_records) returns timestamptz language plpgsql stable security definer set search_path = public as $f$
declare vt date;
begin
  if q.data ->> 'closed' = 'true' then return now() + interval '30 days'; end if;
  if q.data -> 'locked' is not null then return greatest(now() + interval '365 days', now()); end if;
  if q.status = 'rejected' then return now() + interval '3 days'; end if;
  begin vt := (q.data ->> 'valid_till')::date; exception when others then vt := null; end;
  if vt is null then return now() + interval '30 days'; end if;
  return ((vt + 8)::timestamp) at time zone 'Asia/Kolkata';
end $f$;
revoke all on function public.crm__quote_link_expiry(public.crm_records) from public, anon, authenticated;

create or replace function public.crm__quote_share_sync() returns trigger language plpgsql security definer set search_path = public as $f$
begin
  update public.sp_shares set expires_at = public.crm__quote_link_expiry(new) where quote_id = new.id and live and not expiry_manual;
  return new;
end $f$;
drop trigger if exists crm_quote_share_sync on public.crm_records;
create trigger crm_quote_share_sync after update of data, status on public.crm_records for each row when (new.kind = 'quote') execute function public.crm__quote_share_sync();

-- ---------- accepted quotation ab expire nahi hoti (pehle Valid till ke baad "expired" ho jati thi) ----------
create or replace function public.crm_quote_expire_daily() returns void language plpgsql security definer set search_path = public as $f$
declare td text := public.crm_today()::text;
begin
  if coalesce((select data #>> '{stock,expire_day}' from public.crm_settings where id = 1), '') = td then return; end if;
  update public.crm_records set status = 'expired', data = data || jsonb_build_object('pre_expire', status, 'expired_on', td), updated_at = now()
  where kind = 'quote' and deleted_at is null and status in ('draft', 'sent') and data -> 'locked' is null and coalesce(data ->> 'valid_till', '') ~ '^\d{4}-\d{2}-\d{2}$' and (data ->> 'valid_till') < td;
  update public.crm_settings set data = jsonb_set(coalesce(data, '{}'::jsonb), '{stock,expire_day}', to_jsonb(td), true) where id = 1;
end $f$;
-- jo accepted quotation pehle galti se expired ho chuki (kaam chal raha hai) unhe wapas accepted
update public.crm_records set status = coalesce(nullif(data ->> 'pre_expire', ''), 'accepted'), data = data - 'pre_expire' - 'expired_on'
 where kind = 'quote' and status = 'expired' and deleted_at is null and data ->> 'pre_expire' = 'accepted';

-- ---------- option ki jaanch (rate ki limit, inventory item) ----------
create or replace function public.crm__opt_guard(s public.crm_ses, p_lines jsonb, p_disc numeric) returns jsonb language plpgsql security definer set search_path = public as $f$
declare l jsonb; it public.crm_records; calc jsonb; lim numeric;
begin
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'Kam se kam 1 item jodein'; end if;
  for l in select * from jsonb_array_elements(p_lines) loop
    if public.crm_num(l -> 'qty') <= 0 then raise exception 'Har item ki Qty likhein'; end if;
    if coalesce(l ->> 'kind', 'product') <> 'project' and coalesce(l ->> 'item_id', '') = '' then raise exception 'Har item Inventory se hi chunna hoga — "%" Inventory me nahi hai.', coalesce(nullif(l ->> 'name', ''), '?'); end if;
    if coalesce(l ->> 'item_id', '') <> '' and not exists (select 1 from public.crm_records i where i.id = (l ->> 'item_id')::bigint and i.kind = 'item') then raise exception '"%" Inventory me nahi mila. Item dobara chunein.', coalesce(nullif(l ->> 'name', ''), '?'); end if;
  end loop;
  calc := public.crm_doc_calc(jsonb_build_object('lines', p_lines, 'discount', p_disc));
  if not public.crm_can(s, 'quotes.discount_any') then
    for l in select * from jsonb_array_elements(p_lines) loop
      if coalesce(l ->> 'kind', 'product') <> 'project' and coalesce(l ->> 'item_id', '') <> '' then
        select * into it from public.crm_records where id = (l ->> 'item_id')::bigint and kind = 'item';
        if it.id is not null and public.crm_num(it.data -> 'cost_price') > 0 and public.crm_num(l -> 'price') < public.crm_num(it.data -> 'cost_price') - 0.009 then raise exception '"%" ka rate kharid rate se kam nahi ho sakta', it.title; end if;
        if it.id is not null and public.crm_num(it.data -> 'min_price') > 0 and public.crm_num(l -> 'price') < public.crm_num(it.data -> 'min_price') then raise exception '"%" ka rate minimum rate se kam hai — Admin se permission lein', it.title; end if;
      end if;
    end loop;
    select coalesce(nullif(public.crm_num(meta -> 'max_discount_pct'), 0), public.crm_role_discount(role)) into lim from public.crm_users where id = (s).uid;
    if (s).uid <> 0 and public.crm_num(calc -> 'discount') > 0 and public.crm_num(calc -> 'discount') > coalesce(lim, 0) * (public.crm_num(calc -> 'subtotal') + public.crm_num(calc -> 'gst_total')) / 100 + 0.009 then raise exception 'Discount aapki limit (% %%) se zyada hai', coalesce(lim, 0); end if;
  end if;
  return calc;
end $f$;
revoke all on function public.crm__opt_guard(public.crm_ses, jsonb, numeric) from public, anon, authenticated;