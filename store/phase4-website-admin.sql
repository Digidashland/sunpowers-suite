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
