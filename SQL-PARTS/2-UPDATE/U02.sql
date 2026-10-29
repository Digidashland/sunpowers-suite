-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 2 of 30
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U30). Safe to re-run.
-- ============================================================================

-- ============================================================================
-- Grants
-- ============================================================================
do $g$
declare f text;
begin
  foreach f in array array['public.sp_blueprint_submit(jsonb)', 'public.sp_tool_use(jsonb)', 'public.crm_blueprint_save(jsonb)', 'public.crm_blueprint_list(jsonb)', 'public.crm_blueprint_get(jsonb)', 'public.crm_blueprint_delete(jsonb)',
    'public.crm_blueprint_cfg(jsonb)', 'public.crm_conn_get(jsonb)', 'public.crm_conn_save(jsonb)', 'public.crm_items_bulk_delete(jsonb)', 'public.crm_items_bulk_update(jsonb)', 'public.crm_to_store(jsonb)']
  loop
    execute 'revoke all on function ' || f || ' from public';
    execute 'grant execute on function ' || f || ' to anon, authenticated';
  end loop;
  execute 'revoke all on function public.crm_conn_val(text, text) from public, anon, authenticated';
  execute 'revoke all on function public.crm_conn_on(text) from public, anon, authenticated';
  execute 'revoke all on function public.crm_alert(text, jsonb) from public, anon, authenticated';
  execute 'revoke all on function public.crm_bp_role_ok(public.crm_ses) from public, anon, authenticated';
end $g$;
-- ============================================================
-- Sunpowers — Website Admin (edit the website without code)
-- Safe to run more than once. Stores everything in ONE extra row (id = 'web') of sp_store;
-- the Online Store data (id = 'main') is never touched.
-- ============================================================
create or replace function public.sp_get_web()
returns jsonb language sql stable security definer
set search_path = public as $$
  select data from public.sp_store where id = 'web';
$$;

create or replace function public.sp_save_web(p_pass text, p_data jsonb)
returns timestamptz language plpgsql security definer
set search_path = public, extensions as $$
declare t timestamptz := now();
begin
  perform public.sp_check(p_pass);
  if p_data is null or jsonb_typeof(p_data) <> 'object' then raise exception 'Invalid data'; end if;
  if length(p_data::text) > 1500000 then raise exception 'Website data too large'; end if;
  insert into public.sp_store(id, data, updated_at) values ('web', p_data, t)
  on conflict (id) do update set data = excluded.data, updated_at = excluded.updated_at;
  return t;
end $$;

do $$ begin
  grant execute on function public.sp_get_web(), public.sp_save_web(text, jsonb) to anon, authenticated;
exception when undefined_object then null; end $$;

-- ============================================================================
-- ROUND 8 (database) — run AFTER crm-setup.sql, phase1, phase2-3, phase4. Safe to re-run.
--  1) Store order gets a number from the SAME server series (ORD/2026-27/0001)
--  2) Quotation / Bill / Purchase lines MUST come from Inventory (guard)
--  3) Safe uploads: only an admin-issued short-lived token can upload to storage
--  4) Clean-up (old quotations / closed enquiries) + storage meter
--  5) Dashboard graph data (business / leads / marketing / store / maintenance)
--  6) Maintenance & Audit: contracts, visit-done (stock + next date), default checklist + plans
-- ============================================================================

-- (1) --------------------------------------------------------------------------------

create or replace function public.sp_order_no(p_id bigint, p_token text) returns text
language plpgsql stable security definer set search_path = public as $$
declare u public.crm_users; o public.sp_orders;
begin
  u := public.crm_csession(p_token);
  select * into o from public.sp_orders where id = p_id and data ->> 'customer_id' = u.id::text;
  return o.data ->> 'order_no';
end $$;
do $$ begin grant execute on function public.sp_order_no(bigint, text) to anon, authenticated; exception when undefined_object then null; end $$;

