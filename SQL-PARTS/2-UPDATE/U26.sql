-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 26 of 30
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U30). Safe to re-run.
-- ============================================================================

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