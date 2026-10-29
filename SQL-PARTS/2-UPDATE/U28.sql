-- ============================================================================
-- SUNPOWERS — DATABASE UPDATE — part 28 of 30
-- Purane project par update (naya ya purana, dono par chalega).
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (U01 -> U30). Safe to re-run.
-- ============================================================================

-- 6) link kholne par disclaimer bhi aata hai (sirf jab Accept ho sakta hai)
create or replace function public.sp_share_open(p_token text, p_count boolean default false) returns jsonb language plpgsql security definer set search_path = public as $f$
declare r public.sp_shares; q public.crm_records; pub jsonb; amt numeric; pay jsonb; tp jsonb;
begin
  select * into r from public.sp_shares where token = btrim(coalesce(p_token, ''));
  if r.id is null then return null; end if;
  if r.revoked or r.expires_at <= now() then
    return jsonb_build_object('state', case when r.revoked then 'paused' else 'expired' end, 'kind', r.kind, 'brand', r.brand, 'phone', r.phone);
  end if;
  if r.live and r.quote_id is not null then
    select * into q from public.crm_records where id = r.quote_id and kind = 'quote' and deleted_at is null;
    if q.id is null then return jsonb_build_object('state', 'expired', 'kind', r.kind, 'brand', r.brand, 'phone', r.phone); end if;
    pub := public.crm__quote_pub(q);
    begin tp := public.crm__terms_for(q); exception when others then tp := null; end;
  end if;
  if p_count then update public.sp_shares set views = views + 1, first_view = coalesce(first_view, now()), last_view = now() where id = r.id; end if;
  begin pay := public.crm__pay_box(r, q); exception when others then pay := null; end;
  if pub is not null then
    amt := case when q.data -> 'locked' is not null or jsonb_array_length(pub -> 'opts') = 1 then public.crm_num(q.data -> 'grand') end;
    return jsonb_strip_nulls(jsonb_build_object('kind', r.kind, 'title', coalesce(nullif(pub ->> 'title', ''), r.title), 'subtitle', r.subtitle, 'amount', amt, 'valid_till', q.data ->> 'valid_till', 'details', '[]'::jsonb,
      'pdf_url', null, 'view_url', null, 'file_name', r.file_name, 'brand', r.brand, 'phone', r.phone, 'created_at', r.created_at, 'live', true, 'quote', pub, 'pay', pay, 'terms', tp));
  end if;
  return jsonb_strip_nulls(jsonb_build_object('kind', r.kind, 'title', r.title, 'subtitle', r.subtitle, 'amount', r.amount, 'valid_till', r.valid_till, 'details', r.details,
    'pdf_url', r.pdf_url, 'view_url', r.view_url, 'file_name', r.file_name, 'brand', r.brand, 'phone', r.phone, 'created_at', r.created_at, 'pay', pay));
end $f$;
grant execute on function public.sp_share_open(text, boolean) to anon, authenticated;

-- 6b) staff manual "Accepted" (customer link se nahi): record ki customer ka disclaimer nahi bhara gaya
create or replace function public.crm__terms_manual_trg() returns trigger language plpgsql security definer set search_path = public as $f$
begin
  if new.kind = 'quote' and new.status = 'accepted' and old.status is distinct from 'accepted' and (new.data -> 'terms_ok') is null and (new.data -> 'terms_manual') is null
     and public.crm__terms_for(new) is not null and coalesce(current_setting('sp.order_job', true), '') <> '1' and coalesce(current_setting('sp.link_accept', true), '') <> '1' then
    new.data := new.data || jsonb_build_object('terms_manual', jsonb_build_object('at', now(), 'note', 'Customer ne link par disclaimer nahi bhara — staff ne manual accept kiya'));
  end if;
  return new;
end $f$;
drop trigger if exists crm_terms_manual_trg on public.crm_records;
create trigger crm_terms_manual_trg before update on public.crm_records for each row execute function public.crm__terms_manual_trg();

