-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 9 of 9
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U09). Safe to re-run.
-- ============================================================================

-- ---------- blueprint tool: reuse the sign-up lead of the same person (one person = one lead) ----------
create or replace function public.sp_blueprint_submit(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token');      -- login is mandatory
        bp jsonb := p -> 'blueprint'; nm text; mob text;
        city text := left(trim(coalesce(p ->> 'city', '')), 80); note text := left(trim(coalesce(p ->> 'note', '')), 500);
        asg bigint; bid bigint; lid bigint; kw numeric; summary text; src text := coalesce(nullif(p ->> 'from', ''), 'web'); pc int := 0; newlead boolean := false;
begin
  if bp is null or jsonb_typeof(bp) <> 'object' then raise exception 'Blueprint adhura hai'; end if;
  -- photos and video stay on the customer's phone: they are never stored here
  if jsonb_typeof(bp -> 'photos') = 'array' then pc := jsonb_array_length(bp -> 'photos'); end if;
  begin pc := greatest(pc, coalesce(nullif(bp ->> 'photo_count', '')::int, 0)); exception when others then null; end;
  pc := least(pc, 50);
  bp := (bp - 'photos' - 'video') || jsonb_build_object('photo_count', pc);
  if length(bp::text) > 200000 then raise exception 'Blueprint bahut bada hai'; end if;
  nm := left(trim(coalesce(nullif(trim(u.name), ''), p ->> 'name', '')), 80);
  mob := public.crm_mobile(coalesce(nullif(u.mobile, ''), p ->> 'mobile', ''));
  if length(nm) < 2 then raise exception 'Naam likhein'; end if;
  if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Account me sahi 10 ank ka mobile save karein'; end if;
  if (select count(*) from public.crm_records where kind = 'blueprint' and data ->> 'user_id' = u.id::text and created_at > now() - interval '1 hour') >= 10 then raise exception 'Bahut zyada requests — thodi der baad try karein'; end if;
  kw := public.crm_num(bp #> '{result,kw}');
  select nullif(data #>> '{blueprint,assign_to}', '')::bigint into asg from public.crm_settings where id = 1;
  summary := 'Blueprint: ' || coalesce(bp #>> '{site,type}', '-') || ', ' || coalesce(bp #>> '{result,panels}', '0') || ' panels, ' || coalesce(kw::text, '0') || ' kW, structure ' || coalesce(bp #>> '{structure,type}', '-')
             || case when note <> '' then ' | ' || note else '' end;
  insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, data, search, created_by)
    values ('blueprint', nm, mob, 'new', 0, asg, (bp - 'customer') || jsonb_build_object('customer', jsonb_build_object('name', nm, 'mobile', mob, 'city', city, 'note', note), 'from', src, 'user_id', u.id), lower(nm || ' ' || mob), 0)
    returning id into bid;
  -- (Round 16) one person = one lead.  A lead is created ONLY the first time this account uses any Sunpowers tool; later use never makes another lead
  select id into lid from public.crm_records where kind = 'lead' and deleted_at is null and data ->> 'tools_uid' = u.id::text order by id limit 1;
  if lid is null then
    -- the same person may already have a lead from signing up: use that one (one person = one lead)
    select id into lid from public.crm_records where kind = 'lead' and deleted_at is null and data ->> 'signup_uid' = u.id::text and not (data ? 'tools_uid') order by id limit 1;
  end if;
  if lid is not null and not newlead and not exists (select 1 from public.crm_records where id = lid and data ? 'tools_uid') then
    update public.crm_records set assigned_to = coalesce(assigned_to, asg), data = data || jsonb_build_object('email', u.email, 'city', city, 'source', 'Leads from project blueprint', 'kw', kw, 'note', summary, 'company', true, 'blueprint_id', bid, 'tools_uid', u.id::text, 'tool', 'blueprint',
          'address', coalesce(bp #>> '{location,addr}', ''), 'map', 'https://www.google.com/maps?q=' || coalesce(bp #>> '{location,lat}', '') || ',' || coalesce(bp #>> '{location,lng}', ''))
      where id = lid;
    newlead := true;
  elsif lid is null then
    insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, due_at, data, search, created_by)
      values ('lead', nm, mob, 'new', 0, asg, public.crm_today(),
        jsonb_build_object('name', nm, 'mobile', mob, 'email', u.email, 'city', city, 'source', 'Leads from project blueprint', 'kw', kw, 'note', summary, 'company', true, 'blueprint_id', bid, 'tools_uid', u.id::text, 'tool', 'blueprint',
          'address', coalesce(bp #>> '{location,addr}', ''), 'map', 'https://www.google.com/maps?q=' || coalesce(bp #>> '{location,lat}', '') || ',' || coalesce(bp #>> '{location,lng}', '')),
        lower(nm || ' ' || mob), 0)
      returning id into lid;
    newlead := true;
    begin perform public.sp_notify_admin('Naya blueprint lead — ' || nm, '<p>' || nm || ' · ' || mob || '</p><p>' || summary || '</p><p>CRM → Leads mein dekhein.</p>'); exception when others then null; end;
  end if;
  update public.crm_records set data = data || jsonb_build_object('lead_id', lid) where id = bid;
  return jsonb_build_object('ok', true, 'id', bid, 'lead_id', lid, 'new_lead', newlead);
end $$;

-- (Round 17 fix) Tools (Blueprint / Error Detector): if this person already has a lead from signing up, use THAT lead (one person = one lead)
create or replace function public.sp_tool_use(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); tool text := coalesce(p ->> 'tool', ''); info text := left(trim(coalesce(p ->> 'info', '')), 500);
        asg bigint; lid bigint; mob text; src text;
begin
  if tool not in ('detector', 'blueprint') then raise exception 'Galat tool'; end if;
  select id into lid from public.crm_records where kind = 'lead' and deleted_at is null and data ->> 'tools_uid' = u.id::text order by id limit 1;
  if lid is not null then return jsonb_build_object('ok', true, 'new_lead', false, 'lead_id', lid); end if;
  mob := public.crm_mobile(coalesce(u.mobile, ''));
  if mob !~ '^[6-9][0-9]{9}$' then raise exception 'Account me sahi 10 ank ka mobile save karein'; end if;
  src := case tool when 'detector' then 'Solar Error Detector' else 'Leads from project blueprint' end;
  select nullif(data #>> '{blueprint,assign_to}', '')::bigint into asg from public.crm_settings where id = 1;
  select id into lid from public.crm_records where kind = 'lead' and deleted_at is null and data ->> 'signup_uid' = u.id::text and not (data ? 'tools_uid') order by id limit 1;
  if lid is not null then
    update public.crm_records set assigned_to = coalesce(assigned_to, asg),
      data = data || jsonb_build_object('email', u.email, 'source', src, 'tool', tool, 'tools_uid', u.id::text, 'company', true, 'note', coalesce(nullif(info, ''), 'Used ' || tool)), updated_at = now()
      where id = lid;
    return jsonb_build_object('ok', true, 'new_lead', false, 'lead_id', lid);
  end if;
  insert into public.crm_records(kind, title, mobile, status, owner_id, assigned_to, due_at, data, search, created_by)
    values ('lead', u.name, mob, 'new', 0, asg, public.crm_today(),
      jsonb_build_object('name', u.name, 'mobile', mob, 'email', u.email, 'source', src, 'tool', tool, 'tools_uid', u.id::text, 'company', true, 'note', coalesce(nullif(info, ''), 'Used ' || tool)),
      lower(u.name || ' ' || mob), 0)
    returning id into lid;
  begin perform public.sp_notify_admin('Naya lead (' || src || ') — ' || u.name, '<p>' || u.name || ' · ' || mob || '</p><p>' || info || '</p><p>CRM → Leads mein dekhein.</p>'); exception when others then null; end;
  return jsonb_build_object('ok', true, 'new_lead', true, 'lead_id', lid);
end $$;
grant execute on function public.sp_tool_use(jsonb) to anon, authenticated;
