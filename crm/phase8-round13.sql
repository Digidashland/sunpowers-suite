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