-- 7) Settings save: Disclaimer text badle to bhi Activity log me likha jaye
create or replace function public.crm_settings_save(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare s public.crm_ses := public.crm_session(p ->> 'token'); d jsonb := p -> 'data'; oc jsonb; k text; chg text := ''; tchg text := '';
begin
  perform public.crm_need(s, 'settings.manage');
  if jsonb_typeof(d) <> 'object' or length(d::text) > 400000 then raise exception 'Data galat hai'; end if;
  select data -> 'company' into oc from public.crm_settings where id = 1;
  foreach k in array array['bank_holder', 'bank_name', 'bank_acc', 'bank_ifsc', 'upi', 'pay_link', 'pay_box'] loop
    if coalesce(oc ->> k, '') is distinct from coalesce(d #>> array['company', k], '') then chg := chg || (case when chg = '' then '' else ', ' end) || k; end if;
  end loop;
  foreach k in array array['terms_product', 'terms_install'] loop
    if coalesce(oc ->> k, '') is distinct from coalesce(d #>> array['company', k], '') then tchg := tchg || (case when tchg = '' then '' else ', ' end) || k; end if;
  end loop;
  update public.crm_settings set data = (d - 'secrets' - 'auth') || jsonb_build_object('auth', coalesce(data -> 'auth', '{}'::jsonb)),
    secrets = case when d ? 'secrets' and jsonb_typeof(d -> 'secrets') = 'object' then ((d -> 'secrets') - 'resend_api_key' - 'conn') || jsonb_strip_nulls(jsonb_build_object('resend_api_key', secrets -> 'resend_api_key', 'conn', secrets -> 'conn')) else secrets end,
    updated_at = now() where id = 1;
  perform public.crm_log(s, 'settings', null, null, 'Company settings badli');
  if chg <> '' then perform public.crm_log(s, 'settings', null, null, 'PAYMENT DETAILS badli: ' || chg); end if;
  if tchg <> '' then perform public.crm_log(s, 'settings', null, null, 'DISCLAIMER text badla: ' || tchg); end if;
  return jsonb_build_object('ok', true);
end $f$;

-- 4) Customer ko "Advance" shabd nahi: reminder ka text "Bill amount / pehla payment"
do $do$ declare fn oid; src text;
begin
  for fn in select p.oid from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and pg_get_functiondef(p.oid) like '%advance ke liye call karein%' loop
    src := replace(pg_get_functiondef(fn), 'advance ke liye call karein', 'bill amount (pehla payment) ke liye call karein');
    execute src;
  end loop;
end $do$;

-- 8) Part-wise payment dabba SIRF manual (offline) ke liye — Online Store order ka quotation / bill par nahi (online me poora paisa ek baar)
create or replace function public.crm__pay_box(r public.sp_shares, q public.crm_records) returns jsonb language plpgsql stable security definer set search_path = public as $f$
declare co jsonb; upi text; acc text; lnk text; inv public.crm_records; tot numeric; rest_ numeric; ref_ text; nm text;
begin
  select data -> 'company' into co from public.crm_settings where id = 1;
  co := coalesce(co, '{}'::jsonb);
  if coalesce(co ->> 'pay_box', '1') = '0' then return null; end if;
  upi := btrim(coalesce(co ->> 'upi', ''));
  if upi !~ '^[A-Za-z0-9._-]{2,64}@[A-Za-z0-9.-]{2,32}$' then upi := ''; end if;
  acc := btrim(coalesce(co ->> 'bank_acc', ''));
  lnk := btrim(coalesce(co ->> 'pay_link', ''));
  if lnk !~ '^https://[^[:space:]<>"'']{4,255}$' then lnk := ''; end if;
  if upi = '' and acc = '' and lnk = '' then return null; end if;
  if q.id is not null then
    -- live quotation: payment sirf customer ke Accept (lock) ke baad. Pehle payment par koi limit nahi (customer jitna chahe de) — QR me rakam locked nahi
    if q.data ? 'order_id' then return null; end if;   -- online order: poora paisa ek baar me (part-wise sirf manual me)
    if q.data -> 'locked' is null or q.status in ('rejected', 'expired', 'draft') then return null; end if;
    tot := public.crm_num(q.data -> 'grand'); rest_ := tot; ref_ := q.ref;
  elsif r.kind = 'bill' and coalesce(r.ref, '') ~ '^rec:[0-9]+$' then
    select * into inv from public.crm_records where id = substr(r.ref, 5)::bigint and kind = 'invoice' and deleted_at is null;
    if inv.id is null or coalesce(inv.data ->> 'cancelled', '') in ('true', '1') or inv.data ? 'order_id' then return null; end if;   -- online order ka bill: part-wise nahi
    tot := public.crm_num(inv.data -> 'grand'); rest_ := public.crm_num(coalesce(inv.data -> 'balance', inv.data -> 'grand'));
    if rest_ <= 0 then return jsonb_build_object('paid', true); end if;
    ref_ := inv.ref;
  else
    return null;
  end if;
  nm := coalesce(nullif(btrim(co ->> 'bank_holder'), ''), nullif(btrim(co ->> 'legal'), ''), nullif(btrim(co ->> 'name'), ''), 'Sunpowers');
  return jsonb_strip_nulls(jsonb_build_object('upi', nullif(upi, ''), 'payee', nm, 'total', case when tot > 0 then tot end, 'paid', case when tot > rest_ then tot - rest_ end, 'rest', case when rest_ > 0 then rest_ end, 'ref', ref_, 'link', nullif(lnk, ''),
    'bank', case when acc <> '' then jsonb_strip_nulls(jsonb_build_object('holder', nullif(btrim(co ->> 'bank_holder'), ''), 'name', nullif(btrim(co ->> 'bank_name'), ''), 'acc', acc, 'ifsc', nullif(upper(btrim(co ->> 'bank_ifsc')), ''))) end));
end $f$;
revoke all on function public.crm__pay_box(public.sp_shares, public.crm_records) from public, anon, authenticated;

-- ===== U29 (Round 59): disclaimer chhota (ek tick) + install disclaimer me prakritik aapda ki ek line =====
-- Dobara chalane se koi nuksan nahi.
create or replace function public.crm__terms_pack(kinds text[]) returns jsonb language plpgsql stable security definer set search_path = public as $f$
declare co jsonb; k text; items jsonb := '[]'::jsonb; pts jsonb; ttl jsonb; ov text; line text;
begin
  select data -> 'company' into co from public.crm_settings where id = 1; co := coalesce(co, '{}'::jsonb);
  foreach k in array coalesce(kinds, '{}'::text[]) loop
    if k not in ('product', 'install') then continue; end if;
    ov := btrim(coalesce(co ->> ('terms_' || k), ''));
    if ov <> '' then
      pts := '[]'::jsonb;
      foreach line in array regexp_split_to_array(ov, E'\\r?\\n') loop
        if btrim(line) <> '' then pts := pts || jsonb_build_array(jsonb_build_object('h', left(btrim(line), 600), 'e', left(btrim(line), 600))); end if;
      end loop;
    elsif k = 'product' then
      pts := jsonb_build_array(
        jsonb_build_object('h', 'प्रोडक्ट की वारंटी / गारंटी / सर्विस सिर्फ़ उस प्रोडक्ट की निर्माता (मैन्युफैक्चरिंग) कंपनी की ज़िम्मेदारी है। Sunpowers सिर्फ़ विक्रेता / सप्लायर है; वारंटी या मैन्युफैक्चरिंग डिफ़ेक्ट की ज़िम्मेदारी Sunpowers की नहीं होगी। क्लेम के लिए निर्माता के अधिकृत सर्विस सेंटर से संपर्क करना होगा (Sunpowers सहायता करेगा)।',
          'e', 'Warranty / guarantee / service of a product is the responsibility of its manufacturer only. Sunpowers is only the seller / supplier and is not responsible for warranty or manufacturing defects. Claims go through the manufacturer''s authorised service centre (Sunpowers will assist).'),
        jsonb_build_object('h', 'वारंटी तभी मान्य होगी जब प्रोडक्ट निर्माता की शर्तों के अनुसार लगाया और चलाया गया हो। ग़लत इस्तेमाल, पानी, बिजली के झटके (surge) या छेड़छाड़ पर वारंटी लागू नहीं होती।',
          'e', 'Warranty applies only if the product is installed and used as per the manufacturer''s conditions. Misuse, water damage, power surge or tampering voids it.'),
        jsonb_build_object('h', 'डिलीवरी के समय पैकिंग / प्रोडक्ट जाँच लें और कमी हो तो तुरंत बताएँ। भुगतान, रिफ़ंड, शिपिंग और Terms पेज की शर्तें भी लागू हैं।',
          'e', 'Please check the packing / product at delivery and report any issue immediately. The Payment, Refund, Shipping and Terms pages also apply.'));
    else
      pts := jsonb_build_array(
        jsonb_build_object('h', 'इंस्टॉलेशन के दौरान Sunpowers के टेक्नीशियन मानक (standard) टूल्स और पूरी सावधानी / प्रिकॉशन के साथ काम करते हैं। छत में ड्रिल / छेद करना इंस्टॉलेशन का ज़रूरी हिस्सा है।',
          'e', 'Sunpowers technicians work with standard tools and full precautions. Drilling holes in the roof is a necessary part of installation.'),
        jsonb_build_object('h', 'छत की क्वालिटी / हालत (पुरानी या कमज़ोर छत, पतला स्लैब, दरार, सीलन, अंदर छिपे पाइप / सरिया / वायरिंग) पर ड्रिलिंग का नतीजा निर्भर करता है। अगर छेद आर-पार हो जाए, दरार, सीलन, लीकेज या कोई और नुकसान हो, तो यह छत की स्थिति पर निर्भर है और इसकी ज़िम्मेदारी Sunpowers की नहीं होगी। छत की किसी पुरानी कमज़ोरी की जानकारी ग्राहक काम से पहले टेक्नीशियन को देगा।',
          'e', 'The result of drilling depends on the quality / condition of your roof (old or weak roof, thin slab, cracks, dampness, hidden pipes / rods / wiring). If a hole goes through, or cracks, seepage, leakage or other damage occurs, it depends on the roof condition and Sunpowers is not responsible. The customer will tell the technician about any known weakness before work starts.'),
        jsonb_build_object('h', 'इंस्टॉलेशन एरिया / छत पर सिर्फ़ Sunpowers के टेक्नीशियन रहेंगे। ग्राहक, परिवार के सदस्य, बच्चे, पड़ोसी या कोई भी अनधिकृत (unauthorised) व्यक्ति इंस्टॉलेशन के दौरान वहाँ नहीं जाएगा — यह प्रतिबंधित है। ऐसा होने पर बिजली का झटका, गिरना, चोट या कोई भी दुर्घटना हो तो उसकी ज़िम्मेदारी ग्राहक की होगी, Sunpowers की नहीं।',
          'e', 'Only Sunpowers technicians may be in the installation area / on the roof. The customer, family members, children, neighbours or any unauthorised person must not go there during installation — it is prohibited. If an electric shock, fall, injury or any accident happens in that case, the customer is responsible, not Sunpowers.'),
        jsonb_build_object('h', 'ग्राहक छत तक सुरक्षित पहुँच, ज़रूरत पर बिजली बंद / चालू करने की अनुमति और काम के लिए जगह उपलब्ध कराएगा। काम के दौरान पैनल, इन्वर्टर या वायर को हाथ नहीं लगाएगा।',
          'e', 'The customer will provide safe access to the roof, permission to switch power off / on when needed, and space to work. Do not touch panels, inverter or wires during work.'),
        jsonb_build_object('h', 'सब्सिडी, नेट मीटरिंग और अप्रूवल DISCOM / सरकार के नियम और समय पर निर्भर हैं; इनकी गारंटी नहीं है। मौसम या DISCOM की वजह से देरी Sunpowers के नियंत्रण से बाहर है।',
          'e', 'Subsidy, net metering and approvals depend on DISCOM / government rules and timelines and are not guaranteed. Delays due to weather or DISCOM are outside Sunpowers'' control.'),
        jsonb_build_object('h', 'काम पूरा होने के बाद प्राकृतिक आपदा (आंधी-तूफ़ान, ओले, भूकंप, बाढ़, आसमानी बिजली, टर्नेडो आदि) से हुए नुकसान की ज़िम्मेदारी Sunpowers की नहीं होगी। यह हमारे इंस्टॉलेशन की अपनी ख़राबी पर लागू नहीं होता।',
          'e', 'Damage caused by natural disasters (storm, hail, earthquake, flood, lightning, tornado etc.) after the work is done is not Sunpowers'' responsibility. This does not apply to defects in our own installation work.'));
    end if;
    ttl := case k when 'product' then jsonb_build_object('h', 'प्रोडक्ट — वारंटी और ज़िम्मेदारी', 'e', 'Product — warranty and responsibility') else jsonb_build_object('h', 'इंस्टॉलेशन — छत और साइट की सुरक्षा', 'e', 'Installation — roof and site safety') end;
    items := items || jsonb_build_array(jsonb_build_object('k', k, 'title', ttl, 'points', pts));
  end loop;
  if jsonb_array_length(items) = 0 then return null; end if;
  return jsonb_build_object('ver', left(md5(items::text), 8), 'items', items);
end $f$;
revoke all on function public.crm__terms_pack(text[]) from public, anon, authenticated;

-- ===== U30 (Round 60): "Kahan bechna hai" — har item ke liye India / State / District niyam (delivery din + payment tarika + band switch) + Emergency =====
-- Dobara chalane se koi nuksan nahi. Purane sp_pin_* system par hi jud'ta hai (sp_pin_check / sp_pin_guard / sp_place_order wahi, bas ab ye niyam bhi dekhte hain).
-- Rule jeetne ka kram: District > State > Poora Bharat. Jis item ki koi jagah chuni hi nahi wo purane tarike se chalta hai (sab jagah), jab tak "only_chosen" switch chalu na ho.
-- Emergency chalu ho to pin / location dene ke baad har item "uplabdh nahi" dikhta hai (kimat dikhti hai, order nahi hota).

create table if not exists public.sp_sell (
  item_id    text not null,
  scope      text not null check (scope in ('all', 'state', 'district')),
  value      text not null,                       -- all='*' | state='UTTAR PRADESH' | district='UTTAR PRADESH|LUCKNOW'
  eta_min    int  not null default 0 check (eta_min between 0 and 365),
  eta_max    int  not null default 0 check (eta_max between 0 and 365),
  pay        text not null default 'both' check (pay in ('both', 'prepaid')),
  off        boolean not null default false,      -- is jagah par "abhi band" (Out of stock)
  updated_at timestamptz not null default now(),
  primary key (item_id, scope, value)
);
create index if not exists sp_sell_sv on public.sp_sell (scope, value);

create table if not exists public.sp_sell_cfg (
  id         int primary key default 1 check (id = 1),
  emergency  boolean not null default false,      -- ek click: poora Shop page + Store App out of stock (pin dalne ke baad dikhta hai)
  only_chosen     boolean not null default false,      -- jis item ki koi jagah nahi chuni wo kahin nahi bikega
  note       text not null default '',
  updated_at timestamptz not null default now()
);
insert into public.sp_sell_cfg(id) values (1) on conflict (id) do nothing;

alter table public.sp_sell enable row level security;
alter table public.sp_sell_cfg enable row level security;
do $$ begin revoke all on public.sp_sell, public.sp_sell_cfg from anon, authenticated; exception when undefined_object then null; end $$;

-- ---------- core: in items me se har ek par is pin ka sabse specific niyam -----------------------------
create or replace function public.sp_sell_best(p_pin text, p_ids text[])
returns table (r_id text, r_has boolean, r_ok boolean, r_min int, r_max int, r_pay text)
language plpgsql stable security definer set search_path = public as $$
declare st text; di text; stc boolean;
begin
  select state_u, district_u into st, di from public.sp_pin_master where pincode = p_pin;
  select coalesce(only_chosen, false) into stc from public.sp_sell_cfg where id = 1;
  return query
  with ids as (select distinct x as id from unnest(coalesce(p_ids, '{}'::text[])) x where x is not null),
  hasrows as (select distinct s.item_id from public.sp_sell s where s.item_id in (select id from ids)),
  cand as (
    select s.item_id, s.off, s.eta_min, s.eta_max, s.pay,
           case s.scope when 'district' then 3 when 'state' then 2 else 1 end as rk
    from public.sp_sell s
    where s.item_id in (select item_id from hasrows)
      and (s.scope = 'all'
           or (s.scope = 'state' and st is not null and s.value = st)
           or (s.scope = 'district' and st is not null and s.value = st || '|' || di))
  ),
  best as (select distinct on (c.item_id) c.* from cand c order by c.item_id, c.rk desc)
  select i.id,
         (h.item_id is not null or coalesce(stc, false)),
         (b.item_id is not null and not b.off),
         b.eta_min, b.eta_max, b.pay
  from ids i
  left join hasrows h on h.item_id = i.id
  left join best b on b.item_id = i.id;
end $$;

-- ---------- sp_pin_unavail: purana niyam ab "core" hai; naya = core + sell niyam + emergency ----------------
do $do$ declare src text;
begin
  if to_regprocedure('public.sp_pin_unavail_core(text,text[])') is null then
    alter function public.sp_pin_unavail(text, text[]) rename to sp_pin_unavail_core;
  else
    -- U03 dobara chala ho to wo asli function wapas bana deta hai: use "core" bana do
    src := pg_get_functiondef('public.sp_pin_unavail(text,text[])'::regprocedure);
    if position('sp_sell' in src) = 0 then
      drop function public.sp_pin_unavail_core(text, text[]);
      alter function public.sp_pin_unavail(text, text[]) rename to sp_pin_unavail_core;
    end if;
  end if;
end $do$;
revoke all on function public.sp_pin_unavail_core(text, text[]) from public, anon, authenticated;

create or replace function public.sp_pin_unavail(p_pin text, p_ids text[]) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare a text[]; b text[]; emg boolean;
begin
  select emergency into emg from public.sp_sell_cfg where id = 1;
  if coalesce(emg, false) then
    return coalesce((select array_agg(distinct x order by x) from unnest(coalesce(p_ids, '{}'::text[])) x where x is not null), '{}');
  end if;
  a := public.sp_pin_unavail_core(p_pin, p_ids);
  select coalesce(array_agg(r_id), '{}') into b from public.sp_sell_best(p_pin, p_ids) where r_has and not r_ok;
  return coalesce((select array_agg(x order by x) from (select unnest(coalesce(a, '{}'::text[])) as x union select unnest(b)) q), '{}');
end $$;
revoke all on function public.sp_pin_unavail(text, text[]) from public, anon, authenticated;

-- koi bhi niyam / emergency / only_chosen ho to storefront par pin maangna chalu
create or replace function public.sp_pin_enabled() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.sp_pin_rules) or exists (select 1 from public.sp_pin_modes where mode = 'only')
      or exists (select 1 from public.sp_sell) or exists (select 1 from public.sp_sell_cfg where emergency or only_chosen)
