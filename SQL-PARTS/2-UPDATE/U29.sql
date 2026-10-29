-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 29 of 30
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U30). Safe to re-run.
-- ============================================================================

-- ---------- hisaab: kul subsidy kitni (PUBLIC — sirf jankari, koi gopniya cheez nahi) ------------------
create or replace function public.sp_sub_calc(p_state text, p_kw numeric, p_sys text default 'on', p_res boolean default true) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare cfg public.sp_sub_cfg; st public.sp_sub_state; sy text; kw numeric := coalesce(p_kw, 0); c numeric := 0; s numeric := 0; sp boolean := false; sn text := public.sp_sub_norm(p_state); r1 numeric; r2 numeric;
begin
  select * into cfg from public.sp_sub_cfg where id = 1;
  if not found or not cfg.enabled then return jsonb_build_object('ok', false, 'reason', 'off'); end if;
  sy := lower(coalesce(nullif(btrim(p_sys), ''), 'on'));
  sy := case when sy in ('hy', 'hybrid') then 'hy' when sy in ('off', 'offgrid', 'off-grid') then 'off' else 'on' end;
  if not coalesce(p_res, false) then return jsonb_build_object('ok', false, 'reason', 'not_res'); end if;
  if sy = 'off' then return jsonb_build_object('ok', false, 'reason', 'offgrid'); end if;
  if kw <= 0 then return jsonb_build_object('ok', false, 'reason', 'nokw'); end if;
  if sn <> '' then select * into st from public.sp_sub_state where state_u = sn; end if;
  sp := coalesce(st.special, false);
  r1 := case when sp then cfg.r1_sp else cfg.r1 end; r2 := case when sp then cfg.r2_sp else cfg.r2 end;
  c := least(kw, 2) * r1 + least(greatest(kw - 2, 0), greatest(cfg.cap_kw - 2, 0)) * r2;
  if st.state_u is not null and st.active then
    s := case when st.fixed > 0 then st.fixed else st.per_kw * kw end;
    if st.fixed <= 0 and st.cap > 0 then s := least(s, st.cap); end if;
  end if;
  c := round(c); s := round(s);
  return jsonb_build_object('ok', true, 'sys', sy, 'kw', kw, 'central', c, 'state', s, 'total', c + s,
    'state_name', coalesce(st.state, ''), 'state_known', st.state_u is not null, 'state_active', coalesce(st.active, false) and s > 0,
    'special', sp, 'hybrid_note', sy = 'hy', 'state_note', case when s > 0 then coalesce(st.note, '') else '' end,
    'unverified', s > 0 and not coalesce(st.verified, false), 'note', cfg.note);
end $$;
grant execute on function public.sp_sub_calc(text, numeric, text, boolean) to anon, authenticated;

