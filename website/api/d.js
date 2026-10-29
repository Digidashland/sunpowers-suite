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
async function rpcCall(db, fn, body) {
  var h = { 'Content-Type': 'application/json', apikey: db.key };
  if (db.key && db.key.indexOf('sb_') !== 0) h.Authorization = 'Bearer ' + db.key;
  var r = await fetch(db.url + '/rest/v1/rpc/' + fn, { method: 'POST', headers: h, body: JSON.stringify(body) });
  if (!r.ok) throw new Error('db ' + r.status);
  return r.json();
}
async function openShare(db, code, count) {
  var h = { 'Content-Type': 'application/json', apikey: db.key };
  if (db.key && db.key.indexOf('sb_') !== 0) h.Authorization = 'Bearer ' + db.key;
  var r = await fetch(db.url + '/rest/v1/rpc/sp_share_open', { method: 'POST', headers: h, body: JSON.stringify({ p_token: code, p_count: !!count }) });
  if (!r.ok) throw new Error('db ' + r.status);
  return r.json();
}
function dlUrl(u, name) { return u + (u.indexOf('?') < 0 ? '?' : '&') + 'download=' + encodeURIComponent(name || 'document.pdf'); }
function head(d, origin, code, qs, K, brand, desc, img, extraCss) {
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
    '.nopdf{background:#fff4e0;border:1px solid #f1d9a8;color:#6b4a00;border-radius:12px;padding:12px;font-size:14px;margin:0}.ft{text-align:center;color:var(--mut);font-size:12.5px;margin-top:18px}.ft a{color:var(--d)}'+(extraCss||'')+'</style></head><body>';
}
/* ---------------- Round 57: "Payment kaise karein" — QR + company account + (optional) link. Data sirf company Settings se (DB: crm__pay_box) ---------------- */
var PAY_CSS = '.pay{margin-top:16px;border:2px solid var(--g);border-radius:16px;background:#fff;padding:14px}.pay h2{font-size:18px;margin:0 0 4px;color:var(--d)}.pay h2 small{font-weight:600;color:var(--mut);font-size:13px}.pay .safe{background:#fff4e0;border:1px solid #f1d9a8;color:#6b4a00;border-radius:10px;padding:9px 11px;font-size:13.5px;margin:8px 0 12px}' +
  '.pay .pm{border-top:1px solid var(--ln);padding:12px 0 2px}.pay .pm h3{font-size:15.5px;margin:0 0 6px}.pay .qr{display:flex;justify-content:center;padding:6px 0}.pay .qr canvas{max-width:100%;height:auto;border:1px solid var(--ln);border-radius:12px}.pay .pa{font-size:26px;font-weight:800;color:var(--d);margin:2px 0}' +
  '.pay table{width:100%;border-collapse:collapse;font-size:15px}.pay th{text-align:left;color:var(--mut);font-weight:600;padding:6px 6px 6px 0;width:34%;vertical-align:top}.pay td{padding:6px 0;word-break:break-all}.pay .cp{font:inherit;font-size:12.5px;border:1.5px solid var(--ln);background:#f3f7f3;color:var(--d);border-radius:8px;padding:3px 9px;margin-left:8px;cursor:pointer}';
