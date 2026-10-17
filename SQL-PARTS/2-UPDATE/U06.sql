-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 6 of 9
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U09). Safe to re-run.
-- ============================================================================

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