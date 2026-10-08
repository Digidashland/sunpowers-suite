SUNPOWERS — MAIN APP (Online Store) v5
=======================================
Ye customers wala Online Store hai. Admin Panel ab ALAG zip me hai (2-Admin).

FILES
  index.html  — Store (home, products, cart, order, "👤 Mera Account")
  core.js     — engine (mat badlein)
  config.js   — Supabase URL + Key
  setup.sql   — Store ka database (Supabase me Run)
  vercel.json — Vercel setting

LIVE KARNE KE STEPS
  1. Supabase → SQL Editor → setup.sql paste → RUN
     (pehle chala chuke hain to bhi dobara chalayein — naya function judega, data nahi mitega)
  2. CRM wali crm-setup.sql bhi RUN karein (customer login + OTP usi se chalta hai) — GUIDE-1-Supabase.txt dekhein
  3. GitHub ke store repo me ye files daalein (purani files hata kar) → Vercel apne aap live karega
  4. Vercel → Project → Settings → Domains → shop.sunpowers.in jodein (DNS: GUIDE-2-DNS.txt)
  5. Icons (icon-192/512, favicon, apple-touch-icon) naye logo se bane hain — "Add to Home Screen"
     par Sunpowers ka icon aayega

NAYA KYA HAI (v5)
  • Header me 👤 button → customer ID banaye: naam + mobile + email → email OTP → 4 ank ka PIN
  • Ek baar login = jab tak khud Logout na kare tab tak login (365 din, har visit par badhta hai)
  • Mera Account: naam, pata, mere orders (status ke saath), meri poochtaachh,
    "PIN badlein", "Sab phone se logout"
  • PIN bhool gaye → security sawal → 5 baar galat → email par reset link (15 minute)
  • Login customer ka pata order form me apne aap bhar jata hai
  • Dealer / Influencer ka link (…?ref=DSP123456) se aaya order / enquiry CRM me unke naam se dikhta hai

DHYAN DEIN
  • Admin Panel pehle /admin par tha — ab "3-Admin" zip alag Vercel project me lagayein.

config.js
  POWERED_BY / POWERED_URL — footer ki chhoti line ("Powered by DigiDashLand"). Khaali '' = nahi dikhegi
  SP_LICENSE — khaali rehne dein (sirf rental client ke liye)
.vercelignore — setup.sql aur README website par public nahi honge.
