-- =====================================================================================================
-- ROUND 40 — Customer flow ke har step ki alag permission + Projects me Net Metering permission
-- STAGING pe pehle chalayein. Live par tab jab aap kahen (backup ke baad). Dobara chalana safe hai.
-- Badlav:
--   1) crm_perm_catalog me naye keys: flow.step.1 ... flow.step.19 aur projects.netmetering (Team > Permission me tick honge).
--   2) Purane manager / staff ko sab step + Net Metering pehle jaisa hi milta rahega (default ON). Admin sab dekhta hai.
-- =====================================================================================================

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
 {"g":"Products","k":"stock.view","l":"Stock, reserve aur expiry report dekhe"},
 {"g":"Customer flow","k":"flow.step.1","l":"Step 1: Add Customer — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.2","l":"Step 2: Conversation — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.3","l":"Step 3: Quotation — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.4","l":"Step 4: Site Visit — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.5","l":"Step 5: Blueprint — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.6","l":"Step 6: Confirmation — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.7","l":"Step 7: Apply Process — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.8","l":"Step 8: Hand Over Technician — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.9","l":"Step 9: Start Installation — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.10","l":"Step 10: Verification / Commissioning — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.11","l":"Step 11: Net Metering — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.12","l":"Step 12: Finish Work — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.13","l":"Step 13: Subsidy Redeem — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.14","l":"Step 14: Send Demo / Files — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.15","l":"Step 15: Loan / Finance — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.16","l":"Step 16: Suggest / Referral — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.17","l":"Step 17: AMC / Maintenance — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.18","l":"Step 18: Complaint Status — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.19","l":"Step 19: Leads — dekhe aur badle"},
 {"g":"Projects","k":"projects.netmetering","l":"Projects me Net Metering step khole (customer ka)"}
]'::jsonb $$;

update public.crm_roles set perms = (
  select coalesce(jsonb_object_agg(k, true), '{}'::jsonb) from (
    select 'projects.netmetering' as k
    union all select 'flow.step.' || g from generate_series(1,19) g
  ) z
) || coalesce(perms, '{}'::jsonb) where role in ('manager', 'staff');

-- ============================================================================
-- ROUND 43 — purchase price zaroori, role-wise discount, online qty, template reserve (staging only)
-- ============================================================================
create or replace function public.crm_role_discount(r text) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(nullif((select data #>> array['disc_defaults', r] from public.crm_settings where id = 1), '')::numeric,
    case lower(coalesce(r, '')) when 'manager' then 5 when 'staff' then 2.5 else 0 end) $$;

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
    if not isnew then d := jsonb_set(d, '{store}', coalesce(old.data -> 'store', '{}'::jsonb) || (coalesce(d -> 'store', '{}'::jsonb) - 'status' - 'store_id' - 'reviewed_at')); end if;
    if isnew then d := jsonb_set(d, '{store}', (coalesce(d -> 'store', '{}'::jsonb) - 'store_id' - 'reviewed_at') || '{"status":"none"}'::jsonb); end if;
    d := public.crm_item_prep(isnew, case when isnew then null else old.data end, d);   -- Round 13: auto SKU (immutable), project line SKUs
    if coalesce(d ->> 'type', 'product') = 'product' then   -- Round 43: kharid rate (purchase price) zaroori
      if public.crm_num(d -> 'cost_price') > 0 then d := d - 'cost_missing';
      elsif isnew and public.crm_can(s, 'items.cost') and coalesce(d ->> 'cost_ok', '') <> 'true' then raise exception 'Kharid rate (purchase price) zaroori hai — pehle likhein';
      else d := d || '{"cost_missing":true}'::jsonb; end if;
    end if;
    d := d - 'cost_ok';
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
end $function$

;


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

-- public: what is left online for the given store product ids (Web Shop shows left_web, Store App shows left_app)
create or replace function public.sp_online_left(p_ids jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r record; out jsonb := '{}'::jsonb; st jsonb;
begin
  if jsonb_typeof(p_ids) <> 'array' or jsonb_array_length(p_ids) > 400 then return '{}'::jsonb; end if;
  for r in select c.id, c.data #>> '{store,store_id}' sid from public.crm_records c
            where c.kind = 'item' and c.deleted_at is null and c.data #> '{store,online}' is not null and (c.data #>> '{store,store_id}') in (select jsonb_array_elements_text(p_ids)) loop
    st := public.crm_online_state(r.id);
    out := out || jsonb_build_object(r.sid, jsonb_build_object('web', st -> 'left_web', 'app', st -> 'left_app'));
  end loop;
  return out;
end $$;
grant execute on function public.sp_online_left(jsonb) to anon, authenticated;

-- Admin panel: state of every online item + add more qty from inventory
create or replace function public.sp_admin_online_state(p_pass text) returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare r record; out jsonb := '{}'::jsonb; st jsonb;
begin
  perform public.sp_check(p_pass);
  for r in select c.id, c.data #>> '{store,store_id}' sid, c.title, coalesce(c.data ->> 'type', 'product') typ from public.crm_records c
            where c.kind = 'item' and c.deleted_at is null and c.data #> '{store,online}' is not null and coalesce(c.data #>> '{store,store_id}', '') <> '' loop
    st := public.crm_online_state(r.id);
    out := out || jsonb_build_object(r.sid, st || jsonb_build_object('crm_id', r.id, 'type', r.typ, 'name', r.title, 'free', case when r.typ = 'project' then null else public.crm_item_free(r.id, 'auto-store') end));
  end loop;
  return out;
end $$;
create or replace function public.sp_admin_online_add(p_pass text, p_store_id text, p_web numeric, p_app numeric) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare it public.crm_records;
begin
  perform public.sp_check(p_pass);
  select * into it from public.crm_records where kind = 'item' and deleted_at is null and (data #>> '{store,store_id}') = p_store_id and data #> '{store,online}' is not null order by id limit 1;
  if it.id is null then raise exception 'Ye product CRM ki online list me nahi hai'; end if;
  return public.crm__online_apply(it.id, 'add', p_web, p_app);
end $$;
revoke all on function public.sp_admin_online_state(text), public.sp_admin_online_add(text, text, numeric, numeric) from public;
grant execute on function public.sp_admin_online_state(text), public.sp_admin_online_add(text, text, numeric, numeric) to anon, authenticated;

-- shipped / cancelled orders change what is left: keep inventory holds in step
create or replace function public.sp_orders_online_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if new.status is distinct from old.status then
    for r in select distinct c.id from jsonb_array_elements(case when jsonb_typeof(new.data -> 'items') = 'array' then new.data -> 'items' else '[]'::jsonb end) i
              join public.crm_records c on c.kind = 'item' and c.deleted_at is null and (c.data #>> '{store,store_id}') = (i ->> 'id') and c.data #> '{store,online}' is not null loop
      perform public.crm_online_sync(r.id);
    end loop;
  end if;
  return new;
end $$;
drop trigger if exists sp_orders_online on public.sp_orders;
create trigger sp_orders_online after update of status on public.sp_orders for each row execute function public.sp_orders_online_trg();

-- deleting an item releases its online holds
create or replace function public.crm_item_online_cleanup_trg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.kind = 'item' and new.deleted_at is not null and old.deleted_at is null and new.data #> '{store,online}' is not null then
    update public.crm_records set data = jsonb_set(data, '{store}', coalesce(data -> 'store', '{}'::jsonb) - 'online') where id = new.id;
    perform public.crm_online_sync(new.id);
  end if;
  return null;
end $$;
drop trigger if exists crm_item_online_cleanup on public.crm_records;
create trigger crm_item_online_cleanup after update of deleted_at on public.crm_records for each row execute function public.crm_item_online_cleanup_trg();

drop function if exists public.sp_stock_guard(jsonb);
create or replace function public.sp_stock_guard(p_items jsonb, p_channel text default null) returns void language plpgsql security definer set search_path = public as $$
declare r record; it public.crm_records; res numeric; fr numeric; msg text := ''; i jsonb; oi public.crm_records; st jsonb; need numeric; lc numeric;
begin
  for r in select * from public.sp_order_need(p_items) order by item_id loop
    select * into it from public.crm_records where id = r.item_id and kind = 'item' and deleted_at is null for update;
    if it.id is null or not (it.data ? 'stock') or coalesce(it.data ->> 'stock', '') = '' then continue; end if;
    select coalesce(sum(z.qty), 0) into res from public.crm_reserves(null) z where z.item_id = it.id;
    fr := public.crm_num(it.data -> 'stock') - res - public.crm_holds_sum(it.data, false) - public.sp_online_held(it.id, null);
    if r.qty > fr + 0.0001 then
      msg := msg || coalesce(nullif(it.data ->> 'titleEn', ''), nullif(it.data ->> 'title', ''), nullif(it.data ->> 'name', ''), it.title, 'item') || ' (' || case when fr >= 1 then 'sirf ' || floor(fr) || ' bacha' else 'abhi stock mein nahi' end || '); ';
    end if;
  end loop;
  -- Round 44: online pool (web / app allocation) — products and templates linked to CRM with an online qty
  for i in select * from jsonb_array_elements(case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end) loop
    select * into oi from public.crm_records c where c.kind = 'item' and c.deleted_at is null and (c.data #>> '{store,store_id}') = (i ->> 'id') and c.data #> '{store,online}' is not null order by c.id limit 1 for update;
    if oi.id is null then continue; end if;
    st := public.crm_online_state(oi.id); need := greatest(public.crm_num(i -> 'qty'), 1);
    lc := case when p_channel = 'web' then (st ->> 'left_web')::numeric when p_channel = 'app' then (st ->> 'left_app')::numeric else (st ->> 'left_total')::numeric end;
    if need > lc + 0.0001 then
      msg := msg || coalesce(nullif(oi.data ->> 'titleEn', ''), nullif(oi.data ->> 'title', ''), nullif(oi.data ->> 'name', ''), oi.title, 'item') || ' (' || case when lc >= 1 then 'sirf ' || floor(lc) || ' bacha' else 'abhi stock mein nahi' end || '); ';
    end if;
  end loop;
  if msg <> '' then raise exception 'OUT_OF_STOCK: %', left(msg, 300); end if;
end $$;
revoke all on function public.sp_stock_guard(jsonb, text) from public, anon, authenticated;

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

  -- Round 24: same stock for Store App + Website Shop — last unit is held for the first order (server-side, cannot be bypassed)
  perform public.sp_stock_guard(p_order -> 'items', public.sp_order_channel(p_order));

  -- identity always comes from the account, never from the browser
  o := (p_order - 'token' - 'customer_id')
       || jsonb_build_object(
            'name', left(coalesce(nullif(trim(u.name), ''), trim(p_order->>'name')), 80),
            'phone', coalesce(u.mobile, ''),
            'customer_id', u.id::text,
            'login_method', 'email_otp',
            'payment_status', 'awaiting_payment', 'channel', public.sp_order_channel(p_order));

  if coalesce(trim(o->>'name'), '') = '' or coalesce(trim(o->>'phone'), '') = '' then
    raise exception 'Naam aur mobile account mein save karein';
  end if;

  o := o || jsonb_build_object('order_no', public.crm_next_no('order'));
  insert into public.sp_orders(data) values (o) returning id into new_id;
  perform public.sp_notify_admin('Naya order ' || (o->>'order_no') || ' — ' || (o->>'name'),
    '<p>Naya order aaya hai: <b>' || (o->>'order_no') || '</b></p><p>' || (o->>'name') || ' · ' || (o->>'phone') || '</p><p>Total: ₹' || (o->>'total') || ' — payment ka UTR aane par dobara notification milega. Admin panel mein dekhein.</p>');
  return new_id;
end $$;
revoke all on function public.sp_place_order(jsonb) from public;
grant execute on function public.sp_place_order(jsonb) to anon, authenticated;

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
    if coalesce(p ->> 'hold_id', '') like 'auto-%' then raise exception 'Ye reserve Online list se banta hai — wahin se hatayein / badlein'; end if;
    hs := coalesce((select jsonb_agg(h) from jsonb_array_elements(hs) h where h ->> 'id' <> coalesce(p ->> 'hold_id', '')), '[]'::jsonb);
  else raise exception 'Galat kaam'; end if;
  update public.crm_records set data = jsonb_set(data, '{holds}', hs), updated_at = now() where id = it.id;
  perform public.crm_log(s, 'edit', 'item', it.id, 'Stock ' || case when op = 'add' then 'reserve ' || qty || ' (' || tp || ')' else 'reserve release' end || ': ' || it.title);
  return jsonb_build_object('ok', true, 'holds', hs);
end $$;
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
end $function$

;


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
create or replace function public.crm_order_customer(p_data jsonb, p_oid bigint) returns bigint language plpgsql security definer set search_path = public as $$
declare mob text := public.crm_mobile(coalesce(p_data ->> 'phone', p_data ->> 'mobile', '')); nm text := left(trim(coalesce(p_data ->> 'name', '')), 120); pid bigint; items text;
        ad text := trim(coalesce(p_data ->> 'address', '')); ct text := trim(coalesce(p_data ->> 'city', '')); pin text := regexp_replace(coalesce(p_data ->> 'pincode', ''), '\D', '', 'g');
        em text := nullif(lower(trim(coalesce(p_data ->> 'email', ''))), '');
        tpl public.crm_records; ck text := 'product'; ptyp text; kwv text;
begin
  if mob !~ '^[6-9][0-9]{9}$' then return null; end if;
  if nm = '' then nm := 'Online customer ' || right(mob, 4); end if;
  select left(string_agg(coalesce(i ->> 'title', ''), ', '), 180) into items from jsonb_array_elements(case when jsonb_typeof(p_data -> 'items') = 'array' then p_data -> 'items' else '[]'::jsonb end) i;
  select c.* into tpl from jsonb_array_elements(case when jsonb_typeof(p_data -> 'items') = 'array' then p_data -> 'items' else '[]'::jsonb end) i
    join public.crm_records c on c.kind = 'item' and c.deleted_at is null and c.data ->> 'type' = 'project' and (c.data #>> '{store,store_id}') = (i ->> 'id') order by c.id limit 1;
  if tpl.id is not null then
    ck := 'project'; kwv := nullif(tpl.data ->> 'kw', '');
    ptyp := case when tpl.data ->> 'category' in ('Residential', 'Commercial', 'Industrial') then tpl.data ->> 'category' when tpl.data ->> 'category' like 'VFD%' then 'VFD' else null end;
  end if;
  select id into pid from public.crm_records where kind = 'party' and deleted_at is null and mobile = mob order by id limit 1;
  if pid is not null then
    -- purana customer: naya order usi ke record par (Dobara sampark) — kabhi doosra customer / lead nahi. Order = customer (stage).
    perform set_config('sp.stage_ok', '1', true);
    update public.crm_records set data = (case when coalesce(data -> 'inquiries', '[]'::jsonb) @> jsonb_build_array(jsonb_build_object('order_id', p_oid)) or jsonb_array_length(coalesce(data -> 'inquiries', '[]'::jsonb)) >= 60 then data
        else jsonb_set(data, '{inquiries}', coalesce(data -> 'inquiries', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('at', public.crm_iso_now(), 'source', 'Online Store order', 'order_id', p_oid,
          'note', 'Store order #' || p_oid || coalesce(' — ' || nullif(items, ''), '')))) end)
        || case when coalesce(data ->> 'type', 'customer') = 'supplier' then '{}'::jsonb else jsonb_build_object('stage', 'customer') end
        || case when ck = 'project' and coalesce(data ->> 'cust_kind', '') in ('', 'product') then jsonb_strip_nulls(jsonb_build_object('cust_kind', 'project', 'project_type', ptyp, 'kw', kwv)) else '{}'::jsonb end, updated_at = now()
      where id = pid;
    perform set_config('sp.stage_ok', '', true);
    return pid;
  end if;
  perform set_config('sp.order', '1', true);
  insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, due_at, data, search, created_by)
    values ('party', nm, mob, 'active', 0, null, null,
      jsonb_strip_nulls(jsonb_build_object('name', nm, 'mobile', mob, 'email', em, 'address', nullif(ad, ''), 'city', nullif(ct, ''), 'pincode', case when pin ~ '^[0-9]{6}$' then pin end,
        'type', 'customer', 'source', 'Online Store', 'cust_kind', ck, 'project_type', ptyp, 'kw', kwv, 'segment', 'b2c', 'interest', coalesce(nullif(items, ''), 'Online Store order'),
        'store_order_id', p_oid, 'intake', 'store', 'stage', 'customer')),
      lower(concat_ws(' ', nm, mob, ct)), 0)
    returning id into pid;
  perform set_config('sp.order', '', true);
  return pid;
end $$;

-- ============================================================================
-- ROUND 45 — HR role, All Staffs (HR details), Salary & Pay (-> Accounts Kharcha), Partners ke liye alag menu (staging only)
--   Naye permission: staff.view (directory), staff.manage (staff ID jode/badle, permission ke bina), staff.hr (HR details), salary.manage (salary/advance/pay)
--   Naya role: hr. Salary / bank / ID sirf staff.hr / salary.manage / Admin ko; baaki sirf directory (naam, role, mobile, designation).
-- ============================================================================
do $$ begin
  alter table public.crm_users drop constraint if exists crm_users_role_check;
  alter table public.crm_users add constraint crm_users_role_check check (role in ('admin','manager','staff','dealer','influencer','consumer','marketing','hr'));
end $$;
insert into public.crm_roles(role, perms) values ('hr', '{"staff.view":true,"staff.manage":true,"staff.hr":true,"salary.manage":true,"team.stats":true,"docs.view":true,"docs.upload":true}') on conflict (role) do nothing;
update public.crm_roles set perms = perms || '{"staff.view":true}'::jsonb where role in ('manager', 'staff') and not (perms ? 'staff.view');

create table if not exists public.crm_staff_hr (
  user_id    bigint primary key,
  hr         jsonb not null default '{}'::jsonb,
  sal        jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by bigint
);
create table if not exists public.crm_salary_pay (
  id         bigserial primary key,
  user_id    bigint not null,
  month      text not null check (month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  basic      numeric(12,2) not null default 0,
  allowance  numeric(12,2) not null default 0,
  bonus      numeric(12,2) not null default 0,
  deduction  numeric(12,2) not null default 0,
  adv_cut    numeric(12,2) not null default 0,
  net        numeric(12,2) not null check (net > 0),
  paid_on    date not null,
  mode       text not null default 'bank',
  note       text not null default '',
  expense_id bigint,
  created_by bigint,
  created_at timestamptz not null default now(),
  deleted_at timestamptz, deleted_by bigint, delete_reason text
);
create unique index if not exists crm_salary_pay_um on public.crm_salary_pay(user_id, month) where deleted_at is null;
create table if not exists public.crm_staff_adv (
  id         bigserial primary key,
  user_id    bigint not null,
  given_on   date not null,
  amount     numeric(12,2) not null check (amount > 0),
  mode       text not null default 'cash',
  note       text not null default '',
  expense_id bigint,
  created_by bigint,
  created_at timestamptz not null default now(),
  deleted_at timestamptz, deleted_by bigint, delete_reason text
);
alter table public.crm_staff_hr enable row level security;
alter table public.crm_salary_pay enable row level security;
alter table public.crm_staff_adv enable row level security;
revoke all on public.crm_staff_hr, public.crm_salary_pay, public.crm_staff_adv from anon, authenticated;

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
 {"g":"Products","k":"stock.view","l":"Stock, reserve aur expiry report dekhe"},
 {"g":"Customer flow","k":"flow.step.1","l":"Step 1: Add Customer — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.2","l":"Step 2: Conversation — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.3","l":"Step 3: Quotation — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.4","l":"Step 4: Site Visit — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.5","l":"Step 5: Blueprint — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.6","l":"Step 6: Confirmation — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.7","l":"Step 7: Apply Process — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.8","l":"Step 8: Hand Over Technician — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.9","l":"Step 9: Start Installation — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.10","l":"Step 10: Verification / Commissioning — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.11","l":"Step 11: Net Metering — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.12","l":"Step 12: Finish Work — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.13","l":"Step 13: Subsidy Redeem — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.14","l":"Step 14: Send Demo / Files — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.15","l":"Step 15: Loan / Finance — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.16","l":"Step 16: Suggest / Referral — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.17","l":"Step 17: AMC / Maintenance — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.18","l":"Step 18: Complaint Status — dekhe aur badle"},
 {"g":"Customer flow","k":"flow.step.19","l":"Step 19: Leads — dekhe aur badle"},
 {"g":"Projects","k":"projects.netmetering","l":"Projects me Net Metering step khole (customer ka)"},
 {"g":"Staff & HR","k":"staff.view","l":"All Staffs list dekhe (naam, role, mobile)"},
 {"g":"Staff & HR","k":"staff.manage","l":"Staff ID jode / badle (Manager, Staff) — permission badle bina"},
 {"g":"Staff & HR","k":"staff.hr","l":"Staff ki HR details dekhe / badle (job, qualification, bank, ID)"},
 {"g":"Staff & HR","k":"salary.manage","l":"Salary set kare, advance de, salary pay kare"}
]'::jsonb $$;

-- backup now includes the expenses ledger
create or replace function public.crm_backup(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pe text; part text := coalesce(p ->> 'part', 'meta');
  off int := greatest(coalesce((p ->> 'offset')::int, 0), 0); lim int; r jsonb; cnt jsonb := '{}'::jsonb; t text;
  parts text[] := array['crm_settings', 'crm_auth_admin', 'crm_roles', 'crm_users', 'crm_records', 'crm_counters', 'crm_activity', 'sp_store', 'sp_orders', 'sp_enquiries', 'crm_files', 'crm_expenses', 'sp_design_pay'];
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  pe := public.crm_auth_pin_check(public.crm_auth_find('admin', 'admin'), p ->> 'pin');
  if pe is not null then return jsonb_build_object('error', pe); end if;
  if part = 'meta' then
    foreach t in array parts loop
      if to_regclass('public.' || t) is not null then execute format('select count(*) from public.%I', t) into lim; cnt := cnt || jsonb_build_object(t, lim); end if;
    end loop;
    perform public.crm_log(s, 'backup', null, null, 'Poora backup download kiya');
    return jsonb_build_object('app', 'sunpowers-suite', 'format', 1, 'at', now(), 'by', (s).name, 'parts', to_jsonb(parts), 'counts', cnt);
  end if;
  if not (part = any (parts)) or to_regclass('public.' || part) is null then raise exception 'Galat hissa: %', part; end if;
  lim := case when part = 'crm_files' then 4 else 500 end;
  if part = 'crm_users' then
    select coalesce(jsonb_agg(to_jsonb(x) - 'pass_hash' - 'pin_hash' - 'a1' - 'a2' - 'pin_fail' - 'q_fail' order by x.id), '[]') into r from (select * from public.crm_users order by id offset off limit lim) x;
  elsif part = 'crm_auth_admin' then
    select coalesce(jsonb_agg(jsonb_build_object('email', email, 'email2', email2, 'q1', q1, 'q2', q2)), '[]') into r from public.crm_auth_admin where off = 0;
  elsif part = 'crm_settings' then
    select coalesce(jsonb_agg(jsonb_build_object('data', data, 'updated_at', updated_at)), '[]') into r from public.crm_settings where off = 0;
  elsif part = 'crm_files' then
    select coalesce(jsonb_agg(jsonb_build_object('id', id, 'rec_id', rec_id, 'mime', mime, 'size', size, 'b64', encode(data, 'base64')) order by id), '[]') into r from (select * from public.crm_files order by id offset off limit lim) x;
  else
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from (select * from public.%I order by 1 offset %s limit %s) x', part, off, lim) into r;
  end if;
  return jsonb_build_object('part', part, 'rows', r, 'next', case when jsonb_array_length(r) = lim and part not in ('crm_settings', 'crm_auth_admin') then off + lim end);
end $$;

create or replace function public.crm_role_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r text := p ->> 'role';
begin
  if not public.crm_is_admin(s) then raise exception 'Role permission sirf Admin badal sakta hai'; end if;
  if r not in ('manager', 'staff', 'dealer', 'influencer', 'hr') then raise exception 'Role galat hai'; end if;
  if jsonb_typeof(p -> 'perms') <> 'object' then raise exception 'Data galat hai'; end if;
  insert into public.crm_roles(role, perms) values (r, p -> 'perms') on conflict (role) do update set perms = excluded.perms;
  perform public.crm_log(s, 'role_edit', 'role', null, 'Role permission badli: ' || r);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.crm_user_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); u public.crm_users; full_ boolean; d jsonb := coalesce(p -> 'user', '{}'::jsonb); id_ bigint := nullif(d ->> 'id', '')::bigint;
        r text := lower(coalesce(d ->> 'role', '')); un text := lower(trim(coalesce(d ->> 'username', ''))); m text := public.crm_mobile(d ->> 'mobile'); code text; i int := 0;
begin
  full_ := public.crm_can(s, 'users.manage');
  if not full_ then perform public.crm_need(s, 'staff.manage'); end if;
  if r <> '' and r not in ('admin', 'manager', 'staff', 'dealer', 'influencer', 'consumer', 'marketing', 'hr') then raise exception 'Role galat hai'; end if;
  if not full_ then
    /* HR / staff.manage: sirf Manager & Staff ID; permission, commission, discount, password nahi badal sakte */
    if r <> '' and r not in ('manager', 'staff') then raise exception 'Aap sirf Manager ya Staff ID bana / badal sakte hain'; end if;
    d := d - 'perms' - 'meta' - 'password';
    if id_ is not null and coalesce((select role from public.crm_users where id = id_), '') not in ('manager', 'staff', 'marketing') then raise exception 'Is ID ko aap nahi badal sakte'; end if;
  end if;
  if r = 'admin' and not public.crm_is_admin(s) then raise exception 'Admin role sirf Admin de sakta hai'; end if;
  if id_ is null then
    if un !~ '^[a-z0-9_.@-]{3,40}$' or un = 'admin' then raise exception 'Username 3-40 akshar ka ho (a-z, 0-9, _ . - @)'; end if;
    if exists (select 1 from public.crm_users where username = un) then raise exception 'Ye username pehle se liya hua hai'; end if;
    if coalesce(d ->> 'password', '') <> '' and length(d ->> 'password') < 6 then raise exception 'Password kam se kam 6 akshar ka ho'; end if;
    if coalesce(trim(d ->> 'name'), '') = '' then raise exception 'Naam likhein'; end if;
    if coalesce(d ->> 'password', '') = '' and lower(trim(coalesce(d ->> 'email', ''))) !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Sahi email likhein — login ka OTP isi par jayega'; end if;
    if coalesce(d ->> 'email', '') <> '' and exists (select 1 from public.crm_users where lower(email) = lower(trim(d ->> 'email')) and role <> 'consumer') then raise exception 'Ye email pehle se kisi aur user ka hai'; end if;
    if r = '' then raise exception 'Role chunein'; end if;
    if r in ('dealer', 'influencer') then
      loop code := upper(left(r, 1)) || 'SP' || (100000 + floor(random() * 900000))::int::text;
        exit when not exists (select 1 from public.crm_users where ref_code = code); i := i + 1; if i > 20 then raise exception 'Dobara koshish karein'; end if; end loop;
    end if;
    insert into public.crm_users(role, username, name, mobile, email, pass_hash, status, ref_code, perms, meta)
    values (r, un, left(trim(d ->> 'name'), 80), m, lower(left(trim(coalesce(d ->> 'email', '')), 120)), case when coalesce(d ->> 'password', '') = '' then '' else crypt(d ->> 'password', gen_salt('bf')) end, coalesce(nullif(d ->> 'status', ''), 'active'), code,
      coalesce(d -> 'perms', '{}'::jsonb), coalesce(d -> 'meta', '{}'::jsonb)) returning * into u;
    perform public.crm_log(s, 'user_create', 'user', u.id, 'Naya user: ' || u.name || ' (' || u.role || ')');
  else
    select * into u from public.crm_users where id = id_;
    if u.id is null then raise exception 'User nahi mila'; end if;
    if u.role = 'admin' and not public.crm_is_admin(s) then raise exception 'Admin ko sirf Admin badal sakta hai'; end if;
    update public.crm_users set
      name = coalesce(nullif(trim(d ->> 'name'), ''), name),
      mobile = case when d ? 'mobile' then m else mobile end,
      email = case when d ? 'email' then lower(left(trim(coalesce(d ->> 'email', '')), 120)) else email end,
      email_ok = case when d ? 'email' and lower(trim(coalesce(d ->> 'email', ''))) <> lower(email) then false else email_ok end,
      role = case when r <> '' then r else role end,
      status = case when d ->> 'status' in ('active', 'pending', 'blocked') then d ->> 'status' else status end,
      perms = case when d ? 'perms' then coalesce(d -> 'perms', '{}'::jsonb) else perms end,
      meta = case when d ? 'meta' then coalesce(d -> 'meta', '{}'::jsonb) else meta end,
      pass_hash = case when length(coalesce(d ->> 'password', '')) >= 6 then crypt(d ->> 'password', gen_salt('bf')) else pass_hash end
    where id = id_ returning * into u;
    if coalesce(d ->> 'password', '') <> '' and length(d ->> 'password') < 6 then raise exception 'Password kam se kam 6 akshar ka ho'; end if;
    if u.status <> 'active' or length(coalesce(d ->> 'password', '')) >= 6 then delete from public.crm_sessions where user_id = u.id; end if;
    if u.ref_code is null and u.role in ('dealer', 'influencer') then
      loop code := upper(left(u.role, 1)) || 'SP' || (100000 + floor(random() * 900000))::int::text;
        exit when not exists (select 1 from public.crm_users where ref_code = code); end loop;
      update public.crm_users set ref_code = code where id = u.id returning * into u;
    end if;
    perform public.crm_log(s, 'user_edit', 'user', u.id, 'User badla: ' || u.name || ' (' || u.role || ', ' || u.status || ')');
  end if;
  return jsonb_build_object('id', u.id, 'username', u.username, 'role', u.role, 'status', u.status, 'ref_code', u.ref_code);
end $$;

create or replace function public.crm_users_list(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); full_ boolean; hrv boolean; dir_ boolean;
begin
  full_ := public.crm_can(s, 'users.manage');
  hrv := public.crm_can(s, 'staff.manage') or public.crm_can(s, 'staff.hr') or public.crm_can(s, 'salary.manage');
  dir_ := hrv or public.crm_can(s, 'staff.view');
  if not full_ and not dir_ and not (public.crm_can(s, 'leads.assign') or public.crm_can(s, 'reminders.assign') or public.crm_can(s, 'customers.assign') or public.crm_can(s, 'earnings.manage') or public.crm_can(s, 'team.stats') or public.crm_can(s, 'docs.folders')) then
    return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(case when full_ then jsonb_build_object('id', u.id, 'role', u.role, 'username', u.username, 'name', u.name, 'mobile', u.mobile, 'email', u.email, 'status', u.status,
        'ref_code', u.ref_code, 'perms', u.perms, 'meta', u.meta, 'created_at', u.created_at, 'last_seen', u.last_seen, 'designation', h.hr ->> 'designation')
      else jsonb_build_object('id', u.id, 'role', u.role, 'name', u.name, 'status', u.status, 'ref_code', u.ref_code)
        || case when dir_ and u.role in ('admin', 'manager', 'staff', 'hr', 'marketing') then jsonb_build_object('mobile', u.mobile, 'designation', h.hr ->> 'designation') else '{}'::jsonb end
        || case when hrv and u.role in ('admin', 'manager', 'staff', 'hr', 'marketing') then jsonb_build_object('email', u.email, 'username', u.username, 'last_seen', u.last_seen, 'created_at', u.created_at) else '{}'::jsonb end
      end order by u.role, u.name)
    from public.crm_users u left join public.crm_staff_hr h on h.user_id = u.id where u.role <> 'consumer' or full_), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------- staff HR details (job / personal / bank) + salary set
create or replace function public.crm_staff_get(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); id_ bigint := (p ->> 'id')::bigint; u public.crm_users; h public.crm_staff_hr;
        hr_ok boolean := public.crm_can(s, 'staff.hr'); sal_ok boolean := public.crm_can(s, 'salary.manage'); out jsonb;
begin
  if not (hr_ok or sal_ok or (s).uid = id_ or public.crm_can(s, 'staff.view') or public.crm_can(s, 'users.manage')) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  select * into u from public.crm_users where id = id_;
  if u.id is null or u.role in ('dealer', 'influencer', 'consumer') then raise exception 'Staff nahi mila'; end if;
  select * into h from public.crm_staff_hr where user_id = id_;
  out := jsonb_build_object('id', u.id, 'name', u.name, 'role', u.role, 'mobile', u.mobile, 'status', u.status,
    'hr', case when hr_ok then coalesce(h.hr, '{}'::jsonb) else jsonb_build_object('designation', coalesce(h.hr ->> 'designation', ''), 'reports_to', coalesce(h.hr ->> 'reports_to', ''), 'joining', coalesce(h.hr ->> 'joining', '')) end,
    'can_hr', hr_ok, 'can_sal', sal_ok);
  if hr_ok then out := out || jsonb_build_object('email', u.email, 'username', u.username, 'last_seen', u.last_seen); end if;
  if sal_ok then
    out := out || jsonb_build_object('sal', coalesce(h.sal, '{}'::jsonb),
      'adv_out', coalesce((select sum(amount) from public.crm_staff_adv where user_id = id_ and deleted_at is null), 0) - coalesce((select sum(adv_cut) from public.crm_salary_pay where user_id = id_ and deleted_at is null), 0),
      'pays', coalesce((select jsonb_agg(to_jsonb(z) - 'deleted_at' - 'deleted_by' - 'delete_reason' order by z.month desc) from (select * from public.crm_salary_pay where user_id = id_ and deleted_at is null order by month desc limit 12) z), '[]'::jsonb),
      'advs', coalesce((select jsonb_agg(to_jsonb(z) - 'deleted_at' - 'deleted_by' - 'delete_reason' order by z.given_on desc, z.id desc) from (select * from public.crm_staff_adv where user_id = id_ and deleted_at is null order by given_on desc, id desc limit 12) z), '[]'::jsonb));
  end if;
  return out;
end $$;

create or replace function public.crm_staff_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); id_ bigint := (p ->> 'id')::bigint; u public.crm_users; h public.crm_staff_hr;
        hk text[] := array['designation','department','reports_to','joining','emp_type','location','exit_date','qualification','experience','dob','gender','address','emergency_name','emergency_mobile','blood','bank_holder','bank_name','bank_acc','ifsc','upi','id_proof','notes'];
        nh jsonb := '{}'::jsonb; ns jsonb := '{}'::jsonb; k text; v numeric; sd jsonb := coalesce(p -> 'sal', '{}'::jsonb); hd jsonb := coalesce(p -> 'hr', '{}'::jsonb);
begin
  select * into u from public.crm_users where id = id_;
  if u.id is null or u.role in ('dealer', 'influencer', 'consumer') then raise exception 'Staff nahi mila'; end if;
  if u.role = 'admin' and not public.crm_is_admin(s) then raise exception 'Admin ki details sirf Admin badal sakta hai'; end if;
  select * into h from public.crm_staff_hr where user_id = id_;
  if p ? 'hr' then
    perform public.crm_need(s, 'staff.hr');
    foreach k in array hk loop if hd ? k then nh := nh || jsonb_build_object(k, left(trim(coalesce(hd ->> k, '')), 300)); end if; end loop;
    if coalesce(nh ->> 'joining', '') <> '' and (nh ->> 'joining') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Joining date galat hai'; end if;
    if coalesce(nh ->> 'emergency_mobile', '') <> '' then nh := nh || jsonb_build_object('emergency_mobile', public.crm_mobile(nh ->> 'emergency_mobile')); end if;
  end if;
  if p ? 'sal' then
    perform public.crm_need(s, 'salary.manage');
    foreach k in array array['monthly','allowance','deduction','pay_day'] loop
      if sd ? k then v := public.crm_num(sd -> k); if v < 0 or v > 10000000 then raise exception 'Amount galat hai'; end if;
        if k = 'pay_day' and (v < 0 or v > 31) then raise exception 'Pay day 1 se 31 ke beech ho'; end if;
        ns := ns || jsonb_build_object(k, v); end if;
    end loop;
    if sd ? 'note' then ns := ns || jsonb_build_object('note', left(trim(coalesce(sd ->> 'note', '')), 200)); end if;
  end if;
  insert into public.crm_staff_hr(user_id, hr, sal, updated_by) values (id_, coalesce(h.hr, '{}'::jsonb) || nh, coalesce(h.sal, '{}'::jsonb) || ns, (s).uid)
  on conflict (user_id) do update set hr = excluded.hr, sal = excluded.sal, updated_at = now(), updated_by = excluded.updated_by;
  if p ? 'hr' then perform public.crm_log(s, 'staff_hr', 'user', id_, 'HR details badli: ' || u.name); end if;
  if p ? 'sal' then perform public.crm_log(s, 'staff_salary', 'user', id_, 'Salary set / badli: ' || u.name); end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------- payroll (mahine ki salary) — pay karte hi Accounts > Kharcha me entry
create or replace function public.crm_payroll_list(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); m text := coalesce(nullif(p ->> 'month', ''), to_char(public.crm_today(), 'YYYY-MM'));
begin
  perform public.crm_need(s, 'salary.manage');
  if m !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Mahina galat hai'; end if;
  return jsonb_build_object('month', m, 'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'id', u.id, 'name', u.name, 'role', u.role, 'mobile', u.mobile, 'status', u.status, 'designation', h.hr ->> 'designation', 'joining', h.hr ->> 'joining', 'exit', h.hr ->> 'exit_date',
      'sal', coalesce(h.sal, '{}'::jsonb),
      'adv_out', coalesce((select sum(a.amount) from public.crm_staff_adv a where a.user_id = u.id and a.deleted_at is null), 0) - coalesce((select sum(z.adv_cut) from public.crm_salary_pay z where z.user_id = u.id and z.deleted_at is null), 0),
      'pay', (select to_jsonb(z) - 'deleted_at' - 'deleted_by' - 'delete_reason' from public.crm_salary_pay z where z.user_id = u.id and z.month = m and z.deleted_at is null)
    ) order by u.name)
    from public.crm_users u left join public.crm_staff_hr h on h.user_id = u.id
    where u.role in ('manager', 'staff', 'hr', 'marketing') and (u.status = 'active' or exists (select 1 from public.crm_salary_pay z where z.user_id = u.id and z.month = m and z.deleted_at is null))), '[]'::jsonb));
end $$;

create or replace function public.crm_salary_pay(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); uid_ bigint := (p ->> 'user_id')::bigint; m text := p ->> 'month'; u public.crm_users; h public.crm_staff_hr;
        basic numeric; allw numeric; ded numeric; bonus numeric := public.crm_num(p -> 'bonus'); xded numeric := public.crm_num(p -> 'deduction'); acut numeric := public.crm_num(p -> 'adv_cut');
        outst numeric; net numeric; d date; md text := left(coalesce(nullif(p ->> 'mode', ''), 'bank'), 20); ex public.crm_expenses; r public.crm_salary_pay;
begin
  perform public.crm_need(s, 'salary.manage');
  if m is null or m !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Mahina galat hai'; end if;
  select * into u from public.crm_users where id = uid_;
  if u.id is null or u.role not in ('manager', 'staff', 'hr', 'marketing') then raise exception 'Is ID ki salary yahan se nahi hoti'; end if;
  select * into h from public.crm_staff_hr where user_id = uid_;
  basic := public.crm_num(h.sal -> 'monthly'); allw := public.crm_num(h.sal -> 'allowance'); ded := public.crm_num(h.sal -> 'deduction');
  if basic <= 0 then raise exception 'Pehle is staff ki monthly salary set karein'; end if;
  if bonus < 0 or xded < 0 or acut < 0 then raise exception 'Amount galat hai'; end if;
  if exists (select 1 from public.crm_salary_pay where user_id = uid_ and month = m and deleted_at is null) then raise exception 'Is mahine ki salary pehle hi di ja chuki hai'; end if;
  outst := coalesce((select sum(amount) from public.crm_staff_adv where user_id = uid_ and deleted_at is null), 0) - coalesce((select sum(adv_cut) from public.crm_salary_pay where user_id = uid_ and deleted_at is null), 0);
  if acut > outst then raise exception 'Advance sirf % baaki hai', outst; end if;
  net := round(basic + allw + bonus - ded - xded - acut, 2);
  if net <= 0 then raise exception 'Net salary zero se zyada honi chahiye'; end if;
  begin d := coalesce(nullif(p ->> 'paid_on', '')::date, public.crm_today()); exception when others then raise exception 'Tareekh galat hai'; end;
  if d > public.crm_today() + 1 or d < date '2015-01-01' then raise exception 'Tareekh galat hai'; end if;
  insert into public.crm_expenses(spent_on, category, vendor, amount, gst_amount, mode, note, created_by)
  values (d, 'Salary', left(u.name, 120), net, 0, md, 'Salary ' || m || coalesce(nullif(' — ' || left(trim(coalesce(p ->> 'note', '')), 200), ' — '), ''), (s).uid) returning * into ex;
  insert into public.crm_salary_pay(user_id, month, basic, allowance, bonus, deduction, adv_cut, net, paid_on, mode, note, expense_id, created_by)
  values (uid_, m, basic, allw, bonus, ded + xded, acut, net, d, md, left(trim(coalesce(p ->> 'note', '')), 200), ex.id, (s).uid) returning * into r;
  perform public.crm_log(s, 'salary_pay', 'user', uid_, 'Salary di: ' || u.name || ' (' || m || ')');
  return to_jsonb(r) - 'deleted_at' - 'deleted_by' - 'delete_reason';
end $$;

create or replace function public.crm_salary_undo(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_salary_pay; why text := left(trim(coalesce(p ->> 'reason', '')), 200);
begin
  perform public.crm_need(s, 'salary.manage');
  if length(why) < 3 then raise exception 'Wajah likhein'; end if;
  select * into r from public.crm_salary_pay where id = (p ->> 'id')::bigint and deleted_at is null;
  if r.id is null then raise exception 'Salary entry nahi mili'; end if;
  update public.crm_salary_pay set deleted_at = now(), deleted_by = (s).uid, delete_reason = why where id = r.id;
  update public.crm_expenses set deleted_at = now(), deleted_by = (s).uid, delete_reason = 'Salary wapas: ' || why where id = r.expense_id and deleted_at is null;
  perform public.crm_log(s, 'salary_undo', 'user', r.user_id, 'Salary entry hata di: ' || public.crm_uname(r.user_id) || ' (' || r.month || ') — ' || why);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.crm_staff_advance(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); uid_ bigint := (p ->> 'user_id')::bigint; u public.crm_users; a numeric := public.crm_num(p -> 'amount'); d date;
        md text := left(coalesce(nullif(p ->> 'mode', ''), 'cash'), 20); ex public.crm_expenses; r public.crm_staff_adv;
begin
  perform public.crm_need(s, 'salary.manage');
  select * into u from public.crm_users where id = uid_;
  if u.id is null or u.role not in ('manager', 'staff', 'hr', 'marketing') then raise exception 'Is ID ko advance yahan se nahi milta'; end if;
  if a <= 0 or a > 10000000 then raise exception 'Advance amount likhein'; end if;
  begin d := coalesce(nullif(p ->> 'given_on', '')::date, public.crm_today()); exception when others then raise exception 'Tareekh galat hai'; end;
  if d > public.crm_today() + 1 or d < date '2015-01-01' then raise exception 'Tareekh galat hai'; end if;
  insert into public.crm_expenses(spent_on, category, vendor, amount, gst_amount, mode, note, created_by)
  values (d, 'Staff advance', left(u.name, 120), round(a, 2), 0, md, left(trim(coalesce(p ->> 'note', '')), 200), (s).uid) returning * into ex;
  insert into public.crm_staff_adv(user_id, given_on, amount, mode, note, expense_id, created_by) values (uid_, d, round(a, 2), md, left(trim(coalesce(p ->> 'note', '')), 200), ex.id, (s).uid) returning * into r;
  perform public.crm_log(s, 'staff_advance', 'user', uid_, 'Advance diya: ' || u.name);
  return to_jsonb(r) - 'deleted_at' - 'deleted_by' - 'delete_reason';
end $$;

create or replace function public.crm_my_pay(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token');
begin
  if (s).uid is null or (s).uid = 0 then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'month', z.month, 'basic', z.basic, 'allowance', z.allowance, 'bonus', z.bonus, 'deduction', z.deduction, 'adv_cut', z.adv_cut, 'net', z.net, 'paid_on', z.paid_on, 'mode', z.mode) order by z.month desc)
    from (select * from public.crm_salary_pay where user_id = (s).uid and deleted_at is null order by month desc limit 24) z), '[]'::jsonb);
end $$;

grant execute on function public.crm_staff_get(jsonb), public.crm_staff_save(jsonb), public.crm_payroll_list(jsonb), public.crm_salary_pay(jsonb), public.crm_salary_undo(jsonb), public.crm_staff_advance(jsonb), public.crm_my_pay(jsonb) to anon, authenticated;

-- ============================================================================
-- ROUND 46 — Customer flow: "Confirmation" (step 6) ab har flow me (Project, Product, Service) — pehle bar me hamesha grey dikhta tha (staging only)
--   Confirmation quotation Accept hote hi apne aap lagta hai (pehle jaisa). Bas ab wo flow ki list me hai, isliye bar me sahi dikhta hai.
--   AMC only / Site visit only me Confirmation nahi (wahan quotation hi nahi). Dobara chalana safe hai.
-- ============================================================================
create or replace function public.crm_wf_flow(ct text) returns int[] language sql immutable as $$
  select case
    when ct = 'Items only'  then array[19,1,2,14,3,6,12,16,18]                               -- Product customer
    when ct = 'Service'     then array[19,1,2,3,6,4,12,17,16,18]                             -- Service customer (cleaning, AMC, repair, shifting, audit)
    when ct = 'AMC only'        then array[19,1,2,17]                                        -- only a Maintenance / AMC plan
    when ct = 'Site visit only' then array[19,1,2,4]                                         -- only a Site Visit
    when ct = 'Residential' then array[19,1,2,14,3,4,5,6,7,15,8,9,10,11,12,13,16,17,18]      -- Project, subsidy applies
    else                         array[19,1,2,14,3,4,5,6,7,15,8,9,10,11,12,16,17,18] end $$;

-- ============================================================================
-- ROUND 47 — Customer flow steps 14-18 records, commission->salary, attendance+leave, store admin->CRM item, ek hi price har jagah.
--   Staging par chalayein. Dobara chalana safe hai (create or replace / if not exists).
-- ============================================================================

-- =====================================================================================================
-- ROUND 47 / A — Customer flow steps 15 (Loan), 16 (Referral), 18 (Complaint) ke apne records; 17 (AMC) renewal yaad
--   Table crm_flow_rec: ek job (quotation) ke loan / referral / complaint ticket. Sab RPC se (RLS band).
--   Loan Disbursed -> step 15 apne aap ✓, Cash -> "lagu nahi". Referral -> Lead banti hai + step 16 ✓.
--   Complaint ticket -> Aaj ke kaam me reminder; sab Resolved -> step 18 ✓. AMC plan -> renewal ki yaad.
-- Staging pe pehle chalayein. Dobara chalana safe.
-- =====================================================================================================
create table if not exists public.crm_flow_rec (
  id          bigserial primary key,
  kind        text not null check (kind in ('loan', 'referral', 'complaint')),
  quote_id    bigint not null,
  party_id    bigint,
  no          text,
  status      text not null default '',
  data        jsonb not null default '{}'::jsonb,
  hist        jsonb not null default '[]'::jsonb,
  rem_id      bigint,
  created_by  bigint,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz, deleted_by bigint
);
create index if not exists crm_flow_rec_q on public.crm_flow_rec (quote_id, kind) where deleted_at is null;
create index if not exists crm_flow_rec_p on public.crm_flow_rec (party_id) where deleted_at is null;
alter table public.crm_flow_rec enable row level security;

create or replace function public.crm_fr_step(k text) returns int language sql immutable as $$ select case k when 'loan' then 15 when 'referral' then 16 when 'complaint' then 18 else null end $$;

-- writes step n on a quotation (only when not there yet). Same switch as crm_wf_set (sp.wf)
create or replace function public.crm__wf_put(p_qid bigint, n int, p_by text, p_info jsonb, p_note text, p_skip boolean default false) returns void language plpgsql security definer set search_path = public as $$
declare q public.crm_records; prev text := coalesce(current_setting('sp.wf', true), ''); e jsonb;
begin
  select * into q from public.crm_records where id = p_qid and kind = 'quote' and deleted_at is null; if q.id is null then return; end if;
  if not (n = any (public.crm_wf_flow_of(q))) or (q.data -> 'wf') ? n::text then return; end if;
  e := jsonb_build_object('at', public.crm_iso_now(), 'by', coalesce(p_by, ''), 'auto', false, 'note', left(coalesce(p_note, ''), 500));
  if p_skip then e := e || jsonb_build_object('skip', true); end if;
  if p_info is not null and p_info <> '{}'::jsonb then e := e || jsonb_build_object('info', p_info); end if;
  perform set_config('sp.wf', '1', true);
  update public.crm_records set data = data || jsonb_build_object('wf', coalesce(data -> 'wf', '{}'::jsonb) || jsonb_build_object(n::text, e)), updated_at = now() where id = q.id;
  perform set_config('sp.wf', prev, true);
end $$;

create or replace function public.crm_fr_row(r public.crm_flow_rec) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', r.id, 'kind', r.kind, 'quote_id', r.quote_id, 'party_id', r.party_id, 'no', r.no, 'status', r.status, 'data', r.data, 'hist', r.hist,
    'by', public.crm_uname(r.created_by), 'created_at', r.created_at, 'updated_at', r.updated_at) $$;

create or replace function public.crm_fr_list(p jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; k text := nullif(p ->> 'kind', ''); out jsonb := '[]'::jsonb; r public.crm_flow_rec;
begin
  select * into q from public.crm_records where id = nullif(p ->> 'quote_id', '')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  for r in select * from public.crm_flow_rec where quote_id = q.id and deleted_at is null and (k is null or kind = k) order by id desc loop
    if public.crm_wf_can(s, public.crm_fr_step(r.kind), 'view') then out := out || jsonb_build_array(public.crm_fr_row(r)); end if;
  end loop;
  return out;
end $$;

create or replace function public.crm_fr_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; pt public.crm_records; r public.crm_flow_rec; k text := p ->> 'kind'; n int; d jsonb := coalesce(p -> 'data', '{}'::jsonb);
        st text := left(trim(coalesce(p ->> 'status', '')), 30); note text := left(trim(coalesce(p ->> 'note', '')), 300); isnew boolean; w jsonb; lid bigint; lerr text := ''; cnt int; asg bigint; remid bigint; mob text; ino jsonb; due date;
        amt numeric; open_n int;
begin
  if k not in ('loan', 'referral', 'complaint') then raise exception 'Galat prakar'; end if;
  n := public.crm_fr_step(k);
  select * into q from public.crm_records where id = nullif(p ->> 'quote_id', '')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if not (n = any (public.crm_wf_flow_of(q))) then raise exception 'Ye step is customer ke liye nahi hai'; end if;
  if not public.crm_wf_can(s, n, 'edit') then raise exception 'Is step ko badalne ki permission nahi hai — Admin se allow karwayein'; end if;
  w := coalesce(q.data -> 'wf', '{}'::jsonb);
  if not (w ? '6') then raise exception 'Pehle quotation Confirm hona chahiye'; end if;
  select * into pt from public.crm_records where id = q.party_id and kind = 'party';
  if nullif(p ->> 'id', '') is not null then
    select * into r from public.crm_flow_rec where id = (p ->> 'id')::bigint and quote_id = q.id and kind = k and deleted_at is null;
    if r.id is null then raise exception 'Record nahi mila'; end if;
    isnew := false;
  elsif k = 'loan' then
    select * into r from public.crm_flow_rec where quote_id = q.id and kind = 'loan' and deleted_at is null order by id desc limit 1;
    isnew := r.id is null;
  else isnew := true; end if;

  -- ---------------- LOAN: ek job ka ek loan record
  if k = 'loan' then
    d := jsonb_build_object('pay_mode', left(trim(coalesce(d ->> 'pay_mode', '')), 20), 'bank', left(trim(coalesce(d ->> 'bank', '')), 80), 'loan_amount', public.crm_num(d -> 'loan_amount'),
      'apply_date', left(coalesce(d ->> 'apply_date', ''), 10), 'sanction_amount', public.crm_num(d -> 'sanction_amount'), 'disbursed_amount', public.crm_num(d -> 'disbursed_amount'),
      'disbursed_on', left(coalesce(d ->> 'disbursed_on', ''), 10), 'loan_ref', left(trim(coalesce(d ->> 'loan_ref', '')), 60),
      'payment_id', coalesce(nullif(d ->> 'payment_id', ''), case when r.id is null then null else r.data ->> 'payment_id' end));
    if d ->> 'pay_mode' not in ('Cash', 'Loan', 'Mixed') then raise exception 'Payment tarika chunein (Cash / Loan / Mixed)'; end if;
    if d ->> 'pay_mode' = 'Cash' then st := 'cash';
    else
      if st not in ('Applied', 'Sanctioned', 'Disbursed', 'Rejected') then raise exception 'Loan ka stage chunein (Applied / Sanctioned / Disbursed / Rejected)'; end if;
      if (d ->> 'bank') = '' then raise exception 'Bank ka naam likhein'; end if;
      if public.crm_num(d -> 'loan_amount') <= 0 then raise exception 'Loan amount likhein'; end if;
      if st = 'Disbursed' and public.crm_num(d -> 'disbursed_amount') <= 0 then raise exception 'Disburse hui rakam likhein'; end if;
    end if;
  -- ---------------- REFERRAL
  elsif k = 'referral' then
    amt := public.crm_num(d -> 'reward_amount'); if amt < 0 then amt := 0; end if;
    mob := public.crm_mobile(coalesce(d ->> 'referred_mobile', ''));
    d := jsonb_build_object('ref_type', case when d ->> 'ref_type' in ('customer', 'partner', 'other') then d ->> 'ref_type' else 'other' end,
      'referrer_name', left(trim(coalesce(d ->> 'referrer_name', '')), 120), 'referrer_mobile', public.crm_mobile(coalesce(d ->> 'referrer_mobile', '')), 'referrer_party', nullif(d ->> 'referrer_party', ''), 'referrer_user', nullif(d ->> 'referrer_user', ''),
      'referred_name', left(trim(coalesce(d ->> 'referred_name', '')), 120), 'referred_mobile', mob, 'referred_note', left(trim(coalesce(d ->> 'referred_note', '')), 200),
      'reward_amount', amt, 'reward_note', left(trim(coalesce(d ->> 'reward_note', '')), 200), 'lead_id', case when isnew then null else r.data -> 'lead_id' end, 'earning_id', case when isnew then null else r.data -> 'earning_id' end);
    if (d ->> 'referrer_name') = '' then raise exception 'Refer karne wale ka naam likhein'; end if;
    if (d ->> 'referred_name') = '' then raise exception 'Jisko refer kiya uska naam likhein'; end if;
    if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Jisko refer kiya uska sahi 10 ank ka mobile likhein'; end if;
    if st not in ('none', 'due', 'paid') then st := case when amt > 0 then 'due' else 'none' end; end if;
    if amt <= 0 then st := 'none'; end if;
  -- ---------------- COMPLAINT
  else
    d := jsonb_build_object('issue', left(trim(coalesce(d ->> 'issue', '')), 300), 'brand', left(trim(coalesce(d ->> 'brand', '')), 80), 'serial', left(trim(coalesce(d ->> 'serial', '')), 60),
      'handler', case when d ->> 'handler' in ('Installer', 'Dealer', 'Manufacturer') then d ->> 'handler' else 'Installer' end, 'priority', case when d ->> 'priority' = 'Urgent' then 'Urgent' else 'Normal' end,
      'c_date', coalesce(nullif(left(coalesce(d ->> 'c_date', ''), 10), ''), public.crm_today()::text), 'assigned_to', nullif(d ->> 'assigned_to', ''), 'ticket_ref', left(trim(coalesce(d ->> 'ticket_ref', '')), 60),
      'resolution', left(trim(coalesce(d ->> 'resolution', '')), 300));
    if length(d ->> 'issue') < 3 then raise exception 'Samasya likhein (kam se kam 3 akshar)'; end if;
    if st not in ('Open', 'In progress', 'Resolved') then st := 'Open'; end if;
    if st = 'Resolved' and (d ->> 'resolution') = '' then raise exception 'Kaise solve hua — "Hal" likhein'; end if;
  end if;

  -- ---------------- save
  if isnew then
    if k = 'complaint' then
      perform pg_advisory_xact_lock(4747);
      select count(*) + 1 into cnt from public.crm_flow_rec where kind = 'complaint';
      insert into public.crm_flow_rec(kind, quote_id, party_id, no, status, data, hist, created_by)
        values (k, q.id, q.party_id, 'TKT-' || to_char(now() at time zone 'Asia/Kolkata', 'YY') || '-' || lpad(cnt::text, 4, '0'), st, d,
          jsonb_build_array(jsonb_build_object('at', public.crm_iso_now(), 'by', (s).name, 'status', st, 'note', coalesce(nullif(note, ''), 'Ticket bana'))), (s).uid) returning * into r;
    else
      insert into public.crm_flow_rec(kind, quote_id, party_id, no, status, data, hist, created_by)
        values (k, q.id, q.party_id, null, st, d, jsonb_build_array(jsonb_build_object('at', public.crm_iso_now(), 'by', (s).name, 'status', st, 'note', coalesce(nullif(note, ''), 'Jaankari darj'))), (s).uid) returning * into r;
    end if;
  else
    update public.crm_flow_rec set data = case when k = 'complaint' then d else d end, status = st, updated_at = now(),
      hist = case when status is distinct from st or note <> '' then hist || jsonb_build_array(jsonb_build_object('at', public.crm_iso_now(), 'by', (s).name, 'status', st, 'note', note)) else hist end
      where id = r.id returning * into r;
  end if;

  -- ---------------- side effects
  if k = 'loan' then
    -- Cash se Loan/Mixed par badla to purana "lagu nahi" hata do (tabhi stage ke hisab se step chalega)
    if st <> 'cash' and (w -> '15' ->> 'skip') = 'true' and (w -> '15' ->> 'note') like 'Cash payment%' then
      perform set_config('sp.wf', '1', true);
      update public.crm_records set data = jsonb_set(data, '{wf}', (data -> 'wf') - '15'), updated_at = now() where id = q.id;
      perform set_config('sp.wf', '', true);
    end if;
    if st = 'cash' then
      perform public.crm__wf_put(q.id, 15, (s).name, jsonb_build_object('pay_mode', 'Cash'), 'Cash payment — loan lagu nahi', true);
    elsif st = 'Disbursed' then
      perform public.crm__wf_put(q.id, 15, (s).name, jsonb_build_object('pay_mode', d ->> 'pay_mode', 'bank', d ->> 'bank', 'loan_amount', (d ->> 'loan_amount'), 'loan_status', 'Disbursed', 'loan_ref', d ->> 'loan_ref'), 'Loan disburse ho gaya', false);
    end if;
  elsif k = 'referral' then
    if isnew then
      begin
        lid := (public.crm_save(jsonb_build_object('token', p ->> 'token', 'kind', 'lead', 'data', jsonb_build_object('name', d ->> 'referred_name', 'mobile', d ->> 'referred_mobile', 'source', 'Referral',
                 'note', 'Refer kiya: ' || (d ->> 'referrer_name') || ' (customer: ' || coalesce(pt.title, '') || ')' || case when (d ->> 'referred_note') <> '' then ' — ' || (d ->> 'referred_note') else '' end)))
              ->> 'id')::bigint;
        update public.crm_flow_rec set data = data || jsonb_build_object('lead_id', lid) where id = r.id returning * into r;
      exception when others then
        lerr := sqlerrm;
        update public.crm_flow_rec set data = data || jsonb_build_object('lead_error', left(lerr, 160)) where id = r.id returning * into r;
      end;
    end if;
    perform public.crm__wf_put(q.id, 16, (s).name, jsonb_build_object('ref_name', d ->> 'referrer_name', 'ref_mobile', d ->> 'referrer_mobile'), 'Referral darj', false);
  else -- complaint: reminder in "Aaj ke kaam", step 18 when everything is resolved
    asg := coalesce(nullif(d ->> 'assigned_to', '')::bigint, nullif(q.assigned_to, 0), (s).uid);
    if st <> 'Resolved' then
      if r.rem_id is null or not exists (select 1 from public.crm_records where id = r.rem_id and status = 'open' and deleted_at is null) then
        insert into public.crm_records(kind, title, status, owner_id, assigned_to, party_id, mobile, due_at, data, search, created_by)
        values ('reminder', 'Complaint ' || r.no || ' — ' || coalesce(pt.title, '') || ': ' || left(d ->> 'issue', 60), 'open', (s).uid, asg, q.party_id, pt.mobile, public.crm_today(),
          jsonb_build_object('type', 'followup', 'complaint_id', r.id, 'ticket', r.no, 'party_name', coalesce(pt.title, ''), 'mobile', coalesce(pt.mobile, ''), 'note', left(d ->> 'issue', 200), 'priority', d ->> 'priority'),
          lower('complaint ' || r.no || ' ' || coalesce(pt.title, '')), (s).uid) returning id into remid;
        update public.crm_flow_rec set rem_id = remid where id = r.id returning * into r;
      end if;
    else
      if r.rem_id is not null then update public.crm_records set status = 'done', data = data || jsonb_build_object('done_on', public.crm_today()::text), updated_at = now() where id = r.rem_id and status = 'open'; end if;
      select count(*) into open_n from public.crm_flow_rec where quote_id = q.id and kind = 'complaint' and deleted_at is null and status <> 'Resolved';
      if open_n = 0 then
        perform public.crm__wf_put(q.id, 18, (s).name, jsonb_build_object('c_status', 'Resolved', 'c_issue', d ->> 'issue', 'c_ticket', r.no, 'c_handler', d ->> 'handler', 'c_brand', d ->> 'brand', 'c_serial', d ->> 'serial', 'c_date', d ->> 'c_date'), 'Saari complaint solve', false);
      end if;
    end if;
  end if;
  perform public.crm_log(s, 'workflow', 'quote', q.id, coalesce(q.ref, '') || ' — ' || (public.crm_wf_names())[n] || ': ' || k || coalesce(' ' || r.no, '') || ' (' || st || ')');
  return public.crm_fr_row(r);
end $$;

-- referral reward -> Commission page me entry (sirf Partner / staff user ko; Commission manage permission chahiye)
create or replace function public.crm_fr_reward(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_flow_rec; q public.crm_records; eid bigint; uid bigint := nullif(p ->> 'user_id', '')::bigint; e jsonb;
begin
  perform public.crm_need(s, 'earnings.manage');
  select * into r from public.crm_flow_rec where id = (p ->> 'id')::bigint and kind = 'referral' and deleted_at is null;
  if r.id is null then raise exception 'Record nahi mila'; end if;
  select * into q from public.crm_records where id = r.quote_id and kind = 'quote';
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if r.data ->> 'earning_id' is not null then raise exception 'Is referral ka commission pehle hi jud chuka hai'; end if;
  if public.crm_num(r.data -> 'reward_amount') <= 0 then raise exception 'Pehle reward ki rakam likhein'; end if;
  if uid is null or not exists (select 1 from public.crm_users where id = uid) then raise exception 'User chunein'; end if;
  e := public.crm_save(jsonb_build_object('token', p ->> 'token', 'kind', 'earning', 'owner_id', uid, 'party_id', r.party_id,
    'data', jsonb_build_object('title', 'Referral reward — ' || (r.data ->> 'referred_name') || ' (' || coalesce(q.ref, '') || ')', 'amount', public.crm_num(r.data -> 'reward_amount'), 'pay_on', public.crm_today() + 7,
      'note', 'Refer: ' || (r.data ->> 'referrer_name'), 'date', public.crm_today(), 'referral_id', r.id)));
  eid := (e ->> 'id')::bigint;
  update public.crm_flow_rec set data = data || jsonb_build_object('earning_id', eid), status = case when status = 'none' then 'due' else status end, updated_at = now(),
    hist = hist || jsonb_build_array(jsonb_build_object('at', public.crm_iso_now(), 'by', (s).name, 'status', 'due', 'note', 'Commission me jodi')) where id = r.id returning * into r;
  return public.crm_fr_row(r);
end $$;

create or replace function public.crm_fr_del(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_flow_rec; q public.crm_records;
begin
  select * into r from public.crm_flow_rec where id = (p ->> 'id')::bigint and deleted_at is null;
  if r.id is null then raise exception 'Record nahi mila'; end if;
  select * into q from public.crm_records where id = r.quote_id and kind = 'quote';
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if not (public.crm_is_admin(s) or (s).role = 'manager' or r.created_by = (s).uid) then raise exception 'Sirf Admin / Manager ya banane wala hata sakta hai'; end if;
  if length(trim(coalesce(p ->> 'reason', ''))) < 3 then raise exception 'Hatane ki wajah likhein'; end if;
  update public.crm_flow_rec set deleted_at = now(), deleted_by = (s).uid where id = r.id;
  if r.rem_id is not null then update public.crm_records set status = 'done', data = data || jsonb_build_object('done_on', public.crm_today()::text, 'cancelled', true), updated_at = now() where id = r.rem_id and status = 'open'; end if;
  perform public.crm_log(s, 'delete', 'quote', q.id, coalesce(q.ref, '') || ' — ' || r.kind || coalesce(' ' || r.no, '') || ' hataya: ' || left(p ->> 'reason', 120));
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.crm_fr_list(jsonb), public.crm_fr_save(jsonb), public.crm_fr_reward(jsonb), public.crm_fr_del(jsonb) from public;
grant execute on function public.crm_fr_list(jsonb), public.crm_fr_save(jsonb), public.crm_fr_reward(jsonb), public.crm_fr_del(jsonb) to anon, authenticated;


-- Round 47 / A2 — AMC plan dene par renewal ki yaad (Aaj ke kaam me)
CREATE OR REPLACE FUNCTION public.crm_maint_contract(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
  -- Round 47: purana renewal reminder band, naya contract ke liye 15 din pehle renewal yaad (one-time plan me nahi)
  update public.crm_records set status = 'done', data = data || jsonb_build_object('done_on', public.crm_today()::text, 'renewed', true), updated_at = now()
    where kind = 'reminder' and party_id = ex.id and status = 'open' and deleted_at is null and data ->> 'amc_renewal' = 'true';
  if months > 0 then
    insert into public.crm_records(kind, title, status, owner_id, assigned_to, party_id, mobile, due_at, data, search, created_by)
    values ('reminder', 'AMC renewal — ' || ex.title || ' (' || pname || ')', 'open', (s).uid, asg, ex.id, ex.mobile, ((start_ + make_interval(months => total * months))::date - 15),
      jsonb_build_object('type', 'call', 'amc_renewal', 'true', 'contract_id', cid, 'plan_name', pname, 'party_name', ex.title, 'mobile', coalesce(ex.mobile, ''), 'title', 'AMC renewal — ' || ex.title, 'note', 'Plan poora hone wala hai — renewal ke liye baat karein'),
      lower('amc renewal ' || ex.title || ' ' || pname), (s).uid);
  end if;
  perform public.crm_log(s, 'create', 'maintenance', ex.id, 'Maintenance & Audit: ' || pname || ' → ' || ex.title || ' (' || total || ' visits)');
  return jsonb_build_object('ok', true, 'contract_id', cid, 'visits', total, 'first_due', start_);
end $function$;


-- Round 47 (B): Commission -> Salary (apne aap). Staff ki "due" commission usi mahine ki salary me judti hai; pay par "paid", undo par wapas "due".
alter table public.crm_salary_pay add column if not exists commission numeric(12,2) not null default 0;
alter table public.crm_salary_pay add column if not exists comm_ids jsonb not null default '[]'::jsonb;

create or replace function public.crm_comm_due(uid_ bigint, m text) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('sum', coalesce(sum(r.amount), 0), 'n', count(r.id), 'ids', coalesce(jsonb_agg(r.id order by r.id), '[]'::jsonb),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'title', r.title, 'amount', r.amount, 'on', coalesce(r.due_at, r.created_at)::date) order by r.id), '[]'::jsonb))
  from public.crm_records r
  where r.kind = 'earning' and r.owner_id = uid_ and r.status = 'due' and r.deleted_at is null
    and coalesce(r.due_at, r.created_at)::date <= ((to_date(m || '-01', 'YYYY-MM-DD') + interval '1 month')::date - 1) $$;
revoke all on function public.crm_comm_due(bigint, text) from public;

create or replace function public.crm_payroll_list(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); m text := coalesce(nullif(p ->> 'month', ''), to_char(public.crm_today(), 'YYYY-MM'));
begin
  perform public.crm_need(s, 'salary.manage');
  if m !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Mahina galat hai'; end if;
  return jsonb_build_object('month', m, 'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'id', u.id, 'name', u.name, 'role', u.role, 'mobile', u.mobile, 'status', u.status, 'designation', h.hr ->> 'designation', 'joining', h.hr ->> 'joining', 'exit', h.hr ->> 'exit_date',
      'sal', coalesce(h.sal, '{}'::jsonb), 'comm', public.crm_comm_due(u.id, m),
      'adv_out', coalesce((select sum(a.amount) from public.crm_staff_adv a where a.user_id = u.id and a.deleted_at is null), 0) - coalesce((select sum(z.adv_cut) from public.crm_salary_pay z where z.user_id = u.id and z.deleted_at is null), 0),
      'pay', (select to_jsonb(z) - 'deleted_at' - 'deleted_by' - 'delete_reason' from public.crm_salary_pay z where z.user_id = u.id and z.month = m and z.deleted_at is null)
    ) order by u.name)
    from public.crm_users u left join public.crm_staff_hr h on h.user_id = u.id
    where u.role in ('manager', 'staff', 'hr', 'marketing') and (u.status = 'active' or exists (select 1 from public.crm_salary_pay z where z.user_id = u.id and z.month = m and z.deleted_at is null))), '[]'::jsonb));
end $$;

create or replace function public.crm_salary_pay(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); uid_ bigint := (p ->> 'user_id')::bigint; m text := p ->> 'month'; u public.crm_users; h public.crm_staff_hr;
        basic numeric; allw numeric; ded numeric; bonus numeric := public.crm_num(p -> 'bonus'); xded numeric := public.crm_num(p -> 'deduction'); acut numeric := public.crm_num(p -> 'adv_cut');
        outst numeric; net numeric; cm jsonb; cs numeric := 0; incl boolean := coalesce((p ->> 'include_comm')::boolean, true); d date; md text := left(coalesce(nullif(p ->> 'mode', ''), 'bank'), 20); ex public.crm_expenses; r public.crm_salary_pay;
begin
  perform public.crm_need(s, 'salary.manage');
  if m is null or m !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Mahina galat hai'; end if;
  select * into u from public.crm_users where id = uid_;
  if u.id is null or u.role not in ('manager', 'staff', 'hr', 'marketing') then raise exception 'Is ID ki salary yahan se nahi hoti'; end if;
  select * into h from public.crm_staff_hr where user_id = uid_;
  basic := public.crm_num(h.sal -> 'monthly'); allw := public.crm_num(h.sal -> 'allowance'); ded := public.crm_num(h.sal -> 'deduction');
  if basic <= 0 then raise exception 'Pehle is staff ki monthly salary set karein'; end if;
  if bonus < 0 or xded < 0 or acut < 0 then raise exception 'Amount galat hai'; end if;
  if exists (select 1 from public.crm_salary_pay where user_id = uid_ and month = m and deleted_at is null) then raise exception 'Is mahine ki salary pehle hi di ja chuki hai'; end if;
  outst := coalesce((select sum(amount) from public.crm_staff_adv where user_id = uid_ and deleted_at is null), 0) - coalesce((select sum(adv_cut) from public.crm_salary_pay where user_id = uid_ and deleted_at is null), 0);
  if acut > outst then raise exception 'Advance sirf % baaki hai', outst; end if;
  cm := public.crm_comm_due(uid_, m);
  if incl then cs := public.crm_num(cm -> 'sum'); end if;
  net := round(basic + allw + bonus + cs - ded - xded - acut, 2);
  if net <= 0 then raise exception 'Net salary zero se zyada honi chahiye'; end if;
  begin d := coalesce(nullif(p ->> 'paid_on', '')::date, public.crm_today()); exception when others then raise exception 'Tareekh galat hai'; end;
  if d > public.crm_today() + 1 or d < date '2015-01-01' then raise exception 'Tareekh galat hai'; end if;
  insert into public.crm_expenses(spent_on, category, vendor, amount, gst_amount, mode, note, created_by)
  values (d, 'Salary', left(u.name, 120), net, 0, md, 'Salary ' || m || case when cs > 0 then ' (commission ₹' || cs || ' sahit)' else '' end || coalesce(nullif(' — ' || left(trim(coalesce(p ->> 'note', '')), 200), ' — '), ''), (s).uid) returning * into ex;
  insert into public.crm_salary_pay(user_id, month, basic, allowance, bonus, deduction, adv_cut, net, paid_on, mode, note, expense_id, created_by, commission, comm_ids)
  values (uid_, m, basic, allw, bonus, ded + xded, acut, net, d, md, left(trim(coalesce(p ->> 'note', '')), 200), ex.id, (s).uid, cs, case when incl then coalesce(cm -> 'ids', '[]'::jsonb) else '[]'::jsonb end) returning * into r;
  if incl and cs > 0 then
    update public.crm_records set status = 'paid', data = data || jsonb_build_object('paid_on', public.crm_today()::text, 'salary_month', m, 'salary_id', r.id), updated_at = now()
      where kind = 'earning' and id in (select (x)::bigint from jsonb_array_elements_text(cm -> 'ids') x);
  end if;
  perform public.crm_log(s, 'salary_pay', 'user', uid_, 'Salary di: ' || u.name || ' (' || m || ')');
  return to_jsonb(r) - 'deleted_at' - 'deleted_by' - 'delete_reason';
end $$;

create or replace function public.crm_salary_undo(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_salary_pay; why text := left(trim(coalesce(p ->> 'reason', '')), 200);
begin
  perform public.crm_need(s, 'salary.manage');
  if length(why) < 3 then raise exception 'Wajah likhein'; end if;
  select * into r from public.crm_salary_pay where id = (p ->> 'id')::bigint and deleted_at is null;
  if r.id is null then raise exception 'Salary entry nahi mili'; end if;
  update public.crm_salary_pay set deleted_at = now(), deleted_by = (s).uid, delete_reason = why where id = r.id;
  update public.crm_records set status = 'due', data = (data - 'paid_on' - 'salary_month' - 'salary_id'), updated_at = now()
    where kind = 'earning' and status = 'paid' and (data ->> 'salary_id') = r.id::text;
  update public.crm_expenses set deleted_at = now(), deleted_by = (s).uid, delete_reason = 'Salary wapas: ' || why where id = r.expense_id and deleted_at is null;
  perform public.crm_log(s, 'salary_undo', 'user', r.user_id, 'Salary entry hata di: ' || public.crm_uname(r.user_id) || ' (' || r.month || ') — ' || why);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.crm_my_pay(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token');
begin
  if (s).uid is null or (s).uid = 0 then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'month', z.month, 'basic', z.basic, 'allowance', z.allowance, 'bonus', z.bonus, 'deduction', z.deduction, 'adv_cut', z.adv_cut, 'commission', z.commission, 'net', z.net, 'paid_on', z.paid_on, 'mode', z.mode) order by z.month desc)
    from (select * from public.crm_salary_pay where user_id = (s).uid and deleted_at is null order by month desc limit 24) z), '[]'::jsonb);
end $$;

grant execute on function public.crm_payroll_list(jsonb), public.crm_salary_pay(jsonb), public.crm_salary_undo(jsonb), public.crm_my_pay(jsonb) to anon, authenticated;


-- Round 47 (C): Attendance (hazri) + Leave. Staff khud check-in/out + leave maange; HR / Manager sabki hazri aur leave approve. Salary me sirf suggestion (deduction khud tay karein).
create table if not exists public.crm_attendance (
  id bigserial primary key, user_id bigint not null, day date not null,
  status text not null check (status in ('present', 'absent', 'half', 'leave', 'unpaid', 'holiday')),
  in_time text, out_time text, note text not null default '', leave_id bigint, marked_by bigint, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (user_id, day));
create table if not exists public.crm_leave (
  id bigserial primary key, user_id bigint not null, from_date date not null, to_date date not null, days numeric(5,1) not null default 1,
  kind text not null default 'Casual' check (kind in ('Casual', 'Sick', 'Paid', 'Unpaid')), reason text not null default '',
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  decided_by bigint, decided_at timestamptz, decision_note text not null default '', created_at timestamptz not null default now());
create index if not exists crm_leave_u on public.crm_leave (user_id, from_date);
create index if not exists crm_att_day on public.crm_attendance (day);
alter table public.crm_attendance enable row level security;
alter table public.crm_leave enable row level security;

create or replace function public.crm__att_mgr(s public.crm_ses) returns boolean language sql stable as $$ select public.crm_is_admin(s) or public.crm_can(s, 'staff.hr') or public.crm_can(s, 'staff.manage') $$;
create or replace function public.crm__att_staff(uid_ bigint) returns boolean language sql stable security definer set search_path = public as $$ select exists (select 1 from public.crm_users where id = uid_ and role in ('manager', 'staff', 'hr', 'marketing')) $$;
create or replace function public.crm__workdays(a date, b date) returns numeric language sql immutable as $$ select count(*)::numeric from generate_series(a, b, interval '1 day') g where extract(dow from g) <> 0 $$;

-- ek din ki hazri: self ('in' / 'out') ya manager ('set')
create or replace function public.crm_att_mark(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); act text := coalesce(nullif(p ->> 'action', ''), 'set'); uid_ bigint; d date; st text := coalesce(p ->> 'status', 'present'); r public.crm_attendance; nowt text := to_char(now() at time zone 'Asia/Kolkata', 'HH24:MI');
        it text := nullif(left(coalesce(p ->> 'in_time', ''), 5), ''); ot text := nullif(left(coalesce(p ->> 'out_time', ''), 5), ''); nt text := left(trim(coalesce(p ->> 'note', '')), 200);
begin
  if act in ('in', 'out') then
    uid_ := (s).uid;
    if uid_ is null or uid_ = 0 or not public.crm__att_staff(uid_) then raise exception 'Check-in sirf staff ID se hota hai'; end if;
    d := public.crm_today();
    select * into r from public.crm_attendance where user_id = uid_ and day = d;
    if act = 'in' then
      if r.id is not null and r.status in ('present', 'half') and r.in_time is not null then raise exception 'Aaj ka check-in ho chuka (%)', r.in_time; end if;
      if r.id is not null and r.status in ('leave', 'unpaid', 'holiday') then raise exception 'Aaj aapki % marked hai', r.status; end if;
      insert into public.crm_attendance(user_id, day, status, in_time, note, marked_by) values (uid_, d, 'present', nowt, nt, uid_)
        on conflict (user_id, day) do update set status = 'present', in_time = excluded.in_time, note = excluded.note, updated_at = now() returning * into r;
    else
      if r.id is null or r.in_time is null then raise exception 'Pehle check-in karein'; end if;
      if r.out_time is not null then raise exception 'Aaj ka check-out ho chuka (%)', r.out_time; end if;
      update public.crm_attendance set out_time = nowt, updated_at = now() where id = r.id returning * into r;
    end if;
    return to_jsonb(r);
  end if;
  -- manager marks
  if not public.crm__att_mgr(s) then raise exception 'Hazri lagane ki permission nahi hai'; end if;
  uid_ := nullif(p ->> 'user_id', '')::bigint;
  if uid_ is null or not public.crm__att_staff(uid_) then raise exception 'Staff chunein'; end if;
  begin d := (p ->> 'day')::date; exception when others then raise exception 'Tareekh galat hai'; end;
  if d is null or d > public.crm_today() or d < date '2020-01-01' then raise exception 'Tareekh galat hai (aage ki hazri nahi lagti)'; end if;
  if st = 'clear' then
    delete from public.crm_attendance where user_id = uid_ and day = d;
    perform public.crm_log(s, 'attendance', 'user', uid_, 'Hazri hatai: ' || public.crm_uname(uid_) || ' ' || d);
    return jsonb_build_object('ok', true, 'cleared', true);
  end if;
  if st not in ('present', 'absent', 'half', 'leave', 'unpaid', 'holiday') then raise exception 'Status galat hai'; end if;
  insert into public.crm_attendance(user_id, day, status, in_time, out_time, note, marked_by) values (uid_, d, st, it, ot, nt, (s).uid)
    on conflict (user_id, day) do update set status = excluded.status, in_time = excluded.in_time, out_time = excluded.out_time, note = excluded.note, marked_by = excluded.marked_by, updated_at = now() returning * into r;
  perform public.crm_log(s, 'attendance', 'user', uid_, 'Hazri: ' || public.crm_uname(uid_) || ' ' || d || ' — ' || st);
  return to_jsonb(r);
end $$;

-- aaj ki apni hazri + is mahine ka hisab (Profile card)
create or replace function public.crm_att_me(p jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); uid_ bigint := (s).uid; m text := to_char(public.crm_today(), 'YYYY-MM'); fr date; r public.crm_attendance;
begin
  if uid_ is null or uid_ = 0 or not public.crm__att_staff(uid_) then return jsonb_build_object('staff', false); end if;
  fr := to_date(m || '-01', 'YYYY-MM-DD');
  select * into r from public.crm_attendance where user_id = uid_ and day = public.crm_today();
  return jsonb_build_object('staff', true, 'today', case when r.id is null then null else to_jsonb(r) end, 'month', m,
    'sum', (select jsonb_build_object('present', count(*) filter (where status = 'present'), 'half', count(*) filter (where status = 'half'), 'absent', count(*) filter (where status = 'absent'),
        'leave', count(*) filter (where status = 'leave'), 'unpaid', count(*) filter (where status = 'unpaid')) from public.crm_attendance where user_id = uid_ and day >= fr and day < (fr + interval '1 month')::date));
end $$;

-- mahine ki poori hazri (manager: sab staff, staff: sirf apni)
create or replace function public.crm_att_month(p jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); m text := coalesce(nullif(p ->> 'month', ''), to_char(public.crm_today(), 'YYYY-MM')); fr date; mgr boolean := public.crm__att_mgr(s); me bigint := (s).uid;
begin
  if m !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Mahina galat hai'; end if;
  fr := to_date(m || '-01', 'YYYY-MM-DD');
  if not mgr and (me is null or me = 0) then raise exception 'Permission nahi hai'; end if;
  return jsonb_build_object('month', m, 'mgr', mgr, 'days', extract(day from (fr + interval '1 month' - interval '1 day'))::int, 'work', public.crm__workdays(fr, (fr + interval '1 month')::date - 1),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'role', u.role,
        'att', coalesce((select jsonb_object_agg(to_char(a.day, 'YYYY-MM-DD'), jsonb_build_object('s', a.status, 'in', a.in_time, 'out', a.out_time, 'n', a.note)) from public.crm_attendance a where a.user_id = u.id and a.day >= fr and a.day < (fr + interval '1 month')::date), '{}'::jsonb)) order by u.name)
      from public.crm_users u where u.role in ('manager', 'staff', 'hr', 'marketing') and (mgr or u.id = me) and (u.status = 'active' or exists (select 1 from public.crm_attendance a where a.user_id = u.id and a.day >= fr and a.day < (fr + interval '1 month')::date))), '[]'::jsonb));
end $$;

create or replace function public.crm_leave_apply(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); uid_ bigint := (s).uid; a date; b date; k text := coalesce(nullif(p ->> 'kind', ''), 'Casual'); dys numeric; r public.crm_leave; why text := left(trim(coalesce(p ->> 'reason', '')), 300);
begin
  if uid_ is null or uid_ = 0 or not public.crm__att_staff(uid_) then raise exception 'Leave sirf staff ID se maangi jaati hai'; end if;
  begin a := (p ->> 'from')::date; b := coalesce(nullif(p ->> 'to', '')::date, a); exception when others then raise exception 'Tareekh galat hai'; end;
  if a is null or b < a then raise exception 'Tareekh galat hai'; end if;
  if a < public.crm_today() - 7 then raise exception 'Itni purani tareekh ki leave nahi maangi ja sakti (7 din tak)'; end if;
  if b - a > 60 then raise exception 'Ek baar me 60 din se zyada ki leave nahi'; end if;
  if k not in ('Casual', 'Sick', 'Paid', 'Unpaid') then raise exception 'Leave ka prakar chunein'; end if;
  if length(why) < 3 then raise exception 'Leave ki wajah likhein'; end if;
  dys := public.crm__workdays(a, b);
  if dys <= 0 then raise exception 'In tareekhon me sirf Sunday (weekly off) hai'; end if;
  if exists (select 1 from public.crm_leave where user_id = uid_ and status in ('pending', 'approved') and from_date <= b and to_date >= a) then raise exception 'In tareekhon me aapki leave pehle se maangi hui hai'; end if;
  if p ? 'half' and (p ->> 'half') = 'true' and a = b then dys := 0.5; end if;
  insert into public.crm_leave(user_id, from_date, to_date, days, kind, reason) values (uid_, a, b, dys, k, why) returning * into r;
  perform public.crm_log(s, 'leave_apply', 'user', uid_, 'Leave maangi: ' || public.crm_uname(uid_) || ' ' || a || ' se ' || b || ' (' || k || ')');
  return to_jsonb(r);
end $$;

create or replace function public.crm_leave_list(p jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); mgr boolean := public.crm__att_mgr(s); me bigint := (s).uid; st text := nullif(p ->> 'status', ''); mine boolean := coalesce((p ->> 'mine')::boolean, false);
begin
  if not mgr and (me is null or me = 0) then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'user_id', l.user_id, 'name', public.crm_uname(l.user_id), 'from', l.from_date, 'to', l.to_date, 'days', l.days, 'kind', l.kind, 'reason', l.reason,
      'status', l.status, 'decided_by', public.crm_uname(l.decided_by), 'decided_at', l.decided_at, 'note', l.decision_note, 'created_at', l.created_at) order by (l.status = 'pending') desc, l.from_date desc, l.id desc)
    from (select * from public.crm_leave where (st is null or status = st) and ((mgr and not mine) or user_id = me) order by from_date desc, id desc limit 300) l), '[]'::jsonb);
end $$;

create or replace function public.crm_leave_decide(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_leave; act text := coalesce(p ->> 'action', ''); nt text := left(trim(coalesce(p ->> 'note', '')), 200); g date; stt text;
begin
  select * into r from public.crm_leave where id = (p ->> 'id')::bigint;
  if r.id is null then raise exception 'Leave nahi mili'; end if;
  if act = 'cancel' then
    if r.user_id <> (s).uid then raise exception 'Sirf apni leave cancel kar sakte hain'; end if;
    if r.status <> 'pending' then raise exception 'Sirf pending leave cancel hoti hai'; end if;
    update public.crm_leave set status = 'cancelled', decided_at = now() where id = r.id returning * into r;
    return to_jsonb(r);
  end if;
  if not public.crm__att_mgr(s) then raise exception 'Leave approve karne ki permission nahi hai'; end if;
  if r.status <> 'pending' then raise exception 'Ye leave pehle hi % ho chuki', r.status; end if;
  if r.user_id = (s).uid and not public.crm_is_admin(s) then raise exception 'Apni leave khud approve nahi kar sakte'; end if;
  if act = 'reject' and length(nt) < 3 then raise exception 'Reject karne ki wajah likhein'; end if;
  if act not in ('approve', 'reject') then raise exception 'Galat action'; end if;
  update public.crm_leave set status = case act when 'approve' then 'approved' else 'rejected' end, decided_by = (s).uid, decided_at = now(), decision_note = nt where id = r.id returning * into r;
  if act = 'approve' then
    stt := case when r.kind = 'Unpaid' then 'unpaid' else 'leave' end;
    for g in select x::date from generate_series(r.from_date, r.to_date, interval '1 day') x where extract(dow from x) <> 0 loop
      insert into public.crm_attendance(user_id, day, status, note, leave_id, marked_by) values (r.user_id, g, case when r.days = 0.5 then 'half' else stt end, r.kind || ' leave', r.id, (s).uid)
        on conflict (user_id, day) do update set status = excluded.status, note = excluded.note, leave_id = excluded.leave_id, marked_by = excluded.marked_by, updated_at = now() where public.crm_attendance.in_time is null;
    end loop;
  end if;
  perform public.crm_log(s, 'leave_' || act, 'user', r.user_id, 'Leave ' || act || ': ' || public.crm_uname(r.user_id) || ' ' || r.from_date || ' se ' || r.to_date);
  return to_jsonb(r);
end $$;

-- payroll list me hazri ka saar (salary pay ke time deduction suggest karne ke liye)
create or replace function public.crm_payroll_list(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); m text := coalesce(nullif(p ->> 'month', ''), to_char(public.crm_today(), 'YYYY-MM'));
begin
  perform public.crm_need(s, 'salary.manage');
  if m !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Mahina galat hai'; end if;
  return jsonb_build_object('month', m, 'work', public.crm__workdays(to_date(m || '-01', 'YYYY-MM-DD'), (to_date(m || '-01', 'YYYY-MM-DD') + interval '1 month')::date - 1), 'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'id', u.id, 'name', u.name, 'role', u.role, 'mobile', u.mobile, 'status', u.status, 'designation', h.hr ->> 'designation', 'joining', h.hr ->> 'joining', 'exit', h.hr ->> 'exit_date',
      'sal', coalesce(h.sal, '{}'::jsonb), 'comm', public.crm_comm_due(u.id, m),
      'att', (select jsonb_build_object('present', count(*) filter (where x.status = 'present'), 'half', count(*) filter (where x.status = 'half'), 'absent', count(*) filter (where x.status = 'absent'), 'leave', count(*) filter (where x.status = 'leave'), 'unpaid', count(*) filter (where x.status = 'unpaid'))
        from public.crm_attendance x where x.user_id = u.id and to_char(x.day, 'YYYY-MM') = m),
      'adv_out', coalesce((select sum(a.amount) from public.crm_staff_adv a where a.user_id = u.id and a.deleted_at is null), 0) - coalesce((select sum(z.adv_cut) from public.crm_salary_pay z where z.user_id = u.id and z.deleted_at is null), 0),
      'pay', (select to_jsonb(z) - 'deleted_at' - 'deleted_by' - 'delete_reason' from public.crm_salary_pay z where z.user_id = u.id and z.month = m and z.deleted_at is null)
    ) order by u.name)
    from public.crm_users u left join public.crm_staff_hr h on h.user_id = u.id
    where u.role in ('manager', 'staff', 'hr', 'marketing') and (u.status = 'active' or exists (select 1 from public.crm_salary_pay z where z.user_id = u.id and z.month = m and z.deleted_at is null))), '[]'::jsonb));
end $$;

grant execute on function public.crm_att_mark(jsonb), public.crm_att_me(jsonb), public.crm_att_month(jsonb), public.crm_leave_apply(jsonb), public.crm_leave_list(jsonb), public.crm_leave_decide(jsonb), public.crm_payroll_list(jsonb) to anon, authenticated;
revoke all on function public.crm__att_mgr(public.crm_ses), public.crm__att_staff(bigint), public.crm__workdays(date, date) from public;


-- Round 47 (D): Store Admin me naya product banate hi CRM Inventory me bhi (ek hi item, ek hi stock). Duplicate nahi banta.
create or replace function public.sp_admin_crm_cats(p_pass text) returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  perform public.sp_check(p_pass);
  return coalesce((select jsonb_agg(c order by c) from (select distinct trim(data ->> 'category') c from public.crm_records where kind = 'item' and deleted_at is null and coalesce(data ->> 'type', 'product') = 'product' and trim(coalesce(data ->> 'category', '')) <> '') z), '[]'::jsonb);
end $$;

create or replace function public.sp_admin_crm_item_add(p_pass text, p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare tok text := 'ADMADD-' || md5(random()::text || clock_timestamp()::text); r jsonb; iid bigint; ex public.crm_records;
        nm text := left(trim(coalesce(p ->> 'name', '')), 200); sid text := trim(coalesce(p ->> 'store_id', '')); gst numeric := coalesce(nullif(p ->> 'gst', '')::numeric, 18);
        incl numeric := public.crm_num(p -> 'price'); mrp numeric := public.crm_num(p -> 'mrp'); cost numeric := public.crm_num(p -> 'cost'); stk numeric := public.crm_num(p -> 'stock');
        w numeric := public.crm_num(p -> 'web'); a numeric := public.crm_num(p -> 'app'); cat text := left(trim(coalesce(p ->> 'category', '')), 80); dd jsonb;
begin
  perform public.sp_check(p_pass);
  if sid = '' then raise exception 'Store product id nahi mili'; end if;
  select * into ex from public.crm_records where kind = 'item' and deleted_at is null and (data #>> '{store,store_id}') = sid order by id limit 1;
  if ex.id is not null then return jsonb_build_object('ok', true, 'id', ex.id, 'existed', true); end if;
  if length(nm) < 3 then raise exception 'Product ka naam likhein (kam se kam 3 akshar)'; end if;
  if gst < 0 or gst > 40 then raise exception 'GST galat hai'; end if;
  if incl <= 0 then raise exception 'Selling price likhein'; end if;
  if cost <= 0 then raise exception 'Kharid rate (purchase price) zaroori hai — CRM Inventory ke liye'; end if;
  if cat = '' then raise exception 'CRM Category likhein / chunein'; end if;
  if stk < 0 or stk <> floor(stk) then raise exception 'Stock poori sankhya me likhein'; end if;
  if w < 0 or a < 0 or w <> floor(w) or a <> floor(a) then raise exception 'Online qty poori sankhya me likhein'; end if;
  if w + a > stk then raise exception 'Online qty (Web % + App %) stock % se zyada nahi ho sakti', w, a, stk; end if;
  dd := jsonb_build_object('type', 'product', 'name', nm, 'brand', left(trim(coalesce(p ->> 'brand', '')), 80), 'sku', left(trim(coalesce(p ->> 'sku', '')), 60), 'unit', coalesce(nullif(trim(p ->> 'unit'), ''), 'Nos'),
    'category', cat, 'price', round(incl / (1 + gst / 100), 2), 'gst', gst, 'mrp', case when mrp > incl then mrp else 0 end, 'cost_price', cost, 'stock', stk, 'desc', left(coalesce(p ->> 'desc', ''), 2000), 'hsn', left(trim(coalesce(p ->> 'hsn', '')), 10));
  insert into public.crm_sessions(token, user_id, role, expires_at) values (tok, 0, 'admin', now() + interval '2 minutes');
  begin
    r := public.crm_save(jsonb_build_object('token', tok, 'kind', 'item', 'data', dd));
  exception when others then delete from public.crm_sessions where token = tok; raise; end;
  delete from public.crm_sessions where token = tok;
  iid := (r ->> 'id')::bigint;
  update public.crm_records set data = jsonb_set(data, '{store}', coalesce(data -> 'store', '{}'::jsonb) || jsonb_build_object('status', 'published', 'store_id', sid, 'via', 'store_admin', 'reviewed_at', now(), 'note', '')), updated_at = now() where id = iid;
  if w + a > 0 then perform public.crm__online_apply(iid, 'set', w, a); end if;
  insert into public.crm_activity(user_id, user_name, role, action, kind, rec_id, summary) values (0, 'Store Admin', 'admin', 'store_add', 'item', iid, 'Store Admin se naya product CRM Inventory me juda: ' || nm || ' (stock ' || stk || ', online Web ' || w || ' + App ' || a || ')');
  return jsonb_build_object('ok', true, 'id', iid, 'ref', r ->> 'ref', 'sku', (select data ->> 'sku' from public.crm_records where id = iid));
end $$;
grant execute on function public.sp_admin_crm_cats(text), public.sp_admin_crm_item_add(text, jsonb) to anon, authenticated;


-- Round 47 (E): Ek hi price har jagah (CRM = Web Shop = Store App = order). CRM item hi authority; store product ka mrp / offer / gst CRM se hi tay hota hai.
create or replace function public.crm_price_incl(d jsonb) returns numeric language sql immutable as $$ select round(public.crm_num(d -> 'price') * (1 + public.crm_num(d -> 'gst') / 100)) $$;

-- store data me CRM se jude (published) products ke daam CRM ke hisab se laga do (admin ne kuch bhi bheja ho)
create or replace function public.sp__apply_crm_prices(d jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb; changed boolean := false;
begin
  if d is null or jsonb_typeof(d -> 'products') <> 'array' then return d; end if;
  select jsonb_agg(case when m.item_id is null then e.e else e.e || jsonb_build_object('mrp', m.nmrp, 'offer', m.noffer, 'gst', m.gst) end order by e.ord) into out_
  from jsonb_array_elements(d -> 'products') with ordinality as e(e, ord)
  left join lateral (
    select c.id as item_id, public.crm_num(c.data -> 'gst') as gst,
      case when public.crm_num(c.data -> 'mrp') > public.crm_price_incl(c.data) then public.crm_num(c.data -> 'mrp') else public.crm_price_incl(c.data) end as nmrp,
      case when public.crm_num(c.data -> 'mrp') > public.crm_price_incl(c.data) then public.crm_price_incl(c.data) else 0 end as noffer
    from public.crm_records c where c.kind = 'item' and c.deleted_at is null and (c.data #>> '{store,store_id}') = (e.e ->> 'id') and (c.data #>> '{store,status}') = 'published' and public.crm_price_incl(c.data) > 0
    order by c.id limit 1) m on true;
  return jsonb_set(d, '{products}', coalesce(out_, '[]'::jsonb));
end $$;

create or replace function public.sp_store_price_lock() returns trigger language plpgsql as $$
begin
  if NEW.id = 'main' then NEW.data := public.sp__apply_crm_prices(NEW.data); end if;
  return NEW;
end $$;
drop trigger if exists sp_store_price_lock on public.sp_store;
create trigger sp_store_price_lock before insert or update on public.sp_store for each row execute function public.sp_store_price_lock();

-- CRM me price / GST / MRP / store-link badalte hi store me turant wahi price (sirf jab kuch badla ho)
create or replace function public.crm_item_price_push_trg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (NEW.data #>> '{store,status}') = 'published' and coalesce(NEW.data #>> '{store,store_id}', '') <> '' and NEW.deleted_at is null
     and (TG_OP = 'INSERT' or (OLD.data -> 'price', OLD.data -> 'gst', OLD.data -> 'mrp', OLD.data #> '{store,store_id}', OLD.data #> '{store,status}') is distinct from (NEW.data -> 'price', NEW.data -> 'gst', NEW.data -> 'mrp', NEW.data #> '{store,store_id}', NEW.data #> '{store,status}')) then
    update public.sp_store set updated_at = now() where id = 'main';
  end if;
  return null;
end $$;
drop trigger if exists crm_item_price_push on public.crm_records;
create trigger crm_item_price_push after insert or update on public.crm_records for each row when (NEW.kind = 'item') execute function public.crm_item_price_push_trg();

-- order ke samay: browser jo daam bheje wo store / CRM ke daam se milna chahiye (purana ya galat daam nahi chalega)
create or replace function public.sp_price_guard(p_items jsonb, p_subtotal numeric default null) returns void language plpgsql stable security definer set search_path = public as $$
declare i jsonb; pr jsonb; exp_ numeric; got numeric; msg text := ''; sum_ numeric := 0; prods jsonb;
begin
  select data -> 'products' into prods from public.sp_store where id = 'main';
  if prods is null or jsonb_typeof(p_items) <> 'array' then return; end if;
  for i in select * from jsonb_array_elements(p_items) loop
    select e into pr from jsonb_array_elements(prods) e where e ->> 'id' = i ->> 'id' limit 1;
    if pr is null then continue; end if;
    exp_ := case when public.crm_num(pr -> 'offer') > 0 then public.crm_num(pr -> 'offer') else public.crm_num(pr -> 'mrp') end;
    got := public.crm_num(i -> 'price');
    sum_ := sum_ + exp_ * greatest(public.crm_num(i -> 'qty'), 1);
    if i ? 'price' and abs(got - exp_) > 0.5 then
      msg := msg || coalesce(nullif(pr ->> 'titleEn', ''), pr ->> 'title', 'item') || ' (ab ₹' || exp_ || '); ';
    end if;
  end loop;
  if msg <> '' then raise exception 'PRICE_CHANGED: %', left(msg, 300); end if;
  if p_subtotal is not null and p_subtotal > 0 and abs(p_subtotal - sum_) > 1.5 and sum_ > 0 and not exists (select 1 from jsonb_array_elements(p_items) x where not (x ? 'price')) then
    raise exception 'PRICE_CHANGED: Cart ka total badal gaya hai (ab ₹%)', sum_; end if;
end $$;
revoke all on function public.sp_price_guard(jsonb, numeric) from public;

CREATE OR REPLACE FUNCTION public.sp_place_order(p_order jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- Round 24: same stock for Store App + Website Shop — last unit is held for the first order (server-side, cannot be bypassed)
  perform public.sp_price_guard(p_order -> 'items', public.crm_num(p_order -> 'subtotal'));   -- Round 47: ek hi price har jagah
  perform public.sp_stock_guard(p_order -> 'items', public.sp_order_channel(p_order));

  -- identity always comes from the account, never from the browser
  o := (p_order - 'token' - 'customer_id')
       || jsonb_build_object(
            'name', left(coalesce(nullif(trim(u.name), ''), trim(p_order->>'name')), 80),
            'phone', coalesce(u.mobile, ''),
            'customer_id', u.id::text,
            'login_method', 'email_otp',
            'payment_status', 'awaiting_payment', 'channel', public.sp_order_channel(p_order));

  if coalesce(trim(o->>'name'), '') = '' or coalesce(trim(o->>'phone'), '') = '' then
    raise exception 'Naam aur mobile account mein save karein';
  end if;

  o := o || jsonb_build_object('order_no', public.crm_next_no('order'));
  insert into public.sp_orders(data) values (o) returning id into new_id;
  perform public.sp_notify_admin('Naya order ' || (o->>'order_no') || ' — ' || (o->>'name'),
    '<p>Naya order aaya hai: <b>' || (o->>'order_no') || '</b></p><p>' || (o->>'name') || ' · ' || (o->>'phone') || '</p><p>Total: ₹' || (o->>'total') || ' — payment ka UTR aane par dobara notification milega. Admin panel mein dekhein.</p>');
  return new_id;
end $function$;

-- ============================================================================
-- ROUND 48 — Pincode ke hisaab se delivery charge, Product / Service customer flow (4 naye step), customer ki ghoshna (OTP ki jagah), installation add-on.
--   Staging par chalayein. Dobara chalana safe hai (create or replace / if not exists).
-- ============================================================================

-- =====================================================================================================
-- ROUND 48 / A — Pincode ke hisaab se delivery charge (courier / khud), complete project par free, GST nahi.
--   Rules: sp_ship_rules (scope all / state / district / area / pin — pincode availability jaisa). Sabse khaas rule jeetta hai.
--   Charge = base_charge + (kg - base_kg ke upar har poore kg) x per_kg. Free: free_above se upar ya poora cart "complete project" (CRM template) ho.
--   Rule na mile to purani setting (settings.shipping: local / baaki / freeAbove) chalti hai. Order par server wapas hisaab karke check karta hai.
-- =====================================================================================================
create table if not exists public.sp_ship_rules (
  id          bigserial primary key,
  scope       text    not null check (scope in ('all', 'state', 'district', 'area', 'pin')),
  value       text    not null,
  mode        text    not null default 'courier' check (mode in ('self', 'courier')),
  courier     text    not null default '',
  base_charge numeric not null default 0 check (base_charge >= 0),
  base_kg     numeric not null default 5 check (base_kg >= 0),
  per_kg      numeric not null default 0 check (per_kg >= 0),
  free_above  numeric not null default 0 check (free_above >= 0),
  eta_min     int     not null default 0,
  eta_max     int     not null default 0,
  note        text    not null default '',
  updated_at  timestamptz not null default now(),
  unique (scope, value)
);
alter table public.sp_ship_rules enable row level security;

-- quote: public (anon bhi dekh sake: product page / cart). Sirf hisaab deta hai, kuch badalta nahi.
create or replace function public.sp_ship_quote(p_pin text, p_items jsonb, p_subtotal numeric default 0, p_pickup boolean default false)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare pin text := regexp_replace(coalesce(p_pin, ''), '\D', '', 'g'); st text; di text; r public.sp_ship_rules; sh jsonb; prods jsonb; it jsonb; pr jsonb;
        q numeric; kg numeric := 0; nsub numeric := 0; n_non int := 0; n_proj int := 0; ch numeric := 0; fr boolean := false; why text := 'rule'; known boolean := false;
        loc boolean; ct text; ok_pin boolean := pin ~ '^[1-9][0-9]{5}$';
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' then p_items := '[]'::jsonb; end if;
  if jsonb_array_length(p_items) > 300 then raise exception 'Cart bahut bada hai'; end if;
  select data -> 'products', data #> '{settings,shipping}' into prods, sh from public.sp_store where id = 'main';
  prods := coalesce(prods, '[]'::jsonb); sh := coalesce(sh, '{}'::jsonb);
  for it in select * from jsonb_array_elements(p_items) loop
    q := greatest(coalesce(public.crm_num(it -> 'qty'), 1), 0);
    select e into pr from jsonb_array_elements(prods) e where e ->> 'id' = it ->> 'id' limit 1;
    ct := null;
    if pr is not null and coalesce(pr ->> 'crm', '') ~ '^[0-9]+$' then
      select data ->> 'type' into ct from public.crm_records where id = (pr ->> 'crm')::bigint and kind = 'item';
    end if;
    if coalesce(ct, '') = 'project' or coalesce(pr ->> 'proj', '') = 'true' then n_proj := n_proj + 1;
    else
      n_non := n_non + 1; kg := kg + q * coalesce(public.crm_num(pr -> 'weight'), 0);
      nsub := nsub + q * coalesce(public.crm_num(it -> 'price'), 0);
    end if;
  end loop;
  if nsub <= 0 then nsub := greatest(coalesce(p_subtotal, 0), 0); end if;

  if p_pickup then
    return jsonb_build_object('ok', true, 'pin', pin, 'known', true, 'charge', 0, 'free', true, 'reason', 'pickup', 'mode', 'pickup', 'courier', '', 'eta_min', 0, 'eta_max', 0, 'kg', kg, 'gst', 0);
  end if;
  if n_non = 0 and n_proj > 0 then   -- poora cart complete project: delivery free (aur uspar GST bhi nahi)
    select * into r from public.sp_ship_rules where false;
    if ok_pin then
      select state_u, district_u into st, di from public.sp_pin_master where pincode = pin;
      select * into r from public.sp_ship_rules x where x.scope = 'all' or (x.scope = 'pin' and x.value = pin) or (x.scope = 'state' and st is not null and x.value = st)
         or (x.scope = 'district' and st is not null and x.value = st || '|' || di) or (x.scope = 'area' and exists (select 1 from public.sp_pin_areas a where a.name = x.value and pin = any (a.pins)))
       order by (case x.scope when 'pin' then 5 when 'area' then 4 when 'district' then 3 when 'state' then 2 else 1 end) desc limit 1;
    end if;
    return jsonb_build_object('ok', true, 'pin', pin, 'known', true, 'charge', 0, 'free', true, 'reason', 'project', 'mode', coalesce(r.mode, 'courier'), 'courier', coalesce(r.courier, ''),
                              'eta_min', coalesce(r.eta_min, 0), 'eta_max', coalesce(r.eta_max, 0), 'kg', 0, 'gst', 0);
  end if;

  if ok_pin then
    select state_u, district_u into st, di from public.sp_pin_master where pincode = pin;
    select * into r from public.sp_ship_rules x where x.scope = 'all' or (x.scope = 'pin' and x.value = pin) or (x.scope = 'state' and st is not null and x.value = st)
       or (x.scope = 'district' and st is not null and x.value = st || '|' || di) or (x.scope = 'area' and exists (select 1 from public.sp_pin_areas a where a.name = x.value and pin = any (a.pins)))
     order by (case x.scope when 'pin' then 5 when 'area' then 4 when 'district' then 3 when 'state' then 2 else 1 end) desc limit 1;
  end if;
  if r.id is not null then
    known := true; ch := r.base_charge + ceil(greatest(kg - r.base_kg, 0)) * r.per_kg;
    if r.free_above > 0 and nsub >= r.free_above then ch := 0; fr := true; why := 'above'; end if;
    if ch = 0 then fr := true; end if;
    return jsonb_build_object('ok', true, 'pin', pin, 'known', true, 'charge', round(ch), 'free', fr, 'reason', why, 'mode', r.mode, 'courier', r.courier, 'eta_min', r.eta_min, 'eta_max', r.eta_max, 'kg', kg, 'gst', 0, 'note', r.note);
  end if;
  -- koi rule nahi: purani setting (settings.shipping)
  if coalesce(sh ->> 'enabled', 'true') = 'false' then
    return jsonb_build_object('ok', true, 'pin', pin, 'known', true, 'charge', 0, 'free', true, 'reason', 'off', 'mode', 'courier', 'courier', '', 'eta_min', 0, 'eta_max', 0, 'kg', kg, 'gst', 0);
  end if;
  loc := ok_pin and exists (select 1 from regexp_split_to_table(coalesce(sh ->> 'localPins', ''), '[,\s]+') x where x <> '' and pin like x || '%');
  if coalesce(public.crm_num(sh -> 'freeAbove'), 0) > 0 and nsub >= public.crm_num(sh -> 'freeAbove') then
    ch := 0; fr := true; why := 'above'; known := ok_pin;
  elsif loc then ch := coalesce(public.crm_num(sh -> 'localCharge'), 0); known := true; why := 'local';
  else ch := coalesce(public.crm_num(sh -> 'otherCharge'), 0); known := ok_pin; why := 'other'; end if;
  return jsonb_build_object('ok', true, 'pin', pin, 'known', known, 'charge', round(ch), 'free', ch = 0, 'reason', why, 'mode', case when loc then 'self' else 'courier' end, 'courier', '', 'eta_min', 0, 'eta_max', 0, 'kg', kg, 'gst', 0);
end $$;

-- server guard: browser kam delivery charge bhej kar bach nahi sakta
create or replace function public.sp_ship_guard(p_order jsonb) returns void language plpgsql stable security definer set search_path = public as $$
declare qt jsonb; pick boolean := coalesce(p_order ->> 'pickup', 'false') = 'true'; pin text := regexp_replace(coalesce(p_order ->> 'pincode', ''), '\D', '', 'g'); cl numeric := coalesce(public.crm_num(p_order -> 'shipping'), 0);
begin
  if not pick and pin !~ '^[1-9][0-9]{5}$' then return; end if;
  qt := public.sp_ship_quote(pin, p_order -> 'items', public.crm_num(p_order -> 'subtotal'), pick);
  if cl < (qt ->> 'charge')::numeric - 0.5 then
    raise exception 'DELIVERY_CHANGED: Delivery charge badal gaya hai (ab Rs %). Cart dobara kholkar order karein.', qt ->> 'charge';
  end if;
end $$;

-- admin (password wala, pincode rules jaisa)
create or replace function public.sp_ship_rules_list(p_pass text) returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  perform public.sp_check(p_pass);
  return coalesce((select jsonb_agg(to_jsonb(r) - 'updated_at' order by (case r.scope when 'all' then 0 when 'state' then 1 when 'district' then 2 when 'area' then 3 else 4 end), r.value) from public.sp_ship_rules r), '[]'::jsonb);
end $$;
create or replace function public.sp_ship_rule_save(p_pass text, p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare sc text := coalesce(p ->> 'scope', ''); v text; id_ bigint := nullif(p ->> 'id', '')::bigint; md text := coalesce(nullif(p ->> 'mode', ''), 'courier'); r public.sp_ship_rules;
begin
  perform public.sp_check(p_pass);
  if sc not in ('all', 'state', 'district', 'area', 'pin') then raise exception 'Scope galat hai'; end if;
  v := public.sp_pin_val(sc, p ->> 'value');
  if v is null then raise exception 'Value sahi likhein (pin: 6 ank, state / area: naam, district: STATE|DISTRICT)'; end if;
  if md not in ('self', 'courier') then raise exception 'Mode galat hai'; end if;
  if coalesce(public.crm_num(p -> 'base_charge'), 0) < 0 or coalesce(public.crm_num(p -> 'per_kg'), 0) < 0 then raise exception 'Charge negative nahi ho sakta'; end if;
  if id_ is not null then
    update public.sp_ship_rules set scope = sc, value = v, mode = md, courier = left(coalesce(p ->> 'courier', ''), 60), base_charge = coalesce(public.crm_num(p -> 'base_charge'), 0), base_kg = coalesce(public.crm_num(p -> 'base_kg'), 5),
      per_kg = coalesce(public.crm_num(p -> 'per_kg'), 0), free_above = coalesce(public.crm_num(p -> 'free_above'), 0), eta_min = coalesce(public.crm_num(p -> 'eta_min'), 0)::int, eta_max = coalesce(public.crm_num(p -> 'eta_max'), 0)::int,
      note = left(coalesce(p ->> 'note', ''), 200), updated_at = now() where id = id_ returning * into r;
    if r.id is null then raise exception 'Rule nahi mila'; end if;
  else
    insert into public.sp_ship_rules(scope, value, mode, courier, base_charge, base_kg, per_kg, free_above, eta_min, eta_max, note)
    values (sc, v, md, left(coalesce(p ->> 'courier', ''), 60), coalesce(public.crm_num(p -> 'base_charge'), 0), coalesce(public.crm_num(p -> 'base_kg'), 5), coalesce(public.crm_num(p -> 'per_kg'), 0),
            coalesce(public.crm_num(p -> 'free_above'), 0), coalesce(public.crm_num(p -> 'eta_min'), 0)::int, coalesce(public.crm_num(p -> 'eta_max'), 0)::int, left(coalesce(p ->> 'note', ''), 200))
    on conflict (scope, value) do update set mode = excluded.mode, courier = excluded.courier, base_charge = excluded.base_charge, base_kg = excluded.base_kg, per_kg = excluded.per_kg,
      free_above = excluded.free_above, eta_min = excluded.eta_min, eta_max = excluded.eta_max, note = excluded.note, updated_at = now() returning * into r;
  end if;
  return to_jsonb(r) - 'updated_at';
exception when unique_violation then raise exception 'Is scope + value ka rule pehle se hai';
end $$;
create or replace function public.sp_ship_rule_delete(p_pass text, p_id bigint) returns void language plpgsql security definer set search_path = public, extensions as $$
begin perform public.sp_check(p_pass); delete from public.sp_ship_rules where id = p_id; end $$;

-- order par server guard + order me delivery ki jaankari (mode / courier / eta) save
create or replace function public.sp_place_order(p_order jsonb)
returns bigint language plpgsql security definer set search_path to 'public' as $$
declare new_id bigint; u public.crm_users; o jsonb; qt jsonb; inst jsonb := '[]'::jsonb;
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

  -- Round 24: same stock for Store App + Website Shop — last unit is held for the first order (server-side, cannot be bypassed)
  perform public.sp_price_guard(p_order -> 'items', public.crm_num(p_order -> 'subtotal'));   -- Round 47: ek hi price har jagah
  perform public.sp_ship_guard(p_order);                                                      -- Round 48: pincode ke hisaab se delivery charge
  perform public.sp_stock_guard(p_order -> 'items', public.sp_order_channel(p_order));

  -- identity always comes from the account, never from the browser
  o := (p_order - 'token' - 'customer_id')
       || jsonb_build_object(
            'name', left(coalesce(nullif(trim(u.name), ''), trim(p_order->>'name')), 80),
            'phone', coalesce(u.mobile, ''),
            'customer_id', u.id::text,
            'login_method', 'email_otp',
            'payment_status', 'awaiting_payment', 'channel', public.sp_order_channel(p_order));

  if coalesce(trim(o->>'name'), '') = '' or coalesce(trim(o->>'phone'), '') = '' then
    raise exception 'Naam aur mobile account mein save karein';
  end if;

  qt := public.sp_ship_quote(p_order ->> 'pincode', p_order -> 'items', public.crm_num(p_order -> 'subtotal'), coalesce(p_order ->> 'pickup', 'false') = 'true');
  o := o || jsonb_build_object('delivery', jsonb_build_object('mode', qt ->> 'mode', 'courier', qt ->> 'courier', 'eta_min', qt -> 'eta_min', 'eta_max', qt -> 'eta_max', 'reason', qt ->> 'reason', 'free', qt -> 'free', 'kg', qt -> 'kg'));
  -- Round 48: installation ek optional add-on hai (sirf installOk wale product; charge baad me Service kaam ke bill me — order total me nahi judta)
  if jsonb_typeof(p_order -> 'install') = 'array' then
    select coalesce(jsonb_agg(jsonb_build_object('id', pr ->> 'id', 'name', left(coalesce(pr ->> 'title', pr ->> 'name'), 80), 'price', public.crm_num(pr -> 'installPrice'))), '[]'::jsonb) into inst
      from jsonb_array_elements(coalesce((select data -> 'products' from public.sp_store where id = 'main'), '[]'::jsonb)) pr
     where (pr ->> 'installOk') = 'true'
       and (pr ->> 'id') in (select jsonb_array_elements_text(p_order -> 'install'))
       and (pr ->> 'id') in (select it ->> 'id' from jsonb_array_elements(p_order -> 'items') it);
  end if;
  o := (o - 'install') || case when jsonb_array_length(inst) > 0 then jsonb_build_object('install', inst) else '{}'::jsonb end;
  o := o || jsonb_build_object('order_no', public.crm_next_no('order'));
  insert into public.sp_orders(data) values (o) returning id into new_id;
  perform public.sp_notify_admin('Naya order ' || (o->>'order_no') || ' — ' || (o->>'name'),
    '<p>Naya order aaya hai: <b>' || (o->>'order_no') || '</b></p><p>' || (o->>'name') || ' · ' || (o->>'phone') || '</p><p>Total: ₹' || (o->>'total') || ' — payment ka UTR aane par dobara notification milega.</p>' || case when jsonb_array_length(inst) > 0 then '<p><b>🔧 Installation add-on chahiye</b> — Service kaam banayein.</p>' else '' end || '<p>Admin panel mein dekhein.</p>');
  return new_id;
end $$;

-- =====================================================================================================
-- ROUND 48 / B — Customer flow: Product (naya) aur Service (naya) kram. 4 naye steps: 20 Stock Reserve, 21 Dispatch / Delivery, 22 Warranty Registration, 23 Job Done Report.
--   Product : Lead > Customer > Demo/Files > Quotation > Confirmation > Stock Reserve > Billing > Dispatch > Warranty > Referral > Complaint
--   Service : Lead > Customer > Site Visit > Quotation > Confirmation > Schedule+Technician > Job Done Report > Billing > Service report/Docs > Referral > AMC (agli baar) > Complaint
--   Purane steps wahi (8 Technician, 12 Billing, 14 Docs, 16 Referral, 17 AMC, 18 Complaint) — dobara use hote hain. Dobara chalana safe hai.
-- =====================================================================================================
CREATE OR REPLACE FUNCTION public.crm_wf_names()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select array['Add Customer','Conversation','Quotation','Site Visit','Blueprint','Confirmation','Apply Process','Hand Over Technician','Start Installation',
               'Verification / Commissioning','Net Metering','Finish Work','Subsidy Redeem','Send Demo / Files','Loan / Finance','Suggest / Referral','AMC / Maintenance','Complaint Status','Leads','Stock Reserve','Dispatch / Delivery','Warranty Registration','Job Done Report'] $function$;
create or replace function public.crm_wf_flow(ct text) returns int[] language sql immutable as $$
  select case
    when ct = 'Items only'  then array[19,1,2,14,3,6,20,12,21,22,16,18]                       -- Product customer
    when ct = 'Service'     then array[19,1,2,4,3,6,8,23,12,14,16,17,18]                      -- Service customer (cleaning, repair, shifting, audit, installation add-on)
    when ct = 'AMC only'        then array[19,1,2,17]                                        -- only a Maintenance / AMC plan
    when ct = 'Site visit only' then array[19,1,2,4]                                         -- only a Site Visit
    when ct = 'Residential' then array[19,1,2,14,3,4,5,6,7,15,8,9,10,11,12,13,16,17,18]      -- Project, subsidy applies
    else                         array[19,1,2,14,3,4,5,6,7,15,8,9,10,11,12,16,17,18] end $$;
create or replace function public.crm_wf_can_skip(n integer) returns boolean language sql immutable as $$ select n in (4, 5, 11, 13, 14, 15, 16, 17, 18, 20) $$;
CREATE OR REPLACE FUNCTION public.crm_wf_fields()
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select '{
   "4":  [{"k":"roof_type","l":"Chhat ka prakar"},{"k":"roof_area","l":"Chhat ka area (sq ft)"},{"k":"shadow","l":"Chhaya / shadow"},{"k":"phase","l":"Connection (1 / 3 phase)"},{"k":"structure_ht","l":"Structure ki height (ft)"}],
   "5":  [{"k":"kw_final","l":"Final plant size (kW)"},{"k":"panels","l":"Panels (sankhya)"}],
   "7":  [{"k":"discom","l":"DISCOM","req":true},{"k":"consumer_no","l":"Consumer number","req":true},{"k":"sanctioned_load","l":"Sanctioned load (kW)"},{"k":"category","l":"Category (LMV-1 etc.)"},{"k":"portal_app_no","l":"Portal application no."},{"k":"apply_date","l":"Apply ki tareekh"}],
   "8":  [{"k":"tech_name","l":"Technician ka naam","req":true},{"k":"tech_mobile","l":"Technician ka mobile"},{"k":"handover_date","l":"Hand over ki tareekh"}],
   "9":  [{"k":"start_date","l":"Installation shuru hui"},{"k":"team_size","l":"Team (log)"}],
   "10": [{"k":"inverter_sn","l":"Inverter serial no."},{"k":"panel_count","l":"Panels (sankhya)"},{"k":"jcr","l":"Joint Commissioning Report"},{"k":"comm_date","l":"Commissioning ki tareekh"}],
   "11": [{"k":"nm_app_no","l":"Net metering application no."},{"k":"meter_no","l":"Meter number"},{"k":"meter_date","l":"Meter lagne ki tareekh"},{"k":"discom_je","l":"DISCOM JE / contact"}],
   "13": [{"k":"sub_app_no","l":"Subsidy application no."},{"k":"sub_amount","l":"Subsidy amount (Rs)"},{"k":"sub_status","l":"Subsidy status"}],
   "14": [{"k":"sent_what","l":"Kya bheja (demo / datasheet / photo)"},{"k":"sent_mode","l":"Kaise bheja (WhatsApp / Email / Milkar)"}],
   "15": [{"k":"pay_mode","l":"Payment tarika (Cash / Loan / Mixed)","req":true},{"k":"bank","l":"Bank"},{"k":"loan_amount","l":"Loan amount (Rs)"},{"k":"loan_status","l":"Loan status"},{"k":"loan_ref","l":"Loan reference no."}],
   "16": [{"k":"ref_name","l":"Refer kiya (naam)"},{"k":"ref_mobile","l":"Refer kiya (mobile)"}],
   "17": [{"k":"amc_plan","l":"AMC / maintenance plan"},{"k":"amc_start","l":"Shuru ki tareekh"}],
   "18": [{"k":"c_status","l":"Complaint status (None / Open / In progress / Resolved)"},{"k":"c_issue","l":"Samasya"},{"k":"c_ticket","l":"Ticket / complaint no."},{"k":"c_handler","l":"Kisne sambhali (Installer / Dealer / Manufacturer)"},{"k":"c_brand","l":"Brand / product"},{"k":"c_serial","l":"Serial number"},{"k":"c_date","l":"Complaint ki tareekh"}],
   "20": [{"k":"stock_status","l":"Stock (Hai / Purchase karna hai)"},{"k":"reserved_on","l":"Maal alag rakhne ki tareekh"}],
   "21": [{"k":"disp_mode","l":"Kaise gaya (Khud / Courier / Store se uthaya)","req":true},{"k":"courier","l":"Courier / transport ka naam"},{"k":"tracking_no","l":"Tracking / LR number"},{"k":"disp_date","l":"Bheja gaya (tareekh)"},{"k":"deliv_date","l":"Pahuncha (tareekh)"},{"k":"deliv_proof","l":"Delivery ka saboot (photo Documents me / receiver ka naam)"}],
   "22": [{"k":"serials","l":"Serial number(s)"},{"k":"warranty_months","l":"Warranty (mahine)"},{"k":"install_by","l":"Installation (Khud video dekh kar / Hamari team)"},{"k":"video_sent","l":"Demo / install video bheji (Haan / Nahi)"}],
   "23": [{"k":"job_summary","l":"Kaam ka saar (kya kiya)","req":true},{"k":"parts_used","l":"Lage hue parts"},{"k":"photos_done","l":"Before / After photo Documents me (Haan / Nahi)"},{"k":"done_date","l":"Kaam ki tareekh"}]
  }'::jsonb $function$;
CREATE OR REPLACE FUNCTION public.crm_wf_set(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; n int := (p ->> 'step')::int; done boolean := coalesce((p ->> 'done')::boolean, true); note text := left(trim(coalesce(p ->> 'note', '')), 500);
        skip boolean := coalesce((p ->> 'skip')::boolean, false); w jsonb; flow int[]; ct text; inf jsonb := '{}'::jsonb; f jsonb; v text; miss text[] := '{}'; entry jsonb; has_info boolean := p ? 'info';
begin
  select * into q from public.crm_records where id = (p ->> 'id')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if n is null or n < 1 or n > 23 then raise exception 'Step galat hai'; end if;
  if public.crm_wf_is_auto(n) then raise exception 'Ye step apne aap hota hai (quotation / bill / lead se)'; end if;
  ct := coalesce(q.data ->> 'ctype', ''); flow := public.crm_wf_flow_of(q);
  if not (n = any (flow)) then
    if n = 13 then raise exception 'Subsidy sirf Residential solar ke liye hai'; end if;
    raise exception 'Ye step is customer ke liye nahi hai (% — %)', case ct when 'Items only' then 'Product customer' when 'Service' then 'Service customer' when 'AMC only' then 'AMC customer' when 'Site visit only' then 'Site visit customer' else 'Project customer' end, (public.crm_wf_names())[n];
  end if;
  if n = 13 and not (public.crm_is_admin(s) or (s).role = 'manager') then raise exception 'Subsidy sirf Admin ya Manager green kar sakte hain'; end if;
  if not public.crm_wf_can(s, n, 'edit') then raise exception 'Is step ko badalne ki permission nahi hai — Admin se allow karwayein'; end if;
  w := coalesce(q.data -> 'wf', '{}'::jsonb);
  if done then
    if n = 7 and not (w ? '6') then raise exception 'Pehle quotation Confirm hona chahiye'; end if;
    if (n in (9, 10, 11, 13) or (n = 8 and ct <> 'Service') or (n = 17 and ct not in ('Service', 'AMC only'))) and not (w ? '7') then raise exception 'Pehle Apply Process confirm karein — tabhi customer Projects me aata hai'; end if;
    if (n in (15, 16, 18, 20, 21, 22, 23) or (n = 8 and ct = 'Service') or (n = 17 and ct = 'Service')) and not (w ? '6') then raise exception 'Pehle quotation Confirm hona chahiye'; end if;
    if skip and not public.crm_wf_can_skip(n) then raise exception 'Ye step "Lagu nahi" nahi kiya ja sakta'; end if;
    if skip then
      entry := jsonb_build_object('at', public.crm_iso_now(), 'by', (s).name, 'by_id', (s).uid, 'note', note, 'skip', true);
    else
      -- keep only the fields this step defines; mandatory ones must be filled (only when the new screen sends "info")
      for f in select * from jsonb_array_elements(coalesce(public.crm_wf_fields() -> n::text, '[]'::jsonb)) loop
        v := left(trim(coalesce(p -> 'info' ->> (f ->> 'k'), '')), 200);
        if v <> '' then inf := inf || jsonb_build_object(f ->> 'k', v);
        elsif has_info and coalesce((f ->> 'req')::boolean, false) then miss := miss || (f ->> 'l'); end if;
      end loop;
      if array_length(miss, 1) > 0 then raise exception 'Ye details bharna zaroori hai: %', array_to_string(miss, ', '); end if;
      entry := jsonb_build_object('at', public.crm_iso_now(), 'by', (s).name, 'by_id', (s).uid, 'note', note) || case when inf = '{}'::jsonb then '{}'::jsonb else jsonb_build_object('info', inf) end;
    end if;
    w := w || jsonb_build_object(n::text, entry);
  else
    if not public.crm_is_admin(s) then raise exception 'Step wapas sirf Admin kar sakta hai'; end if;
    w := w - n::text;
  end if;
  perform set_config('sp.wf', '1', true);
  update public.crm_records set data = data || jsonb_build_object('wf', w), updated_at = now() where id = q.id;
  perform set_config('sp.wf', '', true);
  perform public.crm_log(s, 'workflow', 'quote', q.id, coalesce(q.ref, '') || ' — ' || (public.crm_wf_names())[n] || case when not done then ' ↩' when skip then ' (lagu nahi)' else ' ✔' end);
  select * into q from public.crm_records where id = q.id;
  return public.crm_wf_get(jsonb_build_object('token', p ->> 'token', 'id', q.id));
end $function$;
CREATE OR REPLACE FUNCTION public.crm_wf_perm(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); cur jsonb;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  if p ? 'perm' then
    update public.crm_settings set data = jsonb_set(coalesce(data, '{}'::jsonb), '{wf}', coalesce(data -> 'wf', '{}'::jsonb) || jsonb_build_object('perm', coalesce(p -> 'perm', '{}'::jsonb), 'allow_old', coalesce((p ->> 'allow_old')::boolean, false))), updated_at = now() where id = 1;
    perform public.crm_log(s, 'settings', 'settings', 1, 'Workflow permission badli');
  end if;
  select data -> 'wf' into cur from public.crm_settings where id = 1;
  return jsonb_build_object('perm', coalesce(cur -> 'perm', '{}'::jsonb), 'allow_old', coalesce((cur ->> 'allow_old')::boolean, false), 'names', to_jsonb(public.crm_wf_names()),
    'manual', (select coalesce(jsonb_agg(k order by k), '[]'::jsonb) from (select generate_series(1, 18) k union all select generate_series(20, 23)) g(k) where not public.crm_wf_is_auto(k)), 'flow', to_jsonb(public.crm_wf_flow('Residential')));
end $function$;

-- =====================================================================================================
-- ROUND 48 / C — Customer DECLARATION (OTP ki jagah): link se "kaam poora hua / main khud lagaunga" ki ghoshna.
--   kind 'job'  : Service kaam poora (step 23 ke baad). Customer 48 ghante me kuch na kare to apne aap manzoor (auto).
--   kind 'self' : Product ko khud lagane ki ghoshna (step 22 Warranty ke saath). Auto-accept nahi hota.
--   Customer "Dikkat hai" dabaye to Complaint ticket + reminder bante hain. Dobara chalana safe hai.
-- =====================================================================================================
create table if not exists public.crm_decl (
  id bigserial primary key,
  token text not null unique,
  quote_id bigint not null,
  party_id bigint,
  kind text not null check (kind in ('job', 'self')),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'auto', 'issue')),
  signer text not null default '',
  issue text not null default '',
  note text not null default '',
  created_by bigint,
  created_at timestamptz not null default now(),
  due_at timestamptz not null default now() + interval '48 hours',
  done_at timestamptz
);
create index if not exists crm_decl_quote_idx on public.crm_decl(quote_id);
alter table public.crm_decl enable row level security;

-- wf step ki entry me declaration ki sthiti likh do (step 23 / 22)
create or replace function public.crm__decl_note(p_qid bigint, p_kind text, p_status text, p_signer text) returns void language plpgsql security definer set search_path to 'public' as $$
declare n int := case p_kind when 'job' then 23 else 22 end; prev text := coalesce(current_setting('sp.wf', true), ''); w jsonb;
begin
  select data -> 'wf' into w from public.crm_records where id = p_qid and kind = 'quote' and deleted_at is null;
  if w is null or not (w ? n::text) then return; end if;
  perform set_config('sp.wf', '1', true);
  update public.crm_records set data = jsonb_set(data, array['wf', n::text, 'info'],
      coalesce(data -> 'wf' -> n::text -> 'info', '{}'::jsonb) || jsonb_build_object('decl', p_status, 'decl_by', p_signer, 'decl_at', public.crm_iso_now()), true), updated_at = now()
    where id = p_qid;
  perform set_config('sp.wf', prev, true);
end $$;

-- 48 ghante beet gaye aur customer chup: "job" declaration apne aap manzoor
create or replace function public.crm_decl_sweep(p_qid bigint default null) returns int language plpgsql security definer set search_path to 'public' as $$
declare r public.crm_decl; c int := 0;
begin
  for r in select * from public.crm_decl where status = 'pending' and kind = 'job' and due_at <= now() and (p_qid is null or quote_id = p_qid) for update skip locked loop
    update public.crm_decl set status = 'auto', signer = 'Auto (48 ghante)', done_at = now() where id = r.id;
    perform public.crm__decl_note(r.quote_id, 'job', 'auto', 'Auto (48 ghante)');
    c := c + 1;
  end loop;
  return c;
end $$;

-- staff: link banao (ya purana pending wala wapas do)
create or replace function public.crm_decl_new(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; k text := p ->> 'kind'; n int; r public.crm_decl; w jsonb;
begin
  if k not in ('job', 'self') then raise exception 'Galat prakar'; end if;
  n := case k when 'job' then 23 else 22 end;
  select * into q from public.crm_records where id = nullif(p ->> 'quote_id', '')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if not (n = any (public.crm_wf_flow_of(q))) then raise exception 'Ye step is customer ke liye nahi hai'; end if;
  if not public.crm_wf_can(s, n, 'edit') then raise exception 'Is step ko badalne ki permission nahi hai — Admin se allow karwayein'; end if;
  w := coalesce(q.data -> 'wf', '{}'::jsonb);
  if k = 'job' and not (w ? '23') then raise exception 'Pehle "Job Done Report" bharein, phir customer ko confirmation bhejein'; end if;
  if k = 'self' and not (w ? '6') then raise exception 'Pehle quotation Confirm hona chahiye'; end if;
  perform public.crm_decl_sweep(q.id);
  select * into r from public.crm_decl where quote_id = q.id and kind = k and status = 'pending' order by id desc limit 1;
  if r.id is null then
    insert into public.crm_decl(token, quote_id, party_id, kind, created_by, note)
      values (md5(random()::text || clock_timestamp()::text || q.id::text) || substr(md5(random()::text), 1, 8), q.id, q.party_id, k, (s).uid, left(trim(coalesce(p ->> 'note', '')), 300)) returning * into r;
  end if;
  return jsonb_build_object('id', r.id, 'token', r.token, 'status', r.status, 'kind', r.kind, 'due_at', r.due_at);
end $$;

create or replace function public.crm_decl_list(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; out jsonb;
begin
  select * into q from public.crm_records where id = nullif(p ->> 'quote_id', '')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  perform public.crm_decl_sweep(q.id);
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'token', d.token, 'kind', d.kind, 'status', d.status, 'signer', d.signer, 'issue', d.issue, 'note', d.note,
           'created_at', d.created_at, 'due_at', d.due_at, 'done_at', d.done_at) order by d.id desc), '[]'::jsonb) into out from public.crm_decl d where d.quote_id = q.id;
  return out;
end $$;

-- staff: customer ne phone par bataya — haath se manzoor kar do
create or replace function public.crm_decl_mark(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_decl; q public.crm_records; n int; who text := left(trim(coalesce(p ->> 'signer', '')), 80);
begin
  select * into r from public.crm_decl where id = nullif(p ->> 'id', '')::bigint;
  if r.id is null then raise exception 'Declaration nahi mili'; end if;
  select * into q from public.crm_records where id = r.quote_id and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  n := case r.kind when 'job' then 23 else 22 end;
  if not public.crm_wf_can(s, n, 'edit') then raise exception 'Is step ko badalne ki permission nahi hai — Admin se allow karwayein'; end if;
  if r.status <> 'pending' then raise exception 'Ye declaration pehle hi ho chuki hai'; end if;
  if who = '' then who := 'Phone par — ' || (s).name; end if;
  update public.crm_decl set status = 'accepted', signer = who, done_at = now() where id = r.id;
  perform public.crm__decl_note(r.quote_id, r.kind, 'accepted', who);
  return jsonb_build_object('ok', true);
end $$;

-- customer (bina login): link kholne par jaankari
create or replace function public.sp_decl_get(p_token text) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r public.crm_decl; q public.crm_records; pt public.crm_records; inf jsonb; w jsonb;
begin
  if coalesce(length(p_token), 0) < 20 then return jsonb_build_object('ok', false, 'error', 'Link galat hai'); end if;
  select * into r from public.crm_decl where token = p_token;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'Link galat hai'); end if;
  perform public.crm_decl_sweep(r.quote_id);
  select * into r from public.crm_decl where id = r.id;
  select * into q from public.crm_records where id = r.quote_id;
  select * into pt from public.crm_records where id = r.party_id;
  w := coalesce(q.data -> 'wf', '{}'::jsonb);
  inf := coalesce(w -> (case r.kind when 'job' then '23' else '22' end) -> 'info', '{}'::jsonb);
  return jsonb_build_object('ok', true, 'kind', r.kind, 'status', r.status, 'signer', r.signer, 'due_at', r.due_at, 'done_at', r.done_at,
    'customer', coalesce(pt.title, ''), 'ref', q.ref, 'title', coalesce(q.data ->> 'qtitle', q.title),
    'summary', coalesce(inf ->> 'job_summary', ''), 'done_date', coalesce(inf ->> 'done_date', ''), 'parts', coalesce(inf ->> 'parts_used', ''), 'note', r.note);
end $$;

-- customer: "Sab theek hai" ya "Dikkat hai"
create or replace function public.sp_decl_submit(p_token text, p_name text, p_ok boolean, p_issue text default '') returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r public.crm_decl; q public.crm_records; pt public.crm_records; nm text := left(trim(coalesce(p_name, '')), 80); iss text := left(trim(coalesce(p_issue, '')), 300); cnt int; fid bigint; asg bigint; no_ text;
begin
  if coalesce(length(p_token), 0) < 20 then return jsonb_build_object('ok', false, 'error', 'Link galat hai'); end if;
  select * into r from public.crm_decl where token = p_token for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'Link galat hai'); end if;
  if r.status <> 'pending' then return jsonb_build_object('ok', true, 'status', r.status, 'already', true); end if;
  if length(nm) < 2 then return jsonb_build_object('ok', false, 'error', 'Apna naam likhein'); end if;
  select * into q from public.crm_records where id = r.quote_id and kind = 'quote' and deleted_at is null;
  if q.id is null then return jsonb_build_object('ok', false, 'error', 'Link galat hai'); end if;
  if p_ok then
    update public.crm_decl set status = 'accepted', signer = nm, done_at = now() where id = r.id;
    perform public.crm__decl_note(r.quote_id, r.kind, 'accepted', nm);
    return jsonb_build_object('ok', true, 'status', 'accepted');
  end if;
  if length(iss) < 3 then return jsonb_build_object('ok', false, 'error', 'Dikkat likhein (kam se kam 3 akshar)'); end if;
  update public.crm_decl set status = 'issue', signer = nm, issue = iss, done_at = now() where id = r.id;
  perform public.crm__decl_note(r.quote_id, r.kind, 'issue', nm);
  select * into pt from public.crm_records where id = q.party_id and kind = 'party';
  perform pg_advisory_xact_lock(4747);
  select count(*) + 1 into cnt from public.crm_flow_rec where kind = 'complaint';
  no_ := 'TKT-' || to_char(now() at time zone 'Asia/Kolkata', 'YY') || '-' || lpad(cnt::text, 4, '0');
  insert into public.crm_flow_rec(kind, quote_id, party_id, no, status, data, hist)
    values ('complaint', q.id, q.party_id, no_, 'Open',
      jsonb_build_object('issue', iss, 'brand', '', 'serial', '', 'handler', 'Installer', 'priority', 'Urgent', 'c_date', public.crm_today()::text, 'assigned_to', null, 'ticket_ref', '', 'resolution', '', 'from_decl', r.id),
      jsonb_build_array(jsonb_build_object('at', public.crm_iso_now(), 'by', nm, 'status', 'Open', 'note', 'Customer ne declaration link se dikkat batayi'))) returning id into fid;
  asg := coalesce(nullif(q.assigned_to, 0), q.owner_id, q.created_by);
  if asg is not null then
    insert into public.crm_records(kind, title, status, owner_id, assigned_to, party_id, mobile, due_at, data, search, created_by)
    values ('reminder', 'Complaint ' || no_ || ' — ' || coalesce(pt.title, '') || ': ' || left(iss, 60), 'open', asg, asg, q.party_id, pt.mobile, public.crm_today(),
      jsonb_build_object('type', 'followup', 'complaint_id', fid, 'ticket', no_, 'party_name', coalesce(pt.title, ''), 'mobile', coalesce(pt.mobile, ''), 'note', left(iss, 200), 'priority', 'Urgent'),
      lower('complaint ' || no_ || ' ' || coalesce(pt.title, '')), asg);
    update public.crm_flow_rec set rem_id = (select max(id) from public.crm_records where kind = 'reminder' and (data ->> 'complaint_id') = fid::text) where id = fid;
  end if;
  return jsonb_build_object('ok', true, 'status', 'issue', 'ticket', no_);
end $$;

-- crm_wf_get ab purani pending declarations bhi sweep karta hai (job screen kholte hi 48h wali apne aap manzoor)
do $$ begin
  if position('crm_decl_sweep' in pg_get_functiondef('public.crm_wf_get(jsonb)'::regprocedure)) = 0 then
    execute replace(replace(pg_get_functiondef('public.crm_wf_get(jsonb)'::regprocedure),
      E'begin\n  if qid is null and pid is not null then', E'begin\n  if qid is not null then perform public.crm_decl_sweep(qid); end if;\n  if qid is null and pid is not null then'), 'x', 'x');
  end if;
end $$;

grant execute on function public.crm_decl_new(jsonb), public.crm_decl_list(jsonb), public.crm_decl_mark(jsonb), public.sp_decl_get(text), public.sp_decl_submit(text, text, boolean, text) to anon, authenticated;
revoke execute on function public.crm_decl_sweep(bigint), public.crm__decl_note(bigint, text, text, text) from public, anon, authenticated;


-- =====================================================================================================
-- ROUND 49 — Customer Profile card (Meri Profile), customer Documents, Routine Checkup, order page, dispatch.
--   Dobara chalana safe hai. Pehle R48 wala block chal chuka hona chahiye (MASTER-UPDATE.sql me sab saath hai).
-- =====================================================================================================
-- =====================================================================================================
-- ROUND 48 / C — Customer DECLARATION (OTP ki jagah): link se "kaam poora hua / main khud lagaunga" ki ghoshna.
--   kind 'job'  : Service kaam poora (step 23 ke baad). Customer 48 ghante me kuch na kare to apne aap manzoor (auto).
--   kind 'self' : Product ko khud lagane ki ghoshna (step 22 Warranty ke saath). Auto-accept nahi hota.
--   Customer "Dikkat hai" dabaye to Complaint ticket + reminder bante hain. Dobara chalana safe hai.
-- =====================================================================================================
create table if not exists public.crm_decl (
  id bigserial primary key,
  token text not null unique,
  quote_id bigint not null,
  party_id bigint,
  kind text not null check (kind in ('job', 'self')),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'auto', 'issue')),
  signer text not null default '',
  issue text not null default '',
  note text not null default '',
  created_by bigint,
  created_at timestamptz not null default now(),
  due_at timestamptz not null default now() + interval '48 hours',
  done_at timestamptz
);
create index if not exists crm_decl_quote_idx on public.crm_decl(quote_id);
alter table public.crm_decl enable row level security;

-- wf step ki entry me declaration ki sthiti likh do (step 23 / 22)
create or replace function public.crm__decl_note(p_qid bigint, p_kind text, p_status text, p_signer text) returns void language plpgsql security definer set search_path to 'public' as $$
declare n int := case p_kind when 'job' then 23 else 22 end; prev text := coalesce(current_setting('sp.wf', true), ''); w jsonb;
begin
  select data -> 'wf' into w from public.crm_records where id = p_qid and kind = 'quote' and deleted_at is null;
  if w is null or not (w ? n::text) then return; end if;
  perform set_config('sp.wf', '1', true);
  update public.crm_records set data = jsonb_set(data, array['wf', n::text, 'info'],
      coalesce(data -> 'wf' -> n::text -> 'info', '{}'::jsonb) || jsonb_build_object('decl', p_status, 'decl_by', p_signer, 'decl_at', public.crm_iso_now()), true), updated_at = now()
    where id = p_qid;
  perform set_config('sp.wf', prev, true);
end $$;

-- 48 ghante beet gaye aur customer chup: "job" declaration apne aap manzoor
create or replace function public.crm_decl_sweep(p_qid bigint default null) returns int language plpgsql security definer set search_path to 'public' as $$
declare r public.crm_decl; c int := 0;
begin
  for r in select * from public.crm_decl where status = 'pending' and kind = 'job' and due_at <= now() and (p_qid is null or quote_id = p_qid) for update skip locked loop
    update public.crm_decl set status = 'auto', signer = 'Auto (48 ghante)', done_at = now() where id = r.id;
    perform public.crm__decl_note(r.quote_id, 'job', 'auto', 'Auto (48 ghante)');
    c := c + 1;
  end loop;
  return c;
end $$;

-- staff: link banao (ya purana pending wala wapas do)
create or replace function public.crm_decl_new(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; k text := p ->> 'kind'; n int; r public.crm_decl; w jsonb;
begin
  if k not in ('job', 'self') then raise exception 'Galat prakar'; end if;
  n := case k when 'job' then 23 else 22 end;
  select * into q from public.crm_records where id = nullif(p ->> 'quote_id', '')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if not (n = any (public.crm_wf_flow_of(q))) then raise exception 'Ye step is customer ke liye nahi hai'; end if;
  if not public.crm_wf_can(s, n, 'edit') then raise exception 'Is step ko badalne ki permission nahi hai — Admin se allow karwayein'; end if;
  w := coalesce(q.data -> 'wf', '{}'::jsonb);
  if k = 'job' and not (w ? '23') then raise exception 'Pehle "Job Done Report" bharein, phir customer ko confirmation bhejein'; end if;
  if k = 'self' and not (w ? '6') then raise exception 'Pehle quotation Confirm hona chahiye'; end if;
  perform public.crm_decl_sweep(q.id);
  select * into r from public.crm_decl where quote_id = q.id and kind = k and status = 'pending' order by id desc limit 1;
  if r.id is null then
    insert into public.crm_decl(token, quote_id, party_id, kind, created_by, note)
      values (md5(random()::text || clock_timestamp()::text || q.id::text) || substr(md5(random()::text), 1, 8), q.id, q.party_id, k, (s).uid, left(trim(coalesce(p ->> 'note', '')), 300)) returning * into r;
  end if;
  return jsonb_build_object('id', r.id, 'token', r.token, 'status', r.status, 'kind', r.kind, 'due_at', r.due_at);
end $$;

create or replace function public.crm_decl_list(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; out jsonb;
begin
  select * into q from public.crm_records where id = nullif(p ->> 'quote_id', '')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  perform public.crm_decl_sweep(q.id);
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'token', d.token, 'kind', d.kind, 'status', d.status, 'signer', d.signer, 'issue', d.issue, 'note', d.note,
           'created_at', d.created_at, 'due_at', d.due_at, 'done_at', d.done_at) order by d.id desc), '[]'::jsonb) into out from public.crm_decl d where d.quote_id = q.id;
  return out;
end $$;

-- staff: customer ne phone par bataya — haath se manzoor kar do
create or replace function public.crm_decl_mark(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_decl; q public.crm_records; n int; who text := left(trim(coalesce(p ->> 'signer', '')), 80);
begin
  select * into r from public.crm_decl where id = nullif(p ->> 'id', '')::bigint;
  if r.id is null then raise exception 'Declaration nahi mili'; end if;
  select * into q from public.crm_records where id = r.quote_id and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  n := case r.kind when 'job' then 23 else 22 end;
  if not public.crm_wf_can(s, n, 'edit') then raise exception 'Is step ko badalne ki permission nahi hai — Admin se allow karwayein'; end if;
  if r.status <> 'pending' then raise exception 'Ye declaration pehle hi ho chuki hai'; end if;
  if who = '' then who := 'Phone par — ' || (s).name; end if;
  update public.crm_decl set status = 'accepted', signer = who, done_at = now() where id = r.id;
  perform public.crm__decl_note(r.quote_id, r.kind, 'accepted', who);
  return jsonb_build_object('ok', true);
end $$;

-- Round 49: ek hi jagah complaint ticket banti hai (declaration link, customer hub, checkup — teeno yahin se). Ticket no + "Aaj ke kaam" reminder.
create or replace function public.crm__complaint_new(p_qid bigint, p_who text, p_issue text, p_prio text, p_extra jsonb, p_note text) returns text language plpgsql security definer set search_path to 'public' as $$
declare q public.crm_records; pt public.crm_records; cnt int; fid bigint; asg bigint; no_ text; iss text := left(trim(coalesce(p_issue, '')), 300);
begin
  select * into q from public.crm_records where id = p_qid and kind = 'quote' and deleted_at is null;
  if q.id is null then raise exception 'Kaam nahi mila'; end if;
  select * into pt from public.crm_records where id = q.party_id and kind = 'party';
  perform pg_advisory_xact_lock(4747);
  select count(*) + 1 into cnt from public.crm_flow_rec where kind = 'complaint';
  no_ := 'TKT-' || to_char(now() at time zone 'Asia/Kolkata', 'YY') || '-' || lpad(cnt::text, 4, '0');
  insert into public.crm_flow_rec(kind, quote_id, party_id, no, status, data, hist)
    values ('complaint', q.id, q.party_id, no_, 'Open',
      jsonb_build_object('issue', iss, 'brand', '', 'serial', '', 'handler', 'Installer', 'priority', case when p_prio = 'Urgent' then 'Urgent' else 'Normal' end, 'c_date', public.crm_today()::text, 'assigned_to', null, 'ticket_ref', '', 'resolution', '') || coalesce(p_extra, '{}'::jsonb),
      jsonb_build_array(jsonb_build_object('at', public.crm_iso_now(), 'by', coalesce(p_who, ''), 'status', 'Open', 'note', coalesce(p_note, 'Ticket bana')))) returning id into fid;
  asg := coalesce(nullif(q.assigned_to, 0), q.owner_id, q.created_by);
  if asg is not null then
    insert into public.crm_records(kind, title, status, owner_id, assigned_to, party_id, mobile, due_at, data, search, created_by)
    values ('reminder', 'Complaint ' || no_ || ' — ' || coalesce(pt.title, '') || ': ' || left(iss, 60), 'open', asg, asg, q.party_id, pt.mobile, public.crm_today(),
      jsonb_build_object('type', 'followup', 'complaint_id', fid, 'ticket', no_, 'party_name', coalesce(pt.title, ''), 'mobile', coalesce(pt.mobile, ''), 'note', left(iss, 200), 'priority', case when p_prio = 'Urgent' then 'Urgent' else 'Normal' end),
      lower('complaint ' || no_ || ' ' || coalesce(pt.title, '')), asg);
    update public.crm_flow_rec set rem_id = (select max(id) from public.crm_records where kind = 'reminder' and (data ->> 'complaint_id') = fid::text) where id = fid;
  end if;
  return no_;
end $$;
revoke execute on function public.crm__complaint_new(bigint, text, text, text, jsonb, text) from public, anon, authenticated;

-- customer (bina login): link kholne par jaankari
create or replace function public.sp_decl_get(p_token text) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r public.crm_decl; q public.crm_records; pt public.crm_records; inf jsonb; w jsonb;
begin
  if coalesce(length(p_token), 0) < 20 then return jsonb_build_object('ok', false, 'error', 'Link galat hai'); end if;
  select * into r from public.crm_decl where token = p_token;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'Link galat hai'); end if;
  perform public.crm_decl_sweep(r.quote_id);
  select * into r from public.crm_decl where id = r.id;
  select * into q from public.crm_records where id = r.quote_id;
  select * into pt from public.crm_records where id = r.party_id;
  w := coalesce(q.data -> 'wf', '{}'::jsonb);
  inf := coalesce(w -> (case r.kind when 'job' then '23' else '22' end) -> 'info', '{}'::jsonb);
  return jsonb_build_object('ok', true, 'kind', r.kind, 'status', r.status, 'signer', r.signer, 'due_at', r.due_at, 'done_at', r.done_at,
    'customer', coalesce(pt.title, ''), 'ref', q.ref, 'title', coalesce(q.data ->> 'qtitle', q.title),
    'summary', coalesce(inf ->> 'job_summary', ''), 'done_date', coalesce(inf ->> 'done_date', ''), 'parts', coalesce(inf ->> 'parts_used', ''), 'note', r.note);
end $$;

-- customer: "Sab theek hai" ya "Dikkat hai"
create or replace function public.sp_decl_submit(p_token text, p_name text, p_ok boolean, p_issue text default '') returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r public.crm_decl; q public.crm_records; nm text := left(trim(coalesce(p_name, '')), 80); iss text := left(trim(coalesce(p_issue, '')), 300); no_ text;
begin
  if coalesce(length(p_token), 0) < 20 then return jsonb_build_object('ok', false, 'error', 'Link galat hai'); end if;
  select * into r from public.crm_decl where token = p_token for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'Link galat hai'); end if;
  if r.status <> 'pending' then return jsonb_build_object('ok', true, 'status', r.status, 'already', true); end if;
  if length(nm) < 2 then return jsonb_build_object('ok', false, 'error', 'Apna naam likhein'); end if;
  select * into q from public.crm_records where id = r.quote_id and kind = 'quote' and deleted_at is null;
  if q.id is null then return jsonb_build_object('ok', false, 'error', 'Link galat hai'); end if;
  if p_ok then
    update public.crm_decl set status = 'accepted', signer = nm, done_at = now() where id = r.id;
    perform public.crm__decl_note(r.quote_id, r.kind, 'accepted', nm);
    return jsonb_build_object('ok', true, 'status', 'accepted');
  end if;
  if length(iss) < 3 then return jsonb_build_object('ok', false, 'error', 'Dikkat likhein (kam se kam 3 akshar)'); end if;
  update public.crm_decl set status = 'issue', signer = nm, issue = iss, done_at = now() where id = r.id;
  perform public.crm__decl_note(r.quote_id, r.kind, 'issue', nm);
  no_ := public.crm__complaint_new(q.id, nm, iss, 'Urgent', jsonb_build_object('from_decl', r.id), 'Customer ne declaration link se dikkat batayi');
  return jsonb_build_object('ok', true, 'status', 'issue', 'ticket', no_);
end $$;

-- crm_wf_get ab purani pending declarations bhi sweep karta hai (job screen kholte hi 48h wali apne aap manzoor)
do $$ begin
  if position('crm_decl_sweep' in pg_get_functiondef('public.crm_wf_get(jsonb)'::regprocedure)) = 0 then
    execute replace(replace(pg_get_functiondef('public.crm_wf_get(jsonb)'::regprocedure),
      E'begin\n  if qid is null and pid is not null then', E'begin\n  if qid is not null then perform public.crm_decl_sweep(qid); end if;\n  if qid is null and pid is not null then'), 'x', 'x');
  end if;
end $$;

grant execute on function public.crm_decl_new(jsonb), public.crm_decl_list(jsonb), public.crm_decl_mark(jsonb), public.sp_decl_get(text), public.sp_decl_submit(text, text, boolean, text) to anon, authenticated;
revoke execute on function public.crm_decl_sweep(bigint), public.crm__decl_note(bigint, text, text, text) from public, anon, authenticated;
-- =====================================================================================================
-- ROUND 49 / D — Customer Hub (store + shop "Meri Profile" card): checkup, complaints, orders page, referral, dispatch.
--   Sab customer ke apne mobile se (crm_csession). Dobara chalana safe hai.
-- =====================================================================================================

-- ---- monthly Routine Checkup (sirf Project) — jawab yahin; report PDF/HTML jawab se banti hai (file storage nahi)
create table if not exists public.crm_checkup (
  id bigserial primary key,
  quote_id bigint not null,
  party_id bigint,
  user_id bigint,
  ym text not null,
  items jsonb not null default '{}'::jsonb,
  gen_kwh numeric,
  note text not null default '',
  ticket text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (quote_id, ym)
);
alter table public.crm_checkup enable row level security;

create or replace function public.crm__checkup_keys() returns jsonb language sql immutable as $$
  select '{"panel_clean":"Solar panel saaf hain","inverter_ok":"Inverter theek chal raha hai (koi error / deactivation nahi)","wiring_ok":"Wiring sahi dikhti hai","acdb_dcdb_ok":"ACDB / DCDB sahi dikhte hain","wires_joined":"Wire sab jude hue hain","connectors_ok":"Connector tight / theek hain","structure_ok":"Structure ke bolt sahi hain","shadow_new":"Nayi chhaya / rukawat nahi hai","noise_heat":"Koi awaaz, garmi ya smell nahi","earthing_ok":"Earthing / lightning arrestor sahi dikhta hai"}'::jsonb $$;

-- customer ka apna party + (optional) apna job
create or replace function public.crm__cust_party(u public.crm_users) returns public.crm_records language sql stable security definer set search_path to 'public' as $$
  select * from public.crm_records where kind = 'party' and deleted_at is null and mobile = u.mobile and u.mobile ~ '^[6-9][0-9]{9}$' and coalesce(data ->> 'type', 'customer') <> 'supplier' order by id limit 1 $$;

create or replace function public.crm_checkup_save(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); pt public.crm_records := public.crm__cust_party(u); q public.crm_records; w jsonb; keys jsonb := public.crm__checkup_keys(); k text; v text; it jsonb := '{}'::jsonb;
        v_ym text := to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM'); bad text[] := '{}'; tk text; gen numeric;
begin
  select * into q from public.crm_records where id = nullif(p ->> 'quote_id', '')::bigint and kind = 'quote' and deleted_at is null and party_id = pt.id;
  if q.id is null or pt.id is null then raise exception 'Plant nahi mila'; end if;
  if coalesce(q.data ->> 'ctype', '') not in ('Residential', 'Commercial', 'Industrial', 'VFD') then raise exception 'Routine checkup sirf Project (plant) ke liye hai'; end if;
  w := coalesce(q.data -> 'wf', '{}'::jsonb);
  if not (w ? '9' or w ? '10') then raise exception 'Checkup install hone ke baad shuru hota hai'; end if;
  for k in select jsonb_object_keys(keys) loop
    v := p -> 'items' ->> k;
    if v is null or v not in ('ok', 'bad', 'na') then raise exception 'Har sawal ka jawab chunein (Theek / Dikkat / Lagu nahi)'; end if;
    it := it || jsonb_build_object(k, v);
    if v = 'bad' then bad := bad || (keys ->> k); end if;
  end loop;
  gen := nullif(regexp_replace(coalesce(p ->> 'gen_kwh', ''), '[^0-9.]', '', 'g'), '')::numeric;
  if gen is not null and (gen < 0 or gen > 1000000) then gen := null; end if;
  insert into public.crm_checkup(quote_id, party_id, user_id, ym, items, gen_kwh, note) values (q.id, pt.id, u.id, v_ym, it, gen, left(trim(coalesce(p ->> 'note', '')), 300))
    on conflict (quote_id, ym) do update set items = excluded.items, gen_kwh = excluded.gen_kwh, note = excluded.note, updated_at = now()
    returning ticket into tk;
  if array_length(bad, 1) > 0 and tk is null then
    tk := public.crm__complaint_new(q.id, u.name, 'Routine checkup me dikkat: ' || array_to_string(bad, '; '), 'Normal', jsonb_build_object('from_checkup', v_ym), 'Customer ke monthly checkup se');
    update public.crm_checkup set ticket = tk where quote_id = q.id and crm_checkup.ym = v_ym;
  end if;
  return jsonb_build_object('ok', true, 'ym', v_ym, 'bad', coalesce(array_length(bad, 1), 0), 'ticket', tk);
end $$;

-- ---- customer: nayi complaint (Support)
create or replace function public.crm_consumer_complaint_new(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); pt public.crm_records := public.crm__cust_party(u); q public.crm_records; iss text := left(trim(coalesce(p ->> 'issue', '')), 300); no_ text; open_n int;
begin
  if pt.id is null then raise exception 'Abhi aapka koi kaam / bill juda nahi hai — call ya WhatsApp karein'; end if;
  if length(iss) < 5 then raise exception 'Samasya thodi detail me likhein (kam se kam 5 akshar)'; end if;
  select count(*) into open_n from public.crm_flow_rec where party_id = pt.id and kind = 'complaint' and deleted_at is null and status <> 'Resolved';
  if open_n >= 5 then raise exception 'Aapki 5 complaint pehle se khuli hain — hum jaldi sampark karenge'; end if;
  select * into q from public.crm_records where id = nullif(p ->> 'quote_id', '')::bigint and kind = 'quote' and deleted_at is null and party_id = pt.id;
  if q.id is null then
    select * into q from public.crm_records where kind = 'quote' and deleted_at is null and party_id = pt.id and status in ('accepted', 'converted') order by id desc limit 1;
  end if;
  if q.id is null then raise exception 'Abhi aapka koi confirmed kaam nahi hai — call ya WhatsApp karein'; end if;
  no_ := public.crm__complaint_new(q.id, u.name, iss, case when p ->> 'priority' = 'Urgent' then 'Urgent' else 'Normal' end, jsonb_build_object('from_hub', true, 'brand', left(coalesce(p ->> 'brand', ''), 80)), 'Customer ne app se complaint ki');
  return jsonb_build_object('ok', true, 'ticket', no_);
end $$;

-- ---- customer: koi bhi apna bill (product bill ho ya plant ka) — printable data
create or replace function public.crm_consumer_bill_doc(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); pt public.crm_records := public.crm__cust_party(u); src public.crm_records; co jsonb; pays jsonb;
begin
  select * into src from public.crm_records where id = nullif(p ->> 'id', '')::bigint and kind = 'invoice' and deleted_at is null and party_id = pt.id;
  if src.id is null or pt.id is null then raise exception 'Bill nahi mila'; end if;
  select data -> 'company' into co from public.crm_settings where id = 1;
  select coalesce(jsonb_agg(jsonb_build_object('date', py.due_at, 'amount', py.amount, 'mode', py.data ->> 'mode') order by py.due_at), '[]'::jsonb) into pays from public.crm_records py where py.kind = 'payment' and py.deleted_at is null and py.data ->> 'invoice_id' = src.id::text;
  return jsonb_build_object('kind', 'bill', 'ref', src.ref, 'date', src.data ->> 'date', 'title', src.data ->> 'qtitle',
    'customer', jsonb_build_object('name', pt.title, 'mobile', pt.mobile, 'address', pt.data ->> 'address', 'city', pt.data ->> 'city', 'gstin', pt.data ->> 'gstin'),
    'company', jsonb_build_object('name', co ->> 'name', 'legal', co ->> 'legal', 'gstin', co ->> 'gstin', 'phone', co ->> 'phone', 'address', co ->> 'address'),
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('name', l ->> 'name', 'qty', l -> 'qty', 'price', l -> 'price', 'gst', l -> 'gst', 'hsn', l ->> 'hsn')), '[]'::jsonb) from jsonb_array_elements(coalesce(src.data -> 'lines', '[]'::jsonb)) l),
    'subtotal', src.data -> 'subtotal', 'gst_total', src.data -> 'gst_total', 'discount', src.data -> 'discount', 'grand', src.amount, 'paid', src.data -> 'paid', 'balance', src.data -> 'balance', 'payments', pays, 'notes', src.data ->> 'notes');
end $$;

-- ---- customer: seva ki maang (AMC / installation / call-back) — enquiry + lead banti hai
create or replace function public.crm_consumer_request(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); pt public.crm_records := public.crm__cust_party(u); k text := p ->> 'kind'; sub text; note text := left(trim(coalesce(p ->> 'note', '')), 200);
begin
  if k not in ('amc', 'install', 'callback') then raise exception 'Galat maang'; end if;
  sub := case k when 'amc' then 'AMC / Maintenance plan' when 'install' then 'Installation add-on' else 'Call back' end;
  perform public.sp_submit_enquiry(jsonb_build_object('name', coalesce(pt.title, u.name), 'phone', u.mobile, 'type', sub, 'subject', sub, 'source', 'customer-hub',
    'message', sub || ' chahiye — ' || coalesce(pt.data ->> 'cust_id', '') || case when note <> '' then ' — ' || note else '' end, 'customer_id', u.id::text));
  return jsonb_build_object('ok', true);
end $$;

-- ---- customer: kisi ko refer karein (lead banti hai, enquiry->lead trigger se)
create or replace function public.crm_consumer_refer(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); pt public.crm_records := public.crm__cust_party(u); nm text := left(trim(coalesce(p ->> 'name', '')), 80); mob text := public.crm_mobile(coalesce(p ->> 'mobile', ''));
begin
  if length(nm) < 2 then raise exception 'Dost ka naam likhein'; end if;
  if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Dost ka sahi 10 ank ka mobile likhein'; end if;
  if mob = u.mobile then raise exception 'Apna hi number refer nahi ho sakta'; end if;
  perform public.sp_submit_enquiry(jsonb_build_object('name', nm, 'phone', mob, 'type', 'Referral', 'subject', 'Referral', 'source', 'referral',
    'message', 'Refer kiya: ' || coalesce(pt.title, u.name) || ' (' || coalesce(pt.data ->> 'cust_id', '') || ', ' || u.mobile || ')' || case when coalesce(p ->> 'note', '') <> '' then ' — ' || left(p ->> 'note', 150) else '' end, 'customer_id', u.id::text));
  return jsonb_build_object('ok', true);
end $$;

-- ---- customer: ek order ka poora page (e-commerce jaisa)
create or replace function public.crm_consumer_order(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); o public.sp_orders; ok boolean := coalesce((u.meta ->> 'mob_ok')::boolean, true);
begin
  select * into o from public.sp_orders where id = nullif(p ->> 'id', '')::bigint and ((ok and (data ->> 'phone') = u.mobile) or (data ->> 'customer_id') = u.id::text);
  if o.id is null then raise exception 'Order nahi mila'; end if;
  return jsonb_build_object('id', o.id, 'order_no', o.data ->> 'order_no', 'created_at', o.created_at, 'status', o.status, 'name', o.data ->> 'name', 'phone', o.data ->> 'phone',
    'address', o.data ->> 'address', 'city', o.data ->> 'city', 'pincode', o.data ->> 'pincode', 'pickup', coalesce((o.data ->> 'pickup')::boolean, false),
    'items', (select coalesce(jsonb_agg(jsonb_build_object('title', i ->> 'title', 'qty', i -> 'qty', 'price', i -> 'price', 'amount', i -> 'amount')), '[]'::jsonb) from jsonb_array_elements(coalesce(o.data -> 'items', '[]'::jsonb)) i),
    'subtotal', o.data -> 'subtotal', 'shipping', o.data -> 'shipping', 'total', o.data -> 'total', 'advance', o.data -> 'advance', 'due', o.data -> 'due', 'payment', o.data ->> 'payment', 'payment_status', o.data ->> 'payment_status',
    'invoice_no', o.data ->> 'invoice_no', 'delivery', o.data -> 'delivery', 'dispatch', coalesce(o.data -> 'dispatch', '{}'::jsonb), 'install', coalesce(o.data -> 'install', '[]'::jsonb));
end $$;

-- ---- Admin (store): order ka dispatch (courier / tracking) — customer ke order page par dikhta hai
create or replace function public.sp_admin_order_dispatch(p_pass text, p_id bigint, p jsonb) returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $$
declare d jsonb; st text := nullif(p ->> 'status', ''); cur text;
begin
  perform public.sp_check(p_pass);
  d := jsonb_build_object('mode', case when p ->> 'mode' in ('courier', 'self', 'pickup') then p ->> 'mode' else 'courier' end, 'courier', left(coalesce(p ->> 'courier', ''), 80), 'tracking', left(coalesce(p ->> 'tracking', ''), 80),
    'track_url', case when coalesce(p ->> 'track_url', '') ~* '^https?://' then left(p ->> 'track_url', 300) else '' end, 'disp_date', left(coalesce(p ->> 'disp_date', ''), 10), 'eta_date', left(coalesce(p ->> 'eta_date', ''), 10),
    'deliv_date', left(coalesce(p ->> 'deliv_date', ''), 10), 'note', left(coalesce(p ->> 'note', ''), 200), 'at', public.crm_iso_now());
  select status into cur from public.sp_orders where id = p_id;
  if cur is null then raise exception 'Order nahi mila'; end if;
  if st is not null and st not in ('new', 'confirmed', 'paid', 'shipped', 'delivered', 'cancelled') then st := null; end if;
  update public.sp_orders set data = data || jsonb_build_object('dispatch', d), status = coalesce(st, status) where id = p_id;
  return jsonb_build_object('ok', true, 'dispatch', d, 'status', coalesce(st, cur));
end $$;

-- ---- HUB: ek hi call me customer ka poora card (profile + orders + complaints + checkups + savings settings)
create or replace function public.crm_consumer_hub(p jsonb) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); pt public.crm_records := public.crm__cust_party(u); prof jsonb; ok boolean := coalesce((u.meta ->> 'mob_ok')::boolean, true);
        orders jsonb; comps jsonb := '[]'::jsonb; chk jsonb := '[]'::jsonb; cats jsonb := '{}'::jsonb; st jsonb; co jsonb;
begin
  prof := public.crm_consumer_profile(p);
  select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'order_no', o.data ->> 'order_no', 'created_at', o.created_at, 'status', o.status, 'total', o.data -> 'total', 'payment_status', o.data ->> 'payment_status',
      'n', jsonb_array_length(coalesce(o.data -> 'items', '[]'::jsonb)), 'first', (o.data -> 'items' -> 0 ->> 'title'), 'courier', o.data -> 'dispatch' ->> 'courier', 'tracking', o.data -> 'dispatch' ->> 'tracking', 'pickup', coalesce((o.data ->> 'pickup')::boolean, false)) order by o.id desc), '[]'::jsonb) into orders
    from (select * from public.sp_orders where (ok and (data ->> 'phone') = u.mobile) or (data ->> 'customer_id') = u.id::text order by id desc limit 50) o;
  if pt.id is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'no', f.no, 'status', f.status, 'issue', f.data ->> 'issue', 'date', f.data ->> 'c_date', 'resolution', f.data ->> 'resolution', 'priority', f.data ->> 'priority', 'quote_id', f.quote_id) order by f.id desc), '[]'::jsonb) into comps
      from public.crm_flow_rec f where f.party_id = pt.id and f.kind = 'complaint' and f.deleted_at is null;
    select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'quote_id', c.quote_id, 'ym', c.ym, 'items', c.items, 'gen_kwh', c.gen_kwh, 'note', c.note, 'ticket', c.ticket, 'at', c.updated_at) order by c.ym desc), '[]'::jsonb) into chk
      from public.crm_checkup c where c.party_id = pt.id;
    select coalesce(jsonb_object_agg(d.id::text, d.data ->> 'cat'), '{}'::jsonb) into cats from public.crm_records d
      where d.kind = 'doc' and d.deleted_at is null and coalesce(d.data ->> 'cat', '') <> '' and (d.data ->> 'shared_quote') in (select id::text from public.crm_records where kind = 'quote' and party_id = pt.id);
  end if;
  select data into st from public.crm_settings where id = 1;
  co := coalesce(st -> 'company', '{}'::jsonb);
  return prof || jsonb_build_object('orders', orders, 'complaints', comps, 'checkups', chk, 'doc_cats', cats, 'checkup_keys', public.crm__checkup_keys(),
    'cfg', jsonb_build_object('tariff', coalesce(nullif(st -> 'hub' ->> 'tariff', '')::numeric, 7), 'gen', coalesce(nullif(st -> 'hub' ->> 'gen', '')::numeric, 4)),
    'company', jsonb_build_object('name', co ->> 'name', 'phone', co ->> 'phone', 'whatsapp', coalesce(nullif(co ->> 'whatsapp', ''), co ->> 'phone')));
end $$;

grant execute on function public.crm_checkup_save(jsonb), public.crm_consumer_complaint_new(jsonb), public.crm_consumer_refer(jsonb), public.crm_consumer_order(jsonb), public.crm_consumer_bill_doc(jsonb), public.crm_consumer_request(jsonb), public.sp_admin_order_dispatch(text, bigint, jsonb), public.crm_consumer_hub(jsonb) to anon, authenticated;
revoke execute on function public.crm__checkup_keys(), public.crm__cust_party(public.crm_users) from public, anon, authenticated;
-- ======================= Round 49: customer-wise Documents (CRM upload / replace / delete) =======================
-- Customer in files ko sirf dekh / download kar sakta hai. Company ka "Documents & Gallery" alag hai.
create or replace function public.crm_cdoc_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; b bytea; r public.crm_records; nm text := left(trim(coalesce(p ->> 'name', '')), 160);
        note text := left(trim(coalesce(p ->> 'note', '')), 300); cat text := coalesce(nullif(trim(p ->> 'cat'), ''), 'Other'); mm text := left(coalesce(nullif(p ->> 'mime', ''), 'application/octet-stream'), 80); rid bigint := nullif(p ->> 'replace_id', '')::bigint;
begin
  if not public.crm_can(s, 'docs.upload') then raise exception 'Aapko documents upload karne ki permission nahi hai'; end if;
  if cat not in ('Blueprint', 'Plant photo', 'Quotation', 'Bill', 'Certificate', 'Warranty', 'Agreement', 'Other') then cat := 'Other'; end if;
  select * into q from public.crm_records where id = nullif(p ->> 'quote_id', '')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Kaam (quotation) nahi mila'; end if;
  if coalesce(p ->> 'b64', '') <> '' then
    begin b := decode(p ->> 'b64', 'base64'); exception when others then raise exception 'File padh nahi paye'; end;
    if octet_length(b) = 0 then raise exception 'File khaali hai'; end if;
    if octet_length(b) > 3 * 1024 * 1024 then raise exception 'File 3 MB se badi hai — chhoti karke dalein'; end if;
  end if;
  if rid is not null then
    select * into r from public.crm_records where id = rid and kind = 'doc' and deleted_at is null and (data ->> 'shared_quote') = q.id::text;
    if r.id is null then raise exception 'Purani file nahi mili'; end if;
    update public.crm_records set title = coalesce(nullif(nm, ''), title), search = lower(coalesce(nullif(nm, ''), title) || ' ' || coalesce(q.ref, '')),
      data = data || jsonb_build_object('cat', cat, 'note', note) || case when b is not null then jsonb_build_object('mime', mm, 'size', octet_length(b), 'replaced_at', public.crm_iso_now(), 'replaced_by', (s).name) else '{}'::jsonb end
      where id = r.id returning * into r;
    if b is not null then update public.crm_files set data = b, mime = mm, size = octet_length(b) where rec_id = r.id; if not found then insert into public.crm_files(rec_id, mime, size, data) values (r.id, mm, octet_length(b), b); end if; end if;
    perform public.crm_log(s, 'edit', 'doc', r.id, 'Customer document ' || case when b is not null then 'badla: ' else 'update: ' end || r.title || ' (' || cat || ')');
    return jsonb_build_object('ok', true, 'id', r.id, 'replaced', b is not null);
  end if;
  if b is null then raise exception 'File chunein'; end if;
  if nm = '' then nm := 'file'; end if;
  insert into public.crm_records(kind, title, status, owner_id, party_id, data, search, created_by)
  values ('doc', nm, 'ok', (s).uid, q.party_id,
    jsonb_build_object('mime', mm, 'size', octet_length(b), 'note', note, 'cat', cat, 'attach_kind', 'party', 'attach_id', q.party_id::text, 'shared_quote', q.id, 'shared_ref', q.ref, 'shared_at', public.crm_iso_now(), 'shared_by', (s).name, 'cdoc', true),
    lower(nm || ' ' || coalesce(q.ref, '')), (s).uid) returning * into r;
  insert into public.crm_files(rec_id, mime, size, data) values (r.id, mm, octet_length(b), b);
  perform public.crm_log(s, 'share', 'doc', r.id, 'Customer document: ' || nm || ' (' || cat || ') → ' || coalesce(q.ref, ''));
  return jsonb_build_object('ok', true, 'id', r.id);
end $$;

create or replace function public.crm_cdoc_delete(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records; q public.crm_records;
begin
  if not public.crm_can(s, 'docs.delete') then raise exception 'Aapko document delete karne ki permission nahi hai'; end if;
  select * into r from public.crm_records where id = nullif(p ->> 'id', '')::bigint and kind = 'doc' and deleted_at is null and data ? 'shared_quote';
  if r.id is null then raise exception 'File nahi mili'; end if;
  select * into q from public.crm_records where id = (r.data ->> 'shared_quote')::bigint;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'File nahi mili'; end if;
  update public.crm_records set deleted_at = now() where id = r.id;
  delete from public.crm_files where rec_id = r.id;
  perform public.crm_log(s, 'delete', 'doc', r.id, 'Customer document hataya: ' || r.title);
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.crm_cdoc_save(jsonb), public.crm_cdoc_delete(jsonb) to anon, authenticated;

-- =====================================================================================================
-- ROUND 51 — (A) Customer HIDE / PERMANENT ERASE (bills kabhi nahi chhute)  (B) Settings -> Services & Limits (sirf Admin)
--   Dobara chalana safe hai. Naya table: crm_services. Koi purana data nahi badalta.
-- =====================================================================================================
create table if not exists public.crm_services (
  id text primary key,
  sort int not null default 0,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.crm_services enable row level security;
revoke all on public.crm_services from anon, authenticated;

-- ---------- defaults (asli free-plan limits; Admin baad me edit kar sakta hai) ----------
create or replace function public.crm__svc_defaults() returns jsonb language sql immutable as $f$
select $j$[
 {"id":"supabase","name":"Supabase","what":"Database + customer documents (files)","plan":"Free",
  "links":[{"t":"Dashboard","u":"https://supabase.com/dashboard"},{"t":"Usage","u":"https://supabase.com/dashboard/org/_/usage"},{"t":"Pricing / limits","u":"https://supabase.com/pricing"}],
  "metrics":[
   {"k":"db","label":"Database size","unit":"MB","limit":500,"auto":"db_mb","hint":"Apne aap naapa jata hai"},
   {"k":"files","label":"Files / documents (CRM)","unit":"MB","limit":1024,"auto":"files_mb","hint":"CRM ke documents + Supabase storage — apne aap"},
   {"k":"egress","label":"Egress (data bahar gaya) / mahina","unit":"GB","limit":5,"hint":"Supabase usage page se dekh kar bharein"},
   {"k":"mau","label":"Monthly active users","unit":"users","limit":50000,"hint":"Supabase usage page se"}]},
 {"id":"vercel","name":"Vercel","what":"Website / Store / CRM / Admin hosting","plan":"Hobby (Free)",
  "links":[{"t":"Dashboard","u":"https://vercel.com/dashboard"},{"t":"Usage","u":"https://vercel.com/dashboard/usage"},{"t":"Limits","u":"https://vercel.com/docs/limits"}],
  "metrics":[
   {"k":"bw","label":"Data transfer / mahina","unit":"GB","limit":100},
   {"k":"req","label":"Edge requests / mahina","unit":"requests","limit":1000000},
   {"k":"fn","label":"Function invocations / mahina","unit":"calls","limit":1000000},
   {"k":"dep","label":"Deployments / din","unit":"deploys","limit":100}]},
 {"id":"cloudinary","name":"Cloudinary","what":"Images / videos (links)","plan":"Free",
  "links":[{"t":"Console","u":"https://console.cloudinary.com"},{"t":"Pricing / limits","u":"https://cloudinary.com/pricing"}],
  "metrics":[{"k":"credits","label":"Credits / mahina (1 credit = 1 GB storage ya 1 GB bandwidth ya 1000 transformations)","unit":"credits","limit":25}]},
 {"id":"resend","name":"Resend","what":"Email (OTP, bill, reminders)","plan":"Free",
  "links":[{"t":"Dashboard","u":"https://resend.com/overview"},{"t":"Pricing / limits","u":"https://resend.com/pricing"}],
  "metrics":[
   {"k":"day","label":"Email aaj","unit":"emails","limit":100,"auto":"mail_day","hint":"CRM ke bheje mail apne aap ginte hain"},
   {"k":"month","label":"Email is mahine","unit":"emails","limit":3000,"auto":"mail_month","hint":"CRM ke bheje mail apne aap ginte hain"},
   {"k":"dom","label":"Domains","unit":"domains","limit":3}]},
 {"id":"github","name":"GitHub","what":"Code ka backup / deploy source","plan":"Free",
  "links":[{"t":"Repositories","u":"https://github.com"},{"t":"Billing / usage","u":"https://github.com/settings/billing"}],
  "metrics":[{"k":"actions","label":"Actions minutes / mahina (private repo)","unit":"minutes","limit":2000,"hint":"Limit apne plan se match karein"}]},
 {"id":"domain","name":"Domain (sunpowers.in)","what":"Website ka address","plan":"Paid (saalana)",
  "links":[{"t":"Domain provider","u":"https://www.google.com/search?q=domain+renew"}],
  "metrics":[{"k":"expiry","label":"Domain kab expire hoga","type":"date","hint":"Date bharein — 30 din pehle yaad dilayenge"}]}
]$j$::jsonb $f$;

-- ---------- evaluate (auto + manual -> % / status) ----------
create or replace function public.crm__svc_eval() returns jsonb language plpgsql stable security definer set search_path = public as $f$
declare auto jsonb; out jsonb := '[]'::jsonb; r record; m jsonb; ms jsonb; v numeric; lim numeric; pct numeric; st text; d date; dl int; sbytes numeric := 0;
begin
  if to_regclass('storage.objects') is not null then
    begin execute 'select coalesce(sum((metadata->>''size'')::numeric),0) from storage.objects' into sbytes; exception when others then sbytes := 0; end;
  end if;
  auto := jsonb_build_object(
    'db_mb', round(pg_database_size(current_database()) / 1048576.0, 1),
    'files_mb', round((coalesce((select sum(size) from public.crm_files), 0) + sbytes) / 1048576.0, 1),
    'mail_day', (select count(*) from public.crm_mail_log where at >= date_trunc('day', now())),
    'mail_month', (select count(*) from public.crm_mail_log where at >= date_trunc('month', now())));
  for r in select * from public.crm_services where id <> '_meta' order by sort, id loop
    ms := '[]'::jsonb;
    for m in select * from jsonb_array_elements(coalesce(r.data -> 'metrics', '[]'::jsonb)) loop
      v := null; pct := null; st := 'none';
      if coalesce(m ->> 'type', 'num') = 'date' then
        d := nullif(m ->> 'used', '')::date; 
        if d is not null then dl := d - (now() at time zone 'Asia/Kolkata')::date;
          st := case when dl <= 0 then 'over' when dl <= 30 then 'warn' else 'ok' end;
          m := m || jsonb_build_object('days_left', dl); end if;
      else
        lim := nullif(m ->> 'limit', '')::numeric;
        if nullif(m ->> 'auto', '') is not null and auto ? (m ->> 'auto') then v := (auto ->> (m ->> 'auto'))::numeric; m := m || jsonb_build_object('is_auto', true);
        else v := nullif(m ->> 'used', '')::numeric; end if;
        if v is not null and lim is not null and lim > 0 then pct := round(v * 100.0 / lim, 1); st := case when pct >= 100 then 'over' when pct >= 80 then 'warn' else 'ok' end; end if;
        m := m || jsonb_build_object('val', v, 'pct', pct);
      end if;
      ms := ms || jsonb_build_array(m || jsonb_build_object('state', st));
    end loop;
    out := out || jsonb_build_array((r.data - 'metrics') || jsonb_build_object('metrics', ms, 'sort', r.sort));
  end loop;
  return out;
end $f$;

create or replace function public.crm__svc_alerts() returns int language sql stable security definer set search_path = public as $f$
  select count(*)::int from jsonb_array_elements(public.crm__svc_eval()) s, jsonb_array_elements(s -> 'metrics') m where m ->> 'state' in ('warn', 'over') $f$;
revoke all on function public.crm__svc_eval() from public, anon, authenticated;
revoke all on function public.crm__svc_alerts() from public, anon, authenticated;

create or replace function public.crm_services_get(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); d jsonb; i int := 0;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  if not exists (select 1 from public.crm_services where id = '_meta') then
    for d in select * from jsonb_array_elements(public.crm__svc_defaults()) loop
      i := i + 1; insert into public.crm_services(id, sort, data) values (d ->> 'id', i * 10, d) on conflict (id) do nothing;
    end loop;
    insert into public.crm_services(id, sort, data) values ('_meta', -1, '{}'::jsonb);
  end if;
  return jsonb_build_object('services', public.crm__svc_eval(), 'defaults', public.crm__svc_defaults(), 'today', (now() at time zone 'Asia/Kolkata')::date);
end $f$;

create or replace function public.crm_services_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); arr jsonb := p -> 'services'; x jsonb; mx jsonb; ms jsonb; links jsonb; l jsonb; i int := 0; sid text; old jsonb; om text; used text; oused text; today text := ((now() at time zone 'Asia/Kolkata')::date)::text; k text;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  if jsonb_typeof(arr) <> 'array' or jsonb_array_length(arr) > 30 then raise exception 'Services list galat ya bahut badi'; end if;
  create temp table if not exists _svc_new(id text, sort int, data jsonb) on commit drop;
  truncate _svc_new;
  for x in select * from jsonb_array_elements(arr) loop
    i := i + 1;
    sid := lower(regexp_replace(coalesce(x ->> 'id', ''), '[^a-zA-Z0-9_-]', '', 'g'));
    if sid = '' or sid = '_meta' then sid := 'svc' || (extract(epoch from clock_timestamp()) * 1000)::bigint::text || i; end if;
    if length(left(trim(coalesce(x ->> 'name', '')), 60)) < 2 then raise exception 'Service ka naam likhein'; end if;
    select data into old from public.crm_services where id = sid;
    links := '[]'::jsonb;
    for l in select * from jsonb_array_elements(coalesce(x -> 'links', '[]'::jsonb)) loop
      if (l ->> 'u') ~* '^https://[^ ]{4,255}$' and length(coalesce(l ->> 't', '')) between 1 and 40 then links := links || jsonb_build_array(jsonb_build_object('t', l ->> 't', 'u', l ->> 'u')); end if;
    end loop;
    ms := '[]'::jsonb;
    for mx in select * from jsonb_array_elements(coalesce(x -> 'metrics', '[]'::jsonb)) loop
      exit when jsonb_array_length(ms) >= 12;
      k := lower(regexp_replace(coalesce(mx ->> 'k', ''), '[^a-zA-Z0-9_-]', '', 'g'));
      if k = '' then k := 'm' || jsonb_array_length(ms); end if;
      used := left(coalesce(mx ->> 'used', ''), 30);
      if coalesce(mx ->> 'type', 'num') = 'date' then
        if used <> '' and used !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Date galat: %', used; end if;
      elsif used <> '' and used !~ '^-?\d+(\.\d+)?$' then raise exception 'Sirf number likhein: %', left(used, 20); end if;
      oused := null;
      select o ->> 'used' into oused from jsonb_array_elements(coalesce(old -> 'metrics', '[]'::jsonb)) o where o ->> 'k' = k limit 1;
      select o ->> 'at' into om from jsonb_array_elements(coalesce(old -> 'metrics', '[]'::jsonb)) o where o ->> 'k' = k limit 1;
      ms := ms || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'k', k, 'label', left(trim(coalesce(mx ->> 'label', k)), 120), 'unit', left(coalesce(mx ->> 'unit', ''), 20),
        'type', case when mx ->> 'type' = 'date' then 'date' end,
        'limit', case when coalesce(mx ->> 'limit', '') ~ '^\d+(\.\d+)?$' then (mx ->> 'limit')::numeric end,
        'auto', case when mx ->> 'auto' in ('db_mb', 'files_mb', 'mail_day', 'mail_month') then mx ->> 'auto' end,
        'hint', nullif(left(coalesce(mx ->> 'hint', ''), 160), ''),
        'used', nullif(used, ''),
        'at', case when used = '' then null when oused is distinct from used then today else coalesce(om, today) end)));
    end loop;
    insert into _svc_new values (sid, i * 10, jsonb_strip_nulls(jsonb_build_object('id', sid, 'name', left(trim(x ->> 'name'), 60), 'what', nullif(left(coalesce(x ->> 'what', ''), 160), ''),
      'plan', nullif(left(coalesce(x ->> 'plan', ''), 60), ''), 'note', nullif(left(coalesce(x ->> 'note', ''), 400), ''), 'links', links, 'metrics', ms)));
  end loop;
  delete from public.crm_services where id <> '_meta';
  insert into public.crm_services(id, sort, data) select id, sort, data from _svc_new on conflict (id) do update set sort = excluded.sort, data = excluded.data, updated_at = now();
  insert into public.crm_services(id, sort, data) values ('_meta', -1, '{}'::jsonb) on conflict (id) do nothing;
  perform public.crm_log(s, 'update', 'services', null, 'Services & Limits badle (' || i || ' services)');
  return jsonb_build_object('ok', true, 'services', public.crm__svc_eval());
end $f$;
grant execute on function public.crm_services_get(jsonb), public.crm_services_save(jsonb) to anon, authenticated;

-- ---------- (A) CUSTOMER HIDE / ERASE ----------
-- bills (invoice + payment) KABHI nahi chhute. Customer ki row sirf naam / mobile / pata / GST ke saath rehti hai (bill par chhapne ke liye).
create or replace function public.crm__cust_scope(pid bigint) returns jsonb language plpgsql stable security definer set search_path = public as $f$
declare pr public.crm_records; u bigint[]; keepq bigint[];
begin
  select * into pr from public.crm_records where id = pid and kind = 'party';
  if pr.id is null then raise exception 'Customer nahi mila'; end if;
  select array_agg(id) into u from public.crm_users where role = 'consumer' and mobile = pr.mobile and pr.mobile is not null and pr.mobile <> '';
  select array_agg(distinct nullif(data ->> 'quote_id', '')::bigint) into keepq from public.crm_records where kind = 'invoice' and party_id = pid;
  return jsonb_build_object(
    'party', pr.id, 'name', pr.title, 'mobile', pr.mobile, 'users', coalesce(to_jsonb(u), '[]'::jsonb), 'keep_quotes', coalesce(to_jsonb(keepq), '[]'::jsonb),
    'bills', (select count(*) from public.crm_records where party_id = pid and kind = 'invoice'),
    'payments', (select count(*) from public.crm_records where party_id = pid and kind = 'payment'),
    'bill_amount', (select coalesce(sum(amount), 0) from public.crm_records where party_id = pid and kind = 'invoice' and deleted_at is null));
end $f$;

create or replace function public.crm_cust_erase_preview(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); sc jsonb; pid bigint := (p ->> 'id')::bigint; keepq bigint[]; mob text;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  sc := public.crm__cust_scope(pid); mob := sc ->> 'mobile';
  select coalesce(array_agg(x::bigint), '{}') into keepq from jsonb_array_elements_text(sc -> 'keep_quotes') x;
  return sc || jsonb_build_object(
    'leads', (select count(*) from public.crm_records where kind = 'lead' and (party_id = pid or (mob is not null and mob <> '' and mobile = mob))),
    'quotes', (select count(*) from public.crm_records where kind = 'quote' and party_id = pid and not (id = any (keepq))),
    'quotes_kept', (select count(*) from public.crm_records where kind = 'quote' and party_id = pid and id = any (keepq)),
    'docs', (select count(*) from public.crm_records where kind = 'doc' and party_id = pid),
    'files_bytes', coalesce((select sum(f.size) from public.crm_files f join public.crm_records d on d.id = f.rec_id where d.party_id = pid), 0),
    'plants', (select count(*) from public.crm_records where kind = 'plant' and party_id = pid),
    'reminders', (select count(*) from public.crm_records where kind in ('reminder', 'note') and party_id = pid),
    'other', (select count(*) from public.crm_records where party_id = pid and kind not in ('invoice', 'payment', 'lead', 'quote', 'doc', 'plant', 'reminder', 'note')),
    'flows', (select count(*) from public.crm_flow_rec where party_id = pid),
    'decls', (select count(*) from public.crm_decl where party_id = pid),
    'checkups', (select count(*) from public.crm_checkup where party_id = pid),
    'logins', jsonb_array_length(sc -> 'users'),
    'enquiries', (select count(*) from public.sp_enquiries where mob is not null and mob <> '' and (data ->> 'mobile' = mob or data ->> 'phone' = mob)));
end $f$;

create or replace function public.crm_cust_erase_backup(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); sc jsonb; pid bigint := (p ->> 'id')::bigint; mob text; fsum bigint; out jsonb;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  sc := public.crm__cust_scope(pid); mob := sc ->> 'mobile';
  select coalesce(sum(f.size), 0) into fsum from public.crm_files f join public.crm_records d on d.id = f.rec_id where d.party_id = pid;
  out := jsonb_build_object('kind', 'sunpowers-customer-backup', 'at', now(), 'customer', sc ->> 'name', 'mobile', mob,
    'records', coalesce((select jsonb_agg(to_jsonb(r) - 'search') from public.crm_records r where r.id = pid or r.party_id = pid or (r.kind = 'lead' and mob is not null and mob <> '' and r.mobile = mob)), '[]'::jsonb),
    'flows', coalesce((select jsonb_agg(to_jsonb(f)) from public.crm_flow_rec f where f.party_id = pid), '[]'::jsonb),
    'decls', coalesce((select jsonb_agg(to_jsonb(d) - 'token') from public.crm_decl d where d.party_id = pid), '[]'::jsonb),
    'checkups', coalesce((select jsonb_agg(to_jsonb(c)) from public.crm_checkup c where c.party_id = pid), '[]'::jsonb),
    'logins', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'mobile', u.mobile, 'email', u.email, 'created_at', u.created_at)) from public.crm_users u where u.role = 'consumer' and u.mobile = mob and mob <> ''), '[]'::jsonb),
    'enquiries', coalesce((select jsonb_agg(to_jsonb(e)) from public.sp_enquiries e where mob is not null and mob <> '' and (e.data ->> 'mobile' = mob or e.data ->> 'phone' = mob)), '[]'::jsonb),
    'files_bytes', fsum);
  if fsum <= 15 * 1024 * 1024 then
    out := out || jsonb_build_object('files', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'rec_id', f.rec_id, 'mime', f.mime, 'size', f.size, 'b64', encode(f.data, 'base64')))
      from public.crm_files f join public.crm_records d on d.id = f.rec_id where d.party_id = pid), '[]'::jsonb));
  else
    out := out || jsonb_build_object('files_skipped', true, 'files_note', 'Files 15 MB se zyada hain — pehle CRM me customer ke Documents se alag download kar lein');
  end if;
  perform public.crm_log(s, 'backup', 'party', pid, 'Customer ka backup nikala: ' || (sc ->> 'name'));
  return out;
end $f$;

create or replace function public.crm_cust_hide(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pr public.crm_records; why text := left(trim(coalesce(p ->> 'reason', '')), 300);
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  select * into pr from public.crm_records where id = (p ->> 'id')::bigint and kind = 'party';
  if pr.id is null then raise exception 'Customer nahi mila'; end if;
  if pr.deleted_at is not null then raise exception 'Ye customer pehle se hata hua hai'; end if;
  update public.crm_records set deleted_at = now(), deleted_by = (s).uid, delete_reason = 'HIDDEN: ' || why, data = data || jsonb_build_object('hidden', true, 'hidden_at', now()) where id = pr.id;
  perform public.crm_log(s, 'hide', 'party', pr.id, 'Customer chhupaya: ' || pr.title || case when why <> '' then ' — ' || why else '' end);
  return jsonb_build_object('ok', true);
end $f$;

create or replace function public.crm_cust_unhide(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pr public.crm_records;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  select * into pr from public.crm_records where id = (p ->> 'id')::bigint and kind = 'party';
  if pr.id is null or coalesce(pr.data ->> 'hidden', '') <> 'true' or coalesce(pr.data ->> 'erased', '') = 'true' then raise exception 'Ye chhupa hua customer nahi hai'; end if;
  update public.crm_records set deleted_at = null, deleted_by = null, delete_reason = null, data = data - 'hidden' - 'hidden_at' where id = pr.id;
  perform public.crm_log(s, 'unhide', 'party', pr.id, 'Customer wapas dikhaya: ' || pr.title);
  return jsonb_build_object('ok', true);
end $f$;

create or replace function public.crm_cust_erase(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pid bigint := (p ->> 'id')::bigint; pr public.crm_records; pe text; sc jsonb; keepq bigint[]; mob text; uids bigint[]; did bigint[]; n jsonb;
        why text := left(trim(coalesce(p ->> 'reason', '')), 300); keep jsonb; cnt_f bigint;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  select * into pr from public.crm_records where id = pid and kind = 'party';
  if pr.id is null then raise exception 'Customer nahi mila'; end if;
  if coalesce(pr.data ->> 'erased', '') = 'true' then raise exception 'Ye customer pehle hi hamesha ke liye hata diya gaya hai'; end if;
  if coalesce((p ->> 'backup_done')::boolean, false) is not true then raise exception 'Pehle backup download karein'; end if;
  if lower(trim(coalesce(p ->> 'confirm_name', ''))) <> lower(trim(pr.title)) then raise exception 'Customer ka naam bilkul wahi likhein jo upar hai'; end if;
  pe := public.crm_auth_pin_check(public.crm_auth_find('admin', 'admin'), p ->> 'pin');
  if pe is not null then return jsonb_build_object('error', pe); end if;
  sc := public.crm__cust_scope(pid); mob := pr.mobile;
  select coalesce(array_agg(x::bigint), '{}') into keepq from jsonb_array_elements_text(sc -> 'keep_quotes') x;
  select coalesce(array_agg(x::bigint), '{}') into uids from jsonb_array_elements_text(sc -> 'users') x;
  n := public.crm_cust_erase_preview(p);
  -- documents + files
  select coalesce(array_agg(id), '{}') into did from public.crm_records where party_id = pid and kind = 'doc';
  delete from public.crm_files where rec_id = any (did);
  -- children (invoice / payment / bill ki quote chhodkar)
  delete from public.crm_records where party_id = pid and kind not in ('invoice', 'payment') and not (id = any (keepq));
  delete from public.crm_records where kind = 'lead' and mob is not null and mob <> '' and mobile = mob;
  delete from public.crm_flow_rec where party_id = pid;
  delete from public.crm_decl where party_id = pid;
  delete from public.crm_checkup where party_id = pid;
  delete from public.crm_consumer_plants where user_id = any (uids);
  delete from public.crm_sessions where user_id = any (uids);
  delete from public.crm_devices where user_id = any (uids);
  delete from public.crm_users where id = any (uids) and role = 'consumer';
  if mob is not null and mob <> '' then delete from public.sp_enquiries where data ->> 'mobile' = mob or data ->> 'phone' = mob; end if;
  -- customer ki row: sirf bill par chhapne layak details
  keep := jsonb_strip_nulls(jsonb_build_object('name', pr.data -> 'name', 'type', coalesce(pr.data -> 'type', '"customer"'::jsonb), 'cust_id', pr.data -> 'cust_id', 'mobile', pr.data -> 'mobile',
    'address', pr.data -> 'address', 'city', pr.data -> 'city', 'state', pr.data -> 'state', 'pincode', pr.data -> 'pincode', 'gstin', pr.data -> 'gstin', 'gst', pr.data -> 'gst',
    'erased', true, 'erased_at', now()));
  update public.crm_records set data = keep, status = '', assigned_to = null, due_at = null, deleted_at = now(), deleted_by = (s).uid, delete_reason = 'ERASED: ' || why where id = pid;
  perform public.crm_log(s, 'erase', 'party', pid, 'Customer hamesha ke liye hataya (bill rakhe): ' || pr.title || ' — ' || why);
  return jsonb_build_object('ok', true, 'removed', n);
end $f$;

create or replace function public.crm_cust_gone_list(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token');
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'name', r.title, 'mobile', r.mobile, 'cust_id', r.data ->> 'cust_id',
      'mode', case when r.data ->> 'erased' = 'true' then 'erased' else 'hidden' end, 'at', r.deleted_at, 'reason', r.delete_reason, 'by', public.crm_uname(r.deleted_by),
      'bills', (select count(*) from public.crm_records b where b.party_id = r.id and b.kind = 'invoice')) order by r.deleted_at desc)
    from public.crm_records r where r.kind = 'party' and r.deleted_at is not null and (r.data ->> 'hidden' = 'true' or r.data ->> 'erased' = 'true')), '[]'::jsonb);
end $f$;
grant execute on function public.crm_cust_erase_preview(jsonb), public.crm_cust_erase_backup(jsonb), public.crm_cust_hide(jsonb), public.crm_cust_unhide(jsonb), public.crm_cust_erase(jsonb), public.crm_cust_gone_list(jsonb) to anon, authenticated;
revoke all on function public.crm__cust_scope(bigint) from public, anon, authenticated;


-- ---------- BUG FIX: Admin PIN check (Restore / Login-settings save / Admin-keep) purane 'crm','admin' lookup se "Ye ID nahi mili" deta tha ----------
CREATE OR REPLACE FUNCTION public.crm_restore(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pe text; part text := coalesce(p ->> 'part', ''); rows jsonb := coalesce(p -> 'rows', '[]'::jsonb);
  allowed text[] := array['crm_records', 'crm_counters', 'crm_expenses', 'sp_orders', 'sp_enquiries', 'sp_store', 'crm_files'];
  cols text; setl text; n int := 0; pk text;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  pe := public.crm_auth_pin_check(public.crm_auth_find('admin', 'admin'), p ->> 'pin');
  if pe is not null then return jsonb_build_object('error', pe); end if;
  if not (part = any (allowed)) or to_regclass('public.' || part) is null then raise exception 'Ye hissa wapas nahi laya ja sakta: %', part; end if;
  if jsonb_typeof(rows) <> 'array' then raise exception 'Backup file galat hai'; end if;
  if jsonb_array_length(rows) > 600 then raise exception 'Ek baar me bahut zyada rows'; end if;
  if jsonb_array_length(rows) = 0 then return jsonb_build_object('part', part, 'restored', 0); end if;
  perform set_config('sp.restoring', 'on', true);
  pk := case part when 'crm_counters' then 'key' when 'sp_store' then 'id' else 'id' end;
  if part = 'crm_files' then
    insert into public.crm_files(id, rec_id, mime, size, data)
    select (x ->> 'id')::bigint, (x ->> 'rec_id')::bigint, coalesce(x ->> 'mime', 'application/octet-stream'), coalesce((x ->> 'size')::int, 0), decode(x ->> 'b64', 'base64')
    from jsonb_array_elements(rows) x
    on conflict (id) do update set rec_id = excluded.rec_id, mime = excluded.mime, size = excluded.size, data = excluded.data;
    get diagnostics n = row_count;
  else
    select string_agg(format('%I', column_name), ', ' order by ordinal_position),
           string_agg(case when column_name = pk then null when part = 'crm_counters' and column_name = 'n' then 'n = greatest(public.crm_counters.n, excluded.n)' else format('%1$I = excluded.%1$I', column_name) end, ', ' order by ordinal_position)
      into cols, setl from information_schema.columns where table_schema = 'public' and table_name = part;
    if part = 'crm_records' then
      -- never bring back a row that was removed for good on purpose: deleted rows stay as the backup has them
      null;
    end if;
    execute format('insert into public.%1$I (%2$s) select %2$s from jsonb_populate_recordset(null::public.%1$I, $1) on conflict (%3$I) do update set %4$s', part, cols, pk, setl) using rows;
    get diagnostics n = row_count;
  end if;
  if part in ('crm_records', 'crm_expenses', 'sp_orders', 'sp_enquiries', 'crm_files') and pg_get_serial_sequence('public.' || part, 'id') is not null then
    execute format('select setval(pg_get_serial_sequence(%L, ''id''), greatest((select coalesce(max(id), 1) from public.%I), 1))', 'public.' || part, part);
  end if;
  perform public.crm_log(s, 'restore', part, null, 'Backup se wapas laya: ' || part || ' (' || n || ' rows)');
  return jsonb_build_object('part', part, 'restored', n);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_auth_admin_save(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); au jsonb := coalesce(p -> 'auth', '{}'::jsonb); pe text; e1 text := lower(trim(coalesce(p ->> 'email', ''))); e2 text := lower(trim(coalesce(p ->> 'email2', '')));
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  pe := public.crm_auth_pin_check(public.crm_auth_find('admin', 'admin'), p ->> 'pin');
  if pe is not null then return jsonb_build_object('error', pe); end if;
  if e1 !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Admin ka sahi email likhein'; end if;
  if e2 <> '' and e2 !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Doosra email sahi nahi hai'; end if;
  update public.crm_auth_admin set email = e1, email2 = e2, updated_at = now() where id = 1;
  update public.crm_settings set data = jsonb_set(data, '{auth}', coalesce(data -> 'auth', '{}'::jsonb) || jsonb_build_object(
      'from', left(coalesce(au ->> 'from', 'Sunpowers <no-reply@sunpowers.in>'), 120),
      'urls', jsonb_build_object('store', coalesce(au #>> '{urls,store}', ''), 'crm', coalesce(au #>> '{urls,crm}', ''), 'admin', coalesce(au #>> '{urls,admin}', ''))))
  where id = 1;
  if coalesce(p ->> 'resend_key', '') <> '' then
    update public.crm_settings set secrets = coalesce(secrets, '{}'::jsonb) || jsonb_build_object('resend_api_key', trim(p ->> 'resend_key')) where id = 1;
  end if;
  perform public.crm_log(s, 'settings', null, null, 'Login / email settings badli');
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_admin_keep(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pe text; on_ boolean := coalesce((p ->> 'on')::boolean, false);
begin
  if not public.crm_is_admin(s) or (s).uid <> 0 then raise exception 'Ye option sirf Admin ke liye hai'; end if;
  pe := public.crm_auth_pin_check(public.crm_auth_find('admin', 'admin'), p ->> 'pin');
  if pe is not null then return jsonb_build_object('error', pe); end if;
  update public.crm_sessions set keep = on_, expires_at = now() + case when on_ then interval '365 days' else interval '12 hours' end where token = p ->> 'token' and user_id = 0;
  perform public.crm_log(s, 'settings', null, null, case when on_ then 'Admin login is device par yaad rakha' else 'Admin login yaad rakhna band' end);
  return jsonb_build_object('ok', true, 'keep', on_);
end $function$;

-- ---------- bell: Admin ko service alert ----------
CREATE OR REPLACE FUNCTION public.crm_pulse(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); since timestamptz := coalesce(nullif(p ->> 'since', '')::timestamptz, now() - interval '3 days'); items jsonb := '[]'::jsonb;
begin
  if public.crm_can(s, 'orders.view') then
    items := items || coalesce((select jsonb_agg(jsonb_build_object('type', 'order', 'id', id, 'at', created_at, 'title', 'Naya order #' || id || ' — ' || coalesce(data ->> 'name', ''), 'amount', data -> 'total'))
      from (select * from public.sp_orders where created_at > since order by id desc limit 20) o), '[]'::jsonb);
    items := items || coalesce((select jsonb_agg(jsonb_build_object('type', 'enquiry', 'id', id, 'at', created_at, 'title', 'Nayi enquiry — ' || coalesce(data ->> 'name', '') || ' (' || coalesce(data ->> 'source', 'store') || ')'))
      from (select * from public.sp_enquiries where created_at > since order by id desc limit 20) e), '[]'::jsonb);
  end if;
  items := items || coalesce((select jsonb_agg(jsonb_build_object('type', 'lead', 'id', id, 'at', updated_at, 'title', 'Lead mili: ' || title))
    from (select * from public.crm_records where kind = 'lead' and deleted_at is null and assigned_to = (s).uid and owner_id <> (s).uid and updated_at > since order by id desc limit 20) l), '[]'::jsonb);
  items := items || coalesce((select jsonb_agg(jsonb_build_object('type', 'reminder', 'id', id, 'at', created_at, 'title', 'Naya kaam: ' || title || ' (' || to_char(due_at, 'DD-MM') || ')'))
    from (select * from public.crm_records where kind = 'reminder' and deleted_at is null and assigned_to = (s).uid and owner_id <> (s).uid and created_at > since order by id desc limit 20) l), '[]'::jsonb);
  if public.crm_can(s, 'plants.verify') then
    items := items || coalesce((select jsonb_agg(jsonb_build_object('type', 'plant', 'id', id, 'at', created_at, 'title', 'Plant verify karna hai: ' || title))
      from (select * from public.crm_records where kind = 'plant' and deleted_at is null and status = 'pending' and created_at > since order by id desc limit 20) l), '[]'::jsonb);
  end if;
  if public.crm_can(s, 'users.manage') then
    items := items || coalesce((select jsonb_agg(jsonb_build_object('type', 'user', 'id', id, 'at', created_at, 'title', 'Nayi ID verify karni hai: ' || name || ' (' || role || ')'))
      from (select * from public.crm_users where status = 'pending' and created_at > since order by id desc limit 20) l), '[]'::jsonb);
  end if;
  if public.crm_is_admin(s) then
    declare n int := public.crm__svc_alerts();
    begin
      if n > 0 then items := items || jsonb_build_array(jsonb_build_object('type', 'svc', 'id', 0, 'at', date_trunc('day', now()), 'title', 'Services & Limits: ' || n || ' service ki limit / date paas hai — Settings me dekhein')); end if;
    end;
  end if;
  return jsonb_build_object('now', now(), 'items', items);
end $function$;
-- =====================================================================================================
-- ROUND 52 — Quotation: ek link, andar OPTIONS (brand), final par LOCK, link se Accept / Badlav chahiye / Call back,
--            link expiry (+ / - / pause), accepted quotation ka expire hona band, quotation PDF me bank box setting.
--   Sirf MANUAL quotations ke liye (Online Store ka flow nahi badla). Link se koi payment nahi.
--   Dobara chalana safe hai. Naye column: sp_shares.quote_id / live / expiry_manual / bad_tries / bad_at.
-- =====================================================================================================
alter table public.sp_shares add column if not exists quote_id bigint;
alter table public.sp_shares add column if not exists live boolean not null default false;
alter table public.sp_shares add column if not exists expiry_manual boolean not null default false;
alter table public.sp_shares add column if not exists bad_tries int not null default 0;
alter table public.sp_shares add column if not exists bad_at timestamptz;
create index if not exists sp_shares_quote_idx on public.sp_shares(quote_id) where quote_id is not null;

-- ---------- link ki auto expiry: Valid till + 7 din; lock ke baad lamba; rejected par chhota ----------
create or replace function public.crm__quote_link_expiry(q public.crm_records) returns timestamptz language plpgsql stable security definer set search_path = public as $f$
declare vt date;
begin
  if q.data ->> 'closed' = 'true' then return now() + interval '30 days'; end if;
  if q.data -> 'locked' is not null then return greatest(now() + interval '365 days', now()); end if;
  if q.status = 'rejected' then return now() + interval '3 days'; end if;
  begin vt := (q.data ->> 'valid_till')::date; exception when others then vt := null; end;
  if vt is null then return now() + interval '30 days'; end if;
  return ((vt + 8)::timestamp) at time zone 'Asia/Kolkata';
end $f$;
revoke all on function public.crm__quote_link_expiry(public.crm_records) from public, anon, authenticated;

create or replace function public.crm__quote_share_sync() returns trigger language plpgsql security definer set search_path = public as $f$
begin
  update public.sp_shares set expires_at = public.crm__quote_link_expiry(new) where quote_id = new.id and live and not expiry_manual;
  return new;
end $f$;
drop trigger if exists crm_quote_share_sync on public.crm_records;
create trigger crm_quote_share_sync after update of data, status on public.crm_records for each row when (new.kind = 'quote') execute function public.crm__quote_share_sync();

-- ---------- accepted quotation ab expire nahi hoti (pehle Valid till ke baad "expired" ho jati thi) ----------
create or replace function public.crm_quote_expire_daily() returns void language plpgsql security definer set search_path = public as $f$
declare td text := public.crm_today()::text;
begin
  if coalesce((select data #>> '{stock,expire_day}' from public.crm_settings where id = 1), '') = td then return; end if;
  update public.crm_records set status = 'expired', data = data || jsonb_build_object('pre_expire', status, 'expired_on', td), updated_at = now()
  where kind = 'quote' and deleted_at is null and status in ('draft', 'sent') and data -> 'locked' is null and coalesce(data ->> 'valid_till', '') ~ '^\d{4}-\d{2}-\d{2}$' and (data ->> 'valid_till') < td;
  update public.crm_settings set data = jsonb_set(coalesce(data, '{}'::jsonb), '{stock,expire_day}', to_jsonb(td), true) where id = 1;
end $f$;
-- jo accepted quotation pehle galti se expired ho chuki (kaam chal raha hai) unhe wapas accepted
update public.crm_records set status = coalesce(nullif(data ->> 'pre_expire', ''), 'accepted'), data = data - 'pre_expire' - 'expired_on'
 where kind = 'quote' and status = 'expired' and deleted_at is null and data ->> 'pre_expire' = 'accepted';

-- ---------- option ki jaanch (rate ki limit, inventory item) ----------
create or replace function public.crm__opt_guard(s public.crm_ses, p_lines jsonb, p_disc numeric) returns jsonb language plpgsql security definer set search_path = public as $f$
declare l jsonb; it public.crm_records; calc jsonb; lim numeric;
begin
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'Kam se kam 1 item jodein'; end if;
  for l in select * from jsonb_array_elements(p_lines) loop
    if public.crm_num(l -> 'qty') <= 0 then raise exception 'Har item ki Qty likhein'; end if;
    if coalesce(l ->> 'kind', 'product') <> 'project' and coalesce(l ->> 'item_id', '') = '' then raise exception 'Har item Inventory se hi chunna hoga — "%" Inventory me nahi hai.', coalesce(nullif(l ->> 'name', ''), '?'); end if;
    if coalesce(l ->> 'item_id', '') <> '' and not exists (select 1 from public.crm_records i where i.id = (l ->> 'item_id')::bigint and i.kind = 'item') then raise exception '"%" Inventory me nahi mila. Item dobara chunein.', coalesce(nullif(l ->> 'name', ''), '?'); end if;
  end loop;
  calc := public.crm_doc_calc(jsonb_build_object('lines', p_lines, 'discount', p_disc));
  if not public.crm_can(s, 'quotes.discount_any') then
    for l in select * from jsonb_array_elements(p_lines) loop
      if coalesce(l ->> 'kind', 'product') <> 'project' and coalesce(l ->> 'item_id', '') <> '' then
        select * into it from public.crm_records where id = (l ->> 'item_id')::bigint and kind = 'item';
        if it.id is not null and public.crm_num(it.data -> 'cost_price') > 0 and public.crm_num(l -> 'price') < public.crm_num(it.data -> 'cost_price') - 0.009 then raise exception '"%" ka rate kharid rate se kam nahi ho sakta', it.title; end if;
        if it.id is not null and public.crm_num(it.data -> 'min_price') > 0 and public.crm_num(l -> 'price') < public.crm_num(it.data -> 'min_price') then raise exception '"%" ka rate minimum rate se kam hai — Admin se permission lein', it.title; end if;
      end if;
    end loop;
    select coalesce(nullif(public.crm_num(meta -> 'max_discount_pct'), 0), public.crm_role_discount(role)) into lim from public.crm_users where id = (s).uid;
    if (s).uid <> 0 and public.crm_num(calc -> 'discount') > 0 and public.crm_num(calc -> 'discount') > coalesce(lim, 0) * (public.crm_num(calc -> 'subtotal') + public.crm_num(calc -> 'gst_total')) / 100 + 0.009 then raise exception 'Discount aapki limit (% %%) se zyada hai', coalesce(lim, 0); end if;
  end if;
  return calc;
end $f$;
revoke all on function public.crm__opt_guard(public.crm_ses, jsonb, numeric) from public, anon, authenticated;

-- ---------- staff: option jodna / badalna / hatana ----------
create or replace function public.crm_quote_option_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; o jsonb := coalesce(p -> 'opt', '{}'::jsonb); prim text; oid text; alt jsonb; calc jsonb; e jsonb; n int; found boolean := false; lbl text; newo jsonb; ids text := 'BCDEFGH'; i int;
begin
  perform public.crm_need(s, 'quotes.edit');
  select * into q from public.crm_records where id = (p ->> 'id')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if q.data -> 'locked' is not null then raise exception 'Customer ne final kar diya — ab naya option nahi jud sakta'; end if;
  if q.status not in ('draft', 'sent') then raise exception 'Sirf draft / bheji hui quotation me option jodein'; end if;
  prim := coalesce(q.data ->> 'opt_id', 'A'); alt := coalesce(q.data -> 'alt', '[]'::jsonb); oid := nullif(trim(coalesce(o ->> 'id', '')), '');
  lbl := left(trim(coalesce(o ->> 'label', '')), 60);
  if oid = prim then   -- sirf pehle option ka naam
    if lbl = '' then raise exception 'Option ka naam likhein'; end if;
    update public.crm_records set data = data || jsonb_build_object('opt_label', lbl), updated_at = now() where id = q.id;
  elsif oid is null then   -- naya option: pehle option ki copy
    if lbl = '' then raise exception 'Option ka naam likhein (jaise: Adani 5 kW)'; end if;
    select count(*) into n from jsonb_array_elements(alt) x where coalesce(x ->> 'dropped', '') <> 'true';
    if n >= 4 then raise exception 'Ek quotation me 5 se zyada option nahi'; end if;
    for i in 1..length(ids) loop oid := substr(ids, i, 1); exit when oid <> prim and not exists (select 1 from jsonb_array_elements(alt) x where x ->> 'id' = oid); end loop;
    newo := jsonb_build_object('id', oid, 'label', lbl, 'lines', q.data -> 'lines', 'discount', coalesce(q.data -> 'discount', '0'::jsonb), 'subtotal', q.data -> 'subtotal', 'gst_total', q.data -> 'gst_total', 'grand', q.data -> 'grand', 'qtitle', q.data -> 'qtitle', 'created_at', now());
    if q.data ? 'kw' then newo := newo || jsonb_build_object('kw', q.data -> 'kw'); end if;
    if o ? 'lines' then
      calc := public.crm__opt_guard(s, o -> 'lines', public.crm_num(o -> 'discount'));
      newo := newo || jsonb_build_object('lines', o -> 'lines', 'discount', calc -> 'discount', 'subtotal', calc -> 'subtotal', 'gst_total', calc -> 'gst_total', 'grand', calc -> 'grand', 'qtitle', coalesce(nullif(left(trim(o ->> 'qtitle'), 120), ''), q.data ->> 'qtitle'));
      if nullif(trim(coalesce(o ->> 'kw', '')), '') is not null then newo := newo || jsonb_build_object('kw', trim(o ->> 'kw')); end if;
    end if;
    update public.crm_records set data = data || jsonb_build_object('alt', alt || jsonb_build_array(newo)), updated_at = now() where id = q.id;
  else
    select x into e from jsonb_array_elements(alt) t(x) where x ->> 'id' = oid and coalesce(x ->> 'dropped', '') <> 'true';
    if e is null then raise exception 'Option nahi mila'; end if;
    if lbl = '' then lbl := e ->> 'label'; end if;
    if o ? 'lines' then
      calc := public.crm__opt_guard(s, o -> 'lines', public.crm_num(o -> 'discount'));
      newo := (e - 'pdf_url') || jsonb_build_object('label', lbl, 'lines', o -> 'lines', 'discount', calc -> 'discount', 'subtotal', calc -> 'subtotal', 'gst_total', calc -> 'gst_total', 'grand', calc -> 'grand', 'qtitle', coalesce(nullif(left(trim(o ->> 'qtitle'), 120), ''), e ->> 'qtitle', q.data ->> 'qtitle'));
      if nullif(trim(coalesce(o ->> 'kw', '')), '') is not null then newo := newo || jsonb_build_object('kw', trim(o ->> 'kw')); end if;
    else newo := e || jsonb_build_object('label', lbl); end if;
    update public.crm_records set data = data || jsonb_build_object('alt', (select coalesce(jsonb_agg(case when x ->> 'id' = oid then newo else x end), '[]'::jsonb) from jsonb_array_elements(alt) x)), updated_at = now() where id = q.id;
  end if;
  perform public.crm_log(s, 'option', 'quote', q.id, coalesce(q.ref, '') || ' option: ' || coalesce(lbl, ''));
  select * into q from public.crm_records where id = q.id; return public.crm_row(s, q);
end $f$;

create or replace function public.crm_quote_option_delete(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records;
begin
  perform public.crm_need(s, 'quotes.edit');
  select * into q from public.crm_records where id = (p ->> 'id')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if q.data -> 'locked' is not null then raise exception 'Customer ne final kar diya — option nahi hat sakta'; end if;
  update public.crm_records set data = data || jsonb_build_object('alt', (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(coalesce(data -> 'alt', '[]'::jsonb)) x where x ->> 'id' <> (p ->> 'opt'))), updated_at = now() where id = q.id;
  perform public.crm_log(s, 'option', 'quote', q.id, coalesce(q.ref, '') || ' option hataya: ' || coalesce(p ->> 'opt', ''));
  select * into q from public.crm_records where id = q.id; return public.crm_row(s, q);
end $f$;

-- option ki PDF ka link (staff ne PDF banakar upload ki)
create or replace function public.crm_quote_option_pdfs(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; pd jsonb := coalesce(p -> 'pdfs', '{}'::jsonb); prim text; k text; u text;
begin
  perform public.crm_need(s, 'quotes.edit');
  select * into q from public.crm_records where id = (p ->> 'id')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  prim := coalesce(q.data ->> 'opt_id', 'A');
  for k, u in select * from jsonb_each_text(pd) loop
    if u !~ '^https://[A-Za-z0-9.-]+/storage/v1/object/public/sp-images/u/[A-Za-z0-9_./%~+-]{1,250}$' then raise exception 'PDF ka link sahi nahi'; end if;
    if k = prim then update public.crm_records set data = data || jsonb_build_object('pdf_url', u) where id = q.id;
    else update public.crm_records set data = data || jsonb_build_object('alt', (select coalesce(jsonb_agg(case when x ->> 'id' = k then x || jsonb_build_object('pdf_url', u) else x end), '[]'::jsonb) from jsonb_array_elements(coalesce(data -> 'alt', '[]'::jsonb)) x)) where id = q.id; end if;
  end loop;
  select * into q from public.crm_records where id = q.id; return public.crm_row(s, q);
end $f$;

-- ---------- LOCK (staff ya customer): chuna hua option hi quotation ban jata hai ----------
create or replace function public.crm__quote_lock(qid bigint, optid text, via text, who text) returns void language plpgsql security definer set search_path = public as $f$
declare q public.crm_records; d jsonb; prim text; o jsonb; e jsonb; na jsonb := '[]'::jsonb; xe jsonb;
begin
  select * into q from public.crm_records where id = qid and kind = 'quote' and deleted_at is null for update;
  if q.id is null then raise exception 'Quotation nahi mili'; end if;
  d := q.data; prim := coalesce(d ->> 'opt_id', 'A'); optid := coalesce(nullif(optid, ''), prim);
  if optid <> prim then
    select x into o from jsonb_array_elements(coalesce(d -> 'alt', '[]'::jsonb)) t(x) where x ->> 'id' = optid and coalesce(x ->> 'dropped', '') <> 'true';
    if o is null then raise exception 'Ye option nahi mila'; end if;
    e := jsonb_build_object('id', prim, 'label', coalesce(d ->> 'opt_label', 'Option ' || prim), 'lines', d -> 'lines', 'discount', coalesce(d -> 'discount', '0'::jsonb), 'subtotal', d -> 'subtotal', 'gst_total', d -> 'gst_total', 'grand', d -> 'grand', 'qtitle', d -> 'qtitle', 'dropped', true);
    if d ? 'kw' then e := e || jsonb_build_object('kw', d -> 'kw'); end if;
    if d ? 'pdf_url' then e := e || jsonb_build_object('pdf_url', d -> 'pdf_url'); end if;
    na := jsonb_build_array(e);
    for xe in select * from jsonb_array_elements(coalesce(d -> 'alt', '[]'::jsonb)) loop if xe ->> 'id' <> optid then na := na || jsonb_build_array(xe || '{"dropped":true}'::jsonb); end if; end loop;
    d := (d - 'kw' - 'pdf_url') || jsonb_build_object('lines', o -> 'lines', 'discount', coalesce(o -> 'discount', '0'::jsonb), 'subtotal', o -> 'subtotal', 'gst_total', o -> 'gst_total', 'grand', o -> 'grand',
          'qtitle', coalesce(o ->> 'qtitle', d ->> 'qtitle'), 'opt_id', optid, 'opt_label', o ->> 'label', 'alt', na);
    if o ? 'kw' then d := d || jsonb_build_object('kw', o -> 'kw'); end if;
    if o ? 'pdf_url' then d := d || jsonb_build_object('pdf_url', o -> 'pdf_url'); end if;
  else
    for xe in select * from jsonb_array_elements(coalesce(d -> 'alt', '[]'::jsonb)) loop na := na || jsonb_build_array(xe || '{"dropped":true}'::jsonb); end loop;
    d := d || jsonb_build_object('alt', na);
  end if;
  d := (d - 'reaccept') || jsonb_build_object('locked', jsonb_build_object('opt_id', coalesce(d ->> 'opt_id', prim), 'label', coalesce(d ->> 'opt_label', 'Option ' || coalesce(d ->> 'opt_id', prim)), 'at', now(), 'by', left(who, 80), 'via', via));
  update public.crm_records set data = d, status = 'accepted', amount = public.crm_num(d -> 'grand'), updated_at = now() where id = q.id;
end $f$;
revoke all on function public.crm__quote_lock(bigint, text, text, text) from public, anon, authenticated;

create or replace function public.crm_quote_lock(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; msg text;
begin
  perform public.crm_need(s, 'quotes.edit');
  select * into q from public.crm_records where id = (p ->> 'id')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if q.status in ('expired', 'converted', 'rejected') then raise exception 'Is quotation ko final nahi kar sakte (status: %)', q.status; end if;
  if q.data -> 'locked' is not null and coalesce(q.data ->> 'reaccept', '') <> 'true' then raise exception 'Ye pehle hi final hai'; end if;
  msg := public.crm_quote_shortage(coalesce((select x -> 'lines' from jsonb_array_elements(coalesce(q.data -> 'alt', '[]'::jsonb)) t(x) where x ->> 'id' = p ->> 'opt'), q.data -> 'lines'), q.id);
  if msg is not null and not public.crm_can(s, 'stock.override') then raise exception 'Stock kam hai: %', msg; end if;
  perform public.crm__quote_lock(q.id, p ->> 'opt', 'staff', (s).name);
  perform public.crm_log(s, 'lock', 'quote', q.id, coalesce(q.ref, '') || ' final: ' || coalesce(q.data ->> 'opt_label', 'option') || ' (staff)');
  select * into q from public.crm_records where id = q.id; return public.crm_row(s, q);
end $f$;

create or replace function public.crm_quote_unlock(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; why text := left(trim(coalesce(p ->> 'reason', '')), 300);
begin
  if not (public.crm_is_admin(s) or (s).role = 'manager') then raise exception 'Sirf Manager ya Admin'; end if;
  if length(why) < 3 then raise exception 'Wajah likhein'; end if;
  select * into q from public.crm_records where id = (p ->> 'id')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if q.data -> 'locked' is null then raise exception 'Ye final nahi hai'; end if;
  if q.status = 'converted' then raise exception 'Bill ban chuka hai'; end if;
  update public.crm_records set status = 'sent', data = (data - 'locked' - 'reaccept') || jsonb_build_object('alt', (select coalesce(jsonb_agg(x - 'dropped'), '[]'::jsonb) from jsonb_array_elements(coalesce(data -> 'alt', '[]'::jsonb)) x), 'unlocks', coalesce(data -> 'unlocks', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('at', now(), 'by', (s).name, 'reason', why))), updated_at = now() where id = q.id;
  perform public.crm_log(s, 'unlock', 'quote', q.id, coalesce(q.ref, '') || ' final wapas liya — ' || why);
  select * into q from public.crm_records where id = q.id; return public.crm_row(s, q);
end $f$;

-- ---------- customer ko dikhne wala (surakshit) roop: koi mobile / pata / kharid rate nahi ----------
create or replace function public.crm__opt_pub(o jsonb, d jsonb, is_prim boolean, chosen boolean) returns jsonb language plpgsql stable security definer set search_path = public as $f$
declare items jsonb := '[]'::jsonb; l jsonb; n int := 0; showp boolean := coalesce(d ->> 'show_item_prices', '') = 'true'; pi jsonb;
begin
  for l in select * from jsonb_array_elements(case when jsonb_typeof(o -> 'lines') = 'array' then o -> 'lines' else '[]'::jsonb end) loop
    n := n + 1; exit when n > 14;
    items := items || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('n', left(coalesce(l ->> 'name', ''), 120), 'q', l -> 'qty', 'u', nullif(l ->> 'unit', ''), 'kw', nullif(l ->> 'kw', ''),
      'p', case when showp then l -> 'price' end,
      'sub', case when (l ->> 'kind') = 'project' then (select jsonb_agg(left(coalesce(x ->> 'name', ''), 80) || ' × ' || coalesce(x ->> 'qty', '')) from (select * from jsonb_array_elements(coalesce(l -> 'proj_items', '[]'::jsonb)) limit 10) t(x)) end)));
  end loop;
  return jsonb_strip_nulls(jsonb_build_object('id', o ->> 'id', 'label', coalesce(nullif(o ->> 'label', ''), 'Option'), 'total', o -> 'grand', 'kw', nullif(o ->> 'kw', ''), 'items', items,
    'n_items', jsonb_array_length(case when jsonb_typeof(o -> 'lines') = 'array' then o -> 'lines' else '[]'::jsonb end), 'pdf_url', nullif(o ->> 'pdf_url', ''), 'chosen', chosen));
end $f$;
revoke all on function public.crm__opt_pub(jsonb, jsonb, boolean, boolean) from public, anon, authenticated;

create or replace function public.crm__quote_pub(q public.crm_records) returns jsonb language plpgsql stable security definer set search_path = public as $f$
declare d jsonb := q.data; prim text := coalesce(q.data ->> 'opt_id', 'A'); opts jsonb := '[]'::jsonb; x jsonb; lk jsonb := q.data -> 'locked'; po jsonb;
begin
  po := jsonb_build_object('id', prim, 'label', coalesce(d ->> 'opt_label', case when jsonb_array_length(coalesce(d -> 'alt', '[]'::jsonb)) > 0 then 'Option 1' else 'Quotation' end), 'lines', d -> 'lines', 'grand', d -> 'grand', 'kw', d -> 'kw', 'pdf_url', d -> 'pdf_url');
  opts := jsonb_build_array(public.crm__opt_pub(po, d, true, lk is not null));
  if lk is null then
    for x in select * from jsonb_array_elements(coalesce(d -> 'alt', '[]'::jsonb)) loop
      if coalesce(x ->> 'dropped', '') <> 'true' then opts := opts || jsonb_build_array(public.crm__opt_pub(x, d, false, false)); end if;
    end loop;
  end if;
  return jsonb_strip_nulls(jsonb_build_object('ref', q.ref, 'title', d ->> 'qtitle', 'status', q.status, 'valid_till', d ->> 'valid_till', 'opts', opts,
    'locked', case when lk is not null then jsonb_build_object('label', lk ->> 'label', 'at', lk ->> 'at', 'via', lk ->> 'via') end,
    'reaccept', case when coalesce(d ->> 'reaccept', '') = 'true' then true end,
    'resp', case when d -> 'resp' is not null then jsonb_build_object('change', d #> '{resp,change,at}', 'callback', d #> '{resp,callback,at}') end));
end $f$;
revoke all on function public.crm__quote_pub(public.crm_records) from public, anon, authenticated;

-- ---------- link kholna: ab expired / paused ho to bhi saaf jawab (error nahi) ----------
create or replace function public.sp_share_open(p_token text, p_count boolean default false) returns jsonb language plpgsql security definer set search_path = public as $f$
declare r public.sp_shares; q public.crm_records; pub jsonb; amt numeric;
begin
  select * into r from public.sp_shares where token = btrim(coalesce(p_token, ''));
  if r.id is null then return null; end if;
  if r.revoked or r.expires_at <= now() then
    return jsonb_build_object('state', case when r.revoked then 'paused' else 'expired' end, 'kind', r.kind, 'brand', r.brand, 'phone', r.phone);
  end if;
  if r.live and r.quote_id is not null then
    select * into q from public.crm_records where id = r.quote_id and kind = 'quote' and deleted_at is null;
    if q.id is null then return jsonb_build_object('state', 'expired', 'kind', r.kind, 'brand', r.brand, 'phone', r.phone); end if;
    pub := public.crm__quote_pub(q);
  end if;
  if p_count then update public.sp_shares set views = views + 1, first_view = coalesce(first_view, now()), last_view = now() where id = r.id; end if;
  if pub is not null then
    amt := case when q.data -> 'locked' is not null or jsonb_array_length(pub -> 'opts') = 1 then public.crm_num(q.data -> 'grand') end;
    return jsonb_build_object('kind', r.kind, 'title', coalesce(nullif(pub ->> 'title', ''), r.title), 'subtitle', r.subtitle, 'amount', amt, 'valid_till', q.data ->> 'valid_till', 'details', '[]'::jsonb,
      'pdf_url', null, 'view_url', null, 'file_name', r.file_name, 'brand', r.brand, 'phone', r.phone, 'created_at', r.created_at, 'live', true, 'quote', pub);
  end if;
  return jsonb_build_object('kind', r.kind, 'title', r.title, 'subtitle', r.subtitle, 'amount', r.amount, 'valid_till', r.valid_till, 'details', r.details,
    'pdf_url', r.pdf_url, 'view_url', r.view_url, 'file_name', r.file_name, 'brand', r.brand, 'phone', r.phone, 'created_at', r.created_at);
end $f$;
grant execute on function public.sp_share_open(text, boolean) to anon, authenticated;

-- ---------- ek quotation = ek hi link: dobara bhejne par wahi link taaza hota hai ----------
create or replace function public.crm_share_create(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); t text; rf text := btrim(coalesce(p ->> 'ref', '')); qid bigint; q public.crm_records; r public.sp_shares; pu text; dt jsonb; am numeric; vt date;
begin
  if coalesce(lower(p ->> 'kind'), '') = 'quote' and rf ~ '^rec:[0-9]+$' then
    qid := substr(rf, 5)::bigint;
    select * into q from public.crm_records where id = qid and kind = 'quote' and deleted_at is null;
    if q.id is not null and public.crm_vis(s, q) then
      select * into r from public.sp_shares where quote_id = qid and live order by id desc limit 1;
      if r.id is not null then
        pu := nullif(btrim(coalesce(p ->> 'pdf_url', '')), '');
        if pu is not null and pu !~ '^https://[A-Za-z0-9.-]+/storage/v1/object/public/sp-images/u/[A-Za-z0-9_./%~+-]{1,250}$' then raise exception 'PDF ka link sahi nahi'; end if;
        begin am := nullif(p ->> 'amount', '')::numeric; exception when others then am := null; end;
        begin vt := nullif(p ->> 'valid_till', '')::date; exception when others then vt := null; end;
        update public.sp_shares set revoked = false, title = left(coalesce(nullif(btrim(p ->> 'title'), ''), title), 200), subtitle = left(coalesce(nullif(btrim(p ->> 'subtitle'), ''), subtitle), 240), amount = am, valid_till = vt,
          pdf_url = coalesce(pu, pdf_url), file_name = coalesce(left(nullif(regexp_replace(coalesce(p ->> 'file_name', ''), '[^A-Za-z0-9_.() -]+', '-', 'g'), ''), 120), file_name),
          brand = coalesce(left(nullif(btrim(coalesce(p ->> 'brand', '')), ''), 80), brand), phone = coalesce(nullif(left(regexp_replace(coalesce(p ->> 'phone', ''), '\D', '', 'g'), 15), ''), phone),
          expires_at = case when expiry_manual then expires_at else public.crm__quote_link_expiry(q) end where id = r.id;
        if pu is not null then update public.crm_records set data = data || jsonb_build_object('pdf_url', pu) where id = qid; end if;
        return jsonb_build_object('token', r.token);
      end if;
      t := public.sp_share_insert(p, (s).uid, (s).name, 'crm');
      update public.sp_shares set quote_id = qid, live = true, expires_at = public.crm__quote_link_expiry(q) where token = t;
      select pdf_url into pu from public.sp_shares where token = t;
      if pu is not null then update public.crm_records set data = data || jsonb_build_object('pdf_url', pu) where id = qid; end if;
      return jsonb_build_object('token', t);
    end if;
  end if;
  t := public.sp_share_insert(p, (s).uid, (s).name, 'crm');
  return jsonb_build_object('token', t);
end $f$;
grant execute on function public.crm_share_create(jsonb) to anon, authenticated;

create or replace function public.crm_share_list(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token');
begin
  return coalesce((select jsonb_agg(jsonb_build_object('token', x.token, 'kind', x.kind, 'title', x.title, 'at', x.created_at, 'by', x.by_name, 'views', x.views,
            'last_view', x.last_view, 'revoked', x.revoked, 'expired', x.expires_at < now(), 'expires_at', x.expires_at, 'live', x.live, 'manual', x.expiry_manual) order by x.id desc)
     from (select * from public.sp_shares where ref = btrim(coalesce(p ->> 'ref', '')) and btrim(coalesce(p ->> 'ref', '')) <> '' order by id desc limit 20) x), '[]'::jsonb);
end $f$;
grant execute on function public.crm_share_list(jsonb) to anon, authenticated;

-- ---------- link ki expiry: badhana / ghatana / pause / auto ----------
create or replace function public.crm_share_expiry(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.sp_shares; q public.crm_records; m text := p ->> 'mode'; dd int := least(greatest(coalesce(nullif(p ->> 'days', '')::int, 7), 1), 365); nd timestamptz;
begin
  select * into r from public.sp_shares where token = btrim(coalesce(p ->> 'code', ''));
  if r.id is null then raise exception 'Link nahi mila'; end if;
  if not (public.crm_is_admin(s) or r.by_uid = (s).uid or public.crm_can(s, 'quotes.edit')) then raise exception 'Aapko is link par kaam ki permission nahi hai'; end if;
  if m = 'add' then update public.sp_shares set expires_at = greatest(expires_at, now()) + make_interval(days => dd), expiry_manual = true where id = r.id;
  elsif m = 'sub' then nd := expires_at - make_interval(days => dd); update public.sp_shares set expires_at = case when nd < now() + interval '1 hour' then now() + interval '1 hour' else nd end, expiry_manual = true where id = r.id;
  elsif m = 'set' then
    if coalesce(p ->> 'date', '') !~ '^\d{4}-\d{2}-\d{2}$' or (p ->> 'date')::date < public.crm_today() or (p ->> 'date')::date > public.crm_today() + 400 then raise exception 'Tareekh aaj se 400 din ke andar chunein'; end if;
    update public.sp_shares set expires_at = (((p ->> 'date')::date + 1)::timestamp) at time zone 'Asia/Kolkata', expiry_manual = true where id = r.id;
  elsif m = 'now' then update public.sp_shares set expires_at = now(), expiry_manual = true where id = r.id;
  elsif m = 'pause' then update public.sp_shares set revoked = true where id = r.id;
  elsif m = 'resume' then update public.sp_shares set revoked = false where id = r.id;
  elsif m = 'auto' then
    select * into q from public.crm_records where id = r.quote_id and kind = 'quote';
    if q.id is null then raise exception 'Ye link auto expiry wala nahi hai'; end if;
    update public.sp_shares set expiry_manual = false, expires_at = public.crm__quote_link_expiry(q) where id = r.id;
  else raise exception 'Galat kaam'; end if;
  perform public.crm_log(s, 'link', coalesce(r.kind, 'doc'), null, 'Link ' || coalesce(r.ref, '') || ': ' || m);
  select * into r from public.sp_shares where id = r.id;
  return jsonb_build_object('ok', true, 'expires_at', r.expires_at, 'revoked', r.revoked, 'manual', r.expiry_manual);
end $f$;
grant execute on function public.crm_share_expiry(jsonb) to anon, authenticated;

-- ---------- staff ko kaam: customer ke jawab par CRM me reminder (Today's tasks + bell) ----------
create or replace function public.crm__quote_remind(q public.crm_records, ttl text, note text) returns void language plpgsql security definer set search_path = public as $f$
declare pa public.crm_records; asg bigint;
begin
  select * into pa from public.crm_records where id = q.party_id;
  asg := coalesce(nullif(q.assigned_to, 0), nullif(pa.assigned_to, 0), nullif(pa.owner_id, 0), nullif(q.owner_id, 0));
  insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, party_id, due_at, data, search)
  values ('reminder', left(ttl || ' — ' || coalesce(pa.title, '') || ' (' || coalesce(q.ref, '') || ')', 200), pa.mobile, 'open', 0, asg, q.party_id, public.crm_today(),
    jsonb_build_object('type', 'call', 'note', left(coalesce(note, ''), 300), 'party_name', pa.title, 'mobile', pa.mobile, 'quote_id', q.id, 'quote_ref', q.ref, 'from_link', true),
    lower(ttl || ' ' || coalesce(pa.title, '') || ' ' || coalesce(q.ref, '')));
end $f$;
revoke all on function public.crm__quote_remind(public.crm_records, text, text) from public, anon, authenticated;

-- ---------- customer ka jawab (link se): Accept / Badlav chahiye / Call back  — koi payment nahi ----------
create or replace function public.sp_quote_respond(p_token text, p_action text, p_opt text default null, p_last4 text default null, p_note text default null) returns jsonb language plpgsql security definer set search_path = public as $f$
declare r public.sp_shares; q public.crm_records; pa public.crm_records; act text := lower(coalesce(p_action, '')); note text := left(btrim(coalesce(p_note, '')), 300); l4 text := regexp_replace(coalesce(p_last4, ''), '\D', '', 'g');
        prim text; oid text; lbl text; nopt int; last_at timestamptz;
begin
  perform public.sp_share_rate(30);
  select * into r from public.sp_shares where token = btrim(coalesce(p_token, '')) and live and not revoked and expires_at > now();
  if r.id is null then raise exception 'Ye link ab chalu nahi hai'; end if;
  select * into q from public.crm_records where id = r.quote_id and kind = 'quote' and deleted_at is null;
  if q.id is null then raise exception 'Quotation nahi mili'; end if;
  if q.status in ('expired', 'converted', 'rejected') then return jsonb_build_object('error', 'Is quotation par ab jawab nahi ho sakta — kripya humse sampark karein'); end if;
  prim := coalesce(q.data ->> 'opt_id', 'A');
  if act = 'accept' then
    if q.data -> 'locked' is not null and coalesce(q.data ->> 'reaccept', '') <> 'true' then return jsonb_build_object('ok', true, 'already', true, 'quote', public.crm__quote_pub(q)); end if;
    if r.bad_tries >= 5 and r.bad_at > now() - interval '1 day' then return jsonb_build_object('error', 'Kai galat koshish ho chuki — kripya humse sampark karein'); end if;
    select * into pa from public.crm_records where id = q.party_id;
    if length(l4) <> 4 or right(coalesce(pa.mobile, ''), 4) is distinct from l4 then
      update public.sp_shares set bad_tries = case when bad_at > now() - interval '1 day' then bad_tries + 1 else 1 end, bad_at = now() where id = r.id;
      return jsonb_build_object('error', 'Mobile ke aakhri 4 ank match nahi hue');
    end if;
    nopt := 1 + (select count(*) from jsonb_array_elements(coalesce(q.data -> 'alt', '[]'::jsonb)) x where coalesce(x ->> 'dropped', '') <> 'true');
    oid := nullif(btrim(coalesce(p_opt, '')), '');
    if q.data -> 'locked' is not null then oid := prim; end if;
    if oid is null and nopt > 1 then return jsonb_build_object('error', 'Pehle ek option chunein'); end if;
    if oid is not null and oid <> prim and not exists (select 1 from jsonb_array_elements(coalesce(q.data -> 'alt', '[]'::jsonb)) x where x ->> 'id' = oid and coalesce(x ->> 'dropped', '') <> 'true') then return jsonb_build_object('error', 'Ye option nahi mila'); end if;
    perform public.crm__quote_lock(q.id, oid, 'customer', 'Customer (link)');
    update public.sp_shares set bad_tries = 0 where id = r.id;
    select * into q from public.crm_records where id = q.id;
    update public.crm_records set data = data || jsonb_build_object('resp', coalesce(data -> 'resp', '{}'::jsonb) || jsonb_build_object('accept', jsonb_build_object('at', now(), 'opt', q.data #>> '{locked,opt_id}', 'amount', q.data -> 'grand'))) where id = q.id;
    insert into public.crm_activity(user_id, user_name, role, action, kind, rec_id, summary) values (0, 'Customer (link)', 'customer', 'accept', 'quote', q.id, left(coalesce(q.ref, '') || ' Accept: ' || coalesce(q.data #>> '{locked,label}', ''), 300));
    perform public.crm__quote_remind(q, 'Customer ne Accept kiya — advance ke liye call karein', 'Option: ' || coalesce(q.data #>> '{locked,label}', '') || ' · ' || coalesce(q.data ->> 'grand', ''));
  elsif act = 'change' then
    if length(note) < 3 then return jsonb_build_object('error', 'Kya badlav chahiye, thoda likhein'); end if;
    last_at := nullif(q.data #>> '{resp,change,at}', '')::timestamptz;
    if last_at is null or last_at < now() - interval '5 minutes' then
      update public.crm_records set data = data || jsonb_build_object('resp', coalesce(data -> 'resp', '{}'::jsonb) || jsonb_build_object('change', jsonb_build_object('at', now(), 'note', note))) where id = q.id;
      select * into q from public.crm_records where id = q.id;
      insert into public.crm_activity(user_id, user_name, role, action, kind, rec_id, summary) values (0, 'Customer (link)', 'customer', 'change', 'quote', q.id, left(coalesce(q.ref, '') || ' badlav: ' || note, 300));
      perform public.crm__quote_remind(q, 'Customer ko badlav chahiye', note);
    end if;
  elsif act = 'callback' then
    last_at := nullif(q.data #>> '{resp,callback,at}', '')::timestamptz;
    if last_at is null or last_at < now() - interval '30 minutes' then
      update public.crm_records set data = data || jsonb_build_object('resp', coalesce(data -> 'resp', '{}'::jsonb) || jsonb_build_object('callback', jsonb_build_object('at', now()))) where id = q.id;
      select * into q from public.crm_records where id = q.id;
      perform public.crm__quote_remind(q, 'Customer ne call back maanga', note);
    end if;
  else raise exception 'Galat kaam'; end if;
  select * into q from public.crm_records where id = q.id;
  return jsonb_build_object('ok', true, 'quote', public.crm__quote_pub(q));
end $f$;
grant execute on function public.sp_quote_respond(text, text, text, text, text) to anon, authenticated;

grant execute on function public.crm_quote_option_save(jsonb), public.crm_quote_option_delete(jsonb), public.crm_quote_option_pdfs(jsonb), public.crm_quote_lock(jsonb), public.crm_quote_unlock(jsonb) to anon, authenticated;

-- ---------- crm_status: final ho chuki quotation ko galti se draft / sent nahi kar sakte; staff 'accepted' dabaye = final ----------
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
    if r.kind = 'quote' and st in ('draft', 'sent') and r.data -> 'locked' is not null then raise exception 'Customer ne final kar diya — pehle "Final wapas lein" (Manager / Admin)'; end if;
    if r.kind = 'quote' and st in ('draft', 'sent', 'accepted') and r.status = 'rejected' and not public.crm_can(s, 'stock.override') then
      perform public.crm_need(s, 'quotes.edit');
      if public.crm_quote_shortage(r.data -> 'lines', r.id) is not null then raise exception 'Stock kam hai — is quotation ko dobara active nahi kar sakte'; end if;
    end if;
    if r.kind = 'purchase' and st not in ('open', 'received', 'cancelled') then raise exception 'Galat status'; end if;
    if r.kind = 'invoice' then raise exception 'Bill ka status payment se apne aap badalta hai'; end if;
    perform public.crm_need(s, case r.kind when 'purchase' then 'purchase.manage' else 'quotes.edit' end);
    update public.crm_records set status = st, data = d -> 'data', updated_at = now() where id = r.id;
    if r.kind = 'quote' and st = 'accepted' and r.data -> 'locked' is null then perform public.crm__quote_lock(r.id, null, 'staff', (s).name); end if;
    if r.kind = 'purchase' and st = 'received' and r.status <> 'received' then perform public.crm_stock(r.data, 1); end if;
    perform public.crm_log(s, 'status', r.kind, r.id, coalesce(r.ref, '') || ' → ' || st);
    select * into r from public.crm_records where id = r.id; return public.crm_row(s, r);
  end if;
  if r.kind = 'plant' and st in ('verified', 'rejected') then perform public.crm_need(s, 'plants.verify'); end if;
  return public.crm_save(d || jsonb_build_object('party_id', r.party_id, 'assigned_to', r.assigned_to, 'due_at', r.due_at));
end $function$;

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

do $seed$
declare root bigint; fid bigint; did bigint;
begin
  if exists (select 1 from public.crm_records where kind = 'folder' and coalesce(data ->> 'sample_root', '') = 'true') then return; end if;
  insert into public.crm_records(kind, title, status, owner_id, data, search)
  values ('folder', 'Customer Samples (namune)', 'ok', 0, jsonb_build_object('name', 'Customer Samples (namune)', 'parent_id', '', 'locked', false, 'sample_root', true, 'note', 'Is folder ki files customer ke quotation link ke "Hum kaise kaam karte hain" page par dikhti hain. Yahan file badlein / jodein — customer ko wahi dikhegi.'), 'customer samples namune') returning id into root;
  insert into public.crm_records(kind, title, status, owner_id, data, search)
  values ('folder', 'Blueprint / Design', 'ok', 0, jsonb_build_object('name', 'Blueprint / Design', 'parent_id', root::text, 'locked', false, 'note', 'Aapki chhat ke hisaab se solar design kaise banta hai.', 'types', '["project"]'::jsonb, 'sort', 1), 'blueprint / design') returning id into fid;
  insert into public.crm_records(kind, title, status, owner_id, data, search)
  values ('doc', 'Blueprint kaise banta hai (namuna)', 'ok', 0, jsonb_build_object('folder_id', fid, 'mime', 'image/svg+xml', 'size', 6651, 'note', '3 kadam: chhat ki jaankari → hamara design → aapka approve.'), 'blueprint kaise banta hai (namuna)') returning id into did;
  insert into public.crm_files(rec_id, mime, size, data) values (did, 'image/svg+xml', 6651, convert_to($svg$<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 520" width="800" height="520" font-family="system-ui,-apple-system,'Segoe UI',Roboto,'Noto Sans Devanagari','Noto Sans',sans-serif" role="img" aria-label="Blueprint / Design kaise banta hai (namuna)"><rect width="800" height="520" fill="#f4f8f4"/><rect width="800" height="76" fill="#0f4d2b"/><text x="28" y="36" font-size="25" font-weight="800" fill="#fff" text-anchor="start" >Blueprint / Design kaise banta hai</text><text x="28" y="60" font-size="14" font-weight="500" fill="#bfe3c8" text-anchor="start" >Aapki chhat ka solar design — 3 aasaan kadam</text><rect x="678" y="20" width="94" height="30" rx="15" fill="#e8870c"/><text x="725" y="41" font-size="14" font-weight="800" fill="#fff" text-anchor="middle" letter-spacing="1.5">NAMUNA</text><rect x="30" y="100" width="220" height="300" rx="14" fill="#fff" stroke="#cfe0d2" stroke-width="1.5" /><circle cx="60" cy="128" r="16" fill="#1e8e3e" stroke="none" stroke-width="0"/><text x="60" y="134" font-size="17" font-weight="800" fill="#fff" text-anchor="middle" >1</text><text x="84" y="134" font-size="16.5" font-weight="800" fill="#0f4d2b" text-anchor="start" >Chhat ki jaankari</text><rect x="290" y="100" width="220" height="300" rx="14" fill="#fff" stroke="#cfe0d2" stroke-width="1.5" /><circle cx="320" cy="128" r="16" fill="#1e8e3e" stroke="none" stroke-width="0"/><text x="320" y="134" font-size="17" font-weight="800" fill="#fff" text-anchor="middle" >2</text><text x="344" y="134" font-size="16.5" font-weight="800" fill="#0f4d2b" text-anchor="start" >Hamara design</text><rect x="550" y="100" width="220" height="300" rx="14" fill="#fff" stroke="#cfe0d2" stroke-width="1.5" /><circle cx="580" cy="128" r="16" fill="#1e8e3e" stroke="none" stroke-width="0"/><text x="580" y="134" font-size="17" font-weight="800" fill="#fff" text-anchor="middle" >3</text><text x="604" y="134" font-size="16.5" font-weight="800" fill="#0f4d2b" text-anchor="start" >Aap approve karein</text><path d="M70 250 L140 195 L210 250 Z" fill="#e3f3e7" stroke="#1e8e3e" stroke-width="3" stroke-linejoin="round"/><rect x="88" y="250" width="104" height="62" fill="#fff" stroke="#1e8e3e" stroke-width="3"/><rect x="128" y="276" width="24" height="36" fill="#cfe9d4" stroke="#1e8e3e" stroke-width="2"/><path d="M52 330 H228" stroke="#e8870c" stroke-width="2" stroke-dasharray="6 5"/><text x="140" y="350" font-size="13" font-weight="700" fill="#e8870c" text-anchor="middle" >naap · photo · disha</text><text x="140" y="376" font-size="13" font-weight="500" fill="#5d6f62" text-anchor="middle" >Aap photo bhejte hain ya</text><text x="140" y="394" font-size="13" font-weight="500" fill="#5d6f62" text-anchor="middle" >hamara engineer aata hai</text><path d="M318 250 L400 168 L482 250 Z" fill="#e3f3e7" stroke="#1e8e3e" stroke-width="3" stroke-linejoin="round"/><rect x="340" y="222" width="24" height="19" rx="2" fill="#1d4e89" stroke="#fff" stroke-width="1.5"/><rect x="368" y="222" width="24" height="19" rx="2" fill="#1d4e89" stroke="#fff" stroke-width="1.5"/><rect x="396" y="222" width="24" height="19" rx="2" fill="#1d4e89" stroke="#fff" stroke-width="1.5"/><rect x="424" y="222" width="24" height="19" rx="2" fill="#1d4e89" stroke="#fff" stroke-width="1.5"/><rect x="452" y="222" width="24" height="19" rx="2" fill="#1d4e89" stroke="#fff" stroke-width="1.5"/><rect x="340" y="246" width="24" height="19" rx="2" fill="#1d4e89" stroke="#fff" stroke-width="1.5"/><rect x="368" y="246" width="24" height="19" rx="2" fill="#1d4e89" stroke="#fff" stroke-width="1.5"/><rect x="396" y="246" width="24" height="19" rx="2" fill="#1d4e89" stroke="#fff" stroke-width="1.5"/><rect x="424" y="246" width="24" height="19" rx="2" fill="#1d4e89" stroke="#fff" stroke-width="1.5"/><rect x="452" y="246" width="24" height="19" rx="2" fill="#1d4e89" stroke="#fff" stroke-width="1.5"/><rect x="318" y="262" width="164" height="50" fill="#fff" stroke="#1e8e3e" stroke-width="3"/><text x="400" y="296" font-size="13" font-weight="700" fill="#1c2b20" text-anchor="middle" >5 kW · 10 panel (namuna)</text><text x="400" y="336" font-size="13" font-weight="700" fill="#e8870c" text-anchor="middle" >panel layout · kW · chhaya</text><text x="400" y="376" font-size="13" font-weight="500" fill="#5d6f62" text-anchor="middle" >Aapki chhat ke hisaab se</text><text x="400" y="394" font-size="13" font-weight="500" fill="#5d6f62" text-anchor="middle" >poora design banta hai</text><rect x="618" y="160" width="84" height="150" rx="14" fill="#fff" stroke="#0f4d2b" stroke-width="3.5"/><rect x="630" y="178" width="60" height="62" rx="6" fill="#e3f3e7"/><rect x="632" y="254" width="56" height="22" rx="11" fill="#1e8e3e"/><text x="660" y="270" font-size="11.5" font-weight="800" fill="#fff" text-anchor="middle" >Approve</text><rect x="632" y="282" width="56" height="18" rx="9" fill="#fff" stroke="#1e8e3e" stroke-width="1.5"/><text x="660" y="295" font-size="11" font-weight="700" fill="#0f4d2b" text-anchor="middle" >Badlav</text><path d="M647 214 l6 7 l12 -14" fill="none" stroke="#1e8e3e" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/><text x="660" y="336" font-size="13" font-weight="500" fill="#5d6f62" text-anchor="middle" >Link me dekhein,</text><text x="660" y="354" font-size="13" font-weight="500" fill="#5d6f62" text-anchor="middle" >Approve ya Badlav</text><text x="660" y="376" font-size="13" font-weight="500" fill="#1c2b20" text-anchor="start" ></text><path d="M252 250 H280" stroke="#1e8e3e" stroke-width="3" stroke-linecap="round"/><path d="M274 243 L284 250 L274 257" fill="none" stroke="#1e8e3e" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/><path d="M512 250 H540" stroke="#1e8e3e" stroke-width="3" stroke-linecap="round"/><path d="M534 243 L544 250 L534 257" fill="none" stroke="#1e8e3e" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/><text x="400" y="426" font-size="15" font-weight="700" fill="#0f4d2b" text-anchor="middle" >Approve karne ke baad hi agla kaam shuru hota hai.</text><g opacity="0.07" transform="rotate(-18 400 290)"><text x="400" y="300" font-size="84" font-weight="900" fill="#0f4d2b" text-anchor="middle" >SAMPLE · नमूना</text></g><rect y="468" width="800" height="52" fill="#fff4e0"/><rect y="468" width="800" height="2" fill="#f1d9a8"/><text x="400.0" y="489" font-size="14.5" font-weight="800" fill="#6b4a00" text-anchor="middle" >Ye sirf samjhane ke liye NAMUNA hai.</text><text x="400.0" y="508" font-size="13" font-weight="500" fill="#6b4a00" text-anchor="middle" >Aapki chhat aur sthiti ke anusaar asli design / report / samay alag ho sakta hai.</text></svg>$svg$, 'UTF8'));
  insert into public.crm_records(kind, title, status, owner_id, data, search)
  values ('folder', 'Site Visit', 'ok', 0, jsonb_build_object('name', 'Site Visit', 'parent_id', root::text, 'locked', false, 'note', 'Site visit kaise book hoti hai aur uski report kaisi hoti hai.', 'types', '["project", "service"]'::jsonb, 'sort', 2), 'site visit') returning id into fid;
  insert into public.crm_records(kind, title, status, owner_id, data, search)
  values ('doc', 'Site visit kaise book hoti hai (namuna)', 'ok', 0, jsonb_build_object('folder_id', fid, 'mime', 'image/svg+xml', 'size', 7346, 'note', 'Tareekh chuniye, engineer aata hai, report milti hai.'), 'site visit kaise book hoti hai (namuna)') returning id into did;
  insert into public.crm_files(rec_id, mime, size, data) values (did, 'image/svg+xml', 7346, convert_to($svg$<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 520" width="800" height="520" font-family="system-ui,-apple-system,'Segoe UI',Roboto,'Noto Sans Devanagari','Noto Sans',sans-serif" role="img" aria-label="Site Visit kaise book hoti hai (namuna)"><rect width="800" height="520" fill="#f4f8f4"/><rect width="800" height="76" fill="#0f4d2b"/><text x="28" y="36" font-size="25" font-weight="800" fill="#fff" text-anchor="start" >Site Visit kaise book hoti hai</text><text x="28" y="60" font-size="14" font-weight="500" fill="#bfe3c8" text-anchor="start" >Pehle humari team aapki chhat dekhti hai</text><rect x="678" y="20" width="94" height="30" rx="15" fill="#e8870c"/><text x="725" y="41" font-size="14" font-weight="800" fill="#fff" text-anchor="middle" letter-spacing="1.5">NAMUNA</text><rect x="30" y="100" width="220" height="200" rx="14" fill="#fff" stroke="#cfe0d2" stroke-width="1.5" /><circle cx="60" cy="128" r="16" fill="#1e8e3e" stroke="none" stroke-width="0"/><text x="60" y="134" font-size="17" font-weight="800" fill="#fff" text-anchor="middle" >1</text><text x="84" y="134" font-size="16" font-weight="800" fill="#0f4d2b" text-anchor="start" >Tareekh chunein</text><text x="140" y="262" font-size="13" font-weight="500" fill="#5d6f62" text-anchor="middle" >Aap apni suvidha ki</text><text x="140" y="280" font-size="13" font-weight="500" fill="#5d6f62" text-anchor="middle" >tareekh batate hain</text><rect x="290" y="100" width="220" height="200" rx="14" fill="#fff" stroke="#cfe0d2" stroke-width="1.5" /><circle cx="320" cy="128" r="16" fill="#1e8e3e" stroke="none" stroke-width="0"/><text x="320" y="134" font-size="17" font-weight="800" fill="#fff" text-anchor="middle" >2</text><text x="344" y="134" font-size="16" font-weight="800" fill="#0f4d2b" text-anchor="start" >Engineer aata hai</text><text x="400" y="262" font-size="13" font-weight="500" fill="#5d6f62" text-anchor="middle" >Chhat dekhta hai, naap aur</text><text x="400" y="280" font-size="13" font-weight="500" fill="#5d6f62" text-anchor="middle" >photo leta hai</text><rect x="550" y="100" width="220" height="200" rx="14" fill="#fff" stroke="#cfe0d2" stroke-width="1.5" /><circle cx="580" cy="128" r="16" fill="#1e8e3e" stroke="none" stroke-width="0"/><text x="580" y="134" font-size="17" font-weight="800" fill="#fff" text-anchor="middle" >3</text><text x="604" y="134" font-size="16" font-weight="800" fill="#0f4d2b" text-anchor="start" >Report milti hai</text><text x="660" y="262" font-size="13" font-weight="500" fill="#5d6f62" text-anchor="middle" >Visit ke baad poori report</text><text x="660" y="280" font-size="13" font-weight="500" fill="#5d6f62" text-anchor="middle" >isi link me milti hai</text><rect x="85" y="160" width="110" height="82" rx="8" fill="#fff" stroke="#1e8e3e" stroke-width="3"/><rect x="85" y="160" width="110" height="22" rx="8" fill="#1e8e3e"/><circle cx="100" cy="198" r="3.5" fill="#9bc9a6" stroke="none" stroke-width="0"/><circle cx="120" cy="198" r="3.5" fill="#9bc9a6" stroke="none" stroke-width="0"/><circle cx="140" cy="198" r="3.5" fill="#9bc9a6" stroke="none" stroke-width="0"/><circle cx="160" cy="198" r="3.5" fill="#9bc9a6" stroke="none" stroke-width="0"/><circle cx="180" cy="198" r="3.5" fill="#9bc9a6" stroke="none" stroke-width="0"/><circle cx="100" cy="215" r="3.5" fill="#9bc9a6" stroke="none" stroke-width="0"/><circle cx="120" cy="215" r="3.5" fill="#9bc9a6" stroke="none" stroke-width="0"/><circle cx="140" cy="215" r="3.5" fill="#9bc9a6" stroke="none" stroke-width="0"/><circle cx="160" cy="215" r="3.5" fill="#9bc9a6" stroke="none" stroke-width="0"/><circle cx="180" cy="215" r="3.5" fill="#9bc9a6" stroke="none" stroke-width="0"/><circle cx="100" cy="232" r="3.5" fill="#9bc9a6" stroke="none" stroke-width="0"/><circle cx="120" cy="232" r="3.5" fill="#9bc9a6" stroke="none" stroke-width="0"/><circle cx="140" cy="232" r="3.5" fill="#9bc9a6" stroke="none" stroke-width="0"/><circle cx="160" cy="232" r="3.5" fill="#9bc9a6" stroke="none" stroke-width="0"/><circle cx="180" cy="232" r="3.5" fill="#9bc9a6" stroke="none" stroke-width="0"/><circle cx="168" cy="227" r="5" fill="#e8870c" stroke="none" stroke-width="0"/><circle cx="400" cy="190" r="16" fill="#cfe9d4" stroke="#1e8e3e" stroke-width="3"/><path d="M372 244 Q372 214 400 214 Q428 214 428 244 Z" fill="#cfe9d4" stroke="#1e8e3e" stroke-width="3"/><path d="M434 244 L458 220 L482 244 Z" fill="#e3f3e7" stroke="#1e8e3e" stroke-width="3" stroke-linejoin="round"/><rect x="442" y="244" width="32" height="0" fill="none"/><rect x="618" y="156" width="84" height="94" rx="8" fill="#fff" stroke="#1e8e3e" stroke-width="3"/><path d="M632 176 H688" stroke="#9bc9a6" stroke-width="3" stroke-linecap="round"/><path d="M632 194 H688" stroke="#9bc9a6" stroke-width="3" stroke-linecap="round"/><path d="M632 212 H688" stroke="#9bc9a6" stroke-width="3" stroke-linecap="round"/><path d="M632 230 H688" stroke="#9bc9a6" stroke-width="3" stroke-linecap="round"/><path d="M630 236 l6 7 l12 -14" fill="none" stroke="#1e8e3e" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/><path d="M254 200 H280" stroke="#1e8e3e" stroke-width="3" stroke-linecap="round"/><path d="M274 193 L284 200 L274 207" fill="none" stroke="#1e8e3e" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/><path d="M514 200 H540" stroke="#1e8e3e" stroke-width="3" stroke-linecap="round"/><path d="M534 193 L544 200 L534 207" fill="none" stroke="#1e8e3e" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/><rect x="30" y="322" width="720" height="110" rx="14" fill="#fff" stroke="#cfe0d2" stroke-width="1.5" /><text x="50" y="350" font-size="15.5" font-weight="800" fill="#0f4d2b" text-anchor="start" >Visit me kya-kya dekha jata hai</text><rect x="50" y="368" width="114.60000000000001" height="34" rx="17" fill="#e3f3e7"/><text x="107.30000000000001" y="390" font-size="12.5" font-weight="700" fill="#0f4d2b" text-anchor="middle" >Chhat ki jagah</text><rect x="170.60000000000002" y="368" width="128.4" height="34" rx="17" fill="#e3f3e7"/><text x="234.8" y="390" font-size="12.5" font-weight="700" fill="#0f4d2b" text-anchor="middle" >Chhaya / shading</text><rect x="305.0" y="368" width="142.2" height="34" rx="17" fill="#e3f3e7"/><text x="376.1" y="390" font-size="12.5" font-weight="700" fill="#0f4d2b" text-anchor="middle" >Structure ki halat</text><rect x="453.2" y="368" width="128.4" height="34" rx="17" fill="#e3f3e7"/><text x="517.4" y="390" font-size="12.5" font-weight="700" fill="#0f4d2b" text-anchor="middle" >Meter aur wiring</text><rect x="587.6" y="368" width="135.3" height="34" rx="17" fill="#e3f3e7"/><text x="655.25" y="390" font-size="12.5" font-weight="700" fill="#0f4d2b" text-anchor="middle" >Bijli ki zaroorat</text><g opacity="0.07" transform="rotate(-18 400 290)"><text x="400" y="300" font-size="84" font-weight="900" fill="#0f4d2b" text-anchor="middle" >SAMPLE · नमूना</text></g><rect y="468" width="800" height="52" fill="#fff4e0"/><rect y="468" width="800" height="2" fill="#f1d9a8"/><text x="400.0" y="489" font-size="14.5" font-weight="800" fill="#6b4a00" text-anchor="middle" >Ye sirf samjhane ke liye NAMUNA hai.</text><text x="400.0" y="508" font-size="13" font-weight="500" fill="#6b4a00" text-anchor="middle" >Aapki chhat aur sthiti ke anusaar asli design / report / samay alag ho sakta hai.</text></svg>$svg$, 'UTF8'));
  insert into public.crm_records(kind, title, status, owner_id, data, search)
  values ('doc', 'Site visit report ka namuna', 'ok', 0, jsonb_build_object('folder_id', fid, 'mime', 'image/svg+xml', 'size', 4091, 'note', 'Visit ke baad aisi report aapko isi link me milti hai.'), 'site visit report ka namuna') returning id into did;
  insert into public.crm_files(rec_id, mime, size, data) values (did, 'image/svg+xml', 4091, convert_to($svg$<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 520" width="800" height="520" font-family="system-ui,-apple-system,'Segoe UI',Roboto,'Noto Sans Devanagari','Noto Sans',sans-serif" role="img" aria-label="Site Visit Report ka namuna (namuna)"><rect width="800" height="520" fill="#f4f8f4"/><rect width="800" height="76" fill="#0f4d2b"/><text x="28" y="36" font-size="25" font-weight="800" fill="#fff" text-anchor="start" >Site Visit Report ka namuna</text><text x="28" y="60" font-size="14" font-weight="500" fill="#bfe3c8" text-anchor="start" >Visit ke baad aapko aisi report milti hai</text><rect x="678" y="20" width="94" height="30" rx="15" fill="#e8870c"/><text x="725" y="41" font-size="14" font-weight="800" fill="#fff" text-anchor="middle" letter-spacing="1.5">NAMUNA</text><rect x="60" y="96" width="680" height="336" rx="14" fill="#fff" stroke="#cfe0d2" stroke-width="1.5" /><text x="84" y="128" font-size="19" font-weight="800" fill="#0f4d2b" text-anchor="start" >SITE VISIT REPORT</text><text x="716" y="128" font-size="14" font-weight="800" fill="#e8870c" text-anchor="end" >(namuna)</text><path d="M84 140 H716" stroke="#cfe0d2" stroke-width="2"/><text x="84" y="166" font-size="14" font-weight="500" fill="#5d6f62" text-anchor="start" >Grahak: Namuna Grahak, Lucknow</text><text x="84" y="188" font-size="14" font-weight="500" fill="#5d6f62" text-anchor="start" >Visit ki tareekh: dd-mm-yyyy</text><path d="M86 224 l6 7 l12 -14" fill="none" stroke="#1e8e3e" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/><text x="114" y="229" font-size="14.5" font-weight="600" fill="#1c2b20" text-anchor="start" >Chhat ka upyogi kshetra</text><path d="M86 254 l6 7 l12 -14" fill="none" stroke="#1e8e3e" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/><text x="114" y="259" font-size="14.5" font-weight="600" fill="#1c2b20" text-anchor="start" >Chhaya / shading ki jaanch</text><path d="M86 284 l6 7 l12 -14" fill="none" stroke="#1e8e3e" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/><text x="114" y="289" font-size="14.5" font-weight="600" fill="#1c2b20" text-anchor="start" >Structure ki halat</text><path d="M86 314 l6 7 l12 -14" fill="none" stroke="#1e8e3e" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/><text x="114" y="319" font-size="14.5" font-weight="600" fill="#1c2b20" text-anchor="start" >Meter aur wiring ki jagah</text><rect x="430" y="196" width="90" height="70" rx="8" fill="#e3f3e7" stroke="#cfe0d2"/><text x="475" y="236" font-size="12" font-weight="600" fill="#5d6f62" text-anchor="middle" >photo</text><rect x="530" y="196" width="90" height="70" rx="8" fill="#e3f3e7" stroke="#cfe0d2"/><text x="575" y="236" font-size="12" font-weight="600" fill="#5d6f62" text-anchor="middle" >photo</text><rect x="630" y="196" width="90" height="70" rx="8" fill="#e3f3e7" stroke="#cfe0d2"/><text x="675" y="236" font-size="12" font-weight="600" fill="#5d6f62" text-anchor="middle" >photo</text><text x="430" y="292" font-size="13.5" font-weight="600" fill="#5d6f62" text-anchor="start" >Hamara sujhav: (aapki chhat ke hisaab se)</text><rect x="84" y="346" width="632" height="62" rx="10" fill="#f3f7f3"/><text x="100" y="372" font-size="15" font-weight="800" fill="#0f4d2b" text-anchor="start" >Agla kadam: Blueprint / Design</text><text x="100" y="394" font-size="13" font-weight="500" fill="#5d6f62" text-anchor="start" >Report me dikhi baatein design me dhyan me li jati hain.</text><g opacity="0.07" transform="rotate(-18 400 290)"><text x="400" y="300" font-size="84" font-weight="900" fill="#0f4d2b" text-anchor="middle" >SAMPLE · नमूना</text></g><rect y="468" width="800" height="52" fill="#fff4e0"/><rect y="468" width="800" height="2" fill="#f1d9a8"/><text x="400.0" y="489" font-size="14.5" font-weight="800" fill="#6b4a00" text-anchor="middle" >Ye sirf samjhane ke liye NAMUNA hai.</text><text x="400.0" y="508" font-size="13" font-weight="500" fill="#6b4a00" text-anchor="middle" >Aapki chhat aur sthiti ke anusaar asli design / report / samay alag ho sakta hai.</text></svg>$svg$, 'UTF8'));
  insert into public.crm_records(kind, title, status, owner_id, data, search)
  values ('folder', 'Error Detector', 'ok', 0, jsonb_build_object('name', 'Error Detector', 'parent_id', root::text, 'locked', false, 'note', 'Inverter ka error code dalte hi karan aur hal.', 'types', '["project", "product", "service"]'::jsonb, 'sort', 3), 'error detector') returning id into fid;
  insert into public.crm_records(kind, title, status, owner_id, data, search)
  values ('doc', 'Error Detector kaise kaam karta hai (namuna)', 'ok', 0, jsonb_build_object('folder_id', fid, 'mime', 'image/svg+xml', 'size', 4350, 'note', 'Code likhein — sambhav karan aur pehle kya jaanchein, turant.'), 'error detector kaise kaam karta hai (namuna)') returning id into did;
  insert into public.crm_files(rec_id, mime, size, data) values (did, 'image/svg+xml', 4350, convert_to($svg$<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 520" width="800" height="520" font-family="system-ui,-apple-system,'Segoe UI',Roboto,'Noto Sans Devanagari','Noto Sans',sans-serif" role="img" aria-label="Error Detector kaise kaam karta hai (namuna)"><rect width="800" height="520" fill="#f4f8f4"/><rect width="800" height="76" fill="#0f4d2b"/><text x="28" y="36" font-size="25" font-weight="800" fill="#fff" text-anchor="start" >Error Detector kaise kaam karta hai</text><text x="28" y="60" font-size="14" font-weight="500" fill="#bfe3c8" text-anchor="start" >Inverter ka code dalein — karan aur hal turant</text><rect x="678" y="20" width="94" height="30" rx="15" fill="#e8870c"/><text x="725" y="41" font-size="14" font-weight="800" fill="#fff" text-anchor="middle" letter-spacing="1.5">NAMUNA</text><rect x="40" y="100" width="300" height="330" rx="14" fill="#fff" stroke="#cfe0d2" stroke-width="1.5" /><text x="60" y="132" font-size="17" font-weight="800" fill="#0f4d2b" text-anchor="start" >1. Error code likhein</text><rect x="60" y="150" width="260" height="22" rx="11" fill="#eef3ee"/><text x="190" y="166" font-size="12.5" font-weight="600" fill="#5d6f62" text-anchor="middle" >Inverter ka brand: (chunein)</text><rect x="60" y="186" width="260" height="46" rx="10" fill="#fff" stroke="#1e8e3e" stroke-width="2.5"/><text x="76" y="216" font-size="22" font-weight="800" fill="#1c2b20" text-anchor="start" >E-03</text><rect x="60" y="248" width="260" height="46" rx="23" fill="#1e8e3e"/><text x="190" y="278" font-size="17" font-weight="800" fill="#fff" text-anchor="middle" >Check karein</text><text x="190" y="330" font-size="13.5" font-weight="500" fill="#5d6f62" text-anchor="middle" >Inverter ki screen par jo code dikhe,</text><text x="190" y="349" font-size="13.5" font-weight="500" fill="#5d6f62" text-anchor="middle" >wahi yahan likh dein</text><path d="M346 265 H384" stroke="#1e8e3e" stroke-width="3" stroke-linecap="round"/><path d="M378 258 L388 265 L378 272" fill="none" stroke="#1e8e3e" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/><rect x="400" y="100" width="360" height="330" rx="14" fill="#fff" stroke="#cfe0d2" stroke-width="1.5" /><text x="420" y="132" font-size="17" font-weight="800" fill="#0f4d2b" text-anchor="start" >2. Karan aur hal</text><rect x="420" y="146" width="320" height="36" rx="8" fill="#fdecea"/><text x="436" y="170" font-size="15.5" font-weight="800" fill="#a52a2a" text-anchor="start" >Code E-03  (namuna)</text><text x="420" y="208" font-size="13" font-weight="700" fill="#5d6f62" text-anchor="start" >Sambhav karan</text><text x="420" y="230" font-size="14" font-weight="500" fill="#1c2b20" text-anchor="start" >• Grid / wiring se judi dikkat</text><text x="420" y="252" font-size="14" font-weight="500" fill="#1c2b20" text-anchor="start" >• Supply ya breaker ka masla</text><text x="420" y="290" font-size="13" font-weight="700" fill="#5d6f62" text-anchor="start" >Pehle ye dekhein</text><path d="M424 314 l6 7 l12 -14" fill="none" stroke="#1e8e3e" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/><text x="452" y="319" font-size="14" font-weight="500" fill="#1c2b20" text-anchor="start" >Supply aur breaker ON hai?</text><path d="M424 342 l6 7 l12 -14" fill="none" stroke="#1e8e3e" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/><text x="452" y="347" font-size="14" font-weight="500" fill="#1c2b20" text-anchor="start" >Wiring dheeli to nahi?</text><path d="M424 370 l6 7 l12 -14" fill="none" stroke="#1e8e3e" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/><text x="452" y="375" font-size="14" font-weight="500" fill="#1c2b20" text-anchor="start" >Phir bhi na chale — team ko bulayein</text><g opacity="0.07" transform="rotate(-18 400 290)"><text x="400" y="300" font-size="84" font-weight="900" fill="#0f4d2b" text-anchor="middle" >SAMPLE · नमूना</text></g><rect y="468" width="800" height="52" fill="#fff4e0"/><rect y="468" width="800" height="2" fill="#f1d9a8"/><text x="400.0" y="489" font-size="14.5" font-weight="800" fill="#6b4a00" text-anchor="middle" >Ye sirf samjhane ke liye NAMUNA hai.</text><text x="400.0" y="508" font-size="13" font-weight="500" fill="#6b4a00" text-anchor="middle" >Aapki chhat aur sthiti ke anusaar asli design / report / samay alag ho sakta hai.</text></svg>$svg$, 'UTF8'));
  insert into public.crm_records(kind, title, status, owner_id, data, search)
  values ('folder', 'Net Metering', 'ok', 0, jsonb_build_object('name', 'Net Metering', 'parent_id', root::text, 'locked', false, 'note', 'Bijli company se net meter judne ki process.', 'types', '["project"]'::jsonb, 'sort', 4), 'net metering') returning id into fid;
  insert into public.crm_records(kind, title, status, owner_id, data, search)
  values ('doc', 'Net Metering ki process (namuna)', 'ok', 0, jsonb_build_object('folder_id', fid, 'mime', 'image/svg+xml', 'size', 4470, 'note', 'Samay aapke ilaake ki bijli company par nirbhar karta hai.'), 'net metering ki process (namuna)') returning id into did;
  insert into public.crm_files(rec_id, mime, size, data) values (did, 'image/svg+xml', 4470, convert_to($svg$<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 520" width="800" height="520" font-family="system-ui,-apple-system,'Segoe UI',Roboto,'Noto Sans Devanagari','Noto Sans',sans-serif" role="img" aria-label="Net Metering ki process (namuna)"><rect width="800" height="520" fill="#f4f8f4"/><rect width="800" height="76" fill="#0f4d2b"/><text x="28" y="36" font-size="25" font-weight="800" fill="#fff" text-anchor="start" >Net Metering ki process</text><text x="28" y="60" font-size="14" font-weight="500" fill="#bfe3c8" text-anchor="start" >Bijli company se meter judne tak ke kadam</text><rect x="678" y="20" width="94" height="30" rx="15" fill="#e8870c"/><text x="725" y="41" font-size="14" font-weight="800" fill="#fff" text-anchor="middle" letter-spacing="1.5">NAMUNA</text><path d="M80 220 H720" stroke="#cfe0d2" stroke-width="6" stroke-linecap="round"/><circle cx="80.0" cy="220" r="24" fill="#1e8e3e" stroke="#fff" stroke-width="4"/><text x="80.0" y="227" font-size="20" font-weight="800" fill="#fff" text-anchor="middle" >1</text><text x="80.0" y="280" font-size="15" font-weight="800" fill="#0f4d2b" text-anchor="middle" >Application</text><text x="80.0" y="304" font-size="12.5" font-weight="500" fill="#5d6f62" text-anchor="middle" >DISCOM ko</text><text x="80.0" y="321" font-size="12.5" font-weight="500" fill="#5d6f62" text-anchor="middle" >arzi</text><circle cx="240.0" cy="220" r="24" fill="#1e8e3e" stroke="#fff" stroke-width="4"/><text x="240.0" y="227" font-size="20" font-weight="800" fill="#fff" text-anchor="middle" >2</text><text x="240.0" y="280" font-size="15" font-weight="800" fill="#0f4d2b" text-anchor="middle" >Documents</text><text x="240.0" y="304" font-size="12.5" font-weight="500" fill="#5d6f62" text-anchor="middle" >jaanch</text><text x="240.0" y="321" font-size="12.5" font-weight="500" fill="#5d6f62" text-anchor="middle" >aur manzoori</text><circle cx="400.0" cy="220" r="24" fill="#1e8e3e" stroke="#fff" stroke-width="4"/><text x="400.0" y="227" font-size="20" font-weight="800" fill="#fff" text-anchor="middle" >3</text><text x="400.0" y="280" font-size="15" font-weight="800" fill="#0f4d2b" text-anchor="middle" >Inspection</text><text x="400.0" y="304" font-size="12.5" font-weight="500" fill="#5d6f62" text-anchor="middle" >sthal ki</text><text x="400.0" y="321" font-size="12.5" font-weight="500" fill="#5d6f62" text-anchor="middle" >jaanch</text><circle cx="560.0" cy="220" r="24" fill="#1e8e3e" stroke="#fff" stroke-width="4"/><text x="560.0" y="227" font-size="20" font-weight="800" fill="#fff" text-anchor="middle" >4</text><text x="560.0" y="280" font-size="15" font-weight="800" fill="#0f4d2b" text-anchor="middle" >Meter</text><text x="560.0" y="304" font-size="12.5" font-weight="500" fill="#5d6f62" text-anchor="middle" >net meter</text><text x="560.0" y="321" font-size="12.5" font-weight="500" fill="#5d6f62" text-anchor="middle" >lagna</text><circle cx="720.0" cy="220" r="24" fill="#1e8e3e" stroke="#fff" stroke-width="4"/><text x="720.0" y="227" font-size="20" font-weight="800" fill="#fff" text-anchor="middle" >5</text><text x="720.0" y="280" font-size="15" font-weight="800" fill="#0f4d2b" text-anchor="middle" >Chalu</text><text x="720.0" y="304" font-size="12.5" font-weight="500" fill="#5d6f62" text-anchor="middle" >bijli ka</text><text x="720.0" y="321" font-size="12.5" font-weight="500" fill="#5d6f62" text-anchor="middle" >hisaab shuru</text><rect x="60" y="372" width="680" height="60" rx="14" fill="#fff" stroke="#cfe0d2" stroke-width="1.5" /><text x="400" y="400" font-size="14" font-weight="800" fill="#0f4d2b" text-anchor="middle" >Samay aapke ilaake ki bijli company aur sthiti par nirbhar karta hai.</text><text x="400" y="421" font-size="13" font-weight="500" fill="#5d6f62" text-anchor="middle" >Hum har kadam par follow-up karte hain — aap bas jaankari dete rahein.</text><g opacity="0.07" transform="rotate(-18 400 290)"><text x="400" y="300" font-size="84" font-weight="900" fill="#0f4d2b" text-anchor="middle" >SAMPLE · नमूना</text></g><rect y="468" width="800" height="52" fill="#fff4e0"/><rect y="468" width="800" height="2" fill="#f1d9a8"/><text x="400.0" y="489" font-size="14.5" font-weight="800" fill="#6b4a00" text-anchor="middle" >Ye sirf samjhane ke liye NAMUNA hai.</text><text x="400.0" y="508" font-size="13" font-weight="500" fill="#6b4a00" text-anchor="middle" >Aapki chhat aur sthiti ke anusaar asli design / report / samay alag ho sakta hai.</text></svg>$svg$, 'UTF8'));
  insert into public.crm_records(kind, title, status, owner_id, data, search)
  values ('folder', 'Subsidy', 'ok', 0, jsonb_build_object('name', 'Subsidy', 'parent_id', root::text, 'locked', false, 'note', 'Sarkari subsidy paane ke kadam.', 'types', '["project"]'::jsonb, 'sort', 5), 'subsidy') returning id into fid;
  insert into public.crm_records(kind, title, status, owner_id, data, search)
  values ('doc', 'Subsidy ki process (namuna)', 'ok', 0, jsonb_build_object('folder_id', fid, 'mime', 'image/svg+xml', 'size', 4456, 'note', 'Niyam aur samay sarkari yojana ke anusaar badalte hain.'), 'subsidy ki process (namuna)') returning id into did;
  insert into public.crm_files(rec_id, mime, size, data) values (did, 'image/svg+xml', 4456, convert_to($svg$<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 520" width="800" height="520" font-family="system-ui,-apple-system,'Segoe UI',Roboto,'Noto Sans Devanagari','Noto Sans',sans-serif" role="img" aria-label="Subsidy ki process (namuna)"><rect width="800" height="520" fill="#f4f8f4"/><rect width="800" height="76" fill="#0f4d2b"/><text x="28" y="36" font-size="25" font-weight="800" fill="#fff" text-anchor="start" >Subsidy ki process</text><text x="28" y="60" font-size="14" font-weight="500" fill="#bfe3c8" text-anchor="start" >Sarkari yojana me subsidy paane ke kadam</text><rect x="678" y="20" width="94" height="30" rx="15" fill="#e8870c"/><text x="725" y="41" font-size="14" font-weight="800" fill="#fff" text-anchor="middle" letter-spacing="1.5">NAMUNA</text><path d="M80 220 H720" stroke="#cfe0d2" stroke-width="6" stroke-linecap="round"/><circle cx="80.0" cy="220" r="24" fill="#1e8e3e" stroke="#fff" stroke-width="4"/><text x="80.0" y="227" font-size="20" font-weight="800" fill="#fff" text-anchor="middle" >1</text><text x="80.0" y="280" font-size="15" font-weight="800" fill="#0f4d2b" text-anchor="middle" >Registration</text><text x="80.0" y="304" font-size="12.5" font-weight="500" fill="#5d6f62" text-anchor="middle" >sarkari portal</text><text x="80.0" y="321" font-size="12.5" font-weight="500" fill="#5d6f62" text-anchor="middle" >par</text><circle cx="240.0" cy="220" r="24" fill="#1e8e3e" stroke="#fff" stroke-width="4"/><text x="240.0" y="227" font-size="20" font-weight="800" fill="#fff" text-anchor="middle" >2</text><text x="240.0" y="280" font-size="15" font-weight="800" fill="#0f4d2b" text-anchor="middle" >Documents</text><text x="240.0" y="304" font-size="12.5" font-weight="500" fill="#5d6f62" text-anchor="middle" >upload</text><text x="240.0" y="321" font-size="12.5" font-weight="500" fill="#5d6f62" text-anchor="middle" >aur jaanch</text><circle cx="400.0" cy="220" r="24" fill="#1e8e3e" stroke="#fff" stroke-width="4"/><text x="400.0" y="227" font-size="20" font-weight="800" fill="#fff" text-anchor="middle" >3</text><text x="400.0" y="280" font-size="15" font-weight="800" fill="#0f4d2b" text-anchor="middle" >Installation</text><text x="400.0" y="304" font-size="12.5" font-weight="500" fill="#5d6f62" text-anchor="middle" >plant ki</text><text x="400.0" y="321" font-size="12.5" font-weight="500" fill="#5d6f62" text-anchor="middle" >sthapna</text><circle cx="560.0" cy="220" r="24" fill="#1e8e3e" stroke="#fff" stroke-width="4"/><text x="560.0" y="227" font-size="20" font-weight="800" fill="#fff" text-anchor="middle" >4</text><text x="560.0" y="280" font-size="15" font-weight="800" fill="#0f4d2b" text-anchor="middle" >Inspection</text><text x="560.0" y="304" font-size="12.5" font-weight="500" fill="#5d6f62" text-anchor="middle" >sarkari</text><text x="560.0" y="321" font-size="12.5" font-weight="500" fill="#5d6f62" text-anchor="middle" >jaanch</text><circle cx="720.0" cy="220" r="24" fill="#1e8e3e" stroke="#fff" stroke-width="4"/><text x="720.0" y="227" font-size="20" font-weight="800" fill="#fff" text-anchor="middle" >5</text><text x="720.0" y="280" font-size="15" font-weight="800" fill="#0f4d2b" text-anchor="middle" >Subsidy</text><text x="720.0" y="304" font-size="12.5" font-weight="500" fill="#5d6f62" text-anchor="middle" >aapke bank</text><text x="720.0" y="321" font-size="12.5" font-weight="500" fill="#5d6f62" text-anchor="middle" >khate me</text><rect x="60" y="372" width="680" height="60" rx="14" fill="#fff" stroke="#cfe0d2" stroke-width="1.5" /><text x="400" y="400" font-size="14" font-weight="800" fill="#0f4d2b" text-anchor="middle" >Niyam, patrata aur samay sarkari yojana ke anusaar badalte rehte hain.</text><text x="400" y="421" font-size="13" font-weight="500" fill="#5d6f62" text-anchor="middle" >Hum aapko har kadam par batate hain ki aage kya karna hai.</text><g opacity="0.07" transform="rotate(-18 400 290)"><text x="400" y="300" font-size="84" font-weight="900" fill="#0f4d2b" text-anchor="middle" >SAMPLE · नमूना</text></g><rect y="468" width="800" height="52" fill="#fff4e0"/><rect y="468" width="800" height="2" fill="#f1d9a8"/><text x="400.0" y="489" font-size="14.5" font-weight="800" fill="#6b4a00" text-anchor="middle" >Ye sirf samjhane ke liye NAMUNA hai.</text><text x="400.0" y="508" font-size="13" font-weight="500" fill="#6b4a00" text-anchor="middle" >Aapki chhat aur sthiti ke anusaar asli design / report / samay alag ho sakta hai.</text></svg>$svg$, 'UTF8'));
  insert into public.crm_records(kind, title, status, owner_id, data, search)
  values ('folder', 'AMC / Service', 'ok', 0, jsonb_build_object('name', 'AMC / Service', 'parent_id', root::text, 'locked', false, 'note', 'Solar plant ki niyamit service kaise milti hai.', 'types', '["project", "service"]'::jsonb, 'sort', 6), 'amc / service') returning id into fid;
  insert into public.crm_records(kind, title, status, owner_id, data, search)
  values ('doc', 'AMC kaise milti hai (namuna)', 'ok', 0, jsonb_build_object('folder_id', fid, 'mime', 'image/svg+xml', 'size', 4411, 'note', 'Visit ki ginti aapke AMC plan ke anusaar hoti hai.'), 'amc kaise milti hai (namuna)') returning id into did;
  insert into public.crm_files(rec_id, mime, size, data) values (did, 'image/svg+xml', 4411, convert_to($svg$<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 520" width="800" height="520" font-family="system-ui,-apple-system,'Segoe UI',Roboto,'Noto Sans Devanagari','Noto Sans',sans-serif" role="img" aria-label="AMC kaise milti hai (namuna)"><rect width="800" height="520" fill="#f4f8f4"/><rect width="800" height="76" fill="#0f4d2b"/><text x="28" y="36" font-size="25" font-weight="800" fill="#fff" text-anchor="start" >AMC kaise milti hai</text><text x="28" y="60" font-size="14" font-weight="500" fill="#bfe3c8" text-anchor="start" >Solar plant ki niyamit dekhbhal</text><rect x="678" y="20" width="94" height="30" rx="15" fill="#e8870c"/><text x="725" y="41" font-size="14" font-weight="800" fill="#fff" text-anchor="middle" letter-spacing="1.5">NAMUNA</text><rect x="40" y="100" width="720" height="330" rx="14" fill="#fff" stroke="#cfe0d2" stroke-width="1.5" /><text x="64" y="134" font-size="17" font-weight="800" fill="#0f4d2b" text-anchor="start" >Saal bhar ki service — aapka calendar</text><rect x="64" y="160" width="100" height="80" rx="12" fill="#1e8e3e"/><text x="114" y="194" font-size="18" font-weight="800" fill="#fff" text-anchor="middle" >Jan</text><text x="114" y="218" font-size="12.5" font-weight="700" fill="#d9f2df" text-anchor="middle" >service</text><rect x="178" y="160" width="100" height="80" rx="12" fill="#eef3ee"/><text x="228" y="194" font-size="18" font-weight="800" fill="#5d6f62" text-anchor="middle" >Feb</text><rect x="292" y="160" width="100" height="80" rx="12" fill="#eef3ee"/><text x="342" y="194" font-size="18" font-weight="800" fill="#5d6f62" text-anchor="middle" >Mar</text><rect x="406" y="160" width="100" height="80" rx="12" fill="#1e8e3e"/><text x="456" y="194" font-size="18" font-weight="800" fill="#fff" text-anchor="middle" >Apr</text><text x="456" y="218" font-size="12.5" font-weight="700" fill="#d9f2df" text-anchor="middle" >service</text><rect x="520" y="160" width="100" height="80" rx="12" fill="#eef3ee"/><text x="570" y="194" font-size="18" font-weight="800" fill="#5d6f62" text-anchor="middle" >May</text><rect x="634" y="160" width="100" height="80" rx="12" fill="#eef3ee"/><text x="684" y="194" font-size="18" font-weight="800" fill="#5d6f62" text-anchor="middle" >Jun</text><rect x="64" y="260" width="100" height="80" rx="12" fill="#1e8e3e"/><text x="114" y="294" font-size="18" font-weight="800" fill="#fff" text-anchor="middle" >Jul</text><text x="114" y="318" font-size="12.5" font-weight="700" fill="#d9f2df" text-anchor="middle" >service</text><rect x="178" y="260" width="100" height="80" rx="12" fill="#eef3ee"/><text x="228" y="294" font-size="18" font-weight="800" fill="#5d6f62" text-anchor="middle" >Aug</text><rect x="292" y="260" width="100" height="80" rx="12" fill="#eef3ee"/><text x="342" y="294" font-size="18" font-weight="800" fill="#5d6f62" text-anchor="middle" >Sep</text><rect x="406" y="260" width="100" height="80" rx="12" fill="#1e8e3e"/><text x="456" y="294" font-size="18" font-weight="800" fill="#fff" text-anchor="middle" >Oct</text><text x="456" y="318" font-size="12.5" font-weight="700" fill="#d9f2df" text-anchor="middle" >service</text><rect x="520" y="260" width="100" height="80" rx="12" fill="#eef3ee"/><text x="570" y="294" font-size="18" font-weight="800" fill="#5d6f62" text-anchor="middle" >Nov</text><rect x="634" y="260" width="100" height="80" rx="12" fill="#eef3ee"/><text x="684" y="294" font-size="18" font-weight="800" fill="#5d6f62" text-anchor="middle" >Dec</text><text x="400" y="382" font-size="13.5" font-weight="700" fill="#e8870c" text-anchor="middle" >Upar ke mahine sirf udaharan (namuna) hain.</text><text x="400" y="406" font-size="13.5" font-weight="600" fill="#5d6f62" text-anchor="middle" >Visit kitni baar hongi — ye aapke AMC plan ke anusaar tay hota hai.</text><g opacity="0.07" transform="rotate(-18 400 290)"><text x="400" y="300" font-size="84" font-weight="900" fill="#0f4d2b" text-anchor="middle" >SAMPLE · नमूना</text></g><rect y="468" width="800" height="52" fill="#fff4e0"/><rect y="468" width="800" height="2" fill="#f1d9a8"/><text x="400.0" y="489" font-size="14.5" font-weight="800" fill="#6b4a00" text-anchor="middle" >Ye sirf samjhane ke liye NAMUNA hai.</text><text x="400.0" y="508" font-size="13" font-weight="500" fill="#6b4a00" text-anchor="middle" >Aapki chhat aur sthiti ke anusaar asli design / report / samay alag ho sakta hai.</text></svg>$svg$, 'UTF8'));
  insert into public.crm_records(kind, title, status, owner_id, data, search)
  values ('doc', 'Service report ka namuna', 'ok', 0, jsonb_build_object('folder_id', fid, 'mime', 'image/svg+xml', 'size', 3766, 'note', 'Har service ke baad aisi report milti hai.'), 'service report ka namuna') returning id into did;
  insert into public.crm_files(rec_id, mime, size, data) values (did, 'image/svg+xml', 3766, convert_to($svg$<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 520" width="800" height="520" font-family="system-ui,-apple-system,'Segoe UI',Roboto,'Noto Sans Devanagari','Noto Sans',sans-serif" role="img" aria-label="AMC / Service Report ka namuna (namuna)"><rect width="800" height="520" fill="#f4f8f4"/><rect width="800" height="76" fill="#0f4d2b"/><text x="28" y="36" font-size="25" font-weight="800" fill="#fff" text-anchor="start" >AMC / Service Report ka namuna</text><text x="28" y="60" font-size="14" font-weight="500" fill="#bfe3c8" text-anchor="start" >Har service ke baad aisi report milti hai</text><rect x="678" y="20" width="94" height="30" rx="15" fill="#e8870c"/><text x="725" y="41" font-size="14" font-weight="800" fill="#fff" text-anchor="middle" letter-spacing="1.5">NAMUNA</text><rect x="60" y="96" width="680" height="336" rx="14" fill="#fff" stroke="#cfe0d2" stroke-width="1.5" /><text x="84" y="128" font-size="19" font-weight="800" fill="#0f4d2b" text-anchor="start" >SERVICE REPORT</text><text x="716" y="128" font-size="14" font-weight="800" fill="#e8870c" text-anchor="end" >(namuna)</text><path d="M84 140 H716" stroke="#cfe0d2" stroke-width="2"/><text x="84" y="166" font-size="14" font-weight="500" fill="#5d6f62" text-anchor="start" >Grahak: Namuna Grahak, Lucknow</text><text x="84" y="188" font-size="14" font-weight="500" fill="#5d6f62" text-anchor="start" >Service ki tareekh: dd-mm-yyyy</text><path d="M86 224 l6 7 l12 -14" fill="none" stroke="#1e8e3e" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/><text x="114" y="229" font-size="14.5" font-weight="600" fill="#1c2b20" text-anchor="start" >Panel ki safai</text><path d="M86 254 l6 7 l12 -14" fill="none" stroke="#1e8e3e" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/><text x="114" y="259" font-size="14.5" font-weight="600" fill="#1c2b20" text-anchor="start" >Inverter ki jaanch</text><path d="M86 284 l6 7 l12 -14" fill="none" stroke="#1e8e3e" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/><text x="114" y="289" font-size="14.5" font-weight="600" fill="#1c2b20" text-anchor="start" >Wiring / earthing ki jaanch</text><path d="M86 314 l6 7 l12 -14" fill="none" stroke="#1e8e3e" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/><text x="114" y="319" font-size="14.5" font-weight="600" fill="#1c2b20" text-anchor="start" >Generation ki jaanch</text><rect x="440" y="196" width="136" height="84" rx="8" fill="#e3f3e7" stroke="#cfe0d2"/><text x="508" y="242" font-size="12.5" font-weight="600" fill="#5d6f62" text-anchor="middle" >Pehle ki photo</text><rect x="590" y="196" width="136" height="84" rx="8" fill="#e3f3e7" stroke="#cfe0d2"/><text x="658" y="242" font-size="12.5" font-weight="600" fill="#5d6f62" text-anchor="middle" >Baad me ki photo</text><rect x="84" y="346" width="632" height="62" rx="10" fill="#f3f7f3"/><text x="100" y="372" font-size="15" font-weight="800" fill="#0f4d2b" text-anchor="start" >Agli service: dd-mm-yyyy</text><text x="100" y="394" font-size="13" font-weight="500" fill="#5d6f62" text-anchor="start" >Agli service ki yaad aapko pehle se mil jati hai.</text><g opacity="0.07" transform="rotate(-18 400 290)"><text x="400" y="300" font-size="84" font-weight="900" fill="#0f4d2b" text-anchor="middle" >SAMPLE · नमूना</text></g><rect y="468" width="800" height="52" fill="#fff4e0"/><rect y="468" width="800" height="2" fill="#f1d9a8"/><text x="400.0" y="489" font-size="14.5" font-weight="800" fill="#6b4a00" text-anchor="middle" >Ye sirf samjhane ke liye NAMUNA hai.</text><text x="400.0" y="508" font-size="13" font-weight="500" fill="#6b4a00" text-anchor="middle" >Aapki chhat aur sthiti ke anusaar asli design / report / samay alag ho sakta hai.</text></svg>$svg$, 'UTF8'));
end $seed$;

-- ---------- customer ke link ke liye: kis type ka customer (project / product / service) ----------
create or replace function public.crm__sample_type(q public.crm_records) returns text language plpgsql stable security definer set search_path = public as $f$
declare ct text := coalesce(q.data ->> 'ctype', ''); pk text;
begin
  if ct in ('Residential', 'Commercial', 'Industrial', 'VFD') then return 'project'; end if;
  if ct = 'Items only' then return 'product'; end if;
  if ct in ('Service', 'AMC only', 'Site visit only') then return 'service'; end if;
  select data ->> 'cust_kind' into pk from public.crm_records where id = q.party_id;
  return case when pk in ('product', 'service') then pk else 'project' end;
end $f$;
revoke all on function public.crm__sample_type(public.crm_records) from public, anon, authenticated;

-- ---------- "Hum kaise kaam karte hain": sirf Customer Samples folder ki files, customer ke type ke hisaab se ----------
create or replace function public.sp_samples(p_token text) returns jsonb language plpgsql security definer set search_path = public as $f$
declare r public.sp_shares; q public.crm_records; root bigint := public.crm__sample_root(); ty text; out jsonb := '[]'::jsonb; fo public.crm_records; ds jsonb; rn text;
begin
  if root is null then return jsonb_build_object('groups', '[]'::jsonb); end if;
  select * into r from public.sp_shares where token = btrim(coalesce(p_token, '')) and live and not revoked and expires_at > now();
  if r.id is null then return null; end if;
  select * into q from public.crm_records where id = r.quote_id and kind = 'quote' and deleted_at is null;
  if q.id is null then return null; end if;
  ty := public.crm__sample_type(q);
  select data ->> 'note' into rn from public.crm_records where id = root;
  for fo in select * from public.crm_records where kind = 'folder' and deleted_at is null and nullif(data ->> 'parent_id', '') = root::text
              and (not (data ? 'types') or jsonb_typeof(data -> 'types') <> 'array' or jsonb_array_length(data -> 'types') = 0 or data -> 'types' ? ty)
              order by coalesce(nullif(data ->> 'sort', '')::int, 999), id loop
    select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'title', d.title, 'note', d.data ->> 'note', 'mime', d.data ->> 'mime') order by d.id), '[]'::jsonb) into ds
      from public.crm_records d where d.kind = 'doc' and d.deleted_at is null and nullif(d.data ->> 'folder_id', '')::bigint = fo.id
       and coalesce(d.data ->> 'mime', '') ~ '^(image/(png|jpeg|webp|gif|svg\+xml)|application/pdf)$';
    if jsonb_array_length(ds) > 0 then out := out || jsonb_build_array(jsonb_build_object('id', fo.id, 'title', coalesce(nullif(fo.data ->> 'name', ''), fo.title), 'note', fo.data ->> 'note', 'docs', ds)); end if;
  end loop;
  return jsonb_build_object('type', ty, 'groups', out);
end $f$;
grant execute on function public.sp_samples(text) to anon, authenticated;

create or replace function public.sp_sample_file(p_token text, p_id bigint) returns jsonb language plpgsql security definer set search_path = public as $f$
declare r public.sp_shares; root bigint := public.crm__sample_root(); d public.crm_records; f public.crm_files; fid bigint;
begin
  if root is null then return null; end if;
  select * into r from public.sp_shares where token = btrim(coalesce(p_token, '')) and live and not revoked and expires_at > now();
  if r.id is null then return null; end if;
  select * into d from public.crm_records where id = p_id and kind = 'doc' and deleted_at is null;
  if d.id is null then return null; end if;
  fid := nullif(d.data ->> 'folder_id', '')::bigint;
  if fid is null or not exists (select 1 from public.crm_records f2 where f2.id = fid and f2.kind = 'folder' and f2.deleted_at is null and (f2.id = root or nullif(f2.data ->> 'parent_id', '') = root::text)) then return null; end if;
  select * into f from public.crm_files where rec_id = d.id limit 1;
  if f.id is null or f.mime !~ '^(image/(png|jpeg|webp|gif|svg\+xml)|application/pdf)$' then return null; end if;
  return jsonb_build_object('mime', f.mime, 'b64', encode(f.data, 'base64'), 'name', d.title);
end $f$;
grant execute on function public.sp_sample_file(text, bigint) to anon, authenticated;

-- =====================================================================================================
-- ROUND 54 — customer flow ka naya kram (Quotation -> Confirmation -> Site Visit -> Blueprint -> Apply),
--   online order = pehle se Confirmed, aur pehli Project quotation par "anumanit" nishaan.
--   Step numbers nahi badle. Purana data/ticks waise hi rehte hain. Dobara chalane se koi nuksan nahi.
-- =====================================================================================================
-- Step numbers (data.wf keys / permissions) NAHI badle — sirf kram. Site Visit (4) kabhi bhi tick ho sakta hai.
create or replace function public.crm_wf_flow(ct text) returns integer[] language sql immutable as $f$
  select case
    when ct = 'Items only'  then array[19,1,2,14,3,6,20,12,21,22,16,18]
    when ct = 'Service'     then array[19,1,2,4,3,6,8,23,12,14,16,17,18]
    when ct = 'AMC only'        then array[19,1,2,17]
    when ct = 'Site visit only' then array[19,1,2,4]
    when ct = 'Residential' then array[19,1,2,14,3,6,4,5,7,15,8,9,10,11,12,13,16,17,18]
    else                         array[19,1,2,14,3,6,4,5,7,15,8,9,10,11,12,16,17,18] end $f$;

-- Online Store order wala customer: order aaya = Confirmed. Conversation / Quotation / Demo files "lagu nahi", Confirmation auto-ticked.
create or replace function public.crm_wf_synth(q public.crm_records) returns jsonb language plpgsql stable security definer set search_path = public as $f$
declare pt public.crm_records; at_ text; e jsonb; oid bigint;
begin
  if q.party_id is null then return '{}'::jsonb; end if;
  select * into pt from public.crm_records where id = q.party_id and kind = 'party';
  if pt.id is null or coalesce(pt.data ->> 'intake', '') <> 'store' then return '{}'::jsonb; end if;
  begin oid := nullif(pt.data ->> 'store_order_id', '')::bigint; exception when others then oid := null; end;
  if oid is not null and exists (select 1 from public.sp_orders where id = oid and status = 'cancelled') then return '{}'::jsonb; end if;
  at_ := to_char(pt.created_at at time zone 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS"+05:30"');
  e := jsonb_build_object('at', at_, 'by', 'Online order (system)', 'auto', true, 'skip', true, 'note', 'Online order — lagu nahi');
  return jsonb_build_object('2', e, '3', e, '14', e, '6', jsonb_build_object('at', at_, 'by', 'Online order (system)', 'auto', true, 'note', 'Online order = Confirmed'));
end $f$;

CREATE OR REPLACE FUNCTION public.crm_wf_steps(s crm_ses, q crm_records)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare names text[] := public.crm_wf_names(); out jsonb := '[]'::jsonb; n int; w jsonb := public.crm_wf_synth(q) || coalesce(q.data -> 'wf', '{}'::jsonb); st jsonb; v boolean; e boolean;
        priv boolean := public.crm_is_admin(s) or (s).role = 'manager'; pat text; auto boolean;
begin
  foreach n in array public.crm_wf_flow_of(q) loop
    auto := public.crm_wf_is_auto(n);
    if n = 19 then
      select to_char(created_at at time zone 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS"+05:30"') into pat from public.crm_records where id = q.party_id;
      out := out || jsonb_build_array(jsonb_build_object('n', 19, 'name', names[19], 'done', true, 'at', pat, 'auto', true, 'manual', false, 'skip', false, 'locked', false, 'can_edit', false,
        'note', 'Path (kahan se aaya): ' || coalesce(nullif((select data ->> 'source' from public.crm_records where id = q.party_id), ''), 'Purana / Unknown')));
      continue;
    end if;
    st := w -> n::text; v := public.crm_wf_can(s, n, 'view'); e := public.crm_wf_can(s, n, 'edit');
    out := out || jsonb_build_array(jsonb_build_object('n', n, 'name', names[n], 'done', st is not null, 'at', st ->> 'at',
      'auto', coalesce((st ->> 'auto')::boolean, false), 'manual', not auto, 'skip', coalesce((st ->> 'skip')::boolean, false), 'can_skip', public.crm_wf_can_skip(n),
      'locked', not v, 'can_edit', e and not auto and (n <> 13 or priv),
      'by', case when v then st ->> 'by' end, 'note', case when v then st ->> 'note' end, 'info', case when v then coalesce(st -> 'info', '{}'::jsonb) end));
  end loop;
  return out;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_wf_set(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; n int := (p ->> 'step')::int; done boolean := coalesce((p ->> 'done')::boolean, true); note text := left(trim(coalesce(p ->> 'note', '')), 500);
        skip boolean := coalesce((p ->> 'skip')::boolean, false); w jsonb; flow int[]; ct text; inf jsonb := '{}'::jsonb; f jsonb; v text; miss text[] := '{}'; entry jsonb; has_info boolean := p ? 'info';
begin
  select * into q from public.crm_records where id = (p ->> 'id')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if n is null or n < 1 or n > 23 then raise exception 'Step galat hai'; end if;
  if public.crm_wf_is_auto(n) then raise exception 'Ye step apne aap hota hai (quotation / bill / lead se)'; end if;
  ct := coalesce(q.data ->> 'ctype', ''); flow := public.crm_wf_flow_of(q);
  if not (n = any (flow)) then
    if n = 13 then raise exception 'Subsidy sirf Residential solar ke liye hai'; end if;
    raise exception 'Ye step is customer ke liye nahi hai (% — %)', case ct when 'Items only' then 'Product customer' when 'Service' then 'Service customer' when 'AMC only' then 'AMC customer' when 'Site visit only' then 'Site visit customer' else 'Project customer' end, (public.crm_wf_names())[n];
  end if;
  if n = 13 and not (public.crm_is_admin(s) or (s).role = 'manager') then raise exception 'Subsidy sirf Admin ya Manager green kar sakte hain'; end if;
  if not public.crm_wf_can(s, n, 'edit') then raise exception 'Is step ko badalne ki permission nahi hai — Admin se allow karwayein'; end if;
  w := public.crm_wf_synth(q) || coalesce(q.data -> 'wf', '{}'::jsonb);
  if done then
    if n = 7 and not (w ? '6') then raise exception 'Pehle quotation Confirm hona chahiye'; end if;
    if (n in (9, 10, 11, 13) or (n = 8 and ct <> 'Service') or (n = 17 and ct not in ('Service', 'AMC only'))) and not (w ? '7') then raise exception 'Pehle Apply Process confirm karein — tabhi customer Projects me aata hai'; end if;
    if (n in (15, 16, 18, 20, 21, 22, 23) or (n = 8 and ct = 'Service') or (n = 17 and ct = 'Service')) and not (w ? '6') then raise exception 'Pehle quotation Confirm hona chahiye'; end if;
    if skip and not public.crm_wf_can_skip(n) then raise exception 'Ye step "Lagu nahi" nahi kiya ja sakta'; end if;
    if skip then
      entry := jsonb_build_object('at', public.crm_iso_now(), 'by', (s).name, 'by_id', (s).uid, 'note', note, 'skip', true);
    else
      -- keep only the fields this step defines; mandatory ones must be filled (only when the new screen sends "info")
      for f in select * from jsonb_array_elements(coalesce(public.crm_wf_fields() -> n::text, '[]'::jsonb)) loop
        v := left(trim(coalesce(p -> 'info' ->> (f ->> 'k'), '')), 200);
        if v <> '' then inf := inf || jsonb_build_object(f ->> 'k', v);
        elsif has_info and coalesce((f ->> 'req')::boolean, false) then miss := miss || (f ->> 'l'); end if;
      end loop;
      if array_length(miss, 1) > 0 then raise exception 'Ye details bharna zaroori hai: %', array_to_string(miss, ', '); end if;
      entry := jsonb_build_object('at', public.crm_iso_now(), 'by', (s).name, 'by_id', (s).uid, 'note', note) || case when inf = '{}'::jsonb then '{}'::jsonb else jsonb_build_object('info', inf) end;
    end if;
    w := w || jsonb_build_object(n::text, entry);
  else
    if not public.crm_is_admin(s) then raise exception 'Step wapas sirf Admin kar sakta hai'; end if;
    w := w - n::text;
  end if;
  perform set_config('sp.wf', '1', true);
  update public.crm_records set data = data || jsonb_build_object('wf', w), updated_at = now() where id = q.id;
  perform set_config('sp.wf', '', true);
  perform public.crm_log(s, 'workflow', 'quote', q.id, coalesce(q.ref, '') || ' — ' || (public.crm_wf_names())[n] || case when not done then ' ↩' when skip then ' (lagu nahi)' else ' ✔' end);
  select * into q from public.crm_records where id = q.id;
  return public.crm_wf_get(jsonb_build_object('token', p ->> 'token', 'id', q.id));
end $function$;

-- Quotation link: anumanit / antim nishaan (sirf Project quotation, site visit se pehle / baad)
CREATE OR REPLACE FUNCTION public.crm__quote_pub(q crm_records)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d jsonb := q.data; prim text := coalesce(q.data ->> 'opt_id', 'A'); opts jsonb := '[]'::jsonb; x jsonb; lk jsonb := q.data -> 'locked'; po jsonb;
begin
  po := jsonb_build_object('id', prim, 'label', coalesce(d ->> 'opt_label', case when jsonb_array_length(coalesce(d -> 'alt', '[]'::jsonb)) > 0 then 'Option 1' else 'Quotation' end), 'lines', d -> 'lines', 'grand', d -> 'grand', 'kw', d -> 'kw', 'pdf_url', d -> 'pdf_url');
  opts := jsonb_build_array(public.crm__opt_pub(po, d, true, lk is not null));
  if lk is null then
    for x in select * from jsonb_array_elements(coalesce(d -> 'alt', '[]'::jsonb)) loop
      if coalesce(x ->> 'dropped', '') <> 'true' then opts := opts || jsonb_build_array(public.crm__opt_pub(x, d, false, false)); end if;
    end loop;
  end if;
  return jsonb_strip_nulls(jsonb_build_object('ref', q.ref, 'title', d ->> 'qtitle', 'status', q.status, 'valid_till', d ->> 'valid_till', 'opts', opts,
    'est', case when coalesce(d ->> 'ctype', '') in ('Residential', 'Commercial', 'Industrial', 'VFD') and not coalesce(d -> 'wf', '{}'::jsonb) ? '4' and q.status not in ('accepted') then true end,
    'final', case when coalesce(d ->> 'ctype', '') in ('Residential', 'Commercial', 'Industrial', 'VFD') and coalesce(d -> 'wf', '{}'::jsonb) ? '4' then true end,
    'locked', case when lk is not null then jsonb_build_object('label', lk ->> 'label', 'at', lk ->> 'at', 'via', lk ->> 'via') end,
    'reaccept', case when coalesce(d ->> 'reaccept', '') = 'true' then true end,
    'resp', case when d -> 'resp' is not null then jsonb_build_object('change', d #> '{resp,change,at}', 'callback', d #> '{resp,callback,at}') end));
end $function$;

-- ===== U25 (Round 55): ek customer = ek pankti; lock par baaki band + chhota history; reserve niyam; stock hint =====
-- Purana data waise hi rehta hai. Dobara chalane se koi nuksan nahi.

create or replace function public.crm__hist_add(d jsonb, e jsonb) returns jsonb language sql immutable as $f$
  select d || jsonb_build_object('history', (select coalesce(jsonb_agg(x order by ord), '[]'::jsonb) from (
      select x, ord from jsonb_array_elements(coalesce(d -> 'history', '[]'::jsonb) || jsonb_build_array(e)) with ordinality t(x, ord) order by ord desc limit 40) z))
$f$;

-- Lock hone par: usi customer ki doosri (usi kaam ki) draft/sent Project quotation band + bhaari data (PDF link) hata kar chhota saar
create or replace function public.crm__quote_supersede(qid bigint) returns void language plpgsql security definer set search_path = public as $f$
declare q public.crm_records; o public.crm_records; d jsonb; x jsonb; pj text[] := array['Residential', 'Commercial', 'Industrial', 'VFD'];
begin
  select * into q from public.crm_records where id = qid and kind = 'quote' and deleted_at is null;
  if q.id is null then return; end if;
  d := q.data;
  -- is quotation ke apne chhode hue options ka saar (dobara lock par double nahi)
  d := d || jsonb_build_object('history', (select coalesce(jsonb_agg(h), '[]'::jsonb) from jsonb_array_elements(coalesce(d -> 'history', '[]'::jsonb)) h where h ->> 't' not in ('option', 'quote', 'accept')));
  for x in select * from jsonb_array_elements(coalesce(d -> 'alt', '[]'::jsonb)) a where coalesce(a ->> 'dropped', '') = 'true' loop
    d := public.crm__hist_add(d, jsonb_strip_nulls(jsonb_build_object('t', 'option', 'at', coalesce(x ->> 'created_at', to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SS')), 'label', x ->> 'label', 'kw', x ->> 'kw', 'grand', x -> 'grand')));
  end loop;
  -- dropped options ka PDF link hata do (lines rakhte hain, taaki unlock par wapas aa sake)
  d := d || jsonb_build_object('alt', (select coalesce(jsonb_agg(case when coalesce(a ->> 'dropped', '') = 'true' then a - 'pdf_url' else a end), '[]'::jsonb) from jsonb_array_elements(coalesce(d -> 'alt', '[]'::jsonb)) a));
  if coalesce(q.data ->> 'ctype', '') = any (pj) then
    for o in select * from public.crm_records c where c.kind = 'quote' and c.deleted_at is null and c.party_id = q.party_id and c.id <> q.id and c.status in ('draft', 'sent')
        and coalesce(c.data ->> 'ctype', '') = coalesce(q.data ->> 'ctype', '') and c.data -> 'locked' is null and c.data -> 'superseded_by' is null
        and (coalesce(c.data ->> 'kw', '') = '' or coalesce(q.data ->> 'kw', '') = '' or public.crm_num(c.data -> 'kw') = public.crm_num(q.data -> 'kw')) loop
      d := public.crm__hist_add(d, jsonb_strip_nulls(jsonb_build_object('t', 'quote', 'at', to_char(o.created_at at time zone 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS'), 'ref', o.ref,
            'label', coalesce(nullif(o.data ->> 'opt_label', ''), nullif(o.data ->> 'qtitle', ''), o.ref), 'kw', o.data ->> 'kw', 'grand', o.data -> 'grand', 'from', o.id)));
      update public.crm_records set status = 'rejected', updated_at = now(),
        data = (o.data - 'pdf_url') || jsonb_build_object('superseded_by', q.id, 'superseded_at', now(),
          'alt', (select coalesce(jsonb_agg(a - 'pdf_url'), '[]'::jsonb) from jsonb_array_elements(coalesce(o.data -> 'alt', '[]'::jsonb)) a))
        where id = o.id;
    end loop;
  end if;
  d := public.crm__hist_add(d, jsonb_strip_nulls(jsonb_build_object('t', 'accept', 'at', to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS'), 'label', coalesce(nullif(d ->> 'opt_label', ''), nullif(d ->> 'qtitle', ''), d #>> '{locked,label}'), 'grand', d -> 'grand', 'kw', d ->> 'kw')));
  update public.crm_records set data = d where id = q.id;
end $f$;
revoke all on function public.crm__quote_supersede(bigint) from public, anon, authenticated;

create or replace function public.crm__quote_revive(qid bigint) returns void language plpgsql security definer set search_path = public as $f$
begin
  update public.crm_records set status = 'sent', updated_at = now(), data = data - 'superseded_by' - 'superseded_at'
    where kind = 'quote' and deleted_at is null and (data ->> 'superseded_by') = qid::text;
  update public.crm_records set data = data || jsonb_build_object('history', (select coalesce(jsonb_agg(h), '[]'::jsonb) from jsonb_array_elements(coalesce(data -> 'history', '[]'::jsonb)) h where h ->> 't' not in ('option', 'quote', 'accept')))
    where id = qid;
end $f$;
revoke all on function public.crm__quote_revive(bigint) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.crm__quote_lock(qid bigint, optid text, via text, who text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare q public.crm_records; d jsonb; prim text; o jsonb; e jsonb; na jsonb := '[]'::jsonb; xe jsonb;
begin
  select * into q from public.crm_records where id = qid and kind = 'quote' and deleted_at is null for update;
  if q.id is null then raise exception 'Quotation nahi mili'; end if;
  d := q.data; prim := coalesce(d ->> 'opt_id', 'A'); optid := coalesce(nullif(optid, ''), prim);
  if optid <> prim then
    select x into o from jsonb_array_elements(coalesce(d -> 'alt', '[]'::jsonb)) t(x) where x ->> 'id' = optid and coalesce(x ->> 'dropped', '') <> 'true';
    if o is null then raise exception 'Ye option nahi mila'; end if;
    e := jsonb_build_object('id', prim, 'label', coalesce(d ->> 'opt_label', 'Option ' || prim), 'lines', d -> 'lines', 'discount', coalesce(d -> 'discount', '0'::jsonb), 'subtotal', d -> 'subtotal', 'gst_total', d -> 'gst_total', 'grand', d -> 'grand', 'qtitle', d -> 'qtitle', 'dropped', true);
    if d ? 'kw' then e := e || jsonb_build_object('kw', d -> 'kw'); end if;
    if d ? 'pdf_url' then e := e || jsonb_build_object('pdf_url', d -> 'pdf_url'); end if;
    na := jsonb_build_array(e);
    for xe in select * from jsonb_array_elements(coalesce(d -> 'alt', '[]'::jsonb)) loop if xe ->> 'id' <> optid then na := na || jsonb_build_array(xe || '{"dropped":true}'::jsonb); end if; end loop;
    d := (d - 'kw' - 'pdf_url') || jsonb_build_object('lines', o -> 'lines', 'discount', coalesce(o -> 'discount', '0'::jsonb), 'subtotal', o -> 'subtotal', 'gst_total', o -> 'gst_total', 'grand', o -> 'grand',
          'qtitle', coalesce(o ->> 'qtitle', d ->> 'qtitle'), 'opt_id', optid, 'opt_label', o ->> 'label', 'alt', na);
    if o ? 'kw' then d := d || jsonb_build_object('kw', o -> 'kw'); end if;
    if o ? 'pdf_url' then d := d || jsonb_build_object('pdf_url', o -> 'pdf_url'); end if;
  else
    for xe in select * from jsonb_array_elements(coalesce(d -> 'alt', '[]'::jsonb)) loop na := na || jsonb_build_array(xe || '{"dropped":true}'::jsonb); end loop;
    d := d || jsonb_build_object('alt', na);
  end if;
  d := (d - 'reaccept') || jsonb_build_object('locked', jsonb_build_object('opt_id', coalesce(d ->> 'opt_id', prim), 'label', coalesce(d ->> 'opt_label', 'Option ' || coalesce(d ->> 'opt_id', prim)), 'at', now(), 'by', left(who, 80), 'via', via));
  update public.crm_records set data = d, status = 'accepted', amount = public.crm_num(d -> 'grand'), updated_at = now() where id = q.id;
  perform public.crm__quote_supersede(q.id);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_quote_unlock(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; why text := left(trim(coalesce(p ->> 'reason', '')), 300);
begin
  if not (public.crm_is_admin(s) or (s).role = 'manager') then raise exception 'Sirf Manager ya Admin'; end if;
  if length(why) < 3 then raise exception 'Wajah likhein'; end if;
  select * into q from public.crm_records where id = (p ->> 'id')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if q.data -> 'locked' is null then raise exception 'Ye final nahi hai'; end if;
  if q.status = 'converted' then raise exception 'Bill ban chuka hai'; end if;
  update public.crm_records set status = 'sent', data = (data - 'locked' - 'reaccept') || jsonb_build_object('alt', (select coalesce(jsonb_agg(x - 'dropped'), '[]'::jsonb) from jsonb_array_elements(coalesce(data -> 'alt', '[]'::jsonb)) x), 'unlocks', coalesce(data -> 'unlocks', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('at', now(), 'by', (s).name, 'reason', why))), updated_at = now() where id = q.id;
  perform public.crm__quote_revive(q.id);
  perform public.crm_log(s, 'unlock', 'quote', q.id, coalesce(q.ref, '') || ' final wapas liya — ' || why);
  select * into q from public.crm_records where id = q.id; return public.crm_row(s, q);
end $function$;

CREATE OR REPLACE FUNCTION public.sp_quote_respond(p_token text, p_action text, p_opt text DEFAULT NULL::text, p_last4 text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.sp_shares; q public.crm_records; pa public.crm_records; act text := lower(coalesce(p_action, '')); note text := left(btrim(coalesce(p_note, '')), 300); l4 text := regexp_replace(coalesce(p_last4, ''), '\D', '', 'g');
        prim text; oid text; lbl text; nopt int; last_at timestamptz;
begin
  perform public.sp_share_rate(30);
  select * into r from public.sp_shares where token = btrim(coalesce(p_token, '')) and live and not revoked and expires_at > now();
  if r.id is null then raise exception 'Ye link ab chalu nahi hai'; end if;
  select * into q from public.crm_records where id = r.quote_id and kind = 'quote' and deleted_at is null;
  if q.id is null then raise exception 'Quotation nahi mili'; end if;
  if q.status in ('expired', 'converted', 'rejected') then return jsonb_build_object('error', 'Is quotation par ab jawab nahi ho sakta — kripya humse sampark karein'); end if;
  prim := coalesce(q.data ->> 'opt_id', 'A');
  if act = 'accept' then
    if q.data -> 'locked' is not null and coalesce(q.data ->> 'reaccept', '') <> 'true' then return jsonb_build_object('ok', true, 'already', true, 'quote', public.crm__quote_pub(q)); end if;
    if r.bad_tries >= 5 and r.bad_at > now() - interval '1 day' then return jsonb_build_object('error', 'Kai galat koshish ho chuki — kripya humse sampark karein'); end if;
    select * into pa from public.crm_records where id = q.party_id;
    if length(l4) <> 4 or right(coalesce(pa.mobile, ''), 4) is distinct from l4 then
      update public.sp_shares set bad_tries = case when bad_at > now() - interval '1 day' then bad_tries + 1 else 1 end, bad_at = now() where id = r.id;
      return jsonb_build_object('error', 'Mobile ke aakhri 4 ank match nahi hue');
    end if;
    nopt := 1 + (select count(*) from jsonb_array_elements(coalesce(q.data -> 'alt', '[]'::jsonb)) x where coalesce(x ->> 'dropped', '') <> 'true');
    oid := nullif(btrim(coalesce(p_opt, '')), '');
    if q.data -> 'locked' is not null then oid := prim; end if;
    if oid is null and nopt > 1 then return jsonb_build_object('error', 'Pehle ek option chunein'); end if;
    if oid is not null and oid <> prim and not exists (select 1 from jsonb_array_elements(coalesce(q.data -> 'alt', '[]'::jsonb)) x where x ->> 'id' = oid and coalesce(x ->> 'dropped', '') <> 'true') then return jsonb_build_object('error', 'Ye option nahi mila'); end if;
    perform public.crm__quote_lock(q.id, oid, 'customer', 'Customer (link)');
    update public.sp_shares set bad_tries = 0 where id = r.id;
    select * into q from public.crm_records where id = q.id;
    update public.crm_records set data = data || jsonb_build_object('resp', coalesce(data -> 'resp', '{}'::jsonb) || jsonb_build_object('accept', jsonb_build_object('at', now(), 'opt', q.data #>> '{locked,opt_id}', 'amount', q.data -> 'grand'))) where id = q.id;
    insert into public.crm_activity(user_id, user_name, role, action, kind, rec_id, summary) values (0, 'Customer (link)', 'customer', 'accept', 'quote', q.id, left(coalesce(q.ref, '') || ' Accept: ' || coalesce(q.data #>> '{locked,label}', ''), 300));
    perform public.crm__quote_remind(q, 'Customer ne Accept kiya — advance ke liye call karein', 'Option: ' || coalesce(q.data #>> '{locked,label}', '') || ' · ' || coalesce(q.data ->> 'grand', ''));
  elsif act = 'change' then
    if length(note) < 3 then return jsonb_build_object('error', 'Kya badlav chahiye, thoda likhein'); end if;
    last_at := nullif(q.data #>> '{resp,change,at}', '')::timestamptz;
    if last_at is null or last_at < now() - interval '5 minutes' then
      update public.crm_records set data = data || jsonb_build_object('resp', coalesce(data -> 'resp', '{}'::jsonb) || jsonb_build_object('change', jsonb_build_object('at', now(), 'note', note))) where id = q.id;
      update public.crm_records set data = public.crm__hist_add(data, jsonb_build_object('t', 'change', 'at', to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS'), 'note', note)) where id = q.id;
      select * into q from public.crm_records where id = q.id;
      insert into public.crm_activity(user_id, user_name, role, action, kind, rec_id, summary) values (0, 'Customer (link)', 'customer', 'change', 'quote', q.id, left(coalesce(q.ref, '') || ' badlav: ' || note, 300));
      perform public.crm__quote_remind(q, 'Customer ko badlav chahiye', note);
    end if;
  elsif act = 'callback' then
    last_at := nullif(q.data #>> '{resp,callback,at}', '')::timestamptz;
    if last_at is null or last_at < now() - interval '30 minutes' then
      update public.crm_records set data = data || jsonb_build_object('resp', coalesce(data -> 'resp', '{}'::jsonb) || jsonb_build_object('callback', jsonb_build_object('at', now()))) where id = q.id;
      select * into q from public.crm_records where id = q.id;
      perform public.crm__quote_remind(q, 'Customer ne call back maanga', note);
    end if;
  else raise exception 'Galat kaam'; end if;
  select * into q from public.crm_records where id = q.id;
  return jsonb_build_object('ok', true, 'quote', public.crm__quote_pub(q));
end $function$;

-- Kai option wali quotation Accept se pehle stock reserve nahi karti; lock ke baad sirf chuna hua option (lines) reserve hota hai
CREATE OR REPLACE FUNCTION public.crm_reserves(p_exclude bigint DEFAULT NULL::bigint)
 RETURNS TABLE(item_id bigint, qty numeric, quote_id bigint, ref text, customer text, valid_till text, qstatus text, qtitle text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select (l ->> 'item_id')::bigint, public.crm_num(l -> 'qty'), q.id, q.ref, q.title, q.data ->> 'valid_till', q.status, q.data ->> 'qtitle'
  from public.crm_records q, jsonb_array_elements(coalesce(q.data -> 'lines', '[]'::jsonb)) l
  where q.kind = 'quote' and q.deleted_at is null and q.status in ('draft', 'sent', 'accepted') and q.id <> coalesce(p_exclude, 0)
    and (q.data -> 'locked' is not null or not exists (select 1 from jsonb_array_elements(coalesce(q.data -> 'alt', '[]'::jsonb)) z where coalesce(z ->> 'dropped', '') <> 'true'))
    and coalesce(l ->> 'kind', 'product') <> 'project' and coalesce(l ->> 'item_id', '') ~ '^[0-9]+$'
  union all
  select (x ->> 'item_id')::bigint, public.crm_num(x -> 'qty') * greatest(public.crm_num(l -> 'qty'), 1), q.id, q.ref, q.title, q.data ->> 'valid_till', q.status, q.data ->> 'qtitle'
  from public.crm_records q, jsonb_array_elements(coalesce(q.data -> 'lines', '[]'::jsonb)) l, jsonb_array_elements(coalesce(l -> 'proj_items', '[]'::jsonb)) x
  where q.kind = 'quote' and q.deleted_at is null and q.status in ('draft', 'sent', 'accepted') and q.id <> coalesce(p_exclude, 0)
    and (q.data -> 'locked' is not null or not exists (select 1 from jsonb_array_elements(coalesce(q.data -> 'alt', '[]'::jsonb)) z where coalesce(z ->> 'dropped', '') <> 'true'))
    and coalesce(l ->> 'kind', 'product') = 'project' and coalesce(x ->> 'item_id', '') ~ '^[0-9]+$' $function$;

CREATE OR REPLACE FUNCTION public.crm__quote_pub(q crm_records)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d jsonb := q.data; prim text := coalesce(q.data ->> 'opt_id', 'A'); opts jsonb := '[]'::jsonb; x jsonb; lk jsonb := q.data -> 'locked'; po jsonb;
begin
  po := jsonb_build_object('id', prim, 'label', coalesce(d ->> 'opt_label', case when jsonb_array_length(coalesce(d -> 'alt', '[]'::jsonb)) > 0 then 'Option 1' else 'Quotation' end), 'lines', d -> 'lines', 'grand', d -> 'grand', 'kw', d -> 'kw', 'pdf_url', d -> 'pdf_url');
  opts := jsonb_build_array(public.crm__opt_pub(po, d, true, lk is not null));
  if lk is null then
    for x in select * from jsonb_array_elements(coalesce(d -> 'alt', '[]'::jsonb)) loop
      if coalesce(x ->> 'dropped', '') <> 'true' then opts := opts || jsonb_build_array(public.crm__opt_pub(x, d, false, false)); end if;
    end loop;
  end if;
  return jsonb_strip_nulls(jsonb_build_object('ref', q.ref, 'title', d ->> 'qtitle', 'status', q.status, 'valid_till', d ->> 'valid_till', 'opts', opts,
    'est', case when coalesce(d ->> 'ctype', '') in ('Residential', 'Commercial', 'Industrial', 'VFD') and not coalesce(d -> 'wf', '{}'::jsonb) ? '4' and q.status not in ('accepted') then true end,
    'final', case when coalesce(d ->> 'ctype', '') in ('Residential', 'Commercial', 'Industrial', 'VFD') and coalesce(d -> 'wf', '{}'::jsonb) ? '4' then true end,
    'history', (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('t', h ->> 't', 'at', h ->> 'at', 'label', h ->> 'label', 'kw', h ->> 'kw', 'grand', h -> 'grand', 'note', h ->> 'note')) order by ord) from jsonb_array_elements(coalesce(d -> 'history', '[]'::jsonb)) with ordinality t(h, ord) where h ->> 't' in ('quote', 'option', 'change', 'accept')),
    'revs', (select jsonb_agg(jsonb_build_object('at', r ->> 'at', 'before', r -> 'before', 'after', r -> 'after') order by ord) from jsonb_array_elements(coalesce(d -> 'rev', '[]'::jsonb)) with ordinality t(r, ord)),
    'locked', case when lk is not null then jsonb_build_object('label', lk ->> 'label', 'at', lk ->> 'at', 'via', lk ->> 'via') end,
    'reaccept', case when coalesce(d ->> 'reaccept', '') = 'true' then true end,
    'resp', case when d -> 'resp' is not null then jsonb_build_object('change', d #> '{resp,change,at}', 'callback', d #> '{resp,callback,at}') end));
end $function$;


-- Har option ka stock hint (CRM me dikhane ke liye)
create or replace function public.crm_quote_option_stock(p jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; res jsonb := '[]'::jsonb; x jsonb; m text;
begin
  select * into q from public.crm_records where id = (p ->> 'id')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  m := public.crm_quote_shortage(q.data -> 'lines', q.id);
  res := res || jsonb_build_array(jsonb_build_object('id', coalesce(q.data ->> 'opt_id', 'A'), 'short', m));
  for x in select * from jsonb_array_elements(coalesce(q.data -> 'alt', '[]'::jsonb)) a where coalesce(a ->> 'dropped', '') <> 'true' loop
    res := res || jsonb_build_array(jsonb_build_object('id', x ->> 'id', 'short', public.crm_quote_shortage(x -> 'lines', q.id)));
  end loop;
  return res;
end $f$;
grant execute on function public.crm_quote_option_stock(jsonb) to anon, authenticated;

-- Naya quotation rok: band (superseded) purani quotation naye quotation ko nahi rokti; sandesh me Option ka rasta
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
      select * into ex from public.crm_records where kind = 'quote' and deleted_at is null and party_id = new.party_id and id <> coalesce(new.id, 0) and status in ('draft', 'sent', 'rejected', 'expired') and (data -> 'superseded_by') is null order by id desc limit 1;
      if ex.id is not null then raise exception 'Is customer ki quotation % pehle se hai — usi ko edit karein. Doosre brand / rate dikhane hon to usi me ''Option'' jodein. Naya plant tabhi, jab ye confirm ho jaye.', coalesce(ex.ref, '#' || ex.id); end if;
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

-- Option ki copy (naya brand) jab tak rate na badle, customer ko nahi dikhti aur Accept nahi hoti
CREATE OR REPLACE FUNCTION public.crm_quote_option_save(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; o jsonb := coalesce(p -> 'opt', '{}'::jsonb); prim text; oid text; alt jsonb; calc jsonb; e jsonb; n int; found boolean := false; lbl text; newo jsonb; ids text := 'BCDEFGH'; i int;
begin
  perform public.crm_need(s, 'quotes.edit');
  select * into q from public.crm_records where id = (p ->> 'id')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if q.data -> 'locked' is not null then raise exception 'Customer ne final kar diya — ab naya option nahi jud sakta'; end if;
  if q.status not in ('draft', 'sent') then raise exception 'Sirf draft / bheji hui quotation me option jodein'; end if;
  prim := coalesce(q.data ->> 'opt_id', 'A'); alt := coalesce(q.data -> 'alt', '[]'::jsonb); oid := nullif(trim(coalesce(o ->> 'id', '')), '');
  lbl := left(trim(coalesce(o ->> 'label', '')), 60);
  if oid = prim then   -- sirf pehle option ka naam
    if lbl = '' then raise exception 'Option ka naam likhein'; end if;
    update public.crm_records set data = data || jsonb_build_object('opt_label', lbl), updated_at = now() where id = q.id;
  elsif oid is null then   -- naya option: pehle option ki copy
    if lbl = '' then raise exception 'Option ka naam likhein (jaise: Adani 5 kW)'; end if;
    select count(*) into n from jsonb_array_elements(alt) x where coalesce(x ->> 'dropped', '') <> 'true';
    if n >= 4 then raise exception 'Ek quotation me 5 se zyada option nahi'; end if;
    for i in 1..length(ids) loop oid := substr(ids, i, 1); exit when oid <> prim and not exists (select 1 from jsonb_array_elements(alt) x where x ->> 'id' = oid); end loop;
    newo := jsonb_build_object('id', oid, 'label', lbl, 'lines', q.data -> 'lines', 'discount', coalesce(q.data -> 'discount', '0'::jsonb), 'subtotal', q.data -> 'subtotal', 'gst_total', q.data -> 'gst_total', 'grand', q.data -> 'grand', 'qtitle', q.data -> 'qtitle', 'created_at', now());
    if q.data ? 'kw' then newo := newo || jsonb_build_object('kw', q.data -> 'kw'); end if;
    if o ? 'lines' then
      calc := public.crm__opt_guard(s, o -> 'lines', public.crm_num(o -> 'discount'));
      newo := newo || jsonb_build_object('lines', o -> 'lines', 'discount', calc -> 'discount', 'subtotal', calc -> 'subtotal', 'gst_total', calc -> 'gst_total', 'grand', calc -> 'grand', 'qtitle', coalesce(nullif(left(trim(o ->> 'qtitle'), 120), ''), q.data ->> 'qtitle'));
      if nullif(trim(coalesce(o ->> 'kw', '')), '') is not null then newo := newo || jsonb_build_object('kw', trim(o ->> 'kw')); end if;
    end if;
    update public.crm_records set data = data || jsonb_build_object('alt', alt || jsonb_build_array(case when o ? 'lines' then newo else newo || '{"copied":true}'::jsonb end)), updated_at = now() where id = q.id;
  else
    select x into e from jsonb_array_elements(alt) t(x) where x ->> 'id' = oid and coalesce(x ->> 'dropped', '') <> 'true';
    if e is null then raise exception 'Option nahi mila'; end if;
    if lbl = '' then lbl := e ->> 'label'; end if;
    if o ? 'lines' then
      calc := public.crm__opt_guard(s, o -> 'lines', public.crm_num(o -> 'discount'));
      newo := (e - 'pdf_url' - 'copied') || jsonb_build_object('label', lbl, 'lines', o -> 'lines', 'discount', calc -> 'discount', 'subtotal', calc -> 'subtotal', 'gst_total', calc -> 'gst_total', 'grand', calc -> 'grand', 'qtitle', coalesce(nullif(left(trim(o ->> 'qtitle'), 120), ''), e ->> 'qtitle', q.data ->> 'qtitle'));
      if nullif(trim(coalesce(o ->> 'kw', '')), '') is not null then newo := newo || jsonb_build_object('kw', trim(o ->> 'kw')); end if;
    else newo := e || jsonb_build_object('label', lbl); end if;
    update public.crm_records set data = data || jsonb_build_object('alt', (select coalesce(jsonb_agg(case when x ->> 'id' = oid then newo else x end), '[]'::jsonb) from jsonb_array_elements(alt) x)), updated_at = now() where id = q.id;
  end if;
  perform public.crm_log(s, 'option', 'quote', q.id, coalesce(q.ref, '') || ' option: ' || coalesce(lbl, ''));
  select * into q from public.crm_records where id = q.id; return public.crm_row(s, q);
end $function$;
CREATE OR REPLACE FUNCTION public.crm__quote_pub(q crm_records)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d jsonb := q.data; prim text := coalesce(q.data ->> 'opt_id', 'A'); opts jsonb := '[]'::jsonb; x jsonb; lk jsonb := q.data -> 'locked'; po jsonb;
begin
  po := jsonb_build_object('id', prim, 'label', coalesce(d ->> 'opt_label', case when jsonb_array_length(coalesce(d -> 'alt', '[]'::jsonb)) > 0 then 'Option 1' else 'Quotation' end), 'lines', d -> 'lines', 'grand', d -> 'grand', 'kw', d -> 'kw', 'pdf_url', d -> 'pdf_url');
  opts := jsonb_build_array(public.crm__opt_pub(po, d, true, lk is not null));
  if lk is null then
    for x in select * from jsonb_array_elements(coalesce(d -> 'alt', '[]'::jsonb)) loop
      if coalesce(x ->> 'dropped', '') <> 'true' and coalesce(x ->> 'copied', '') <> 'true' then opts := opts || jsonb_build_array(public.crm__opt_pub(x, d, false, false)); end if;
    end loop;
  end if;
  return jsonb_strip_nulls(jsonb_build_object('ref', q.ref, 'title', d ->> 'qtitle', 'status', q.status, 'valid_till', d ->> 'valid_till', 'opts', opts,
    'est', case when coalesce(d ->> 'ctype', '') in ('Residential', 'Commercial', 'Industrial', 'VFD') and not coalesce(d -> 'wf', '{}'::jsonb) ? '4' and q.status not in ('accepted') then true end,
    'final', case when coalesce(d ->> 'ctype', '') in ('Residential', 'Commercial', 'Industrial', 'VFD') and coalesce(d -> 'wf', '{}'::jsonb) ? '4' then true end,
    'history', (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('t', h ->> 't', 'at', h ->> 'at', 'label', h ->> 'label', 'kw', h ->> 'kw', 'grand', h -> 'grand', 'note', h ->> 'note')) order by ord) from jsonb_array_elements(coalesce(d -> 'history', '[]'::jsonb)) with ordinality t(h, ord) where h ->> 't' in ('quote', 'option', 'change', 'accept')),
    'revs', (select jsonb_agg(jsonb_build_object('at', r ->> 'at', 'before', r -> 'before', 'after', r -> 'after') order by ord) from jsonb_array_elements(coalesce(d -> 'rev', '[]'::jsonb)) with ordinality t(r, ord)),
    'locked', case when lk is not null then jsonb_build_object('label', lk ->> 'label', 'at', lk ->> 'at', 'via', lk ->> 'via') end,
    'reaccept', case when coalesce(d ->> 'reaccept', '') = 'true' then true end,
    'resp', case when d -> 'resp' is not null then jsonb_build_object('change', d #> '{resp,change,at}', 'callback', d #> '{resp,callback,at}') end));
end $function$;
CREATE OR REPLACE FUNCTION public.sp_quote_respond(p_token text, p_action text, p_opt text DEFAULT NULL::text, p_last4 text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.sp_shares; q public.crm_records; pa public.crm_records; act text := lower(coalesce(p_action, '')); note text := left(btrim(coalesce(p_note, '')), 300); l4 text := regexp_replace(coalesce(p_last4, ''), '\D', '', 'g');
        prim text; oid text; lbl text; nopt int; last_at timestamptz;
begin
  perform public.sp_share_rate(30);
  select * into r from public.sp_shares where token = btrim(coalesce(p_token, '')) and live and not revoked and expires_at > now();
  if r.id is null then raise exception 'Ye link ab chalu nahi hai'; end if;
  select * into q from public.crm_records where id = r.quote_id and kind = 'quote' and deleted_at is null;
  if q.id is null then raise exception 'Quotation nahi mili'; end if;
  if q.status in ('expired', 'converted', 'rejected') then return jsonb_build_object('error', 'Is quotation par ab jawab nahi ho sakta — kripya humse sampark karein'); end if;
  prim := coalesce(q.data ->> 'opt_id', 'A');
  if act = 'accept' then
    if q.data -> 'locked' is not null and coalesce(q.data ->> 'reaccept', '') <> 'true' then return jsonb_build_object('ok', true, 'already', true, 'quote', public.crm__quote_pub(q)); end if;
    if r.bad_tries >= 5 and r.bad_at > now() - interval '1 day' then return jsonb_build_object('error', 'Kai galat koshish ho chuki — kripya humse sampark karein'); end if;
    select * into pa from public.crm_records where id = q.party_id;
    if length(l4) <> 4 or right(coalesce(pa.mobile, ''), 4) is distinct from l4 then
      update public.sp_shares set bad_tries = case when bad_at > now() - interval '1 day' then bad_tries + 1 else 1 end, bad_at = now() where id = r.id;
      return jsonb_build_object('error', 'Mobile ke aakhri 4 ank match nahi hue');
    end if;
    nopt := 1 + (select count(*) from jsonb_array_elements(coalesce(q.data -> 'alt', '[]'::jsonb)) x where coalesce(x ->> 'dropped', '') <> 'true' and coalesce(x ->> 'copied', '') <> 'true');
    oid := nullif(btrim(coalesce(p_opt, '')), '');
    if q.data -> 'locked' is not null then oid := prim; end if;
    if oid is null and nopt > 1 then return jsonb_build_object('error', 'Pehle ek option chunein'); end if;
    if oid is not null and oid <> prim and not exists (select 1 from jsonb_array_elements(coalesce(q.data -> 'alt', '[]'::jsonb)) x where x ->> 'id' = oid and coalesce(x ->> 'dropped', '') <> 'true' and coalesce(x ->> 'copied', '') <> 'true') then return jsonb_build_object('error', 'Ye option nahi mila'); end if;
    perform public.crm__quote_lock(q.id, oid, 'customer', 'Customer (link)');
    update public.sp_shares set bad_tries = 0 where id = r.id;
    select * into q from public.crm_records where id = q.id;
    update public.crm_records set data = data || jsonb_build_object('resp', coalesce(data -> 'resp', '{}'::jsonb) || jsonb_build_object('accept', jsonb_build_object('at', now(), 'opt', q.data #>> '{locked,opt_id}', 'amount', q.data -> 'grand'))) where id = q.id;
    insert into public.crm_activity(user_id, user_name, role, action, kind, rec_id, summary) values (0, 'Customer (link)', 'customer', 'accept', 'quote', q.id, left(coalesce(q.ref, '') || ' Accept: ' || coalesce(q.data #>> '{locked,label}', ''), 300));
    perform public.crm__quote_remind(q, 'Customer ne Accept kiya — advance ke liye call karein', 'Option: ' || coalesce(q.data #>> '{locked,label}', '') || ' · ' || coalesce(q.data ->> 'grand', ''));
  elsif act = 'change' then
    if length(note) < 3 then return jsonb_build_object('error', 'Kya badlav chahiye, thoda likhein'); end if;
    last_at := nullif(q.data #>> '{resp,change,at}', '')::timestamptz;
    if last_at is null or last_at < now() - interval '5 minutes' then
      update public.crm_records set data = data || jsonb_build_object('resp', coalesce(data -> 'resp', '{}'::jsonb) || jsonb_build_object('change', jsonb_build_object('at', now(), 'note', note))) where id = q.id;
      update public.crm_records set data = public.crm__hist_add(data, jsonb_build_object('t', 'change', 'at', to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS'), 'note', note)) where id = q.id;
      select * into q from public.crm_records where id = q.id;
      insert into public.crm_activity(user_id, user_name, role, action, kind, rec_id, summary) values (0, 'Customer (link)', 'customer', 'change', 'quote', q.id, left(coalesce(q.ref, '') || ' badlav: ' || note, 300));
      perform public.crm__quote_remind(q, 'Customer ko badlav chahiye', note);
    end if;
  elsif act = 'callback' then
    last_at := nullif(q.data #>> '{resp,callback,at}', '')::timestamptz;
    if last_at is null or last_at < now() - interval '30 minutes' then
      update public.crm_records set data = data || jsonb_build_object('resp', coalesce(data -> 'resp', '{}'::jsonb) || jsonb_build_object('callback', jsonb_build_object('at', now()))) where id = q.id;
      select * into q from public.crm_records where id = q.id;
      perform public.crm__quote_remind(q, 'Customer ne call back maanga', note);
    end if;
  else raise exception 'Galat kaam'; end if;
  select * into q from public.crm_records where id = q.id;
  return jsonb_build_object('ok', true, 'quote', public.crm__quote_pub(q));
end $function$;

-- Band (dusri chuni gayi) quotation ka purana link: 'ab chalu nahi' dikhata hai
CREATE OR REPLACE FUNCTION public.sp_share_open(p_token text, p_count boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.sp_shares; q public.crm_records; pub jsonb; amt numeric;
begin
  select * into r from public.sp_shares where token = btrim(coalesce(p_token, ''));
  if r.id is null then return null; end if;
  if r.revoked or r.expires_at <= now() then
    return jsonb_build_object('state', case when r.revoked then 'paused' else 'expired' end, 'kind', r.kind, 'brand', r.brand, 'phone', r.phone);
  end if;
  if r.quote_id is not null and exists (select 1 from public.crm_records z where z.id = r.quote_id and (z.data -> 'superseded_by') is not null) then
    return jsonb_build_object('state', 'closed', 'kind', r.kind, 'brand', r.brand, 'phone', r.phone);
  end if;
  if r.live and r.quote_id is not null then
    select * into q from public.crm_records where id = r.quote_id and kind = 'quote' and deleted_at is null;
    if q.id is null then return jsonb_build_object('state', 'expired', 'kind', r.kind, 'brand', r.brand, 'phone', r.phone); end if;
    pub := public.crm__quote_pub(q);
  end if;
  if p_count then update public.sp_shares set views = views + 1, first_view = coalesce(first_view, now()), last_view = now() where id = r.id; end if;
  if pub is not null then
    amt := case when q.data -> 'locked' is not null or jsonb_array_length(pub -> 'opts') = 1 then public.crm_num(q.data -> 'grand') end;
    return jsonb_build_object('kind', r.kind, 'title', coalesce(nullif(pub ->> 'title', ''), r.title), 'subtitle', r.subtitle, 'amount', amt, 'valid_till', q.data ->> 'valid_till', 'details', '[]'::jsonb,
      'pdf_url', null, 'view_url', null, 'file_name', r.file_name, 'brand', r.brand, 'phone', r.phone, 'created_at', r.created_at, 'live', true, 'quote', pub);
  end if;
  return jsonb_build_object('kind', r.kind, 'title', r.title, 'subtitle', r.subtitle, 'amount', r.amount, 'valid_till', r.valid_till, 'details', r.details,
    'pdf_url', r.pdf_url, 'view_url', r.view_url, 'file_name', r.file_name, 'brand', r.brand, 'phone', r.phone, 'created_at', r.created_at);
end $function$;

-- ===== U26 (Round 56): online order = apne aap Confirmed "Kaam"; flow dedupe; reserve double-hold fix =====
-- Step numbers nahi badle. Purana data waise hi rehta hai. Dobara chalane se koi nuksan nahi.

-- 1) Service flow: "Demo / Files" Conversation ke baad (pehle Finish ke baad tha)
create or replace function public.crm_wf_flow(ct text) returns integer[] language sql immutable as $f$
  select case
    when ct = 'Items only'  then array[19,1,2,14,3,6,20,12,21,22,16,18]
    when ct = 'Service'     then array[19,1,2,14,4,3,6,8,23,12,16,17,18]
    when ct = 'AMC only'        then array[19,1,2,17]
    when ct = 'Site visit only' then array[19,1,2,4]
    when ct = 'Residential' then array[19,1,2,14,3,6,4,5,7,15,8,9,10,11,12,13,16,17,18]
    else                         array[19,1,2,14,3,6,4,5,7,15,8,9,10,11,12,16,17,18] end $f$;

-- 2) Online order ke steps: order se seedha (Conversation / Quotation / Demo = lagu nahi, Confirmation = order, Stock = order ke saath, Dispatch = Store Orders ke dispatch se)
create or replace function public.crm_wf_synth(q public.crm_records) returns jsonb language plpgsql stable security definer set search_path = public as $f$
declare pt public.crm_records; o public.sp_orders; oid bigint; at_ text; e jsonb; res jsonb; dp jsonb; mode_ text; di jsonb;
begin
  if q.party_id is null then return '{}'::jsonb; end if;
  begin
    if q.data ? 'order_id' then oid := nullif(q.data ->> 'order_id', '')::bigint;
    elsif q.id is null then
      select * into pt from public.crm_records where id = q.party_id and kind = 'party';
      if pt.id is not null and coalesce(pt.data ->> 'intake', '') = 'store' then oid := nullif(pt.data ->> 'store_order_id', '')::bigint; end if;
    end if;
  exception when others then oid := null; end;
  if oid is null then return '{}'::jsonb; end if;
  select * into o from public.sp_orders where id = oid;
  if o.id is null or o.status = 'cancelled' then return '{}'::jsonb; end if;
  at_ := to_char(o.created_at at time zone 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS"+05:30"');
  e := jsonb_build_object('at', at_, 'by', 'Online order (system)', 'auto', true, 'skip', true, 'note', 'Online order — lagu nahi');
  res := jsonb_build_object('2', e, '3', e, '14', e,
    '6', jsonb_build_object('at', at_, 'by', 'Online order (system)', 'auto', true, 'note', 'Online order = Confirmed'),
    '20', jsonb_build_object('at', at_, 'by', 'Online order (system)', 'auto', true, 'note', 'Online order ke saath maal alag', 'info', jsonb_build_object('stock_status', 'Online order ke saath alag')));
  if o.status in ('shipped', 'delivered') then
    dp := coalesce(o.data -> 'dispatch', '{}'::jsonb);
    mode_ := case dp ->> 'mode' when 'courier' then 'Courier' when 'self' then 'Khud' when 'pickup' then 'Store se uthaya' else coalesce(nullif(dp ->> 'mode', ''), 'Courier') end;
    di := jsonb_strip_nulls(jsonb_build_object('disp_mode', mode_, 'courier', nullif(dp ->> 'courier', ''), 'tracking_no', nullif(dp ->> 'tracking', ''), 'disp_date', nullif(dp ->> 'disp_date', ''), 'deliv_date', nullif(dp ->> 'deliv_date', '')));
    res := res || jsonb_build_object('21', jsonb_build_object('at', coalesce(nullif(dp ->> 'at', ''), at_), 'by', 'Store Orders (system)', 'auto', true, 'note', 'Store Orders ke dispatch se', 'info', di));
  end if;
  return res;
end $f$;

-- Asli (effective) steps = order wale + jo staff ne khud tick kiye (staff ka tick jeetta hai; sirf 2 / 3 order se hi tay)
create or replace function public.crm_wf_eff(q public.crm_records) returns jsonb language plpgsql stable security definer set search_path = public as $f$
declare s jsonb := public.crm_wf_synth(q); st jsonb := coalesce(q.data -> 'wf', '{}'::jsonb);
begin
  if s = '{}'::jsonb then return st; end if;
  if q.data ? 'order_id' then return (s || st) || jsonb_build_object('2', s -> '2', '3', s -> '3'); end if;
  return s || st;
end $f$;

CREATE OR REPLACE FUNCTION public.crm_wf_steps(s crm_ses, q crm_records)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare names text[] := public.crm_wf_names(); out jsonb := '[]'::jsonb; n int; w jsonb := public.crm_wf_eff(q); st jsonb; v boolean; e boolean;
        priv boolean := public.crm_is_admin(s) or (s).role = 'manager'; pat text; auto boolean;
begin
  foreach n in array public.crm_wf_flow_of(q) loop
    auto := public.crm_wf_is_auto(n);
    if n = 19 then
      select to_char(created_at at time zone 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS"+05:30"') into pat from public.crm_records where id = q.party_id;
      out := out || jsonb_build_array(jsonb_build_object('n', 19, 'name', names[19], 'done', true, 'at', pat, 'auto', true, 'manual', false, 'skip', false, 'locked', false, 'can_edit', false,
        'note', 'Path (kahan se aaya): ' || coalesce(nullif((select data ->> 'source' from public.crm_records where id = q.party_id), ''), 'Purana / Unknown')));
      continue;
    end if;
    st := w -> n::text; v := public.crm_wf_can(s, n, 'view'); e := public.crm_wf_can(s, n, 'edit');
    out := out || jsonb_build_array(jsonb_build_object('n', n, 'name', names[n], 'done', st is not null, 'at', st ->> 'at',
      'auto', coalesce((st ->> 'auto')::boolean, false), 'manual', not auto, 'skip', coalesce((st ->> 'skip')::boolean, false), 'can_skip', public.crm_wf_can_skip(n),
      'locked', not v, 'can_edit', e and not auto and (n <> 13 or priv),
      'by', case when v then st ->> 'by' end, 'note', case when v then st ->> 'note' end, 'info', case when v then coalesce(st -> 'info', '{}'::jsonb) end));
  end loop;
  return out;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_wf_set(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); q public.crm_records; n int := (p ->> 'step')::int; done boolean := coalesce((p ->> 'done')::boolean, true); note text := left(trim(coalesce(p ->> 'note', '')), 500);
        skip boolean := coalesce((p ->> 'skip')::boolean, false); w jsonb; flow int[]; ct text; inf jsonb := '{}'::jsonb; f jsonb; v text; miss text[] := '{}'; entry jsonb; has_info boolean := p ? 'info';
begin
  select * into q from public.crm_records where id = (p ->> 'id')::bigint and kind = 'quote' and deleted_at is null;
  if q.id is null or not public.crm_vis(s, q) then raise exception 'Quotation nahi mili'; end if;
  if n is null or n < 1 or n > 23 then raise exception 'Step galat hai'; end if;
  if public.crm_wf_is_auto(n) then raise exception 'Ye step apne aap hota hai (quotation / bill / lead se)'; end if;
  ct := coalesce(q.data ->> 'ctype', ''); flow := public.crm_wf_flow_of(q);
  if not (n = any (flow)) then
    if n = 13 then raise exception 'Subsidy sirf Residential solar ke liye hai'; end if;
    raise exception 'Ye step is customer ke liye nahi hai (% — %)', case ct when 'Items only' then 'Product customer' when 'Service' then 'Service customer' when 'AMC only' then 'AMC customer' when 'Site visit only' then 'Site visit customer' else 'Project customer' end, (public.crm_wf_names())[n];
  end if;
  if n = 13 and not (public.crm_is_admin(s) or (s).role = 'manager') then raise exception 'Subsidy sirf Admin ya Manager green kar sakte hain'; end if;
  if not public.crm_wf_can(s, n, 'edit') then raise exception 'Is step ko badalne ki permission nahi hai — Admin se allow karwayein'; end if;
  w := public.crm_wf_eff(q);
  if done then
    if n = 7 and not (w ? '6') then raise exception 'Pehle quotation Confirm hona chahiye'; end if;
    if (n in (9, 10, 11, 13) or (n = 8 and ct <> 'Service') or (n = 17 and ct not in ('Service', 'AMC only'))) and not (w ? '7') then raise exception 'Pehle Apply Process confirm karein — tabhi customer Projects me aata hai'; end if;
    if (n in (15, 16, 18, 20, 21, 22, 23) or (n = 8 and ct = 'Service') or (n = 17 and ct = 'Service')) and not (w ? '6') then raise exception 'Pehle quotation Confirm hona chahiye'; end if;
    if skip and not public.crm_wf_can_skip(n) then raise exception 'Ye step "Lagu nahi" nahi kiya ja sakta'; end if;
    if skip then
      entry := jsonb_build_object('at', public.crm_iso_now(), 'by', (s).name, 'by_id', (s).uid, 'note', note, 'skip', true);
    else
      -- keep only the fields this step defines; mandatory ones must be filled (only when the new screen sends "info")
      for f in select * from jsonb_array_elements(coalesce(public.crm_wf_fields() -> n::text, '[]'::jsonb)) loop
        v := left(trim(coalesce(p -> 'info' ->> (f ->> 'k'), '')), 200);
        if v <> '' then inf := inf || jsonb_build_object(f ->> 'k', v);
        elsif has_info and coalesce((f ->> 'req')::boolean, false) then miss := miss || (f ->> 'l'); end if;
      end loop;
      if array_length(miss, 1) > 0 then raise exception 'Ye details bharna zaroori hai: %', array_to_string(miss, ', '); end if;
      entry := jsonb_build_object('at', public.crm_iso_now(), 'by', (s).name, 'by_id', (s).uid, 'note', note) || case when inf = '{}'::jsonb then '{}'::jsonb else jsonb_build_object('info', inf) end;
    end if;
    w := w || jsonb_build_object(n::text, entry);
  else
    if not public.crm_is_admin(s) then raise exception 'Step wapas sirf Admin kar sakta hai'; end if;
    w := w - n::text;
  end if;
  perform set_config('sp.wf', '1', true);
  update public.crm_records set data = data || jsonb_build_object('wf', w), updated_at = now() where id = q.id;
  perform set_config('sp.wf', '', true);
  perform public.crm_log(s, 'workflow', 'quote', q.id, coalesce(q.ref, '') || ' — ' || (public.crm_wf_names())[n] || case when not done then ' ↩' when skip then ' (lagu nahi)' else ' ✔' end);
  select * into q from public.crm_records where id = q.id;
  return public.crm_wf_get(jsonb_build_object('token', p ->> 'token', 'id', q.id));
end $function$;


-- Online order ka auto-Kaam: pata / shahar adhura ho tab bhi ban jaye (baaki jagah niyam waisa hi)
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
      select * into ex from public.crm_records where kind = 'quote' and deleted_at is null and party_id = new.party_id and id <> coalesce(new.id, 0) and status in ('draft', 'sent', 'rejected', 'expired') and (data -> 'superseded_by') is null order by id desc limit 1;
      if ex.id is not null then raise exception 'Is customer ki quotation % pehle se hai — usi ko edit karein. Doosre brand / rate dikhane hon to usi me ''Option'' jodein. Naya plant tabhi, jab ye confirm ho jaye.', coalesce(ex.ref, '#' || ex.id); end if;
    end if;
    -- mandatory customer details before the quotation is sent / confirmed
    if new.status in ('sent', 'accepted') and coalesce(current_setting('sp.order_job', true), '') <> '1' and (TG_OP = 'INSERT' or old.status is distinct from new.status or coalesce(old.data ->> 'ctype', '') <> ct or coalesce(old.data ->> 'kw', '') <> coalesce(d ->> 'kw', '')) then
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


-- 3) Online order aate hi customer ke andar ek Confirmed "Kaam" (quotation) apne aap — Store Orders ke hisaab se
create or replace function public.crm__order_job(p_oid bigint, p_pid bigint) returns bigint language plpgsql security definer set search_path = public as $f$
declare o public.sp_orders; i jsonb; c public.crm_records; lines jsonb := '[]'::jsonb; ln jsonb; qty numeric; proj public.crm_records; ct text; d jsonb; calc jsonb; qid bigint; pt public.crm_records; nm text;
begin
  select * into o from public.sp_orders where id = p_oid;
  if o.id is null or o.status = 'cancelled' or p_pid is null then return null; end if;
  if exists (select 1 from public.crm_records where kind = 'quote' and deleted_at is null and (data ->> 'order_id') = p_oid::text) then return null; end if;
  select * into pt from public.crm_records where id = p_pid and kind = 'party';
  if pt.id is null then return null; end if;
  for i in select * from jsonb_array_elements(case when jsonb_typeof(o.data -> 'items') = 'array' then o.data -> 'items' else '[]'::jsonb end) loop
    select * into c from public.crm_records x where x.kind = 'item' and x.deleted_at is null and (x.data #>> '{store,store_id}') = (i ->> 'id') order by x.id limit 1;
    if c.id is null then return null; end if;   -- item Inventory se juda nahi: Store Orders se "Quotation banayein" button chalega
    qty := greatest(public.crm_num(i -> 'qty'), 1);
    if c.data ->> 'type' = 'project' then
      proj := coalesce(proj, c);
      ln := jsonb_strip_nulls(jsonb_build_object('kind', 'project', 'item_id', c.id, 'name', c.title, 'qty', qty, 'unit', 'Set', 'price', public.crm_num(i -> 'price'), 'gst', public.crm_num(i -> 'gst'),
              'kw', nullif(c.data ->> 'kw', ''), 'proj_items', c.data -> 'proj_items'));
    else
      ln := jsonb_strip_nulls(jsonb_build_object('kind', 'product', 'item_id', c.id, 'name', c.title, 'qty', qty, 'unit', coalesce(nullif(c.data ->> 'unit', ''), 'Pc'), 'price', public.crm_num(i -> 'price'), 'gst', public.crm_num(i -> 'gst')));
    end if;
    lines := lines || jsonb_build_array(ln);
  end loop;
  if jsonb_array_length(lines) = 0 then return null; end if;
  ct := case when proj.id is null then 'Items only' when proj.data ->> 'category' in ('Residential', 'Commercial', 'Industrial') then proj.data ->> 'category' when proj.data ->> 'category' like 'VFD%' then 'VFD' else 'Residential' end;
  nm := coalesce(o.data ->> 'order_no', '#' || o.id);
  d := jsonb_strip_nulls(jsonb_build_object('ctype', ct, 'qtitle', 'Online order ' || nm, 'lines', lines, 'order_id', o.id, 'order_no', nm, 'online', true,
         'kw', case when proj.id is not null then nullif(proj.data ->> 'kw', '') end, 'valid_till', (public.crm_today() + 15)::text, 'date', public.crm_today()::text));
  calc := public.crm_doc_calc(d);
  d := d || calc;
  perform set_config('sp.order_job', '1', true);
  insert into public.crm_records(kind, ref, title, mobile, status, owner_id, party_id, amount, data, search, created_by)
    values ('quote', public.crm_next_no('quote'), pt.title, nullif(pt.mobile, ''), 'accepted', coalesce(pt.owner_id, 0), pt.id, public.crm_num(calc -> 'grand'), d,
            lower(concat_ws(' ', pt.title, pt.mobile, nm, 'online order')), 0)
    returning id into qid;
  perform set_config('sp.order_job', '', true);
  return qid;
end $f$;
revoke all on function public.crm__order_job(bigint, bigint) from public, anon, authenticated;

create or replace function public.crm_order_customer_trg() returns trigger language plpgsql security definer set search_path = public as $f$
declare pid bigint;
begin
  begin pid := public.crm_order_customer(new.data, new.id); exception when others then pid := null; end;
  if pid is not null then begin perform public.crm__order_job(new.id, pid); exception when others then null; end; end if;
  return new;
end $f$;

CREATE OR REPLACE FUNCTION public.sp_orders_online_trg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record;
begin
  if new.status is distinct from old.status then
    for r in select distinct c.id from jsonb_array_elements(case when jsonb_typeof(new.data -> 'items') = 'array' then new.data -> 'items' else '[]'::jsonb end) i
              join public.crm_records c on c.kind = 'item' and c.deleted_at is null and (c.data #>> '{store,store_id}') = (i ->> 'id') and c.data #> '{store,online}' is not null loop
      perform public.crm_online_sync(r.id);
    end loop;
  end if;
  -- Round 56: order cancel = uska auto-Kaam hat jata hai (bill na bana ho to); cancel wapas = Kaam wapas
  if new.status is distinct from old.status then
    if new.status = 'cancelled' then
      update public.crm_records set deleted_at = now(), updated_at = now() where kind = 'quote' and deleted_at is null and status = 'accepted' and (data ->> 'order_id') = new.id::text;
    elsif old.status = 'cancelled' then
      begin perform public.crm__order_job(new.id, public.crm_order_customer(new.data, new.id)); exception when others then null; end;
    end if;
  end if;
  return new;
end $function$;

-- 4) Online order se bana Kaam stock dobara reserve nahi karta (order apna hold khud rakhta hai)
CREATE OR REPLACE FUNCTION public.crm_reserves(p_exclude bigint DEFAULT NULL::bigint)
 RETURNS TABLE(item_id bigint, qty numeric, quote_id bigint, ref text, customer text, valid_till text, qstatus text, qtitle text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select (l ->> 'item_id')::bigint, public.crm_num(l -> 'qty'), q.id, q.ref, q.title, q.data ->> 'valid_till', q.status, q.data ->> 'qtitle'
  from public.crm_records q, jsonb_array_elements(coalesce(q.data -> 'lines', '[]'::jsonb)) l
  where q.kind = 'quote' and q.deleted_at is null and q.status in ('draft', 'sent', 'accepted') and q.id <> coalesce(p_exclude, 0)
    and (q.data ->> 'order_id') is null
    and (q.data -> 'locked' is not null or not exists (select 1 from jsonb_array_elements(coalesce(q.data -> 'alt', '[]'::jsonb)) z where coalesce(z ->> 'dropped', '') <> 'true'))
    and coalesce(l ->> 'kind', 'product') <> 'project' and coalesce(l ->> 'item_id', '') ~ '^[0-9]+$'
  union all
  select (x ->> 'item_id')::bigint, public.crm_num(x -> 'qty') * greatest(public.crm_num(l -> 'qty'), 1), q.id, q.ref, q.title, q.data ->> 'valid_till', q.status, q.data ->> 'qtitle'
  from public.crm_records q, jsonb_array_elements(coalesce(q.data -> 'lines', '[]'::jsonb)) l, jsonb_array_elements(coalesce(l -> 'proj_items', '[]'::jsonb)) x
  where q.kind = 'quote' and q.deleted_at is null and q.status in ('draft', 'sent', 'accepted') and q.id <> coalesce(p_exclude, 0)
    and (q.data ->> 'order_id') is null
    and (q.data -> 'locked' is not null or not exists (select 1 from jsonb_array_elements(coalesce(q.data -> 'alt', '[]'::jsonb)) z where coalesce(z ->> 'dropped', '') <> 'true'))
    and coalesce(l ->> 'kind', 'product') = 'project' and coalesce(x ->> 'item_id', '') ~ '^[0-9]+$' $function$;

-- 5) Store Orders me us order ka Kaam (job) dikhane ke liye
CREATE OR REPLACE FUNCTION public.crm_orders(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.crm_ses := public.crm_session(p ->> 'token'); k text := p ->> 'kind'; st text := nullif(p ->> 'status', '');
begin
  perform public.crm_need(s, 'orders.view');
  if k = 'orders' then
    return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'created_at', created_at, 'status', status, 'data', data, 'job_id', (select z.id from public.crm_records z where z.kind = 'quote' and z.deleted_at is null and (z.data ->> 'order_id') = o.id::text order by z.id limit 1), 'party_id', (select z.party_id from public.crm_records z where z.kind = 'quote' and z.deleted_at is null and (z.data ->> 'order_id') = o.id::text order by z.id limit 1)) order by id desc) from (select * from public.sp_orders where st is null or status = st order by id desc limit 500) o), '[]'::jsonb);
  elsif k = 'enquiries' then
    return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'created_at', created_at, 'status', status, 'data', data) order by id desc) from (select * from public.sp_enquiries where st is null or status = st order by id desc limit 500) o), '[]'::jsonb);
  end if;
  raise exception 'Galat list';
end $function$;

-- 6) Ek hi option wali quotation ka final label 'Quotation' (pehle 'Option A' dikhta tha)
CREATE OR REPLACE FUNCTION public.crm__quote_lock(qid bigint, optid text, via text, who text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare q public.crm_records; d jsonb; prim text; o jsonb; e jsonb; na jsonb := '[]'::jsonb; xe jsonb;
begin
  select * into q from public.crm_records where id = qid and kind = 'quote' and deleted_at is null for update;
  if q.id is null then raise exception 'Quotation nahi mili'; end if;
  d := q.data; prim := coalesce(d ->> 'opt_id', 'A'); optid := coalesce(nullif(optid, ''), prim);
  if optid <> prim then
    select x into o from jsonb_array_elements(coalesce(d -> 'alt', '[]'::jsonb)) t(x) where x ->> 'id' = optid and coalesce(x ->> 'dropped', '') <> 'true';
    if o is null then raise exception 'Ye option nahi mila'; end if;
    e := jsonb_build_object('id', prim, 'label', coalesce(d ->> 'opt_label', 'Option ' || prim), 'lines', d -> 'lines', 'discount', coalesce(d -> 'discount', '0'::jsonb), 'subtotal', d -> 'subtotal', 'gst_total', d -> 'gst_total', 'grand', d -> 'grand', 'qtitle', d -> 'qtitle', 'dropped', true);
    if d ? 'kw' then e := e || jsonb_build_object('kw', d -> 'kw'); end if;
    if d ? 'pdf_url' then e := e || jsonb_build_object('pdf_url', d -> 'pdf_url'); end if;
    na := jsonb_build_array(e);
    for xe in select * from jsonb_array_elements(coalesce(d -> 'alt', '[]'::jsonb)) loop if xe ->> 'id' <> optid then na := na || jsonb_build_array(xe || '{"dropped":true}'::jsonb); end if; end loop;
    d := (d - 'kw' - 'pdf_url') || jsonb_build_object('lines', o -> 'lines', 'discount', coalesce(o -> 'discount', '0'::jsonb), 'subtotal', o -> 'subtotal', 'gst_total', o -> 'gst_total', 'grand', o -> 'grand',
          'qtitle', coalesce(o ->> 'qtitle', d ->> 'qtitle'), 'opt_id', optid, 'opt_label', o ->> 'label', 'alt', na);
    if o ? 'kw' then d := d || jsonb_build_object('kw', o -> 'kw'); end if;
    if o ? 'pdf_url' then d := d || jsonb_build_object('pdf_url', o -> 'pdf_url'); end if;
  else
    for xe in select * from jsonb_array_elements(coalesce(d -> 'alt', '[]'::jsonb)) loop na := na || jsonb_build_array(xe || '{"dropped":true}'::jsonb); end loop;
    d := d || jsonb_build_object('alt', na);
  end if;
  d := (d - 'reaccept') || jsonb_build_object('locked', jsonb_build_object('opt_id', coalesce(d ->> 'opt_id', prim), 'label', coalesce(d ->> 'opt_label', case when jsonb_array_length(coalesce(d -> 'alt', '[]'::jsonb)) > 0 then 'Option ' || coalesce(d ->> 'opt_id', prim) else 'Quotation' end), 'at', now(), 'by', left(who, 80), 'via', via));
  update public.crm_records set data = d, status = 'accepted', amount = public.crm_num(d -> 'grand'), updated_at = now() where id = q.id;
  perform public.crm__quote_supersede(q.id);
end $function$;


-- 7) Pehle ke khule (new / confirmed / paid / shipped) online orders ka bhi Kaam bana do (ek baar; dobara chalane par double nahi banta)
do $b$
declare r record;
begin
  for r in select id, data from public.sp_orders where status in ('new', 'confirmed', 'paid', 'shipped') order by id loop
    begin perform public.crm__order_job(r.id, public.crm_order_customer(r.data, r.id)); exception when others then null; end;
  end loop;
end $b$;

-- ===== U27 (Round 57): customer link par "Payment kaise karein" — QR + company account + (optional) link, sab sirf company Settings se =====
-- Staff koi alag account nahi bhej sakta; jo bhi account/UPI badle uska Activity log me record rehta hai. Purana data waise hi rehta hai. Dobara chalane se koi nuksan nahi.

-- 1) Payment dabba: sirf company Settings (Bank / UPI) se banta hai. Bill = poori / ab tak mili / baaki rakam; quotation = accept ke baad. QR me rakam locked nahi (pehle payment par koi limit nahi)
create or replace function public.crm__pay_box(r public.sp_shares, q public.crm_records) returns jsonb language plpgsql stable security definer set search_path = public as $f$
declare co jsonb; upi text; acc text; lnk text; inv public.crm_records; tot numeric; rest_ numeric; ref_ text; nm text;
begin
  select data -> 'company' into co from public.crm_settings where id = 1;
  co := coalesce(co, '{}'::jsonb);
  if coalesce(co ->> 'pay_box', '1') = '0' then return null; end if;
  upi := btrim(coalesce(co ->> 'upi', ''));
  if upi !~ '^[A-Za-z0-9._-]{2,64}@[A-Za-z0-9.-]{2,32}$' then upi := ''; end if;
  acc := btrim(coalesce(co ->> 'bank_acc', ''));
  lnk := btrim(coalesce(co ->> 'pay_link', ''));
  if lnk !~ '^https://[^[:space:]<>"'']{4,255}$' then lnk := ''; end if;
  if upi = '' and acc = '' and lnk = '' then return null; end if;
  if q.id is not null then
    -- live quotation: payment sirf customer ke Accept (lock) ke baad. Pehle payment par koi limit nahi (customer jitna chahe de) — QR me rakam locked nahi
    if q.data -> 'locked' is null or q.status in ('rejected', 'expired', 'draft') then return null; end if;
    tot := public.crm_num(q.data -> 'grand'); rest_ := tot; ref_ := q.ref;
  elsif r.kind = 'bill' and coalesce(r.ref, '') ~ '^rec:[0-9]+$' then
    select * into inv from public.crm_records where id = substr(r.ref, 5)::bigint and kind = 'invoice' and deleted_at is null;
    if inv.id is null or coalesce(inv.data ->> 'cancelled', '') in ('true', '1') then return null; end if;
    tot := public.crm_num(inv.data -> 'grand'); rest_ := public.crm_num(coalesce(inv.data -> 'balance', inv.data -> 'grand'));
    if rest_ <= 0 then return jsonb_build_object('paid', true); end if;
    ref_ := inv.ref;
  else
    return null;
  end if;
  nm := coalesce(nullif(btrim(co ->> 'bank_holder'), ''), nullif(btrim(co ->> 'legal'), ''), nullif(btrim(co ->> 'name'), ''), 'Sunpowers');
  return jsonb_strip_nulls(jsonb_build_object('upi', nullif(upi, ''), 'payee', nm, 'total', case when tot > 0 then tot end, 'paid', case when tot > rest_ then tot - rest_ end, 'rest', case when rest_ > 0 then rest_ end, 'ref', ref_, 'link', nullif(lnk, ''),
    'bank', case when acc <> '' then jsonb_strip_nulls(jsonb_build_object('holder', nullif(btrim(co ->> 'bank_holder'), ''), 'name', nullif(btrim(co ->> 'bank_name'), ''), 'acc', acc, 'ifsc', nullif(upper(btrim(co ->> 'bank_ifsc')), ''))) end));
end $f$;
revoke all on function public.crm__pay_box(public.sp_shares, public.crm_records) from public, anon, authenticated;

-- 2) link kholne par wahi dabba saath me aata hai
create or replace function public.sp_share_open(p_token text, p_count boolean default false) returns jsonb language plpgsql security definer set search_path = public as $f$
declare r public.sp_shares; q public.crm_records; pub jsonb; amt numeric; pay jsonb;
begin
  select * into r from public.sp_shares where token = btrim(coalesce(p_token, ''));
  if r.id is null then return null; end if;
  if r.revoked or r.expires_at <= now() then
    return jsonb_build_object('state', case when r.revoked then 'paused' else 'expired' end, 'kind', r.kind, 'brand', r.brand, 'phone', r.phone);
  end if;
  if r.live and r.quote_id is not null then
    select * into q from public.crm_records where id = r.quote_id and kind = 'quote' and deleted_at is null;
    if q.id is null then return jsonb_build_object('state', 'expired', 'kind', r.kind, 'brand', r.brand, 'phone', r.phone); end if;
    pub := public.crm__quote_pub(q);
  end if;
  if p_count then update public.sp_shares set views = views + 1, first_view = coalesce(first_view, now()), last_view = now() where id = r.id; end if;
  begin pay := public.crm__pay_box(r, q); exception when others then pay := null; end;
  if pub is not null then
    amt := case when q.data -> 'locked' is not null or jsonb_array_length(pub -> 'opts') = 1 then public.crm_num(q.data -> 'grand') end;
    return jsonb_strip_nulls(jsonb_build_object('kind', r.kind, 'title', coalesce(nullif(pub ->> 'title', ''), r.title), 'subtitle', r.subtitle, 'amount', amt, 'valid_till', q.data ->> 'valid_till', 'details', '[]'::jsonb,
      'pdf_url', null, 'view_url', null, 'file_name', r.file_name, 'brand', r.brand, 'phone', r.phone, 'created_at', r.created_at, 'live', true, 'quote', pub, 'pay', pay));
  end if;
  return jsonb_strip_nulls(jsonb_build_object('kind', r.kind, 'title', r.title, 'subtitle', r.subtitle, 'amount', r.amount, 'valid_till', r.valid_till, 'details', r.details,
    'pdf_url', r.pdf_url, 'view_url', r.view_url, 'file_name', r.file_name, 'brand', r.brand, 'phone', r.phone, 'created_at', r.created_at, 'pay', pay));
end $f$;
grant execute on function public.sp_share_open(text, boolean) to anon, authenticated;

-- 3) Settings save: Bank / UPI / Payment link badle to Activity log me likha jaye (kisne, kya)
create or replace function public.crm_settings_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); d jsonb := p -> 'data'; oc jsonb; k text; chg text := '';
begin
  perform public.crm_need(s, 'settings.manage');
  if jsonb_typeof(d) <> 'object' or length(d::text) > 400000 then raise exception 'Data galat hai'; end if;
  select data -> 'company' into oc from public.crm_settings where id = 1;
  foreach k in array array['bank_holder', 'bank_name', 'bank_acc', 'bank_ifsc', 'upi', 'pay_link', 'pay_box'] loop
    if coalesce(oc ->> k, '') is distinct from coalesce(d #>> array['company', k], '') then chg := chg || (case when chg = '' then '' else ', ' end) || k; end if;
  end loop;
  update public.crm_settings set data = (d - 'secrets' - 'auth') || jsonb_build_object('auth', coalesce(data -> 'auth', '{}'::jsonb)),
    secrets = case when d ? 'secrets' and jsonb_typeof(d -> 'secrets') = 'object' then ((d -> 'secrets') - 'resend_api_key' - 'conn') || jsonb_strip_nulls(jsonb_build_object('resend_api_key', secrets -> 'resend_api_key', 'conn', secrets -> 'conn')) else secrets end,
    updated_at = now() where id = 1;
  perform public.crm_log(s, 'settings', null, null, 'Company settings badli');
  if chg <> '' then perform public.crm_log(s, 'settings', null, null, 'PAYMENT DETAILS badli: ' || chg); end if;
  return jsonb_build_object('ok', true);
end $f$;

-- 4) Customer ko "Advance" shabd nahi: reminder ka text "Bill amount / pehla payment"
do $do$ declare fn oid; src text;
begin
  for fn in select p.oid from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and pg_get_functiondef(p.oid) like '%advance ke liye call karein%' loop
    src := replace(pg_get_functiondef(fn), 'advance ke liye call karein', 'bill amount (pehla payment) ke liye call karein');
    execute src;
  end loop;
end $do$;

-- ===== U28 (Round 58): ORDER / ACCEPT se pehle customer se Disclaimer (Terms) bharwana — Online + Offline link =====
-- Teen jagah: (1) Online Store + Website checkout (order se pehle tick zaroori, server bhi mana karta hai), (2) manual quotation link ka Accept,
-- (3) staff manual Accept par chetavni + record. Text Settings se badal sakte hain; khali ho to neeche ka default. Dobara chalane se koi nuksan nahi.

-- 1) Disclaimer ka text: kinds = 'product' (warranty manufacturer ki) , 'install' (chhat drilling, anadhikrit vyakti, site safety)
create or replace function public.crm__terms_pack(kinds text[]) returns jsonb language plpgsql stable security definer set search_path = public as $f$
declare co jsonb; k text; items jsonb := '[]'::jsonb; pts jsonb; ttl jsonb; ov text; line text;
begin
  select data -> 'company' into co from public.crm_settings where id = 1; co := coalesce(co, '{}'::jsonb);
  foreach k in array coalesce(kinds, '{}'::text[]) loop
    if k not in ('product', 'install') then continue; end if;
    ov := btrim(coalesce(co ->> ('terms_' || k), ''));
    if ov <> '' then
      pts := '[]'::jsonb;
      foreach line in array regexp_split_to_array(ov, E'\\r?\\n') loop
        if btrim(line) <> '' then pts := pts || jsonb_build_array(jsonb_build_object('h', left(btrim(line), 600), 'e', left(btrim(line), 600))); end if;
      end loop;
    elsif k = 'product' then
      pts := jsonb_build_array(
        jsonb_build_object('h', 'प्रोडक्ट की वारंटी / गारंटी / सर्विस सिर्फ़ उस प्रोडक्ट की निर्माता (मैन्युफैक्चरिंग) कंपनी की ज़िम्मेदारी है। Sunpowers सिर्फ़ विक्रेता / सप्लायर है; वारंटी या मैन्युफैक्चरिंग डिफ़ेक्ट की ज़िम्मेदारी Sunpowers की नहीं होगी। क्लेम के लिए निर्माता के अधिकृत सर्विस सेंटर से संपर्क करना होगा (Sunpowers सहायता करेगा)।',
          'e', 'Warranty / guarantee / service of a product is the responsibility of its manufacturer only. Sunpowers is only the seller / supplier and is not responsible for warranty or manufacturing defects. Claims go through the manufacturer''s authorised service centre (Sunpowers will assist).'),
        jsonb_build_object('h', 'वारंटी तभी मान्य होगी जब प्रोडक्ट निर्माता की शर्तों के अनुसार लगाया और चलाया गया हो। ग़लत इस्तेमाल, पानी, बिजली के झटके (surge) या छेड़छाड़ पर वारंटी लागू नहीं होती।',
          'e', 'Warranty applies only if the product is installed and used as per the manufacturer''s conditions. Misuse, water damage, power surge or tampering voids it.'),
        jsonb_build_object('h', 'डिलीवरी के समय पैकिंग / प्रोडक्ट जाँच लें और कमी हो तो तुरंत बताएँ। भुगतान, रिफ़ंड, शिपिंग और Terms पेज की शर्तें भी लागू हैं।',
          'e', 'Please check the packing / product at delivery and report any issue immediately. The Payment, Refund, Shipping and Terms pages also apply.'));
    else
      pts := jsonb_build_array(
        jsonb_build_object('h', 'इंस्टॉलेशन के दौरान Sunpowers के टेक्नीशियन मानक (standard) टूल्स और पूरी सावधानी / प्रिकॉशन के साथ काम करते हैं। छत में ड्रिल / छेद करना इंस्टॉलेशन का ज़रूरी हिस्सा है।',
          'e', 'Sunpowers technicians work with standard tools and full precautions. Drilling holes in the roof is a necessary part of installation.'),
        jsonb_build_object('h', 'छत की क्वालिटी / हालत (पुरानी या कमज़ोर छत, पतला स्लैब, दरार, सीलन, अंदर छिपे पाइप / सरिया / वायरिंग) पर ड्रिलिंग का नतीजा निर्भर करता है। अगर छेद आर-पार हो जाए, दरार, सीलन, लीकेज या कोई और नुकसान हो, तो यह छत की स्थिति पर निर्भर है और इसकी ज़िम्मेदारी Sunpowers की नहीं होगी। छत की किसी पुरानी कमज़ोरी की जानकारी ग्राहक काम से पहले टेक्नीशियन को देगा।',
          'e', 'The result of drilling depends on the quality / condition of your roof (old or weak roof, thin slab, cracks, dampness, hidden pipes / rods / wiring). If a hole goes through, or cracks, seepage, leakage or other damage occurs, it depends on the roof condition and Sunpowers is not responsible. The customer will tell the technician about any known weakness before work starts.'),
        jsonb_build_object('h', 'इंस्टॉलेशन एरिया / छत पर सिर्फ़ Sunpowers के टेक्नीशियन रहेंगे। ग्राहक, परिवार के सदस्य, बच्चे, पड़ोसी या कोई भी अनधिकृत (unauthorised) व्यक्ति इंस्टॉलेशन के दौरान वहाँ नहीं जाएगा — यह प्रतिबंधित है। ऐसा होने पर बिजली का झटका, गिरना, चोट या कोई भी दुर्घटना हो तो उसकी ज़िम्मेदारी ग्राहक की होगी, Sunpowers की नहीं।',
          'e', 'Only Sunpowers technicians may be in the installation area / on the roof. The customer, family members, children, neighbours or any unauthorised person must not go there during installation — it is prohibited. If an electric shock, fall, injury or any accident happens in that case, the customer is responsible, not Sunpowers.'),
        jsonb_build_object('h', 'ग्राहक छत तक सुरक्षित पहुँच, ज़रूरत पर बिजली बंद / चालू करने की अनुमति और काम के लिए जगह उपलब्ध कराएगा। काम के दौरान पैनल, इन्वर्टर या वायर को हाथ नहीं लगाएगा।',
          'e', 'The customer will provide safe access to the roof, permission to switch power off / on when needed, and space to work. Do not touch panels, inverter or wires during work.'),
        jsonb_build_object('h', 'सब्सिडी, नेट मीटरिंग और अप्रूवल DISCOM / सरकार के नियम और समय पर निर्भर हैं; इनकी गारंटी नहीं है। मौसम या DISCOM की वजह से देरी Sunpowers के नियंत्रण से बाहर है।',
          'e', 'Subsidy, net metering and approvals depend on DISCOM / government rules and timelines and are not guaranteed. Delays due to weather or DISCOM are outside Sunpowers'' control.'));
    end if;
    ttl := case k when 'product' then jsonb_build_object('h', 'प्रोडक्ट — वारंटी और ज़िम्मेदारी', 'e', 'Product — warranty and responsibility') else jsonb_build_object('h', 'इंस्टॉलेशन — छत और साइट की सुरक्षा', 'e', 'Installation — roof and site safety') end;
    items := items || jsonb_build_array(jsonb_build_object('k', k, 'title', ttl, 'points', pts));
  end loop;
  if jsonb_array_length(items) = 0 then return null; end if;
  return jsonb_build_object('ver', left(md5(items::text), 8), 'items', items);
end $f$;
revoke all on function public.crm__terms_pack(text[]) from public, anon, authenticated;

-- 2) Online Store / Website checkout isse text lete hain
create or replace function public.sp_terms(p_kinds jsonb default '["product"]'::jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $f$
begin
  if jsonb_typeof(p_kinds) <> 'array' then return null; end if;
  return public.crm__terms_pack(array(select jsonb_array_elements_text(p_kinds)));
end $f$;
grant execute on function public.sp_terms(jsonb) to anon, authenticated;

-- 3) quotation ke liye kaun se disclaimer (ctype se)
create or replace function public.crm__terms_for(q public.crm_records) returns jsonb language plpgsql stable security definer set search_path = public as $f$
declare ct text := coalesce(q.data ->> 'ctype', '');
begin
  if q.id is null then return null; end if;
  return public.crm__terms_pack(case when ct = 'Items only' then array['product'] when ct = 'Service' then array['install'] when ct in ('AMC only', 'Site visit only') then array[]::text[] else array['product', 'install'] end);
end $f$;
revoke all on function public.crm__terms_for(public.crm_records) from public, anon, authenticated;

-- 4) Online order: tick ke bina order nahi; kaun sa version / kab maana — order me record
do $do$ declare src text;
begin
  src := pg_get_functiondef('public.sp_place_order(jsonb)'::regprocedure);
  if position('terms_ok' in src) = 0 then
    src := replace(src, '  perform public.sp_pin_guard(', E'  if coalesce(p_order ->> ''terms_ok'', '''') <> ''true'' then raise exception ''Order se pehle Disclaimer padhkar sahmati (tick) dein''; end if;\n  perform public.sp_pin_guard(');
    src := replace(src, E'  o := (o - ''install'') ||', E'  if jsonb_array_length(inst) > 0 and not (coalesce(p_order -> ''terms_kinds'', ''[]''::jsonb) ? ''install'') then raise exception ''Installation ke Disclaimer par sahmati dein''; end if;\n  o := o || jsonb_build_object(''terms'', jsonb_build_object(''ver'', left(coalesce(p_order ->> ''terms_ver'', ''''), 16), ''kinds'', coalesce(p_order -> ''terms_kinds'', ''[]''::jsonb), ''at'', now()));\n  o := (o - ''install'') ||');
    execute src;
  end if;
end $do$;

-- 5) Manual quotation link: Accept se pehle disclaimer (server bhi rokta hai). Purana function core ban jata hai, bahar se band.
do $do$ begin
  if to_regprocedure('public.sp_quote_respond_core(text,text,text,text,text)') is null then
    alter function public.sp_quote_respond(text, text, text, text, text) rename to sp_quote_respond_core;
  end if;
end $do$;
revoke all on function public.sp_quote_respond_core(text, text, text, text, text) from public, anon, authenticated;

create or replace function public.sp_quote_respond(p_token text, p_action text, p_opt text default null, p_last4 text default null, p_note text default null, p_terms text default null) returns jsonb
language plpgsql security definer set search_path = public as $f$
declare r public.sp_shares; q public.crm_records; tp jsonb; res jsonb;
begin
  if lower(coalesce(p_action, '')) = 'accept' then
    select * into r from public.sp_shares where token = btrim(coalesce(p_token, ''));
    if r.id is not null and r.quote_id is not null then
      select * into q from public.crm_records where id = r.quote_id and kind = 'quote' and deleted_at is null;
      tp := public.crm__terms_for(q);
      if tp is not null and coalesce(p_terms, '') <> tp ->> 'ver' then raise exception 'Accept se pehle Disclaimer padhkar sahmati (tick) dein'; end if;
    end if;
  end if;
  perform set_config('sp.link_accept', '1', true);
  res := public.sp_quote_respond_core(p_token, p_action, p_opt, p_last4, p_note);
  if lower(coalesce(p_action, '')) = 'accept' and tp is not null and q.id is not null and not (res ? 'error') then
    update public.crm_records set data = data || jsonb_build_object('terms_ok', jsonb_build_object('ver', tp ->> 'ver', 'at', now(), 'via', 'link', 'kinds', (select jsonb_agg(i ->> 'k') from jsonb_array_elements(tp -> 'items') i))) where id = q.id;
  end if;
  return res;
end $f$;
grant execute on function public.sp_quote_respond(text, text, text, text, text, text) to anon, authenticated;

-- 6) link kholne par disclaimer bhi aata hai (sirf jab Accept ho sakta hai)
create or replace function public.sp_share_open(p_token text, p_count boolean default false) returns jsonb language plpgsql security definer set search_path = public as $f$
declare r public.sp_shares; q public.crm_records; pub jsonb; amt numeric; pay jsonb; tp jsonb;
begin
  select * into r from public.sp_shares where token = btrim(coalesce(p_token, ''));
  if r.id is null then return null; end if;
  if r.revoked or r.expires_at <= now() then
    return jsonb_build_object('state', case when r.revoked then 'paused' else 'expired' end, 'kind', r.kind, 'brand', r.brand, 'phone', r.phone);
  end if;
  if r.live and r.quote_id is not null then
    select * into q from public.crm_records where id = r.quote_id and kind = 'quote' and deleted_at is null;
    if q.id is null then return jsonb_build_object('state', 'expired', 'kind', r.kind, 'brand', r.brand, 'phone', r.phone); end if;
    pub := public.crm__quote_pub(q);
    begin tp := public.crm__terms_for(q); exception when others then tp := null; end;
  end if;
  if p_count then update public.sp_shares set views = views + 1, first_view = coalesce(first_view, now()), last_view = now() where id = r.id; end if;
  begin pay := public.crm__pay_box(r, q); exception when others then pay := null; end;
  if pub is not null then
    amt := case when q.data -> 'locked' is not null or jsonb_array_length(pub -> 'opts') = 1 then public.crm_num(q.data -> 'grand') end;
    return jsonb_strip_nulls(jsonb_build_object('kind', r.kind, 'title', coalesce(nullif(pub ->> 'title', ''), r.title), 'subtitle', r.subtitle, 'amount', amt, 'valid_till', q.data ->> 'valid_till', 'details', '[]'::jsonb,
      'pdf_url', null, 'view_url', null, 'file_name', r.file_name, 'brand', r.brand, 'phone', r.phone, 'created_at', r.created_at, 'live', true, 'quote', pub, 'pay', pay, 'terms', tp));
  end if;
  return jsonb_strip_nulls(jsonb_build_object('kind', r.kind, 'title', r.title, 'subtitle', r.subtitle, 'amount', r.amount, 'valid_till', r.valid_till, 'details', r.details,
    'pdf_url', r.pdf_url, 'view_url', r.view_url, 'file_name', r.file_name, 'brand', r.brand, 'phone', r.phone, 'created_at', r.created_at, 'pay', pay));
end $f$;
grant execute on function public.sp_share_open(text, boolean) to anon, authenticated;

-- 6b) staff manual "Accepted" (customer link se nahi): record ki customer ka disclaimer nahi bhara gaya
create or replace function public.crm__terms_manual_trg() returns trigger language plpgsql security definer set search_path = public as $f$
begin
  if new.kind = 'quote' and new.status = 'accepted' and old.status is distinct from 'accepted' and (new.data -> 'terms_ok') is null and (new.data -> 'terms_manual') is null
     and public.crm__terms_for(new) is not null and coalesce(current_setting('sp.order_job', true), '') <> '1' and coalesce(current_setting('sp.link_accept', true), '') <> '1' then
    new.data := new.data || jsonb_build_object('terms_manual', jsonb_build_object('at', now(), 'note', 'Customer ne link par disclaimer nahi bhara — staff ne manual accept kiya'));
  end if;
  return new;
end $f$;
drop trigger if exists crm_terms_manual_trg on public.crm_records;
create trigger crm_terms_manual_trg before update on public.crm_records for each row execute function public.crm__terms_manual_trg();

-- 7) Settings save: Disclaimer text badle to bhi Activity log me likha jaye
create or replace function public.crm_settings_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); d jsonb := p -> 'data'; oc jsonb; k text; chg text := ''; tchg text := '';
begin
  perform public.crm_need(s, 'settings.manage');
  if jsonb_typeof(d) <> 'object' or length(d::text) > 400000 then raise exception 'Data galat hai'; end if;
  select data -> 'company' into oc from public.crm_settings where id = 1;
  foreach k in array array['bank_holder', 'bank_name', 'bank_acc', 'bank_ifsc', 'upi', 'pay_link', 'pay_box'] loop
    if coalesce(oc ->> k, '') is distinct from coalesce(d #>> array['company', k], '') then chg := chg || (case when chg = '' then '' else ', ' end) || k; end if;
  end loop;
  foreach k in array array['terms_product', 'terms_install'] loop
    if coalesce(oc ->> k, '') is distinct from coalesce(d #>> array['company', k], '') then tchg := tchg || (case when tchg = '' then '' else ', ' end) || k; end if;
  end loop;
  update public.crm_settings set data = (d - 'secrets' - 'auth') || jsonb_build_object('auth', coalesce(data -> 'auth', '{}'::jsonb)),
    secrets = case when d ? 'secrets' and jsonb_typeof(d -> 'secrets') = 'object' then ((d -> 'secrets') - 'resend_api_key' - 'conn') || jsonb_strip_nulls(jsonb_build_object('resend_api_key', secrets -> 'resend_api_key', 'conn', secrets -> 'conn')) else secrets end,
    updated_at = now() where id = 1;
  perform public.crm_log(s, 'settings', null, null, 'Company settings badli');
  if chg <> '' then perform public.crm_log(s, 'settings', null, null, 'PAYMENT DETAILS badli: ' || chg); end if;
  if tchg <> '' then perform public.crm_log(s, 'settings', null, null, 'DISCLAIMER text badla: ' || tchg); end if;
  return jsonb_build_object('ok', true);
end $f$;

-- 4) Customer ko "Advance" shabd nahi: reminder ka text "Bill amount / pehla payment"
do $do$ declare fn oid; src text;
begin
  for fn in select p.oid from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and pg_get_functiondef(p.oid) like '%advance ke liye call karein%' loop
    src := replace(pg_get_functiondef(fn), 'advance ke liye call karein', 'bill amount (pehla payment) ke liye call karein');
    execute src;
  end loop;
end $do$;

-- 8) Part-wise payment dabba SIRF manual (offline) ke liye — Online Store order ka quotation / bill par nahi (online me poora paisa ek baar)
create or replace function public.crm__pay_box(r public.sp_shares, q public.crm_records) returns jsonb language plpgsql stable security definer set search_path = public as $f$
declare co jsonb; upi text; acc text; lnk text; inv public.crm_records; tot numeric; rest_ numeric; ref_ text; nm text;
begin
  select data -> 'company' into co from public.crm_settings where id = 1;
  co := coalesce(co, '{}'::jsonb);
  if coalesce(co ->> 'pay_box', '1') = '0' then return null; end if;
  upi := btrim(coalesce(co ->> 'upi', ''));
  if upi !~ '^[A-Za-z0-9._-]{2,64}@[A-Za-z0-9.-]{2,32}$' then upi := ''; end if;
  acc := btrim(coalesce(co ->> 'bank_acc', ''));
  lnk := btrim(coalesce(co ->> 'pay_link', ''));
  if lnk !~ '^https://[^[:space:]<>"'']{4,255}$' then lnk := ''; end if;
  if upi = '' and acc = '' and lnk = '' then return null; end if;
  if q.id is not null then
    -- live quotation: payment sirf customer ke Accept (lock) ke baad. Pehle payment par koi limit nahi (customer jitna chahe de) — QR me rakam locked nahi
    if q.data ? 'order_id' then return null; end if;   -- online order: poora paisa ek baar me (part-wise sirf manual me)
    if q.data -> 'locked' is null or q.status in ('rejected', 'expired', 'draft') then return null; end if;
    tot := public.crm_num(q.data -> 'grand'); rest_ := tot; ref_ := q.ref;
  elsif r.kind = 'bill' and coalesce(r.ref, '') ~ '^rec:[0-9]+$' then
    select * into inv from public.crm_records where id = substr(r.ref, 5)::bigint and kind = 'invoice' and deleted_at is null;
    if inv.id is null or coalesce(inv.data ->> 'cancelled', '') in ('true', '1') or inv.data ? 'order_id' then return null; end if;   -- online order ka bill: part-wise nahi
    tot := public.crm_num(inv.data -> 'grand'); rest_ := public.crm_num(coalesce(inv.data -> 'balance', inv.data -> 'grand'));
    if rest_ <= 0 then return jsonb_build_object('paid', true); end if;
    ref_ := inv.ref;
  else
    return null;
  end if;
  nm := coalesce(nullif(btrim(co ->> 'bank_holder'), ''), nullif(btrim(co ->> 'legal'), ''), nullif(btrim(co ->> 'name'), ''), 'Sunpowers');
  return jsonb_strip_nulls(jsonb_build_object('upi', nullif(upi, ''), 'payee', nm, 'total', case when tot > 0 then tot end, 'paid', case when tot > rest_ then tot - rest_ end, 'rest', case when rest_ > 0 then rest_ end, 'ref', ref_, 'link', nullif(lnk, ''),
    'bank', case when acc <> '' then jsonb_strip_nulls(jsonb_build_object('holder', nullif(btrim(co ->> 'bank_holder'), ''), 'name', nullif(btrim(co ->> 'bank_name'), ''), 'acc', acc, 'ifsc', nullif(upper(btrim(co ->> 'bank_ifsc')), ''))) end));
end $f$;
revoke all on function public.crm__pay_box(public.sp_shares, public.crm_records) from public, anon, authenticated;

-- ===== U29 (Round 59): disclaimer chhota (ek tick) + install disclaimer me prakritik aapda ki ek line =====
-- Dobara chalane se koi nuksan nahi.
create or replace function public.crm__terms_pack(kinds text[]) returns jsonb language plpgsql stable security definer set search_path = public as $f$
declare co jsonb; k text; items jsonb := '[]'::jsonb; pts jsonb; ttl jsonb; ov text; line text;
begin
  select data -> 'company' into co from public.crm_settings where id = 1; co := coalesce(co, '{}'::jsonb);
  foreach k in array coalesce(kinds, '{}'::text[]) loop
    if k not in ('product', 'install') then continue; end if;
    ov := btrim(coalesce(co ->> ('terms_' || k), ''));
    if ov <> '' then
      pts := '[]'::jsonb;
      foreach line in array regexp_split_to_array(ov, E'\\r?\\n') loop
        if btrim(line) <> '' then pts := pts || jsonb_build_array(jsonb_build_object('h', left(btrim(line), 600), 'e', left(btrim(line), 600))); end if;
      end loop;
    elsif k = 'product' then
      pts := jsonb_build_array(
        jsonb_build_object('h', 'प्रोडक्ट की वारंटी / गारंटी / सर्विस सिर्फ़ उस प्रोडक्ट की निर्माता (मैन्युफैक्चरिंग) कंपनी की ज़िम्मेदारी है। Sunpowers सिर्फ़ विक्रेता / सप्लायर है; वारंटी या मैन्युफैक्चरिंग डिफ़ेक्ट की ज़िम्मेदारी Sunpowers की नहीं होगी। क्लेम के लिए निर्माता के अधिकृत सर्विस सेंटर से संपर्क करना होगा (Sunpowers सहायता करेगा)।',
          'e', 'Warranty / guarantee / service of a product is the responsibility of its manufacturer only. Sunpowers is only the seller / supplier and is not responsible for warranty or manufacturing defects. Claims go through the manufacturer''s authorised service centre (Sunpowers will assist).'),
        jsonb_build_object('h', 'वारंटी तभी मान्य होगी जब प्रोडक्ट निर्माता की शर्तों के अनुसार लगाया और चलाया गया हो। ग़लत इस्तेमाल, पानी, बिजली के झटके (surge) या छेड़छाड़ पर वारंटी लागू नहीं होती।',
          'e', 'Warranty applies only if the product is installed and used as per the manufacturer''s conditions. Misuse, water damage, power surge or tampering voids it.'),
        jsonb_build_object('h', 'डिलीवरी के समय पैकिंग / प्रोडक्ट जाँच लें और कमी हो तो तुरंत बताएँ। भुगतान, रिफ़ंड, शिपिंग और Terms पेज की शर्तें भी लागू हैं।',
          'e', 'Please check the packing / product at delivery and report any issue immediately. The Payment, Refund, Shipping and Terms pages also apply.'));
    else
      pts := jsonb_build_array(
        jsonb_build_object('h', 'इंस्टॉलेशन के दौरान Sunpowers के टेक्नीशियन मानक (standard) टूल्स और पूरी सावधानी / प्रिकॉशन के साथ काम करते हैं। छत में ड्रिल / छेद करना इंस्टॉलेशन का ज़रूरी हिस्सा है।',
          'e', 'Sunpowers technicians work with standard tools and full precautions. Drilling holes in the roof is a necessary part of installation.'),
        jsonb_build_object('h', 'छत की क्वालिटी / हालत (पुरानी या कमज़ोर छत, पतला स्लैब, दरार, सीलन, अंदर छिपे पाइप / सरिया / वायरिंग) पर ड्रिलिंग का नतीजा निर्भर करता है। अगर छेद आर-पार हो जाए, दरार, सीलन, लीकेज या कोई और नुकसान हो, तो यह छत की स्थिति पर निर्भर है और इसकी ज़िम्मेदारी Sunpowers की नहीं होगी। छत की किसी पुरानी कमज़ोरी की जानकारी ग्राहक काम से पहले टेक्नीशियन को देगा।',
          'e', 'The result of drilling depends on the quality / condition of your roof (old or weak roof, thin slab, cracks, dampness, hidden pipes / rods / wiring). If a hole goes through, or cracks, seepage, leakage or other damage occurs, it depends on the roof condition and Sunpowers is not responsible. The customer will tell the technician about any known weakness before work starts.'),
        jsonb_build_object('h', 'इंस्टॉलेशन एरिया / छत पर सिर्फ़ Sunpowers के टेक्नीशियन रहेंगे। ग्राहक, परिवार के सदस्य, बच्चे, पड़ोसी या कोई भी अनधिकृत (unauthorised) व्यक्ति इंस्टॉलेशन के दौरान वहाँ नहीं जाएगा — यह प्रतिबंधित है। ऐसा होने पर बिजली का झटका, गिरना, चोट या कोई भी दुर्घटना हो तो उसकी ज़िम्मेदारी ग्राहक की होगी, Sunpowers की नहीं।',
          'e', 'Only Sunpowers technicians may be in the installation area / on the roof. The customer, family members, children, neighbours or any unauthorised person must not go there during installation — it is prohibited. If an electric shock, fall, injury or any accident happens in that case, the customer is responsible, not Sunpowers.'),
        jsonb_build_object('h', 'ग्राहक छत तक सुरक्षित पहुँच, ज़रूरत पर बिजली बंद / चालू करने की अनुमति और काम के लिए जगह उपलब्ध कराएगा। काम के दौरान पैनल, इन्वर्टर या वायर को हाथ नहीं लगाएगा।',
          'e', 'The customer will provide safe access to the roof, permission to switch power off / on when needed, and space to work. Do not touch panels, inverter or wires during work.'),
        jsonb_build_object('h', 'सब्सिडी, नेट मीटरिंग और अप्रूवल DISCOM / सरकार के नियम और समय पर निर्भर हैं; इनकी गारंटी नहीं है। मौसम या DISCOM की वजह से देरी Sunpowers के नियंत्रण से बाहर है।',
          'e', 'Subsidy, net metering and approvals depend on DISCOM / government rules and timelines and are not guaranteed. Delays due to weather or DISCOM are outside Sunpowers'' control.'),
        jsonb_build_object('h', 'काम पूरा होने के बाद प्राकृतिक आपदा (आंधी-तूफ़ान, ओले, भूकंप, बाढ़, आसमानी बिजली, टर्नेडो आदि) से हुए नुकसान की ज़िम्मेदारी Sunpowers की नहीं होगी। यह हमारे इंस्टॉलेशन की अपनी ख़राबी पर लागू नहीं होता।',
          'e', 'Damage caused by natural disasters (storm, hail, earthquake, flood, lightning, tornado etc.) after the work is done is not Sunpowers'' responsibility. This does not apply to defects in our own installation work.'));
    end if;
    ttl := case k when 'product' then jsonb_build_object('h', 'प्रोडक्ट — वारंटी और ज़िम्मेदारी', 'e', 'Product — warranty and responsibility') else jsonb_build_object('h', 'इंस्टॉलेशन — छत और साइट की सुरक्षा', 'e', 'Installation — roof and site safety') end;
    items := items || jsonb_build_array(jsonb_build_object('k', k, 'title', ttl, 'points', pts));
  end loop;
  if jsonb_array_length(items) = 0 then return null; end if;
  return jsonb_build_object('ver', left(md5(items::text), 8), 'items', items);
end $f$;
revoke all on function public.crm__terms_pack(text[]) from public, anon, authenticated;

-- ===== U30 (Round 60): "Kahan bechna hai" — har item ke liye India / State / District niyam (delivery din + payment tarika + band switch) + Emergency =====
-- Dobara chalane se koi nuksan nahi. Purane sp_pin_* system par hi jud'ta hai (sp_pin_check / sp_pin_guard / sp_place_order wahi, bas ab ye niyam bhi dekhte hain).
-- Rule jeetne ka kram: District > State > Poora Bharat. Jis item ki koi jagah chuni hi nahi wo purane tarike se chalta hai (sab jagah), jab tak "only_chosen" switch chalu na ho.
-- Emergency chalu ho to pin / location dene ke baad har item "uplabdh nahi" dikhta hai (kimat dikhti hai, order nahi hota).

create table if not exists public.sp_sell (
  item_id    text not null,
  scope      text not null check (scope in ('all', 'state', 'district')),
  value      text not null,                       -- all='*' | state='UTTAR PRADESH' | district='UTTAR PRADESH|LUCKNOW'
  eta_min    int  not null default 0 check (eta_min between 0 and 365),
  eta_max    int  not null default 0 check (eta_max between 0 and 365),
  pay        text not null default 'both' check (pay in ('both', 'prepaid')),
  off        boolean not null default false,      -- is jagah par "abhi band" (Out of stock)
  updated_at timestamptz not null default now(),
  primary key (item_id, scope, value)
);
create index if not exists sp_sell_sv on public.sp_sell (scope, value);

create table if not exists public.sp_sell_cfg (
  id         int primary key default 1 check (id = 1),
  emergency  boolean not null default false,      -- ek click: poora Shop page + Store App out of stock (pin dalne ke baad dikhta hai)
  only_chosen     boolean not null default false,      -- jis item ki koi jagah nahi chuni wo kahin nahi bikega
  note       text not null default '',
  updated_at timestamptz not null default now()
);
insert into public.sp_sell_cfg(id) values (1) on conflict (id) do nothing;

alter table public.sp_sell enable row level security;
alter table public.sp_sell_cfg enable row level security;
do $$ begin revoke all on public.sp_sell, public.sp_sell_cfg from anon, authenticated; exception when undefined_object then null; end $$;

-- ---------- core: in items me se har ek par is pin ka sabse specific niyam -----------------------------
create or replace function public.sp_sell_best(p_pin text, p_ids text[])
returns table (r_id text, r_has boolean, r_ok boolean, r_min int, r_max int, r_pay text)
language plpgsql stable security definer set search_path = public as $$
declare st text; di text; stc boolean;
begin
  select state_u, district_u into st, di from public.sp_pin_master where pincode = p_pin;
  select coalesce(only_chosen, false) into stc from public.sp_sell_cfg where id = 1;
  return query
  with ids as (select distinct x as id from unnest(coalesce(p_ids, '{}'::text[])) x where x is not null),
  hasrows as (select distinct s.item_id from public.sp_sell s where s.item_id in (select id from ids)),
  cand as (
    select s.item_id, s.off, s.eta_min, s.eta_max, s.pay,
           case s.scope when 'district' then 3 when 'state' then 2 else 1 end as rk
    from public.sp_sell s
    where s.item_id in (select item_id from hasrows)
      and (s.scope = 'all'
           or (s.scope = 'state' and st is not null and s.value = st)
           or (s.scope = 'district' and st is not null and s.value = st || '|' || di))
  ),
  best as (select distinct on (c.item_id) c.* from cand c order by c.item_id, c.rk desc)
  select i.id,
         (h.item_id is not null or coalesce(stc, false)),
         (b.item_id is not null and not b.off),
         b.eta_min, b.eta_max, b.pay
  from ids i
  left join hasrows h on h.item_id = i.id
  left join best b on b.item_id = i.id;
end $$;

-- ---------- sp_pin_unavail: purana niyam ab "core" hai; naya = core + sell niyam + emergency ----------------
do $do$ declare src text;
begin
  if to_regprocedure('public.sp_pin_unavail_core(text,text[])') is null then
    alter function public.sp_pin_unavail(text, text[]) rename to sp_pin_unavail_core;
  else
    -- U03 dobara chala ho to wo asli function wapas bana deta hai: use "core" bana do
    src := pg_get_functiondef('public.sp_pin_unavail(text,text[])'::regprocedure);
    if position('sp_sell' in src) = 0 then
      drop function public.sp_pin_unavail_core(text, text[]);
      alter function public.sp_pin_unavail(text, text[]) rename to sp_pin_unavail_core;
    end if;
  end if;
end $do$;
revoke all on function public.sp_pin_unavail_core(text, text[]) from public, anon, authenticated;

create or replace function public.sp_pin_unavail(p_pin text, p_ids text[]) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare a text[]; b text[]; emg boolean;
begin
  select emergency into emg from public.sp_sell_cfg where id = 1;
  if coalesce(emg, false) then
    return coalesce((select array_agg(distinct x order by x) from unnest(coalesce(p_ids, '{}'::text[])) x where x is not null), '{}');
  end if;
  a := public.sp_pin_unavail_core(p_pin, p_ids);
  select coalesce(array_agg(r_id), '{}') into b from public.sp_sell_best(p_pin, p_ids) where r_has and not r_ok;
  return coalesce((select array_agg(x order by x) from (select unnest(coalesce(a, '{}'::text[])) as x union select unnest(b)) q), '{}');
end $$;
revoke all on function public.sp_pin_unavail(text, text[]) from public, anon, authenticated;

-- koi bhi niyam / emergency / only_chosen ho to storefront par pin maangna chalu
create or replace function public.sp_pin_enabled() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.sp_pin_rules) or exists (select 1 from public.sp_pin_modes where mode = 'only')
      or exists (select 1 from public.sp_sell) or exists (select 1 from public.sp_sell_cfg where emergency or only_chosen)
$$;

-- ---------- customer: pin dalte hi kya dikhega (sirf padhta hai) -----------------------------------------
create or replace function public.sp_pin_check(p_pin text, p_ids jsonb default '[]'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pin text := regexp_replace(coalesce(p_pin, ''), '\D', '', 'g'); ids text[]; en boolean := public.sp_pin_enabled(); m record; kn boolean;
        cfg public.sp_sell_cfg; info jsonb := '{}'::jsonb;
begin
  if jsonb_typeof(coalesce(p_ids, '[]'::jsonb)) <> 'array' then raise exception 'Invalid list'; end if;
  if jsonb_array_length(coalesce(p_ids, '[]'::jsonb)) > 2000 then raise exception 'Too many products'; end if;
  if pin !~ '^[1-9][0-9]{5}$' then return jsonb_build_object('enabled', en, 'valid', false, 'bad', '[]'::jsonb); end if;
  select * into m from public.sp_pin_master where pincode = pin; kn := found;
  if not en then
    return jsonb_build_object('enabled', false, 'valid', true, 'pin', pin, 'known', kn, 'state', coalesce(m.state, ''), 'district', coalesce(m.district, ''), 'bad', '[]'::jsonb);
  end if;
  select * into cfg from public.sp_sell_cfg where id = 1;
  select coalesce(array_agg(x), '{}') into ids from jsonb_array_elements_text(coalesce(p_ids, '[]'::jsonb)) x;
  if not coalesce(cfg.emergency, false) then
    select coalesce(jsonb_object_agg(r_id, jsonb_build_object('min', r_min, 'max', r_max, 'pay', r_pay)), '{}'::jsonb) into info
      from public.sp_sell_best(pin, ids) where r_has and r_ok and r_pay is not null;
  end if;
  return jsonb_build_object('enabled', true, 'valid', true, 'pin', pin, 'known', kn, 'state', coalesce(m.state, ''), 'district', coalesce(m.district, ''),
                            'bad', to_jsonb(public.sp_pin_unavail(pin, ids)), 'info', info,
                            'emg', coalesce(cfg.emergency, false), 'emg_note', case when coalesce(cfg.emergency, false) then coalesce(cfg.note, '') else '' end);
end $$;

-- ---------- order ke time: prepaid-only jagah par COD nahi chalega (server bhi rokta hai) ----------------
create or replace function public.sp_sell_pay_guard(p_pin text, p_items jsonb, p_payment text) returns void
language plpgsql stable security definer set search_path = public as $$
declare pin text := regexp_replace(coalesce(p_pin, ''), '\D', '', 'g'); ids text[]; names text;
begin
  if lower(coalesce(p_payment, '')) <> 'cod' then return; end if;
  if pin !~ '^[1-9][0-9]{5}$' then return; end if;
  select coalesce(array_agg(i ->> 'id'), '{}') into ids from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) i where coalesce(i ->> 'id', '') <> '';
  select string_agg(r_id, ', ') into names from public.sp_sell_best(pin, ids) where r_has and r_ok and r_pay = 'prepaid';
  if names is not null then
    raise exception 'PREPAID_ONLY_AT_PIN: Pincode % par in items me COD nahi hai, pura payment pehle dena hoga: %', pin, left(names, 200);
  end if;
end $$;
revoke all on function public.sp_sell_pay_guard(text, jsonb, text) from public, anon, authenticated;

do $do$ declare src text;
begin
  src := pg_get_functiondef('public.sp_place_order(jsonb)'::regprocedure);
  if position('sp_sell_pay_guard' in src) = 0 then
    src := replace(src, '  perform public.sp_pin_guard(', E'  perform public.sp_sell_pay_guard(p_order ->> ''pincode'', p_order -> ''items'', p_order ->> ''payment'');\n  perform public.sp_pin_guard(');
    execute src;
  end if;
end $do$;

-- ============================ ADMIN (Store Admin: sp_check) ============================
create or replace function public.sp_sell_val(p_scope text, p_value text) returns text language plpgsql immutable as $$
declare a text; b text;
begin
  if p_scope = 'all' then return '*'; end if;
  if p_scope = 'state' then a := public.sp_pin_norm(p_value); return nullif(a, ''); end if;
  if p_scope = 'district' then
    a := public.sp_pin_norm(split_part(coalesce(p_value, ''), '|', 1)); b := public.sp_pin_norm(split_part(coalesce(p_value, ''), '|', 2));
    if a = '' or b = '' then return null; end if;
    return a || '|' || b;
  end if;
  return null;
end $$;

-- ek item ki saari jagah
create or replace function public.sp_sell_get(p_pass text, p_item text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  perform public.sp_check(p_pass);
  return coalesce((select jsonb_agg(jsonb_build_object('scope', scope, 'value', value, 'eta_min', eta_min, 'eta_max', eta_max, 'pay', pay, 'off', off)
                   order by (case scope when 'all' then 0 when 'state' then 1 else 2 end), value)
                   from public.sp_sell where item_id = p_item), '[]'::jsonb);
end $$;

-- kai items par ek saath lagayein. mode: 'replace' (purani jagah hata kar sirf ye) | 'merge' (jodein / badlein)
create or replace function public.sp_sell_apply(p_pass text, p_items jsonb, p_rows jsonb, p_mode text default 'merge') returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare it text; r jsonb; sc text; v text; n int := 0; ni int := 0; em int; ex int; py text;
begin
  perform public.sp_check(p_pass);
  if jsonb_typeof(p_items) <> 'array' or jsonb_typeof(p_rows) <> 'array' then raise exception 'Invalid data'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'Koi item nahi chuna'; end if;
  if jsonb_array_length(p_items) > 800 then raise exception 'Ek baar me 800 se zyada item nahi'; end if;
  if jsonb_array_length(p_rows) > 3000 then raise exception 'Ek baar me 3000 se zyada jagah nahi'; end if;
  if p_mode not in ('merge', 'replace') then raise exception 'Mode galat'; end if;
  for it in select x from jsonb_array_elements_text(p_items) x loop
    if coalesce(it, '') = '' then continue; end if;
    if p_mode = 'replace' then delete from public.sp_sell where item_id = it; end if;
    for r in select * from jsonb_array_elements(p_rows) loop
      sc := coalesce(r ->> 'scope', ''); v := public.sp_sell_val(sc, r ->> 'value');
      if v is null then continue; end if;
      em := greatest(0, least(365, coalesce(nullif(r ->> 'eta_min', '')::int, 0)));
      ex := greatest(0, least(365, coalesce(nullif(r ->> 'eta_max', '')::int, 0)));
      if ex < em then ex := em; end if;
      py := case when r ->> 'pay' = 'prepaid' then 'prepaid' else 'both' end;
      insert into public.sp_sell(item_id, scope, value, eta_min, eta_max, pay, off)
      values (it, sc, v, em, ex, py, coalesce((r ->> 'off')::boolean, false))
      on conflict (item_id, scope, value) do update set eta_min = excluded.eta_min, eta_max = excluded.eta_max, pay = excluded.pay, off = excluded.off, updated_at = now();
      n := n + 1;
    end loop;
    ni := ni + 1;
  end loop;
  return jsonb_build_object('items', ni, 'rows', n);
end $$;

-- kisi jagah ko hatana (items me se)
create or replace function public.sp_sell_remove(p_pass text, p_items jsonb, p_scope text, p_value text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v text := public.sp_sell_val(p_scope, p_value); n int;
begin
  perform public.sp_check(p_pass);
  if v is null then raise exception 'Jagah galat'; end if;
  delete from public.sp_sell where scope = p_scope and value = v and item_id in (select x from jsonb_array_elements_text(p_items) x);
  get diagnostics n = row_count; return jsonb_build_object('deleted', n);
end $$;

-- kisi ek jagah par "abhi band / chalu" (kai items ek saath). Jagah pehle se chuni na ho to band karne par uske liye band-row ban jaati hai.
create or replace function public.sp_sell_off(p_pass text, p_items jsonb, p_scope text, p_value text, p_off boolean) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v text := public.sp_sell_val(p_scope, p_value); n int := 0; it text; c int;
begin
  perform public.sp_check(p_pass);
  if v is null then raise exception 'Jagah galat'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 1500 then raise exception 'Items galat'; end if;
  for it in select x from jsonb_array_elements_text(p_items) x loop
    update public.sp_sell set off = coalesce(p_off, false), updated_at = now() where item_id = it and scope = p_scope and value = v;
    get diagnostics c = row_count;
    if c = 0 and coalesce(p_off, false) then
      -- jis item ki koi jagah chuni hi nahi thi (sab jagah chal raha tha) use sirf ek jagah band karne par baaki jagah band na ho: pehle "Poora Bharat" chalu row
      if not exists (select 1 from public.sp_sell where item_id = it) then
        insert into public.sp_sell(item_id, scope, value) values (it, 'all', '*') on conflict do nothing;
      end if;
      insert into public.sp_sell(item_id, scope, value, off) values (it, p_scope, v, true) on conflict do nothing; c := 1;
    end if;
    n := n + c;
  end loop;
  return jsonb_build_object('changed', n);
end $$;

-- "Jagah-wise" screen: is jagah par kaun se items ke niyam hain
create or replace function public.sp_sell_place_list(p_pass text, p_scope text, p_value text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare v text := public.sp_sell_val(p_scope, p_value);
begin
  perform public.sp_check(p_pass);
  if v is null then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('item_id', item_id, 'eta_min', eta_min, 'eta_max', eta_max, 'pay', pay, 'off', off) order by item_id)
                   from public.sp_sell where scope = p_scope and value = v), '[]'::jsonb);
end $$;

-- sab items ka saar (list par chip dikhane ke liye)
create or replace function public.sp_sell_overview(p_pass text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  perform public.sp_check(p_pass);
  return coalesce((select jsonb_agg(jsonb_build_object('item_id', item_id, 'n', n, 'all', allr, 'all_off', alloff, 'states', st, 'dists', ds, 'off', offn) order by item_id)
    from (select item_id, count(*) n, bool_or(scope = 'all') allr, coalesce(bool_or(scope = 'all' and off), false) alloff,
                 count(*) filter (where scope = 'state') st, count(*) filter (where scope = 'district') ds, count(*) filter (where off) offn
          from public.sp_sell group by item_id) q), '[]'::jsonb);
end $$;

create or replace function public.sp_sell_cfg_get(p_pass text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare c public.sp_sell_cfg;
begin
  perform public.sp_check(p_pass);
  select * into c from public.sp_sell_cfg where id = 1;
  return jsonb_build_object('emergency', c.emergency, 'only_chosen', c.only_chosen, 'note', c.note, 'master', (select count(*) from public.sp_pin_master));
end $$;

create or replace function public.sp_sell_cfg_set(p_pass text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.sp_check(p_pass);
  update public.sp_sell_cfg set
    emergency = coalesce((p ->> 'emergency')::boolean, emergency),
    only_chosen    = coalesce((p ->> 'only_chosen')::boolean, only_chosen),
    note      = case when p ? 'note' then left(coalesce(p ->> 'note', ''), 200) else note end,
    updated_at = now()
  where id = 1;
  return public.sp_sell_cfg_get(p_pass);
end $$;

do $$ begin
  revoke all on function public.sp_sell_best(text, text[]), public.sp_sell_val(text, text) from public, anon, authenticated;
  grant execute on function
    public.sp_pin_check(text, jsonb),
    public.sp_sell_get(text, text), public.sp_sell_apply(text, jsonb, jsonb, text), public.sp_sell_remove(text, jsonb, text, text),
    public.sp_sell_off(text, jsonb, text, text, boolean), public.sp_sell_place_list(text, text, text), public.sp_sell_overview(text),
    public.sp_sell_cfg_get(text), public.sp_sell_cfg_set(text, jsonb)
  to anon, authenticated;
exception when undefined_object then null; end $$;

notify pgrst, 'reload schema';

-- ===== U31 (Round 61): Sarkari SUBSIDY (sirf jankari) — Central PM Surya Ghar + Rajya, sirf Residential On-Grid / Hybrid =====
-- Subsidy bill / quotation ki rakam me se KAM NAHI hoti. Ye sirf jankari ka dabba hai: project rate, Central, Rajya, kul subsidy, anumanit asli kharch.
-- Sunpowers koi subsidy nahi deta — sarkar seedha customer ke bank khate me deti hai. Dobara chalana safe hai (admin ke badle hue amount overwrite nahi hote).
-- Central (MNRE operational guidelines, residential): pehle 2 kW par Rs 30,000/kW, tisre kW par Rs 18,000, 3 kW ke baad koi extra nahi (max Rs 78,000).
--   Special category rajya (North-East, Uttarakhand, Himachal, J&K, Ladakh, A&N, Lakshadweep): Rs 33,000/kW aur Rs 19,800.
--   Off-Grid par CFA nahi. Battery-hybrid: rajya ke bijli aayog ki manzoori ke adheen. Non-residential par nahi.

create table if not exists public.sp_sub_cfg (
  id         int primary key default 1 check (id = 1),
  enabled    boolean not null default true,
  r1         numeric not null default 30000,   -- pehle 2 kW, Rs per kW
  r2         numeric not null default 18000,   -- tisra kW, Rs per kW
  r1_sp      numeric not null default 33000,   -- special category rajya
  r2_sp      numeric not null default 19800,
  cap_kw     numeric not null default 3,       -- is se upar koi extra CFA nahi
  note       text not null default '',
  updated_at timestamptz not null default now()
);
insert into public.sp_sub_cfg(id) values (1) on conflict (id) do nothing;

create table if not exists public.sp_sub_state (
  state_u    text primary key,                 -- UPPER naam
  state      text not null,
  special    boolean not null default false,   -- special category (Central ki dar +10%)
  per_kw     numeric not null default 0,       -- Rs per kW
  cap        numeric not null default 0,       -- max Rs (0 = koi seema nahi)
  fixed      numeric not null default 0,       -- tay raqam (>0 ho to per_kw ki jagah yahi)
  note       text not null default '',
  src        text not null default '',
  verified   boolean not null default false,   -- official site se pakka kiya
  active     boolean not null default false,   -- customer ko dikhana hai ya nahi
  updated_at timestamptz not null default now()
);
alter table public.sp_sub_cfg enable row level security;
alter table public.sp_sub_state enable row level security;
do $$ begin revoke all on public.sp_sub_cfg, public.sp_sub_state from anon, authenticated; exception when undefined_object then null; end $$;

-- 36 rajya / UT (CRM ki list jaisa naam). Pehle se bhare hue ko nahi chhedta.
insert into public.sp_sub_state(state_u, state, special, per_kw, cap, note, src, verified, active) values
 ('ANDAMAN AND NICOBAR ISLANDS', 'Andaman and Nicobar Islands', true, 0, 0, '', '', false, false),
 ('ANDHRA PRADESH', 'Andhra Pradesh', false, 0, 0, '', '', false, false),
 ('ARUNACHAL PRADESH', 'Arunachal Pradesh', true, 0, 0, '', '', false, false),
 ('ASSAM', 'Assam', true, 0, 0, '', '', false, false),
 ('BIHAR', 'Bihar', false, 10000, 20000, 'Rs 10,000/kW, max Rs 20,000 (do news-sources; official se pakka karke chalu karein)', 'news (Saur Energy)', false, false),
 ('CHANDIGARH', 'Chandigarh', false, 0, 0, '', '', false, false),
 ('CHHATTISGARH', 'Chhattisgarh', false, 0, 0, '', '', false, false),
 ('DADRA AND NAGAR HAVELI AND DAMAN AND DIU', 'Dadra and Nagar Haveli and Daman and Diu', false, 0, 0, '', '', false, false),
 ('DELHI', 'Delhi', false, 10000, 30000, 'Rs 10,000/kW, max Rs 30,000 (Delhi cabinet, May 2025 — official site se pakka karke chalu karein)', 'news (Power Line / Energetica)', false, false),
 ('GOA', 'Goa', false, 0, 0, '', '', false, false),
 ('GUJARAT', 'Gujarat', false, 0, 0, 'Naya niyam (22 Oct 2026 ke baad chalu systems, 2.18 kWp tak) — raqam tay nahi, benchmark se nikalti hai; admin pakka karke bharein', '', false, false),
 ('HARYANA', 'Haryana', false, 0, 0, '', '', false, false),
 ('HIMACHAL PRADESH', 'Himachal Pradesh', true, 0, 0, '', '', false, false),
 ('JAMMU AND KASHMIR', 'Jammu and Kashmir', true, 0, 0, '', '', false, false),
 ('JHARKHAND', 'Jharkhand', false, 0, 0, '', '', false, false),
 ('KARNATAKA', 'Karnataka', false, 0, 0, '', '', false, false),
 ('KERALA', 'Kerala', false, 0, 0, '', '', false, false),
 ('LADAKH', 'Ladakh', true, 0, 0, '', '', false, false),
 ('LAKSHADWEEP', 'Lakshadweep', true, 0, 0, '', '', false, false),
 ('MADHYA PRADESH', 'Madhya Pradesh', false, 0, 0, '', '', false, false),
 ('MAHARASHTRA', 'Maharashtra', false, 0, 0, '', '', false, false),
 ('MANIPUR', 'Manipur', true, 0, 0, '', '', false, false),
 ('MEGHALAYA', 'Meghalaya', true, 0, 0, '', '', false, false),
 ('MIZORAM', 'Mizoram', true, 0, 0, '', '', false, false),
 ('NAGALAND', 'Nagaland', true, 0, 0, '', '', false, false),
 ('ODISHA', 'Odisha', false, 0, 0, '', '', false, false),
 ('PUDUCHERRY', 'Puducherry', false, 0, 0, '', '', false, false),
 ('PUNJAB', 'Punjab', false, 0, 0, '', '', false, false),
 ('RAJASTHAN', 'Rajasthan', false, 0, 0, '', '', false, false),
 ('SIKKIM', 'Sikkim', true, 0, 0, '', '', false, false),
 ('TAMIL NADU', 'Tamil Nadu', false, 0, 0, '', '', false, false),
 ('TELANGANA', 'Telangana', false, 0, 0, '', '', false, false),
 ('TRIPURA', 'Tripura', true, 0, 0, '', '', false, false),
 ('UTTAR PRADESH', 'Uttar Pradesh', false, 15000, 30000, 'Rs 15,000/kW, max Rs 30,000, Central ke upar (UPNEDA)', 'UPNEDA FAQ — upneda.org.in', true, true),
 ('UTTARAKHAND', 'Uttarakhand', true, 0, 0, '', '', false, false),
 ('WEST BENGAL', 'West Bengal', false, 0, 0, '', '', false, false)
on conflict (state_u) do nothing;

-- ---------- rajya ka naam ek jaisa karna (CRM ka naam / pin-master ka naam / purane naam) ----------------
create or replace function public.sp_sub_norm(s text) returns text language sql immutable as $$
  select case
    when x in ('ORISSA') then 'ODISHA'
    when x in ('PONDICHERRY') then 'PUDUCHERRY'
    when x in ('NCT OF DELHI', 'NEW DELHI', 'DELHI NCR') then 'DELHI'
    when x in ('UTTARANCHAL') then 'UTTARAKHAND'
    when x in ('JAMMU AND KASHMIR', 'JAMMU KASHMIR') then 'JAMMU AND KASHMIR'
    when x in ('ANDAMAN AND NICOBAR', 'ANDAMAN NICOBAR ISLANDS', 'ANDAMAN AND NICOBAR ISLANDS') then 'ANDAMAN AND NICOBAR ISLANDS'
    when x in ('DADRA AND NAGAR HAVELI', 'DAMAN AND DIU', 'DADRA AND NAGAR HAVELI AND DAMAN AND DIU', 'DAMAN DIU', 'DADRA NAGAR HAVELI') then 'DADRA AND NAGAR HAVELI AND DAMAN AND DIU'
    else x end
  from (select btrim(regexp_replace(regexp_replace(upper(replace(coalesce(s, ''), '&', ' AND ')), '[^A-Z ]', ' ', 'g'), '\s+', ' ', 'g')) x) t
$$;

-- ---------- hisaab: kul subsidy kitni (PUBLIC — sirf jankari, koi gopniya cheez nahi) ------------------
create or replace function public.sp_sub_calc(p_state text, p_kw numeric, p_sys text default 'on', p_res boolean default true) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare cfg public.sp_sub_cfg; st public.sp_sub_state; sy text; kw numeric := coalesce(p_kw, 0); c numeric := 0; s numeric := 0; sp boolean := false; sn text := public.sp_sub_norm(p_state); r1 numeric; r2 numeric;
begin
  select * into cfg from public.sp_sub_cfg where id = 1;
  if not found or not cfg.enabled then return jsonb_build_object('ok', false, 'reason', 'off'); end if;
  sy := lower(coalesce(nullif(btrim(p_sys), ''), 'on'));
  sy := case when sy in ('hy', 'hybrid') then 'hy' when sy in ('off', 'offgrid', 'off-grid') then 'off' else 'on' end;
  if not coalesce(p_res, false) then return jsonb_build_object('ok', false, 'reason', 'not_res'); end if;
  if sy = 'off' then return jsonb_build_object('ok', false, 'reason', 'offgrid'); end if;
  if kw <= 0 then return jsonb_build_object('ok', false, 'reason', 'nokw'); end if;
  if sn <> '' then select * into st from public.sp_sub_state where state_u = sn; end if;
  sp := coalesce(st.special, false);
  r1 := case when sp then cfg.r1_sp else cfg.r1 end; r2 := case when sp then cfg.r2_sp else cfg.r2 end;
  c := least(kw, 2) * r1 + least(greatest(kw - 2, 0), greatest(cfg.cap_kw - 2, 0)) * r2;
  if st.state_u is not null and st.active then
    s := case when st.fixed > 0 then st.fixed else st.per_kw * kw end;
    if st.fixed <= 0 and st.cap > 0 then s := least(s, st.cap); end if;
  end if;
  c := round(c); s := round(s);
  return jsonb_build_object('ok', true, 'sys', sy, 'kw', kw, 'central', c, 'state', s, 'total', c + s,
    'state_name', coalesce(st.state, ''), 'state_known', st.state_u is not null, 'state_active', coalesce(st.active, false) and s > 0,
    'special', sp, 'hybrid_note', sy = 'hy', 'state_note', case when s > 0 then coalesce(st.note, '') else '' end,
    'unverified', s > 0 and not coalesce(st.verified, false), 'note', cfg.note);
end $$;
grant execute on function public.sp_sub_calc(text, numeric, text, boolean) to anon, authenticated;

-- ---------- order ke time: server khud hisaab karke order me "subsidy" likh deta hai (sirf jankari) ----------
create or replace function public.sp_sub_order(p_pin text, p_items jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pin text := regexp_replace(coalesce(p_pin, ''), '\D', '', 'g'); stn text := ''; prods jsonb; i jsonb; pr jsonb; q numeric; r jsonb; lines jsonb := '[]'::jsonb; tc numeric := 0; ts numeric := 0;
begin
  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array' then return null; end if;
  select coalesce(state, '') into stn from public.sp_pin_master where pincode = pin;
  select coalesce(data -> 'products', '[]'::jsonb) into prods from public.sp_store where id = 'main';
  for i in select * from jsonb_array_elements(p_items) loop
    select x into pr from jsonb_array_elements(prods) x where x ->> 'id' = i ->> 'id' limit 1;
    if pr is null or jsonb_typeof(pr -> 'sub') <> 'object' then continue; end if;
    q := greatest(public.crm_num(i -> 'qty'), 1);
    r := public.sp_sub_calc(stn, public.crm_num(pr #> '{sub,kw}'), pr #>> '{sub,sys}', coalesce((pr #>> '{sub,res}') = 'true', false));
    if coalesce((r ->> 'ok')::boolean, false) then
      lines := lines || jsonb_build_object('id', pr ->> 'id', 'name', left(coalesce(pr ->> 'title', ''), 120), 'qty', q, 'kw', r -> 'kw', 'sys', r ->> 'sys',
                                           'central', (r ->> 'central')::numeric * q, 'state', (r ->> 'state')::numeric * q, 'total', (r ->> 'total')::numeric * q);
      tc := tc + (r ->> 'central')::numeric * q; ts := ts + (r ->> 'state')::numeric * q;
    end if;
  end loop;
  if jsonb_array_length(lines) = 0 then return null; end if;
  return jsonb_build_object('state', stn, 'pin', pin, 'central', tc, 'state_amt', ts, 'total', tc + ts, 'lines', lines, 'info_only', true);
end $$;
revoke all on function public.sp_sub_order(text, jsonb) from public, anon, authenticated;

do $do$ declare src text;
begin
  src := pg_get_functiondef('public.sp_place_order(jsonb)'::regprocedure);
  if position('sp_sub_order' in src) = 0 then
    src := replace(src, '  insert into public.sp_orders(data) values (o) returning id into new_id;',
      E'  o := o || coalesce((select jsonb_build_object(''subsidy'', x) from (select public.sp_sub_order(p_order ->> ''pincode'', p_order -> ''items'') x) q where x is not null), ''{}''::jsonb);\n  insert into public.sp_orders(data) values (o) returning id into new_id;');
    if position('sp_sub_order' in src) = 0 then raise exception 'U31: sp_place_order me jagah nahi mili'; end if;
    execute src;
  end if;
end $do$;

-- ============================ ADMIN (Store Admin: sp_check) ============================
create or replace function public.sp_sub_admin_get(p_pass text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.sp_check(p_pass);
  return jsonb_build_object(
    'cfg', (select to_jsonb(c) - 'id' - 'updated_at' from public.sp_sub_cfg c where id = 1),
    'states', coalesce((select jsonb_agg(to_jsonb(s) - 'updated_at' order by s.state) from public.sp_sub_state s), '[]'::jsonb));
end $$;

create or replace function public.sp_sub_admin_cfg_set(p_pass text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k text; v numeric;
begin
  perform public.sp_check(p_pass);
  foreach k in array array['r1', 'r2', 'r1_sp', 'r2_sp', 'cap_kw'] loop
    if p ? k then
      v := public.crm_num(p -> k);
      if v < 0 or v > 1000000 then raise exception 'Raqam galat hai: %', k; end if;
      execute format('update public.sp_sub_cfg set %I = $1, updated_at = now() where id = 1', k) using v;
    end if;
  end loop;
  if p ? 'enabled' then update public.sp_sub_cfg set enabled = coalesce((p ->> 'enabled')::boolean, true), updated_at = now() where id = 1; end if;
  if p ? 'note' then update public.sp_sub_cfg set note = left(coalesce(p ->> 'note', ''), 400), updated_at = now() where id = 1; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.sp_sub_admin_state_set(p_pass text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare su text := public.sp_sub_norm(p ->> 'state'); pk numeric := public.crm_num(p -> 'per_kw'); cp numeric := public.crm_num(p -> 'cap'); fx numeric := public.crm_num(p -> 'fixed');
begin
  perform public.sp_check(p_pass);
  if su = '' then raise exception 'Rajya ka naam likhein'; end if;
  if pk < 0 or pk > 1000000 or cp < 0 or cp > 10000000 or fx < 0 or fx > 10000000 then raise exception 'Raqam galat hai'; end if;
  insert into public.sp_sub_state(state_u, state, special, per_kw, cap, fixed, note, src, verified, active, updated_at)
  values (su, left(trim(coalesce(p ->> 'state', su)), 60), coalesce((p ->> 'special')::boolean, false), pk, cp, fx, left(coalesce(p ->> 'note', ''), 300), left(coalesce(p ->> 'src', ''), 200),
          coalesce((p ->> 'verified')::boolean, false), coalesce((p ->> 'active')::boolean, false), now())
  on conflict (state_u) do update set special = excluded.special, per_kw = excluded.per_kw, cap = excluded.cap, fixed = excluded.fixed, note = excluded.note, src = excluded.src,
        verified = excluded.verified, active = excluded.active, updated_at = now();
  return jsonb_build_object('ok', true);
end $$;

do $$ begin
  revoke all on function public.sp_sub_admin_get(text), public.sp_sub_admin_cfg_set(text, jsonb), public.sp_sub_admin_state_set(text, jsonb) from public;
  grant execute on function public.sp_sub_admin_get(text), public.sp_sub_admin_cfg_set(text, jsonb), public.sp_sub_admin_state_set(text, jsonb) to anon, authenticated;
end $$;

-- ============================ CUSTOMER: pin dalte hi subsidy (sp_pin_check me "sub" jud jata hai) ============================
-- Jin products me "sub" (kW + System type + Residential) bhara hai unki subsidy us pin ke rajya ke hisaab se. Pin dene se pehle kuch nahi dikhta.
create or replace function public.sp_sub_ids(p_state text, p_ids jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ids text[]; prods jsonb; out jsonb := '{}'::jsonb; x jsonb; r jsonb;
begin
  if jsonb_typeof(coalesce(p_ids, '[]'::jsonb)) <> 'array' then return out; end if;
  select coalesce(array_agg(v), '{}') into ids from jsonb_array_elements_text(p_ids) v;
  select coalesce(data -> 'products', '[]'::jsonb) into prods from public.sp_store where id = 'main';
  for x in select e from jsonb_array_elements(prods) e where (e ->> 'id') = any (ids) and jsonb_typeof(e -> 'sub') = 'object' loop
    r := public.sp_sub_calc(p_state, public.crm_num(x #> '{sub,kw}'), x #>> '{sub,sys}', coalesce((x #>> '{sub,res}') = 'true', false));
    if coalesce((r ->> 'ok')::boolean, false) then
      out := out || jsonb_build_object(x ->> 'id', jsonb_build_object('kw', r -> 'kw', 'sys', r ->> 'sys', 'central', r -> 'central', 'state', r -> 'state', 'total', r -> 'total',
              'state_name', r ->> 'state_name', 'hy', r -> 'hybrid_note', 'note', r ->> 'state_note', 'unv', r -> 'unverified'));
    end if;
  end loop;
  return out;
end $$;
revoke all on function public.sp_sub_ids(text, jsonb) from public, anon, authenticated;

do $do$ begin
  if to_regprocedure('public.sp_pin_check_core(text,jsonb)') is null then
    alter function public.sp_pin_check(text, jsonb) rename to sp_pin_check_core;
  end if;
end $do$;
revoke all on function public.sp_pin_check_core(text, jsonb) from public, anon, authenticated;

create or replace function public.sp_pin_check(p_pin text, p_ids jsonb default '[]'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb := public.sp_pin_check_core(p_pin, p_ids);
begin
  if coalesce((r ->> 'valid')::boolean, false) is not true then return r; end if;
  return r || jsonb_build_object('sub', public.sp_sub_ids(r ->> 'state', p_ids));
end $$;
grant execute on function public.sp_pin_check(text, jsonb) to anon, authenticated;

-- ---------- customer ka order page: order me likhi hui subsidy (jankari) bhi dikhe ----------
do $do$ declare src text;
begin
  src := pg_get_functiondef('public.crm_consumer_order(jsonb)'::regprocedure);
  if position('''subsidy''' in src) = 0 then
    src := replace(src, '''install'', coalesce(o.data -> ''install'', ''[]''::jsonb));', '''install'', coalesce(o.data -> ''install'', ''[]''::jsonb), ''subsidy'', o.data -> ''subsidy'');');
    if position('''subsidy''' in src) = 0 then raise exception 'U31: crm_consumer_order me jagah nahi mili'; end if;
    execute src;
  end if;
end $do$;

-- ===== U32 (Round 62): customer ke Documents me sab kuch ek jagah — rasid (receipt), customer ki apni upload, kya dikhana hai (Settings) + bill me "Aapko kya milega" data =====
-- Dobara chalane se koi nuksan nahi. Purane documents / bill waise hi rehte hain. Naya table nahi — sab purane crm_records / crm_files me.

-- 0) Settings: customer ko kaunse documents dikhein  (Settings > Company > hub.docs; khali = sab dikhein)
create or replace function public.crm__hubdocs() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select data #> '{hub,docs}' from public.crm_settings where id = 1), '{}'::jsonb) $$;
revoke all on function public.crm__hubdocs() from public, anon, authenticated;

-- 1) Customer ke print (quotation / bill) me subsidy + faayde + item ki category chali jaye (sirf safe fields)
do $u$ declare src text; fn text;
begin
  foreach fn in array array['public.crm_consumer_plant_doc(jsonb)', 'public.crm_consumer_bill_doc(jsonb)'] loop
    src := pg_get_functiondef(fn::regprocedure);
    if position('benefits' in src) = 0 then
      src := replace(src, $a$'hsn', l ->> 'hsn'))$a$, $b$'hsn', l ->> 'hsn', 'kind', l ->> 'kind', 'category', l ->> 'category', 'subcategory', l ->> 'subcategory', 'kw', l ->> 'kw', 'sys', l ->> 'sys'))$b$);
      src := replace(src, $a$'notes', src.data ->> 'notes'$a$, $b$'notes', src.data ->> 'notes', 'ctype', src.data ->> 'ctype', 'kw', src.data ->> 'kw', 'sys', src.data ->> 'sys', 'subsidy', src.data -> 'subsidy', 'benefits', src.data -> 'benefits', 'no_ben', src.data -> 'no_ben', 'hub', (select data -> 'hub' from public.crm_settings where id = 1)$b$);
      if position('benefits' in src) = 0 then raise exception 'U32: % me jagah nahi mili', fn; end if;
      execute src;
    end if;
  end loop;
end $u$;

-- 2) Online order ka bill/quotation: item ki category, project ka System type, aur order ki subsidy jankari bhi saath
do $u$ declare src text;
begin
  src := pg_get_functiondef('public.crm__order_job(bigint,bigint)'::regprocedure);
  if position('subsidy' in src) = 0 then
    src := replace(src, $a$jsonb_build_object('kind', 'product', 'item_id', c.id,$a$, $b$jsonb_build_object('kind', 'product', 'category', c.data ->> 'category', 'subcategory', c.data ->> 'subcategory', 'item_id', c.id,$b$);
    src := replace(src, $a$'kw', nullif(c.data ->> 'kw', ''), 'proj_items', c.data -> 'proj_items'));$a$, $b$'kw', nullif(c.data ->> 'kw', ''), 'sys', nullif(c.data ->> 'sys', ''), 'proj_items', c.data -> 'proj_items'));$b$);
    src := replace(src, $a$'kw', case when proj.id is not null then nullif(proj.data ->> 'kw', '') end,$a$, $b$'kw', case when proj.id is not null then nullif(proj.data ->> 'kw', '') end, 'sys', case when proj.id is not null then nullif(proj.data ->> 'sys', '') end,
         'subsidy', case when ct = 'Residential' and public.crm_num(o.data #> '{subsidy,total}') > 0 then jsonb_build_object('central', o.data #> '{subsidy,central}', 'state', o.data #> '{subsidy,state_amt}', 'total', o.data #> '{subsidy,total}', 'state_name', o.data #>> '{subsidy,state}', 'kw', nullif(proj.data ->> 'kw', ''), 'sys', coalesce(nullif(proj.data ->> 'sys', ''), 'on')) end,$b$);
    if position('subsidy' in src) = 0 then raise exception 'U32: crm__order_job me jagah nahi mili'; end if;
    execute src;
  end if;
end $u$;

-- 3) Hub: rasid list + "kya dikhana hai" + faayde ke text overrides
do $u$ declare src text;
begin
  src := pg_get_functiondef('public.crm_consumer_hub(jsonb)'::regprocedure);
  if position('docs_cfg' in src) = 0 then
    src := replace(src, $a$cats jsonb := '{}'::jsonb; st jsonb; co jsonb;$a$, $b$cats jsonb := '{}'::jsonb; st jsonb; co jsonb; rc jsonb := '[]'::jsonb;$b$);
    src := replace(src, $a$  select data into st from public.crm_settings where id = 1;$a$, $b$  select data into st from public.crm_settings where id = 1;
  select coalesce(jsonb_agg(z.j order by z.pid desc), '[]'::jsonb) into rc from (
    select py.id as pid, jsonb_build_object('id', py.id, 'ref', py.ref, 'date', coalesce(nullif(py.data ->> 'date', ''), py.due_at::text), 'amount', py.amount, 'mode', py.data ->> 'mode', 'bill', i.ref, 'quote_id', nullif(i.data ->> 'quote_id', '')::bigint) as j
      from public.crm_records py join public.crm_records i on i.id = nullif(py.data ->> 'invoice_id', '')::bigint and i.kind = 'invoice' and i.deleted_at is null and i.party_id = pt.id
     where py.kind = 'payment' and py.deleted_at is null and pt.id is not null order by py.id desc limit 100) z;$b$);
    src := replace(src, $a$'gen', coalesce(nullif(st -> 'hub' ->> 'gen', '')::numeric, 4))$a$, $b$'gen', coalesce(nullif(st -> 'hub' ->> 'gen', '')::numeric, 4), 'ben', coalesce(st -> 'hub' -> 'ben', '{}'::jsonb))$b$);
    src := replace(src, $a$return prof || jsonb_build_object('orders', orders,$a$, $b$return prof || jsonb_build_object('receipts', case when coalesce(st #>> '{hub,docs,receipt}', '1') = '0' then '[]'::jsonb else rc end, 'docs_cfg', coalesce(st #> '{hub,docs}', '{}'::jsonb), 'orders', orders,$b$);
    if position('docs_cfg' in src) = 0 or position('rc jsonb' in src) = 0 then raise exception 'U32: crm_consumer_hub me jagah nahi mili'; end if;
    execute src;
  end if;
end $u$;

-- 4) Staff ki upload ki file customer ko tabhi jaaye jab Settings me wo category / "files" band na ho (customer ki apni file hamesha)
do $u$ declare src text;
begin
  src := pg_get_functiondef('public.crm_consumer_file(jsonb)'::regprocedure);
  if position('crm__hubdocs' in src) = 0 then
    src := replace(src, $a$  select * into f from public.crm_files where rec_id = d.id limit 1;$a$, $b$  if coalesce((d.data ->> 'by_customer')::boolean, false) = false and (coalesce(public.crm__hubdocs() ->> 'files', '1') = '0'
     or (d.data ->> 'cat') in (select jsonb_array_elements_text(case when jsonb_typeof(public.crm__hubdocs() -> 'hide_cats') = 'array' then public.crm__hubdocs() -> 'hide_cats' else '[]'::jsonb end))) then raise exception 'File nahi mili'; end if;
  select * into f from public.crm_files where rec_id = d.id limit 1;$b$);
    if position('crm__hubdocs' in src) = 0 then raise exception 'U32: crm_consumer_file me jagah nahi mili'; end if;
    execute src;
  end if;
end $u$;

-- 5) Rasid (payment receipt) — customer ka apna, sirf safe fields
create or replace function public.crm_consumer_receipt(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); pt public.crm_records := public.crm__cust_party(u); py public.crm_records; i public.crm_records; co jsonb;
begin
  if coalesce(public.crm__hubdocs() ->> 'receipt', '1') = '0' then raise exception 'Rasid nahi mili'; end if;
  select * into py from public.crm_records where id = nullif(p ->> 'id', '')::bigint and kind = 'payment' and deleted_at is null;
  if py.id is null or pt.id is null then raise exception 'Rasid nahi mili'; end if;
  select * into i from public.crm_records where id = nullif(py.data ->> 'invoice_id', '')::bigint and kind = 'invoice' and deleted_at is null and party_id = pt.id;
  if i.id is null then raise exception 'Rasid nahi mili'; end if;
  select data -> 'company' into co from public.crm_settings where id = 1;
  return jsonb_build_object('kind', 'receipt', 'ref', py.ref, 'date', coalesce(nullif(py.data ->> 'date', ''), py.due_at::text), 'amount', py.amount, 'mode', py.data ->> 'mode', 'bill', i.ref, 'bill_total', i.amount,
    'bill_paid', i.data -> 'paid', 'bill_balance', i.data -> 'balance', 'title', i.data ->> 'qtitle',
    'customer', jsonb_build_object('name', pt.title, 'mobile', pt.mobile, 'address', pt.data ->> 'address', 'city', pt.data ->> 'city'),
    'company', jsonb_build_object('name', co ->> 'name', 'legal', co ->> 'legal', 'gstin', co ->> 'gstin', 'phone', co ->> 'phone', 'address', co ->> 'address'));
end $$;

-- 6) Customer apni file khud bhejta hai (ID, bijli bill, chhat ki photo, payment screenshot...) — seedha usi kaam ke Documents me; staff ko step 14 me apne aap dikhti hai
create or replace function public.crm_consumer_doc_upload(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); q public.crm_records; r public.crm_records; b bytea; nm text := regexp_replace(left(trim(coalesce(p ->> 'name', 'file')), 120), '[<>"''\\/]', '', 'g'); mm text := lower(coalesce(p ->> 'mime', ''));
        cc text := coalesce(nullif(trim(p ->> 'ccat'), ''), 'Other'); n int; hd bytea;
begin
  if coalesce(public.crm__hubdocs() ->> 'upload', '1') = '0' then raise exception 'Abhi file bhejna band hai — Sunpowers team se sampark karein'; end if;
  select q2.* into q from public.crm_records q2 join public.crm_consumer_plants cp on cp.quote_id = q2.id and cp.user_id = u.id where q2.id = nullif(p ->> 'quote_id', '')::bigint;
  if q.id is null or not public.crm_plant_owned(u, q) then raise exception 'Kaam nahi mila'; end if;
  if cc not in ('ID proof', 'Bijli bill', 'Chhat ki photo', 'Payment screenshot', 'Other') then cc := 'Other'; end if;
  if nm = '' then nm := 'file'; end if;
  if mm not in ('image/jpeg', 'image/png', 'image/webp', 'application/pdf') then raise exception 'Sirf photo (JPG / PNG) ya PDF bhejein'; end if;
  begin b := decode(coalesce(p ->> 'b64', ''), 'base64'); exception when others then raise exception 'File padh nahi paye'; end;
  if octet_length(b) = 0 then raise exception 'File khaali hai'; end if;
  if octet_length(b) > 3 * 1024 * 1024 then raise exception 'File 3 MB se badi hai — chhoti karke bhejein'; end if;
  hd := substring(b from 1 for 4);
  if not ((mm = 'image/jpeg' and substring(hd from 1 for 2) = '\xffd8'::bytea) or (mm = 'image/png' and hd = '\x89504e47'::bytea) or (mm = 'application/pdf' and hd = '\x25504446'::bytea) or (mm = 'image/webp' and hd = '\x52494646'::bytea)) then raise exception 'File ka type sahi nahi hai'; end if;
  select count(*) into n from public.crm_records where kind = 'doc' and deleted_at is null and (data ->> 'shared_quote') = q.id::text and coalesce((data ->> 'by_customer')::boolean, false);
  if n >= 30 then raise exception 'Is kaam me 30 file ho chuki hain — pehle purani hata dein'; end if;
  insert into public.crm_records(kind, title, status, owner_id, party_id, data, search, created_by)
  values ('doc', nm, 'ok', q.owner_id, q.party_id,
    jsonb_build_object('mime', mm, 'size', octet_length(b), 'note', left(trim(coalesce(p ->> 'note', '')), 300), 'cat', 'Customer ne bheja', 'ccat', cc, 'attach_kind', 'party', 'attach_id', q.party_id::text,
      'shared_quote', q.id, 'shared_ref', q.ref, 'shared_at', public.crm_iso_now(), 'shared_by', coalesce(u.name, 'Customer'), 'by_customer', true, 'cdoc', true),
    lower(nm || ' ' || coalesce(q.ref, '')), q.owner_id) returning * into r;
  insert into public.crm_files(rec_id, mime, size, data) values (r.id, mm, octet_length(b), b);
  return jsonb_build_object('ok', true, 'id', r.id);
end $$;

create or replace function public.crm_consumer_doc_delete(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); d public.crm_records; q public.crm_records;
begin
  select * into d from public.crm_records where id = nullif(p ->> 'id', '')::bigint and kind = 'doc' and deleted_at is null and coalesce((data ->> 'by_customer')::boolean, false);
  if d.id is null then raise exception 'File nahi mili'; end if;
  select q2.* into q from public.crm_records q2 join public.crm_consumer_plants cp on cp.quote_id = q2.id and cp.user_id = u.id where q2.id = (d.data ->> 'shared_quote')::bigint;
  if q.id is null or not public.crm_plant_owned(u, q) then raise exception 'File nahi mili'; end if;
  update public.crm_records set deleted_at = now() where id = d.id;
  delete from public.crm_files where rec_id = d.id;
  return jsonb_build_object('ok', true);
end $$;

grant execute on function public.crm_consumer_receipt(jsonb), public.crm_consumer_doc_upload(jsonb), public.crm_consumer_doc_delete(jsonb) to anon, authenticated;
notify pgrst, 'reload schema';

-- ROUND 63 (U33) — ek item ek baar: Inventory se online (naam, brand, model, warranty, baatein, specification) apne-aap; purani double jagahen saaf;
--                  online order: payment hote hi quotation se bill apne-aap. Dobara chalana safe hai.

-- 0) Supabase "DELETE ke liye WHERE chahiye" (pincode master) — pehle wala FIX-PIN-DELETE bhi yahin shamil
do $fix$ declare fn text; src text;
begin
  foreach fn in array array['public.sp_pin_master_load(text,jsonb,boolean)', 'public.sp_pin_master_clear(text)', 'public.sp_pin_rules_delete(text,jsonb)'] loop
    begin src := pg_get_functiondef(fn::regprocedure); exception when undefined_function then continue; end;
    if src ~ 'delete from public\.sp_pin_(master|rules);' then
      src := regexp_replace(src, 'delete from public\.(sp_pin_master|sp_pin_rules);', 'delete from public.\1 where true;', 'g');
      execute src;
    end if;
  end loop;
end $fix$;

-- 1) Specification padhne ke helper (CRM ke C.specPairs / C.specLine jaisa hi)
create or replace function public.crm__spec_pairs(sp jsonb) returns jsonb language plpgsql immutable as $f$
declare res jsonb := '[]'::jsonb; k text; i int := 0; n int := 0; seen text[] := '{}'; v text;
begin
  if sp is null or jsonb_typeof(sp) <> 'object' then return res; end if;
  begin n := coalesce((sp ->> '_n')::int, 0); exception when others then n := 0; end;
  if jsonb_typeof(sp -> '_o') = 'array' then
    for k in select jsonb_array_elements_text(sp -> '_o') loop
      if sp ? k and left(k, 1) <> '_' and not (k = any (seen)) then
        v := btrim(coalesce(sp ->> k, ''));
        if v <> '' then res := res || jsonb_build_array(jsonb_build_array(k, v, i < n)); end if;
        seen := seen || k; i := i + 1;
      end if;
    end loop;
  end if;
  for k in select x from jsonb_object_keys(sp) x order by x loop
    if left(k, 1) <> '_' and not (k = any (seen)) and k not in ('Product warranty (yrs)', 'Warranty (yrs)', 'Warranty') then
      v := btrim(coalesce(sp ->> k, ''));
      if v <> '' then res := res || jsonb_build_array(jsonb_build_array(k, v, false)); end if;
    end if;
  end loop;
  return res;
end $f$;

create or replace function public.crm__spec_val(k text, v text) returns text language plpgsql immutable as $f$
declare u text;
begin
  v := btrim(coalesce(v, '')); u := substring(k from '\(([^)]+)\)\s*$');
  if u is not null and v ~ '^[0-9.,[:space:]x×*]+$' then return case when u = '%' then v || '%' else v || ' ' || u end; end if;
  if u is null and v ~ '^[0-9.,]+$' then return regexp_replace(k, '\s*\([^)]*\)\s*$', '') || ': ' || v; end if;
  return v;
end $f$;

create or replace function public.crm__warranty_text(w text) returns text language plpgsql immutable as $f$
begin
  w := btrim(coalesce(w, '')); if w = '' then return ''; end if;
  if w ~ '^[0-9.]+$' then w := w || ' yrs'; end if;
  return case when w ~* 'warrant' then w else w || ' warranty' end;
end $f$;

create or replace function public.crm__spec_line(d jsonb) returns text language plpgsql immutable as $f$
declare parts text[] := '{}'; p jsonb; c int := 0; w text;
begin
  if btrim(coalesce(d ->> 'brand', '')) <> '' then parts := parts || btrim(d ->> 'brand'); end if;
  if btrim(coalesce(d ->> 'mpn', '')) <> '' then parts := parts || btrim(d ->> 'mpn'); end if;
  for p in select * from jsonb_array_elements(public.crm__spec_pairs(d -> 'specs')) loop
    exit when c >= 3;
    if (p ->> 2)::boolean then parts := parts || public.crm__spec_val(p ->> 0, p ->> 1); c := c + 1; end if;
  end loop;
  w := public.crm__warranty_text(d ->> 'warranty'); if w <> '' then parts := parts || w; end if;
  return array_to_string(parts, ' · ');
end $f$;

-- 2) CRM item ke jo fields Online Store / website par apne-aap jaate hain (Store Admin me dobara nahi bharne)
create or replace function public.crm__store_desc(d jsonb) returns text language plpgsql immutable as $f$
declare b text := ''; l text; pl text := ''; x jsonb;
begin
  for l in select btrim(z) from unnest(string_to_array(coalesce(d ->> 'desc', ''), E'\n')) z loop
    if l <> '' then b := b || case when b = '' then '' else E'\n' end || '• ' || l; end if;
  end loop;
  if coalesce(d ->> 'type', 'product') = 'project' then
    if jsonb_typeof(d -> 'proj_items') = 'array' and jsonb_array_length(d -> 'proj_items') > 0 then
      for x in select * from jsonb_array_elements(d -> 'proj_items') loop
        pl := pl || case when pl = '' then '' else E'\n' end || '• ' || btrim(coalesce(nullif(x ->> 'title', '') || ' – ', '') || coalesce(x ->> 'name', '')) || case when coalesce(x ->> 'qty', '1') not in ('1', '1.0', '') then ' × ' || (x ->> 'qty') else '' end;
      end loop;
      b := case when b <> '' then b || E'\n\n' else '' end || 'इस पैकेज में शामिल:' || E'\n' || pl;
    end if;
    if btrim(coalesce(d ->> 'kw', '')) <> '' then b := 'सिस्टम साइज़: ' || btrim(d ->> 'kw') || ' kW' || case when b <> '' then E'\n\n' || b else '' end; end if;
  end if;
  return b;
end $f$;

create or replace function public.crm__store_fields(d jsonb, ttl text) returns jsonb language sql immutable as $f$
  select jsonb_build_object(
    'title', coalesce(nullif(btrim(d ->> 'name'), ''), ttl, ''), 'titleEn', coalesce(nullif(btrim(d ->> 'name'), ''), ttl, ''),
    'brand', btrim(coalesce(d ->> 'brand', '')), 'model', btrim(coalesce(d ->> 'mpn', '')), 'sku', btrim(coalesce(d ->> 'sku', '')),
    'unit', btrim(coalesce(d ->> 'unit', '')), 'weight', public.crm_num(d -> 'weight'),
    'warranty', public.crm__warranty_text(d ->> 'warranty'), 'desc', public.crm__store_desc(d),
    'specs', public.crm__spec_pairs(d -> 'specs'), 'tagline', btrim(coalesce(d #>> '{store,tagline}', '')), 'cat', btrim(coalesce(d ->> 'category', '')))
$f$;

-- store data me CRM se jude (published) products: daam + ye sab fields CRM ke hisab se (admin ne kuch bhi bheja ho)
create or replace function public.sp__apply_crm_prices(d jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb;
begin
  if d is null or jsonb_typeof(d -> 'products') <> 'array' then return d; end if;
  select jsonb_agg(case when m.item_id is null then e.e else e.e || jsonb_build_object('mrp', m.nmrp, 'offer', m.noffer, 'gst', m.gst, 'crm', m.item_id) || m.fields end order by e.ord) into out_
  from jsonb_array_elements(d -> 'products') with ordinality as e(e, ord)
  left join lateral (
    select c.id as item_id, public.crm_num(c.data -> 'gst') as gst,
      case when public.crm_num(c.data -> 'mrp') > public.crm_price_incl(c.data) then public.crm_num(c.data -> 'mrp') else public.crm_price_incl(c.data) end as nmrp,
      case when public.crm_num(c.data -> 'mrp') > public.crm_price_incl(c.data) then public.crm_price_incl(c.data) else 0 end as noffer,
      public.crm__store_fields(c.data, c.title) as fields
    from public.crm_records c where c.kind = 'item' and c.deleted_at is null and (c.data #>> '{store,store_id}') = (e.e ->> 'id') and (c.data #>> '{store,status}') = 'published' and public.crm_price_incl(c.data) > 0
    order by c.id limit 1) m on true;
  return jsonb_set(d, '{products}', coalesce(out_, '[]'::jsonb));
end $$;

-- CRM me inme se kuch bhi badle to store me turant (sirf jab kuch badla ho; stock ki ginti se store nahi chhedta)
create or replace function public.crm_item_price_push_trg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (NEW.data #>> '{store,status}') = 'published' and coalesce(NEW.data #>> '{store,store_id}', '') <> '' and NEW.deleted_at is null
     and (TG_OP = 'INSERT' or (public.crm__store_fields(OLD.data, OLD.title), OLD.data -> 'price', OLD.data -> 'gst', OLD.data -> 'mrp', OLD.data #> '{store,store_id}', OLD.data #> '{store,status}')
          is distinct from (public.crm__store_fields(NEW.data, NEW.title), NEW.data -> 'price', NEW.data -> 'gst', NEW.data -> 'mrp', NEW.data #> '{store,store_id}', NEW.data #> '{store,status}')) then
    update public.sp_store set updated_at = now() where id = 'main';
  end if;
  return null;
end $$;

-- store par live hote hi CRM ki purani (kabhi na dikhne wali) photo hat jaati hai — photo ab sirf Store Admin me
create or replace function public.crm_item_drop_photos() returns trigger language plpgsql as $$
begin
  if (NEW.data #>> '{store,status}') = 'published' and (NEW.data ? 'images' or NEW.data ? 'image_link') then NEW.data := NEW.data - 'images' - 'image_link'; end if;
  return NEW;
end $$;
drop trigger if exists crm_item_drop_photos on public.crm_records;
create trigger crm_item_drop_photos before insert or update on public.crm_records for each row when (NEW.kind = 'item') execute function public.crm_item_drop_photos();


-- 3) Purani double jagahen saaf: warranty ek hi (specification wali alag nahi), "More Info" -> Khaas baatein, Title / Image link / extra categories / store offer hat gaye;
--    specification ko category ke order me rakha (mukhya fields pehle). Kuch bhi delete nahi hota jo ab bhi kaam ka ho.
create or replace function public.crm__spec_order() returns jsonb language sql immutable as $f$ select $j${"PNL":{"all":["Wattage (Wp)","Cell technology","DCR / Non-DCR","Efficiency (%)","Dimensions (mm)","Weight (kg)","Performance warranty (yrs)","Bifacial","No. of cells","Vmp (V)","Imp (A)","Voc (V)","Isc (A)","Temp. coefficient (Pmax)","Certification","Made in"],"n":7},"INV":{"all":["Capacity (kW)","Phase","No. of MPPT","Max PV input (kWp)","Efficiency (%)","Communication / WiFi","MPPT voltage range (V)","Max DC voltage (V)","IP rating","Battery support","Cooling","Certification","Made in"],"n":6},"BAT":{"all":["Battery type","Voltage (V)","Capacity (Ah)","Cycle life","Depth of discharge (%)","Energy (kWh)","Dimensions (mm)","Weight (kg)","Terminal","Made in"],"n":5},"STR":{"all":["Material","Coating / thickness","Wind speed rating (km/h)","Panels supported","Tilt angle","Mounting type","Fasteners material","Standard"],"n":4},"ADB":{"all":["Rating (A)","Strings / Phase","IP rating","SPD","Enclosure","MCB / MCCB make","Fuse","Input / Output","Standard"],"n":4},"ERT":{"all":["Earthing type","Electrode material","Electrode size","Length (m)","Chemical / Backfill","LA type","Resistance (Ohm)","Standard"],"n":4},"LGT":{"all":["Wattage (W)","Lumens (lm)","Solar panel (W)","Battery","Autonomy (hrs)","Sensor / Mode","IP rating","Pole / Mounting","Body material"],"n":5},"CAM":{"all":["Resolution (MP)","Connectivity","Solar panel (W)","Night vision","Storage","Battery (mAh)","Field of view","IP rating","App"],"n":5},"HAP":{"all":["Capacity (VA/kVA)","System voltage (V)","Wave form","Battery (Ah)","Charging current (A)","Display","Solar charge controller","Trolley included"],"n":4},"BOS":{"all":["Size / Rating","Material","Length / Qty per pack","Standard / Certification","Colour","Application"],"n":4},"MNT":{"all":["Plan duration","Visits per year","Plant size covered (kW)","Includes","Response time","Report / Audit","Terms"],"n":4},"_":{"all":["Size / Rating","Material","Length / Qty per pack","Colour","Standard / Certification","Application"],"n":4}}$j$::jsonb $f$;
create or replace function public.crm__cat_code(n text) returns text language sql immutable as $f$ select coalesce(($j${"Solar Panel/Solar Modules":"PNL","Solar Inverter":"INV","Solar Batteries":"BAT","Solar Structure":"STR","Solar ACDB/DCDB":"ADB","Chemical Earthings & LA":"ERT","Solar Lights":"LGT","Solar Cameras":"CAM","Home Appliances":"HAP","Solar BOS Materials":"BOS","Solar Maintenance & Package":"MNT"}$j$::jsonb) ->> btrim(coalesce(n, '')), '_') $f$;

create or replace function public.crm__item_clean(d jsonb) returns jsonb language plpgsql stable as $f$
declare sp jsonb; k text; w text; ord jsonb; code text; lst jsonb; keys text[]; present text[] := '{}'; o text[] := '{}'; kn int := 0; m text; ds text;
begin
  if d is null then return d; end if;
  if coalesce(d ->> 'type', 'product') = 'product' then
    sp := d -> 'specs';
    if jsonb_typeof(sp) = 'object' then
      w := btrim(coalesce(d ->> 'warranty', ''));
      foreach k in array array['Product warranty (yrs)', 'Warranty (yrs)', 'Warranty'] loop
        if sp ? k then
          if w = '' and btrim(coalesce(sp ->> k, '')) <> '' then w := btrim(sp ->> k); if w ~ '^[0-9.]+$' then w := w || ' yrs'; end if; end if;
          sp := sp - k;
        end if;
      end loop;
      if w <> '' then d := d || jsonb_build_object('warranty', w); end if;
      if not (sp ? '_o') then
        ord := public.crm__spec_order(); code := public.crm__cat_code(d ->> 'category'); lst := coalesce(ord -> code -> 'all', ord -> '_' -> 'all'); kn := coalesce((ord -> code ->> 'n')::int, (ord -> '_' ->> 'n')::int, 0);
        for k in select jsonb_array_elements_text(lst) loop
          if sp ? k and btrim(coalesce(sp ->> k, '')) <> '' then o := o || k; end if;
        end loop;
        for k in select x from jsonb_object_keys(sp) x order by x loop
          if left(k, 1) <> '_' and not (k = any (o)) and btrim(coalesce(sp ->> k, '')) <> '' then o := o || k; end if;
        end loop;
        if array_length(o, 1) is not null then
          select count(*) into kn from unnest(o) z where z in (select jsonb_array_elements_text(lst) limit kn);
          sp := sp || jsonb_build_object('_o', to_jsonb(o), '_n', kn);
        end if;
      end if;
      d := jsonb_set(d, '{specs}', sp);
    end if;
  end if;
  m := btrim(coalesce(d ->> 'more', ''));
  if m <> '' and position(m in coalesce(d ->> 'desc', '')) = 0 then d := d || jsonb_build_object('desc', case when btrim(coalesce(d ->> 'desc', '')) = '' then m else rtrim(d ->> 'desc') || E'\n' || m end); end if;
  d := d - 'more' - 'title' - 'image_link' - 'categories';
  if d #> '{store,offer}' is not null then d := jsonb_set(d, '{store}', (d -> 'store') - 'offer'); end if;
  return d;
end $f$;

do $mig$ declare r record; nd jsonb; sd jsonb; sp record; pr jsonb; w numeric; tg text; dd text;
begin
  perform set_config('sp.order_job', '1', true);
  for r in select id, data from public.crm_records where kind = 'item' and deleted_at is null loop
    nd := public.crm__item_clean(r.data);
    if nd is distinct from r.data then update public.crm_records set data = nd where id = r.id; end if;
  end loop;
  -- Store Admin me jo weight / tagline / baatein pehle alag bhari thi, CRM me khali ho to wahin se le aao (CRM ab authority hai)
  select data into sd from public.sp_store where id = 'main';
  if sd is not null and jsonb_typeof(sd -> 'products') = 'array' then
    for r in select c.id, c.data from public.crm_records c where c.kind = 'item' and c.deleted_at is null and c.data #>> '{store,status}' = 'published' loop
      select e into pr from jsonb_array_elements(sd -> 'products') e where e ->> 'id' = r.data #>> '{store,store_id}' limit 1;
      if pr is null then continue; end if;
      nd := r.data;
      if public.crm_num(nd -> 'weight') <= 0 and public.crm_num(pr -> 'weight') > 0 then nd := nd || jsonb_build_object('weight', public.crm_num(pr -> 'weight')); end if;
      if btrim(coalesce(nd #>> '{store,tagline}', '')) = '' and btrim(coalesce(pr ->> 'tagline', '')) <> '' then nd := jsonb_set(nd, '{store}', coalesce(nd -> 'store', '{}'::jsonb) || jsonb_build_object('tagline', btrim(pr ->> 'tagline'))); end if;
      if coalesce(nd ->> 'type', 'product') = 'product' and btrim(coalesce(nd ->> 'desc', '')) = '' and btrim(coalesce(pr ->> 'desc', '')) <> '' then
        dd := regexp_replace(pr ->> 'desc', '(^|\n)\s*[•\-\*]\s*', E'\\1', 'g'); nd := nd || jsonb_build_object('desc', btrim(dd));
      end if;
      if nd is distinct from r.data then update public.crm_records set data = nd where id = r.id; end if;
    end loop;
  end if;
  perform set_config('sp.order_job', '', true);
end $mig$;

-- 4) Online order ka Kaam (quotation) ab har line par chhoti spec-line ke saath banta hai
do $u$ declare src text;
begin
  src := pg_get_functiondef('public.crm__order_job(bigint,bigint)'::regprocedure);
  if position('crm__spec_line' in src) = 0 then
    src := replace(src, $a$jsonb_build_object('kind', 'product', 'category', c.data ->> 'category',$a$, $b$jsonb_build_object('kind', 'product', 'spec', public.crm__spec_line(c.data), 'category', c.data ->> 'category',$b$);
    if position('crm__spec_line' in src) = 0 then raise exception 'U33: crm__order_job me jagah nahi mili'; end if;
    execute src;
  end if;
end $u$;

-- 5) ONLINE ORDER: payment hote hi quotation se bill apne-aap (staff ko "Bill banayein" nahi dabana). Quotation sirf tab tak jab tak payment nahi aayi.
create or replace function public.crm__order_bill(p_oid bigint) returns bigint language plpgsql security definer set search_path = public as $f$
declare o public.sp_orders; q public.crm_records; tok text := 'ORDBILL-' || md5(random()::text || clock_timestamp()::text); inv jsonb; iid bigint; amt numeric; mode_ text;
begin
  select * into o from public.sp_orders where id = p_oid;
  if o.id is null or o.status = 'cancelled' then return null; end if;
  perform pg_advisory_xact_lock(7330000 + p_oid);
  select * into q from public.crm_records where kind = 'quote' and deleted_at is null and (data ->> 'order_id') = p_oid::text order by id limit 1;
  if q.id is null then return null; end if;
  if q.status = 'converted' then return nullif(q.data ->> 'invoice_id', '')::bigint; end if;
  amt := case when o.data ->> 'payment' = 'cod' then public.crm_num(o.data -> 'advance') else public.crm_num(o.data -> 'total') end;
  mode_ := case when o.data ->> 'payment' = 'cod' then 'UPI (advance)' else 'UPI' end;
  insert into public.crm_sessions(token, user_id, role, expires_at) values (tok, 0, 'admin', now() + interval '2 minutes');
  begin
    inv := public.crm_convert(jsonb_build_object('token', tok, 'id', q.id));
    iid := (inv ->> 'id')::bigint;
    if amt > 0 and o.status = 'paid' then
      perform public.crm_save(jsonb_build_object('token', tok, 'kind', 'payment', 'party_id', q.party_id, 'data', jsonb_strip_nulls(jsonb_build_object('amount', least(amt, public.crm_num(inv -> 'amount')), 'date', public.crm_today()::text, 'mode', mode_, 'utr', nullif(o.data ->> 'utr', ''), 'note', 'Online order ' || coalesce(o.data ->> 'order_no', '#' || o.id) || ' — payment verify hote hi apne-aap', 'invoice_id', iid::text, 'invoice_ref', inv ->> 'ref'))));
      perform public.crm_inv_recalc(iid);
    end if;
  exception when others then delete from public.crm_sessions where token = tok; raise; end;
  delete from public.crm_sessions where token = tok;
  insert into public.crm_activity(user_id, user_name, role, action, kind, rec_id, summary) values (0, 'Online order', 'admin', 'order_bill', 'invoice', iid, 'Online order ka bill ban gaya: ' || coalesce(inv ->> 'ref', '') || ' (order ' || coalesce(o.data ->> 'order_no', '#' || o.id) || ')');
  return iid;
end $f$;
revoke all on function public.crm__order_bill(bigint) from public, anon, authenticated;

-- COD: maal pahunchne (delivered) par baaki raqam ka payment bhi apne-aap likh do
create or replace function public.crm__order_cod_close(p_oid bigint) returns void language plpgsql security definer set search_path = public as $f$
declare o public.sp_orders; inv public.crm_records; tok text := 'ORDCOD-' || md5(random()::text || clock_timestamp()::text); bal numeric;
begin
  select * into o from public.sp_orders where id = p_oid; if o.id is null or o.data ->> 'payment' <> 'cod' then return; end if;
  select * into inv from public.crm_records where kind = 'invoice' and deleted_at is null and (data ->> 'order_id') = p_oid::text order by id limit 1;
  if inv.id is null then return; end if;
  bal := greatest(inv.amount - coalesce((select sum(amount) from public.crm_records where kind = 'payment' and deleted_at is null and (data ->> 'invoice_id') = inv.id::text), 0), 0);
  if bal <= 0.009 then return; end if;
  insert into public.crm_sessions(token, user_id, role, expires_at) values (tok, 0, 'admin', now() + interval '2 minutes');
  begin
    perform public.crm_save(jsonb_build_object('token', tok, 'kind', 'payment', 'party_id', inv.party_id, 'data', jsonb_build_object('amount', bal, 'date', public.crm_today()::text, 'mode', 'COD (delivery par)', 'note', 'Online order ' || coalesce(o.data ->> 'order_no', '#' || o.id) || ' — COD, maal pahunchne par', 'invoice_id', inv.id::text, 'invoice_ref', inv.ref)));
    perform public.crm_inv_recalc(inv.id);
  exception when others then delete from public.crm_sessions where token = tok; raise; end;
  delete from public.crm_sessions where token = tok;
end $f$;
revoke all on function public.crm__order_cod_close(bigint) from public, anon, authenticated;

create or replace function public.sp_orders_bill_trg() returns trigger language plpgsql security definer set search_path = public as $f$
begin
  if new.status = 'paid' and old.status is distinct from 'paid' then
    begin perform public.crm__order_bill(new.id); exception when others then raise warning 'order bill: %', sqlerrm; end;
  end if;
  if new.status = 'delivered' and old.status is distinct from 'delivered' then
    begin perform public.crm__order_bill(new.id); perform public.crm__order_cod_close(new.id); exception when others then raise warning 'order cod close: %', sqlerrm; end;
  end if;
  return new;
end $f$;
drop trigger if exists sp_orders_bill on public.sp_orders;
create trigger sp_orders_bill after update of status on public.sp_orders for each row execute function public.sp_orders_bill_trg();

-- 6) Customer hub: online order ka document "Order bill" dikhe, "Quotation" nahi; bill ban jaye to sirf bill; bill / order bill me item ki chhoti line
do $u$ declare src text;
begin
  src := pg_get_functiondef('public.crm_consumer_profile(jsonb)'::regprocedure);
  if position('''online'', (q.data ? ''order_id'')' in src) = 0 then
    src := replace(src, $a$card := card || jsonb_build_object('kind', k,$a$, $b$card := card || jsonb_build_object('online', (q.data ? 'order_id'), 'kind', k,$b$);
    if position('''online'', (q.data ? ''order_id'')' in src) = 0 then raise exception 'U33: crm_consumer_profile me jagah nahi mili'; end if;
    execute src;
  end if;
  src := pg_get_functiondef('public.crm_consumer_plant_doc(jsonb)'::regprocedure);
  if position('''online'', (q.data ? ''order_id'')' in src) = 0 then
    src := replace(src, $a$'hsn', l ->> 'hsn', 'kind', l ->> 'kind',$a$, $b$'hsn', l ->> 'hsn', 'spec', l ->> 'spec', 'kind', l ->> 'kind',$b$);
    src := replace(src, $a$'ctype', src.data ->> 'ctype',$a$, $b$'online', (q.data ? 'order_id'), 'ctype', src.data ->> 'ctype',$b$);
    if position('''online'', (q.data ? ''order_id'')' in src) = 0 or position('''spec'', l ->> ''spec''' in src) = 0 then raise exception 'U33: crm_consumer_plant_doc me jagah nahi mili'; end if;
    execute src;
  end if;
  src := pg_get_functiondef('public.crm_consumer_bill_doc(jsonb)'::regprocedure);
  if position('''spec'', l ->> ''spec''' in src) = 0 then
    src := replace(src, $a$'hsn', l ->> 'hsn', 'kind', l ->> 'kind',$a$, $b$'hsn', l ->> 'hsn', 'spec', l ->> 'spec', 'kind', l ->> 'kind',$b$);
    if position('''spec'', l ->> ''spec''' in src) = 0 then raise exception 'U33: crm_consumer_bill_doc me jagah nahi mili'; end if;
    execute src;
  end if;
  src := pg_get_functiondef('public.crm_plant_card(public.crm_records)'::regprocedure);
  if position('''online'', (q.data ? ''order_id'')' in src) = 0 then
    src := replace(src, $a$'has_bill', inv.id is not null,$a$, $b$'has_bill', inv.id is not null, 'online', (q.data ? 'order_id'),$b$);
    if position('''online'', (q.data ? ''order_id'')' in src) = 0 then raise exception 'U33: crm_plant_card me jagah nahi mili'; end if;
    execute src;
  end if;
end $u$;

notify pgrst, 'reload schema';
