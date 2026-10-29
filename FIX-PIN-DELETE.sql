-- FIX: Supabase "DELETE ke liye WHERE clause ki avashyakta hoti hai" — pincode master / niyam saaf karne wale 3 function me `where true` joda.
-- Staging me SQL Editor me chalayein. Dobara chalana safe hai. Kuch aur nahi badalta.
do $fix$ declare fn text; src text;
begin
  foreach fn in array array['public.sp_pin_master_load(text,jsonb,boolean)', 'public.sp_pin_master_clear(text)', 'public.sp_pin_rules_delete(text,jsonb)'] loop
    begin
      src := pg_get_functiondef(fn::regprocedure);
    exception when undefined_function then continue;
    end;
    if src ~ 'delete from public\.sp_pin_(master|rules);' then
      src := regexp_replace(src, 'delete from public\.(sp_pin_master|sp_pin_rules);', 'delete from public.\1 where true;', 'g');
      execute src;
      raise notice 'theek kiya: %', fn;
    end if;
  end loop;
end $fix$;
notify pgrst, 'reload schema';