$$;

-- ---------- customer: pin dalte hi kya dikhega (sirf padhta hai) -----------------------------------------
create or replace function public.sp_pin_check(p_pin text, p_ids jsonb default '[]'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pin text := regexp_replace(coalesce(p_pin, ''), '\D', '', 'g'); ids text[]; en boolean := public.sp_pin_enabled(); m record; kn boolean;
        cfg public.sp_sell_cfg; info jsonb := '{}'::jsonb;
begin
  if jsonb_typeof(coalesce(p_ids, '[]'::jsonb)) <> 'array' then raise exception 'Invalid list'; end if;
  if jsonb_array_length(coalesce(p_ids, '[]'::jsonb)) > 2000 then raise exception 'Too many products'; end if;
  if pin !~ '^[1-9][0-9]{5}$' then return jsonb_build_object('enabled', en, 'valid', false, 'bad', '[]'::jsonb); end if;
  select * into m from public.sp_pin_master where pincode = pin; kn := found;
  if not en then
    return jsonb_build_object('enabled', false, 'valid', true, 'pin', pin, 'known', kn, 'state', coalesce(m.state, ''), 'district', coalesce(m.district, ''), 'bad', '[]'::jsonb);
  end if;
  select * into cfg from public.sp_sell_cfg where id = 1;
  select coalesce(array_agg(x), '{}') into ids from jsonb_array_elements_text(coalesce(p_ids, '[]'::jsonb)) x;
  if not coalesce(cfg.emergency, false) then
    select coalesce(jsonb_object_agg(r_id, jsonb_build_object('min', r_min, 'max', r_max, 'pay', r_pay)), '{}'::jsonb) into info
      from public.sp_sell_best(pin, ids) where r_has and r_ok and r_pay is not null;
  end if;
  return jsonb_build_object('enabled', true, 'valid', true, 'pin', pin, 'known', kn, 'state', coalesce(m.state, ''), 'district', coalesce(m.district, ''),
                            'bad', to_jsonb(public.sp_pin_unavail(pin, ids)), 'info', info,
                            'emg', coalesce(cfg.emergency, false), 'emg_note', case when coalesce(cfg.emergency, false) then coalesce(cfg.note, '') else '' end);
end $$;

-- ---------- order ke time: prepaid-only jagah par COD nahi chalega (server bhi rokta hai) ----------------
create or replace function public.sp_sell_pay_guard(p_pin text, p_items jsonb, p_payment text) returns void
language plpgsql stable security definer set search_path = public as $$
declare pin text := regexp_replace(coalesce(p_pin, ''), '\D', '', 'g'); ids text[]; names text;
begin
  if lower(coalesce(p_payment, '')) <> 'cod' then return; end if;
  if pin !~ '^[1-9][0-9]{5}$' then return; end if;
  select coalesce(array_agg(i ->> 'id'), '{}') into ids from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) i where coalesce(i ->> 'id', '') <> '';
  select string_agg(r_id, ', ') into names from public.sp_sell_best(pin, ids) where r_has and r_ok and r_pay = 'prepaid';
  if names is not null then
    raise exception 'PREPAID_ONLY_AT_PIN: Pincode % par in items me COD nahi hai, pura payment pehle dena hoga: %', pin, left(names, 200);
  end if;
