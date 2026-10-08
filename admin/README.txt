SUNPOWERS — ADMIN PANEL (Online Store ka control)
==================================================
FILES
  index.html  — Admin Panel
  core.js, xlsx-lite.js — engine (mat badlein)
  config.js   — Supabase URL/Key + STORE_URL (store ka link) + CRM_URL
  vercel.json — Vercel setting (Google par index nahi hoga)

LIVE KARNE KE STEPS
  1. GitHub par naya repo (jaise: sunpowers-admin) → ye files upload
  2. vercel.com → Add New → Project → wahi repo → Deploy
  3. Settings → Domains → admin.sunpowers.in jodein (DNS: GUIDE-2-DNS.txt)
  4. config.js me CRM_URL bhar dein (CRM ka link) — Admin me "📊 CRM" button aa jayega

LOGIN
  • Naye computer par: OTP apne aap helpsunpowers@gmail.com par jayega → code → 6 ank ka PIN
    (pehli baar PIN CRM me ya yahin banta hai — dono ka ek hi Admin login hai)
  • Usi computer par phir: har baar sirf 6 ank ka PIN (tab/browser band = logout, suraksha ke liye)
  • "Primary email nahi khul raha? Backup email par bhejein" → surajanandpbh@gmail.com
  • Email hi nahi aa raha: "Master password se" → purana Store Admin password + PIN
  • PIN bhool gaye: security sawal → 5 baar galat → reset link email par

NAYA KYA HAI
  • "🔗 CRM se aaye product" tab: CRM se bheja product yahan aata hai
      → Google / Meta jaanch (4 tick) → section chunein → Publish
      → ya "Lautayein" (kaaran likhein — CRM me dikhega)
      → Publish ke baad CRM me "Store par live" dikhega. Dobara bhejne par "Update"
  • Naya order / poochtaachh / CRM product aate hi ghanti + tab par ginti (har 45 second check)

config.js ke neeche  window.SP_LICENSE  — khaali rehne dein (sirf rental client ke liye).
