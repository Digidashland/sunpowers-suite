-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 5 of 12
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U12). Safe to re-run.
-- ============================================================================

create or replace function public.crm_sheet_revoke(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); sh public.crm_sheets;
begin
  perform public.crm_need(s, 'items.edit');
  select * into sh from public.crm_sheets where code = p ->> 'code';
  if sh.code is null or not (public.crm_is_admin(s) or public.crm_can(s, 'sheets.manage') or sh.issuer_uid = (s).uid) then raise exception 'Sheet nahi mili'; end if;
  update public.crm_sheets set revoked = true where code = sh.code;
  perform public.crm_log(s, 'update', 'item', 0, 'Sheet ' || sh.code || ' band ki gayi');
  return jsonb_build_object('ok', true);
end $$;

-- upload edited sheet: only rows+columns that were exported under the sheet code
create or replace function public.crm_items_bulk_update(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); row_ jsonb; r public.crm_records; patch jsonb; k text; allowed text[]; sh public.crm_sheets; code_ text := nullif(trim(coalesce(p ->> 'code', '')), '');
        upd int := 0; skipped jsonb := '[]'::jsonb; blocked int := 0; outscope int := 0; costok boolean; nm text; sp jsonb; sk text; sset jsonb;
begin
  perform public.crm_need(s, 'items.edit'); perform public.crm_need(s, 'sheets.upload');
  if jsonb_typeof(p -> 'rows') <> 'array' then raise exception 'Sheet khaali hai'; end if;
  if jsonb_array_length(p -> 'rows') > 5000 then raise exception 'Ek baar me 5000 se zyada rows nahi'; end if;
  if code_ is null then
    if not public.crm_is_admin(s) then raise exception 'Ye sheet "Download sheet for edit" se nahi bani — upload nahi ho sakti'; end if;
  else
    select * into sh from public.crm_sheets where code = code_ and kind = 'item';
    if sh.code is null then raise exception 'Sheet ka code galat hai — dobara "Download sheet for edit" karein'; end if;
    if sh.revoked then raise exception 'Ye sheet band kar di gayi hai'; end if;
    if sh.expires_at < now() then raise exception 'Ye sheet expire ho gayi (30 din) — nayi sheet download karein'; end if;
  end if;
  costok := public.crm_can(s, 'items.cost');
  allowed := array['name', 'title', 'category', 'subcategory', 'price', 'mrp', 'gst', 'hsn', 'unit', 'desc', 'more', 'brand', 'mpn', 'image_link', 'stock', 'warranty', 'cost_price', 'min_price', 'specs'];
  for row_ in select * from jsonb_array_elements(p -> 'rows') loop
    select * into r from public.crm_records where id = nullif(row_ ->> 'id', '')::bigint and kind = 'item' and deleted_at is null;
    if r.id is null then skipped := skipped || to_jsonb(coalesce(row_ ->> 'id', '?')); continue; end if;   -- update only: unknown id is never created
    if code_ is not null and not (sh.ids ? r.id::text or sh.ids @> to_jsonb(r.id)) then outscope := outscope + 1; skipped := skipped || to_jsonb(r.id::text); continue; end if;
    if not public.crm_vis(s, r) then skipped := skipped || to_jsonb(r.id::text); continue; end if;
    patch := '{}'::jsonb;
    for k in select jsonb_object_keys(coalesce(row_ -> 'set', '{}'::jsonb)) loop
      if k = 'specs' then
        sset := '{}'::jsonb;
        if jsonb_typeof(row_ -> 'set' -> 'specs') = 'object' then
          for sk in select jsonb_object_keys(row_ -> 'set' -> 'specs') loop
            if code_ is null or sh.cols ? ('spec:' || sk) then sset := sset || jsonb_build_object(sk, row_ -> 'set' -> 'specs' -> sk); else blocked := blocked + 1; end if;
          end loop;
        end if;
        if sset <> '{}'::jsonb then patch := patch || jsonb_build_object('specs', sset); end if;
      elsif k = any(allowed) and (costok or k not in ('cost_price', 'min_price')) then
        if code_ is null or sh.cols ? k then patch := patch || jsonb_build_object(k, row_ -> 'set' -> k); else blocked := blocked + 1; end if;
      end if;
    end loop;
    if patch = '{}'::jsonb then continue; end if;
    nm := coalesce(patch ->> 'name', r.title);
    update public.crm_records set title = left(nm, 200), amount = case when patch ? 'price' then public.crm_num(patch -> 'price') else amount end,
      data = (data || (patch - 'specs')) || case when patch ? 'specs' and jsonb_typeof(patch -> 'specs') = 'object' then jsonb_build_object('specs', coalesce(data -> 'specs', '{}'::jsonb) || (patch -> 'specs')) else '{}'::jsonb end,
      search = lower(nm || ' ' || coalesce(patch ->> 'brand', data ->> 'brand', '') || ' ' || coalesce(data ->> 'sku', '') || ' ' || coalesce(patch ->> 'mpn', data ->> 'mpn', '') || ' ' || coalesce(patch ->> 'category', data ->> 'category', '') || ' ' || coalesce(patch ->> 'subcategory', data ->> 'subcategory', '')), updated_at = now() where id = r.id;
    upd := upd + 1;
  end loop;
  if code_ is not null then update public.crm_sheets set uses = uses + 1, last_used = now() where code = code_; end if;
  perform public.crm_log(s, 'update', 'item', 0, 'Sheet upload' || coalesce(' ' || code_, '') || ': ' || upd || ' items update' || case when outscope > 0 then ', ' || outscope || ' row sheet ke bahar (roki)' else '' end || case when blocked > 0 then ', ' || blocked || ' cell roke' else '' end);
  return jsonb_build_object('ok', true, 'updated', upd, 'skipped', skipped, 'outside', outscope, 'blocked', blocked);