end $$;
revoke all on function public.sp_sell_pay_guard(text, jsonb, text) from public, anon, authenticated;

do $do$ declare src text;
begin
  src := pg_get_functiondef('public.sp_place_order(jsonb)'::regprocedure);
  if position('sp_sell_pay_guard' in src) = 0 then
    src := replace(src, '  perform public.sp_pin_guard(', E'  perform public.sp_sell_pay_guard(p_order ->> ''pincode'', p_order -> ''items'', p_order ->> ''payment'');\n  perform public.sp_pin_guard(');
    execute src;
  end if;
end $do$;

-- ============================ ADMIN (Store Admin: sp_check) ============================
create or replace function public.sp_sell_val(p_scope text, p_value text) returns text language plpgsql immutable as $$
declare a text; b text;
begin
  if p_scope = 'all' then return '*'; end if;
  if p_scope = 'state' then a := public.sp_pin_norm(p_value); return nullif(a, ''); end if;
  if p_scope = 'district' then
    a := public.sp_pin_norm(split_part(coalesce(p_value, ''), '|', 1)); b := public.sp_pin_norm(split_part(coalesce(p_value, ''), '|', 2));
    if a = '' or b = '' then return null; end if;
    return a || '|' || b;
  end if;
  return null;
end $$;

-- ek item ki saari jagah
create or replace function public.sp_sell_get(p_pass text, p_item text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  perform public.sp_check(p_pass);
  return coalesce((select jsonb_agg(jsonb_build_object('scope', scope, 'value', value, 'eta_min', eta_min, 'eta_max', eta_max, 'pay', pay, 'off', off)
                   order by (case scope when 'all' then 0 when 'state' then 1 else 2 end), value)
                   from public.sp_sell where item_id = p_item), '[]'::jsonb);
end $$;

-- kai items par ek saath lagayein. mode: 'replace' (purani jagah hata kar sirf ye) | 'merge' (jodein / badlein)
create or replace function public.sp_sell_apply(p_pass text, p_items jsonb, p_rows jsonb, p_mode text default 'merge') returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare it text; r jsonb; sc text; v text; n int := 0; ni int := 0; em int; ex int; py text;
begin
  perform public.sp_check(p_pass);
  if jsonb_typeof(p_items) <> 'array' or jsonb_typeof(p_rows) <> 'array' then raise exception 'Invalid data'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'Koi item nahi chuna'; end if;
  if jsonb_array_length(p_items) > 800 then raise exception 'Ek baar me 800 se zyada item nahi'; end if;
  if jsonb_array_length(p_rows) > 3000 then raise exception 'Ek baar me 3000 se zyada jagah nahi'; end if;
  if p_mode not in ('merge', 'replace') then raise exception 'Mode galat'; end if;
  for it in select x from jsonb_array_elements_text(p_items) x loop
    if coalesce(it, '') = '' then continue; end if;
    if p_mode = 'replace' then delete from public.sp_sell where item_id = it; end if;
    for r in select * from jsonb_array_elements(p_rows) loop
      sc := coalesce(r ->> 'scope', ''); v := public.sp_sell_val(sc, r ->> 'value');
      if v is null then continue; end if;
      em := greatest(0, least(365, coalesce(nullif(r ->> 'eta_min', '')::int, 0)));
      ex := greatest(0, least(365, coalesce(nullif(r ->> 'eta_max', '')::int, 0)));
      if ex < em then ex := em; end if;
      py := case when r ->> 'pay' = 'prepaid' then 'prepaid' else 'both' end;
      insert into public.sp_sell(item_id, scope, value, eta_min, eta_max, pay, off)
      values (it, sc, v, em, ex, py, coalesce((r ->> 'off')::boolean, false))
      on conflict (item_id, scope, value) do update set eta_min = excluded.eta_min, eta_max = excluded.eta_max, pay = excluded.pay, off = excluded.off, updated_at = now();
      n := n + 1;
    end loop;
    ni := ni + 1;
  end loop;
  return jsonb_build_object('items', ni, 'rows', n);
end $$;

-- kisi jagah ko hatana (items me se)
create or replace function public.sp_sell_remove(p_pass text, p_items jsonb, p_scope text, p_value text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v text := public.sp_sell_val(p_scope, p_value); n int;
begin
  perform public.sp_check(p_pass);
  if v is null then raise exception 'Jagah galat'; end if;
  delete from public.sp_sell where scope = p_scope and value = v and item_id in (select x from jsonb_array_elements_text(p_items) x);
  get diagnostics n = row_count; return jsonb_build_object('deleted', n);
end $$;

-- kisi ek jagah par "abhi band / chalu" (kai items ek saath). Jagah pehle se chuni na ho to band karne par uske liye band-row ban jaati hai.
create or replace function public.sp_sell_off(p_pass text, p_items jsonb, p_scope text, p_value text, p_off boolean) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v text := public.sp_sell_val(p_scope, p_value); n int := 0; it text; c int;
begin
  perform public.sp_check(p_pass);
  if v is null then raise exception 'Jagah galat'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 1500 then raise exception 'Items galat'; end if;
  for it in select x from jsonb_array_elements_text(p_items) x loop
    update public.sp_sell set off = coalesce(p_off, false), updated_at = now() where item_id = it and scope = p_scope and value = v;
    get diagnostics c = row_count;
    if c = 0 and coalesce(p_off, false) then
      -- jis item ki koi jagah chuni hi nahi thi (sab jagah chal raha tha) use sirf ek jagah band karne par baaki jagah band na ho: pehle "Poora Bharat" chalu row
      if not exists (select 1 from public.sp_sell where item_id = it) then
        insert into public.sp_sell(item_id, scope, value) values (it, 'all', '*') on conflict do nothing;
      end if;
      insert into public.sp_sell(item_id, scope, value, off) values (it, p_scope, v, true) on conflict do nothing; c := 1;
    end if;
    n := n + c;
  end loop;
  return jsonb_build_object('changed', n);
end $$;

-- "Jagah-wise" screen: is jagah par kaun se items ke niyam hain
create or replace function public.sp_sell_place_list(p_pass text, p_scope text, p_value text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare v text := public.sp_sell_val(p_scope, p_value);
begin
  perform public.sp_check(p_pass);
  if v is null then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('item_id', item_id, 'eta_min', eta_min, 'eta_max', eta_max, 'pay', pay, 'off', off) order by item_id)
                   from public.sp_sell where scope = p_scope and value = v), '[]'::jsonb);
