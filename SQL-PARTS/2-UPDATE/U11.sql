-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 11 of 30
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U30). Safe to re-run.
-- ============================================================================

-- ============================================================================
-- ROUND 34b — 5 FIXED Maintenance & AMC plans (Random, Recommended, Valuable, Tension Free, Best Value): only Admin can change price + what is included; cycle / duration are locked.
-- ============================================================================
create or replace function public.crm_save(p jsonb)
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

create or replace function public.crm_maint_contract(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); ex public.crm_records; pl public.crm_records; months int; yrs int; total int; i int;
        cid text := 'MC-' || encode(gen_random_bytes(4), 'hex'); start_ date; checks jsonb := '[]'::jsonb; pname text; cost numeric := 0; asg bigint := coalesce(nullif(p ->> 'assigned_to', '')::bigint, (s).uid); c jsonb; ck public.crm_records; cyc text := ''; vt text := left(coalesce(p ->> 'time', ''), 5);
begin
  if not (public.crm_can(s, 'customers.create') or public.crm_can(s, 'customers.edit') or public.crm_can(s, 'items.view') or public.crm_is_admin(s)) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  select * into ex from public.crm_records where id = (p ->> 'party_id')::bigint and kind = 'party';
  if not public.crm_vis(s, ex) then raise exception 'Customer nahi mila'; end if;
  begin start_ := (p ->> 'start')::date; exception when others then raise exception 'Sahi tareekh chunein'; end;
  if start_ is null then raise exception 'Pehli visit ki tareekh chunein'; end if;
  select * into pl from public.crm_records where id = nullif(p ->> 'plan_id', '')::bigint and kind = 'item' and deleted_at is null and data ->> 'type' = 'maintenance';
  if pl.id is null then raise exception 'Plan chunein (Maintenance & Audit Packages me plan banayein)'; end if;
  cyc := lower(coalesce(nullif(p ->> 'cycle', ''), pl.data ->> 'period', ''));
  pname := pl.title; months := public.crm_months_of(coalesce(nullif(cyc, ''), pl.data ->> 'period'));
  if cyc = 'one' then months := 0; elsif cyc = 'five' then months := 60; elsif cyc = 'monthly' then months := 1; end if;
  if vt <> '' and vt !~ '^[0-2][0-9]:[0-5][0-9]$' then raise exception 'Sahi time chunein'; end if;
  yrs := least(greatest(coalesce(nullif(pl.data ->> 'years', '')::int, 1), 1), 10);
  total := case when months = 0 then 1 else least(greatest(ceil(12.0 / months * yrs)::int, 1), 120) end;
  for c in select * from jsonb_array_elements(coalesce(pl.data -> 'checklist', '[]'::jsonb)) loop
    select * into ck from public.crm_records where id = nullif(c #>> '{}', '')::bigint and kind = 'item' and deleted_at is null and data ->> 'type' = 'mcheck';
    if ck.id is not null then
      checks := checks || jsonb_build_array(jsonb_build_object('id', ck.id, 'name', ck.title, 'cost', public.crm_num(ck.data -> 'cost'),
        'mat_id', nullif(ck.data ->> 'material_item_id', ''), 'mat_qty', public.crm_num(ck.data -> 'material_qty')));
      cost := cost + public.crm_num(ck.data -> 'cost');
    end if;
  end loop;
  for i in 0 .. total - 1 loop
    insert into public.crm_records(kind, title, status, owner_id, assigned_to, party_id, mobile, due_at, data, search, created_by)
    values ('reminder', 'Solar service — ' || ex.title, 'open', (s).uid, asg, ex.id, ex.mobile, (start_ + make_interval(months => i * months))::date,
      jsonb_build_object('type', 'amc', 'maint', true, 'contract_id', cid, 'plan_id', pl.id, 'plan_name', pname, 'free', coalesce((pl.data ->> 'free')::boolean, false), 'months', months, 'cycle', coalesce(nullif(cyc, ''), pl.data ->> 'period'), 'visit_time', vt, 'plan_code', coalesce(pl.data ->> 'plan_code', ''), 'plan_price', public.crm_num(pl.data -> 'price'), 'plan_gst', public.crm_num(pl.data -> 'gst'), 'prev_contract', coalesce(p ->> 'prev_contract', ''),
        'visit_no', i + 1, 'visits_total', total, 'checks', checks, 'visit_cost', cost, 'mobile', coalesce(ex.mobile, ''), 'party_name', ex.title, 'title', 'Solar service — ' || ex.title),
      lower('solar service ' || ex.title || ' ' || pname), (s).uid);
  end loop;
  perform public.crm_log(s, 'create', 'maintenance', ex.id, 'Maintenance & Audit: ' || pname || ' → ' || ex.title || ' (' || total || ' visits)');
  return jsonb_build_object('ok', true, 'contract_id', cid, 'visits', total, 'first_due', start_);
end $$;

-- structure of a fixed plan can never change (not even by Admin); it cannot be deleted
create or replace function public.crm_plan_lock() returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('sp.restoring', true), '') = 'on' then return new; end if;
  if old.kind = 'item' and old.data ->> 'fixed' = 'true' then
    if new.deleted_at is not null and old.deleted_at is null then raise exception 'Fixed plan hataya nahi ja sakta'; end if;
    new.title := old.title; new.kind := old.kind;
    new.data := new.data || jsonb_build_object('fixed', true, 'type', 'maintenance', 'plan_code', old.data -> 'plan_code', 'name', old.data -> 'name', 'period', old.data -> 'period', 'years', old.data -> 'years', 'visits', old.data -> 'visits', 'unit', old.data -> 'unit', 'category', old.data -> 'category');
  end if;
  return new;