-- ---------- order ke time: server khud hisaab karke order me "subsidy" likh deta hai (sirf jankari) ----------
create or replace function public.sp_sub_order(p_pin text, p_items jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pin text := regexp_replace(coalesce(p_pin, ''), '\D', '', 'g'); stn text := ''; prods jsonb; i jsonb; pr jsonb; q numeric; r jsonb; lines jsonb := '[]'::jsonb; tc numeric := 0; ts numeric := 0;
begin
  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array' then return null; end if;
  select coalesce(state, '') into stn from public.sp_pin_master where pincode = pin;
  select coalesce(data -> 'products', '[]'::jsonb) into prods from public.sp_store where id = 'main';
  for i in select * from jsonb_array_elements(p_items) loop
    select x into pr from jsonb_array_elements(prods) x where x ->> 'id' = i ->> 'id' limit 1;
    if pr is null or jsonb_typeof(pr -> 'sub') <> 'object' then continue; end if;
    q := greatest(public.crm_num(i -> 'qty'), 1);
    r := public.sp_sub_calc(stn, public.crm_num(pr #> '{sub,kw}'), pr #>> '{sub,sys}', coalesce((pr #>> '{sub,res}') = 'true', false));
    if coalesce((r ->> 'ok')::boolean, false) then
      lines := lines || jsonb_build_object('id', pr ->> 'id', 'name', left(coalesce(pr ->> 'title', ''), 120), 'qty', q, 'kw', r -> 'kw', 'sys', r ->> 'sys',
                                           'central', (r ->> 'central')::numeric * q, 'state', (r ->> 'state')::numeric * q, 'total', (r ->> 'total')::numeric * q);
      tc := tc + (r ->> 'central')::numeric * q; ts := ts + (r ->> 'state')::numeric * q;
    end if;
  end loop;
  if jsonb_array_length(lines) = 0 then return null; end if;
  return jsonb_build_object('state', stn, 'pin', pin, 'central', tc, 'state_amt', ts, 'total', tc + ts, 'lines', lines, 'info_only', true);
end $$;
revoke all on function public.sp_sub_order(text, jsonb) from public, anon, authenticated;

do $do$ declare src text;
begin
  src := pg_get_functiondef('public.sp_place_order(jsonb)'::regprocedure);
  if position('sp_sub_order' in src) = 0 then
    src := replace(src, '  insert into public.sp_orders(data) values (o) returning id into new_id;',
      E'  o := o || coalesce((select jsonb_build_object(''subsidy'', x) from (select public.sp_sub_order(p_order ->> ''pincode'', p_order -> ''items'') x) q where x is not null), ''{}''::jsonb);\n  insert into public.sp_orders(data) values (o) returning id into new_id;');
    if position('sp_sub_order' in src) = 0 then raise exception 'U31: sp_place_order me jagah nahi mili'; end if;
    execute src;
  end if;
end $do$;

-- ============================ ADMIN (Store Admin: sp_check) ============================
create or replace function public.sp_sub_admin_get(p_pass text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.sp_check(p_pass);
  return jsonb_build_object(
    'cfg', (select to_jsonb(c) - 'id' - 'updated_at' from public.sp_sub_cfg c where id = 1),
    'states', coalesce((select jsonb_agg(to_jsonb(s) - 'updated_at' order by s.state) from public.sp_sub_state s), '[]'::jsonb));
end $$;

create or replace function public.sp_sub_admin_cfg_set(p_pass text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k text; v numeric;
begin
  perform public.sp_check(p_pass);
  foreach k in array array['r1', 'r2', 'r1_sp', 'r2_sp', 'cap_kw'] loop
    if p ? k then
      v := public.crm_num(p -> k);
      if v < 0 or v > 1000000 then raise exception 'Raqam galat hai: %', k; end if;
      execute format('update public.sp_sub_cfg set %I = $1, updated_at = now() where id = 1', k) using v;
    end if;
  end loop;
  if p ? 'enabled' then update public.sp_sub_cfg set enabled = coalesce((p ->> 'enabled')::boolean, true), updated_at = now() where id = 1; end if;
  if p ? 'note' then update public.sp_sub_cfg set note = left(coalesce(p ->> 'note', ''), 400), updated_at = now() where id = 1; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.sp_sub_admin_state_set(p_pass text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare su text := public.sp_sub_norm(p ->> 'state'); pk numeric := public.crm_num(p -> 'per_kw'); cp numeric := public.crm_num(p -> 'cap'); fx numeric := public.crm_num(p -> 'fixed');
begin
  perform public.sp_check(p_pass);
  if su = '' then raise exception 'Rajya ka naam likhein'; end if;
  if pk < 0 or pk > 1000000 or cp < 0 or cp > 10000000 or fx < 0 or fx > 10000000 then raise exception 'Raqam galat hai'; end if;
  insert into public.sp_sub_state(state_u, state, special, per_kw, cap, fixed, note, src, verified, active, updated_at)
  values (su, left(trim(coalesce(p ->> 'state', su)), 60), coalesce((p ->> 'special')::boolean, false), pk, cp, fx, left(coalesce(p ->> 'note', ''), 300), left(coalesce(p ->> 'src', ''), 200),
          coalesce((p ->> 'verified')::boolean, false), coalesce((p ->> 'active')::boolean, false), now())
  on conflict (state_u) do update set special = excluded.special, per_kw = excluded.per_kw, cap = excluded.cap, fixed = excluded.fixed, note = excluded.note, src = excluded.src,
        verified = excluded.verified, active = excluded.active, updated_at = now();
  return jsonb_build_object('ok', true);
end $$;

do $$ begin
  revoke all on function public.sp_sub_admin_get(text), public.sp_sub_admin_cfg_set(text, jsonb), public.sp_sub_admin_state_set(text, jsonb) from public;
  grant execute on function public.sp_sub_admin_get(text), public.sp_sub_admin_cfg_set(text, jsonb), public.sp_sub_admin_state_set(text, jsonb) to anon, authenticated;
end $$;

-- ============================ CUSTOMER: pin dalte hi subsidy (sp_pin_check me "sub" jud jata hai) ============================
-- Jin products me "sub" (kW + System type + Residential) bhara hai unki subsidy us pin ke rajya ke hisaab se. Pin dene se pehle kuch nahi dikhta.
create or replace function public.sp_sub_ids(p_state text, p_ids jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ids text[]; prods jsonb; out jsonb := '{}'::jsonb; x jsonb; r jsonb;
begin
  if jsonb_typeof(coalesce(p_ids, '[]'::jsonb)) <> 'array' then return out; end if;
  select coalesce(array_agg(v), '{}') into ids from jsonb_array_elements_text(p_ids) v;
  select coalesce(data -> 'products', '[]'::jsonb) into prods from public.sp_store where id = 'main';
  for x in select e from jsonb_array_elements(prods) e where (e ->> 'id') = any (ids) and jsonb_typeof(e -> 'sub') = 'object' loop
    r := public.sp_sub_calc(p_state, public.crm_num(x #> '{sub,kw}'), x #>> '{sub,sys}', coalesce((x #>> '{sub,res}') = 'true', false));
    if coalesce((r ->> 'ok')::boolean, false) then
      out := out || jsonb_build_object(x ->> 'id', jsonb_build_object('kw', r -> 'kw', 'sys', r ->> 'sys', 'central', r -> 'central', 'state', r -> 'state', 'total', r -> 'total',
              'state_name', r ->> 'state_name', 'hy', r -> 'hybrid_note', 'note', r ->> 'state_note', 'unv', r -> 'unverified'));
    end if;
  end loop;
  return out;
end $$;
revoke all on function public.sp_sub_ids(text, jsonb) from public, anon, authenticated;

do $do$ begin
  if to_regprocedure('public.sp_pin_check_core(text,jsonb)') is null then
    alter function public.sp_pin_check(text, jsonb) rename to sp_pin_check_core;
  end if;
end $do$;
revoke all on function public.sp_pin_check_core(text, jsonb) from public, anon, authenticated;

create or replace function public.sp_pin_check(p_pin text, p_ids jsonb default '[]'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb := public.sp_pin_check_core(p_pin, p_ids);
begin
  if coalesce((r ->> 'valid')::boolean, false) is not true then return r; end if;
  return r || jsonb_build_object('sub', public.sp_sub_ids(r ->> 'state', p_ids));
end $$;
grant execute on function public.sp_pin_check(text, jsonb) to anon, authenticated;

-- ---------- customer ka order page: order me likhi hui subsidy (jankari) bhi dikhe ----------
do $do$ declare src text;
begin
  src := pg_get_functiondef('public.crm_consumer_order(jsonb)'::regprocedure);
  if position('''subsidy''' in src) = 0 then
    src := replace(src, '''install'', coalesce(o.data -> ''install'', ''[]''::jsonb));', '''install'', coalesce(o.data -> ''install'', ''[]''::jsonb), ''subsidy'', o.data -> ''subsidy'');');
    if position('''subsidy''' in src) = 0 then raise exception 'U31: crm_consumer_order me jagah nahi mili'; end if;
    execute src;
  end if;
end $do$;

-- ===== U32 (Round 62): customer ke Documents me sab kuch ek jagah — rasid (receipt), customer ki apni upload, kya dikhana hai (Settings) + bill me "Aapko kya milega" data =====
-- Dobara chalane se koi nuksan nahi. Purane documents / bill waise hi rehte hain. Naya table nahi — sab purane crm_records / crm_files me.

-- 0) Settings: customer ko kaunse documents dikhein  (Settings > Company > hub.docs; khali = sab dikhein)
create or replace function public.crm__hubdocs() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select data #> '{hub,docs}' from public.crm_settings where id = 1), '{}'::jsonb) $$;
revoke all on function public.crm__hubdocs() from public, anon, authenticated;

-- 1) Customer ke print (quotation / bill) me subsidy + faayde + item ki category chali jaye (sirf safe fields)
do $u$ declare src text; fn text;
begin
  foreach fn in array array['public.crm_consumer_plant_doc(jsonb)', 'public.crm_consumer_bill_doc(jsonb)'] loop
    src := pg_get_functiondef(fn::regprocedure);
    if position('benefits' in src) = 0 then
      src := replace(src, $a$'hsn', l ->> 'hsn'))$a$, $b$'hsn', l ->> 'hsn', 'kind', l ->> 'kind', 'category', l ->> 'category', 'subcategory', l ->> 'subcategory', 'kw', l ->> 'kw', 'sys', l ->> 'sys'))$b$);
      src := replace(src, $a$'notes', src.data ->> 'notes'$a$, $b$'notes', src.data ->> 'notes', 'ctype', src.data ->> 'ctype', 'kw', src.data ->> 'kw', 'sys', src.data ->> 'sys', 'subsidy', src.data -> 'subsidy', 'benefits', src.data -> 'benefits', 'no_ben', src.data -> 'no_ben', 'hub', (select data -> 'hub' from public.crm_settings where id = 1)$b$);
      if position('benefits' in src) = 0 then raise exception 'U32: % me jagah nahi mili', fn; end if;
      execute src;
    end if;
  end loop;
end $u$;

-- 2) Online order ka bill/quotation: item ki category, project ka System type, aur order ki subsidy jankari bhi saath
do $u$ declare src text;
begin
  src := pg_get_functiondef('public.crm__order_job(bigint,bigint)'::regprocedure);
  if position('subsidy' in src) = 0 then
    src := replace(src, $a$jsonb_build_object('kind', 'product', 'item_id', c.id,$a$, $b$jsonb_build_object('kind', 'product', 'category', c.data ->> 'category', 'subcategory', c.data ->> 'subcategory', 'item_id', c.id,$b$);
    src := replace(src, $a$'kw', nullif(c.data ->> 'kw', ''), 'proj_items', c.data -> 'proj_items'));$a$, $b$'kw', nullif(c.data ->> 'kw', ''), 'sys', nullif(c.data ->> 'sys', ''), 'proj_items', c.data -> 'proj_items'));$b$);
    src := replace(src, $a$'kw', case when proj.id is not null then nullif(proj.data ->> 'kw', '') end,$a$, $b$'kw', case when proj.id is not null then nullif(proj.data ->> 'kw', '') end, 'sys', case when proj.id is not null then nullif(proj.data ->> 'sys', '') end,
         'subsidy', case when ct = 'Residential' and public.crm_num(o.data #> '{subsidy,total}') > 0 then jsonb_build_object('central', o.data #> '{subsidy,central}', 'state', o.data #> '{subsidy,state_amt}', 'total', o.data #> '{subsidy,total}', 'state_name', o.data #>> '{subsidy,state}', 'kw', nullif(proj.data ->> 'kw', ''), 'sys', coalesce(nullif(proj.data ->> 'sys', ''), 'on')) end,$b$);
    if position('subsidy' in src) = 0 then raise exception 'U32: crm__order_job me jagah nahi mili'; end if;
    execute src;
  end if;
end $u$;

-- 3) Hub: rasid list + "kya dikhana hai" + faayde ke text overrides
do $u$ declare src text;
begin
  src := pg_get_functiondef('public.crm_consumer_hub(jsonb)'::regprocedure);
  if position('docs_cfg' in src) = 0 then
    src := replace(src, $a$cats jsonb := '{}'::jsonb; st jsonb; co jsonb;$a$, $b$cats jsonb := '{}'::jsonb; st jsonb; co jsonb; rc jsonb := '[]'::jsonb;$b$);
    src := replace(src, $a$  select data into st from public.crm_settings where id = 1;$a$, $b$  select data into st from public.crm_settings where id = 1;
  select coalesce(jsonb_agg(z.j order by z.pid desc), '[]'::jsonb) into rc from (
    select py.id as pid, jsonb_build_object('id', py.id, 'ref', py.ref, 'date', coalesce(nullif(py.data ->> 'date', ''), py.due_at::text), 'amount', py.amount, 'mode', py.data ->> 'mode', 'bill', i.ref, 'quote_id', nullif(i.data ->> 'quote_id', '')::bigint) as j
      from public.crm_records py join public.crm_records i on i.id = nullif(py.data ->> 'invoice_id', '')::bigint and i.kind = 'invoice' and i.deleted_at is null and i.party_id = pt.id
     where py.kind = 'payment' and py.deleted_at is null and pt.id is not null order by py.id desc limit 100) z;$b$);
    src := replace(src, $a$'gen', coalesce(nullif(st -> 'hub' ->> 'gen', '')::numeric, 4))$a$, $b$'gen', coalesce(nullif(st -> 'hub' ->> 'gen', '')::numeric, 4), 'ben', coalesce(st -> 'hub' -> 'ben', '{}'::jsonb))$b$);
    src := replace(src, $a$return prof || jsonb_build_object('orders', orders,$a$, $b$return prof || jsonb_build_object('receipts', case when coalesce(st #>> '{hub,docs,receipt}', '1') = '0' then '[]'::jsonb else rc end, 'docs_cfg', coalesce(st #> '{hub,docs}', '{}'::jsonb), 'orders', orders,$b$);
    if position('docs_cfg' in src) = 0 or position('rc jsonb' in src) = 0 then raise exception 'U32: crm_consumer_hub me jagah nahi mili'; end if;
    execute src;
  end if;
end $u$;

-- 4) Staff ki upload ki file customer ko tabhi jaaye jab Settings me wo category / "files" band na ho (customer ki apni file hamesha)
do $u$ declare src text;
begin
  src := pg_get_functiondef('public.crm_consumer_file(jsonb)'::regprocedure);
  if position('crm__hubdocs' in src) = 0 then
    src := replace(src, $a$  select * into f from public.crm_files where rec_id = d.id limit 1;$a$, $b$  if coalesce((d.data ->> 'by_customer')::boolean, false) = false and (coalesce(public.crm__hubdocs() ->> 'files', '1') = '0'
     or (d.data ->> 'cat') in (select jsonb_array_elements_text(case when jsonb_typeof(public.crm__hubdocs() -> 'hide_cats') = 'array' then public.crm__hubdocs() -> 'hide_cats' else '[]'::jsonb end))) then raise exception 'File nahi mili'; end if;
  select * into f from public.crm_files where rec_id = d.id limit 1;$b$);
    if position('crm__hubdocs' in src) = 0 then raise exception 'U32: crm_consumer_file me jagah nahi mili'; end if;
    execute src;
  end if;
end $u$;

-- 5) Rasid (payment receipt) — customer ka apna, sirf safe fields
create or replace function public.crm_consumer_receipt(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); pt public.crm_records := public.crm__cust_party(u); py public.crm_records; i public.crm_records; co jsonb;
begin
  if coalesce(public.crm__hubdocs() ->> 'receipt', '1') = '0' then raise exception 'Rasid nahi mili'; end if;
  select * into py from public.crm_records where id = nullif(p ->> 'id', '')::bigint and kind = 'payment' and deleted_at is null;
  if py.id is null or pt.id is null then raise exception 'Rasid nahi mili'; end if;
  select * into i from public.crm_records where id = nullif(py.data ->> 'invoice_id', '')::bigint and kind = 'invoice' and deleted_at is null and party_id = pt.id;
  if i.id is null then raise exception 'Rasid nahi mili'; end if;
  select data -> 'company' into co from public.crm_settings where id = 1;
  return jsonb_build_object('kind', 'receipt', 'ref', py.ref, 'date', coalesce(nullif(py.data ->> 'date', ''), py.due_at::text), 'amount', py.amount, 'mode', py.data ->> 'mode', 'bill', i.ref, 'bill_total', i.amount,
    'bill_paid', i.data -> 'paid', 'bill_balance', i.data -> 'balance', 'title', i.data ->> 'qtitle',
    'customer', jsonb_build_object('name', pt.title, 'mobile', pt.mobile, 'address', pt.data ->> 'address', 'city', pt.data ->> 'city'),
    'company', jsonb_build_object('name', co ->> 'name', 'legal', co ->> 'legal', 'gstin', co ->> 'gstin', 'phone', co ->> 'phone', 'address', co ->> 'address'));
end $$;

-- 6) Customer apni file khud bhejta hai (ID, bijli bill, chhat ki photo, payment screenshot...) — seedha usi kaam ke Documents me; staff ko step 14 me apne aap dikhti hai
create or replace function public.crm_consumer_doc_upload(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); q public.crm_records; r public.crm_records; b bytea; nm text := regexp_replace(left(trim(coalesce(p ->> 'name', 'file')), 120), '[<>"''\\/]', '', 'g'); mm text := lower(coalesce(p ->> 'mime', ''));
        cc text := coalesce(nullif(trim(p ->> 'ccat'), ''), 'Other'); n int; hd bytea;
begin
  if coalesce(public.crm__hubdocs() ->> 'upload', '1') = '0' then raise exception 'Abhi file bhejna band hai — Sunpowers team se sampark karein'; end if;
  select q2.* into q from public.crm_records q2 join public.crm_consumer_plants cp on cp.quote_id = q2.id and cp.user_id = u.id where q2.id = nullif(p ->> 'quote_id', '')::bigint;
  if q.id is null or not public.crm_plant_owned(u, q) then raise exception 'Kaam nahi mila'; end if;
  if cc not in ('ID proof', 'Bijli bill', 'Chhat ki photo', 'Payment screenshot', 'Other') then cc := 'Other'; end if;
  if nm = '' then nm := 'file'; end if;
  if mm not in ('image/jpeg', 'image/png', 'image/webp', 'application/pdf') then raise exception 'Sirf photo (JPG / PNG) ya PDF bhejein'; end if;
  begin b := decode(coalesce(p ->> 'b64', ''), 'base64'); exception when others then raise exception 'File padh nahi paye'; end;
  if octet_length(b) = 0 then raise exception 'File khaali hai'; end if;
  if octet_length(b) > 3 * 1024 * 1024 then raise exception 'File 3 MB se badi hai — chhoti karke bhejein'; end if;
  hd := substring(b from 1 for 4);
  if not ((mm = 'image/jpeg' and substring(hd from 1 for 2) = '\xffd8'::bytea) or (mm = 'image/png' and hd = '\x89504e47'::bytea) or (mm = 'application/pdf' and hd = '\x25504446'::bytea) or (mm = 'image/webp' and hd = '\x52494646'::bytea)) then raise exception 'File ka type sahi nahi hai'; end if;
  select count(*) into n from public.crm_records where kind = 'doc' and deleted_at is null and (data ->> 'shared_quote') = q.id::text and coalesce((data ->> 'by_customer')::boolean, false);
  if n >= 30 then raise exception 'Is kaam me 30 file ho chuki hain — pehle purani hata dein'; end if;
  insert into public.crm_records(kind, title, status, owner_id, party_id, data, search, created_by)
  values ('doc', nm, 'ok', q.owner_id, q.party_id,
    jsonb_build_object('mime', mm, 'size', octet_length(b), 'note', left(trim(coalesce(p ->> 'note', '')), 300), 'cat', 'Customer ne bheja', 'ccat', cc, 'attach_kind', 'party', 'attach_id', q.party_id::text,
      'shared_quote', q.id, 'shared_ref', q.ref, 'shared_at', public.crm_iso_now(), 'shared_by', coalesce(u.name, 'Customer'), 'by_customer', true, 'cdoc', true),
    lower(nm || ' ' || coalesce(q.ref, '')), q.owner_id) returning * into r;
  insert into public.crm_files(rec_id, mime, size, data) values (r.id, mm, octet_length(b), b);
  return jsonb_build_object('ok', true, 'id', r.id);
end $$;

create or replace function public.crm_consumer_doc_delete(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); d public.crm_records; q public.crm_records;
begin
  select * into d from public.crm_records where id = nullif(p ->> 'id', '')::bigint and kind = 'doc' and deleted_at is null and coalesce((data ->> 'by_customer')::boolean, false);
  if d.id is null then raise exception 'File nahi mili'; end if;
  select q2.* into q from public.crm_records q2 join public.crm_consumer_plants cp on cp.quote_id = q2.id and cp.user_id = u.id where q2.id = (d.data ->> 'shared_quote')::bigint;
  if q.id is null or not public.crm_plant_owned(u, q) then raise exception 'File nahi mili'; end if;
  update public.crm_records set deleted_at = now() where id = d.id;
  delete from public.crm_files where rec_id = d.id;
  return jsonb_build_object('ok', true);
end $$;

grant execute on function public.crm_consumer_receipt(jsonb), public.crm_consumer_doc_upload(jsonb), public.crm_consumer_doc_delete(jsonb) to anon, authenticated;
notify pgrst, 'reload schema';

-- ROUND 63 (U33) — ek item ek baar: Inventory se online (naam, brand, model, warranty, baatein, specification) apne-aap; purani double jagahen saaf;
--                  online order: payment hote hi quotation se bill apne-aap. Dobara chalana safe hai.

-- 0) Supabase "DELETE ke liye WHERE chahiye" (pincode master) — pehle wala FIX-PIN-DELETE bhi yahin shamil
do $fix$ declare fn text; src text;
begin
  foreach fn in array array['public.sp_pin_master_load(text,jsonb,boolean)', 'public.sp_pin_master_clear(text)', 'public.sp_pin_rules_delete(text,jsonb)'] loop
    begin src := pg_get_functiondef(fn::regprocedure); exception when undefined_function then continue; end;
    if src ~ 'delete from public\.sp_pin_(master|rules);' then
      src := regexp_replace(src, 'delete from public\.(sp_pin_master|sp_pin_rules);', 'delete from public.\1 where true;', 'g');
      execute src;
    end if;
  end loop;
