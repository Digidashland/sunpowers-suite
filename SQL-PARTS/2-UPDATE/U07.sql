-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 7 of 9
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U09). Safe to re-run.
-- ============================================================================

-- ---- ROUND 13: changed core CRM functions (full redefinitions; safe to re-run) ----
CREATE OR REPLACE FUNCTION public.crm_save(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); k text := p ->> 'kind'; id_ bigint := nullif(p ->> 'id', '')::bigint;
        d jsonb := coalesce(p -> 'data', '{}'::jsonb); old public.crm_records; r public.crm_records; isnew boolean := id_ is null or id_ = 0;
        mob text; ttl text; st text := coalesce(p ->> 'status', ''); asg bigint := nullif(p ->> 'assigned_to', '')::bigint; pid bigint := nullif(p ->> 'party_id', '')::bigint;
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
  ttl := left(trim(coalesce(d ->> 'name', d ->> 'title', '')), 200);
  owner_ := case when isnew then (s).uid else old.owner_id end;
  if not isnew and pid is null and not (p ? 'party_id') then pid := old.party_id; end if;
  if not isnew and not (p ? 'assigned_to') then asg := old.assigned_to; end if;
  if not isnew and not (p ? 'due_at') then due := old.due_at; end if;

  -- ---------------- per kind rules
  if k = 'party' then
    perform public.crm_need(s, case when isnew then 'customers.create' else 'customers.edit' end);
    if ttl = '' then raise exception 'Customer ka naam likhein'; end if;
    if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein'; end if;
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
    if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Sahi 10 ank ka mobile number likhein'; end if;
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
    if pid is null then select id into pid from public.crm_records where kind = 'party' and mobile = mob and deleted_at is null limit 1; end if;
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

  srch := lower(concat_ws(' ', ttl, ref_, mob, d ->> 'city', d ->> 'company', d ->> 'gstin', d ->> 'note', d ->> 'type', d ->> 'brand', d ->> 'qtitle', d ->> 'category', d ->> 'subcategory', d ->> 'sku', d ->> 'mpn', d ->> 'source'));
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

-- One call = everything for the dashboards.  p_days: 1..365   (compared with the previous equal period)
create or replace function public.sp_admin_analytics(p_pass text, p_days int default 30) returns jsonb language plpgsql security definer set search_path = public as $$
declare d int := greatest(1, least(coalesce(p_days, 30), 365)); t0 timestamptz; t1 timestamptz := now(); tp timestamptz; r jsonb := '{}'::jsonb;
        ord_cnt int; enq_new int; ord_new int; ord_unpaid int;
