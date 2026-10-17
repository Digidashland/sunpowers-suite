-- ============================================================================
-- SUNPOWERS — NAYA PROJECT SETUP — part 1 of 15
-- Naya (khali) Supabase project: pehle F01..F06, phir 2-UPDATE ke U01..U09.
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (F01 -> F06, phir U01 -> U09). Safe to re-run.
-- ============================================================================

-- =====================================================================
--  SUNPOWERS STORE  —  Supabase setup  (run ONCE in Supabase → SQL Editor)
--  Safe to run again: it never deletes your data or resets your password.
-- =====================================================================

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ---------- Tables ----------------------------------------------------
create table if not exists public.sp_store (
  id          text primary key,
  data        jsonb not null,
  updated_at  timestamptz not null default now()
);

create table if not exists public.sp_admin (
  id         int primary key default 1 check (id = 1),
  pass_hash  text not null
);

create table if not exists public.sp_orders (
  id          bigserial primary key,
  created_at  timestamptz not null default now(),
  status      text not null default 'new',
  data        jsonb not null
);

create table if not exists public.sp_enquiries (
  id          bigserial primary key,
  created_at  timestamptz not null default now(),
  status      text not null default 'new',
  data        jsonb not null
);

-- Default admin password: sunpowers@123   (CHANGE IT from Admin → Settings)
insert into public.sp_admin (id, pass_hash)
values (1, extensions.crypt('sunpowers@123', extensions.gen_salt('bf')))
on conflict (id) do nothing;

-- Lock tables: browsers can only use the functions below
alter table public.sp_store     enable row level security;
alter table public.sp_admin     enable row level security;
alter table public.sp_orders    enable row level security;
alter table public.sp_enquiries enable row level security;

do $$ begin
  revoke all on public.sp_store, public.sp_admin, public.sp_orders, public.sp_enquiries from anon, authenticated;
exception when undefined_object then null; end $$;