end $fix$;

-- 1) Specification padhne ke helper (CRM ke C.specPairs / C.specLine jaisa hi)
create or replace function public.crm__spec_pairs(sp jsonb) returns jsonb language plpgsql immutable as $f$
declare res jsonb := '[]'::jsonb; k text; i int := 0; n int := 0; seen text[] := '{}'; v text;
begin
  if sp is null or jsonb_typeof(sp) <> 'object' then return res; end if;
  begin n := coalesce((sp ->> '_n')::int, 0); exception when others then n := 0; end;
  if jsonb_typeof(sp -> '_o') = 'array' then
    for k in select jsonb_array_elements_text(sp -> '_o') loop
      if sp ? k and left(k, 1) <> '_' and not (k = any (seen)) then
        v := btrim(coalesce(sp ->> k, ''));
        if v <> '' then res := res || jsonb_build_array(jsonb_build_array(k, v, i < n)); end if;
        seen := seen || k; i := i + 1;
      end if;
    end loop;
  end if;
  for k in select x from jsonb_object_keys(sp) x order by x loop
    if left(k, 1) <> '_' and not (k = any (seen)) and k not in ('Product warranty (yrs)', 'Warranty (yrs)', 'Warranty') then
      v := btrim(coalesce(sp ->> k, ''));
      if v <> '' then res := res || jsonb_build_array(jsonb_build_array(k, v, false)); end if;
    end if;
  end loop;
  return res;
