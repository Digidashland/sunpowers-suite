/* Sunpowers Apps page (Round 50).
   Shows ONLY the install steps that match the visitor's own device (iPhone / Android / computer).
   Apps are installed from their own address (store / crm), so this page only opens them and explains the steps.
   Privacy: the page carries no customer or company data; the only things shown are the two official links.
   The links can NOT be changed from the address bar (no ?url= overrides) — only from config.js. */
(function () {
  'use strict';
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var ua = navigator.userAgent || '';
  var iOS = /iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  var android = /Android/i.test(ua);
  var mobile = iOS || android;
  var inApp = mobile && (/FBAN|FBAV|FB_IAB|Instagram|WhatsApp|Snapchat|Line\/|Twitter|LinkedInApp|MicroMessenger|; wv\)/i.test(ua) || (iOS && !/Safari\//.test(ua) && !/CriOS|FxiOS|EdgiOS/.test(ua)));
  var dkind = mobile ? '' : (/Firefox\//.test(ua) ? 'firefox' : (/Edg\/|Chrome\/|CriOS|OPR\//.test(ua) ? 'chromium' : (/Safari\//.test(ua) ? 'safari' : 'other')));
  var dev = iOS ? 'ios' : android ? 'android' : 'desktop';
  function standalone() { try { return matchMedia('(display-mode: standalone)').matches || navigator.standalone === true; } catch (e) { return false; } }
  function en() { return document.documentElement.lang === 'en'; }
  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }

  /* ---------- official links (never from the address bar) ---------- */
  var LIVE = { store: 'https://store.sunpowers.in', crm: 'https://crm.sunpowers.in' };
  function urlFor(app) {
    var h = location.hostname, m;
    if (/(^|\.)sunpowers\.in$/.test(h)) return LIVE[app];
    m = h.match(/^(.*?)-(website|store|admin|crm)(-git-.*)$/);               /* staging preview: same branch, other app */
    if (m) return location.protocol + '//' + m[1] + '-' + app + m[3];
    var c = window.SITE || {}, v = String(app === 'store' ? c.SHOP_URL : c.CRM_URL).trim();
    return /^https:\/\//.test(v) ? v.replace(/\/+$/, '') : LIVE[app];
  }

  /* ---------- text (Hindi / English) ---------- */
  var T = {
    h1: ['Sunpowers Apps', 'Sunpowers ऐप्स'],
    sub: ['Install the app on your phone or computer — no Play Store or App Store needed.', 'अपने फ़ोन या कंप्यूटर में ऐप इंस्टॉल करें — Play Store / App Store की ज़रूरत नहीं।'],
    devAnd: ['📱 Android phone detected', '📱 आपका डिवाइस: Android फ़ोन'], devIos: ['📱 iPhone / iPad detected', '📱 आपका डिवाइस: iPhone / iPad'], devPc: ['💻 Computer / laptop detected', '💻 आपका डिवाइस: कंप्यूटर / लैपटॉप'],
    inst: ['✓ You opened this from the installed app', '✓ आपने इसे इंस्टॉल किए हुए ऐप से खोला है'],
    storeN: ['Sunpowers Store App', 'Sunpowers Store ऐप'], storeFor: ['For customers', 'ग्राहकों के लिए'],
    storeD: ['Shop solar products, track your orders, bills and plant details — all in one place.', 'सोलर प्रोडक्ट खरीदें, ऑर्डर, बिल और प्लांट की जानकारी — सब एक जगह।'],
    crmN: ['Sunpowers CRM', 'Sunpowers CRM'], crmFor: ['Only for Staff · Dealer · Influencer · Partner', 'सिर्फ़ Staff · Dealer · Influencer · Partner के लिए'],
    crmD: ['Work app for the Sunpowers team and partners. You need a login ID given by Sunpowers.', 'Sunpowers टीम और पार्टनर्स का वर्क ऐप। इसके लिए Sunpowers से मिली लॉगिन ID चाहिए।'],
    openA: ['Install', 'इंस्टॉल करें'], openI: ['Open in Safari & install', 'Safari में खोलकर इंस्टॉल करें'], openD: ['Open in browser', 'ब्राउज़र में खोलें'],
    steps: ['Steps', 'स्टेप्स'],
    a1: ['Tap <b>Install</b> above — it opens in <b>Chrome</b>', 'ऊपर <b>इंस्टॉल करें</b> दबाएँ — यह <b>Chrome</b> में खुलेगा'], a2: ['If Chrome shows an install box, tap <b>Install</b>', 'Chrome इंस्टॉल का बॉक्स दिखाए तो <b>Install</b> दबाएँ'], a3: ['Otherwise: menu <b>⋮</b> (top right) → <b>Install app</b> → <b>Install</b>', 'नहीं दिखे तो: ऊपर दाईं तरफ़ मेन्यू <b>⋮</b> → <b>Install app</b> → <b>Install</b>'],
    i1: ['Tap the button above — it opens in <b>Safari</b>', 'ऊपर का बटन दबाएँ — यह <b>Safari</b> में खुलेगा'], i2: ['Tap the <b>Share</b> button <span class="ap-ico">⬆️</span> at the bottom', 'नीचे <b>Share</b> बटन <span class="ap-ico">⬆️</span> दबाएँ'], i3: ['Choose <b>Add to Home Screen</b>', '<b>Add to Home Screen</b> चुनें'], i4: ['Tap <b>Add</b> — the icon appears on your home screen', '<b>Add</b> दबाएँ — होम स्क्रीन पर आइकन आ जाएगा'],
    d1: ['Click <b>Open in browser</b> above', 'ऊपर <b>ब्राउज़र में खोलें</b> दबाएँ'], d2: ['Click the install icon <span class="ap-ico">⊕</span> at the right end of the address bar (or menu <b>⋮</b> → <b>Install</b> / <b>Cast, save and share → Install page as app</b>)', 'एड्रेस बार के दाएँ सिरे पर इंस्टॉल आइकन <span class="ap-ico">⊕</span> दबाएँ (या मेन्यू <b>⋮</b> → <b>Install</b>)'], d3: ['Click <b>Install</b> — it opens like a normal desktop app', '<b>Install</b> दबाएँ — यह सामान्य डेस्कटॉप ऐप की तरह खुलेगा'],
    m1: ['Click <b>Open in browser</b> above (use Safari)', 'ऊपर <b>ब्राउज़र में खोलें</b> दबाएँ (Safari में)'], m2: ['In the menu bar choose <b>File → Add to Dock…</b>', 'मेन्यू बार में <b>File → Add to Dock…</b> चुनें'], m3: ['Click <b>Add</b>', '<b>Add</b> दबाएँ'],
    f1: ['Firefox on a computer cannot install apps. Open the app in <b>Chrome</b> or <b>Edge</b> to install it, or just use it in the browser.', 'कंप्यूटर पर Firefox में ऐप इंस्टॉल नहीं होता। इंस्टॉल के लिए <b>Chrome</b> या <b>Edge</b> में खोलें, या ब्राउज़र में ही चलाएँ।'],
    noteShared: ['Do not install on a shared / office computer. Always log out after work.', 'साझा / ऑफ़िस कंप्यूटर पर इंस्टॉल न करें। काम के बाद हमेशा लॉग-आउट करें।'],
    qrT: ['Scan with a phone camera to open', 'फ़ोन के कैमरे से स्कैन करके खोलें'], qrShow: ['Show QR code', 'QR कोड दिखाएँ'], qrHide: ['Hide QR code', 'QR कोड छुपाएँ'], qrDl: ['Download QR', 'QR डाउनलोड'], qrPr: ['Print QR', 'QR प्रिंट'], cp: ['Copy link', 'लिंक कॉपी करें'], cpd: ['Link copied ✓', 'लिंक कॉपी हो गया ✓'],
    wTitle: ['This page is open inside another app (WhatsApp / Instagram / Facebook).', 'यह पेज किसी दूसरे ऐप (WhatsApp / Instagram / Facebook) के अंदर खुला है।'],
    wA: ['Tap the menu <b>⋮</b> (or <b>⋯</b>) at the top and choose <b>Open in Chrome</b>.', 'ऊपर मेन्यू <b>⋮</b> (या <b>⋯</b>) दबाकर <b>Chrome में खोलें</b> चुनें।'], wI: ['Tap the <b>Safari</b> (compass) icon, or menu <b>⋯</b> → <b>Open in Safari</b>.', '<b>Safari</b> (कंपास) आइकन दबाएँ, या मेन्यू <b>⋯</b> → <b>Open in Safari</b> चुनें।'],
    wC: ['Or copy this page link and paste it in your browser:', 'या इस पेज का लिंक कॉपी करके अपने ब्राउज़र में खोलें:'],
    othShow: ['Steps for another device ▾', 'दूसरे डिवाइस के स्टेप्स देखें ▾'], othHide: ['Hide other devices ▴', 'दूसरे डिवाइस के स्टेप्स छुपाएँ ▴'],
    nAnd: ['Android phone / tablet', 'Android फ़ोन / टैबलेट'], nIos: ['iPhone / iPad', 'iPhone / iPad'], nPc: ['Computer / laptop (Chrome or Edge)', 'कंप्यूटर / लैपटॉप (Chrome या Edge)'], nMac: ['Mac with Safari', 'Mac में Safari'],
    pv: ['Please note', 'ज़रूरी बातें'],
    p1: ['The CRM is only for Sunpowers Staff, Dealers, Influencers and Partners. The login ID is given by Sunpowers — never share your ID or OTP with anyone.', 'CRM सिर्फ़ Sunpowers के Staff, Dealer, Influencer और Partner के लिए है। लॉगिन ID Sunpowers देता है — अपनी ID या OTP किसी को न दें।'],
    p2: ['Use only the official links on this page. Do not log in from a link that someone forwards to you.', 'सिर्फ़ इस पेज के आधिकारिक लिंक इस्तेमाल करें। किसी के भेजे हुए दूसरे लिंक पर लॉगिन न करें।'],
    p3: ['Keep your phone locked. If your phone is lost, tell Sunpowers at once so your login can be closed.', 'फ़ोन में लॉक रखें। फ़ोन खो जाए तो तुरंत Sunpowers को बताएँ ताकि आपकी लॉगिन बंद की जा सके।'],
    p4: ['Never install on a shared computer, and log out after your work.', 'साझा कंप्यूटर पर कभी इंस्टॉल न करें, और काम के बाद लॉग-आउट करें।']
  };
  function L(k) { var d = T[k]; return d ? d[en() ? 0 : 1] : k; }

  /* ---------- device-wise block (only the visitor's own device is drawn in the cards) ---------- */
  function ol(keys) { return '<ol class="ap-steps">' + keys.map(function (k) { return '<li>' + L(k) + '</li>'; }).join('') + '</ol>'; }
  function stepsFor(d, withNote) {
    var h;
    if (d === 'android') h = ol(['a1', 'a2', 'a3']);
    else if (d === 'ios') h = ol(['i1', 'i2', 'i3', 'i4']);
    else if (d === 'mac') h = ol(['m1', 'm2', 'm3']);
    else if (d === 'firefox') h = '<p class="ap-note">' + L('f1') + '</p>';
    else h = ol(['d1', 'd2', 'd3']);
    return h;
  }
  function myKind() { return dev === 'desktop' ? (dkind === 'safari' ? 'mac' : dkind === 'firefox' ? 'firefox' : 'desktop') : dev; }
  function openLabel() { return dev === 'android' ? L('openA') : dev === 'ios' ? L('openI') : L('openD'); }

  var APPS = [
    { id: 'store', ic: '🛒', n: 'storeN', f: 'storeFor', d: 'storeD', crm: false },
    { id: 'crm', ic: '📊', n: 'crmN', f: 'crmFor', d: 'crmD', crm: true }
  ];
  var QRSHOWN = {};

  function card(a) {
    var base = urlFor(a.id), go = base + '/?install=1', qrOn = QRSHOWN[a.id] != null ? QRSHOWN[a.id] : !mobile;
    var h = '<article class="ap-card' + (a.crm ? ' is-crm' : '') + '" data-app-id="' + a.id + '"><div class="ap-hd"><span class="ap-ic" aria-hidden="true">' + a.ic + '</span><div><h2>' + esc(L(a.n)) + '</h2><span class="ap-who">' + esc(L(a.f)) + '</span></div></div><p class="ap-d">' + esc(L(a.d)) + '</p>';
    if (inApp) h += '<div class="ap-act"><button type="button" class="btn btn-sun" data-copy="' + a.id + '">' + L('cp') + '</button></div>';
    else if (standalone()) h += '<p class="ap-note">' + L('inst') + '</p>';
    else h += '<div class="ap-act"><a class="btn btn-sun" href="' + esc(go) + '" target="_blank" rel="noopener" data-open="' + a.id + '">' + esc(openLabel()) + '</a></div>' + (mobile && !inApp ? '' : '') + '<div class="ap-st"><b>' + L('steps') + '</b>' + stepsFor(myKind()) + '</div>';
    if (a.crm || !mobile) h += '<p class="ap-note">' + L('noteShared') + '</p>';
    h += '<button type="button" class="btn btn-line ap-qrbtn" data-qrtoggle="' + a.id + '" aria-expanded="' + (qrOn ? 'true' : 'false') + '">' + (qrOn ? L('qrHide') : L('qrShow')) + '</button>';
    h += '<div class="ap-qr" data-qr="' + a.id + '"' + (qrOn ? '' : ' hidden') + '><span class="ap-qrc" data-qrc></span><div class="ap-qr-t"><span>' + L('qrT') + '</span><span class="ap-url">' + esc(base) + '</span><button type="button" class="btn btn-line" data-qrdl="' + a.id + '">' + L('qrDl') + '</button><button type="button" class="btn btn-line" data-qrpr="' + a.id + '">' + L('qrPr') + '</button><button type="button" class="btn btn-line" data-copy="' + a.id + '">' + L('cp') + '</button></div></div></article>';
    return h;
  }
  function paintQr() {
    APPS.forEach(function (a) {
      var box = $('[data-qr="' + a.id + '"] [data-qrc]'); if (!box || !window.SPQR) return;
      var cv = SPQR.canvas(urlFor(a.id) + '/?install=1', 264); cv.setAttribute('role', 'img'); cv.setAttribute('aria-label', 'QR ' + a.id); box.innerHTML = ''; box.appendChild(cv);
    });
  }
  function others() {
    var order = ['android', 'ios', 'desktop', 'mac'], me = myKind(), nm = { android: 'nAnd', ios: 'nIos', desktop: 'nPc', mac: 'nMac' };
    return order.filter(function (k) { return k !== me && !(me === 'firefox' && k === 'desktop'); }).map(function (k) { return '<section><h3>' + L(nm[k]) + '</h3>' + stepsFor(k) + '</section>'; }).join('');
  }
  function render() {
    var q = function (id) { return document.getElementById(id); };
    q('apH1').textContent = L('h1'); q('apSub').textContent = L('sub');
    q('apDev').textContent = L(dev === 'ios' ? 'devIos' : dev === 'android' ? 'devAnd' : 'devPc');
    var w = q('apIn'); if (inApp) { w.hidden = false; w.innerHTML = L('wTitle') + '<ol>' + '<li>' + L(iOS ? 'wI' : 'wA') + '</li></ol>' + L('wC') + ' <b style="word-break:break-all">' + esc(location.origin + location.pathname) + '</b><div class="ap-act" style="margin-top:10px"><button type="button" class="btn btn-sun" data-copyself>' + L('cp') + '</button></div>'; } else w.hidden = true;
    q('apApps').innerHTML = APPS.map(card).join('');
    var ob = q('apOthBtn'), op = q('apOth'), open = !op.hidden; op.innerHTML = others(); ob.textContent = open ? L('othHide') : L('othShow'); ob.setAttribute('aria-expanded', open ? 'true' : 'false');
    q('apPriv').innerHTML = '<h3>' + L('pv') + '</h3><ul><li>' + L('p1') + '</li><li>' + L('p2') + '</li><li>' + L('p3') + '</li><li>' + L('p4') + '</li></ul>';
    paintQr();
  }

  function copy(text, btn) {
    var done = function () { if (btn) { var o = btn.textContent; btn.textContent = L('cpd'); setTimeout(function () { btn.textContent = o; }, 2200); } };
    try { navigator.clipboard.writeText(text).then(done, function () { fall(); }); } catch (e) { fall(); }
    function fall() { var t = document.createElement('textarea'); t.value = text; t.style.cssText = 'position:fixed;opacity:0'; document.body.appendChild(t); t.select(); try { document.execCommand('copy'); } catch (e) {} t.remove(); done(); }
  }
  document.addEventListener('click', function (e) {
    var t = e.target.closest ? e.target.closest('button,a') : null; if (!t) return;
    var id;
    if (t.hasAttribute('data-copy')) { id = t.getAttribute('data-copy'); copy(urlFor(id) + '/?install=1', t); }
    else if (t.hasAttribute('data-copyself')) copy(location.origin + location.pathname, t);
    else if (t.hasAttribute('data-qrtoggle')) { id = t.getAttribute('data-qrtoggle'); var b = $('[data-qr="' + id + '"]'), on = b.hidden; b.hidden = !on; QRSHOWN[id] = on; t.textContent = on ? L('qrHide') : L('qrShow'); t.setAttribute('aria-expanded', on ? 'true' : 'false'); }
    else if (t.hasAttribute('data-qrdl')) {
      id = t.getAttribute('data-qrdl'); var cv = SPQR.canvas(urlFor(id) + '/?install=1', 720), fn = 'sunpowers-' + id + '-qr.png';
      cv.toBlob(function (bl) { if (!bl) return; var u = URL.createObjectURL(bl), a = document.createElement('a'); a.href = u; a.download = fn; document.body.appendChild(a); a.click(); a.remove(); setTimeout(function () { URL.revokeObjectURL(u); }, 4000); }, 'image/png');
    }
    else if (t.hasAttribute('data-qrpr')) {
      id = t.getAttribute('data-qrpr'); var c = $('[data-app-id="' + id + '"]'); c.classList.add('ap-printing'); var cvs = c.querySelector('canvas'); var old = cvs.cloneNode(true);
      try { window.print(); } catch (er) {} setTimeout(function () { c.classList.remove('ap-printing'); }, 400);
    }
    else if (t.id === 'apOthBtn') { var op = document.getElementById('apOth'); op.hidden = !op.hidden; t.textContent = op.hidden ? L('othShow') : L('othHide'); t.setAttribute('aria-expanded', op.hidden ? 'false' : 'true'); }
  });
  render();
  try { new MutationObserver(function () { render(); }).observe(document.documentElement, { attributes: true, attributeFilter: ['lang'] }); } catch (e) {}
  window.SPApps = { device: dev, kind: myKind, inApp: inApp, urlFor: urlFor };
})();
