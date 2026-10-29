-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 25 of 30
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U30). Safe to re-run.
-- ============================================================================

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