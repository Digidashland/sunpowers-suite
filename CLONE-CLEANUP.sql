-- ================= PURANE CLONE SAAF KARNE KI SQL (pehle backup, phir STAGING, phir LIVE) =================
-- STEP A: dekhne ke liye (kuch badalta nahi)
select 'customer ke mobile par khuli lead' as kya, count(*) from crm_records l where l.kind='lead' and l.deleted_at is null and l.status not in ('won','lost') and exists (select 1 from crm_records p where p.kind='party' and p.deleted_at is null and p.mobile=l.mobile)
union all
select 'ek mobile par ek se zyada khuli lead (extra)', coalesce(sum(c-1),0) from (select mobile, count(*) c from crm_records where kind='lead' and deleted_at is null and status not in ('won','lost') group by mobile having count(*)>1) x
union all
select 'ek mobile par ek se zyada customer (sirf report, apne aap nahi judte)', coalesce(sum(c-1),0) from (select mobile, count(*) c from crm_records where kind='party' and deleted_at is null and coalesce(data->>'type','customer')<>'supplier' group by mobile having count(*)>1) y;

-- STEP B: safai
begin;
-- B1: customer ban chuke mobile ki khuli lead -> "won" (customer se jodi)
update crm_records l set status='won', party_id=p.id, data=l.data||jsonb_build_object('transferred_party',p.id,'transferred_at',crm_iso_now(),'cleanup','R37'), updated_at=now()
  from crm_records p where l.kind='lead' and l.deleted_at is null and l.status not in ('won','lost') and p.kind='party' and p.deleted_at is null and p.mobile=l.mobile and coalesce(p.data->>'type','customer')<>'supplier';
-- B2: ek mobile ki kai khuli lead -> sabse purani rakho, baaki hata do (note purani me jud jaata hai)
with d as (select id, mobile, row_number() over (partition by mobile order by id) rn, first_value(id) over (partition by mobile order by id) keep from crm_records where kind='lead' and deleted_at is null and status not in ('won','lost'))
update crm_records l set deleted_at=now(), data=l.data||jsonb_build_object('cleanup','R37 duplicate of '||d.keep) from d where l.id=d.id and d.rn>1;
commit;

-- STEP C: ek mobile par ek se zyada customer ho to ye list dekhkar khud tay karein (bill wale customer apne aap nahi mitaye jaate)
select mobile, array_agg(id order by id) ids, array_agg(title order by id) names from crm_records where kind='party' and deleted_at is null and coalesce(data->>'type','customer')<>'supplier' group by mobile having count(*)>1;