end $$;
drop trigger if exists crm_plan_lock on public.crm_records;
create trigger crm_plan_lock before update on public.crm_records for each row when (old.kind = 'item') execute function public.crm_plan_lock();

-- the 5 fixed plans (old test plans are removed; nobody was assigned to them)
create or replace function public.crm_seed_plans() returns void language plpgsql security definer set search_path = public as $$
declare rec record; ids jsonb := '{}'::jsonb; c record; ck jsonb;
begin
  update public.crm_records set deleted_at = now(), delete_reason = 'Purane plan hataye — 5 Fixed plans aaye'
    where kind = 'item' and data ->> 'type' = 'maintenance' and coalesce(data ->> 'fixed', '') <> 'true' and deleted_at is null;
  for c in select id, title from public.crm_records where kind = 'item' and data ->> 'type' = 'mcheck' and deleted_at is null loop ids := ids || jsonb_build_object(c.title, c.id); end loop;
  for rec in select * from (values
    ('random',      'Random Plan',        'one',       1,  1, 1500, 'Solar panel cleaning|Visual & physical inspection|Inverter check (error log, display, firmware)|Generation report', 'Sirf ek baar ki service — agli due date nahi'),
    ('recommended', 'Recommended Plan',   'quarterly', 1,  4, 4800, 'Solar panel cleaning|Visual & physical inspection|Inverter check (error log, display, firmware)|Earthing resistance test|ACDB check & tightening|DCDB check & tightening|Cable & MC4 connector check|Generation report', 'Quarterly: saal me 4 services (har 3 mahine)'),
    ('valuable',    'Valuable Plan',      'yearly',    1,  1, 1600, 'Solar panel cleaning|Visual & physical inspection|Inverter check (error log, display, firmware)|Generation report', 'Yearly: saal me 1 service'),
    ('tension',     'Tension Free Plan',  'quarterly', 5, 20, 20000, 'Solar panel cleaning|Visual & physical inspection|Inverter check (error log, display, firmware)|Earthing resistance test|ACDB check & tightening|DCDB check & tightening|Cable & MC4 connector check|Shadow & structure check|Lightning arrestor check|Generation report', 'Quarterly: saal me 4, 5 saal me 20 services'),
    ('best',        'Best Value Plan',    'yearly',    5,  5, 7000, 'Solar panel cleaning|Visual & physical inspection|Inverter check (error log, display, firmware)|Earthing resistance test|ACDB check & tightening|DCDB check & tightening|Cable & MC4 connector check|Generation report', 'Yearly: 5 saal me 5 services')
  ) as t(code, nm, per, yrs, vis, price, names, descr) loop
    if exists (select 1 from public.crm_records where kind = 'item' and data ->> 'plan_code' = rec.code and deleted_at is null) then continue; end if;
    select coalesce(jsonb_agg(ids -> n), '[]'::jsonb) into ck from unnest(string_to_array(rec.names, '|')) n where ids ? n;
    insert into public.crm_records(kind, title, status, owner_id, amount, data, search)
    values ('item', rec.nm, 'active', 0, rec.price, jsonb_build_object('type', 'maintenance', 'fixed', true, 'plan_code', rec.code, 'name', rec.nm, 'title', '', 'category', 'Maintenance', 'price', rec.price, 'gst', 18, 'unit', 'Plan',
      'period', rec.per, 'years', rec.yrs, 'visits', rec.vis, 'free', false, 'checklist', ck, 'desc', rec.descr), lower(rec.nm));
  end loop;
