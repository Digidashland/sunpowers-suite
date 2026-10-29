-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 14 of 30
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U30). Safe to re-run.
-- ============================================================================

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