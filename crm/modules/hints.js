/* Help & Hints — sirf Admin ke liye (login / PIN ke niyam yahan hain, users ki screen par nahi) */
(function () {
  'use strict';
  var C = window.CRM;
  var H = [
    ['bolt', 'Round 16: Customer flow (13 step)', [
      'Customer Connect → Starting Conversation → Quotation → Site Visit → Blueprint → Confirmation → Apply Process → Hand Over Technician → Start Installation → Installation Done → Net Meter / Inspection → Finish Work → Subsidy (sirf Residential).',
      'Har step par date + time sabko dikhta hai; step ki detail (note, kisne kiya) sirf unko jinko Admin ne Projects → Access me ijazat di.',
      'Blueprint, documents aur gallery zaroori NAHI hain. Sirf item wala customer Confirmation par khatam hota hai.',
      'Ek customer = ek quotation. Naya plant lagana ho to pehli quotation confirm hone ke baad nayi quotation (naya number) banti hai.',
      'Quotation bhejne se pehle zaroori: naam, mobile, pata, shahar, customer type (Residential / Commercial / Industrial / VFD / Items only) aur project type me kW.'
    ]],
    ['users', 'Leads ke niyam', [
      'Form / signup / ads se aayi lead me naam aur mobile dono zaroori. Manual, Excel ya phone-contacts wali lead me sirf mobile.',
      'Lead tab tak Leads me rehti hai jab tak customer se baat nahi hoti. Baat ke baad "Transfer to Customer list" (lead ka owner / assigned user ya Admin).',
      'Fake lead ko Ignore ya Delete kar sakte hain.'
    ]],
    ['doc', 'Bill, Pending ribbon aur Projects', [
      'Bill kisi bhi raste se (CRM, kisi bhi user se, online auto-bill) ek hi Invoices list me aata hai.',
      'Bill ke baad balance baaki ho to Quotation aur Invoice list me "Pending bill" ribbon dikhta hai; quotation Quotation list se tabhi jaati hai jab final bill ka balance zero ho.',
      'Projects menu = Live tracking. Customer Apply Process par yahan aata hai. Purane final projects Admin allow kare tabhi aate hain. Plants ab Projects ke andar hain.'
    ]],
    ['share', 'Documents & Gallery + Meri Plant', [
      'Documents & Gallery se file / photo / video chunkar customer ko bhejein — customer ka naam aur quotation number file par chhap jata hai.',
      'Customer website / shop / store par login karke "Meri Plant" me Plant ID (= confirmed quotation number) daalta hai. Sirf usi mobile se juda ID chalta hai; galat koshish 15 minute me 8 se zyada nahi.',
      'Customer ko sirf capacity, install date, agli maintenance, payment sthiti, timeline aur apni downloads dikhti hain — cost, margin ya notes kabhi nahi.'
    ]],
    ['key', 'Login aur PIN', [
      'Pehli baar har user ka login email OTP (6 ank) se hota hai, phir woh apna PIN banata hai.',
      'Admin ka PIN 6 ank ka hota hai; team, dealer, influencer aur Online Store customer ka PIN 4 ank ka.',
      'Usi phone / computer par agli baar sirf PIN lagta hai. Naye phone / computer par phir se email OTP aata hai.',
      'PIN 5 baar galat daalne par PIN lock ho jata hai — user "PIN bhool gaye?" se naya PIN banata hai.',
      'PIN bhoolne par 2 security sawal poochhe jaate hain. 5 baar galat jawab dene par user ki email par reset link jata hai (15 minute tak, sirf ek baar chalta hai).',
      'OTP 4–5 baar galat hone par naya OTP maangna padta hai. 1 ghante me 6 se zyada OTP nahi bheje jaate.'
    ]],
    ['shield', 'Admin login', [
      'Admin ka OTP sirf primary email par jata hai (Settings → Login & Email OTP). Backup email par tabhi jata hai jab login screen par "Backup email par bhejein" dabaya jaye.',
      'Emergency: email na khule to login screen par "Master password" — purana Store Admin password + 6 ank ka Admin PIN.',
      'Store Admin panel har baar PIN maangta hai (tab band = logout).',
      'Settings save karne aur Backup lene ke liye Admin PIN dobara maanga jata hai.'
    ]],
    ['users', 'Team user ka login reset', [
      'Team → user kholein → "Login reset" dabane se uska PIN aur purana phone hat jata hai; woh dobara email OTP se login karega.',
      'Marketing user ka password / security sawal bhi Admin hi reset karta hai (Marketing & Grow → Team).'
    ]],
    ['download', 'Backup', [
      'Settings → Backup → Admin PIN → ek .zip (saara data + Excel + documents). Har hafte lein.',
      'Password, PIN aur API key backup me nahi jaate.'
    ]],
    ['alert', 'Suraksha', [
      'Resend API key kabhi chat / WhatsApp par share na karein — sirf Settings → Login & Email OTP me daalein.',
      'Kisi user ko apna PIN batane ko na kahein. Zaroorat ho to "Login reset" karein.'
    ]]
  ];

  /* ---- har screen ke upar "Kaise use karein" hint (band karne par yaad rakhta hai) ---- */
  C.HINT_TEXT = {
    home: ['Upar ke boxes me aaj ka hisab hai — kisi par dabane se wahi list khulti hai.', 'Growth graph me Pura business / Marketing / Store / Leads / Maintenance ka mahine-ke-hisab se badhna dikhta hai. 6 ya 12 mahine chun sakte hain.', '"Jaldi karein" se nayi lead, customer ya quotation ek click me.'],
    today: ['Yahan aaj ke aur overdue kaam hain: lead follow-up, reminder aur maintenance visits.', 'Kaam poora hone par "Ho gaya" dabayein — agla kaam apne aap upar aa jata hai.'],
    leads: ['Nayi lead "+" se jodein ya Excel / CSV se import karein. Har lead par "Kahan se aayi" zaroor chunein — Growth graph usi se banta hai.', 'Lead jeet jaye to "Customer banayein" dabayein, phir uski quotation banayein.'],
    customers: ['Har customer ek hi baar banta hai (mobile number se pehchan). Customer kholne par uski quotation, bill, payment, plant aur Maintenance & Audit plan sab dikhta hai.', 'Naye ya purane customer ko "Maintenance & Audit plan dein" se package de sakte hain.'],
    customer: ['Upar ke buttons se is customer ki nayi quotation, payment, reminder, plan jodein.', 'Neeche ke tabs me iska poora hisab (Ledger) aur documents hain.'],
    quotes: ['Quotation sirf Inventory ke items se banti hai — item list me nahi hai to pehle Products & Templates me jodein.', 'Quotation ka number server khud deta hai (QT/saal/0001) — chahe kisi ne bhi, kahin se bhi banayi ho, ek hi series chalti hai.', 'Quotation par "Bill banayein" dabane se Bill banta hai; bill sirf quotation se hi banta hai.'],
    quote: ['Customer chunein, "Product / Template jodein" se Inventory ke item lagayein. Apni line nahi likh sakte — naya item chahiye to "Inventory me naya item" dabayein.', 'Save ke baad number apne aap lagta hai. Discount aapki limit se zyada nahi ho sakta.'],
    billing: ['Bill (invoice) sirf quotation se banta hai aur uska number quotation ki tarah ek hi series me aata hai.', 'Payment aane par bill kholkar "Payment jodein" dabayein — baaki rakam apne aap ghatti hai. Bill ban jaane ke baad item ya rate nahi badla ja sakta.'],
    invoice: ['Yahan bill ka poora hisab hai. "Payment jodein" se rasid ban jati hai aur WhatsApp par bheji ja sakti hai.'],
    purchase: ['Maal kharidne ka order. "Maal aa gaya" dabane par stock apne aap badh jata hai.'],
    items: ['Ye aapki ek hi Inventory hai — Quotation, Bill, Online Store aur Maintenance sab yahin se item lete hain.', '"Maintenance & Audit" tab me packages aur unke checklist items hain: yahin se edit, delete ya naye jod sakte hain.', 'Product ko Online Store par bhejne ke liye "Online Store ko bhejein" dabayein — Store Admin check karke publish karega.'],
    accounts: ['Pehla tab: Sale, Purchase, Kharcha se Profit, GST (output - input) aur ITR summary — FY chunkar dekhein.', 'Dusra tab: Kharcha (rent, salary, petrol…) yahan likhein — GST bill ho to GST amount bhi likhein, wahi input credit banega.', 'Har table ke upar Download / Share to Accountant — CA ko seedha bhej sakte hain. Ye report hai, GST/ITR filing nahi.', 'Kharcha hatane par wajah likhni padti hai aur Activity Record me dikhta hai.'],
    maintenance: ['Dashboard me dikhta hai kis customer ka kaunsa package hai, last service kab hui aur next due kab hai.', '"Visit ho gayi" dabane par jo kaam hue unhe tick karein — unka maal stock se kat jata hai aur agli date aage badh jati hai.', 'Plans aur Checklist items Inventory ka hissa hain. Free plan bhi banta hai (keemat Rs 0).'],
    orders: ['Online Store ke naye order yahan aate hain (ghanti bajegi). Har order ka apna ORD number hota hai.', '"Quotation banayein" se order ke items ki quotation ban jati hai (sirf wahi items jo Inventory me hain).'],
    blueprint: ['Customer ke ghar ki free survey: photo, jagah aur layout se Project Blueprint banta hai — iska PDF customer ko bhej sakte hain.'],
    plants: ['Lage hue plant ka record. Verify hone par dealer / influencer ka commission ban jata hai.'],
    commission: ['Dealer / influencer ka kamaya hua commission aur kitna diya gaya — yahin se "Diya" mark karein.'],
    docs: ['Sirf zaroori kaagaz rakhein (jaise signed quotation, agreement). Customer ke bill ya photo faltu me save na karein — storage bharta hai.'],
    marketing: ['Overview me dikhta hai lead kahan se aayi. Platforms tab me Instagram, Facebook, JustDial, IndiaMART, Meta / Google Ads sab ke liye Manual aur Auto dono hain.', 'Platform ka login link aur apni ID save kar sakte hain; password browser yaad rakhta hai.'],
    team: ['Yahan se naye staff / dealer / influencer banayein aur permission tay karein. Jo user jis kaam ki permission nahi pata, usse wo hissa dikhta hi nahi.'],
    activity: ['Kisne kya kiya — login, save, delete — sab ka record. Galti ya gadbad dhundhne me kaam aata hai.'],
    settings: ['Company ka naam, GST, bank, quotation / bill ke terms yahin se badalte hain — ye sab bill par chhapta hai.', 'Storage & Safai tab me dekh sakte hain kitna storage bhara hai aur purani quotation saaf kar sakte hain (bill / payment safe rahte hain).'],
    connections: ['Dusre apps ki API key yahan daalein (sirf Admin). Key server par surakshit rehti hai, dobara nahi dikhti.', 'Sab me se abhi Telegram, Slack aur Webhook sach me kaam karte hain; baaki me key save hoti hai, kaam tab chalega jab unki API ka approval mile.'],
    profile: ['Apna PIN, security sawal aur device yahan badalte hain. Admin yahan se "Login yaad rakhein" chalu kar sakta hai.']
  };
  C.addHint = function (view, name) {
    var L = C.HINT_TEXT[name]; if (!L || !view) return;
    var ph = view.querySelector('.ph'); if (!ph) return;
    var closed = C.ls('crm_hint_' + name) === 1, d = document.createElement('details');
    d.className = 'hintbar'; if (!closed) d.open = true;
    d.innerHTML = '<summary>' + C.ic('bell') + ' Kaise use karein</summary><ul>' + L.map(function (x) { return '<li>' + C.esc(x) + '</li>'; }).join('') + '</ul>';
    d.addEventListener('toggle', function () { C.ls('crm_hint_' + name, d.open ? 0 : 1); });
    ph.insertAdjacentElement('afterend', d);
  };
  C.mod('hints', {
    title: 'Help & Hints',
    allowed: function () { return C.isAdmin(); },
    render: async function (el) {
      el.innerHTML = '<div class="ph"><div><h1>Help &amp; Hints</h1><p>Sirf Admin ko dikhta hai — login aur PIN ke niyam users ki screen par nahi dikhaye jaate.</p></div></div><div class="grid g2">' +
        H.map(function (s) { return '<div class="card hintbox"><h3>' + C.ic(s[0]) + ' ' + C.esc(s[1]) + '</h3><ul>' + s[2].map(function (x) { return '<li>' + C.esc(x) + '</li>'; }).join('') + '</ul></div>'; }).join('') + '</div>';
    }
  });
})();
