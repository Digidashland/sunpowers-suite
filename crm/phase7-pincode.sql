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
