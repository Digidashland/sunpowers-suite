/* Sunpowers Store App — "Create ID with PIN" (name + mobile + 4-digit PIN, no OTP) and "Login with PIN".
   The profile photo is shrunk on the phone to about 5 KB, whatever the size of the picture the customer picks.
   Talks to sp_cust_signup / sp_cust_login / sp_cust_avatar (see the SQL). Works with the store's SP helper. */
(function () {
  'use strict';
  var Q = window.SPQID = { MAX: 5120 };
  var T = {
    hi: { create: 'PIN से ID बनाएँ', login: 'PIN से लॉगिन', name: 'आपका नाम', mobile: 'मोबाइल नंबर (10 अंक)', pin: '4 अंक का PIN', pin2: 'PIN दोबारा', photo: 'फ़ोटो', photoHint: 'अपनी फ़ोटो चुनें।', change: 'बदलें', remove: 'हटाएँ',
      btnCreate: '✔ ID बनाएँ', btnLogin: '🔐 लॉगिन', why: 'ऑर्डर और सर्विस के लिए सिर्फ़ नाम, मोबाइल और 4 अंक का PIN चाहिए — OTP नहीं।', whyLogin: 'अपने मोबाइल और PIN से लॉगिन करें।', forgot: 'PIN भूल गए? हमसे WhatsApp पर संपर्क करें',
      email: 'Email OTP से लॉगिन (पुराना तरीक़ा)', haveId: 'ID पहले से है? PIN से लॉगिन', close: 'बंद करें', needName: 'अपना नाम लिखें', needMob: 'सही 10 अंक का मोबाइल नंबर लिखें', needPin: 'PIN 4 अंक का हो', pinMis: 'दोनों PIN एक जैसे नहीं हैं', photoBad: 'यह फ़ोटो नहीं खुल पाई — दूसरी चुनें',
      off: 'अभी ID बनाना उपलब्ध नहीं है — कुछ देर बाद कोशिश करें', hello: 'स्वागत है', done: 'ID बन गई ✓', loggedIn: 'लॉगिन हो गया ✓', size: 'फ़ोटो {n} KB' },
    en: { create: 'Create ID with PIN', login: 'Login with PIN', name: 'Your name', mobile: 'Mobile number (10 digits)', pin: '4-digit PIN', pin2: 'PIN again', photo: 'Photo', photoHint: 'Choose your photo.', change: 'Change', remove: 'Remove',
      btnCreate: '✔ Create ID', btnLogin: '🔐 Login', why: 'For orders and services we only need your name, mobile and a 4-digit PIN — no OTP.', whyLogin: 'Log in with your mobile and PIN.', forgot: 'Forgot PIN? Contact us on WhatsApp',
      email: 'Login with email OTP (old way)', haveId: 'Already have an ID? Login with PIN', close: 'Close', needName: 'Enter your name', needMob: 'Enter a valid 10-digit mobile number', needPin: 'PIN must be 4 digits', pinMis: 'The two PINs do not match', photoBad: 'This photo could not be opened — pick another one',
      off: 'Creating an ID is not available right now — please try again later', hello: 'Welcome', done: 'ID created ✓', loggedIn: 'Logged in ✓', size: 'Photo {n} KB' }
  };
  function esc(v) { return String(v == null ? '' : v).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function rnd() { var a = new Uint8Array(20); (window.crypto || window.msCrypto).getRandomValues(a); return Array.prototype.map.call(a, function (x) { return ('0' + x.toString(16)).slice(-2); }).join(''); }
  function dev() { try { var d = JSON.parse(localStorage.getItem('spa_dev_store') || 'null'); if (!d || d.length < 20) { d = rnd(); localStorage.setItem('spa_dev_store', JSON.stringify(d)); } return d; } catch (e) { return rnd(); } }
  function devName() { var u = navigator.userAgent || ''; return (/Android/i.test(u) ? 'Android' : /iPhone|iPad/i.test(u) ? 'iPhone' : /Windows/i.test(u) ? 'Windows' : /Mac/i.test(u) ? 'Mac' : 'Device') + ' · ' + (/Edg\//.test(u) ? 'Edge' : /Chrome\//.test(u) ? 'Chrome' : /Firefox\//.test(u) ? 'Firefox' : /Safari\//.test(u) ? 'Safari' : 'Browser'); }
  function bytes(url) { var b = String(url).split(',')[1] || ''; return Math.floor(b.length * 3 / 4) - (b.slice(-2) === '==' ? 2 : b.slice(-1) === '=' ? 1 : 0); }
  Q.bytes = bytes;

  /* Any picture (any size) -> small square JPEG data URL of at most 5 KB. */
  Q.compress = function (file) {
    return new Promise(function (resolve, reject) {
      if (!file || !/^image\//.test(file.type || '')) return reject(new Error('photo'));
      var url = URL.createObjectURL(file), img = new Image();
      img.onerror = function () { URL.revokeObjectURL(url); reject(new Error('photo')); };
      img.onload = function () {
        URL.revokeObjectURL(url);
        try {
          var w = img.naturalWidth || img.width, h = img.naturalHeight || img.height; if (!w || !h) throw new Error('photo');
          var s = Math.min(w, h), sx = (w - s) / 2, sy = (h - s) / 2, sizes = [128, 112, 96, 80, 64, 48, 40, 32], best = null;
          for (var i = 0; i < sizes.length && !best; i++) {
            var c = document.createElement('canvas'); c.width = c.height = sizes[i];
            var g = c.getContext('2d'); g.fillStyle = '#fff'; g.fillRect(0, 0, c.width, c.height); g.imageSmoothingQuality = 'high'; g.drawImage(img, sx, sy, s, s, 0, 0, c.width, c.height);
            for (var q = 0.82; q >= 0.3; q -= 0.1) { var d = c.toDataURL('image/jpeg', q); if (bytes(d) <= Q.MAX) { best = d; break; } }
          }
          if (!best) throw new Error('photo'); resolve(best);
        } catch (e) { reject(e); }
      };
      img.src = url;
    });
  };

  var CSS = '.qid-ov{position:fixed;inset:0;z-index:99990;background:rgba(10,30,20,.58);display:flex;align-items:flex-end;justify-content:center}' +
    '.qid-box{background:#fff;color:#1c2b20;width:100%;max-width:440px;max-height:94vh;overflow:auto;border-radius:20px 20px 0 0;padding:18px 16px;padding-bottom:calc(20px + env(safe-area-inset-bottom,0px));position:relative}' +
    '@media(min-width:600px){.qid-ov{align-items:center;padding:16px}.qid-box{border-radius:20px}}' +
    '.qid-x{position:absolute;right:10px;top:10px;border:0;background:#eef3ee;border-radius:99px;width:34px;height:34px;font-size:20px;cursor:pointer;color:#1c2b20}' +
    '.qid-h{font-weight:800;font-size:19px;margin:0 40px 4px 0}.qid-s{margin:0 0 12px;color:#66756a;font-size:13.5px;line-height:1.45}' +
    '.qid-ph{display:flex;align-items:center;gap:12px;margin-bottom:12px}.qid-av{width:64px;height:64px;border-radius:50%;background:#e8f5e9;border:2px dashed #9ccc9f;display:grid;place-items:center;font-size:26px;overflow:hidden;flex:none;cursor:pointer;padding:0}.qid-av img{width:100%;height:100%;object-fit:cover;display:block}' +
    '.qid-ph small{display:block;color:#66756a;font-size:12px;line-height:1.35}.qid-ph b{font-size:14px}.qid-mini{border:0;background:none;color:#14692c;font-weight:700;font-size:13px;text-decoration:underline;cursor:pointer;padding:2px 6px 2px 0}' +
    '.qid-f{display:flex;flex-direction:column;gap:4px;margin-bottom:10px}.qid-f label{font-size:13px;font-weight:600}.qid-f input{width:100%;font-size:16px;border:1.5px solid #cdd7cc;border-radius:12px;padding:11px 12px;background:#fff;color:#1c2b20}' +
    '.qid-f input.pin{letter-spacing:6px;text-align:center;font-size:20px}.qid-f input.bad{border-color:#d93025}.qid-pins{display:grid;grid-template-columns:1fr 1fr;gap:10px}' +
    '.qid-btn{width:100%;border:0;background:#1e8e3e;color:#fff;font-weight:800;font-size:16px;padding:13px;border-radius:14px;cursor:pointer;margin-top:4px}.qid-btn:disabled{opacity:.6}' +
    '.qid-err{color:#d93025;font-size:13px;min-height:18px;margin-top:6px;font-weight:600}.qid-links{display:flex;flex-direction:column;align-items:flex-start;gap:4px;margin-top:10px}' +
    '.qid-link{border:0;background:none;color:#14692c;font-weight:700;font-size:13.5px;text-decoration:underline;cursor:pointer;padding:3px 0;text-align:left}a.qid-link{display:inline-block}';

  /* Draws the form into el. o: { rpc(fn, params), lang(), mode:'create'|'login', onDone(r), onEmail(), whatsapp, note } */
  Q.mount = function (el, o) {
    var mode = o.mode === 'login' ? 'login' : 'create', photo = '';
    function L() { return o.lang && o.lang() === 'en' ? 'en' : 'hi'; }
    function t(k, n) { return String((T[L()] || T.hi)[k] || k).replace('{n}', n); }
    function $(s) { return el.querySelector(s); }
    function err(m) { var e = $('#qidErr'); if (e) e.textContent = m || ''; }
    function draw() {
      var c = mode === 'create';
      el.setAttribute('data-noi18n', '');
      el.innerHTML = '<p class="qid-h">' + esc(c ? t('create') : t('login')) + '</p><p class="qid-s">' + esc(o.note || (c ? t('why') : t('whyLogin'))) + '</p><form id="qidF" novalidate>' +
        (c ? '<div class="qid-ph"><button type="button" class="qid-av" id="qidAv" aria-label="' + esc(t('photo')) + '">' + (photo ? '<img alt="" src="' + esc(photo) + '">' : '📷') + '</button><div><b>' + esc(t('photo')) + '</b><small id="qidPh">' + esc(photo ? t('size', (bytes(photo) / 1024).toFixed(1)) : t('photoHint')) + '</small>' +
          '<button type="button" class="qid-mini" id="qidPick">' + esc(photo ? t('change') : '＋') + '</button>' + (photo ? '<button type="button" class="qid-mini" id="qidDel">' + esc(t('remove')) + '</button>' : '') + '</div><input type="file" id="qidFile" accept="image/*" hidden></div>' +
          '<div class="qid-f"><label for="qidName">' + esc(t('name')) + '</label><input id="qidName" maxlength="80" autocomplete="name"></div>' : '') +
        '<div class="qid-f"><label for="qidMob">' + esc(t('mobile')) + '</label><input id="qidMob" type="tel" inputmode="numeric" maxlength="14" autocomplete="tel"></div>' +
        (c ? '<div class="qid-pins"><div class="qid-f"><label for="qidP1">' + esc(t('pin')) + '</label><input class="pin" id="qidP1" type="password" inputmode="numeric" maxlength="4" autocomplete="new-password"></div><div class="qid-f"><label for="qidP2">' + esc(t('pin2')) + '</label><input class="pin" id="qidP2" type="password" inputmode="numeric" maxlength="4" autocomplete="off"></div></div>'
          : '<div class="qid-f"><label for="qidP1">PIN</label><input class="pin" id="qidP1" type="password" inputmode="numeric" maxlength="4" autocomplete="current-password"></div>') +
        '<button class="qid-btn" type="submit" id="qidGo">' + esc(c ? t('btnCreate') : t('btnLogin')) + '</button><div class="qid-err" id="qidErr" role="alert"></div></form><div class="qid-links">' +
        '<button type="button" class="qid-link" id="qidSw">' + esc(c ? t('haveId') : '＋ ' + t('create')) + '</button>' +
        (!c && o.whatsapp ? '<a class="qid-link" target="_blank" rel="noopener" href="' + esc(o.whatsapp) + '">' + esc(t('forgot')) + '</a>' : '') +
        (o.onEmail ? '<button type="button" class="qid-link" id="qidEm">' + esc(t('email')) + '</button>' : '') + '</div>';
      wire();
    }
    function digits(i, n) { i.addEventListener('input', function () { i.value = i.value.replace(/\D/g, '').slice(0, n); i.classList.remove('bad'); }); }
    function wire() {
      var c = mode === 'create', mob = $('#qidMob'), p1 = $('#qidP1'), p2 = $('#qidP2');
      digits(p1, 4); if (p2) digits(p2, 4);
      mob.addEventListener('input', function () { mob.value = mob.value.replace(/[^\d+\s-]/g, ''); mob.classList.remove('bad'); });
      if (o.mobile) mob.value = o.mobile;
      $('#qidSw').onclick = function () { mode = c ? 'login' : 'create'; var m = mob.value; draw(); $('#qidMob').value = m; };
      var em = $('#qidEm'); if (em) em.onclick = function () { o.onEmail(); };
      if (c) {
        var f = $('#qidFile');
        $('#qidAv').onclick = $('#qidPick').onclick = function () { f.click(); };
        var dl = $('#qidDel'); if (dl) dl.onclick = function () { photo = ''; var n = $('#qidName').value, m = mob.value; draw(); $('#qidName').value = n; $('#qidMob').value = m; };
        f.onchange = function () {
          var file = f.files && f.files[0]; if (!file) return; err('');
          Q.compress(file).then(function (d) { photo = d; var n = $('#qidName').value, m = mob.value; draw(); $('#qidName').value = n; $('#qidMob').value = m; }, function () { err(t('photoBad')); });
        };
        $('#qidName').focus && window.innerWidth > 700 && $('#qidName').focus();
      }
      $('#qidF').onsubmit = async function (e) {
        e.preventDefault(); err('');
        var nm = c ? $('#qidName').value.trim() : '', m = mob.value.replace(/\D/g, '').replace(/^91(?=\d{10}$)/, '').replace(/^0(?=\d{10}$)/, '');
        [mob, p1, p2, c && $('#qidName')].forEach(function (x) { if (x) x.classList.remove('bad'); });
        if (c && nm.length < 2) { $('#qidName').classList.add('bad'); return err(t('needName')); }
        if (!/^[6-9]\d{9}$/.test(m)) { mob.classList.add('bad'); return err(t('needMob')); }
        if (!/^\d{4}$/.test(p1.value)) { p1.classList.add('bad'); return err(t('needPin')); }
        if (c && p1.value !== p2.value) { p2.classList.add('bad'); return err(t('pinMis')); }
        var b = $('#qidGo'), lbl = b.innerHTML; b.disabled = true; b.textContent = '…';
        try {
          var body = { mobile: m, pin: p1.value, device: dev(), dev_name: devName() };
          if (c) { body.name = nm; if (photo) body.avatar = photo; }
          var r = await o.rpc(c ? 'sp_cust_signup' : 'sp_cust_login', body);
          if (r && r.error) throw new Error(r.error);
          if (!r || !r.token) throw new Error(t('off'));
          if (!r.name) r.name = nm; r.created = c; o.onDone(r);
        } catch (x) {
          b.disabled = false; b.innerHTML = lbl; var msg = (x && x.message) || '';
          if (/Could not find|PGRST202|schema cache|404/i.test(msg)) msg = t('off');
          err(msg); if (!c) p1.value = '';
        }
      };
    }
    draw();
    return { setMode: function (m) { mode = m; draw(); } };
  };

  /* Pop-up version. Closes itself after a successful login. */
  Q.open = function (o) {
    if (document.getElementById('qidOv')) return;
    if (!document.getElementById('qidCss')) { var s = document.createElement('style'); s.id = 'qidCss'; s.textContent = CSS; document.head.appendChild(s); }
    var ov = document.createElement('div'); ov.className = 'qid-ov'; ov.id = 'qidOv';
    ov.innerHTML = '<div class="qid-box" role="dialog" aria-modal="true"><button type="button" class="qid-x" aria-label="Close">×</button><div id="qidBody"></div></div>';
    document.body.appendChild(ov); document.documentElement.style.overflow = 'hidden';
    function close() { ov.remove(); document.documentElement.style.overflow = ''; }
    ov.querySelector('.qid-x').onclick = close; ov.addEventListener('click', function (e) { if (e.target === ov) close(); });
    var oo = Object.assign({}, o, { onDone: function (r) { close(); o.onDone && o.onDone(r); }, onEmail: o.onEmail ? function () { close(); o.onEmail(); } : null });
    Q.mount(ov.querySelector('#qidBody'), oo);
    return close;
  };
  Q.css = CSS;
  Q.inject = function () { if (!document.getElementById('qidCss')) { var s = document.createElement('style'); s.id = 'qidCss'; s.textContent = CSS; document.head.appendChild(s); } };
})();
