-- ============================================================================
-- SUNPOWERS — NAYA PROJECT SETUP — part 3 of 18
-- Naya (khali) Supabase project: pehle F01..F06, phir 2-UPDATE ke U01..U12.
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (F01 -> F06, phir U01 -> U12). Safe to re-run.
-- ============================================================================

-- ---------------------------------------------------------------- records
create or replace function public.crm_list(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
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
end $$;

create or replace function public.crm_get(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records;
begin
  perform public.crm_quote_expire_daily();
  select * into r from public.crm_records where id = (p ->> 'id')::bigint;
  if not public.crm_vis(s, r) then raise exception 'Record nahi mila'; end if;
  return public.crm_row(s, r);
end $$;

create or replace function public.crm_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
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
end $$;

-- quick status change (lead stage, reminder done, plant verify, order etc.)
create or replace function public.crm_status(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
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
end $$;

create or replace function public.crm_convert(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
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
end $$;

create or replace function public.crm_delete(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records; why text := left(trim(coalesce(p ->> 'reason', '')), 300); need text; own boolean;
begin
  select * into r from public.crm_records where id = (p ->> 'id')::bigint;
  if not public.crm_vis(s, r) then raise exception 'Record nahi mila'; end if;
  own := r.owner_id = (s).uid;
  need := case r.kind when 'party' then 'customers.delete' when 'item' then 'items.delete' when 'quote' then 'quotes.delete' when 'invoice' then 'invoices.delete'
    when 'payment' then 'payments.delete' when 'purchase' then 'purchase.manage' when 'lead' then 'leads.delete' when 'earning' then 'earnings.manage'
    when 'folder' then 'docs.folders' when 'doc' then 'docs.delete' when 'notice' then 'settings.manage' else null end;
  if r.kind = 'plant' then
    if not (public.crm_can(s, 'plants.delete') or (own and r.status = 'pending')) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  elsif r.kind in ('reminder', 'note') then
    if not (own or public.crm_can(s, 'reminders.assign')) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  elsif r.kind = 'doc' then
    if not (own or public.crm_can(s, 'docs.delete')) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  elsif r.kind = 'lead' then
    if not (public.crm_can(s, 'leads.delete') or (own and r.owner_id <> 0)) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  elsif need is not null then perform public.crm_need(s, need);
  end if;
  if r.kind in ('party', 'quote', 'invoice', 'payment', 'plant', 'earning') and length(why) < 3 then raise exception 'Hatane ki wajah likhein'; end if;
  if r.kind = 'invoice' and exists (select 1 from public.crm_records where kind = 'payment' and deleted_at is null and data ->> 'invoice_id' = r.id::text) then raise exception 'Pehle is bill ke payments hatayein'; end if;
  if r.kind = 'party' and exists (select 1 from public.crm_records where party_id = r.id and deleted_at is null and kind in ('invoice', 'payment')) then raise exception 'Is customer ke bill / payment hain — pehle unhe hatayein'; end if;
  if r.kind = 'folder' and exists (select 1 from public.crm_records where kind in ('folder', 'doc') and deleted_at is null and coalesce(data ->> 'parent_id', data ->> 'folder_id') = r.id::text) then raise exception 'Folder khaali nahi hai'; end if;
  if r.kind = 'earning' and r.status = 'paid' and not public.crm_is_admin(s) then raise exception 'Paid commission sirf Admin hata sakta hai'; end if;
  update public.crm_records set deleted_at = now(), deleted_by = (s).uid, delete_reason = why where id = r.id;
  if r.kind = 'payment' and coalesce(r.data ->> 'invoice_id', '') <> '' then perform public.crm_inv_recalc((r.data ->> 'invoice_id')::bigint); end if;
  if r.kind = 'invoice' then
    perform public.crm_stock(r.data, 1);
    update public.crm_records set status = 'accepted', data = data - 'invoice_id' - 'invoice_ref' where id = nullif(r.data ->> 'quote_id', '')::bigint;
  end if;
  if r.kind = 'plant' then perform public.crm_commission(r.id, s); end if;
  if r.kind = 'doc' then delete from public.crm_files where rec_id = r.id; end if;
  perform public.crm_log(s, 'delete', r.kind, r.id, coalesce(r.ref || ' ', '') || r.title || case when why <> '' then ' — Wajah: ' || why else '' end);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.crm_assign(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); k text := p ->> 'kind'; to_ bigint := nullif(p ->> 'user_id', '')::bigint; n int := 0; rid jsonb; r public.crm_records;
begin
  if k = 'lead' then perform public.crm_need(s, 'leads.assign');
  elsif k = 'party' then perform public.crm_need(s, 'customers.assign');
  elsif k = 'reminder' then perform public.crm_need(s, 'reminders.assign');
  else raise exception 'Galat record'; end if;
  if to_ is not null and not exists (select 1 from public.crm_users where id = to_ and status = 'active') then raise exception 'User nahi mila'; end if;
  for rid in select * from jsonb_array_elements(coalesce(p -> 'ids', '[]'::jsonb)) loop
    select * into r from public.crm_records where id = (rid #>> '{}')::bigint and kind = k;
    if public.crm_vis(s, r) then
      if k = 'party' then update public.crm_records set owner_id = coalesce(to_, 0), assigned_to = null, updated_at = now() where id = r.id;
      else update public.crm_records set assigned_to = to_, data = data || jsonb_build_object('assigned_on', public.crm_today())
             || case when k = 'lead' and to_ is not null and to_ <> r.owner_id then '{"company":true}'::jsonb else '{}'::jsonb end, updated_at = now() where id = r.id; end if;
      n := n + 1;
    end if;
  end loop;
  perform public.crm_log(s, 'assign', k, null, n || ' ' || k || ' → ' || coalesce(public.crm_uname(to_), 'Company'));
  return jsonb_build_object('count', n);
end $$;

create or replace function public.crm_lead_import(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); to_ bigint := nullif(p ->> 'assign_to', '')::bigint; r jsonb; m text; n int := 0; sk int := 0; own bigint; company boolean;
begin
  perform public.crm_need(s, 'leads.import');
  if to_ is not null and to_ <> (s).uid then
    perform public.crm_need(s, 'leads.assign');
    if not exists (select 1 from public.crm_users where id = to_ and status = 'active') then raise exception 'User nahi mila'; end if;
  end if;
  if jsonb_typeof(p -> 'rows') <> 'array' or jsonb_array_length(p -> 'rows') > 3000 then raise exception 'Ek baar me max 3000 leads'; end if;
  company := to_ is not null and to_ <> (s).uid;
  own := case when company then 0 else (s).uid end;
  for r in select * from jsonb_array_elements(p -> 'rows') loop
    if jsonb_typeof(r) <> 'object' or length(r::text) > 4000 then sk := sk + 1; continue; end if;
    m := public.crm_mobile(r ->> 'mobile');
    if m !~ '^[6-9][0-9]{9}$' then sk := sk + 1; continue; end if;
    if exists (select 1 from public.crm_records where kind = 'lead' and deleted_at is null and mobile = m and (assigned_to = coalesce(to_, (s).uid) or owner_id = coalesce(to_, (s).uid))) then sk := sk + 1; continue; end if;
    insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, due_at, data, search, created_by)
    values ('lead', left(coalesce(nullif(trim(r ->> 'name'), ''), 'Lead ' || m), 120), m, 'new', own, coalesce(to_, (s).uid),
      case when coalesce(r ->> 'followup', '') ~ '^\d{4}-\d{2}-\d{2}$' then (r ->> 'followup')::date else null end,
      (r - 'mobile') || jsonb_build_object('mobile', m, 'source', coalesce(nullif(r ->> 'source', ''), case when company then 'Company' else 'Import' end), 'company', company),
      lower(concat_ws(' ', r ->> 'name', m, r ->> 'city', r ->> 'source')), (s).uid);
    n := n + 1;
  end loop;
  perform public.crm_log(s, 'import', 'lead', null, n || ' leads import' || case when company then ' → ' || public.crm_uname(to_) else '' end || ' (' || sk || ' chhodi)');
  return jsonb_build_object('added', n, 'skipped', sk);
end $$;

-- ---------------------------------------------------------------- files (documents)
create or replace function public.crm_file_put(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); b bytea; fid bigint := nullif(p ->> 'folder_id', '')::bigint; r public.crm_records; nm text := left(trim(coalesce(p ->> 'name', 'file')), 160);
begin
  if not (public.crm_can(s, 'docs.upload') or coalesce(p ->> 'attach_kind', '') <> '') then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  if fid is not null and not public.crm_folder_ok(s, fid) then raise exception 'Folder nahi mila'; end if;
  if coalesce(p ->> 'attach_kind', '') <> '' then
    if nullif(p ->> 'party_id', '') is null then raise exception 'Customer chunein'; end if;
    select * into r from public.crm_records where id = (p ->> 'party_id')::bigint and kind = 'party';
    if not public.crm_vis(s, r) then raise exception 'Customer nahi mila'; end if;
    fid := null;
  end if;
  begin b := decode(coalesce(p ->> 'b64', ''), 'base64'); exception when others then raise exception 'File padh nahi paye'; end;
  if octet_length(b) = 0 then raise exception 'File khaali hai'; end if;
  if octet_length(b) > 3 * 1024 * 1024 then raise exception 'File 3 MB se badi hai'; end if;
  insert into public.crm_records(kind, title, status, owner_id, party_id, data, search, created_by)
  values ('doc', nm, 'ok', (s).uid, nullif(p ->> 'party_id', '')::bigint,
    jsonb_build_object('folder_id', fid, 'mime', left(coalesce(p ->> 'mime', 'application/octet-stream'), 80), 'size', octet_length(b), 'note', left(coalesce(p ->> 'note', ''), 500),
      'attach_kind', nullif(p ->> 'attach_kind', ''), 'attach_id', nullif(p ->> 'attach_id', '')),
    lower(nm || ' ' || coalesce(p ->> 'note', '')), (s).uid) returning * into r;
  insert into public.crm_files(rec_id, mime, size, data) values (r.id, left(coalesce(p ->> 'mime', 'application/octet-stream'), 80), octet_length(b), b);
  perform public.crm_log(s, 'upload', 'doc', r.id, 'Document: ' || nm);
  return public.crm_row(s, r);
end $$;

create or replace function public.crm_file_get(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records; f public.crm_files;
begin
  select * into r from public.crm_records where id = (p ->> 'id')::bigint and kind = 'doc';
  if not public.crm_vis(s, r) then raise exception 'Document nahi mila'; end if;
  select * into f from public.crm_files where rec_id = r.id limit 1;
  if f.id is null then raise exception 'File nahi mili'; end if;
  perform public.crm_log(s, 'open', 'doc', r.id, 'Document khola: ' || r.title);
  return jsonb_build_object('name', r.title, 'mime', f.mime, 'b64', encode(f.data, 'base64'));
end $$;

-- ---------------------------------------------------------------- search / today / dashboards
create or replace function public.crm_search(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q text := lower(trim(coalesce(p ->> 'q', '')));
begin
  if length(q) < 2 then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'title', title, 'ref', ref, 'mobile', mobile, 'status', status, 'amount', amount, 'data',
      case when kind = 'doc' then jsonb_build_object('folder_id', data -> 'folder_id', 'mime', data -> 'mime') when kind = 'item' then jsonb_build_object('type', data -> 'type') else '{}'::jsonb end))
    from (select * from public.crm_records r where r.deleted_at is null and r.kind in ('party', 'lead', 'quote', 'invoice', 'item', 'doc', 'folder', 'plant', 'payment')
      and r.search like '%' || q || '%' and public.crm_vis(s, r) order by r.updated_at desc limit 40) x), '[]'::jsonb);
end $$;

create or replace function public.crm_today_list(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); u bigint := coalesce(nullif(p ->> 'user_id', '')::bigint, (s).uid); dt date := coalesce(nullif(p ->> 'date', '')::date, public.crm_today());
        allu boolean := coalesce((p ->> 'all')::boolean, false);
begin
  if (u <> (s).uid or allu) and not (public.crm_can(s, 'reminders.view_all') or public.crm_can(s, 'team.stats')) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  return jsonb_build_object('date', dt, 'items', coalesce((select jsonb_agg(x order by x ->> 'due_at', x ->> 'kind') from (
    select jsonb_build_object('src', 'reminder', 'id', r.id, 'kind', coalesce(r.data ->> 'type', 'other'), 'title', r.title, 'note', r.data ->> 'note', 'time', r.data ->> 'time', 'due_at', r.due_at,
      'overdue', r.due_at < dt, 'party_id', r.party_id, 'mobile', r.mobile, 'user', public.crm_uname(coalesce(r.assigned_to, r.owner_id)), 'user_id', coalesce(r.assigned_to, r.owner_id)) x
    from public.crm_records r where r.kind = 'reminder' and r.deleted_at is null and r.status = 'open' and r.due_at <= dt and (allu or coalesce(r.assigned_to, r.owner_id) = u)
    union all
    select jsonb_build_object('src', 'lead', 'id', r.id, 'kind', 'followup', 'title', r.title, 'note', r.data ->> 'note', 'due_at', r.due_at, 'overdue', r.due_at < dt, 'mobile', r.mobile, 'status', r.status,
      'user', public.crm_uname(coalesce(r.assigned_to, r.owner_id)), 'user_id', coalesce(r.assigned_to, r.owner_id))
    from public.crm_records r where r.kind = 'lead' and r.deleted_at is null and r.status not in ('won', 'lost') and r.due_at <= dt and (allu or coalesce(r.assigned_to, r.owner_id) = u)
    union all
    select jsonb_build_object('src', 'invoice', 'id', r.id, 'kind', 'payment_in', 'title', r.title || ' — ' || coalesce(r.ref, ''), 'due_at', r.due_at, 'overdue', r.due_at < dt, 'mobile', r.mobile,
      'amount', r.data -> 'balance', 'user', public.crm_uname(r.owner_id), 'user_id', r.owner_id)
    from public.crm_records r where r.kind = 'invoice' and r.deleted_at is null and r.status <> 'paid' and r.due_at <= dt and (allu or r.owner_id = u)
    union all
    select jsonb_build_object('src', 'quote', 'id', r.id, 'kind', 'quote_send', 'title', r.title || ' — ' || coalesce(r.ref, ''), 'due_at', r.due_at, 'overdue', r.due_at < dt, 'mobile', r.mobile,
      'amount', r.amount, 'user', public.crm_uname(r.owner_id), 'user_id', r.owner_id)
    from public.crm_records r where r.kind = 'quote' and r.deleted_at is null and r.status = 'draft' and r.due_at <= dt and (allu or r.owner_id = u)
    union all
    select jsonb_build_object('src', 'earning', 'id', r.id, 'kind', 'payment_out', 'title', r.title || ' → ' || coalesce(public.crm_uname(r.owner_id), ''), 'due_at', r.due_at, 'overdue', r.due_at < dt,
      'amount', r.amount, 'user', 'Admin', 'user_id', 0)
    from public.crm_records r where r.kind = 'earning' and r.deleted_at is null and r.status = 'due' and r.due_at <= dt and (allu or u = 0) and public.crm_can(s, 'earnings.manage')
  ) q), '[]'::jsonb));
end $$;

create or replace function public.crm_team_stats(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); dt date := public.crm_today(); fr date := coalesce(nullif(p ->> 'from', '')::date, public.crm_today() - 30);
begin
  perform public.crm_need(s, 'team.stats');
  return coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'role', u.role, 'last_seen', u.last_seen,
    'open', (select count(*) from public.crm_records r where r.kind = 'reminder' and r.deleted_at is null and r.status = 'open' and coalesce(r.assigned_to, r.owner_id) = u.id),
    'overdue', (select count(*) from public.crm_records r where r.deleted_at is null and coalesce(r.assigned_to, r.owner_id) = u.id and r.due_at < dt
                 and ((r.kind = 'reminder' and r.status = 'open') or (r.kind = 'lead' and r.status not in ('won', 'lost')))),
    'done', (select count(*) from public.crm_records r where r.kind = 'reminder' and r.deleted_at is null and r.status = 'done' and coalesce(r.assigned_to, r.owner_id) = u.id and r.updated_at::date >= fr),
    'late', (select count(*) from public.crm_records r where r.kind = 'reminder' and r.deleted_at is null and r.status = 'done' and coalesce(r.assigned_to, r.owner_id) = u.id and r.updated_at::date >= fr
              and (r.data ->> 'done_at')::timestamptz::date > r.due_at),
    'leads', (select count(*) from public.crm_records r where r.kind = 'lead' and r.deleted_at is null and coalesce(r.assigned_to, r.owner_id) = u.id),
    'won', (select count(*) from public.crm_records r where r.kind = 'lead' and r.deleted_at is null and r.status = 'won' and coalesce(r.assigned_to, r.owner_id) = u.id),
    'quotes', (select count(*) from public.crm_records r where r.kind = 'quote' and r.deleted_at is null and r.owner_id = u.id and r.created_at::date >= fr),
    'sales', (select coalesce(sum(amount), 0) from public.crm_records r where r.kind = 'invoice' and r.deleted_at is null and r.owner_id = u.id and r.created_at::date >= fr),
    'plants', (select count(*) from public.crm_records r where r.kind = 'plant' and r.deleted_at is null and r.status = 'verified' and (r.owner_id = u.id or upper(r.data ->> 'ref') = u.ref_code))
  ) order by u.name) from public.crm_users u where u.role not in ('consumer') and u.status = 'active'), '[]'::jsonb);
end $$;