end $$;

-- sab items ka saar (list par chip dikhane ke liye)
create or replace function public.sp_sell_overview(p_pass text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  perform public.sp_check(p_pass);
  return coalesce((select jsonb_agg(jsonb_build_object('item_id', item_id, 'n', n, 'all', allr, 'all_off', alloff, 'states', st, 'dists', ds, 'off', offn) order by item_id)
    from (select item_id, count(*) n, bool_or(scope = 'all') allr, coalesce(bool_or(scope = 'all' and off), false) alloff,
                 count(*) filter (where scope = 'state') st, count(*) filter (where scope = 'district') ds, count(*) filter (where off) offn
          from public.sp_sell group by item_id) q), '[]'::jsonb);
end $$;

create or replace function public.sp_sell_cfg_get(p_pass text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare c public.sp_sell_cfg;
begin
  perform public.sp_check(p_pass);
  select * into c from public.sp_sell_cfg where id = 1;
  return jsonb_build_object('emergency', c.emergency, 'only_chosen', c.only_chosen, 'note', c.note, 'master', (select count(*) from public.sp_pin_master));
end $$;

create or replace function public.sp_sell_cfg_set(p_pass text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.sp_check(p_pass);
  update public.sp_sell_cfg set
    emergency = coalesce((p ->> 'emergency')::boolean, emergency),
    only_chosen    = coalesce((p ->> 'only_chosen')::boolean, only_chosen),
    note      = case when p ? 'note' then left(coalesce(p ->> 'note', ''), 200) else note end,
    updated_at = now()
  where id = 1;
  return public.sp_sell_cfg_get(p_pass);
end $$;

do $$ begin
  revoke all on function public.sp_sell_best(text, text[]), public.sp_sell_val(text, text) from public, anon, authenticated;
  grant execute on function
    public.sp_pin_check(text, jsonb),
    public.sp_sell_get(text, text), public.sp_sell_apply(text, jsonb, jsonb, text), public.sp_sell_remove(text, jsonb, text, text),
    public.sp_sell_off(text, jsonb, text, text, boolean), public.sp_sell_place_list(text, text, text), public.sp_sell_overview(text),
    public.sp_sell_cfg_get(text), public.sp_sell_cfg_set(text, jsonb)
  to anon, authenticated;
exception when undefined_object then null; end $$;

notify pgrst, 'reload schema';

-- ===== U31 (Round 61): Sarkari SUBSIDY (sirf jankari) — Central PM Surya Ghar + Rajya, sirf Residential On-Grid / Hybrid =====
-- Subsidy bill / quotation ki rakam me se KAM NAHI hoti. Ye sirf jankari ka dabba hai: project rate, Central, Rajya, kul subsidy, anumanit asli kharch.
-- Sunpowers koi subsidy nahi deta — sarkar seedha customer ke bank khate me deti hai. Dobara chalana safe hai (admin ke badle hue amount overwrite nahi hote).
-- Central (MNRE operational guidelines, residential): pehle 2 kW par Rs 30,000/kW, tisre kW par Rs 18,000, 3 kW ke baad koi extra nahi (max Rs 78,000).
--   Special category rajya (North-East, Uttarakhand, Himachal, J&K, Ladakh, A&N, Lakshadweep): Rs 33,000/kW aur Rs 19,800.
--   Off-Grid par CFA nahi. Battery-hybrid: rajya ke bijli aayog ki manzoori ke adheen. Non-residential par nahi.

create table if not exists public.sp_sub_cfg (
  id         int primary key default 1 check (id = 1),
  enabled    boolean not null default true,
  r1         numeric not null default 30000,   -- pehle 2 kW, Rs per kW
  r2         numeric not null default 18000,   -- tisra kW, Rs per kW
  r1_sp      numeric not null default 33000,   -- special category rajya
  r2_sp      numeric not null default 19800,
  cap_kw     numeric not null default 3,       -- is se upar koi extra CFA nahi
  note       text not null default '',
  updated_at timestamptz not null default now()
);
insert into public.sp_sub_cfg(id) values (1) on conflict (id) do nothing;

create table if not exists public.sp_sub_state (
  state_u    text primary key,                 -- UPPER naam
  state      text not null,
  special    boolean not null default false,   -- special category (Central ki dar +10%)
  per_kw     numeric not null default 0,       -- Rs per kW
  cap        numeric not null default 0,       -- max Rs (0 = koi seema nahi)
  fixed      numeric not null default 0,       -- tay raqam (>0 ho to per_kw ki jagah yahi)
  note       text not null default '',
  src        text not null default '',
  verified   boolean not null default false,   -- official site se pakka kiya
  active     boolean not null default false,   -- customer ko dikhana hai ya nahi
  updated_at timestamptz not null default now()
);
alter table public.sp_sub_cfg enable row level security;
alter table public.sp_sub_state enable row level security;
do $$ begin revoke all on public.sp_sub_cfg, public.sp_sub_state from anon, authenticated; exception when undefined_object then null; end $$;

-- 36 rajya / UT (CRM ki list jaisa naam). Pehle se bhare hue ko nahi chhedta.
insert into public.sp_sub_state(state_u, state, special, per_kw, cap, note, src, verified, active) values
 ('ANDAMAN AND NICOBAR ISLANDS', 'Andaman and Nicobar Islands', true, 0, 0, '', '', false, false),
 ('ANDHRA PRADESH', 'Andhra Pradesh', false, 0, 0, '', '', false, false),
 ('ARUNACHAL PRADESH', 'Arunachal Pradesh', true, 0, 0, '', '', false, false),
 ('ASSAM', 'Assam', true, 0, 0, '', '', false, false),
 ('BIHAR', 'Bihar', false, 10000, 20000, 'Rs 10,000/kW, max Rs 20,000 (do news-sources; official se pakka karke chalu karein)', 'news (Saur Energy)', false, false),
 ('CHANDIGARH', 'Chandigarh', false, 0, 0, '', '', false, false),
 ('CHHATTISGARH', 'Chhattisgarh', false, 0, 0, '', '', false, false),
 ('DADRA AND NAGAR HAVELI AND DAMAN AND DIU', 'Dadra and Nagar Haveli and Daman and Diu', false, 0, 0, '', '', false, false),
 ('DELHI', 'Delhi', false, 10000, 30000, 'Rs 10,000/kW, max Rs 30,000 (Delhi cabinet, May 2025 — official site se pakka karke chalu karein)', 'news (Power Line / Energetica)', false, false),
 ('GOA', 'Goa', false, 0, 0, '', '', false, false),
 ('GUJARAT', 'Gujarat', false, 0, 0, 'Naya niyam (22 Oct 2026 ke baad chalu systems, 2.18 kWp tak) — raqam tay nahi, benchmark se nikalti hai; admin pakka karke bharein', '', false, false),
 ('HARYANA', 'Haryana', false, 0, 0, '', '', false, false),
 ('HIMACHAL PRADESH', 'Himachal Pradesh', true, 0, 0, '', '', false, false),
 ('JAMMU AND KASHMIR', 'Jammu and Kashmir', true, 0, 0, '', '', false, false),
 ('JHARKHAND', 'Jharkhand', false, 0, 0, '', '', false, false),
 ('KARNATAKA', 'Karnataka', false, 0, 0, '', '', false, false),
 ('KERALA', 'Kerala', false, 0, 0, '', '', false, false),
 ('LADAKH', 'Ladakh', true, 0, 0, '', '', false, false),
 ('LAKSHADWEEP', 'Lakshadweep', true, 0, 0, '', '', false, false),
 ('MADHYA PRADESH', 'Madhya Pradesh', false, 0, 0, '', '', false, false),
 ('MAHARASHTRA', 'Maharashtra', false, 0, 0, '', '', false, false),
 ('MANIPUR', 'Manipur', true, 0, 0, '', '', false, false),
 ('MEGHALAYA', 'Meghalaya', true, 0, 0, '', '', false, false),
 ('MIZORAM', 'Mizoram', true, 0, 0, '', '', false, false),
 ('NAGALAND', 'Nagaland', true, 0, 0, '', '', false, false),
 ('ODISHA', 'Odisha', false, 0, 0, '', '', false, false),
 ('PUDUCHERRY', 'Puducherry', false, 0, 0, '', '', false, false),
 ('PUNJAB', 'Punjab', false, 0, 0, '', '', false, false),
 ('RAJASTHAN', 'Rajasthan', false, 0, 0, '', '', false, false),
 ('SIKKIM', 'Sikkim', true, 0, 0, '', '', false, false),
 ('TAMIL NADU', 'Tamil Nadu', false, 0, 0, '', '', false, false),
 ('TELANGANA', 'Telangana', false, 0, 0, '', '', false, false),
 ('TRIPURA', 'Tripura', true, 0, 0, '', '', false, false),
 ('UTTAR PRADESH', 'Uttar Pradesh', false, 15000, 30000, 'Rs 15,000/kW, max Rs 30,000, Central ke upar (UPNEDA)', 'UPNEDA FAQ — upneda.org.in', true, true),
 ('UTTARAKHAND', 'Uttarakhand', true, 0, 0, '', '', false, false),
 ('WEST BENGAL', 'West Bengal', false, 0, 0, '', '', false, false)
on conflict (state_u) do nothing;

-- ---------- rajya ka naam ek jaisa karna (CRM ka naam / pin-master ka naam / purane naam) ----------------
create or replace function public.sp_sub_norm(s text) returns text language sql immutable as $$
  select case
    when x in ('ORISSA') then 'ODISHA'
    when x in ('PONDICHERRY') then 'PUDUCHERRY'
    when x in ('NCT OF DELHI', 'NEW DELHI', 'DELHI NCR') then 'DELHI'
    when x in ('UTTARANCHAL') then 'UTTARAKHAND'
    when x in ('JAMMU AND KASHMIR', 'JAMMU KASHMIR') then 'JAMMU AND KASHMIR'
    when x in ('ANDAMAN AND NICOBAR', 'ANDAMAN NICOBAR ISLANDS', 'ANDAMAN AND NICOBAR ISLANDS') then 'ANDAMAN AND NICOBAR ISLANDS'
    when x in ('DADRA AND NAGAR HAVELI', 'DAMAN AND DIU', 'DADRA AND NAGAR HAVELI AND DAMAN AND DIU', 'DAMAN DIU', 'DADRA NAGAR HAVELI') then 'DADRA AND NAGAR HAVELI AND DAMAN AND DIU'
    else x end
  from (select btrim(regexp_replace(regexp_replace(upper(replace(coalesce(s, ''), '&', ' AND ')), '[^A-Z ]', ' ', 'g'), '\s+', ' ', 'g')) x) t
$$;