end $f$;

create or replace function public.crm__spec_val(k text, v text) returns text language plpgsql immutable as $f$
declare u text;
begin
  v := btrim(coalesce(v, '')); u := substring(k from '\(([^)]+)\)\s*$');
  if u is not null and v ~ '^[0-9.,[:space:]x×*]+$' then return case when u = '%' then v || '%' else v || ' ' || u end; end if;
  if u is null and v ~ '^[0-9.,]+$' then return regexp_replace(k, '\s*\([^)]*\)\s*$', '') || ': ' || v; end if;
  return v;
end $f$;

create or replace function public.crm__warranty_text(w text) returns text language plpgsql immutable as $f$
begin
  w := btrim(coalesce(w, '')); if w = '' then return ''; end if;
  if w ~ '^[0-9.]+$' then w := w || ' yrs'; end if;
  return case when w ~* 'warrant' then w else w || ' warranty' end;
end $f$;

create or replace function public.crm__spec_line(d jsonb) returns text language plpgsql immutable as $f$
declare parts text[] := '{}'; p jsonb; c int := 0; w text;
begin
  if btrim(coalesce(d ->> 'brand', '')) <> '' then parts := parts || btrim(d ->> 'brand'); end if;
  if btrim(coalesce(d ->> 'mpn', '')) <> '' then parts := parts || btrim(d ->> 'mpn'); end if;
  for p in select * from jsonb_array_elements(public.crm__spec_pairs(d -> 'specs')) loop
    exit when c >= 3;
    if (p ->> 2)::boolean then parts := parts || public.crm__spec_val(p ->> 0, p ->> 1); c := c + 1; end if;
  end loop;
  w := public.crm__warranty_text(d ->> 'warranty'); if w <> '' then parts := parts || w; end if;
  return array_to_string(parts, ' · ');
