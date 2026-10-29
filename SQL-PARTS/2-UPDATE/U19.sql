-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 19 of 30
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U30). Safe to re-run.
-- ============================================================================

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