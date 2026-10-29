-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 23 of 30
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U30). Safe to re-run.
-- ============================================================================

-- ---------- crm_save: options / lock / PDF ki jaankari save me nahi khoti; final quotation ke rate sirf Manager / Admin wajah ke saath badal sakte hain ----------
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
    if not isnew and old.data ->> 'fixed' = 'true' and not public.crm_is_admin(s) then raise exception 'Ye Fixed plan hai — sirf Admin iski keemat / kaam ki list badal sakta hai'; end if;
    if ttl = '' then raise exception 'Item ka naam likhein'; end if;
    amt := public.crm_num(d -> 'price'); mob := null; pid := null;
    if not public.crm_can(s, 'items.cost') and not isnew then d := d || jsonb_build_object('cost_price', old.data -> 'cost_price', 'min_price', old.data -> 'min_price'); end if;
    -- online store status: only the review flow can publish
    if not isnew then d := jsonb_set(d, '{store}', coalesce(old.data -> 'store', '{}'::jsonb) || (coalesce(d -> 'store', '{}'::jsonb) - 'status' - 'store_id' - 'reviewed_at' - 'online' - 'sent_at')); end if;
    if not isnew then d := jsonb_set(d, '{holds}', coalesce(old.data -> 'holds', '[]'::jsonb)); elsif d ? 'holds' then d := d - 'holds'; end if;
    if isnew then d := jsonb_set(d, '{store}', (coalesce(d -> 'store', '{}'::jsonb) - 'store_id' - 'reviewed_at') || '{"status":"none"}'::jsonb); end if;
    d := public.crm_item_prep(isnew, case when isnew then null else old.data end, d);   -- Round 13: auto SKU (immutable), project line SKUs
    if coalesce(d ->> 'type', 'product') = 'product' then   -- Round 43: kharid rate (purchase price) zaroori
      if public.crm_num(d -> 'cost_price') > 0 then d := d - 'cost_missing';
      elsif isnew and public.crm_can(s, 'items.cost') and coalesce(d ->> 'cost_ok', '') <> 'true' then raise exception 'Kharid rate (purchase price) zaroori hai — pehle likhein';
      else d := d || '{"cost_missing":true}'::jsonb; end if;
    end if;
    d := d - 'cost_ok';
    if not isnew and coalesce(d ->> 'type', 'product') = 'project' and old.data #> '{store,online}' is not null
       and coalesce((select jsonb_agg(jsonb_build_object('i', x ->> 'item_id', 'q', public.crm_num(x -> 'qty')) order by o) from jsonb_array_elements(coalesce(d -> 'proj_items', '[]'::jsonb)) with ordinality t(x, o)), '[]'::jsonb)
          is distinct from coalesce((select jsonb_agg(jsonb_build_object('i', x ->> 'item_id', 'q', public.crm_num(x -> 'qty')) order by o) from jsonb_array_elements(coalesce(old.data -> 'proj_items', '[]'::jsonb)) with ordinality t(x, o)), '[]'::jsonb) then
      raise exception 'Ye template Online par hai — items / qty badalne ke liye pehle Online list me "Online se hatayein" karein (naam badal sakte hain)'; end if;
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
          if it.id is not null and public.crm_num(it.data -> 'cost_price') > 0 and public.crm_num(l -> 'price') < public.crm_num(it.data -> 'cost_price') - 0.009 then
            raise exception '"%" ka rate kharid rate (%) se kam nahi ho sakta', it.title, public.crm_num(it.data -> 'cost_price'); end if;
          if it.id is not null and public.crm_num(it.data -> 'min_price') > 0 and public.crm_num(l -> 'price') < public.crm_num(it.data -> 'min_price') then
            raise exception '"%" ka rate minimum rate se kam hai — Admin se permission lein', it.title; end if;
        end if;
      end loop;
      select coalesce(nullif(public.crm_num(meta -> 'max_discount_pct'), 0), public.crm_role_discount(role)) into lim from public.crm_users where id = (s).uid;
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
    if k = 'quote' then
      declare chg boolean := false; rv jsonb := '[]'::jsonb; keepd jsonb := d;
      begin
        d := d - 'alt' - 'locked' - 'resp' - 'reaccept' - 'opt_id' - 'opt_label' - 'pdf_url' - 'rev' - 'unlocks';
        if not isnew then
          chg := public.crm_doc_calc(old.data) is distinct from calc or jsonb_array_length(coalesce(old.data -> 'lines', '[]'::jsonb)) <> jsonb_array_length(d -> 'lines');
          rv := coalesce(old.data -> 'rev', '[]'::jsonb);
          if old.data -> 'locked' is not null and chg then
            if not (public.crm_is_admin(s) or (s).role = 'manager') then raise exception 'Customer ne final kar diya — rate / items sirf Manager ya Admin badal sakta hai'; end if;
            if length(trim(coalesce(p ->> 'reason', ''))) < 3 then raise exception 'Badlav ki wajah likhein'; end if;
            rv := rv || jsonb_build_array(jsonb_build_object('at', now(), 'by', (s).name, 'reason', left(trim(p ->> 'reason'), 300), 'before', old.data -> 'grand', 'after', calc -> 'grand'));
          end if;
          if old.data ? 'alt' then d := d || jsonb_build_object('alt', old.data -> 'alt'); end if;
          if old.data ? 'locked' then d := d || jsonb_build_object('locked', old.data -> 'locked'); end if;
          if old.data ? 'resp' then d := d || jsonb_build_object('resp', old.data -> 'resp'); end if;
          if old.data ? 'opt_id' then d := d || jsonb_build_object('opt_id', old.data -> 'opt_id'); end if;
          if old.data ? 'opt_label' or keepd ? 'opt_label' then d := d || jsonb_build_object('opt_label', coalesce(keepd -> 'opt_label', old.data -> 'opt_label')); end if;
          if old.data ? 'unlocks' then d := d || jsonb_build_object('unlocks', old.data -> 'unlocks'); end if;
          if jsonb_array_length(rv) > 0 then d := d || jsonb_build_object('rev', rv); end if;
          if old.data -> 'locked' is not null and (chg or coalesce(old.data ->> 'reaccept', '') = 'true') then d := d || jsonb_build_object('reaccept', true); end if;
          if not chg and old.data ? 'pdf_url' then d := d || jsonb_build_object('pdf_url', old.data -> 'pdf_url'); end if;
        end if;
      end;
    end if;
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
    if isnew and exists (select 1 from public.crm_records where kind = 'lead' and deleted_at is null and status not in ('won', 'lost') and mobile = mob and (owner_id = (s).uid or assigned_to = coalesce(asg, (s).uid))) then
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
end $function$;
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
  if q.data -> 'locked' is null and exists (select 1 from jsonb_array_elements(coalesce(q.data -> 'alt', '[]'::jsonb)) x where coalesce(x ->> 'dropped', '') <> 'true') then raise exception 'Is quotation me kai option hain — pehle jo option customer ne chuna use "Ye final" karein'; end if;
  inv := public.crm_save(jsonb_build_object('token', p ->> 'token', 'kind', 'invoice', 'party_id', q.party_id,
    'data', (q.data - 'send_on' - 'valid_till' - 'alt' - 'locked' - 'resp' - 'rev' - 'unlocks' - 'reaccept' - 'pdf_url' - 'opt_id' - 'opt_label') || jsonb_build_object('quote_id', q.id, 'quote_ref', q.ref, 'date', public.crm_today(), 'due_date', coalesce(p ->> 'due_date', ''))));
  update public.crm_records set status = 'converted', data = data || jsonb_build_object('invoice_id', inv ->> 'id', 'invoice_ref', inv ->> 'ref'), updated_at = now() where id = q.id;
  perform public.crm_stock(q.data, -1);
  return inv;
end $function$;
-- =====================================================================================================
-- ROUND 53 — "Hum kaise kaam karte hain" page (customer link) + CRM Documents & Gallery me "Customer Samples" folder (namune)
--   Sirf folder "Customer Samples" ki files customer ke link me dikhti hain (aur koi document kabhi nahi).
--   Namune pehli baar hi daalte hain (folder pehle se ho to kuch nahi badalta). Dobara chalana safe hai.
-- =====================================================================================================
create or replace function public.crm__sample_root() returns bigint language sql stable security definer set search_path = public as $f$
  select id from public.crm_records where kind = 'folder' and deleted_at is null and coalesce(data ->> 'sample_root', '') = 'true' order by id limit 1
$f$;
revoke all on function public.crm__sample_root() from public, anon, authenticated;