end $$;
select public.crm_seed_plans();
do $g$ begin execute 'revoke all on function public.crm_seed_plans() from public, anon, authenticated'; exception when undefined_object then null; end $g$;

-- Change plan for a customer who already has one: open visits of the old plan are cancelled, the new plan is scheduled from the next due date (or today)
create or replace function public.crm_maint_change(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records; old_cid text := p ->> 'contract_id'; nxt date; res jsonb; pid bigint;
begin
  if not (public.crm_can(s, 'customers.edit') or public.crm_can(s, 'items.view') or public.crm_is_admin(s)) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  if coalesce(old_cid, '') = '' then raise exception 'Purana plan nahi mila'; end if;
  select * into r from public.crm_records where kind = 'reminder' and data ->> 'contract_id' = old_cid and deleted_at is null order by id limit 1;
  if r.id is null or not public.crm_vis(s, r) then raise exception 'Purana plan nahi mila'; end if;
  pid := r.party_id;
  select min(due_at) into nxt from public.crm_records where kind = 'reminder' and data ->> 'contract_id' = old_cid and deleted_at is null and status = 'open';
  update public.crm_records set deleted_at = now(), delete_reason = 'Plan badal diya', updated_at = now()
    where kind = 'reminder' and data ->> 'contract_id' = old_cid and deleted_at is null and status = 'open';
  res := public.crm_maint_contract(jsonb_build_object('token', p ->> 'token', 'party_id', pid, 'plan_id', p -> 'plan_id', 'assigned_to', p -> 'assigned_to',
           'start', coalesce(nullif(p ->> 'start', ''), greatest(coalesce(nxt, public.crm_today()), public.crm_today())::text), 'time', coalesce(p ->> 'time', ''), 'prev_contract', old_cid));
  return res || jsonb_build_object('changed_from', old_cid);
end $$;
do $g$ begin
  execute 'revoke all on function public.crm_maint_change(jsonb) from public';
  execute 'grant execute on function public.crm_maint_change(jsonb) to anon, authenticated';
exception when undefined_object then null; end $g$;


-- ============================================================================
-- ROUND 35 — one permanent Customer ID (SP-C-000123) per person + stage: Lead -> Pending Inquiry -> Customer (on first bill)
-- ============================================================================
create or replace function public.crm_cust_id_next() returns text language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into public.crm_counters(key, n) values ('custid', 1) on conflict (key) do update set n = public.crm_counters.n + 1 returning public.crm_counters.n into n;
  return 'SP-C-' || lpad(n::text, 6, '0');
end $$;

-- BEFORE INSERT: every lead / customer gets the ID (same mobile = same ID); a new customer starts as a Pending Inquiry
create or replace function public.crm_custid_ins() returns trigger language plpgsql security definer set search_path = public as $$
declare cid text; d jsonb := coalesce(new.data, '{}'::jsonb);
begin
  if new.kind = 'party' and coalesce(d ->> 'type', 'customer') = 'supplier' then return new; end if;
  cid := nullif(d ->> 'cust_id', '');
  if cid is null and coalesce(new.mobile, '') <> '' then
    select data ->> 'cust_id' into cid from public.crm_records where kind in ('party', 'lead') and mobile = new.mobile and coalesce(data ->> 'cust_id', '') <> '' and deleted_at is null and coalesce(data ->> 'type', 'customer') <> 'supplier' order by id limit 1;
  end if;
  if cid is null then cid := public.crm_cust_id_next(); end if;
  d := d || jsonb_build_object('cust_id', cid);
  if new.kind = 'party' and coalesce(d ->> 'stage', '') not in ('inquiry', 'customer') then d := d || jsonb_build_object('stage', 'inquiry'); end if;
  new.data := d;
  new.search := trim(coalesce(new.search, '') || ' ' || lower(cid));
  return new;
end $$;
drop trigger if exists crm_custid_ins on public.crm_records;
create trigger crm_custid_ins before insert on public.crm_records for each row when (new.kind in ('party', 'lead')) execute function public.crm_custid_ins();

-- BEFORE UPDATE: the ID never changes; the stage changes only through the bill (never from a form)
create or replace function public.crm_custid_upd() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(old.data ->> 'cust_id', '') <> '' then new.data := new.data || jsonb_build_object('cust_id', old.data ->> 'cust_id'); end if;
  if new.kind = 'party' and coalesce(current_setting('sp.stage_ok', true), '') <> '1' and coalesce(current_setting('sp.restoring', true), '') <> 'on' then
    if coalesce(old.data ->> 'stage', '') <> '' then new.data := new.data || jsonb_build_object('stage', old.data ->> 'stage'); end if;
  end if;
  return new;
end $$;
drop trigger if exists crm_custid_upd on public.crm_records;
create trigger crm_custid_upd before update on public.crm_records for each row when (old.kind in ('party', 'lead')) execute function public.crm_custid_upd();

-- first bill => the Pending Inquiry becomes a Customer (stays there for life)
create or replace function public.crm_stage_bill() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.party_id is null then return new; end if;
  perform set_config('sp.stage_ok', '1', true);
  update public.crm_records set data = data || jsonb_build_object('stage', 'customer', 'billed_at', public.crm_iso_now()), updated_at = now()
    where id = new.party_id and kind = 'party' and coalesce(data ->> 'stage', '') = 'inquiry';
  perform set_config('sp.stage_ok', '', true);
  return new;
end $$;
drop trigger if exists crm_stage_bill on public.crm_records;
create trigger crm_stage_bill after insert on public.crm_records for each row when (new.kind = 'invoice') execute function public.crm_stage_bill();

-- backfill: IDs for everyone already there (one ID per mobile), stage = Customer when a bill exists, else Pending Inquiry
do $b$
declare r record; cid text; m text;
begin
  perform set_config('sp.restoring', 'on', true);
  for r in select id, kind, mobile, data from public.crm_records
           where kind in ('party', 'lead') and coalesce(data ->> 'cust_id', '') = '' and coalesce(data ->> 'type', 'customer') <> 'supplier' order by id loop
    cid := null; m := coalesce(r.mobile, '');
    if m <> '' then select data ->> 'cust_id' into cid from public.crm_records where kind in ('party', 'lead') and mobile = m and coalesce(data ->> 'cust_id', '') <> '' and coalesce(data ->> 'type', 'customer') <> 'supplier' order by id limit 1; end if;
    if cid is null then cid := public.crm_cust_id_next(); end if;
    update public.crm_records set data = data || jsonb_build_object('cust_id', cid), search = trim(coalesce(search, '') || ' ' || lower(cid)) where id = r.id;
  end loop;
  update public.crm_records p set data = data || jsonb_build_object('stage', case when exists (select 1 from public.crm_records i where i.kind = 'invoice' and i.party_id = p.id) then 'customer' else 'inquiry' end)
    where p.kind = 'party' and coalesce(p.data ->> 'type', 'customer') <> 'supplier' and coalesce(p.data ->> 'stage', '') not in ('inquiry', 'customer');
end $b$;


-- Customer app / shop page: one profile by mobile login — Customer ID, projects (+warranty, AMC), products (+warranty), services (+status), pending quotations
create or replace function public.crm_consumer_profile(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); pt public.crm_records; q public.crm_records; inv public.crm_records; l jsonb; k text; card jsonb; wl jsonb;
        projects jsonb := '[]'::jsonb; services jsonb := '[]'::jsonb; inquiries jsonb := '[]'::jsonb; products jsonb := '[]'::jsonb; cid text; it public.crm_records; qk text;
begin
  select * into pt from public.crm_records where kind = 'party' and deleted_at is null and mobile = u.mobile and u.mobile ~ '^[6-9][0-9]{9}$' and coalesce(data ->> 'type', 'customer') <> 'supplier' order by id limit 1;
  if pt.id is null then
    select data ->> 'cust_id' into cid from public.crm_records where kind = 'lead' and deleted_at is null and mobile = u.mobile order by id limit 1;
    return jsonb_build_object('cust_id', cid, 'stage', 'lead', 'name', u.name, 'mobile', u.mobile, 'projects', projects, 'services', services, 'products', products, 'inquiries', inquiries);
  end if;
  for q in select * from public.crm_records where kind = 'quote' and party_id = pt.id and deleted_at is null order by id loop
    k := case when q.data ->> 'ctype' in ('Residential', 'Commercial', 'Industrial', 'VFD') then 'project' when q.data ->> 'ctype' = 'Items only' then 'product' when coalesce(q.data ->> 'ctype', '') = '' then 'project' else 'service' end;
    if q.status in ('accepted', 'converted') then
      if k = 'product' then continue; end if;
      insert into public.crm_consumer_plants(user_id, quote_id) values (u.id, q.id) on conflict do nothing;
      card := public.crm_plant_card(q);
      wl := '[]'::jsonb;
      for l in select * from jsonb_array_elements(coalesce(q.data -> 'lines', '[]'::jsonb)) loop
        select * into it from public.crm_records where id = nullif(l ->> 'item_id', '')::bigint and kind = 'item';
        if it.id is not null and coalesce(it.data ->> 'warranty', '') <> '' then wl := wl || jsonb_build_array(jsonb_build_object('name', coalesce(l ->> 'name', it.title), 'warranty', it.data ->> 'warranty')); end if;
      end loop;
      card := card || jsonb_build_object('kind', k, 'warranty', wl, 'job_status', case when (q.data ->> 'closed') = 'true' then 'Poora hua' else 'Chal raha hai' end);
      if k = 'project' then projects := projects || jsonb_build_array(card); else services := services || jsonb_build_array(card); end if;
    elsif q.status in ('draft', 'sent') then
      inquiries := inquiries || jsonb_build_array(jsonb_build_object('id', q.id, 'ref', q.ref, 'title', coalesce(q.data ->> 'qtitle', q.title), 'kind', k, 'status', case q.status when 'sent' then 'Quotation bheji gayi' else 'Taiyaar ho rahi hai' end));
    end if;
  end loop;
  for inv in select i.* from public.crm_records i where i.kind = 'invoice' and i.party_id = pt.id and i.deleted_at is null order by i.id loop
    qk := null;
    select case when q2.data ->> 'ctype' = 'Items only' then 'product' else 'other' end into qk from public.crm_records q2 where q2.id = nullif(inv.data ->> 'quote_id', '')::bigint;
    if qk = 'other' then continue; end if;
    for l in select * from jsonb_array_elements(coalesce(inv.data -> 'lines', '[]'::jsonb)) loop
      select * into it from public.crm_records where id = nullif(l ->> 'item_id', '')::bigint and kind = 'item';
      products := products || jsonb_build_array(jsonb_build_object('name', coalesce(l ->> 'name', it.title), 'qty', l -> 'qty', 'bill', inv.ref, 'date', inv.data ->> 'date', 'brand', it.data ->> 'brand', 'warranty', nullif(it.data ->> 'warranty', ''), 'paid', coalesce((inv.data ->> 'balance')::numeric, inv.amount) <= 0.009));
    end loop;
  end loop;
  return jsonb_build_object('cust_id', pt.data ->> 'cust_id', 'stage', coalesce(pt.data ->> 'stage', 'customer'), 'name', pt.title, 'mobile', pt.mobile,
    'projects', projects, 'services', services, 'products', products, 'inquiries', inquiries);
end $$;
grant execute on function public.crm_consumer_profile(jsonb) to anon, authenticated;


-- ============================================================================
-- ROUND 36 — Bills are non-refundable; a bill can be cancelled ("Cancelled – non refundable"); only Admin can allow a refund exception
-- ============================================================================
create or replace function public.crm_bill_cancel(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records; act text := coalesce(p ->> 'action', 'cancel'); why text := left(trim(coalesce(p ->> 'reason', '')), 300);
begin
  select * into r from public.crm_records where id = (p ->> 'id')::bigint and kind = 'invoice' and deleted_at is null;
  if r.id is null or not public.crm_vis(s, r) then raise exception 'Bill nahi mila'; end if;
  perform set_config('sp.restoring', 'on', true);   -- only a flag is changed here: skip the item-line guard of old bills
  if act = 'refund_ok' or act = 'refund_no' then
    if not public.crm_is_admin(s) then raise exception 'Refund ka exception sirf Admin laga sakta hai'; end if;
    update public.crm_records set data = data || jsonb_build_object('refund_ok', act = 'refund_ok', 'refund_note', why), updated_at = now() where id = r.id;
    perform public.crm_log(s, 'update', 'invoice', r.id, case when act = 'refund_ok' then 'Refund exception allowed: ' else 'Refund exception removed: ' end || r.ref);
    return jsonb_build_object('ok', true);
  end if;
  if not (public.crm_can(s, 'invoices.delete') or public.crm_can(s, 'invoices.edit') or public.crm_is_admin(s)) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  if length(why) < 3 then raise exception 'Cancel ka reason likhein'; end if;
  if act = 'restore' then
    if not public.crm_is_admin(s) then raise exception 'Bill dobara sirf Admin chalu kar sakta hai'; end if;
    update public.crm_records set data = (data - 'cancelled' - 'cancel_reason' - 'cancelled_at'), updated_at = now() where id = r.id;
    perform public.crm_log(s, 'update', 'invoice', r.id, 'Bill dobara chalu: ' || r.ref);
    return jsonb_build_object('ok', true);
  end if;
  update public.crm_records set data = data || jsonb_build_object('cancelled', true, 'cancel_reason', why, 'cancelled_at', public.crm_iso_now(), 'cancelled_by', (s).name), updated_at = now() where id = r.id;
  perform public.crm_log(s, 'update', 'invoice', r.id, 'Bill cancel (non-refundable): ' || r.ref || ' — ' || why);
  return jsonb_build_object('ok', true);
end $$;
do $g$ begin execute 'revoke all on function public.crm_bill_cancel(jsonb) from public'; execute 'grant execute on function public.crm_bill_cancel(jsonb) to anon, authenticated'; exception when undefined_object then null; end $g$;