begin
  perform public.sp_check(p_pass);
  delete from public.sp_events where ts < now() - interval '400 days';
  t0 := date_trunc('day', now() - ((d - 1) || ' days')::interval); tp := t0 - (d || ' days')::interval;

  -- per site totals for current and previous period
  r := r || jsonb_build_object('cur', (
    select coalesce(jsonb_object_agg(site, o), '{}'::jsonb) from (
      select s.site, jsonb_build_object(
        'visitors', (select count(distinct sid) from public.sp_events where site = s.site and kind = 'view' and ts >= t0 and sid <> ''),
        'views',    (select count(*) from public.sp_events where site = s.site and kind = 'view' and ts >= t0),
        'clicks',   (select count(*) from public.sp_events where site = s.site and kind = 'click' and ts >= t0),
        'carts',    (select count(*) from public.sp_events where site = s.site and kind = 'cart' and ts >= t0),
        'searches', (select count(*) from public.sp_events where site = s.site and kind = 'search' and ts >= t0),
        'shop_views', (select count(*) from public.sp_events where site = s.site and kind = 'view' and ts >= t0 and page like '%shop.html%'),
        'shop_visitors', (select count(distinct sid) from public.sp_events where site = s.site and kind = 'view' and ts >= t0 and page like '%shop.html%' and sid <> ''),
        'mobile',   (select count(distinct sid) from public.sp_events where site = s.site and kind = 'view' and ts >= t0 and dev = 'mobile'),
        'orders',   (select count(*) from public.sp_orders where created_at >= t0 and (case when s.site = 'website' then coalesce(data ->> 'src', '') in ('website','shop') else coalesce(data ->> 'src', '') not in ('website','shop') end)),
        'sales',    (select coalesce(sum(nullif(data ->> 'total', '')::numeric), 0) from public.sp_orders where created_at >= t0 and (case when s.site = 'website' then coalesce(data ->> 'src', '') in ('website','shop') else coalesce(data ->> 'src', '') not in ('website','shop') end)),
        'enquiries',(select count(*) from public.sp_enquiries where created_at >= t0 and (case when s.site = 'website' then coalesce(data ->> 'source', 'website') <> 'store' else coalesce(data ->> 'source', '') = 'store' end))
      ) o from (values ('website'), ('store')) s(site)) q));
  r := r || jsonb_build_object('prev', (
    select coalesce(jsonb_object_agg(site, o), '{}'::jsonb) from (
      select s.site, jsonb_build_object(
        'visitors', (select count(distinct sid) from public.sp_events where site = s.site and kind = 'view' and ts >= tp and ts < t0 and sid <> ''),
        'views',    (select count(*) from public.sp_events where site = s.site and kind = 'view' and ts >= tp and ts < t0),
        'orders',   (select count(*) from public.sp_orders where created_at >= tp and created_at < t0 and (case when s.site = 'website' then coalesce(data ->> 'src', '') in ('website','shop') else coalesce(data ->> 'src', '') not in ('website','shop') end)),
        'sales',    (select coalesce(sum(nullif(data ->> 'total', '')::numeric), 0) from public.sp_orders where created_at >= tp and created_at < t0 and (case when s.site = 'website' then coalesce(data ->> 'src', '') in ('website','shop') else coalesce(data ->> 'src', '') not in ('website','shop') end)),
        'enquiries',(select count(*) from public.sp_enquiries where created_at >= tp and created_at < t0 and (case when s.site = 'website' then coalesce(data ->> 'source', 'website') <> 'store' else coalesce(data ->> 'source', '') = 'store' end))
      ) o from (values ('website'), ('store')) s(site)) q));

  -- daily series (one row per day, both sites)
  r := r || jsonb_build_object('days', (
    select coalesce(jsonb_agg(row_to_json(x) order by x.d), '[]'::jsonb) from (
      select to_char(g.d, 'YYYY-MM-DD') as d,
        (select count(distinct sid) from public.sp_events e where e.site = 'website' and e.kind = 'view' and e.ts >= g.d and e.ts < g.d + interval '1 day' and e.sid <> '') as wv,
        (select count(distinct sid) from public.sp_events e where e.site = 'store' and e.kind = 'view' and e.ts >= g.d and e.ts < g.d + interval '1 day' and e.sid <> '') as sv,
        (select count(*) from public.sp_events e where e.site = 'website' and e.kind = 'view' and e.page like '%shop.html%' and e.ts >= g.d and e.ts < g.d + interval '1 day') as shv,
        (select count(*) from public.sp_orders o where o.created_at >= g.d and o.created_at < g.d + interval '1 day' and coalesce(o.data ->> 'src', '') in ('website','shop')) as wo,
        (select count(*) from public.sp_orders o where o.created_at >= g.d and o.created_at < g.d + interval '1 day' and coalesce(o.data ->> 'src', '') not in ('website','shop')) as so,
        (select coalesce(sum(nullif(o.data ->> 'total', '')::numeric), 0) from public.sp_orders o where o.created_at >= g.d and o.created_at < g.d + interval '1 day' and coalesce(o.data ->> 'src', '') in ('website','shop')) as wsale,
        (select coalesce(sum(nullif(o.data ->> 'total', '')::numeric), 0) from public.sp_orders o where o.created_at >= g.d and o.created_at < g.d + interval '1 day' and coalesce(o.data ->> 'src', '') not in ('website','shop')) as ssale
      from generate_series(t0, date_trunc('day', now()), interval '1 day') g(d)) x));

  -- hour of day (0..23) visitors, both sites (IST)
  r := r || jsonb_build_object('hours', (
    select coalesce(jsonb_agg(jsonb_build_object('h', h, 'w', w, 's', s) order by h), '[]'::jsonb) from (
      select g.h, (select count(*) from public.sp_events e where e.site = 'website' and e.kind = 'view' and e.ts >= t0 and extract(hour from e.ts at time zone 'Asia/Kolkata') = g.h) as w,
                  (select count(*) from public.sp_events e where e.site = 'store' and e.kind = 'view' and e.ts >= t0 and extract(hour from e.ts at time zone 'Asia/Kolkata') = g.h) as s
      from generate_series(0, 23) g(h)) z));

  -- top pages / top buttons / traffic sources (per site)
  r := r || jsonb_build_object('pages', (select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
      select site, page, count(*) as views, count(distinct sid) as visitors from public.sp_events where kind = 'view' and ts >= t0 group by site, page order by count(*) desc limit 40) x));
  r := r || jsonb_build_object('clicks', (select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
      select site, label, page, count(*) as n from public.sp_events where kind = 'click' and ts >= t0 and label <> '' group by site, label, page order by count(*) desc limit 40) x));
  r := r || jsonb_build_object('searches', (select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
      select site, lower(label) as label, count(*) as n from public.sp_events where kind = 'search' and ts >= t0 and label <> '' group by site, lower(label) order by count(*) desc limit 20) x));
  r := r || jsonb_build_object('sources', (select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
      select site, case when src = '' then 'direct' else src end as src, count(distinct sid) as visitors from public.sp_events where kind = 'view' and ts >= t0 group by site, case when src = '' then 'direct' else src end order by count(distinct sid) desc limit 30) x));

  -- funnel (distinct visitors per step)
  r := r || jsonb_build_object('funnel', (select coalesce(jsonb_object_agg(site, f), '{}'::jsonb) from (
      select s.site, jsonb_build_object(
        'visit',    (select count(distinct sid) from public.sp_events where site = s.site and kind = 'view' and ts >= t0 and sid <> ''),
        'cart',     (select count(distinct sid) from public.sp_events where site = s.site and kind = 'cart' and ts >= t0 and sid <> ''),
        'checkout', (select count(distinct sid) from public.sp_events where site = s.site and kind in ('checkout','order') and ts >= t0 and sid <> ''),
        'order',    (select count(*) from public.sp_orders where created_at >= t0 and (case when s.site = 'website' then coalesce(data ->> 'src', '') in ('website','shop') else coalesce(data ->> 'src', '') not in ('website','shop') end))
      ) f from (values ('website'), ('store')) s(site)) q));

  -- top products sold (from orders in the period)
  r := r || jsonb_build_object('top_products', (select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
      select coalesce(i ->> 'title', i ->> 'titleEn', '?') as title, sum(coalesce(nullif(i ->> 'qty', '')::numeric, 1)) as qty, sum(coalesce(nullif(i ->> 'amount', '')::numeric, 0)) as amount,
             sum(case when coalesce(o.data ->> 'src', '') in ('website','shop') then coalesce(nullif(i ->> 'qty', '')::numeric, 1) else 0 end) as web_qty
      from public.sp_orders o, jsonb_array_elements(case when jsonb_typeof(o.data -> 'items') = 'array' then o.data -> 'items' else '[]'::jsonb end) i
      where o.created_at >= t0 group by 1 order by 3 desc limit 10) x));

  -- recent orders
  r := r || jsonb_build_object('recent_orders', (select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
      select id, to_char(created_at at time zone 'Asia/Kolkata', 'DD Mon HH24:MI') as at, status, data ->> 'order_no' as order_no, data ->> 'name' as name, nullif(data ->> 'total', '')::numeric as total,
             case when coalesce(data ->> 'src', '') in ('website','shop') then 'website' else 'store' end as site
      from public.sp_orders order by id desc limit 8) x));

  -- alerts
  select count(*) into ord_new from public.sp_orders where status = 'new';
  select count(*) into ord_unpaid from public.sp_orders where status = 'new' and created_at < now() - interval '24 hours';
  select count(*) into enq_new from public.sp_enquiries where status = 'new';
  r := r || jsonb_build_object('alerts', jsonb_build_object('orders_new', ord_new, 'orders_old', ord_unpaid, 'enquiries_new', enq_new,
        'enquiries_old', (select count(*) from public.sp_enquiries where status = 'new' and created_at < now() - interval '24 hours'),
        'events_total', (select count(*) from public.sp_events)));
  return r || jsonb_build_object('range', jsonb_build_object('days', d, 'from', to_char(t0, 'YYYY-MM-DD'), 'to', to_char(now(), 'YYYY-MM-DD')));
