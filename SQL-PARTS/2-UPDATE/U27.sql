-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 27 of 30
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U30). Safe to re-run.
-- ============================================================================

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