end $$;

-- every download from the CRM is written to the Activity Record (who, what, how many rows, which filter)
create or replace function public.crm_export_log(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token');
begin
  perform public.crm_log(s, 'export', coalesce(nullif(p ->> 'kind', ''), 'report'), 0, 'Download ' || left(coalesce(p ->> 'name', '?'), 60) || ': ' || coalesce(nullif(p ->> 'rows', ''), '0') || ' rows' || coalesce(' · ' || nullif(left(p ->> 'filters', 200), ''), ''));
  return jsonb_build_object('ok', true);
end $$;

do $g$
declare f text;
begin
  foreach f in array array['public.crm_sheet_issue(jsonb)', 'public.crm_sheet_list(jsonb)', 'public.crm_sheet_revoke(jsonb)', 'public.crm_items_bulk_update(jsonb)', 'public.crm_export_log(jsonb)']
  loop begin execute 'revoke all on function ' || f || ' from public'; execute 'grant execute on function ' || f || ' to anon, authenticated'; exception when others then null; end; end loop;
end $g$;


-- ============================================================================
-- Round 13-3b: the same sheet-scope + download log for the Store Admin / Website Admin
-- (products sheet, full Excel, pincode rules). Table crm_sheets is shared with the CRM.
-- ============================================================================
create or replace function public.sp_sheet_issue(p_pass text, p_kind text, p_ids jsonb, p_cols jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare code_ text; n_ int;
begin
  perform public.sp_check(p_pass);
  if p_kind not in ('sp_product', 'sp_excel', 'sp_pin') then raise exception 'Galat sheet'; end if;
  if jsonb_typeof(coalesce(p_ids, '[]'::jsonb)) <> 'array' or jsonb_typeof(coalesce(p_cols, '[]'::jsonb)) <> 'array' then raise exception 'Galat data'; end if;
  n_ := jsonb_array_length(coalesce(p_ids, '[]'::jsonb));
  if n_ > 30000 or jsonb_array_length(coalesce(p_cols, '[]'::jsonb)) > 400 then raise exception 'Sheet bahut badi hai'; end if;
  code_ := 'SS' || upper(substr(md5(random()::text || clock_timestamp()::text || p_kind), 1, 12));
  insert into public.crm_sheets(code, kind, ids, cols, filt, n, issuer_uid, issuer_name, expires_at)
  values (code_, p_kind, coalesce(p_ids, '[]'::jsonb), coalesce(p_cols, '[]'::jsonb), jsonb_build_object('note', left(coalesce(p_note, ''), 300)), n_, null, 'Store Admin', now() + interval '30 days');
  insert into public.crm_activity(user_id, user_name, role, action, kind, rec_id, summary) values (null, 'Store Admin', 'admin', 'export', 'store', 0, left('Sheet download for edit ' || code_ || ' (' || p_kind || '): ' || n_ || ' rows' || coalesce(' · ' || nullif(p_note, ''), ''), 300));
  return jsonb_build_object('ok', true, 'code', code_, 'n', n_, 'expires_at', now() + interval '30 days');
end $$;

create or replace function public.sp_sheet_check(p_pass text, p_code text, p_kind text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sh public.crm_sheets;
begin
  perform public.sp_check(p_pass);
  select * into sh from public.crm_sheets where code = nullif(trim(coalesce(p_code, '')), '') and kind = p_kind;
  if sh.code is null then raise exception 'Sheet ka code galat hai — dobara "Edit ke liye sheet download" karein'; end if;
  if sh.revoked then raise exception 'Ye sheet band kar di gayi hai'; end if;
  if sh.expires_at < now() then raise exception 'Ye sheet expire ho gayi (30 din) — nayi sheet download karein'; end if;
  update public.crm_sheets set uses = uses + 1, last_used = now() where code = sh.code;
  insert into public.crm_activity(user_id, user_name, role, action, kind, rec_id, summary) values (null, 'Store Admin', 'admin', 'update', 'store', 0, left('Sheet upload ' || sh.code || ' (' || p_kind || ')', 300));
  return jsonb_build_object('ok', true, 'ids', sh.ids, 'cols', sh.cols, 'n', sh.n, 'filt', sh.filt);
end $$;

create or replace function public.sp_admin_export_log(p_pass text, p_name text, p_rows int, p_filters text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public.sp_check(p_pass);
  insert into public.crm_activity(user_id, user_name, role, action, kind, rec_id, summary) values (null, 'Store Admin', 'admin', 'export', 'store', 0, left('Download ' || coalesce(p_name, '?') || ': ' || coalesce(p_rows, 0) || ' rows' || coalesce(' · ' || nullif(p_filters, ''), ''), 300));
  return jsonb_build_object('ok', true);
end $$;

do $g$
declare f text;
begin
  foreach f in array array['public.sp_sheet_issue(text, text, jsonb, jsonb, text)', 'public.sp_sheet_check(text, text, text)', 'public.sp_admin_export_log(text, text, int, text)']
  loop begin execute 'revoke all on function ' || f || ' from public'; execute 'grant execute on function ' || f || ' to anon, authenticated'; exception when others then null; end; end loop;
end $g$;

-- ============================================================================
-- Round 13-4: permission points (tick / untick per user) — new points + sensible role defaults
-- Existing role settings are never overwritten (existing key wins), so any change the Admin made stays.
-- ============================================================================

update public.crm_roles set perms = '{"dashboard.money":true,"dashboard.team":true,"analytics.view":true,"analytics.all":true,"accounts.view":true,"reports.download":true,"sheets.download":true,"sheets.upload":true,"items.export":true,"stock.view":true}'::jsonb || coalesce(perms, '{}'::jsonb) where role = 'manager';
update public.crm_roles set perms = '{"stock.view":true,"analytics.view":true}'::jsonb || coalesce(perms, '{}'::jsonb) where role = 'staff';
update public.crm_roles set perms = '{"stock.view":true}'::jsonb || coalesce(perms, '{}'::jsonb) where role in ('dealer');

-- ============================================================================
-- Round 13-5: role-wise dashboard data, Analytics, Accounts (ledger / receivable / payable / payments out) and Reports
-- Everything is scoped by crm_vis (what the user may see) and by the permission points added in 13-4.
-- ============================================================================
create or replace function public.crm_rdate(r public.crm_records) returns date language sql stable as $$
  select coalesce(case when (r.data ->> 'date') ~ '^\d{4}-\d{2}-\d{2}' then left(r.data ->> 'date', 10)::date end, (r.created_at at time zone 'Asia/Kolkata')::date) $$;
create or replace function public.crm_pdate(r public.crm_records) returns date language sql stable as $$
  select coalesce(r.due_at, public.crm_rdate(r)) $$;
create or replace function public.crm_money_ok(s public.crm_ses) returns boolean language sql stable as $$
  select public.crm_can(s, 'dashboard.money') or public.crm_can(s, 'accounts.view') or public.crm_can(s, 'accounts.manage') $$;
create or replace function public.crm_mine(s public.crm_ses, r public.crm_records) returns boolean language sql stable as $$
  select public.crm_can(s, 'analytics.all') or r.owner_id = (s).uid or r.assigned_to = (s).uid $$;

-- ---------------------------------------------------------------- dashboard (extra data for the role-wise Home)
create or replace function public.crm_dash2(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); today_ date := public.crm_today(); m0 date := date_trunc('month', public.crm_today())::date; pm0 date := (date_trunc('month', public.crm_today()) - interval '1 month')::date;
        money boolean := public.crm_can(s, 'dashboard.money'); team boolean := public.crm_can(s, 'dashboard.team'); cur jsonb; prev jsonb; res jsonb;
begin
  create temp table if not exists _dv(kind text, status text, d date, amount numeric, kw numeric, src text, owner_id bigint, party_id bigint) on commit drop;
  truncate _dv;
  insert into _dv select r.kind, r.status, case r.kind when 'payment' then public.crm_pdate(r) else public.crm_rdate(r) end, r.amount, public.crm_num(r.data -> 'kw'), coalesce(nullif(r.data ->> 'source', ''), 'Other'), coalesce(r.assigned_to, r.owner_id), r.party_id
    from public.crm_records r where r.deleted_at is null and r.kind in ('lead', 'quote', 'invoice', 'payment', 'plant', 'party') and r.status <> 'cancelled'
      and (r.created_at >= pm0 - interval '40 days' or r.kind in ('lead', 'quote')) and public.crm_vis(s, r);
  select jsonb_build_object('leads_new', count(*) filter (where kind = 'lead'), 'leads_won', count(*) filter (where kind = 'lead' and status = 'won'),
      'quotes_n', count(*) filter (where kind = 'quote'), 'customers_new', count(*) filter (where kind = 'party'),
      'plants_n', count(*) filter (where kind = 'plant'), 'kw', coalesce(sum(kw) filter (where kind = 'plant'), 0),
      'bills_n', count(*) filter (where kind = 'invoice'),
      'quotes_amt', case when money then coalesce(sum(amount) filter (where kind = 'quote'), 0) end,
      'sales', case when money then coalesce(sum(amount) filter (where kind = 'invoice'), 0) end,
      'collected', case when money then coalesce(sum(amount) filter (where kind = 'payment'), 0) end)
    into cur from _dv where d >= m0 and d <= today_;
  select jsonb_build_object('leads_new', count(*) filter (where kind = 'lead'), 'leads_won', count(*) filter (where kind = 'lead' and status = 'won'),
      'quotes_n', count(*) filter (where kind = 'quote'), 'customers_new', count(*) filter (where kind = 'party'),
      'plants_n', count(*) filter (where kind = 'plant'), 'kw', coalesce(sum(kw) filter (where kind = 'plant'), 0),
      'bills_n', count(*) filter (where kind = 'invoice'),
      'quotes_amt', case when money then coalesce(sum(amount) filter (where kind = 'quote'), 0) end,
      'sales', case when money then coalesce(sum(amount) filter (where kind = 'invoice'), 0) end,
      'collected', case when money then coalesce(sum(amount) filter (where kind = 'payment'), 0) end)
    into prev from _dv where d >= pm0 and d < m0;
  res := jsonb_build_object('scope', case when team then 'all' else 'own' end, 'money', money, 'cur', cur, 'prev', prev,
    'leads_by_status', (select coalesce(jsonb_agg(jsonb_build_object('s', status, 'n', n) order by n desc), '[]'::jsonb) from (select status, count(*) n from _dv where kind = 'lead' group by status) x),
    'quotes_by_status', (select coalesce(jsonb_agg(jsonb_build_object('s', status, 'n', n, 'amt', case when money then a end) order by n desc), '[]'::jsonb) from (select status, count(*) n, sum(amount) a from _dv where kind = 'quote' group by status) x),
    'sources', (select coalesce(jsonb_agg(jsonb_build_object('s', src, 'n', n, 'won', w) order by n desc), '[]'::jsonb) from (select src, count(*) n, count(*) filter (where status = 'won') w from _dv where kind = 'lead' and d >= today_ - 90 group by src order by count(*) desc limit 6) x),
    'daily', (select coalesce(jsonb_agg(jsonb_build_object('d', to_char(g, 'YYYY-MM-DD'),
        'leads', (select count(*) from _dv where kind = 'lead' and d = g::date), 'quotes', (select count(*) from _dv where kind = 'quote' and d = g::date),
        'sales', case when money then (select coalesce(sum(amount), 0) from _dv where kind = 'invoice' and d = g::date) end) order by g), '[]'::jsonb)
        from generate_series((today_ - 13)::timestamp, today_::timestamp, interval '1 day') g));
  if money then
    res := res || jsonb_build_object('top_customers', (select coalesce(jsonb_agg(jsonb_build_object('name', coalesce((select title from public.crm_records pp where pp.id = z.party_id), 'Walk-in'), 'amt', z.a) order by z.a desc), '[]'::jsonb)
        from (select party_id, sum(amount) a from _dv where kind = 'invoice' group by party_id order by sum(amount) desc limit 5) z));
    res := res || jsonb_build_object('aging', (select jsonb_build_object('b0', coalesce(sum(bal) filter (where age <= 30), 0), 'b30', coalesce(sum(bal) filter (where age between 31 and 60), 0), 'b60', coalesce(sum(bal) filter (where age between 61 and 90), 0), 'b90', coalesce(sum(bal) filter (where age > 90), 0), 'total', coalesce(sum(bal), 0))
        from (select r.amount - public.crm_num(r.data -> 'paid') bal, today_ - public.crm_rdate(r) age from public.crm_records r where r.kind = 'invoice' and r.deleted_at is null and r.status in ('due', 'partial') and public.crm_vis(s, r)) q where bal > 0));
  end if;
  if team then
    res := res || jsonb_build_object('team', (select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'role', u.role,
        'leads_open', (select count(*) from public.crm_records r where r.kind = 'lead' and r.deleted_at is null and r.status not in ('won', 'lost') and coalesce(r.assigned_to, r.owner_id) = u.id),
        'overdue', (select count(*) from public.crm_records r where r.deleted_at is null and coalesce(r.assigned_to, r.owner_id) = u.id and r.due_at < today_ and ((r.kind = 'reminder' and r.status = 'open') or (r.kind = 'lead' and r.status not in ('won', 'lost')))),
        'quotes_m', (select count(*) from public.crm_records r where r.kind = 'quote' and r.deleted_at is null and r.owner_id = u.id and public.crm_rdate(r) >= m0),
        'sales_m', case when money then (select coalesce(sum(r.amount), 0) from public.crm_records r where r.kind = 'invoice' and r.deleted_at is null and r.status <> 'cancelled' and r.owner_id = u.id and public.crm_rdate(r) >= m0) end,
        'target', u.meta -> 'target_monthly') order by u.name), '[]'::jsonb)
      from public.crm_users u where u.status = 'active' and u.role in ('manager', 'staff', 'dealer', 'influencer')));
  end if;
  return res;
end $$;

-- ---------------------------------------------------------------- analytics
create or replace function public.crm_analytics(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); fr date := coalesce(nullif(p ->> 'from', '')::date, (date_trunc('month', public.crm_today()) - interval '11 months')::date); t date := coalesce(nullif(p ->> 'to', '')::date, public.crm_today());
        money boolean := public.crm_money_ok(s); uid_ bigint := nullif(p ->> 'user_id', '')::bigint; res jsonb;
begin
  perform public.crm_need(s, 'analytics.view');
  if t < fr or t - fr > 1100 then raise exception 'Sahi tareekh range chunein (max 3 saal)'; end if;
  if uid_ is not null and not public.crm_can(s, 'analytics.all') then uid_ := (s).uid; end if;
  create temp table if not exists _av(id bigint, kind text, status text, d date, amount numeric, kw numeric, src text, uid bigint, party_id bigint, lines jsonb, paid numeric) on commit drop;
  truncate _av;
  insert into _av select r.id, r.kind, r.status, case r.kind when 'payment' then public.crm_pdate(r) else public.crm_rdate(r) end, r.amount, public.crm_num(r.data -> 'kw'), coalesce(nullif(r.data ->> 'source', ''), 'Other'),
      coalesce(r.assigned_to, r.owner_id), r.party_id, case when r.kind = 'invoice' then coalesce(r.data -> 'lines', '[]'::jsonb) end, public.crm_num(r.data -> 'paid')
    from public.crm_records r where r.deleted_at is null and r.kind in ('lead', 'quote', 'invoice', 'payment', 'plant') and r.status <> 'cancelled' and public.crm_vis(s, r) and public.crm_mine(s, r)
      and (uid_ is null or r.owner_id = uid_ or r.assigned_to = uid_);
  delete from _av where d < fr or d > t;
  res := jsonb_build_object('from', fr, 'to', t, 'money', money, 'all', public.crm_can(s, 'analytics.all'),
    'months', (select coalesce(jsonb_agg(jsonb_build_object('m', to_char(g, 'YYYY-MM'),
        'leads', (select count(*) from _av where kind = 'lead' and to_char(d, 'YYYY-MM') = to_char(g, 'YYYY-MM')),
        'won', (select count(*) from _av where kind = 'lead' and status = 'won' and to_char(d, 'YYYY-MM') = to_char(g, 'YYYY-MM')),
        'quotes', (select count(*) from _av where kind = 'quote' and to_char(d, 'YYYY-MM') = to_char(g, 'YYYY-MM')),
        'bills', (select count(*) from _av where kind = 'invoice' and to_char(d, 'YYYY-MM') = to_char(g, 'YYYY-MM')),
        'kw', (select coalesce(sum(kw), 0) from _av where kind = 'plant' and to_char(d, 'YYYY-MM') = to_char(g, 'YYYY-MM')),
        'sales', case when money then (select coalesce(sum(amount), 0) from _av where kind = 'invoice' and to_char(d, 'YYYY-MM') = to_char(g, 'YYYY-MM')) end,
        'collected', case when money then (select coalesce(sum(amount), 0) from _av where kind = 'payment' and to_char(d, 'YYYY-MM') = to_char(g, 'YYYY-MM')) end) order by g), '[]'::jsonb)
      from generate_series(date_trunc('month', fr)::timestamp, date_trunc('month', t)::timestamp, interval '1 month') g),
    'sources', (select coalesce(jsonb_agg(jsonb_build_object('s', src, 'leads', n, 'won', w, 'rate', case when n > 0 then round(100.0 * w / n, 1) else 0 end) order by n desc), '[]'::jsonb) from (select src, count(*) n, count(*) filter (where status = 'won') w from _av where kind = 'lead' group by src) x),
    'funnel', jsonb_build_object('leads', (select count(*) from _av where kind = 'lead'), 'leads_won', (select count(*) from _av where kind = 'lead' and status = 'won'), 'leads_lost', (select count(*) from _av where kind = 'lead' and status = 'lost'),
        'quotes', (select count(*) from _av where kind = 'quote'), 'quotes_accepted', (select count(*) from _av where kind = 'quote' and status in ('accepted', 'converted')),
        'bills', (select count(*) from _av where kind = 'invoice'), 'bills_paid', (select count(*) from _av where kind = 'invoice' and status = 'paid')),
    'lead_status', (select coalesce(jsonb_agg(jsonb_build_object('s', status, 'n', n) order by n desc), '[]'::jsonb) from (select status, count(*) n from _av where kind = 'lead' group by status) x),
    'quote_status', (select coalesce(jsonb_agg(jsonb_build_object('s', status, 'n', n, 'amt', case when money then a end) order by n desc), '[]'::jsonb) from (select status, count(*) n, sum(amount) a from _av where kind = 'quote' group by status) x),
    'by_user', (select coalesce(jsonb_agg(jsonb_build_object('name', coalesce(u.name, 'Company'), 'leads', x.l, 'won', x.w, 'quotes', x.q, 'bills', x.b, 'kw', x.k, 'sales', case when money then x.sa end) order by x.sa desc nulls last), '[]'::jsonb)
        from (select uid, count(*) filter (where kind = 'lead') l, count(*) filter (where kind = 'lead' and status = 'won') w, count(*) filter (where kind = 'quote') q, count(*) filter (where kind = 'invoice') b,
              coalesce(sum(kw) filter (where kind = 'plant'), 0) k, coalesce(sum(amount) filter (where kind = 'invoice'), 0) sa from _av group by uid) x left join public.crm_users u on u.id = x.uid));
  if money then
    res := res || jsonb_build_object(
      'by_category', (select coalesce(jsonb_agg(jsonb_build_object('c', c, 'amt', a, 'qty', q) order by a desc), '[]'::jsonb) from (
          select coalesce(nullif(it.data ->> 'category', ''), 'Other') c, sum(public.crm_num(l -> 'qty') * public.crm_num(l -> 'price')) a, sum(public.crm_num(l -> 'qty')) q
          from _av v cross join lateral jsonb_array_elements(coalesce(v.lines, '[]'::jsonb)) l left join public.crm_records it on it.id = nullif(case when coalesce(l ->> 'item_id', '') ~ '^[0-9]+$' then l ->> 'item_id' end, '')::bigint
          where v.kind = 'invoice' group by 1) z),
      'by_item', (select coalesce(jsonb_agg(jsonb_build_object('name', nm, 'amt', a, 'qty', q) order by a desc), '[]'::jsonb) from (
          select coalesce(nullif(l ->> 'name', ''), '?') nm, sum(public.crm_num(l -> 'qty') * public.crm_num(l -> 'price')) a, sum(public.crm_num(l -> 'qty')) q
          from _av v cross join lateral jsonb_array_elements(coalesce(v.lines, '[]'::jsonb)) l where v.kind = 'invoice' group by 1 order by 2 desc limit 10) z),
      'top_customers', (select coalesce(jsonb_agg(jsonb_build_object('name', coalesce((select title from public.crm_records pp where pp.id = z.party_id), 'Walk-in'), 'amt', z.a, 'bills', z.n) order by z.a desc), '[]'::jsonb)
          from (select party_id, sum(amount) a, count(*) n from _av where kind = 'invoice' group by party_id order by sum(amount) desc limit 10) z),
      'aging', (select jsonb_build_object('b0', coalesce(sum(bal) filter (where age <= 30), 0), 'b30', coalesce(sum(bal) filter (where age between 31 and 60), 0), 'b60', coalesce(sum(bal) filter (where age between 61 and 90), 0), 'b90', coalesce(sum(bal) filter (where age > 90), 0), 'total', coalesce(sum(bal), 0))
          from (select amount - paid bal, public.crm_today() - d age from _av where kind = 'invoice' and status in ('due', 'partial')) q where bal > 0),
      'totals', (select jsonb_build_object('sales', coalesce(sum(amount) filter (where kind = 'invoice'), 0), 'collected', coalesce(sum(amount) filter (where kind = 'payment'), 0), 'quotes', coalesce(sum(amount) filter (where kind = 'quote'), 0)) from _av));
  end if;
  return res;
end $$;

-- ---------------------------------------------------------------- purchase payments (money paid OUT to suppliers)
create or replace function public.crm_purchase_pay(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); r public.crm_records; amt numeric := public.crm_num(p -> 'amount'); paid numeric; pays jsonb; dt date := coalesce(nullif(p ->> 'date', '')::date, public.crm_today());
begin
  perform public.crm_need(s, 'purchase.manage');
  select * into r from public.crm_records where id = nullif(p ->> 'id', '')::bigint and kind = 'purchase' and deleted_at is null;
  if r.id is null then raise exception 'Purchase nahi mila'; end if;
  if r.status not in ('open', 'received') then raise exception 'Is purchase par payment nahi ho sakti'; end if;
  if amt <= 0 then raise exception 'Amount likhein'; end if;
  paid := public.crm_num(r.data -> 'paid');
  if paid + amt > r.amount + 0.005 then raise exception 'Baaki sirf % hai', round(r.amount - paid, 2); end if;
  pays := coalesce(r.data -> 'pays', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('date', dt, 'amount', amt, 'mode', coalesce(nullif(p ->> 'mode', ''), 'bank'), 'note', left(coalesce(p ->> 'note', ''), 200), 'by', (s).name));
  update public.crm_records set data = data || jsonb_build_object('pays', pays, 'paid', paid + amt), updated_at = now() where id = r.id;
  perform public.crm_log(s, 'update', 'purchase', r.id, 'Supplier ko payment ' || amt || ' (' || coalesce(r.ref, r.id::text) || ')');
  return jsonb_build_object('ok', true, 'paid', paid + amt, 'balance', r.amount - paid - amt);
end $$;

-- ---------------------------------------------------------------- receivable / payable (who owes whom)
create or replace function public.crm_receivable(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); side text := coalesce(nullif(p ->> 'side', ''), 'receivable'); today_ date := public.crm_today(); rows jsonb;
begin
  if not (public.crm_can(s, 'accounts.view') or public.crm_can(s, 'accounts.manage') or public.crm_can(s, 'invoices.view_all') or (side = 'receivable' and public.crm_can(s, 'invoices.create'))) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  if side = 'payable' then
    if not (public.crm_can(s, 'purchase.manage') or public.crm_can(s, 'accounts.view') or public.crm_can(s, 'accounts.manage')) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
    select coalesce(jsonb_agg(jsonb_build_object('party_id', party_id, 'name', coalesce((select title from public.crm_records pp where pp.id = z.party_id), '?'), 'mobile', (select mobile from public.crm_records pp where pp.id = z.party_id), 'n', n, 'total', tot, 'b0', b0, 'b30', b30, 'b60', b60, 'b90', b90, 'oldest', oldest,
        'docs', docs) order by tot desc), '[]'::jsonb) into rows from (
      select party_id, count(*) n, sum(bal) tot, sum(bal) filter (where age <= 30) b0, sum(bal) filter (where age between 31 and 60) b30, sum(bal) filter (where age between 61 and 90) b60, sum(bal) filter (where age > 90) b90, min(d) oldest,
        jsonb_agg(jsonb_build_object('id', id, 'ref', ref, 'date', d, 'amount', amt, 'paid', amt - bal, 'balance', bal, 'status', status) order by d) docs
      from (select r.id, r.ref, r.party_id, r.status, r.amount amt, r.amount - public.crm_num(r.data -> 'paid') bal, public.crm_rdate(r) d, today_ - public.crm_rdate(r) age
            from public.crm_records r where r.kind = 'purchase' and r.deleted_at is null and r.status = 'received' and public.crm_vis(s, r)) q where bal > 0.004 group by party_id) z;
  else
    select coalesce(jsonb_agg(jsonb_build_object('party_id', party_id, 'name', coalesce((select title from public.crm_records pp where pp.id = z.party_id), 'Walk-in'), 'mobile', (select mobile from public.crm_records pp where pp.id = z.party_id), 'n', n, 'total', tot, 'b0', b0, 'b30', b30, 'b60', b60, 'b90', b90, 'oldest', oldest,
        'docs', docs) order by tot desc), '[]'::jsonb) into rows from (
      select party_id, count(*) n, sum(bal) tot, sum(bal) filter (where age <= 30) b0, sum(bal) filter (where age between 31 and 60) b30, sum(bal) filter (where age between 61 and 90) b60, sum(bal) filter (where age > 90) b90, min(d) oldest,
        jsonb_agg(jsonb_build_object('id', id, 'ref', ref, 'date', d, 'amount', amt, 'paid', amt - bal, 'balance', bal, 'status', status) order by d) docs
      from (select r.id, r.ref, r.party_id, r.status, r.amount amt, r.amount - public.crm_num(r.data -> 'paid') bal, public.crm_rdate(r) d, today_ - public.crm_rdate(r) age
            from public.crm_records r where r.kind = 'invoice' and r.deleted_at is null and r.status in ('due', 'partial') and public.crm_vis(s, r)) q where bal > 0.004 group by party_id) z;
  end if;
  return jsonb_build_object('side', side, 'rows', rows, 'total', (select coalesce(sum((x ->> 'total')::numeric), 0) from jsonb_array_elements(rows) x));
end $$;

-- ---------------------------------------------------------------- ledger (party statement or day book)
create or replace function public.crm_ledger(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.crm_ses := public.crm_session(p ->> 'token'); pid bigint := nullif(p ->> 'party_id', '')::bigint; fr date := coalesce(nullif(p ->> 'from', '')::date, (date_trunc('month', public.crm_today()))::date); t date := coalesce(nullif(p ->> 'to', '')::date, public.crm_today());
        opening numeric := 0; lines jsonb; pname text;
begin
  if not (public.crm_can(s, 'accounts.view') or public.crm_can(s, 'accounts.manage') or public.crm_can(s, 'invoices.view_all')) then raise exception 'Aapko is kaam ki permission nahi hai'; end if;
  if t < fr or t - fr > 1100 then raise exception 'Sahi tareekh range chunein (max 3 saal)'; end if;
  create temp table if not exists _lg(d date, typ text, ref text, party_id bigint, party text, note text, debit numeric, credit numeric, cash_in numeric, cash_out numeric, sk bigint) on commit drop;
  truncate _lg;
  insert into _lg select public.crm_rdate(r), 'Bill', r.ref, r.party_id, coalesce((select title from public.crm_records pp where pp.id = r.party_id), ''), r.status, r.amount, 0, 0, 0, r.id
    from public.crm_records r where r.kind = 'invoice' and r.deleted_at is null and r.status <> 'cancelled' and public.crm_vis(s, r) and (pid is null or r.party_id = pid);
  insert into _lg select public.crm_pdate(r), 'Payment mila', r.ref, r.party_id, coalesce((select title from public.crm_records pp where pp.id = r.party_id), ''), coalesce(r.data ->> 'mode', ''), 0, r.amount, r.amount, 0, r.id
    from public.crm_records r where r.kind = 'payment' and r.deleted_at is null and public.crm_vis(s, r) and (pid is null or r.party_id = pid);
  if public.crm_can(s, 'purchase.manage') or public.crm_can(s, 'accounts.view') or public.crm_can(s, 'accounts.manage') or public.crm_is_admin(s) then
    insert into _lg select public.crm_rdate(r), 'Purchase', r.ref, r.party_id, coalesce((select title from public.crm_records pp where pp.id = r.party_id), ''), r.status, 0, r.amount, 0, 0, r.id
      from public.crm_records r where r.kind = 'purchase' and r.deleted_at is null and r.status = 'received' and (pid is null or r.party_id = pid) and public.crm_vis(s, r);
    insert into _lg select (pz ->> 'date')::date, 'Supplier ko payment', r.ref, r.party_id, coalesce((select title from public.crm_records pp where pp.id = r.party_id), ''), coalesce(pz ->> 'mode', ''), public.crm_num(pz -> 'amount'), 0, 0, public.crm_num(pz -> 'amount'), r.id
      from public.crm_records r cross join lateral jsonb_array_elements(coalesce(r.data -> 'pays', '[]'::jsonb)) pz where r.kind = 'purchase' and r.deleted_at is null and (pid is null or r.party_id = pid) and public.crm_vis(s, r);
    if pid is null then
      insert into _lg select e.spent_on, 'Kharcha', e.category, null, e.vendor, e.mode, 0, 0, 0, case when e.mode = 'credit' then 0 else e.amount end, e.id from public.crm_expenses e where e.deleted_at is null;
    end if;
  end if;
  select coalesce(sum(debit - credit), 0) into opening from _lg where d < fr and pid is not null;
  select coalesce(jsonb_agg(jsonb_build_object('d', d, 'typ', typ, 'ref', ref, 'party', party, 'note', note, 'debit', debit, 'credit', credit, 'cash_in', cash_in, 'cash_out', cash_out, 'bal', bal) order by d, typ, sk), '[]'::jsonb) into lines
    from (select z.*, opening + sum(debit - credit) over (order by d, typ, sk rows unbounded preceding) bal from _lg z where d between fr and t) y;
  select title into pname from public.crm_records where id = pid;
  return jsonb_build_object('from', fr, 'to', t, 'party_id', pid, 'party', pname, 'opening', opening, 'lines', lines,
    'tot', (select jsonb_build_object('debit', coalesce(sum(debit), 0), 'credit', coalesce(sum(credit), 0), 'cash_in', coalesce(sum(cash_in), 0), 'cash_out', coalesce(sum(cash_out), 0)) from _lg where d between fr and t));
end $$;