function payBox(p) {
  if (!p) return '';
  if (p.paid) return '<div class="ok">✔ Is bill ka poora payment mil chuka hai — dhanyavaad! <small>पूरा भुगतान मिल चुका है</small></div>';
  var tot = Number(p.total) || 0, pd = Number(p.paid) || 0, rest = Number(p.rest) || 0, h = '<section class="pay" id="payBox"><h2>Pay your bill amount <small>अपने बिल की रकम दें</small></h2>';
  h += '<div class="safe"><b>Dhyan dein:</b> payment sirf neeche diye ' + esc(p.payee || 'Sunpowers') + ' ke QR / account / link par karein. Kisi aur account ya number par paisa na bhejein. / भुगतान सिर्फ़ नीचे दिए कंपनी के QR / अकाउंट / लिंक पर करें।</div>';
  if (tot) h += '<table><tr><th>Bill ki rakam' + (p.ref ? ' (' + esc(p.ref) + ')' : '') + '</th><td><b>' + esc(inr(tot)) + '</b></td></tr>' + (pd ? '<tr><th>Ab tak mila</th><td>' + esc(inr(pd)) + '</td></tr>' : '') + (rest && pd ? '<tr><th>Baaki (Rest)</th><td><b>' + esc(inr(rest)) + '</b></td></tr>' : '') + '</table>';
  h += '<p class="val" style="margin:8px 0 0"><div class="ok" style="margin-top:10px">✔ Part-wise payment ki suvidha available hai — poora ek saath dena zaroori nahi. Aap apni suvidha se jitni rakam chahein, hisson me de sakte hain.<br><span style="font-weight:600;font-size:13.5px">पार्ट-वाइज (हिस्सों में) पेमेंट की सुविधा उपलब्ध है — पूरा एक साथ देना ज़रूरी नहीं, अपनी सुविधा से हिस्सों में दे सकते हैं।</span></div><p class="val" style="margin:8px 0 0">Payment mil jane par hamari team confirm karke aage ki rakam aur kaam ke baare me batayegi.</p>';
  if (p.upi) {
    var u = 'upi://pay?pa=' + encodeURIComponent(p.upi) + '&pn=' + encodeURIComponent(p.payee || 'Sunpowers') + '&cu=INR&tn=' + encodeURIComponent(p.ref || 'Payment');
    h += '<div class="pm"><h3>1. QR scan karein <small>QR से पेमेंट</small></h3><div class="qr" id="payqr" data-u="' + esc(u) + '"></div><div class="val" style="text-align:center">Kisi bhi UPI app (GPay / PhonePe / Paytm / BHIM) se scan karein' + ' — rakam aap khud daalein' + '</div>' +
      '<a class="b p" style="margin-top:8px;padding:12px;font-size:15.5px" href="' + esc(u) + '">📱 UPI app kholein <small>(mobile)</small></a><table style="margin-top:8px"><tr><th>UPI ID</th><td><b>' + esc(p.upi) + '</b><button type="button" class="cp" data-cp="' + esc(p.upi) + '">Copy</button></td></tr></table></div>';
  }
  var b = p.bank;
  if (b && b.acc) h += '<div class="pm"><h3>' + (p.upi ? '2' : '1') + '. Bank account me bhejein <small>बैंक ट्रांसफ़र</small></h3><table>' + (b.holder ? '<tr><th>Naam</th><td>' + esc(b.holder) + '</td></tr>' : '') + (b.name ? '<tr><th>Bank</th><td>' + esc(b.name) + '</td></tr>' : '') +
    '<tr><th>Account no.</th><td><b>' + esc(b.acc) + '</b><button type="button" class="cp" data-cp="' + esc(b.acc) + '">Copy</button></td></tr>' + (b.ifsc ? '<tr><th>IFSC</th><td><b>' + esc(b.ifsc) + '</b><button type="button" class="cp" data-cp="' + esc(b.ifsc) + '">Copy</button></td></tr>' : '') + '</table></div>';
  if (p.link) h += '<div class="pm"><h3>' + ((p.upi ? 1 : 0) + (b && b.acc ? 1 : 0) + 1) + '. Payment link se <small>लिंक से पेमेंट</small></h3><a class="b p" style="padding:12px;font-size:15.5px" target="_blank" rel="noopener noreferrer" href="' + esc(p.link) + '">💳 Payment link kholein <small>खोलें</small></a></div>';
  return h + '<p class="val" style="margin:10px 0 0">Payment karne ke baad hamari team ko WhatsApp / call par bata dein. / भुगतान के बाद टीम को बताएँ।</p></section>';
}
function termsHtml(t) {
  if (!t || !t.items || !t.items.length) return '';
  return '<div class="terms" style="margin:2px 0 10px"><label style="display:flex;gap:10px;align-items:flex-start;cursor:pointer"><input type="checkbox" id="tk" style="width:22px;height:22px;padding:0;margin:1px 0 0;flex:none"><span style="font-weight:600;font-size:14px;line-height:1.4">Main <a href="#" id="tv" style="color:var(--d);text-decoration:underline">Disclaimer / Terms</a> se sahmat hoon. <span style="font-weight:500;color:var(--mut)">/ मैं डिस्क्लेमर / शर्तों से सहमत हूँ।</span></span></label>' +
    '<div id="tb" hidden style="margin-top:8px;max-height:36vh;overflow:auto;font-size:11.5px;line-height:1.45;color:var(--mut);border:1px solid var(--ln);border-radius:10px;padding:8px 10px 8px 4px;background:#fff">' + t.items.map(function (it) {
      return '<b style="margin-left:6px;color:var(--ink)">' + esc((it.title || {}).h) + '</b><ol style="padding-left:22px;margin:4px 0 8px">' + (it.points || []).map(function (p) { return '<li style="margin:4px 0">' + esc(p.h) + (p.e && p.e !== p.h ? '<br>' + esc(p.e) : '') + '</li>'; }).join('') + '</ol>';
    }).join('') + '</div></div>';
}
var PAY_JS = '(function(){var c=document.getElementById("payqr");if(c&&window.SPQR){try{var v=SPQR.canvas(c.getAttribute("data-u"),240);c.appendChild(v)}catch(e){c.textContent="QR nahi ban saka — neeche UPI ID / account use karein"}}' +
  'var bs=document.querySelectorAll("[data-cp]");for(var i=0;i<bs.length;i++)bs[i].onclick=function(){var t=this.getAttribute("data-cp"),b=this,ok=function(){var o=b.textContent;b.textContent="✔ Copy ho gaya";setTimeout(function(){b.textContent=o},1500)};' +
  'if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(t).then(ok,function(){fb(t,ok)})}else fb(t,ok)};' +
  'function fb(t,ok){var a=document.createElement("textarea");a.value=t;a.style.cssText="position:fixed;opacity:0";document.body.appendChild(a);a.select();try{document.execCommand("copy");ok()}catch(e){}document.body.removeChild(a)}})();';
