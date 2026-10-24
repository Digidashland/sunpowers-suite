/* Sunpowers share page  —  https://www.sunpowers.in/d/<code>   (Vercel function; vercel.json rewrites /d/:t -> /api/d?t=:t)
   Shows a document's details + Download button, and carries the WhatsApp preview card (Open Graph tags).
   The data comes from ONE database function  sp_share_open(code)  — nothing else is readable. Same live/staging rule as config.js. */
'use strict';
var LIVE_HOSTS = ['sunpowers.in', 'www.sunpowers.in', 'store.sunpowers.in', 'admin.sunpowers.in', 'crm.sunpowers.in'];
var DB_LIVE = { url: 'https://fotmykjrqrgjnzqbdsea.supabase.co', key: 'sb_publishable_sN48EuIxQhDgS4xaalwJZA_aV-9mfLg' };
var DB_STAGING = { url: 'https://czthmbezxlkqanbhqplz.supabase.co', key: 'sb_publishable_B0f2LniPY1cR5Jzx-CbYYg_wrUiUfdq' };
var KIND = {
  quote: ['Quotation', 'कोटेशन'], bill: ['Invoice', 'बिल / इनवॉइस'], receipt: ['Payment receipt', 'पेमेंट रसीद'], ledger: ['Ledger statement', 'लेजर स्टेटमेंट'],
  design: ['Solar design', 'सोलर डिज़ाइन'], blueprint: ['Project blueprint', 'प्रोजेक्ट ब्लूप्रिंट'], doctor: ['Error report', 'एरर रिपोर्ट'], invoice: ['Tax invoice', 'टैक्स इनवॉइस'],
  plan: ['Proposal', 'प्रस्ताव'], report: ['Report', 'रिपोर्ट'], service: ['Service report', 'सर्विस रिपोर्ट'], visit: ['Site visit report', 'साइट विज़िट रिपोर्ट'], order: ['Order details', 'ऑर्डर विवरण'], doc: ['Document', 'दस्तावेज़']
};
var BOT = /bot|crawl|spider|facebookexternalhit|whatsapp|telegram|slack|preview|curl|wget|head(less)?chrome|lighthouse|embed|monitor/i;
function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return '&#' + c.charCodeAt(0) + ';'; }); }
function inr(n) { var x = Number(n); return isFinite(x) ? '₹' + Math.round(x).toLocaleString('en-IN') : ''; }
function dmy(d) { var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(d || ''); return m ? m[3] + '-' + m[2] + '-' + m[1] : ''; }
function dbFor(host, stg) {
  if (process.env.SP_DB_URL) return { url: process.env.SP_DB_URL, key: process.env.SP_DB_KEY || '' };
  if (stg) return DB_STAGING;   /* link made on a staging app carries ?e=s */
  host = String(host || '').split(':')[0].toLowerCase();
  return LIVE_HOSTS.indexOf(host) >= 0 ? DB_LIVE : DB_STAGING;
}
async function openShare(db, code, count) {
  var h = { 'Content-Type': 'application/json', apikey: db.key };
  if (db.key && db.key.indexOf('sb_') !== 0) h.Authorization = 'Bearer ' + db.key;
  var r = await fetch(db.url + '/rest/v1/rpc/sp_share_open', { method: 'POST', headers: h, body: JSON.stringify({ p_token: code, p_count: !!count }) });
  if (!r.ok) throw new Error('db ' + r.status);
  return r.json();
}
function dlUrl(u, name) { return u + (u.indexOf('?') < 0 ? '?' : '&') + 'download=' + encodeURIComponent(name || 'document.pdf'); }
function page(d, origin, code, qs) {
  var K = KIND[d.kind] || KIND.doc, brand = d.brand || 'Sunpowers', phone = String(d.phone || '').replace(/\D/g, '').slice(-10);
  var desc = [d.amount != null ? 'Amount ' + inr(d.amount) : '', d.valid_till ? 'Valid till ' + dmy(d.valid_till) : '', d.subtitle || ''].filter(Boolean).join(' · ') || (K[0] + ' from ' + brand);
  var img = origin + '/img/share/' + (KIND[d.kind] ? d.kind : 'doc') + '.png';
  var rows = (d.details || []).map(function (r) { return '<tr><th>' + esc(r[0]) + '</th><td>' + esc(r[1]) + '</td></tr>'; }).join('');
  var fname = d.file_name || (String(d.title).replace(/[^A-Za-z0-9_.-]+/g, '-').slice(0, 60) + '.pdf');
  var btn = '';
  if (d.pdf_url) btn += '<a class="b p" href="' + esc(dlUrl(d.pdf_url, fname)) + '" rel="noopener">⬇ Download PDF <small>डाउनलोड करें</small></a><a class="b s" href="' + esc(d.pdf_url) + '" target="_blank" rel="noopener">👁 View online <small>देखें</small></a>';
  if (d.view_url) btn += '<a class="b ' + (d.pdf_url ? 's' : 'p') + '" href="' + esc(d.view_url) + '" rel="noopener">🔎 Open design <small>खोलें</small></a>';
  if (!d.pdf_url && !d.view_url) btn += '<p class="nopdf">PDF abhi is link me nahi judi — bhejne wale (' + esc(brand) + ') se dobara link maangein. / इस लिंक में PDF नहीं जुड़ी, भेजने वाले से नया लिंक मांगें।</p>';
  var talk = '';
  if (phone.length === 10) talk = '<a class="b wa" href="https://wa.me/91' + phone + '?text=' + encodeURIComponent('Namaste ' + brand + ', main ' + d.title + ' ke baare me baat karna chahta hoon.') + '" rel="noopener">💬 WhatsApp <small>बात करें</small></a><a class="b s" href="tel:+91' + phone + '">📞 Call <small>कॉल करें</small></a>';
  return '<!doctype html><html lang="hi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><title>' + esc(d.title) + ' — ' + esc(brand) + '</title>' +
    '<meta name="robots" content="noindex,nofollow"><meta name="description" content="' + esc(desc) + '">' +
    '<meta property="og:type" content="website"><meta property="og:site_name" content="' + esc(brand) + '"><meta property="og:title" content="' + esc(d.title) + '"><meta property="og:description" content="' + esc(desc) + '">' +
    '<meta property="og:image" content="' + esc(img) + '"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta property="og:url" content="' + esc(origin + '/d/' + code + (qs || '')) + '">' +
    '<meta name="twitter:card" content="summary_large_image"><meta name="theme-color" content="#0f4d2b"><link rel="icon" href="/favicon.ico">' +
    '<style>:root{--g:#1e8e3e;--d:#0f4d2b;--ink:#1c2b20;--mut:#5d6f62;--bg:#eef3ee;--ln:#dfe8e0}*{box-sizing:border-box}html{-webkit-text-size-adjust:100%}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,"Noto Sans Devanagari",sans-serif}' +
    '.top{background:var(--d);color:#fff;padding:14px max(16px,env(safe-area-inset-left)) 14px max(16px,env(safe-area-inset-right));display:flex;align-items:center;gap:10px}.top img{width:34px;height:34px;border-radius:8px;background:#fff;padding:3px}.top b{font-size:18px;letter-spacing:.2px}.top span{margin-left:auto;font-size:12px;opacity:.85}' +
    '.w{max-width:560px;margin:0 auto;padding:18px max(16px,env(safe-area-inset-left)) 40px max(16px,env(safe-area-inset-right))}.card{background:#fff;border:1px solid var(--ln);border-radius:18px;padding:18px;box-shadow:0 2px 12px rgba(15,77,43,.06)}' +
    '.chip{display:inline-block;background:#e3f3e7;color:var(--d);font-weight:700;font-size:12.5px;border-radius:999px;padding:4px 12px}h1{font-size:22px;line-height:1.25;margin:10px 0 4px;text-wrap:balance}.sub{color:var(--mut);margin:0 0 12px}' +
    '.amt{font-size:32px;font-weight:800;color:var(--d);margin:4px 0 2px}.val{color:var(--mut);font-size:14px;margin-bottom:10px}table{width:100%;border-collapse:collapse;margin:8px 0 4px;font-size:15px}th{text-align:left;color:var(--mut);font-weight:600;padding:8px 10px 8px 0;border-top:1px solid var(--ln);width:42%;vertical-align:top}td{padding:8px 0;border-top:1px solid var(--ln);font-weight:600;overflow-wrap:anywhere}' +
    '.acts{display:grid;gap:10px;margin-top:16px}.b{display:flex;align-items:center;justify-content:center;gap:8px;flex-wrap:wrap;text-decoration:none;border-radius:14px;padding:15px 16px;font-weight:800;font-size:17px;text-align:center}.b small{font-weight:600;font-size:13px;opacity:.85}.p{background:var(--g);color:#fff}.s{background:#fff;color:var(--ink);border:1.5px solid var(--ln)}.b.wa{background:#25d366;color:#fff}' +
    '.nopdf{background:#fff4e0;border:1px solid #f1d9a8;color:#6b4a00;border-radius:12px;padding:12px;font-size:14px;margin:0}.ft{text-align:center;color:var(--mut);font-size:12.5px;margin-top:18px}.ft a{color:var(--d)}</style></head><body>' +
    '<div class="top"><img src="/assets/logo-mark.png" alt=""><b>' + esc(brand) + '</b><span>' + esc(K[0]) + '</span></div>' +
    '<main class="w"><div class="card"><span class="chip">' + esc(K[0]) + ' · ' + esc(K[1]) + '</span><h1>' + esc(d.title) + '</h1>' + (d.subtitle ? '<p class="sub">' + esc(d.subtitle) + '</p>' : '') +
    (d.amount != null && isFinite(Number(d.amount)) ? '<div class="amt">' + esc(inr(d.amount)) + '</div>' : '') + (d.valid_till ? '<div class="val">Valid till / मान्य तिथि: <b>' + esc(dmy(d.valid_till)) + '</b></div>' : '') +
    (rows ? '<table>' + rows + '</table>' : '') + '<div class="acts">' + btn + talk + '</div></div>' +
    '<p class="ft">Shared by ' + esc(brand) + ' · <a href="' + esc(origin) + '/">' + esc(origin.replace(/^https?:\/\//, '')) + '</a></p></main></body></html>';
}
function gone(origin) {
  return '<!doctype html><html lang="hi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>Link band hai — Sunpowers</title>' +
    '<style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#eef3ee;color:#1c2b20;font:16px/1.5 system-ui,"Noto Sans Devanagari",sans-serif;text-align:center;padding:24px}div{max-width:420px}h1{font-size:22px}a{display:inline-block;margin-top:12px;background:#1e8e3e;color:#fff;text-decoration:none;border-radius:12px;padding:12px 20px;font-weight:800}</style></head><body><div><h1>🔒 यह लिंक बंद या पुराना हो गया है</h1><p>This link is closed or has expired.<br>कृपया भेजने वाले से नया लिंक माँगें।</p><a href="' + esc(origin) + '/">Sunpowers.in</a></div></body></html>';
}
module.exports = async function (req, res) {
  var q = req.query || {}, code = String(q.t || (/[?&]t=([^&]+)/.exec(req.url || '') || [])[1] || '').replace(/[^A-Za-z0-9]/g, '').slice(0, 40);
  var host = (req.headers && (req.headers['x-forwarded-host'] || req.headers.host)) || '', proto = (req.headers && req.headers['x-forwarded-proto']) || 'https';
  var origin = process.env.SP_SITE_ORIGIN || (proto + '://' + host);
  res.setHeader('Content-Type', 'text/html; charset=utf-8'); res.setHeader('X-Robots-Tag', 'noindex, nofollow'); res.setHeader('Cache-Control', 'no-store'); res.setHeader('Referrer-Policy', 'no-referrer');
  try {
    if (!code) { res.statusCode = 404; return res.end(gone(origin)); }
    var ua = (req.headers && req.headers['user-agent']) || '';
    var d = await openShare(dbFor(host, q.e === 's'), code, !BOT.test(ua) && req.method !== 'HEAD');
    if (!d) { res.statusCode = 404; return res.end(gone(origin)); }
    res.statusCode = 200; return res.end(req.method === 'HEAD' ? '' : page(d, origin, code, q.e === 's' ? '?e=s' : ''));
  } catch (e) {
    res.statusCode = 503; return res.end(gone(origin).replace('यह लिंक बंद या पुराना हो गया है', 'अभी लिंक नहीं खुल रहा, कुछ देर बाद फिर कोशिश करें'));
  }
};
module.exports._page = page; module.exports._dbFor = dbFor;
