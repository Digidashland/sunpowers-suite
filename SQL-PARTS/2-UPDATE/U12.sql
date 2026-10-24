-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 12 of 12
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U12). Safe to re-run.
-- ============================================================================

-- customer app profile now also lists all bills (Pending / Paid / Cancelled)

-- Customer app / shop page: one profile by mobile login — Customer ID, projects (+warranty, AMC), products (+warranty), services (+status), pending quotations
create or replace function public.crm_consumer_profile(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u public.crm_users := public.crm_csession(p ->> 'token'); pt public.crm_records; q public.crm_records; inv public.crm_records; l jsonb; k text; card jsonb; wl jsonb;
        bills jsonb := '[]'::jsonb; projects jsonb := '[]'::jsonb; services jsonb := '[]'::jsonb; inquiries jsonb := '[]'::jsonb; products jsonb := '[]'::jsonb; cid text; it public.crm_records; qk text;
begin
  select * into pt from public.crm_records where kind = 'party' and deleted_at is null and mobile = u.mobile and u.mobile ~ '^[6-9][0-9]{9}$' and coalesce(data ->> 'type', 'customer') <> 'supplier' order by id limit 1;
  if pt.id is null then
    select data ->> 'cust_id' into cid from public.crm_records where kind = 'lead' and deleted_at is null and mobile = u.mobile order by id limit 1;
    return jsonb_build_object('cust_id', cid, 'stage', 'lead', 'name', u.name, 'mobile', u.mobile, 'projects', projects, 'services', services, 'products', products, 'inquiries', inquiries, 'bills', bills);
  end if;
  for q in select * from public.crm_records where kind = 'quote' and party_id = pt.id and deleted_at is null order by id loop
    k := case when q.data ->> 'ctype' in ('Residential', 'Commercial', 'Industrial', 'VFD') then 'project' when q.data ->> 'ctype' = 'Items only' then 'product' when coalesce(q.data ->> 'ctype', '') = '' then 'project' else 'service' end;
    if q.status in ('accepted', 'converted') then
      if k = 'product' then continue; end if;
      insert into public.crm_consumer_plants(user_id, quote_id) values (u.id, q.id) on conflict do nothing;
      card := public.crm_plant_card(q);
      wl := '[]'::jsonb;
      for l in select * from jsonb_array_elements(coalesce(q.data -> 'lines', '[]'::jsonb)) loop
        select * into it from public.crm_records where id = nullif(l ->> 'item_id', '')::bigint and kind = 'item';
        if it.id is not null and coalesce(it.data ->> 'warranty', '') <> '' then wl := wl || jsonb_build_array(jsonb_build_object('name', coalesce(l ->> 'name', it.title), 'warranty', it.data ->> 'warranty')); end if;
      end loop;
      card := card || jsonb_build_object('kind', k, 'warranty', wl, 'job_status', case when (q.data ->> 'closed') = 'true' then 'Poora hua' else 'Chal raha hai' end);
      if k = 'project' then projects := projects || jsonb_build_array(card); else services := services || jsonb_build_array(card); end if;
    elsif q.status in ('draft', 'sent') then
      inquiries := inquiries || jsonb_build_array(jsonb_build_object('id', q.id, 'ref', q.ref, 'title', coalesce(q.data ->> 'qtitle', q.title), 'kind', k, 'status', case q.status when 'sent' then 'Quotation bheji gayi' else 'Taiyaar ho rahi hai' end));
    end if;
  end loop;
  for inv in select i.* from public.crm_records i where i.kind = 'invoice' and i.party_id = pt.id and i.deleted_at is null order by i.id loop
    bills := bills || jsonb_build_array(jsonb_build_object('id', inv.id, 'ref', inv.ref, 'date', inv.data ->> 'date', 'title', coalesce(inv.data ->> 'qtitle', inv.title), 'amount', inv.amount, 'paid', coalesce((inv.data ->> 'paid')::numeric, 0), 'balance', coalesce((inv.data ->> 'balance')::numeric, inv.amount), 'due_date', nullif(coalesce(inv.data ->> 'due_date', inv.due_at::text), ''),
      'state', case when (inv.data ->> 'cancelled') = 'true' then 'cancelled' when coalesce((inv.data ->> 'balance')::numeric, inv.amount) <= 0.009 then 'paid' else 'pending' end, 'nonrefundable', coalesce((inv.data ->> 'refund_ok')::boolean, false) = false));
    qk := null;
    select case when q2.data ->> 'ctype' = 'Items only' then 'product' else 'other' end into qk from public.crm_records q2 where q2.id = nullif(inv.data ->> 'quote_id', '')::bigint;
    if qk = 'other' then continue; end if;
    for l in select * from jsonb_array_elements(coalesce(inv.data -> 'lines', '[]'::jsonb)) loop
      select * into it from public.crm_records where id = nullif(l ->> 'item_id', '')::bigint and kind = 'item';
      products := products || jsonb_build_array(jsonb_build_object('name', coalesce(l ->> 'name', it.title), 'qty', l -> 'qty', 'bill', inv.ref, 'date', inv.data ->> 'date', 'brand', it.data ->> 'brand', 'warranty', nullif(it.data ->> 'warranty', ''), 'paid', coalesce((inv.data ->> 'balance')::numeric, inv.amount) <= 0.009));
    end loop;
  end loop;
  return jsonb_build_object('cust_id', pt.data ->> 'cust_id', 'stage', coalesce(pt.data ->> 'stage', 'customer'), 'name', pt.title, 'mobile', pt.mobile,
    'projects', projects, 'services', services, 'products', products, 'inquiries', inquiries, 'bills', bills);
end $$;
grant execute on function public.crm_consumer_profile(jsonb) to anon, authenticated;