function payScripts(p) { return p && !p.paid ? '<script src="/assets/sp-qr.js?v=1"></script><script>' + PAY_JS + '</script>' : ''; }
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
  return head(d, origin, code, qs, K, brand, desc, img, PAY_CSS) +
    '<div class="top"><img src="/assets/logo-mark.png" alt=""><b>' + esc(brand) + '</b><span>' + esc(K[0]) + '</span></div>' +
    '<main class="w"><div class="card"><span class="chip">' + esc(K[0]) + ' · ' + esc(K[1]) + '</span><h1>' + esc(d.title) + '</h1>' + (d.subtitle ? '<p class="sub">' + esc(d.subtitle) + '</p>' : '') +
    (d.amount != null && isFinite(Number(d.amount)) ? '<div class="amt">' + esc(inr(d.amount)) + '</div>' : '') + (d.valid_till ? '<div class="val">Valid till / मान्य तिथि: <b>' + esc(dmy(d.valid_till)) + '</b></div>' : '') +
    (rows ? '<table>' + rows + '</table>' : '') + '<div class="acts">' + btn + talk + '</div></div>' +
    payBox(d.pay) + '<p class="ft">Shared by ' + esc(brand) + ' · <a href="' + esc(origin) + '/">' + esc(origin.replace(/^https?:\/\//, '')) + '</a></p></main>' + payScripts(d.pay) + '</body></html>';
}
/* ---------------- Round 52: ek hi LIVE link — options, Accept / Badlav / Call back ---------------- */
var LIVE_CSS = '.hist{margin-top:14px;border:1px solid var(--ln);border-radius:14px;padding:10px 14px;background:#fff}.hist summary{cursor:pointer;font-weight:700;font-size:15px}.hist ul{margin:10px 0 0;padding-left:18px;font-size:14px;line-height:1.5}.hist li{margin-bottom:8px}.ban{background:#fff4e0;border:1px solid #f1d9a8;color:#6b4a00;border-radius:14px;padding:12px 14px;font-size:14px;line-height:1.5}.opt{border:1.5px solid var(--ln);border-radius:16px;padding:14px;margin-top:12px;background:#fff}.opt.sel{border-color:var(--g);box-shadow:0 0 0 3px rgba(30,142,62,.15)}.opt h2{font-size:18px;margin:0 0 2px}.opt .tot{font-size:26px;font-weight:800;color:var(--d)}.opt ul{margin:8px 0 0;padding-left:18px;color:var(--ink);font-size:14.5px}.opt li small{color:var(--mut)}' +
  '.cmp{width:100%;border-collapse:collapse;font-size:14px;margin-top:10px}.cmp th,.cmp td{border-top:1px solid var(--ln);padding:7px 6px;text-align:left}.cmp th{color:var(--mut);font-weight:600;width:auto}' +
  '.ok{background:#e3f3e7;border:1px solid #bfe0c7;color:var(--d);border-radius:12px;padding:12px;font-weight:700;margin-top:12px}.warn{background:#fff4e0;border:1px solid #f1d9a8;color:#6b4a00;border-radius:12px;padding:12px;font-size:14px;margin-top:12px}' +
  '.bt{font:inherit;border:0;cursor:pointer;width:100%}.b.s.bt{border:1.5px solid var(--ln)}.pick{background:#fff;color:var(--d);border:2px solid var(--g)!important;margin-top:10px;padding:11px;font-size:15px}.opt.sel .pick{background:var(--g);color:#fff}' +
  '.box2{background:#f3f7f3;border-radius:14px;padding:14px;margin-top:12px}.box2 input,.box2 textarea{width:100%;border:1.5px solid #cfd8cf;border-radius:12px;padding:12px;font:inherit;background:#fff;color:var(--ink);margin-top:6px}.box2 label{font-weight:700;font-size:14px}.msg{margin-top:10px;font-weight:700;font-size:14px;min-height:18px}.msg.bad{color:#c8372d}.msg.good{color:#15702f}.row2{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:10px}@media(max-width:380px){.row2{grid-template-columns:1fr}}';
function stateGone(d, origin) {
  var K = KIND[d.kind] || KIND.doc, brand = d.brand || 'Sunpowers', phone = String(d.phone || '').replace(/\D/g, '').slice(-10), paused = d.state === 'paused', closed = d.state === 'closed';
  var talk = phone.length === 10 ? '<a class="b wa" href="https://wa.me/91' + phone + '?text=' + encodeURIComponent('Namaste ' + brand + ', mera ' + K[0] + ' ka link chal nahi raha, kripya naya bhejein.') + '" rel="noopener">💬 WhatsApp <small>बात करें</small></a><a class="b s" href="tel:+91' + phone + '">📞 Call <small>कॉल करें</small></a>' : '';
  return head({ title: K[0], kind: d.kind }, origin, '', '', K, brand, K[0] + ' — ' + brand, origin + '/img/share/doc.png') + '<div class="top"><img src="/assets/logo-mark.png" alt=""><b>' + esc(brand) + '</b><span>' + esc(K[0]) + '</span></div><main class="w"><div class="card"><span class="chip">' + esc(K[0]) + '</span><h1>' + (closed ? '✔ Ye quotation ab chalu nahi hai' : paused ? '⏸ Ye link abhi ruka hua hai' : '⌛ Ye link expire ho gaya hai') + '</h1><p class="sub">' + (closed ? 'Aapne doosra quotation chun liya hai, isliye ye band ho gaya hai. ' : paused ? 'Kuchh der ke liye roka gaya hai. ' : 'Quotation ki avadhi poori ho chuki hai. ') + 'Naya / chalu link ke liye humse sampark karein.<br><span style="font-size:13.5px">' + (paused ? 'यह लिंक अभी रुका हुआ है।' : 'यह लिंक अब चालू नहीं है।') + ' नया लिंक पाने के लिए हमें कॉल या WhatsApp करें।</span></p><div class="acts">' + talk + '</div></div></main></body></html>';
}
function livePage(d, origin, code, qs, db, hasHow) {
  var q = d.quote || {}, K = KIND.quote, brand = d.brand || 'Sunpowers', phone = String(d.phone || '').replace(/\D/g, '').slice(-10), opts = q.opts || [], multi = opts.length > 1, locked = q.locked, st = q.status || '';
  var title = q.title || d.title || 'Quotation', desc = (multi ? opts.length + ' options · ' : '') + (q.valid_till ? 'Valid till ' + dmy(q.valid_till) + ' · ' : '') + (q.ref || '');
  var canAct = !locked || q.reaccept, fname = String(q.ref || 'quotation').replace(/[^A-Za-z0-9_.-]+/g, '-') + '.pdf';
  var cmp = multi ? '<table class="cmp"><tr><th>Option</th><th>kW</th><th style="text-align:right">Kul (GST samet)</th></tr>' + opts.map(function (o) { return '<tr><td><b>' + esc(o.label) + '</b></td><td>' + esc(o.kw || '—') + '</td><td style="text-align:right"><b>' + esc(inr(o.total)) + '</b></td></tr>'; }).join('') + '</table>' : '';
  var cards = opts.map(function (o, i) {
    var its = (o.items || []).map(function (x) { return '<li>' + esc(x.n) + (x.q ? ' × ' + esc(x.q) + (x.u ? ' ' + esc(x.u) : '') : '') + (x.p != null ? ' — ' + esc(inr(x.p)) : '') + (x.sub && x.sub.length ? '<br><small>' + x.sub.map(esc).join(' · ') + '</small>' : '') + '</li>'; }).join('');
    return '<div class="opt' + (locked || !multi ? ' sel' : '') + '" data-o="' + esc(o.id) + '"><h2>' + esc(o.label) + (o.chosen ? ' ✔' : '') + '</h2>' + (o.kw ? '<div class="val" style="margin:0">' + esc(o.kw) + ' kW</div>' : '') + '<div class="tot">' + esc(inr(o.total)) + '</div><div class="val" style="margin:0">GST samet / जीएसटी सहित</div>' +
      (its ? '<ul>' + its + (o.n_items > (o.items || []).length ? '<li><small>… aur ' + (o.n_items - o.items.length) + ' items (PDF me)</small></li>' : '') + '</ul>' : '') +
      (o.pdf_url ? '<div class="row2"><a class="b s" style="padding:11px;font-size:15px" href="' + esc(dlUrl(o.pdf_url, fname)) + '" rel="noopener">⬇ PDF</a><a class="b s" style="padding:11px;font-size:15px" href="' + esc(o.pdf_url) + '" target="_blank" rel="noopener">👁 Dekhein</a></div>' : '') +
      (multi && !locked ? '<button type="button" class="b pick bt" data-pick="' + esc(o.id) + '">Ye option chunein <small>चुनें</small></button>' : '') + '</div>';
  }).join('');
  var banner = locked ? '<div class="ok">✔ ' + (q.reaccept ? 'Aapka chuna hua option: ' : 'Aapne ye option final kiya hai: ') + esc(locked.label || '') + '<br><span style="font-weight:600;font-size:13.5px">' + (q.reaccept ? 'Rate / items me badlav hua hai — kripya neeche dobara Accept karein.' : 'Humari team jaldi aapse sampark karegi. / हमारी टीम जल्द आपसे संपर्क करेगी।') + '</span></div>' : '';
  var est = q.est ? '<div class="ban" style="margin:14px 0 0"><b>Yah anumanit (estimate) quotation hai.</b><br>Aapki chhat, sthiti aur site visit ke baad keemat aur saamaan badal sakta hai. Antim quotation site visit ke baad milegi.<br><span style="font-size:13px">यह अनुमानित कोटेशन है। छत और साइट विजिट के बाद कीमत व सामान बदल सकता है; अंतिम कोटेशन साइट विजिट के बाद मिलेगी।</span></div>' : (q.final ? '<div class="ok" style="margin:14px 0 0">✔ Yah antim (final) quotation hai — site visit ke baad.</div>' : '');
  var hs = (q.history || []).map(function (h) { var T = { quote: 'Pehle bheji gayi', option: 'Vikalp jo chuna nahi', change: 'Aapne badlav maanga', accept: 'Aapne final kiya' }[h.t] || ''; if (!T) return ''; return '<li><b>' + esc(T) + '</b>' + (h.label ? ' — ' + esc(h.label) : '') + (h.kw ? ' (' + esc(h.kw) + ' kW)' : '') + (h.grand != null ? ' · ' + esc(inr(h.grand)) : '') + (h.note ? '<br><i>“' + esc(h.note) + '”</i>' : '') + (h.at ? '<br><small>' + esc(dmy(h.at)) + '</small>' : '') + '</li>'; }).join('') +
    (q.revs || []).map(function (v, i) { return '<li><b>Rate badla (Revision ' + (i + 2) + ')</b> · ' + esc(inr(v.before)) + ' → ' + esc(inr(v.after)) + (v.at ? '<br><small>' + esc(dmy(v.at)) + '</small>' : '') + '</li>'; }).join('');
  var hist = hs ? '<details class="hist"><summary>Aapko ab tak kya bheja gaya <small>इतिहास</small></summary><ul>' + hs + '</ul></details>' : '';
  var accNote = q.est ? '<p class="nt" style="margin:10px 0 0;font-size:13.5px">Accept ka matlab aap aage badhna chahte hain; antim keemat site visit ke baad tay hogi.</p>' : '';
  var acts = '';
  if (canAct) acts += '<button type="button" class="b p bt" id="bAcc">✔ ' + (multi && !locked ? 'Chuna hua option Accept karein' : 'Accept karein') + ' <small>स्वीकार करें</small></button>';
  acts += '<div class="row2"><button type="button" class="b s bt" id="bChg" style="padding:12px;font-size:15px">✏ Badlav chahiye <small>बदलाव</small></button><button type="button" class="b s bt" id="bCb" style="padding:12px;font-size:15px">📞 Call back <small>कॉल बैक</small></button></div>';
  var talk = phone.length === 10 ? '<div class="row2"><a class="b wa" style="padding:12px;font-size:15px" href="https://wa.me/91' + phone + '?text=' + encodeURIComponent('Namaste ' + brand + ', main ' + title + ' (' + (q.ref || '') + ') ke baare me baat karna chahta hoon.') + '" rel="noopener">💬 WhatsApp</a><a class="b s" style="padding:12px;font-size:15px" href="tel:+91' + phone + '">📞 Call</a></div>' : '';
  var panel = '<div class="box2" id="pAcc" hidden>' + termsHtml(d.terms) + '<label for="l4">Pakka? Apne registered mobile ke <b>aakhri 4 ank</b> likhein</label><input id="l4" inputmode="numeric" maxlength="4" autocomplete="off" placeholder="____"><p class="val" style="margin:6px 0 0">Accept karne par ye option final ho jayega; humari team aapko call karegi. Accept ke baad isi page par payment ka tareeka dikhega.</p><button type="button" class="b p bt" id="bAccOk" style="margin-top:10px">Haan, Accept karein</button></div>' +
    '<div class="box2" id="pChg" hidden><label for="ch">Kya badlav chahiye?</label><textarea id="ch" rows="3" maxlength="300" placeholder="Jaise: 5 kW chahiye / rate kam / brand badalna hai"></textarea><button type="button" class="b p bt" id="bChgOk" style="margin-top:10px">Bhejein</button></div>';
  var js = '(function(){var U=' + JSON.stringify(db.url).replace(/</g, '\\u003c') + ',K=' + JSON.stringify(db.key).replace(/</g, '\\u003c') + ',T=' + JSON.stringify(code) + ',TV=' + JSON.stringify((d.terms && d.terms.ver) || '') + ',MULTI=' + (multi && !locked ? 'true' : 'false') + ',SEL=' + JSON.stringify(!multi || locked ? (opts[0] || {}).id || '' : '') + ';' +
    'function $(i){return document.getElementById(i)}function say(t,k){var m=$("msg");m.textContent=t||"";m.className="msg"+(k?" "+k:"")}' +
    'function call(a,o,l4,n){var h={"Content-Type":"application/json",apikey:K};if(K.indexOf("sb_")!==0)h.Authorization="Bearer "+K;return fetch(U+"/rest/v1/rpc/sp_quote_respond",{method:"POST",headers:h,body:JSON.stringify({p_token:T,p_action:a,p_opt:o||null,p_last4:l4||null,p_note:n||null,p_terms:(a==="accept"&&TV)?TV:null})}).then(function(r){return r.text().then(function(t){var j=null;try{j=JSON.parse(t)}catch(e){}if(!r.ok)throw new Error((j&&(j.message||j.hint))||"error");return j})})}' +
    'function show(id,on){$(id).hidden=!on}' +
    'var tv=$("tv");if(tv)tv.onclick=function(e){e.preventDefault();$("tb").hidden=!$("tb").hidden};' +
    'var ps=document.querySelectorAll("[data-pick]");for(var i=0;i<ps.length;i++)ps[i].onclick=function(){SEL=this.getAttribute("data-pick");var os=document.querySelectorAll(".opt");for(var j=0;j<os.length;j++)os[j].className="opt"+(os[j].getAttribute("data-o")===SEL?" sel":"");say("Chuna: "+this.parentNode.querySelector("h2").textContent+" — ab neeche Accept dabayein","good")};' +
    'if($("bAcc"))$("bAcc").onclick=function(){if(MULTI&&!SEL){say("Pehle ek option chunein (\\"Ye option chunein\\")","bad");return}show("pChg",false);show("pAcc",true);$("l4").focus();say("")};' +
    '$("bChg").onclick=function(){show("pAcc",false);show("pChg",true);$("ch").focus();say("")};' +
    '$("bAccOk").onclick=function(){var v=$("l4").value.replace(/\\D/g,"");if(TV&&(!$("tk")||!$("tk").checked)){say("Pehle Disclaimer par tick karein / पहले Disclaimer पर टिक करें","bad");return}if(v.length!==4){say("4 ank likhein","bad");return}this.disabled=true;var b=this;call("accept",SEL,v).then(function(r){if(r&&r.error){say(r.error,"bad");b.disabled=false;return}say("✔ Accept ho gaya — dhanyavaad!","good");setTimeout(function(){location.reload()},900)},function(e){say(e.message||"nahi hua","bad");b.disabled=false})};' +
    '$("bChgOk").onclick=function(){var v=$("ch").value.trim();if(v.length<3){say("Thoda likhein","bad");return}this.disabled=true;var b=this;call("change",null,null,v).then(function(r){if(r&&r.error){say(r.error,"bad");b.disabled=false;return}say("✔ Aapka sandesh pahunch gaya — hum jaldi sampark karenge","good");show("pChg",false);b.disabled=false},function(e){say(e.message||"nahi hua","bad");b.disabled=false})};' +
    '$("bCb").onclick=function(){this.disabled=true;var b=this;call("callback").then(function(){say("✔ Hum aapko jaldi call karenge","good")},function(e){say(e.message||"nahi hua","bad");b.disabled=false})};})();';
  return head({ title: title, kind: 'quote' }, origin, code, qs, K, brand, desc, origin + '/img/share/quote.png', LIVE_CSS + PAY_CSS) +
    '<div class="top"><img src="/assets/logo-mark.png" alt=""><b>' + esc(brand) + '</b><span>' + esc(K[0]) + '</span></div><main class="w"><div class="card"><span class="chip">' + esc(K[0]) + ' · ' + esc(K[1]) + '</span><h1>' + esc(title) + '</h1><p class="sub">' + esc(q.ref || '') + (q.valid_till ? ' · Valid till / मान्य तिथि: <b>' + esc(dmy(q.valid_till)) + '</b>' : '') + '</p>' + banner + cmp + cards + est + hist + '<div class="acts">' + acts + '</div>' + accNote + panel + '<div class="msg" id="msg" role="status"></div>' + talk +
    payBox(d.pay) +
    (hasHow ? '<a class="b s" style="margin-top:14px;padding:13px;font-size:15.5px" href="' + esc(origin + '/d/' + code + '?p=how' + (qs ? '&e=s' : '')) + '">🎬 Hum kaise kaam karte hain — dekhein <small>हम कैसे काम करते हैं</small></a>' : '') +
    '</div><p class="ft">Shared by ' + esc(brand) + ' · <a href="' + esc(origin) + '/">' + esc(origin.replace(/^https?:\/\//, '')) + '</a></p></main>' + payScripts(d.pay) + '<script>' + js + '</script></body></html>';
}
/* ---------------- Round 53: "Hum kaise kaam karte hain" — namune (sirf Customer Samples folder) ---------------- */
var HOW_CSS = '.ban{background:#fff4e0;border:1px solid #f1d9a8;color:#6b4a00;border-radius:14px;padding:12px 14px;font-size:14px;line-height:1.5;margin-bottom:14px}.grp{margin-top:16px}.grp h2{font-size:19px;margin:0 0 2px;color:var(--d)}.grp .nt{color:var(--mut);font-size:14px;margin:0 0 8px}figure{margin:10px 0 0}figure img{display:block;width:100%;height:auto;border-radius:12px;border:1px solid var(--ln);background:#fff}figcaption{font-size:13px;color:var(--mut);margin-top:5px}.back{margin-bottom:14px}';
function howPage(d, how, origin, code, qs) {
  var K = KIND.quote, brand = d.brand || 'Sunpowers', base = origin + '/d/' + code, q2 = qs ? '&e=s' : '';
  var groups = (how && how.groups) || [];
  var body = groups.map(function (g) {
    return '<section class="card grp"><h2>' + esc(g.title) + '</h2>' + (g.note ? '<p class="nt">' + esc(g.note) + '</p>' : '') + (g.docs || []).map(function (f) {
      var u = esc(base + '?f=' + f.id + q2);
      if (/pdf/.test(f.mime || '')) return '<a class="b s" style="margin-top:10px;padding:12px;font-size:15px" href="' + u + '" target="_blank" rel="noopener">📄 ' + esc(f.title) + '</a>';
      return '<figure><a href="' + u + '" target="_blank" rel="noopener"><img src="' + u + '" alt="' + esc(f.title) + '" loading="lazy"></a><figcaption><b>' + esc(f.title) + '</b>' + (f.note ? ' — ' + esc(f.note) : '') + '</figcaption></figure>';
    }).join('') + '</section>';
  }).join('');
  return head({ title: 'Hum kaise kaam karte hain', kind: 'quote' }, origin, code, qs, K, brand, 'Hum kaise kaam karte hain — ' + brand, origin + '/img/share/quote.png', HOW_CSS) +
    '<div class="top"><img src="/assets/logo-mark.png" alt=""><b>' + esc(brand) + '</b><span>Hum kaise kaam karte hain</span></div><main class="w">' +
    '<a class="b s back" style="padding:11px;font-size:15px" href="' + esc(base + (qs || '')) + '">← Quotation par wapas <small>वापस</small></a>' +
    '<div class="ban"><b>Ye sab NAMUNA hai — sirf samjhane ke liye.</b><br>Aapki chhat aur sthiti ke anusaar asli design / report / samay alag ho sakta hai.<br><span style="font-size:13px">ये सब नमूना है — सिर्फ समझाने के लिए। आपकी छत और स्थिति के अनुसार असली डिज़ाइन / रिपोर्ट / समय अलग हो सकता है।</span></div>' +
    (body || '<div class="card"><p class="sub">Abhi koi namuna nahi hai.</p></div>') +
    '<a class="b p" style="margin-top:18px" href="' + esc(base + (qs || '')) + '">← Quotation par wapas <small>वापस</small></a><p class="ft">Shared by ' + esc(brand) + '</p></main></body></html>';
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
    if (q.f) {   /* namune ki file (sirf Customer Samples folder, sirf chalu link par) */
      var fid = String(q.f).replace(/[^0-9]/g, '').slice(0, 12), fr = fid ? await rpcCall(dbFor(host, q.e === 's'), 'sp_sample_file', { p_token: code, p_id: Number(fid) }) : null;
      if (!fr || !fr.b64) { res.statusCode = 404; res.setHeader('Content-Type', 'text/plain; charset=utf-8'); return res.end('Not found'); }
      res.statusCode = 200; res.setHeader('Content-Type', fr.mime); res.setHeader('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; img-src data:; sandbox"); res.setHeader('X-Content-Type-Options', 'nosniff'); res.setHeader('Cache-Control', 'private, max-age=300'); res.setHeader('Content-Disposition', 'inline');
      return res.end(Buffer.from(fr.b64, 'base64'));
    }
    var ua = (req.headers && req.headers['user-agent']) || '';
    var db = dbFor(host, q.e === 's'), d = await openShare(db, code, !BOT.test(ua) && req.method !== 'HEAD');
    if (!d) { res.statusCode = 404; return res.end(gone(origin)); }
    res.statusCode = 200;
    if (req.method === 'HEAD') return res.end('');
    var qs = q.e === 's' ? '?e=s' : '';
    if (d.state) return res.end(stateGone(d, origin));
    if (d.live && d.quote) {
      var sm = null; try { sm = await rpcCall(db, 'sp_samples', { p_token: code }); } catch (e1) { sm = null; }
      if (q.p === 'how') return res.end(howPage(d, sm, origin, code, qs));
      return res.end(livePage(d, origin, code, qs, db, !!(sm && sm.groups && sm.groups.length)));
    }
    return res.end(page(d, origin, code, qs));
  } catch (e) {
    res.statusCode = 503; return res.end(gone(origin).replace('यह लिंक बंद या पुराना हो गया है', 'अभी लिंक नहीं खुल रहा, कुछ देर बाद फिर कोशिश करें'));
  }
};
module.exports._how = howPage; module.exports._page = page; module.exports._live = livePage; module.exports._state = stateGone; module.exports._dbFor = dbFor;
