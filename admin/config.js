// =====================================================================
//  SUNPOWERS ADMIN — Database connection (Supabase) + links
//  SUPABASE_URL / SUPABASE_KEY : wahi jo Online Store (Main App) ki config.js me hai
//  STORE_URL : aapka Online Store (Main App) ka link — "स्टोर देखें" button + product feed
//  CRM_URL   : aapka CRM ka link (khaali chhod sakte hain)
//  SITE_URL  : aapki Website ka link (khaali = Store Settings ka "मुख्य वेबसाइट लिंक")
// =====================================================================
var SP_DB = (function () {
  // Branch preview URL (…-git-branch…vercel.app) = STAGING database. Live domain = LIVE database.
  var h = location.hostname;
  var staging = /-git-/.test(h) && /\.vercel\.app$/.test(h);
  return staging
    ? { url: 'https://czthmbezxlkqanbhqplz.supabase.co', key: 'sb_publishable_B0f2LniPY1cR5Jzx-CbYYg_wrUiUfdq' }
    : { url: 'https://fotmykjrqrgjnzqbdsea.supabase.co', key: 'sb_publishable_sN48EuIxQhDgS4xaalwJZA_aV-9mfLg' };
})();
window.SP_CONFIG = {
  SUPABASE_URL: SP_DB.url,
  SUPABASE_KEY: SP_DB.key,
  IMAGE_BUCKET: 'sp-images',
  STORE_URL: 'https://store.sunpowers.in',
  CRM_URL: 'https://crm.sunpowers.in',
  SITE_URL: 'https://www.sunpowers.in'
};

// =====================================================================
//  LICENSE — sirf software developer bharega. Khaali = koi check nahi.
// =====================================================================
window.SP_LICENSE = { URL: '', KEY: '', ID: '' };