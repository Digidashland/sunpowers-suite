-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 17 of 30
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U30). Safe to re-run.
-- ============================================================================

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