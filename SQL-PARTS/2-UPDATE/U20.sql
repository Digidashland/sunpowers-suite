-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 20 of 30
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U30). Safe to re-run.
-- ============================================================================

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