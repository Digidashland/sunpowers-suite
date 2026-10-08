SUNPOWERS CRM — Phase 1 (Live karne ke simple steps)
====================================================

STEP 1 — Database + Email OTP (sirf ek baar)
  Poore steps: GUIDE-1-Supabase.txt (pg_net ON → setup.sql → crm-setup.sql → Resend key Vault me)
  Neeche "Sunpowers CRM setup complete ✔" aayega. (Dobara chalane se data nahi mitta.)

STEP 2 — config.js check karein
  Isme Supabase URL / Key, Store link aur Website link pehle se bhare hain.
  Kuch badalna ho to sirf isi file me badlein.

STEP 3 — GitHub + Vercel
  1. GitHub par naya repo banayein (jaise: sunpowers-crm)
  2. Is folder ki SAARI files upload karein (crm-setup.sql aur README.txt chhod sakte hain)
  3. vercel.com → Add New → Project → wahi repo → Deploy
  4. Settings → Domains → crm.sunpowers.in jodein (DNS: GUIDE-2-DNS.txt)

STEP 4 — Pehla login (password nahi — email OTP + PIN)
  1. "Mobile / Email / Username": admin → Aage badhein
  2. OTP helpsunpowers@gmail.com par aayega (backup surajanandpbh@gmail.com sirf button dabane par)
  3. OTP → apna 6 ank ka PIN → 2 security sawal. Ab is phone/computer par sirf PIN
  4. Settings → "Login & Email OTP" → "Test email bhejein" se check karein
  Emergency: "Master password se" → purana Store Admin password + PIN

LOGIN NIYAM (sab users)
  • Admin = 6 ank PIN, baaki sab = 4 ank PIN. Naya phone = phir email OTP
  • Login tab tak bana rahta hai jab tak khud Logout na karein
  • PIN bhool gaye → security sawal → 5 baar galat → email par reset link (15 min, ek baar)
  • Profile → Suraksha: PIN badlein, sawal badlein, apne phone/computer dekhein, sab se logout
  • Team → user ka email zaroor bharein. Atak jaye to "Login reset (PIN + phone hatayein)"

STEP 5 — Shuru karein (Admin)
  1. Settings → Company: legal naam, GSTIN, pata, logo, sign
  2. Settings → Bill / Quotation: bank, UPI, terms, number series
  3. Settings → Accountant: CA ka naam + WhatsApp + email
  4. Team → Naya user (email zaroori — OTP usi par): Manager / Staff / Dealer / Influencer (commission, discount limit, target)
  5. Products & Projects → items jodein (ya Excel se)
  Dealer / Influencer khud bhi "ID banayein" kar sakte hain → Team → Verify baaki → Chalu karein

KHAAS BAATEIN
  • Har user ko sirf apna data — Admin ko sab. Permission: Team → Role permission (tick/untick)
    aur kisi ek user ke liye alag: user kholein → "alag permission". Privacy: Settings → Privacy
  • Ek mobile = ek customer (lock). Doosra user wahi number dale to bata deta hai kiske paas hai.
  • Quotation → "Bill banayein" → Payment jodein → Rasid WhatsApp. Stock apne aap ghatta/badhta hai.
  • Product seedha store par live NAHI hota: "Store ko bhejein" → Store Admin review → Publish
    Admin Panel → "🔗 CRM se aaye product" → jaanch → Publish. Live hone par yahan "Store par live" + link
  • Store Orders → "App customers": jinhone Main App par login banaya. Ek click me CRM customer
  • Dealer/Influencer ke link se aaya order "Ref: code — naam" ke saath dikhta hai
  • Plant verify hote hi commission apne aap banta hai (Dealer/Influencer ko dikhta hai).
  • Har report par: Download  aur  Download & Share to Accountant.
  • Aaj ke kaam: reminder, AMC (repeat), follow-up, payment due — overdue laal me.
    Team → Kaam ka hisab: kaun time par kaam nahi kar raha.
  • Documents: folder banayein, Admin lock laga sakta hai, har file ka Share button. Max 3 MB / file.
  • Mobile par "Add to Home Screen" karke app ki tarah chalayein.

BACKUP (har hafte ek baar)
  Settings → Backup → apna 6 ank PIN → "Backup download karein"
  Ek .zip milegi: backup.json (poora data) + backup.xlsx (Excel) + files/ (documents)
  Google Drive / pen drive me rakhein. Password, PIN aur API key backup me nahi jaate.

config.js ke neeche  window.SP_LICENSE  — khaali rehne dein (sirf rental client ke liye).
.vercelignore — crm-setup.sql aur README website par public nahi honge.