end $$;

-- ---------- Look (colour theme per panel) + Greeting banner : one public row, edited only by Admin ----------
-- Shape: { theme: { website:{preset,...}, store:{...}, admin:{...}, crm:{...} },
--          greet: { on, text, icon, anim, from, to, id, targets:{ website, shop, store, admin, crm:{all, users:{<id>:true}} } } }
create or replace function public.sp_get_cfg() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select data from public.sp_store where id = 'cfg'), '{}'::jsonb);
$$;

create or replace function public.sp_save_cfg(p_pass text, p_data jsonb) returns timestamptz language plpgsql security definer set search_path = public, extensions as $$
declare t timestamptz := now();
begin
  perform public.sp_check(p_pass);
  if p_data is null or jsonb_typeof(p_data) <> 'object' then raise exception 'Invalid data'; end if;
  if length(p_data::text) > 60000 then raise exception 'Settings too large'; end if;
  insert into public.sp_store(id, data, updated_at) values ('cfg', p_data, t)
  on conflict (id) do update set data = excluded.data, updated_at = excluded.updated_at;
  return t;
end $$;

-- Same save, for an Admin-role user logged into the CRM (token based)
create or replace function public.crm_cfg_save(p jsonb) returns timestamptz language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); t timestamptz := now(); d jsonb := p -> 'data';
begin
  if not public.crm_can(s, 'users.manage') then raise exception 'Not allowed'; end if;
  if d is null or jsonb_typeof(d) <> 'object' then raise exception 'Invalid data'; end if;
  if length(d::text) > 60000 then raise exception 'Settings too large'; end if;
  insert into public.sp_store(id, data, updated_at) values ('cfg', d, t)
  on conflict (id) do update set data = excluded.data, updated_at = excluded.updated_at;
  return t;