end $f$;

-- 2) CRM item ke jo fields Online Store / website par apne-aap jaate hain (Store Admin me dobara nahi bharne)
create or replace function public.crm__store_desc(d jsonb) returns text language plpgsql immutable as $f$
declare b text := ''; l text; pl text := ''; x jsonb;
begin
  for l in select btrim(z) from unnest(string_to_array(coalesce(d ->> 'desc', ''), E'\n')) z loop
    if l <> '' then b := b || case when b = '' then '' else E'\n' end || '• ' || l; end if;
  end loop;
  if coalesce(d ->> 'type', 'product') = 'project' then
    if jsonb_typeof(d -> 'proj_items') = 'array' and jsonb_array_length(d -> 'proj_items') > 0 then
      for x in select * from jsonb_array_elements(d -> 'proj_items') loop
        pl := pl || case when pl = '' then '' else E'\n' end || '• ' || btrim(coalesce(nullif(x ->> 'title', '') || ' – ', '') || coalesce(x ->> 'name', '')) || case when coalesce(x ->> 'qty', '1') not in ('1', '1.0', '') then ' × ' || (x ->> 'qty') else '' end;
      end loop;
      b := case when b <> '' then b || E'\n\n' else '' end || 'इस पैकेज में शामिल:' || E'\n' || pl;
    end if;
    if btrim(coalesce(d ->> 'kw', '')) <> '' then b := 'सिस्टम साइज़: ' || btrim(d ->> 'kw') || ' kW' || case when b <> '' then E'\n\n' || b else '' end; end if;
  end if;
  return b;