-- ---------- Helper: password check -----------------------------------
create or replace function public.sp_check(p_pass text)
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare h text; ok boolean := false; legacy boolean := true;
begin
  -- After the CRM (crm-setup.sql) is installed, Admin logs in with Email OTP + PIN and uses a session token.
  -- The old password alone then works only if "legacy_password" is switched on in CRM settings.
  if to_regclass('public.crm_sessions') is not null then
    execute 'select exists (select 1 from public.crm_sessions where token = $1 and user_id = 0 and expires_at > now())' into ok using coalesce(p_pass, '');
    if ok then return; end if;
    execute $q$select coalesce((data #>> '{auth,legacy_password}')::boolean, false) from public.crm_settings where id = 1$q$ into legacy;
    legacy := coalesce(legacy, false);
  end if;
  if legacy then
    select pass_hash into h from public.sp_admin where id = 1;
    if h is not null and p_pass is not null and crypt(p_pass, h) = h then return; end if;
  end if;
  perform pg_sleep(1);
  raise exception 'Wrong password';
end $$;

-- ---------- Public functions -----------------------------------------
create or replace function public.sp_get_store()
returns jsonb language sql stable security definer
set search_path = public as $$
  select data from public.sp_store where id = 'main';
$$;

create or replace function public.sp_place_order(p_order jsonb)
returns bigint language plpgsql security definer
set search_path = public as $$
declare new_id bigint;
begin
  if p_order is null or jsonb_typeof(p_order) <> 'object' then raise exception 'Invalid order'; end if;
  if length(p_order::text) > 30000 then raise exception 'Order too large'; end if;
  if coalesce(trim(p_order->>'name'),'') = '' or coalesce(trim(p_order->>'phone'),'') = '' then
    raise exception 'Name and phone are required';
  end if;
  if jsonb_typeof(p_order->'items') <> 'array' or jsonb_array_length(p_order->'items') = 0 then
    raise exception 'Cart is empty';
  end if;
  insert into public.sp_orders(data) values (p_order) returning id into new_id;
  return new_id;
end $$;

create or replace function public.sp_submit_enquiry(p_data jsonb)
returns bigint language plpgsql security definer
set search_path = public as $$
declare new_id bigint;
begin
  if p_data is null or jsonb_typeof(p_data) <> 'object' then raise exception 'Invalid form'; end if;
  if length(p_data::text) > 10000 then raise exception 'Form too large'; end if;
  if coalesce(trim(p_data->>'name'),'') = '' or coalesce(trim(p_data->>'phone'),'') = '' then
    raise exception 'Name and phone are required';
  end if;
  insert into public.sp_enquiries(data) values (p_data) returning id into new_id;
  return new_id;
end $$;

-- ---------- Admin functions (password protected) ---------------------
create or replace function public.sp_admin_login(p_pass text)
returns boolean language plpgsql security definer
set search_path = public, extensions as $$
begin
  perform public.sp_check(p_pass);
  return true;
end $$;

create or replace function public.sp_save_store(p_pass text, p_data jsonb)
returns timestamptz language plpgsql security definer
set search_path = public, extensions as $$
declare t timestamptz := now();
begin
  perform public.sp_check(p_pass);
  if p_data is null or jsonb_typeof(p_data) <> 'object' then raise exception 'Invalid data'; end if;
  insert into public.sp_store(id, data, updated_at) values ('main', p_data, t)
  on conflict (id) do update set data = excluded.data, updated_at = excluded.updated_at;
  return t;
end $$;

create or replace function public.sp_admin_list(p_pass text, p_kind text)
returns jsonb language plpgsql security definer
set search_path = public, extensions as $$
declare r jsonb;
begin
  perform public.sp_check(p_pass);
  if p_kind = 'orders' then
    select coalesce(jsonb_agg(jsonb_build_object('id',id,'created_at',created_at,'status',status,'data',data) order by id desc), '[]'::jsonb)
      into r from (select * from public.sp_orders order by id desc limit 1000) x;
  elsif p_kind = 'enquiries' then
    select coalesce(jsonb_agg(jsonb_build_object('id',id,'created_at',created_at,'status',status,'data',data) order by id desc), '[]'::jsonb)
      into r from (select * from public.sp_enquiries order by id desc limit 1000) x;
  else
    raise exception 'Unknown list';
  end if;
  return r;
end $$;

create or replace function public.sp_admin_set_status(p_pass text, p_kind text, p_id bigint, p_status text)
returns boolean language plpgsql security definer
set search_path = public, extensions as $$
begin
  perform public.sp_check(p_pass);
  if p_kind = 'orders' then update public.sp_orders set status = p_status where id = p_id;
  elsif p_kind = 'enquiries' then update public.sp_enquiries set status = p_status where id = p_id;
  else raise exception 'Unknown list'; end if;
  return found;
end $$;

create or replace function public.sp_admin_delete(p_pass text, p_kind text, p_id bigint)
returns boolean language plpgsql security definer
set search_path = public, extensions as $$
begin
  perform public.sp_check(p_pass);
  if p_kind = 'orders' then delete from public.sp_orders where id = p_id;
  elsif p_kind = 'enquiries' then delete from public.sp_enquiries where id = p_id;
  else raise exception 'Unknown list'; end if;
  return found;
end $$;

create or replace function public.sp_change_password(p_old text, p_new text)
returns boolean language plpgsql security definer
set search_path = public, extensions as $$
begin
  perform public.sp_check(p_old);
  if p_new is null or length(p_new) < 6 then raise exception 'New password must be at least 6 characters'; end if;
  update public.sp_admin set pass_hash = crypt(p_new, gen_salt('bf')) where id = 1;
  return true;
end $$;

-- ---------- Admin notifications (new orders / enquiries / CRM items waiting for review) ----------
create or replace function public.sp_admin_counts(p_pass text)
returns jsonb language plpgsql security definer
set search_path = public, extensions as $$
declare crm int := 0;
begin
  perform public.sp_check(p_pass);
  if to_regclass('public.crm_records') is not null then
    execute $q$select count(*) from public.crm_records where kind = 'item' and deleted_at is null and data #>> '{store,status}' = 'pending'$q$ into crm;
  end if;
  return jsonb_build_object(
    'orders_new', (select count(*) from public.sp_orders where status = 'new'),
    'enquiries_new', (select count(*) from public.sp_enquiries where status = 'new'),
    'last_order', (select coalesce(max(id), 0) from public.sp_orders),
    'last_enquiry', (select coalesce(max(id), 0) from public.sp_enquiries),
    'crm_pending', crm, 'crm_ready', to_regclass('public.crm_records') is not null);
end $$;

-- ---------- Permissions ----------------------------------------------
revoke all on function public.sp_check(text) from public;
do $$ begin
  revoke all on function public.sp_check(text) from anon, authenticated;
exception when undefined_object then null; end $$;
do $$ begin
  grant execute on function
    public.sp_get_store(), public.sp_place_order(jsonb), public.sp_submit_enquiry(jsonb),
    public.sp_admin_login(text), public.sp_save_store(text, jsonb), public.sp_admin_list(text, text),
    public.sp_admin_set_status(text, text, bigint, text), public.sp_admin_delete(text, text, bigint),
    public.sp_change_password(text, text), public.sp_admin_counts(text)
  to anon, authenticated;
exception when undefined_object then null; end $$;

-- ---------- Image storage bucket (public read, upload allowed) -------
do $$ begin
  insert into storage.buckets (id, name, public) values ('sp-images', 'sp-images', true)
  on conflict (id) do update set public = true;
  begin
    update storage.buckets set file_size_limit = 5242880,
      allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif']
    where id = 'sp-images';
  exception when others then null; end;
  begin
    drop policy if exists "sp images upload" on storage.objects;
    create policy "sp images upload" on storage.objects
      for insert to anon, authenticated with check (bucket_id = 'sp-images');
  exception when others then raise notice 'Storage policy skipped: %', sqlerrm; end;
exception when others then
  raise notice 'Storage not set up (%). Images will be saved inside the store data instead.', sqlerrm;
end $$;

notify pgrst, 'reload schema';

select 'Sunpowers setup complete ✔' as status;