end $$;

do $$ begin
  revoke all on function public.sp_track(jsonb), public.sp_admin_analytics(text, int), public.sp_get_cfg(), public.sp_save_cfg(text, jsonb), public.crm_cfg_save(jsonb) from public;
  grant execute on function public.sp_track(jsonb), public.sp_admin_analytics(text, int), public.sp_get_cfg(), public.sp_save_cfg(text, jsonb), public.crm_cfg_save(jsonb) to anon, authenticated;
exception when undefined_object then null; end $$;


-- ============================================================================
-- ROUND 16 (database) — 13-step workflow, Projects, lead/quotation rules, pending bill, Documents sharing, customer "My Plant". Safe to re-run.
-- ============================================================================
-- =====================================================================
-- Round 16 — customer workflow, Projects, lead / quotation rules, pending-bill flags, Plant ID for customers
-- Safe to run more than once (create or replace / if not exists).
-- =====================================================================

-- ---------- 13-step customer workflow (names) -------------------------------------------------
create or replace function public.crm_wf_names() returns text[] language sql immutable as $$
  select array['Customer Connect','Starting Conversation','Quotation','Site Visit','Blueprint','Confirmation','Apply Process','Hand Over Technician','Start Installation','Commissioning','Net Metering','Finish Work','Subsidy Redeem'] $$;

create or replace function public.crm_ctypes() returns text[] language sql immutable as $$ select array['Residential','Commercial','Industrial','VFD','Items only'] $$;

create or replace function public.crm_iso_now() returns text language sql stable as $$
  select to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS"+05:30"') $$;

-- sets step n inside data.wf when it is not there yet
create or replace function public.crm_wf_mark(d jsonb, n int, by text, at_ text default null, auto boolean default true) returns jsonb language sql stable as $$
  select case when coalesce(d -> 'wf', '{}'::jsonb) ? n::text then d
    else d || jsonb_build_object('wf', coalesce(d -> 'wf', '{}'::jsonb) || jsonb_build_object(n::text, jsonb_build_object('at', coalesce(at_, public.crm_iso_now()), 'by', coalesce(by, ''), 'auto', auto))) end $$;