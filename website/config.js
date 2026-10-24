/* ============================================================
   Sunpowers website settings — sirf yahi file badalni hoti hai
   ============================================================ */
var SP_DB = (function () {
  // Sirf 5 live hosts = LIVE database. Baaki sab (staging-*, preview, vercel.app, localhost) = STAGING database.
  var h = location.hostname;
  var staging = ['sunpowers.in','www.sunpowers.in','store.sunpowers.in','admin.sunpowers.in','crm.sunpowers.in'].indexOf(h) === -1;
  return staging
    ? { url: 'https://czthmbezxlkqanbhqplz.supabase.co', key: 'sb_publishable_B0f2LniPY1cR5Jzx-CbYYg_wrUiUfdq' }
    : { url: 'https://fotmykjrqrgjnzqbdsea.supabase.co', key: 'sb_publishable_sN48EuIxQhDgS4xaalwJZA_aV-9mfLg' };
})();
window.SITE = {
  // Online Store (Main App) ka link
  SHOP_URL: 'https://store.sunpowers.in',

  // Customer Login ka link — Online Store (Main App) ka "Mera Account" page (khaali = Login button nahi dikhega)
  LOGIN_URL: 'https://store.sunpowers.in/?view=account',

  // Footer me chhota brand (khaali = nahi dikhega)
  POWERED_BY: 'Powered by Digidashland.in',
  POWERED_URL: 'https://www.digidashland.in',

  // WhatsApp number (10 ank)
  WHATSAPP: '9621050636',

  // Contact form isi database me jaata hai -> Online Store Admin -> पूछताछ
  SUPABASE_URL: SP_DB.url,
  SUPABASE_KEY: SP_DB.key
};

// =====================================================================
//  LICENSE — sirf software developer bharega. Khaali = koi check nahi.
// =====================================================================
window.SP_LICENSE = { URL: '', KEY: '', ID: '' };
