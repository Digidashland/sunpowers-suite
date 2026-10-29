-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 22 of 30
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U30). Safe to re-run.
-- ============================================================================

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