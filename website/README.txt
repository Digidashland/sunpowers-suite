SUNPOWERS — WEBSITE (Vercel)
============================
LIVE KARNE KE STEPS
  1. GitHub par naya repo (jaise: sunpowers-website) → is folder ki SAARI files upload
  2. vercel.com → Add New → Project → wahi repo → Deploy (koi setting nahi badalni)
  3. Vercel → Project → Settings → Domains → "sunpowers.in" aur "www.sunpowers.in" jodein
     (DNS records alag guide me diye hain)
  4. config.js check karein:
       SHOP_URL  — Online Store (Main App) ka link
       LOGIN_URL — customer login (Main App ka "Mera Account" page)
     (Pehle se bhare hain: https://store.sunpowers.in aur …/?view=account)
       WHATSAPP  — WhatsApp number
  5. Apni photos img/ folder me daalein (naam img/PHOTOS-YAHAN-DAALEIN.txt me likhe hain)

Contact form ki enquiry → Store Admin "पूछताछ" + CRM "Store Orders → Enquiry" me aati hai.

Logo + favicon naye logo se lage hain (assets/logo-mark.png, logo-mark-light.png, logo-full.png).
MilesWeb wali .htaccess ki ab zaroorat nahi — Vercel apne aap 404.html dikhata hai.
config.js: POWERED_BY / POWERED_URL — footer ki chhoti line. Khaali '' = nahi dikhegi.
config.js: SP_LICENSE — khaali rehne dein (sirf rental client ke liye).