-- consumer account shows the same order number
create or replace function public.crm_consumer_me(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token');
begin
  return jsonb_build_object('id', u.id, 'name', u.name, 'mobile', u.mobile, 'email', u.email, 'username', u.username, 'meta', coalesce(u.meta, '{}'::jsonb), 'created_at', u.created_at,
    'orders', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'order_no', o.data ->> 'order_no', 'created_at', o.created_at, 'status', o.status, 'total', o.data -> 'total', 'advance', o.data -> 'advance', 'payment', o.data ->> 'payment',
        'items', (select coalesce(jsonb_agg(jsonb_build_object('title', i ->> 'title', 'qty', i -> 'qty', 'amount', i -> 'amount')), '[]'::jsonb) from jsonb_array_elements(coalesce(o.data -> 'items', '[]'::jsonb)) i)) order by o.id desc)
      from (select * from public.sp_orders where (data ->> 'phone') = u.mobile or (data ->> 'customer_id') = u.id::text order by id desc limit 100) o), '[]'::jsonb),
    'enquiries', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'created_at', e.created_at, 'status', e.status, 'type', e.data ->> 'type', 'subject', e.data ->> 'subject', 'message', e.data ->> 'message') order by e.id desc)
      from (select * from public.sp_enquiries where (data ->> 'phone') = u.mobile or (data ->> 'customer_id') = u.id::text order by id desc limit 50) e), '[]'::jsonb));
end $$;

-- (2) --------------------------------------------------------------------------------
create or replace function public.crm_lines_guard() returns trigger language plpgsql as $$
declare l jsonb;
begin
  if coalesce(current_setting('sp.restoring', true), '') = 'on' then return new; end if;
  if new.kind in ('quote', 'invoice', 'purchase') and new.deleted_at is null and jsonb_typeof(new.data -> 'lines') = 'array' then
    for l in select * from jsonb_array_elements(new.data -> 'lines') loop
      if coalesce(l ->> 'kind', 'product') <> 'project' and coalesce(l ->> 'item_id', '') = '' then
        raise exception 'Har item Inventory se hi chunna hoga — "%" Inventory me nahi hai. Pehle Inventory me jodein.', coalesce(nullif(l ->> 'name', ''), '?');
      end if;
      if coalesce(l ->> 'item_id', '') <> '' and not exists (select 1 from public.crm_records i where i.id = (l ->> 'item_id')::bigint and i.kind = 'item') then
        raise exception '"%" Inventory me nahi mila (delete ho gaya?). Item dobara chunein.', coalesce(nullif(l ->> 'name', ''), '?');
      end if;
    end loop;
  end if;
  return new;
end $$;
drop trigger if exists crm_lines_guard on public.crm_records;
create trigger crm_lines_guard before insert or update of data on public.crm_records for each row execute function public.crm_lines_guard();

-- (3) --------------------------------------------------------------------------------
create table if not exists public.sp_upload_tokens (token text primary key, exp timestamptz not null);
alter table public.sp_upload_tokens enable row level security;
revoke all on public.sp_upload_tokens from anon, authenticated;

