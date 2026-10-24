-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 6 of 12
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U12). Safe to re-run.
-- ============================================================================

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
        mob text; em text; ttl text; st text := coalesce(p ->> 'status', ''); asg bigint := nullif(p ->> 'assigned_to', '')::bigint; pid bigint := nullif(p ->> 'party_id', '')::bigint;
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
  em := lower(left(trim(coalesce(d ->> 'email', '')), 160));
  ttl := left(trim(coalesce(d ->> 'name', d ->> 'title', '')), 200);
  owner_ := case when isnew then (s).uid else old.owner_id end;
  if not isnew and pid is null and not (p ? 'party_id') then pid := old.party_id; end if;
  if not isnew and not (p ? 'assigned_to') then asg := old.assigned_to; end if;
  if not isnew and not (p ? 'due_at') then due := old.due_at; end if;

  -- ---------------- per kind rules
  if k = 'party' then
    perform public.crm_need(s, case when isnew then 'customers.create' else 'customers.edit' end);
    if ttl = '' then raise exception 'Customer ka naam likhein'; end if;
    if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein (mobile zaroori hai)'; end if;
    if em <> '' and em !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'Sahi email likhein (ya khali chhodein)'; end if;
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
    if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein (mobile zaroori hai)'; end if;
    if em <> '' and em !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'Sahi email likhein (ya khali chhodein)'; end if;
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
    if pid is null and mob <> '' then select id into pid from public.crm_records where kind = 'party' and mobile = mob and deleted_at is null limit 1; end if;
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

  srch := lower(concat_ws(' ', ttl, ref_, mob, em, d ->> 'city', d ->> 'company', d ->> 'gstin', d ->> 'note', d ->> 'type', d ->> 'brand', d ->> 'qtitle', d ->> 'category', d ->> 'subcategory', d ->> 'sku', d ->> 'mpn', d ->> 'source'));
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