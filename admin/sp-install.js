/* Sunpowers — "Install app" helper for CRM and Admin (Round 50). One shared file (same copy in crm/assets and admin).
   Android / Chrome / Edge: real Install button. iPhone: Add to Home Screen steps. Mac Safari: Add to Dock. In-app browsers (WhatsApp, Instagram): open-in-browser notice.
   Nothing is sent anywhere — it only shows steps and calls the browser's own install prompt.
   Use:  SPInstall.open()   |   any element with [data-sp-install]   |   page opened as /?install=1   |   SPInstall.available() tells if a button should be shown. */
(function () {
  'use strict';
  if (window.SPInstall) return;
  var dp = null, ua = navigator.userAgent || '', me = document.currentScript, NAME = (me && me.getAttribute('data-app-name')) || 'Sunpowers App';
  var iOS = /iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1), android = /Android/i.test(ua), mobile = iOS || android;
  var inApp = mobile && (/FBAN|FBAV|FB_IAB|Instagram|WhatsApp|Snapchat|Line\/|Twitter|LinkedInApp|MicroMessenger|; wv\)/i.test(ua) || (iOS && !/Safari\//.test(ua) && !/CriOS|FxiOS|EdgiOS/.test(ua)));
  var dk = mobile ? '' : (/Firefox\//.test(ua) ? 'firefox' : (/Edg\/|Chrome\/|OPR\//.test(ua) ? 'chromium' : (/Safari\//.test(ua) ? 'safari' : 'other')));
  function standalone() { try { return matchMedia('(display-mode: standalone)').matches || navigator.standalone === true; } catch (e) { return false; } }
  function en() { return document.documentElement.lang === 'en'; }
  var T = {
    t: ['Install ' + NAME, NAME + ' इंस्टॉल करें'], now: ['Install now', 'अभी इंस्टॉल करें'], later: ['Close', 'बंद करें'], done: ['The app is already installed here ✓', 'ऐप यहाँ पहले से इंस्टॉल है ✓'], ok: ['Installed ✓', 'इंस्टॉल हो गया ✓'],
    ready: ['Tap the button — your phone / browser will ask to install.', 'बटन दबाएँ — आपका फ़ोन / ब्राउज़र इंस्टॉल के लिए पूछेगा।'],
    i1: ['Open this page in <b>Safari</b>', 'इस पेज को <b>Safari</b> में खोलें'], i2: ['Tap the <b>Share</b> button <span class="spi-ic">⬆️</span> at the bottom', 'नीचे <b>Share</b> बटन <span class="spi-ic">⬆️</span> दबाएँ'], i3: ['Choose <b>Add to Home Screen</b>', '<b>Add to Home Screen</b> चुनें'], i4: ['Tap <b>Add</b> — the icon appears on your home screen', '<b>Add</b> दबाएँ — होम स्क्रीन पर आइकन आ जाएगा'],
    a1: ['Open this page in <b>Chrome</b>', 'इस पेज को <b>Chrome</b> में खोलें'], a2: ['Tap the menu <b>⋮</b> (top right)', 'ऊपर दाईं तरफ़ मेन्यू <b>⋮</b> दबाएँ'], a3: ['Choose <b>Install app</b> (or <b>Add to Home screen</b>)', '<b>Install app</b> (या <b>Add to Home screen</b>) चुनें'], a4: ['Tap <b>Install</b>', '<b>Install</b> दबाएँ'],
    d1: ['Click the install icon <span class="spi-ic">⊕</span> at the right end of the address bar (or menu <b>⋮</b> → <b>Install</b>)', 'एड्रेस बार के दाएँ सिरे पर इंस्टॉल आइकन <span class="spi-ic">⊕</span> दबाएँ (या मेन्यू <b>⋮</b> → <b>Install</b>)'], d2: ['Click <b>Install</b> — it opens like a normal desktop app', '<b>Install</b> दबाएँ — यह सामान्य डेस्कटॉप ऐप की तरह खुलेगा'],
    m1: ['In Safari menu bar choose <b>File → Add to Dock…</b>', 'Safari के मेन्यू बार में <b>File → Add to Dock…</b> चुनें'], m2: ['Click <b>Add</b>', '<b>Add</b> दबाएँ'],
    f1: ['Firefox on a computer cannot install apps. Open this page in <b>Chrome</b> or <b>Edge</b> to install it, or keep using it in the browser.', 'कंप्यूटर पर Firefox में ऐप इंस्टॉल नहीं होता। इंस्टॉल के लिए इसे <b>Chrome</b> या <b>Edge</b> में खोलें, या ब्राउज़र में ही चलाएँ।'],
    sh: ['Do not install on a shared / office computer. Always log out after work.', 'साझा / ऑफ़िस कंप्यूटर पर इंस्टॉल न करें। काम के बाद हमेशा लॉग-आउट करें।'],
    w1: ['This page is open inside another app (WhatsApp / Instagram / Facebook) — it cannot be installed from here.', 'यह पेज किसी दूसरे ऐप (WhatsApp / Instagram / Facebook) के अंदर खुला है — यहाँ से इंस्टॉल नहीं हो सकता।'],
    wa: ['Tap the menu <b>⋮</b> (or <b>⋯</b>) at the top and choose <b>Open in Chrome</b>', 'ऊपर मेन्यू <b>⋮</b> (या <b>⋯</b>) दबाकर <b>Chrome में खोलें</b> चुनें'], wi: ['Tap the <b>Safari</b> (compass) icon, or menu <b>⋯</b> → <b>Open in Safari</b>', '<b>Safari</b> (कंपास) आइकन दबाएँ, या मेन्यू <b>⋯</b> → <b>Open in Safari</b> दबाएँ'],
    wc: ['Or copy the link and paste it in your browser', 'या लिंक कॉपी करके अपने ब्राउज़र में खोलें'], copy: ['Copy link', 'लिंक कॉपी करें'], copied: ['Link copied ✓', 'लिंक कॉपी हो गया ✓']
  };
  function L(k) { var d = T[k]; return d ? d[en() ? 0 : 1] : k; }
  function css() {
    if (document.getElementById('spiCss')) return; var s = document.createElement('style'); s.id = 'spiCss';
    s.textContent = '.spi-dlg{position:fixed;inset:0;z-index:99990;background:rgba(10,20,12,.55);display:flex;align-items:flex-end;justify-content:center}@media(min-width:600px){.spi-dlg{align-items:center}}.spi-c{background:#fff;color:#1c2b20;width:100%;max-width:440px;border-radius:22px 22px 0 0;padding:20px 18px calc(18px + env(safe-area-inset-bottom,0px));font:500 15px/1.45 system-ui,sans-serif;max-height:90vh;overflow:auto}@media(min-width:600px){.spi-c{border-radius:22px}}.spi-c h3{font-size:19px;margin:0 0 10px}.spi-c p{margin:0 0 10px}.spi-c ol{margin:0 0 14px;padding-left:22px;display:grid;gap:8px}.spi-ic{display:inline-block;border:1px solid #cfd8cf;border-radius:6px;padding:0 5px}.spi-note{font-size:13px;color:#66756a;border-left:3px solid #dfe7de;padding-left:10px}.spi-row{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}.spi-c button{font:inherit;border:0;cursor:pointer;border-radius:999px;padding:11px 18px;font-weight:800}.spi-p{background:#1e8e3e;color:#fff}.spi-s{background:#eef3ee;color:#1c2b20}';
    document.head.appendChild(s);
  }
  function ol(k) { return '<ol>' + k.map(function (x) { return '<li>' + L(x) + '</li>'; }).join('') + '</ol>'; }
  function url() { return location.origin + '/'; }
  function open() {
    var old = document.getElementById('spiDlg'); if (old) old.remove(); css();
    var d = document.createElement('div'); d.className = 'spi-dlg'; d.id = 'spiDlg'; d.setAttribute('data-noi18n', '');
    var body, btns = '';
    if (standalone()) body = '<p>' + L('done') + '</p>';
    else if (inApp) { body = '<p>' + L('w1') + '</p>' + ol([iOS ? 'wi' : 'wa']) + '<p>' + L('wc') + '</p><p><b style="word-break:break-all">' + url() + '</b></p>'; btns = '<button type="button" class="spi-p" data-spi-copy>' + L('copy') + '</button>'; }
    else if (dp) { body = '<p>' + L('ready') + '</p>'; btns = '<button type="button" class="spi-p" data-spi-now>' + L('now') + '</button>'; }
    else if (iOS) body = ol(['i1', 'i2', 'i3', 'i4']);
    else if (android) body = ol(['a1', 'a2', 'a3', 'a4']);
    else if (dk === 'firefox') body = '<p>' + L('f1') + '</p>';
    else if (dk === 'safari') body = ol(['m1', 'm2']);
    else body = ol(['d1', 'd2']);
    if (!mobile && !standalone()) body += '<p class="spi-note">' + L('sh') + '</p>';
    d.innerHTML = '<div class="spi-c" role="dialog" aria-modal="true"><h3>📲 ' + L('t') + '</h3>' + body + '<div class="spi-row">' + btns + '<button type="button" class="spi-s" data-spi-close>' + L('later') + '</button></div></div>';
    document.body.appendChild(d);
  }
  function close() { var d = document.getElementById('spiDlg'); if (d) d.remove(); }
  function now() { if (!dp) return; var p = dp; dp = null; try { p.prompt(); (p.userChoice || Promise.resolve()).then(close); } catch (e) { close(); } }
  window.addEventListener('beforeinstallprompt', function (e) { e.preventDefault(); dp = e; if (document.getElementById('spiDlg')) open(); else if (/[?&]install=1/.test(location.search) && !standalone()) { var go = function () { if (!document.getElementById('spiDlg')) open(); }; if (document.body) go(); else addEventListener('DOMContentLoaded', go); } });
  window.addEventListener('appinstalled', function () { dp = null; close(); });
  document.addEventListener('click', function (e) {
    var g = e.target.closest ? e.target.closest('[data-sp-install],[data-spi-now],[data-spi-close],[data-spi-copy],.spi-dlg') : null; if (!g) return;
    if (g.hasAttribute('data-sp-install')) { e.preventDefault(); open(); }
    else if (g.hasAttribute('data-spi-now')) now();
    else if (g.hasAttribute('data-spi-copy')) { var done = function () { g.textContent = L('copied'); }; try { navigator.clipboard.writeText(url()).then(done, done); } catch (er) { done(); } }
    else if (g.hasAttribute('data-spi-close') || (g.classList.contains('spi-dlg') && e.target === g)) close();
  });
  window.addEventListener('load', function () { if (/[?&]install=1/.test(location.search) && !standalone()) setTimeout(function () { if (!document.getElementById('spiDlg')) open(); }, 1600); });
  window.SPInstall = { open: open, close: close, standalone: standalone, available: function () { return !standalone(); }, canPrompt: function () { return !!dp; }, inApp: inApp };
})();