create or replace function public.sp_admin_upload_token(p_pass text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare t text := encode(gen_random_bytes(12), 'hex');
begin
  perform public.sp_check(p_pass);
  delete from public.sp_upload_tokens where exp < now();
  insert into public.sp_upload_tokens(token, exp) values (t, now() + interval '8 hours');
  return t;
end $$;

create or replace function public.sp_upload_ok(p_name text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.sp_upload_tokens where token = split_part(p_name, '/', 2) and exp > now());
$$;
do $$ begin
  grant execute on function public.sp_admin_upload_token(text), public.sp_upload_ok(text) to anon, authenticated;
exception when undefined_object then null; end $$;

do $$ begin
  begin
    update storage.buckets set file_size_limit = 52428800,
      allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm','application/pdf']
    where id = 'sp-images';
  exception when others then null; end;
  begin
    drop policy if exists "sp images upload" on storage.objects;
    create policy "sp images upload" on storage.objects
      for insert to anon, authenticated with check (bucket_id = 'sp-images' and public.sp_upload_ok(name));
  exception when others then raise notice 'Storage policy skipped: %', sqlerrm; end;
exception when others then null; end $$;

-- (4) --------------------------------------------------------------------------------
create or replace function public.crm_storage_stats(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token');
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin'; end if;
  return jsonb_build_object(
    'db_bytes', pg_database_size(current_database()),
    'files_bytes', coalesce((select sum(size) from public.crm_files), 0), 'files_n', (select count(*) from public.crm_files),
    'quotes_n', (select count(*) from public.crm_records where kind = 'quote' and deleted_at is null),
    'invoices_n', (select count(*) from public.crm_records where kind = 'invoice' and deleted_at is null),
    'enquiries_n', (select count(*) from public.sp_enquiries),
    'orders_n', (select count(*) from public.sp_orders));
end $$;

create or replace function public.crm_purge(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); days int := least(greatest(coalesce(nullif(p ->> 'days', '')::int, 90), 7), 3650);
        run boolean := coalesce(p ->> 'run', '') = 'true'; cut timestamptz; nq int; ne int; nd int := 0;
begin
  if not public.crm_is_admin(s) then raise exception 'Sirf Admin safai kar sakta hai'; end if;
  cut := now() - make_interval(days => days);
  -- old quotations that never became a bill (bills, payments and customers are NEVER touched)
  select count(*) into nq from public.crm_records q where q.kind = 'quote' and q.created_at < cut and q.status in ('draft', 'sent', 'rejected')
    and not exists (select 1 from public.crm_records i where i.kind = 'invoice' and i.deleted_at is null and i.data ->> 'quote_id' = q.id::text);
  select count(*) into ne from public.sp_enquiries where status in ('closed', 'cancelled') and created_at < cut;
  if run then
    delete from public.crm_records q where q.kind = 'quote' and q.created_at < cut and q.status in ('draft', 'sent', 'rejected')
      and not exists (select 1 from public.crm_records i where i.kind = 'invoice' and i.deleted_at is null and i.data ->> 'quote_id' = q.id::text);
    delete from public.sp_enquiries where status in ('closed', 'cancelled') and created_at < cut;
    delete from public.crm_otps where created_at < now() - interval '7 days';
    delete from public.crm_mail_log where at < now() - interval '60 days';
    perform public.crm_log(s, 'purge', 'quote', 0, 'Safai: ' || nq || ' purani quotation, ' || ne || ' band enquiry (' || days || ' din se purani)');
  end if;
  return jsonb_build_object('quotes', nq, 'enquiries', ne, 'days', days, 'done', run);
end $$;

-- (5) --------------------------------------------------------------------------------
create or replace function public.crm_series(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); n int := least(greatest(coalesce(nullif(p ->> 'months', '')::int, 12), 3), 24);
        m_end date := date_trunc('month', public.crm_today())::date; m0 date; mk jsonb; res jsonb;
        mkt text := 'insta|face|fb|meta|google|justdial|^jd|indiamart|trade|sulekha|youtube|website|online|ads|whatsapp|exporters';
begin
  m0 := (m_end - make_interval(months => n - 1))::date;
  select jsonb_agg(to_char(g, 'YYYY-MM') order by g) into mk from generate_series(m0::timestamp, m_end::timestamp, interval '1 month') g;
  res := jsonb_build_object('months', mk);
  if public.crm_can(s, 'invoices.view_all') or public.crm_can(s, 'invoices.create') then
    res := res || jsonb_build_object('business', (select jsonb_agg(jsonb_build_object('m', mo,
      'sales', (select coalesce(sum(r.amount), 0) from public.crm_records r where r.kind = 'invoice' and r.deleted_at is null and to_char(r.created_at at time zone 'Asia/Kolkata', 'YYYY-MM') = mo and public.crm_vis(s, r)),
      'collected', (select coalesce(sum(r.amount), 0) from public.crm_records r where r.kind = 'payment' and r.deleted_at is null and to_char(r.due_at, 'YYYY-MM') = mo and public.crm_vis(s, r)),
      'quotes', (select coalesce(sum(r.amount), 0) from public.crm_records r where r.kind = 'quote' and r.deleted_at is null and to_char(r.created_at at time zone 'Asia/Kolkata', 'YYYY-MM') = mo and public.crm_vis(s, r))
    ) order by mo) from jsonb_array_elements_text(mk) mo));
  end if;
  if public.crm_can(s, 'leads.view_all') or public.crm_can(s, 'leads.create') then
    res := res || jsonb_build_object('leads', (select jsonb_agg(jsonb_build_object('m', mo,
      'new', (select count(*) from public.crm_records r where r.kind = 'lead' and r.deleted_at is null and to_char(r.created_at at time zone 'Asia/Kolkata', 'YYYY-MM') = mo and public.crm_vis(s, r)),
      'won', (select count(*) from public.crm_records r where r.kind = 'lead' and r.status = 'won' and r.deleted_at is null and to_char(r.created_at at time zone 'Asia/Kolkata', 'YYYY-MM') = mo and public.crm_vis(s, r))
    ) order by mo) from jsonb_array_elements_text(mk) mo));
  end if;
  if public.crm_can(s, 'marketing.leads') then
    res := res || jsonb_build_object('marketing', (select jsonb_agg(jsonb_build_object('m', mo,
      'leads', (select count(*) from public.crm_records r where r.kind = 'lead' and r.deleted_at is null and lower(coalesce(r.data ->> 'source', '')) ~ mkt and to_char(r.created_at at time zone 'Asia/Kolkata', 'YYYY-MM') = mo),
      'won', (select count(*) from public.crm_records r where r.kind = 'lead' and r.status = 'won' and r.deleted_at is null and lower(coalesce(r.data ->> 'source', '')) ~ mkt and to_char(r.created_at at time zone 'Asia/Kolkata', 'YYYY-MM') = mo)
    ) order by mo) from jsonb_array_elements_text(mk) mo));
  end if;
  if public.crm_can(s, 'orders.view') then
    res := res || jsonb_build_object('store', (select jsonb_agg(jsonb_build_object('m', mo,
      'orders', (select count(*) from public.sp_orders o where to_char(o.created_at at time zone 'Asia/Kolkata', 'YYYY-MM') = mo and o.status <> 'cancelled'),
      'amount', (select coalesce(sum(public.crm_num(o.data -> 'total')), 0) from public.sp_orders o where to_char(o.created_at at time zone 'Asia/Kolkata', 'YYYY-MM') = mo and o.status <> 'cancelled'),
      'enquiries', (select count(*) from public.sp_enquiries e where to_char(e.created_at at time zone 'Asia/Kolkata', 'YYYY-MM') = mo)
    ) order by mo) from jsonb_array_elements_text(mk) mo));
  end if;
  if public.crm_can(s, 'items.view') or public.crm_can(s, 'reminders.view_all') then
    res := res || jsonb_build_object('maintenance', (select jsonb_agg(jsonb_build_object('m', mo,
      'planned', (select count(*) from public.crm_records r where r.kind = 'reminder' and r.deleted_at is null and r.data ->> 'maint' = 'true' and to_char(r.due_at, 'YYYY-MM') = mo and public.crm_vis(s, r)),
      'done', (select count(*) from public.crm_records r where r.kind = 'reminder' and r.deleted_at is null and r.data ->> 'maint' = 'true' and r.status = 'done' and to_char(r.due_at, 'YYYY-MM') = mo and public.crm_vis(s, r))
    ) order by mo) from jsonb_array_elements_text(mk) mo));
  end if;
  return res;
end $$;

-- (6) --------------------------------------------------------------------------------
create or replace function public.crm_months_of(p_period text) returns int language sql immutable as $$
  select case lower(coalesce(p_period, '')) when 'monthly' then 1 when 'quarterly' then 3 when 'half' then 6 when 'halfyearly' then 6 when 'yearly' then 12 else 6 end $$;

create or replace function public.crm_maint_contract(p jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); ex public.crm_records; pl public.crm_records; months int; yrs int; total int; i int;
        cid text := 'MC-' || encode(gen_random_bytes(4), 'hex'); start_ date; checks jsonb := '[]'::jsonb; pname text; cost numeric := 0; asg bigint := coalesce(nullif(p ->> 'assigned_to', '')::bigint, (s).uid); c jsonb; ck public.crm_records;
begin
  if not (public.crm_can(s, 'customers.create') or public.crm_can(s, 'customers.edit') or public.crm_can(s, 'items.view') or public.crm_is_admin(s)) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  select * into ex from public.crm_records where id = (p ->> 'party_id')::bigint and kind = 'party';
  if not public.crm_vis(s, ex) then raise exception 'Customer nahi mila'; end if;
  begin start_ := (p ->> 'start')::date; exception when others then raise exception 'Sahi tareekh chunein'; end;
  if start_ is null then raise exception 'Pehli visit ki tareekh chunein'; end if;
  select * into pl from public.crm_records where id = nullif(p ->> 'plan_id', '')::bigint and kind = 'item' and deleted_at is null and data ->> 'type' = 'maintenance';
  if pl.id is null then raise exception 'Plan chunein (Maintenance & Audit Packages me plan banayein)'; end if;
  pname := pl.title; months := public.crm_months_of(pl.data ->> 'period');
  yrs := least(greatest(coalesce(nullif(pl.data ->> 'years', '')::int, 1), 1), 10);
  total := least(greatest(ceil(12.0 / months * yrs)::int, 1), 120);
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
      jsonb_build_object('type', 'amc', 'maint', true, 'contract_id', cid, 'plan_id', pl.id, 'plan_name', pname, 'free', coalesce((pl.data ->> 'free')::boolean, false), 'months', months,
        'visit_no', i + 1, 'visits_total', total, 'checks', checks, 'visit_cost', cost, 'mobile', coalesce(ex.mobile, ''), 'party_name', ex.title, 'title', 'Solar service — ' || ex.title),
      lower('solar service ' || ex.title || ' ' || pname), (s).uid);
  end loop;
  perform public.crm_log(s, 'create', 'maintenance', ex.id, 'Maintenance & Audit: ' || pname || ' → ' || ex.title || ' (' || total || ' visits)');
  return jsonb_build_object('ok', true, 'contract_id', cid, 'visits', total, 'first_due', start_);
end $$;

create or replace function public.crm_maint_done(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records; done_on date; ticked jsonb; c jsonb; tot numeric := 0; months int; k int := 0; nxt public.crm_records; nd date; first_next date; mats int := 0;
begin
  select * into r from public.crm_records where id = (p ->> 'id')::bigint and kind = 'reminder' and data ->> 'maint' = 'true';
  if r.id is null or not public.crm_vis(s, r) then raise exception 'Visit nahi mili'; end if;
  if r.status = 'done' then raise exception 'Ye visit pehle hi ho chuki hai'; end if;
  begin done_on := coalesce(nullif(p ->> 'done_on', '')::date, public.crm_today()); exception when others then raise exception 'Sahi tareekh chunein'; end;
  ticked := case when jsonb_typeof(p -> 'ticked') = 'array' then p -> 'ticked' else null end;
  for c in select * from jsonb_array_elements(coalesce(r.data -> 'checks', '[]'::jsonb)) loop
    if ticked is null or ticked @> to_jsonb((c ->> 'id')::text) or ticked @> to_jsonb((c ->> 'id')::bigint) then
      tot := tot + public.crm_num(c -> 'cost');
      if nullif(c ->> 'mat_id', '') is not null and public.crm_num(c -> 'mat_qty') > 0 then
        update public.crm_records set data = jsonb_set(data, '{stock}', to_jsonb(public.crm_num(data -> 'stock') - public.crm_num(c -> 'mat_qty'))), updated_at = now()
          where id = (c ->> 'mat_id')::bigint and kind = 'item' and data ? 'stock';
        mats := mats + 1;
      end if;
    end if;
  end loop;
  update public.crm_records set status = 'done', updated_at = now(),
    data = data || jsonb_build_object('done_on', done_on, 'done_cost', tot, 'done_ticked', coalesce(ticked, '[]'::jsonb), 'done_note', left(coalesce(p ->> 'note', ''), 500), 'done_by', (s).name)
    where id = r.id;
  -- next visits move forward from the actual service date
  months := coalesce(nullif(r.data ->> 'months', '')::int, 6);
  for nxt in select * from public.crm_records x where x.kind = 'reminder' and x.deleted_at is null and x.status = 'open' and x.data ->> 'contract_id' = r.data ->> 'contract_id'
      and coalesce((x.data ->> 'visit_no')::int, 0) > coalesce((r.data ->> 'visit_no')::int, 0) order by (x.data ->> 'visit_no')::int loop
    k := k + 1; nd := (done_on + make_interval(months => k * months))::date;
    update public.crm_records set due_at = nd, updated_at = now() where id = nxt.id;
    if k = 1 then first_next := nd; end if;
  end loop;
  perform public.crm_log(s, 'done', 'maintenance', r.id, 'Visit ho gayi: ' || r.title || ' (' || coalesce(r.data ->> 'plan_name', '') || ')');
  return jsonb_build_object('ok', true, 'cost', tot, 'next_due', first_next, 'materials', mats);
end $$;

-- default Maintenance & Audit checklist + plans (inserted once; afterwards fully controlled from Inventory)
create or replace function public.crm_seed_maint() returns void language plpgsql security definer set search_path = public as $$
declare ids jsonb := '{}'::jsonb; rec record; nid bigint; ck jsonb;
begin
  if coalesce((select (data ->> 'seeded_maint')::boolean from public.crm_settings where id = 1), false) then return; end if;
  if exists (select 1 from public.crm_records where kind = 'item' and data ->> 'type' = 'mcheck' and deleted_at is null) then return; end if;
  for rec in select * from (values
    ('clean',  'Solar panel cleaning',                         300, 'Panels ki safai (pani / brush)'),
    ('visual', 'Visual & physical inspection',                 100, 'Panel, structure, nut-bolt, crack / hot-spot ki nazar se jaanch'),
    ('inv',    'Inverter check (error log, display, firmware)',200, 'Inverter ka error log, display aur firmware'),
    ('earth',  'Earthing resistance test',                     300, 'Earthing pit ka resistance naapna'),
    ('acdb',   'ACDB check & tightening',                      200, 'AC distribution box, MCB, tightening'),
    ('dcdb',   'DCDB check & tightening',                      200, 'DC distribution box, fuse, SPD, tightening'),
    ('cable',  'Cable & MC4 connector check',                  200, 'Cable, MC4 connector aur joint ki jaanch'),
    ('shadow', 'Shadow & structure check',                     100, 'Naye shadow / structure ka jhukaav'),
    ('lightn', 'Lightning arrestor check',                     150, 'Lightning arrestor aur grounding'),
    ('report', 'Generation report',                            100, 'Meter / app se generation ka report'),
    ('iv',     'IV curve / thermography audit',                800, 'Performance audit (advanced)')
  ) as t(code, nm, cost, descr) loop
    insert into public.crm_records(kind, title, status, owner_id, amount, data, search)
    values ('item', rec.nm, 'active', 0, rec.cost, jsonb_build_object('type', 'mcheck', 'name', rec.nm, 'title', '', 'cost', rec.cost, 'price', rec.cost, 'unit', 'Visit', 'gst', 18, 'category', 'Maintenance & Audit', 'desc', rec.descr, 'material_item_id', '', 'material_qty', 0), lower(rec.nm))
    returning id into nid;
    ids := ids || jsonb_build_object(rec.code, nid);
  end loop;
  -- plans: name, period, years, price (0 = free), checklist codes
  for rec in select * from (values
    ('Free Basic Check (1 visit / saal)',      'yearly',    1,    0, 'visual,report',                                 true,  'Free: saal me 1 baar nazar se jaanch aur generation report'),
    ('Silver AMC (Half-yearly)',               'half',      1, 1600, 'clean,visual,inv,report',                       false, 'Saal me 2 visits: safai, jaanch, inverter, report'),
    ('Gold AMC (Quarterly)',                   'quarterly', 1, 4800, 'clean,visual,inv,earth,acdb,dcdb,cable,report', false, 'Saal me 4 visits: safai + poora electrical check'),
    ('Platinum Audit (Quarterly + IV audit)',  'quarterly', 1, 7200, 'clean,visual,inv,earth,acdb,dcdb,cable,shadow,lightn,report,iv', false, 'Saal me 4 visits + performance audit')
  ) as t(nm, per, yrs, price, codes, fr, descr) loop
    select jsonb_agg((ids ->> c)::bigint) into ck from unnest(string_to_array(rec.codes, ',')) c;
    insert into public.crm_records(kind, title, status, owner_id, amount, data, search)
    values ('item', rec.nm, 'active', 0, rec.price, jsonb_build_object('type', 'maintenance', 'name', rec.nm, 'title', '', 'category', 'Maintenance', 'price', rec.price, 'gst', 18, 'unit', 'Plan', 'period', rec.per, 'years', rec.yrs,
      'visits', case rec.per when 'quarterly' then 4 when 'half' then 2 when 'monthly' then 12 else 1 end, 'free', rec.fr, 'checklist', ck, 'desc', rec.descr), lower(rec.nm));
  end loop;
  update public.crm_settings set data = data || '{"seeded_maint": true}'::jsonb where id = 1;
end $$;
select public.crm_seed_maint();

do $g$
declare f text;
begin
  foreach f in array array['public.crm_storage_stats(jsonb)', 'public.crm_purge(jsonb)', 'public.crm_series(jsonb)', 'public.crm_maint_contract(jsonb)', 'public.crm_maint_done(jsonb)']
  loop
    execute 'revoke all on function ' || f || ' from public';
    execute 'grant execute on function ' || f || ' to anon, authenticated';
  end loop;
  execute 'revoke all on function public.crm_seed_maint() from public, anon, authenticated';
  execute 'revoke all on function public.crm_months_of(text) from public, anon, authenticated';
exception when undefined_object then null; end $g$;

-- (7) Admin: "Is device par login yaad rakhein" (opt-in, needs the Admin PIN; stays until Logout)
alter table public.crm_sessions add column if not exists keep boolean not null default false;
create or replace function public.crm_session(p_token text) returns public.crm_ses
language plpgsql security definer set search_path = public, extensions as $$
declare s public.crm_ses; se record; u public.crm_users; rp jsonb;
begin
  select * into se from public.crm_sessions where token = coalesce(p_token, '') and expires_at > now();
  if se.token is null then raise exception 'Login expired — dobara login karein'; end if;
  if se.role = 'consumer' then raise exception 'Ye login sirf Online Store ke liye hai'; end if;
  if (se.user_id <> 0 or se.keep) and se.expires_at < now() + interval '330 days' then update public.crm_sessions set expires_at = now() + interval '365 days' where token = se.token; end if;
  if se.user_id = 0 then
    s := row(0::bigint, 'admin', 'Admin', '{"*":true}'::jsonb, null::text, null::text)::public.crm_ses; return s;
  end if;
  select * into u from public.crm_users where id = se.user_id;
  if u.id is null or u.status <> 'active' then raise exception 'Account active nahi hai — Admin se sampark karein'; end if;
  select perms into rp from public.crm_roles where role = u.role;
  s := row(u.id, u.role, u.name, coalesce(rp, '{}'::jsonb) || coalesce(u.perms, '{}'::jsonb), u.ref_code, u.mobile)::public.crm_ses;
  if u.role = 'admin' then s.perms := '{"*":true}'::jsonb; end if;
  if u.last_seen is null or u.last_seen < now() - interval '5 minutes' then update public.crm_users set last_seen = now() where id = u.id; end if;
  return s;
end $$;

create or replace function public.crm_admin_keep(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pe text; on_ boolean := coalesce((p ->> 'on')::boolean, false);
begin
  if not public.crm_is_admin(s) or (s).uid <> 0 then raise exception 'Ye option sirf Admin ke liye hai'; end if;
  pe := public.crm_auth_pin_check(public.crm_auth_find('admin', 'admin'), p ->> 'pin');
  if pe is not null then return jsonb_build_object('error', pe); end if;
  update public.crm_sessions set keep = on_, expires_at = now() + case when on_ then interval '365 days' else interval '12 hours' end where token = p ->> 'token' and user_id = 0;
  perform public.crm_log(s, 'settings', null, null, case when on_ then 'Admin login is device par yaad rakha' else 'Admin login yaad rakhna band' end);
  return jsonb_build_object('ok', true, 'keep', on_);
end $$;
do $g$ begin
  execute 'revoke all on function public.crm_admin_keep(jsonb) from public';
  execute 'grant execute on function public.crm_admin_keep(jsonb) to anon, authenticated';
exception when undefined_object then null; end $g$;

notify pgrst, 'reload schema';

-- ============================================================================
-- ROUND 9 (database) — Accounts (Kharcha + P&L + GST + ITR summary) and Backup RESTORE.
-- Run AFTER crm-setup.sql, phase1, phase2-3, phase4, phase5. Safe to re-run.
-- Note: this is a report for your CA — it is not GST / ITR filing.
-- ============================================================================

-- (1) expenses ledger ----------------------------------------------------------------
create table if not exists public.crm_expenses (
  id         bigserial primary key,
  spent_on   date not null,
  category   text not null default 'Other',
  vendor     text not null default '',
  amount     numeric(14,2) not null check (amount > 0),
  gst_amount numeric(14,2) not null default 0 check (gst_amount >= 0),
  mode       text not null default 'cash',
  note       text not null default '',
  created_by bigint,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  deleted_by bigint,
  delete_reason text
);
create index if not exists crm_expenses_on on public.crm_expenses(spent_on);
alter table public.crm_expenses enable row level security;
revoke all on public.crm_expenses from anon, authenticated;

create or replace function public.crm_exp_list(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); fr date := coalesce(nullif(p ->> 'from', '')::date, date '2000-01-01'); t date := coalesce(nullif(p ->> 'to', '')::date, date '2999-12-31');
begin
  if not (public.crm_can(s, 'accounts.manage') or public.crm_can(s, 'accounts.view')) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  return coalesce((select jsonb_agg(to_jsonb(e) - 'deleted_at' - 'deleted_by' - 'delete_reason' order by e.spent_on desc, e.id desc)
    from public.crm_expenses e where e.deleted_at is null and e.spent_on between fr and t), '[]'::jsonb);
end $$;

create or replace function public.crm_exp_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); id_ bigint := nullif(p ->> 'id', '')::bigint; d date; a numeric; g numeric; r public.crm_expenses;
  cat text := left(trim(coalesce(nullif(p ->> 'category', ''), 'Other')), 40);
begin
  perform public.crm_need(s, 'accounts.manage');
  begin d := (p ->> 'spent_on')::date; exception when others then raise exception 'Sahi tareekh likhein'; end;
  if d is null or d > public.crm_today() + 1 or d < date '2015-01-01' then raise exception 'Tareekh galat hai'; end if;
  a := public.crm_num(p -> 'amount'); g := public.crm_num(p -> 'gst_amount');
  if a <= 0 then raise exception 'Amount likhein'; end if;
  if g < 0 or g > a then raise exception 'GST amount kul amount se zyada nahi ho sakta'; end if;
  if id_ is null then
    insert into public.crm_expenses(spent_on, category, vendor, amount, gst_amount, mode, note, created_by)
    values (d, cat, left(trim(coalesce(p ->> 'vendor', '')), 120), round(a, 2), round(g, 2), left(coalesce(nullif(p ->> 'mode', ''), 'cash'), 20), left(trim(coalesce(p ->> 'note', '')), 300), (s).uid) returning * into r;
    perform public.crm_log(s, 'create', 'expense', r.id, 'Kharcha ' || r.category || ' ' || r.amount);
  else
    update public.crm_expenses set spent_on = d, category = cat, vendor = left(trim(coalesce(p ->> 'vendor', '')), 120), amount = round(a, 2), gst_amount = round(g, 2),
      mode = left(coalesce(nullif(p ->> 'mode', ''), 'cash'), 20), note = left(trim(coalesce(p ->> 'note', '')), 300) where id = id_ and deleted_at is null returning * into r;
    if r.id is null then raise exception 'Kharcha nahi mila'; end if;
    perform public.crm_log(s, 'edit', 'expense', r.id, 'Kharcha badla ' || r.category || ' ' || r.amount);
  end if;
  return to_jsonb(r) - 'deleted_at' - 'deleted_by' - 'delete_reason';
end $$;

create or replace function public.crm_exp_del(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); why text := trim(coalesce(p ->> 'why', '')); r public.crm_expenses;
begin
  perform public.crm_need(s, 'accounts.manage');
  if length(why) < 3 then raise exception 'Hatane ki wajah likhein'; end if;
  update public.crm_expenses set deleted_at = now(), deleted_by = (s).uid, delete_reason = why where id = (p ->> 'id')::bigint and deleted_at is null returning * into r;
  if r.id is null then raise exception 'Kharcha nahi mila'; end if;
  perform public.crm_log(s, 'delete', 'expense', r.id, 'Kharcha hataya (' || why || ') ' || r.category || ' ' || r.amount);
  return jsonb_build_object('ok', true);
end $$;