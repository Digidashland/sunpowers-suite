-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 4 of 9
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U09). Safe to re-run.
-- ============================================================================

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