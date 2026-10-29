-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 18 of 30
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U30). Safe to re-run.
-- ============================================================================

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