/* Sunpowers App — install on the phone without any app store (Round 31).
   Android Chrome: real "Install" button (browser install prompt). iPhone: step-by-step "Add to Home Screen" guide.
   Shows a small dismissible bar, a footer link (data-pwa-install) and opens by itself when the page is opened as /?install=1 (link from the website). */
(function () {
  'use strict';
  var KEY = 'sp_pwa_dismiss', dp = null, ua = navigator.userAgent || '';
  var iOS = /iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1), android = /Android/i.test(ua),
    inApp = /FBAN|FBAV|FB_IAB|Instagram|WhatsApp|Snapchat|Line\/|Twitter|LinkedInApp|MicroMessenger|; wv\)/i.test(ua) || (iOS && !/Safari\//.test(ua) && !/CriOS|FxiOS|EdgiOS/.test(ua)),
    mobile = iOS || android;
  function standalone() { try { return matchMedia('(display-mode: standalone)').matches || navigator.standalone === true; } catch (e) { return false; } }
  function en() { return document.documentElement.lang === 'en'; }
  function L(k) { var d = { t: ['📲 Sunpowers App install karein', '📲 Sunpowers App इंस्टॉल करें'], bar: ['Install the app — order faster, no Play Store needed', 'ऐप इंस्टॉल करें — जल्दी ऑर्डर, Play Store की ज़रूरत नहीं'], go: ['Install', 'इंस्टॉल'], now: ['Install now', 'अभी इंस्टॉल करें'], later: ['Not now', 'अभी नहीं'], done: ['App is already installed on this phone ✓', 'ऐप इस फ़ोन में पहले से इंस्टॉल है ✓'],
    i1: ['Open this page in <b>Safari</b>', 'इस पेज को <b>Safari</b> में खोलें'], i2: ['Tap the <b>Share</b> button <span class="pw-ic">⬆️</span> at the bottom', 'नीचे <b>Share</b> बटन <span class="pw-ic">⬆️</span> दबाएँ'], i3: ['Choose <b>Add to Home Screen</b>', '<b>Add to Home Screen</b> चुनें'], i4: ['Tap <b>Add</b> — the app icon appears on your home screen', '<b>Add</b> दबाएँ — होम स्क्रीन पर ऐप आ जाएगा'],
    a1: ['Open this page in <b>Chrome</b>', 'इस पेज को <b>Chrome</b> में खोलें'], a2: ['Tap the menu <b>⋮</b> (top right)', 'ऊपर दाईं तरफ़ मेन्यू <b>⋮</b> दबाएँ'], a3: ['Choose <b>Install app</b> (or <b>Add to Home screen</b>)', '<b>Install app</b> (या <b>Add to Home screen</b>) चुनें'], a4: ['Tap <b>Install</b>', '<b>Install</b> दबाएँ'],
    d1: ['In Chrome, click the install icon <b>⊕</b> at the right end of the address bar', 'Chrome में एड्रेस बार के दाएँ सिरे पर इंस्टॉल आइकन <b>⊕</b> दबाएँ'], w1: ['This page is open inside another app (WhatsApp / Instagram / Facebook) — it cannot be installed from here.', 'यह पेज किसी दूसरे ऐप (WhatsApp / Instagram / Facebook) के अंदर खुला है — यहाँ से इंस्टॉल नहीं हो सकता।'], wa: ['Tap the menu <b>⋮</b> (or <b>⋯</b>) at the top and choose <b>Open in Chrome</b>', 'ऊपर मेन्यू <b>⋮</b> (या <b>⋯</b>) दबाकर <b>Chrome में खोलें</b> चुनें'], wi: ['Tap the <b>Safari</b> / compass icon (or menu <b>⋯</b> → <b>Open in Safari</b>)', 'ऊपर/नीचे <b>Safari</b> (कंपास) आइकन या मेन्यू <b>⋯</b> → <b>Open in Safari</b> दबाएँ'], wc: ['Or copy the link and paste it in your browser', 'या लिंक कॉपी करके अपने ब्राउज़र में खोलें'], copy: ['Copy link', 'लिंक कॉपी करें'], copied: ['Link copied ✓', 'लिंक कॉपी हो गया ✓'],
    pc: ['This app is made for phones. Open this address on your phone:', 'यह ऐप फ़ोन के लिए है। अपने फ़ोन में यह पता खोलें:'], pc2: ['On Android use Chrome, on iPhone use Safari.', 'Android में Chrome और iPhone में Safari इस्तेमाल करें।'],
    ok: ['Installed ✓ Find “Sunpowers App” on your home screen', 'इंस्टॉल हो गया ✓ होम स्क्रीन पर “Sunpowers App” देखें'] }[k]; return d ? d[en() ? 0 : 1] : k; }
  function css() {
    if (document.getElementById('pwCss')) return; var s = document.createElement('style'); s.id = 'pwCss';
    s.textContent = '.pw-bar{position:fixed;left:12px;right:70px;bottom:calc(var(--navh,64px) + env(safe-area-inset-bottom,0px) + 10px);z-index:56;display:flex;align-items:center;gap:10px;background:#0f4d2b;color:#fff;border-radius:16px;padding:10px 12px;box-shadow:0 6px 22px rgba(0,0,0,.28);font:600 13.5px/1.3 system-ui,sans-serif}.pw-bar span{flex:1;min-width:0}.pw-bar button{font:inherit;border:0;cursor:pointer}.pw-go{background:#f9a825;color:#1c2b20;font-weight:800;border-radius:999px;padding:8px 14px}.pw-x{background:none;color:#fff;font-size:18px;padding:4px 6px;opacity:.8}' +
      '.pw-dlg{position:fixed;inset:0;z-index:9995;background:rgba(10,20,12,.55);display:flex;align-items:flex-end;justify-content:center}@media(min-width:600px){.pw-dlg{align-items:center}}.pw-c{background:#fff;color:#1c2b20;width:100%;max-width:440px;border-radius:22px 22px 0 0;padding:20px 18px calc(18px + env(safe-area-inset-bottom,0px));font:500 15px/1.45 system-ui,sans-serif}@media(min-width:600px){.pw-c{border-radius:22px}}.pw-c h3{font-size:19px;margin:0 0 10px}.pw-c ol{margin:0 0 14px;padding-left:22px;display:grid;gap:8px}.pw-ic{display:inline-block;border:1px solid #cfd8cf;border-radius:6px;padding:0 5px}.pw-c .pw-row{display:flex;gap:8px;flex-wrap:wrap}.pw-c button{font:inherit;border:0;cursor:pointer;border-radius:999px;padding:11px 18px;font-weight:800}.pw-p{background:#1e8e3e;color:#fff}.pw-s{background:#eef3ee;color:#1c2b20}';
    document.head.appendChild(s);
  }
  function dismissed() { try { var t = parseInt(localStorage.getItem(KEY) || '0', 10); return t && Date.now() - t < 7 * 864e5; } catch (e) { return false; } }
  function bar() {
    if (standalone() || dismissed() || document.getElementById('pwBar') || !(dp || (iOS && !inApp))) return;
    css(); var b = document.createElement('div'); b.className = 'pw-bar'; b.id = 'pwBar'; b.setAttribute('data-noi18n', '');
    b.innerHTML = '<span>' + L('bar') + '</span><button type="button" class="pw-go" data-pw-open>' + L('go') + '</button><button type="button" class="pw-x" data-pw-x aria-label="Close">✕</button>';
    document.body.appendChild(b);
  }
  function closeBar(keep) { var b = document.getElementById('pwBar'); if (b) b.remove(); if (!keep) try { localStorage.setItem(KEY, String(Date.now())); } catch (e) {} }
  function dlg() {
    var old = document.getElementById('pwDlg'); if (old) old.remove(); css();
    var d = document.createElement('div'); d.className = 'pw-dlg'; d.id = 'pwDlg'; d.setAttribute('data-noi18n', '');
    var body;
    var url = location.origin + '/', cp = '<p><b style="word-break:break-all">' + url + '</b></p>';
    if (standalone()) body = '<p>' + L('done') + '</p>';
    else if (inApp && mobile && !dp) body = '<p>' + L('w1') + '</p><ol><li>' + L(iOS ? 'wi' : 'wa') + '</li></ol><p>' + L('wc') + '</p>' + cp;
    else if (!mobile && !dp) body = '<p>' + L('pc') + '</p>' + cp + '<p>' + L('pc2') + '</p>';
    else if (dp) body = '<p>' + L('bar') + '</p>';
    else if (iOS) body = '<ol><li>' + L('i1') + '</li><li>' + L('i2') + '</li><li>' + L('i3') + '</li><li>' + L('i4') + '</li></ol>';
    else if (android) body = '<ol><li>' + L('a1') + '</li><li>' + L('a2') + '</li><li>' + L('a3') + '</li><li>' + L('a4') + '</li></ol>';
    else body = '<p>' + L('d1') + '</p>';
    d.innerHTML = '<div class="pw-c" role="dialog" aria-modal="true"><h3>' + L('t') + '</h3>' + body + '<div class="pw-row">' + (dp && !standalone() ? '<button type="button" class="pw-p" data-pw-now>' + L('now') + '</button>' : '') + (!standalone() && !dp && (inApp || !mobile) ? '<button type="button" class="pw-p" data-pw-copy>' + L('copy') + '</button>' : '') + '<button type="button" class="pw-s" data-pw-close>' + L('later') + '</button></div></div>';
    document.body.appendChild(d);
  }
  function closeDlg() { var d = document.getElementById('pwDlg'); if (d) d.remove(); }
  function install() {
    if (!dp) return; var p = dp; dp = null;
    try { p.prompt(); (p.userChoice || Promise.resolve()).then(function (c) { closeDlg(); closeBar(true); if (c && c.outcome === 'dismissed') { try { localStorage.setItem(KEY, String(Date.now())); } catch (e) {} } }); } catch (e) { closeDlg(); }
  }
  /* Round 34: Chrome's install prompt often arrives AFTER the first (manual-steps) dialog opened — replace that dialog so the real Install button shows */
  window.addEventListener('beforeinstallprompt', function (e) { e.preventDefault(); dp = e; bar(); if (/[?&]install=1/.test(location.search) && !standalone()) dlg(); });
  window.addEventListener('appinstalled', function () { dp = null; closeBar(true); closeDlg(); try { var t = document.getElementById('toast'); if (t) { t.textContent = L('ok'); t.classList.add('show'); setTimeout(function () { t.classList.remove('show'); }, 3500); } } catch (e) {} });
  document.addEventListener('click', function (e) {
    var g = e.target.closest ? e.target.closest('[data-pwa-install],[data-pw-open],[data-pw-x],[data-pw-now],[data-pw-close],[data-pw-copy],.pw-dlg') : null; if (!g) return;
    if (g.hasAttribute('data-pwa-install') || g.hasAttribute('data-pw-open')) { e.preventDefault(); dlg(); }
    else if (g.hasAttribute('data-pw-x')) closeBar(false);
    else if (g.hasAttribute('data-pw-now')) install();
    else if (g.hasAttribute('data-pw-copy')) { var u = location.origin + '/', done = function () { g.textContent = L('copied'); }; try { navigator.clipboard.writeText(u).then(done, done); } catch (er) { done(); } }
    else if (g.hasAttribute('data-pw-close') || (g.classList.contains('pw-dlg') && e.target === g)) closeDlg();
  });
  if ('serviceWorker' in navigator && window.isSecureContext) window.addEventListener('load', function () { try { navigator.serviceWorker.register('sw.js').catch(function () {}); } catch (e) {} });
  window.addEventListener('load', function () {
    setTimeout(bar, 2500);
    if (/[?&]install=1/.test(location.search)) setTimeout(function () { if (!document.getElementById('pwDlg')) dlg(); }, 900);
  });
  window.SPPWA = { open: dlg, standalone: standalone, canPrompt: function () { return !!dp; } };
})();