end $f$;

create or replace function public.crm__store_fields(d jsonb, ttl text) returns jsonb language sql immutable as $f$
  select jsonb_build_object(
    'title', coalesce(nullif(btrim(d ->> 'name'), ''), ttl, ''), 'titleEn', coalesce(nullif(btrim(d ->> 'name'), ''), ttl, ''),
    'brand', btrim(coalesce(d ->> 'brand', '')), 'model', btrim(coalesce(d ->> 'mpn', '')), 'sku', btrim(coalesce(d ->> 'sku', '')),
    'unit', btrim(coalesce(d ->> 'unit', '')), 'weight', public.crm_num(d -> 'weight'),
    'warranty', public.crm__warranty_text(d ->> 'warranty'), 'desc', public.crm__store_desc(d),
    'specs', public.crm__spec_pairs(d -> 'specs'), 'tagline', btrim(coalesce(d #>> '{store,tagline}', '')), 'cat', btrim(coalesce(d ->> 'category', '')))
$f$;

-- store data me CRM se jude (published) products: daam + ye sab fields CRM ke hisab se (admin ne kuch bhi bheja ho)
create or replace function public.sp__apply_crm_prices(d jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb;
begin
  if d is null or jsonb_typeof(d -> 'products') <> 'array' then return d; end if;
  select jsonb_agg(case when m.item_id is null then e.e else e.e || jsonb_build_object('mrp', m.nmrp, 'offer', m.noffer, 'gst', m.gst, 'crm', m.item_id) || m.fields end order by e.ord) into out_
  from jsonb_array_elements(d -> 'products') with ordinality as e(e, ord)
  left join lateral (
    select c.id as item_id, public.crm_num(c.data -> 'gst') as gst,
      case when public.crm_num(c.data -> 'mrp') > public.crm_price_incl(c.data) then public.crm_num(c.data -> 'mrp') else public.crm_price_incl(c.data) end as nmrp,
      case when public.crm_num(c.data -> 'mrp') > public.crm_price_incl(c.data) then public.crm_price_incl(c.data) else 0 end as noffer,
      public.crm__store_fields(c.data, c.title) as fields
    from public.crm_records c where c.kind = 'item' and c.deleted_at is null and (c.data #>> '{store,store_id}') = (e.e ->> 'id') and (c.data #>> '{store,status}') = 'published' and public.crm_price_incl(c.data) > 0
    order by c.id limit 1) m on true;
  return jsonb_set(d, '{products}', coalesce(out_, '[]'::jsonb));
end $$;

-- CRM me inme se kuch bhi badle to store me turant (sirf jab kuch badla ho; stock ki ginti se store nahi chhedta)
create or replace function public.crm_item_price_push_trg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (NEW.data #>> '{store,status}') = 'published' and coalesce(NEW.data #>> '{store,store_id}', '') <> '' and NEW.deleted_at is null
     and (TG_OP = 'INSERT' or (public.crm__store_fields(OLD.data, OLD.title), OLD.data -> 'price', OLD.data -> 'gst', OLD.data -> 'mrp', OLD.data #> '{store,store_id}', OLD.data #> '{store,status}')
          is distinct from (public.crm__store_fields(NEW.data, NEW.title), NEW.data -> 'price', NEW.data -> 'gst', NEW.data -> 'mrp', NEW.data #> '{store,store_id}', NEW.data #> '{store,status}')) then
    update public.sp_store set updated_at = now() where id = 'main';
  end if;
  return null;
end $$;

-- store par live hote hi CRM ki purani (kabhi na dikhne wali) photo hat jaati hai — photo ab sirf Store Admin me
create or replace function public.crm_item_drop_photos() returns trigger language plpgsql as $$
begin
  if (NEW.data #>> '{store,status}') = 'published' and (NEW.data ? 'images' or NEW.data ? 'image_link') then NEW.data := NEW.data - 'images' - 'image_link'; end if;
  return NEW;
end $$;
drop trigger if exists crm_item_drop_photos on public.crm_records;
create trigger crm_item_drop_photos before insert or update on public.crm_records for each row when (NEW.kind = 'item') execute function public.crm_item_drop_photos();


-- 3) Purani double jagahen saaf: warranty ek hi (specification wali alag nahi), "More Info" -> Khaas baatein, Title / Image link / extra categories / store offer hat gaye;
--    specification ko category ke order me rakha (mukhya fields pehle). Kuch bhi delete nahi hota jo ab bhi kaam ka ho.
create or replace function public.crm__spec_order() returns jsonb language sql immutable as $f$ select $j${"PNL":{"all":["Wattage (Wp)","Cell technology","DCR / Non-DCR","Efficiency (%)","Dimensions (mm)","Weight (kg)","Performance warranty (yrs)","Bifacial","No. of cells","Vmp (V)","Imp (A)","Voc (V)","Isc (A)","Temp. coefficient (Pmax)","Certification","Made in"],"n":7},"INV":{"all":["Capacity (kW)","Phase","No. of MPPT","Max PV input (kWp)","Efficiency (%)","Communication / WiFi","MPPT voltage range (V)","Max DC voltage (V)","IP rating","Battery support","Cooling","Certification","Made in"],"n":6},"BAT":{"all":["Battery type","Voltage (V)","Capacity (Ah)","Cycle life","Depth of discharge (%)","Energy (kWh)","Dimensions (mm)","Weight (kg)","Terminal","Made in"],"n":5},"STR":{"all":["Material","Coating / thickness","Wind speed rating (km/h)","Panels supported","Tilt angle","Mounting type","Fasteners material","Standard"],"n":4},"ADB":{"all":["Rating (A)","Strings / Phase","IP rating","SPD","Enclosure","MCB / MCCB make","Fuse","Input / Output","Standard"],"n":4},"ERT":{"all":["Earthing type","Electrode material","Electrode size","Length (m)","Chemical / Backfill","LA type","Resistance (Ohm)","Standard"],"n":4},"LGT":{"all":["Wattage (W)","Lumens (lm)","Solar panel (W)","Battery","Autonomy (hrs)","Sensor / Mode","IP rating","Pole / Mounting","Body material"],"n":5},"CAM":{"all":["Resolution (MP)","Connectivity","Solar panel (W)","Night vision","Storage","Battery (mAh)","Field of view","IP rating","App"],"n":5},"HAP":{"all":["Capacity (VA/kVA)","System voltage (V)","Wave form","Battery (Ah)","Charging current (A)","Display","Solar charge controller","Trolley included"],"n":4},"BOS":{"all":["Size / Rating","Material","Length / Qty per pack","Standard / Certification","Colour","Application"],"n":4},"MNT":{"all":["Plan duration","Visits per year","Plant size covered (kW)","Includes","Response time","Report / Audit","Terms"],"n":4},"_":{"all":["Size / Rating","Material","Length / Qty per pack","Colour","Standard / Certification","Application"],"n":4}}$j$::jsonb $f$;
create or replace function public.crm__cat_code(n text) returns text language sql immutable as $f$ select coalesce(($j${"Solar Panel/Solar Modules":"PNL","Solar Inverter":"INV","Solar Batteries":"BAT","Solar Structure":"STR","Solar ACDB/DCDB":"ADB","Chemical Earthings & LA":"ERT","Solar Lights":"LGT","Solar Cameras":"CAM","Home Appliances":"HAP","Solar BOS Materials":"BOS","Solar Maintenance & Package":"MNT"}$j$::jsonb) ->> btrim(coalesce(n, '')), '_') $f$;

create or replace function public.crm__item_clean(d jsonb) returns jsonb language plpgsql stable as $f$
declare sp jsonb; k text; w text; ord jsonb; code text; lst jsonb; keys text[]; present text[] := '{}'; o text[] := '{}'; kn int := 0; m text; ds text;
begin
  if d is null then return d; end if;
  if coalesce(d ->> 'type', 'product') = 'product' then
    sp := d -> 'specs';
    if jsonb_typeof(sp) = 'object' then
      w := btrim(coalesce(d ->> 'warranty', ''));
      foreach k in array array['Product warranty (yrs)', 'Warranty (yrs)', 'Warranty'] loop
        if sp ? k then
          if w = '' and btrim(coalesce(sp ->> k, '')) <> '' then w := btrim(sp ->> k); if w ~ '^[0-9.]+$' then w := w || ' yrs'; end if; end if;
          sp := sp - k;
        end if;
      end loop;
      if w <> '' then d := d || jsonb_build_object('warranty', w); end if;
      if not (sp ? '_o') then
        ord := public.crm__spec_order(); code := public.crm__cat_code(d ->> 'category'); lst := coalesce(ord -> code -> 'all', ord -> '_' -> 'all'); kn := coalesce((ord -> code ->> 'n')::int, (ord -> '_' ->> 'n')::int, 0);
        for k in select jsonb_array_elements_text(lst) loop
          if sp ? k and btrim(coalesce(sp ->> k, '')) <> '' then o := o || k; end if;
        end loop;
        for k in select x from jsonb_object_keys(sp) x order by x loop
          if left(k, 1) <> '_' and not (k = any (o)) and btrim(coalesce(sp ->> k, '')) <> '' then o := o || k; end if;
        end loop;
        if array_length(o, 1) is not null then
          select count(*) into kn from unnest(o) z where z in (select jsonb_array_elements_text(lst) limit kn);
          sp := sp || jsonb_build_object('_o', to_jsonb(o), '_n', kn);
        end if;
      end if;
      d := jsonb_set(d, '{specs}', sp);
    end if;
  end if;
  m := btrim(coalesce(d ->> 'more', ''));
  if m <> '' and position(m in coalesce(d ->> 'desc', '')) = 0 then d := d || jsonb_build_object('desc', case when btrim(coalesce(d ->> 'desc', '')) = '' then m else rtrim(d ->> 'desc') || E'\n' || m end); end if;
  d := d - 'more' - 'title' - 'image_link' - 'categories';
  if d #> '{store,offer}' is not null then d := jsonb_set(d, '{store}', (d -> 'store') - 'offer'); end if;
  return d;
end $f$;

do $mig$ declare r record; nd jsonb; sd jsonb; sp record; pr jsonb; w numeric; tg text; dd text;
begin
  perform set_config('sp.order_job', '1', true);
  for r in select id, data from public.crm_records where kind = 'item' and deleted_at is null loop
    nd := public.crm__item_clean(r.data);
    if nd is distinct from r.data then update public.crm_records set data = nd where id = r.id; end if;
  end loop;
  -- Store Admin me jo weight / tagline / baatein pehle alag bhari thi, CRM me khali ho to wahin se le aao (CRM ab authority hai)
  select data into sd from public.sp_store where id = 'main';
  if sd is not null and jsonb_typeof(sd -> 'products') = 'array' then
    for r in select c.id, c.data from public.crm_records c where c.kind = 'item' and c.deleted_at is null and c.data #>> '{store,status}' = 'published' loop
      select e into pr from jsonb_array_elements(sd -> 'products') e where e ->> 'id' = r.data #>> '{store,store_id}' limit 1;
      if pr is null then continue; end if;
      nd := r.data;
      if public.crm_num(nd -> 'weight') <= 0 and public.crm_num(pr -> 'weight') > 0 then nd := nd || jsonb_build_object('weight', public.crm_num(pr -> 'weight')); end if;
      if btrim(coalesce(nd #>> '{store,tagline}', '')) = '' and btrim(coalesce(pr ->> 'tagline', '')) <> '' then nd := jsonb_set(nd, '{store}', coalesce(nd -> 'store', '{}'::jsonb) || jsonb_build_object('tagline', btrim(pr ->> 'tagline'))); end if;
      if coalesce(nd ->> 'type', 'product') = 'product' and btrim(coalesce(nd ->> 'desc', '')) = '' and btrim(coalesce(pr ->> 'desc', '')) <> '' then
        dd := regexp_replace(pr ->> 'desc', '(^|\n)\s*[•\-\*]\s*', E'\\1', 'g'); nd := nd || jsonb_build_object('desc', btrim(dd));
      end if;
      if nd is distinct from r.data then update public.crm_records set data = nd where id = r.id; end if;
    end loop;
  end if;
  perform set_config('sp.order_job', '', true);
end $mig$;

-- 4) Online order ka Kaam (quotation) ab har line par chhoti spec-line ke saath banta hai
do $u$ declare src text;
begin
  src := pg_get_functiondef('public.crm__order_job(bigint,bigint)'::regprocedure);
  if position('crm__spec_line' in src) = 0 then
    src := replace(src, $a$jsonb_build_object('kind', 'product', 'category', c.data ->> 'category',$a$, $b$jsonb_build_object('kind', 'product', 'spec', public.crm__spec_line(c.data), 'category', c.data ->> 'category',$b$);
    if position('crm__spec_line' in src) = 0 then raise exception 'U33: crm__order_job me jagah nahi mili'; end if;
    execute src;
  end if;
end $u$;