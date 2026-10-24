/* ================================================================
   SUNPOWERS CRM — SETTINGS (sirf yahi file badalni hai)
   SUPABASE_URL / SUPABASE_KEY : wahi jo Online Store ki config.js me hai
   STORE_URL : aapka Online Store (App) ka link
   SITE_URL  : aapki Website ka link
   ================================================================ */
var SP_DB = (function () {
  // Sirf 5 live hosts = LIVE database. Baaki sab (staging-*, preview, vercel.app, localhost) = STAGING database.
  var h = location.hostname;
  var staging = ['sunpowers.in','www.sunpowers.in','store.sunpowers.in','admin.sunpowers.in','crm.sunpowers.in'].indexOf(h) === -1;
  return staging
    ? { url: 'https://czthmbezxlkqanbhqplz.supabase.co', key: 'sb_publishable_B0f2LniPY1cR5Jzx-CbYYg_wrUiUfdq' }
    : { url: 'https://fotmykjrqrgjnzqbdsea.supabase.co', key: 'sb_publishable_sN48EuIxQhDgS4xaalwJZA_aV-9mfLg' };
})();
window.CRM_CONFIG = {
  SUPABASE_URL: SP_DB.url,
  SUPABASE_KEY: SP_DB.key,
  STORE_URL: 'https://store.sunpowers.in',
  SITE_URL: 'https://www.sunpowers.in',
  // Staging par link test karne ke liye: staging Website ka link (khaali = upar wala SITE_URL; link phir bhi staging database se khulta hai)
  SITE_URL_STAGING: ''
};

// =====================================================================
//  LICENSE — sirf software developer bharega. Khaali = koi check nahi.
// =====================================================================
window.SP_LICENSE = { URL: '', KEY: '', ID: '' };
