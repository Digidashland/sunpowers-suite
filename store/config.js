// =====================================================================
//  SUNPOWERS — Database connection (Supabase)
//  Supabase → Connect → Project URL + Publishable (anon) key
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
  // Footer me chhota brand (khaali '' = nahi dikhega)
  POWERED_BY: 'Powered by Digidashland.in',
  POWERED_URL: 'https://www.digidashland.in'
};

// =====================================================================
//  LICENSE — sirf software developer bharega. Khaali = koi check nahi.
// =====================================================================
window.SP_LICENSE = { URL: '', KEY: '', ID: '' };