/* Sunpowers — shared login screens: Email OTP → PIN, security questions, e-mail reset link.
   Used by CRM, Online Store (customers) and Store Admin.  No libraries; talks to Supabase RPCs (crm_auth_*). */
(function () {
  'use strict';
  var L = {
    hn: { login: 'Login', idLabel: 'Mobile / Email / Username', idStore: 'Mobile ya Email', next: 'Aage badhein', otpTitle: 'Email OTP daalein', otpSent: 'OTP bheja gaya:', verify: 'Verify karein',
      resend: 'OTP dobara bhejein', resendIn: 'Dobara bhejein ({s}s)', backup: 'Primary email nahi khul raha? Backup email par bhejein', master: 'Email nahi aa raha? Master password se', masterTitle: 'Master password', masterHint: 'Emergency login', pinTitle: 'PIN daalein',
      hello: 'Namaste', pinOf: '{n} ank ka PIN', forgot: 'PIN bhool gaye?', other: 'Doosri ID se login', setTitle: 'Apna PIN banayein', setHint: 'Agli baar sirf ye PIN lagega. Kisi ko na batayein.', newPin: 'Naya PIN ({n} ank)', pin2: 'PIN dobara', save: 'Save karein',
      qTitle: 'Security sawal (PIN bhoolne par kaam aayenge)', q1: 'Sawal 1', q2: 'Sawal 2', ans: 'Jawab', choose: '— chunein —', fTitle: 'PIN bhool gaye', fHint: 'Sawalon ke sahi jawab dein aur naya PIN banayein.',
      linkSent: 'Email par link bhej diya', linkHint: 'Email kholkar "Naya PIN banayein" dabayein. Link 15 minute tak chalega.', backLogin: '← Login par wapas', regTitle: 'Nayi ID banayein', name: 'Poora naam', mobile: 'Mobile', email: 'Email (OTP isi par aayega)', role: 'Main hoon',
      register: 'Nayi ID banayein', regBtn: 'ID banayein', pending: 'ID ban gayi ✔', pendingHint: 'Admin verify karega, uske baad isi phone par sirf PIN se login hoga.', resetTitle: 'Naya PIN banayein', mis: 'Dono PIN same nahi hain', pinLen: 'PIN {n} ank ka hona chahiye', need: 'Laal wale khaane bharein',
      qSame: 'Dono sawal alag chunein', mobBad: 'Sahi 10 ank ka mobile likhein', emBad: 'Sahi email likhein', welcome: 'Swagat hai', setQ: 'Security sawal set karein', locked: 'PIN lock hai — naya PIN banayein', passTitle: 'Password daalein', password: 'Password', newPass: 'Naya password (kam se kam 8 akshar)', pass2: 'Password dobara', passForgot: 'Password bhool gaye?', passMis: 'Dono password same nahi hain', passLen: 'Password kam se kam 8 akshar ka ho', passFTitle: 'Naya password banayein' },
    hi: { login: 'लॉगिन', idLabel: 'मोबाइल / ईमेल', idStore: 'मोबाइल या ईमेल', next: 'आगे बढ़ें', otpTitle: 'ईमेल OTP डालें', otpSent: 'OTP भेजा गया:', verify: 'वेरिफ़ाई करें', resend: 'OTP दोबारा भेजें', resendIn: 'दोबारा भेजें ({s}s)',
      backup: 'मुख्य ईमेल नहीं खुल रहा? बैकअप ईमेल पर भेजें', master: 'ईमेल नहीं आ रहा? मास्टर पासवर्ड से', masterTitle: 'मास्टर पासवर्ड', masterHint: 'इमरजेंसी लॉगिन', pinTitle: 'PIN डालें', hello: 'नमस्ते', pinOf: '{n} अंकों का PIN', forgot: 'PIN भूल गए?', other: 'दूसरी ID से लॉगिन',
      setTitle: 'अपना PIN बनाएँ', setHint: 'अगली बार सिर्फ़ यही PIN लगेगा। किसी को न बताएँ।', newPin: 'नया PIN ({n} अंक)', pin2: 'PIN दोबारा', save: 'सेव करें', qTitle: 'सुरक्षा सवाल (PIN भूलने पर काम आएँगे)', q1: 'सवाल 1', q2: 'सवाल 2', ans: 'जवाब', choose: '— चुनें —',
      fTitle: 'PIN भूल गए', fHint: 'सवालों के सही जवाब दें और नया PIN बनाएँ।', linkSent: 'ईमेल पर लिंक भेज दिया', linkHint: 'ईमेल खोलकर "Naya PIN banayein" दबाएँ। लिंक 15 मिनट तक चलेगा।', backLogin: '← लॉगिन पर वापस',
      regTitle: 'नई ID बनाएँ', name: 'पूरा नाम', mobile: 'मोबाइल', email: 'ईमेल (OTP इसी पर आएगा)', role: 'मैं हूँ', register: 'नई ID बनाएँ', regBtn: 'ID बनाएँ', pending: 'ID बन गई ✔', pendingHint: 'Admin वेरिफ़ाई करेगा, फिर सिर्फ़ PIN से लॉगिन होगा।', resetTitle: 'नया PIN बनाएँ',
      mis: 'दोनों PIN एक जैसे नहीं हैं', pinLen: 'PIN {n} अंकों का होना चाहिए', need: 'लाल वाले खाने भरें', qSame: 'दोनों सवाल अलग चुनें', mobBad: 'सही 10 अंकों का मोबाइल लिखें', emBad: 'सही ईमेल लिखें', welcome: 'स्वागत है', setQ: 'सुरक्षा सवाल सेट करें', locked: 'PIN लॉक है — नया PIN बनाएँ', passTitle: 'पासवर्ड डालें', password: 'पासवर्ड', newPass: 'नया पासवर्ड (कम से कम 8 अक्षर)', pass2: 'पासवर्ड दोबारा', passForgot: 'पासवर्ड भूल गए?', passMis: 'दोनों पासवर्ड एक जैसे नहीं हैं', passLen: 'पासवर्ड कम से कम 8 अक्षर का हो', passFTitle: 'नया पासवर्ड बनाएँ' },
    en: { login: 'Login', idLabel: 'Mobile / Email', idStore: 'Mobile or Email', next: 'Continue', otpTitle: 'Enter email OTP', otpSent: 'OTP sent to', verify: 'Verify', resend: 'Resend OTP', resendIn: 'Resend ({s}s)',
      backup: 'Can\'t open the main email? Send to backup email', master: 'No email? Use master password', masterTitle: 'Master password', masterHint: 'Emergency login', pinTitle: 'Enter PIN', hello: 'Hello', pinOf: '{n}-digit PIN', forgot: 'Forgot PIN?', other: 'Use another ID',
      setTitle: 'Create your PIN', setHint: 'Next time you only need this PIN. Never share it.', newPin: 'New PIN ({n} digits)', pin2: 'PIN again', save: 'Save', qTitle: 'Security questions (to recover your PIN)', q1: 'Question 1', q2: 'Question 2', ans: 'Answer', choose: '— choose —',
      fTitle: 'Forgot PIN', fHint: 'Answer your questions and create a new PIN.', linkSent: 'Link sent to your email', linkHint: 'Open the email and tap "Naya PIN banayein". The link works for 15 minutes.', backLogin: '← Back to login',
      regTitle: 'Create account', name: 'Full name', mobile: 'Mobile', email: 'Email (OTP comes here)', role: 'I am a', register: 'Create account', regBtn: 'Create account', pending: 'Account created ✔', pendingHint: 'After Admin approval you can log in with your PIN.', resetTitle: 'Create a new PIN',
      mis: 'PINs do not match', pinLen: 'PIN must be {n} digits', need: 'Fill the red boxes', qSame: 'Choose two different questions', mobBad: 'Enter a valid 10-digit mobile', emBad: 'Enter a valid email', welcome: 'Welcome', setQ: 'Set security questions', locked: 'PIN locked — create a new PIN', passTitle: 'Enter password', password: 'Password', newPass: 'New password (min 8 characters)', pass2: 'Password again', passForgot: 'Forgot password?', passMis: 'Passwords do not match', passLen: 'Password must be at least 8 characters', passFTitle: 'Create a new password' }
  };
  var QS = {
    hn: ['Aapke pehle school ka naam?', 'Aapka janm sthan (shahar/gaon)?', 'Maa ka pehla naam?', 'Pehli gaadi/bike ka number ya naam?', 'Bachpan ke dost ka naam?', 'Pasandida khana?'],
    hi: ['आपके पहले स्कूल का नाम?', 'आपका जन्म स्थान (शहर/गाँव)?', 'माँ का पहला नाम?', 'पहली गाड़ी/बाइक का नाम या नंबर?', 'बचपन के दोस्त का नाम?', 'पसंदीदा खाना?'],
    en: ['Name of your first school?', 'Your birthplace (city/village)?', 'Your mother\'s first name?', 'Name or number of your first vehicle?', 'Name of a childhood friend?', 'Your favourite food?']
  };
  var CSS = '.spa{font-family:inherit;color:#14231a;width:100%;max-width:400px;margin:0 auto}.spa *{box-sizing:border-box}.spa h2{font-size:24px;font-weight:800;margin:0 0 6px;line-height:1.2}.spa .spa-sub{color:#5f6f64;font-size:14.5px;margin:0 0 16px}' +
    '.spa label{display:block;font-size:13px;font-weight:700;margin:12px 0 5px;color:#2b3d31}.spa input,.spa select{width:100%;min-height:46px;border:1.5px solid #ccd9ca;border-radius:12px;padding:10px 13px;font:inherit;font-size:16px;background:#fff;color:#14231a;outline:none}' +
    '.spa input:focus,.spa select:focus{border-color:#1e8e3e;box-shadow:0 0 0 4px rgba(30,142,62,.12)}.spa input.bad,.spa select.bad{border-color:#c8372d}.spa .spa-code{text-align:center;font-size:28px;letter-spacing:.5em;font-weight:800;padding-left:.5em;font-variant-numeric:tabular-nums}' +
    '.spa .spa-btn{display:flex;width:100%;align-items:center;justify-content:center;gap:8px;min-height:48px;margin-top:16px;border:0;border-radius:12px;background:#1e8e3e;color:#fff;font:inherit;font-weight:800;font-size:16px;cursor:pointer}.spa .spa-btn:hover{background:#15702f}.spa .spa-btn[disabled]{opacity:.6;pointer-events:none}' +
    '.spa .spa-link{background:none;border:0;color:#15702f;font:inherit;font-weight:700;font-size:14px;cursor:pointer;padding:8px 0;text-align:left}.spa .spa-links{display:flex;flex-direction:column;gap:2px;margin-top:10px}.spa .spa-err{color:#c8372d;font-weight:600;font-size:14px;margin-top:10px;min-height:1px}' +
    '.spa .spa-ok{background:#e7f3e9;border:1px solid #d3e9d7;color:#0b2e1f;border-radius:12px;padding:12px 14px;font-size:14.5px;margin-top:10px}.spa .spa-who{display:flex;align-items:center;gap:12px;background:#f4f7f2;border-radius:14px;padding:12px;margin-bottom:6px}.spa .spa-av{width:44px;height:44px;border-radius:12px;background:#1e8e3e;color:#fff;font-weight:800;font-size:18px;display:flex;align-items:center;justify-content:center;flex:none}' +
    '.spa .spa-roles{display:grid;grid-template-columns:1fr 1fr;gap:8px}.spa .spa-roles button{min-height:44px;border:1.5px solid #ccd9ca;border-radius:12px;background:#fff;font:inherit;font-weight:700;color:#5f6f64;cursor:pointer}.spa .spa-roles button.on{border-color:#1e8e3e;background:#e7f3e9;color:#0b2e1f}' +
    '.spa .spa-sec{font-size:12px;font-weight:800;letter-spacing:.08em;text-transform:uppercase;color:#15702f;margin:18px 0 0}.spa .spa-g2{display:grid;grid-template-columns:1fr 1fr;gap:0 10px}.spa .spa-logo{display:block;width:64px;height:64px;border-radius:16px;margin:0 0 14px}';
  function esc(v) { return String(v == null ? '' : v).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function rnd() { var a = new Uint8Array(20); (window.crypto || window.msCrypto).getRandomValues(a); return Array.prototype.map.call(a, function (x) { return ('0' + x.toString(16)).slice(-2); }).join(''); }
  function ls(k, v) { try { if (v === undefined) return JSON.parse(localStorage.getItem(k) || 'null'); if (v === null) localStorage.removeItem(k); else localStorage.setItem(k, JSON.stringify(v)); } catch (e) { return null; } }
  function device(app) { var k = 'spa_dev_' + app, d = ls(k); if (!d || d.length < 20) { d = rnd(); ls(k, d); } return d; }
  function devName() { var u = navigator.userAgent || '', os = /Android/i.test(u) ? 'Android' : /iPhone|iPad/i.test(u) ? 'iPhone' : /Windows/i.test(u) ? 'Windows' : /Mac/i.test(u) ? 'Mac' : /Linux/i.test(u) ? 'Linux' : 'Device', br = /Edg\//.test(u) ? 'Edge' : /OPR\//.test(u) ? 'Opera' : /Chrome\//.test(u) ? 'Chrome' : /Firefox\//.test(u) ? 'Firefox' : /Safari\//.test(u) ? 'Safari' : 'Browser'; return os + ' · ' + br; }
  function mob(v) { var d = String(v || '').replace(/\D/g, ''); if (d.length === 12 && d.indexOf('91') === 0) d = d.slice(2); if (d.length === 11 && d[0] === '0') d = d.slice(1); return d; }
  function resetToken() { try { var t = new URLSearchParams(location.search).get('reset'); return t && /^[0-9a-f]{48}$/.test(t) ? t : ''; } catch (e) { return ''; } }
  function clearReset() { try { var u = new URL(location.href); u.searchParams.delete('reset'); history.replaceState(history.state, '', u.pathname + (u.search || '') + u.hash); } catch (e) {} }

  function mount(el, o) {
    var app = o.app, dev = device(app), st = { id: o.fixedId || '', name: '', len: app === 'admin' ? 6 : 4 }, timer = null;
    if (!document.getElementById('spa-css')) { var s = document.createElement('style'); s.id = 'spa-css'; s.textContent = CSS; document.head.appendChild(s); }
    function cur() { return window.SPI18N && !SPI18N.off ? SPI18N.lang : o.lang; }
    function t(k, n) { var T = L[cur()] || L[o.lang] || L.hn; return String(T[k] || L.en[k] || k).replace('{n}', n).replace('{s}', n); }
    async function call(fn, p) { var r = await o.rpc(fn, Object.assign({ app: app, id: st.id, device: dev, dev_name: devName() }, p || {})); if (r && r.error) throw new Error(r.error); return r; }
    // Emergency login button: sunpowers.in (live domains) par nahi dikhega, baaki sab (preview/vercel/localhost) par dikhega.
    function isStagingHost() { var h = location.hostname; return ['sunpowers.in','www.sunpowers.in','store.sunpowers.in','admin.sunpowers.in','crm.sunpowers.in'].indexOf(h) === -1; }
    function head(title, sub) { return (o.logo ? '<img class="spa-logo" src="' + esc(o.logo) + '" alt="">' : '') + '<h2>' + esc(title) + '</h2>' + (sub ? '<p class="spa-sub">' + sub + '</p>' : ''); }
    function show(html, after) { clearInterval(timer); el.innerHTML = '<div class="spa">' + html + '<div class="spa-err" id="spaErr" role="alert"></div></div>'; var f = el.querySelector('input:not([readonly]),select'); if (f && window.innerWidth > 700) setTimeout(function () { try { f.focus(); } catch (e) {} }, 30); if (after) after(); }
    function $(s) { return el.querySelector(s); }
    function err(m) { var e = $('#spaErr'); if (e) e.textContent = m || ''; }
    function busy(btn, on) { if (!btn) return; btn.disabled = on; if (on) { btn.dataset.l = btn.innerHTML; btn.innerHTML = '…'; } else if (btn.dataset.l) btn.innerHTML = btn.dataset.l; }
    async function run(btn, fn) { err(''); busy(btn, true); try { await fn(); } catch (e) { err(e.message || String(e)); busy(btn, false); } }
    function pinInput(id, len, auto) { return '<input id="' + id + '" class="spa-code" type="password" inputmode="numeric" pattern="[0-9]*" maxlength="' + len + '" autocomplete="off" aria-label="PIN">'; }
    function digits(inp, len, cb) { inp.addEventListener('input', function () { inp.value = inp.value.replace(/\D/g, '').slice(0, len); inp.classList.remove('bad'); if (cb && inp.value.length === len) cb(); }); }
    function qSelect(id) { return '<select id="' + id + '"><option value="">' + t('choose') + '</option>' + QS[cur() === 'en' ? 'en' : cur() === 'hi' ? 'hi' : 'hn'].map(function (q) { return '<option>' + esc(q) + '</option>'; }).join('') + '</select>'; }
    function qBlock() { return '<p class="spa-sec">' + t('qTitle') + '</p><label for="spaQ1">' + t('q1') + '</label>' + qSelect('spaQ1') + '<label for="spaA1">' + t('ans') + '</label><input id="spaA1" maxlength="60" autocomplete="off"><label for="spaQ2">' + t('q2') + '</label>' + qSelect('spaQ2') + '<label for="spaA2">' + t('ans') + '</label><input id="spaA2" maxlength="60" autocomplete="off">'; }
    function readQ() { var q = { q1: $('#spaQ1').value, a1: $('#spaA1').value.trim(), q2: $('#spaQ2').value, a2: $('#spaA2').value.trim() }; ['spaQ1', 'spaA1', 'spaQ2', 'spaA2'].forEach(function (i) { $('#' + i).classList.toggle('bad', !$('#' + i).value.trim()); }); if (!q.q1 || !q.q2 || !q.a1 || !q.a2) throw new Error(t('need')); if (q.q1 === q.q2) throw new Error(t('qSame')); return q; }
    function readPins(len) { var a = $('#spaP1').value, b = $('#spaP2').value; if (a.length !== len) { $('#spaP1').classList.add('bad'); throw new Error(t('pinLen', len)); } if (a !== b) { $('#spaP2').classList.add('bad'); throw new Error(t('mis')); } return a; }
    function remember() { if (!o.fixedId) ls('spa_last_' + app, { id: st.id, name: st.name }); }
    function done(r) { if (r.pending) return showPending(); remember(); clearReset(); o.onDone(r, st.id); }

    function showId() {
      var last = ls('spa_last_' + app);
      show(head(o.title || t('login'), o.sub || '') + '<form id="spaF"><label for="spaId">' + (app === 'store' ? t('idStore') : t('idLabel')) + '</label><input id="spaId" autocomplete="username" value="' + esc(st.id || (last && last.id) || '') + '" required><button class="spa-btn" type="submit">' + t('next') + ' →</button></form>' +
        '<div class="spa-links">' + (o.register ? '<button class="spa-link" type="button" id="spaReg">＋ ' + t('register') + '</button>' : '') + (isStagingHost() && app === 'admin' ? '<button class="spa-link" type="button" id="spaEm">Emergency login (staging)</button>' : '') + '</div>', function () {
        $('#spaF').onsubmit = function (e) { e.preventDefault(); var v = $('#spaId').value.trim(); if (!v) return $('#spaId').classList.add('bad'); st.id = /^[\d\s+()-]{10,}$/.test(v) ? mob(v) : v.toLowerCase(); go($('#spaF button')); };
        var rg = $('#spaReg'); if (rg) rg.onclick = showRegister; var em = $('#spaEm'); if (em) em.onclick = function () { st.id = 'admin'; showMaster(); };
      });
    }
    function go(btn, otpForce) { return run(btn, async function () { if (app === 'crm' && String(st.id || '').trim().toLowerCase() === 'admin') throw new Error('Ye ID nahi mili — mobile / email check karein'); var r = await call('crm_auth_start', otpForce ? { otp: true } : {}); st.name = r.name || st.name; st.len = r.pin_len || st.len; if (r.step === 'pin') showPin(null, r.locked); else if (r.step === 'password') showPass(); else showOtp(r); }); }
    function showOtp(r, purpose) {
      var wait = 40;
      show(head(t('otpTitle'), t('otpSent') + ' <b>' + esc(r.email || '') + '</b>') + '<form id="spaF"><input id="spaC" class="spa-code" inputmode="numeric" pattern="[0-9]*" maxlength="6" autocomplete="one-time-code" aria-label="OTP"><button class="spa-btn" type="submit">' + t('verify') + '</button></form>' +
        '<div class="spa-links"><button class="spa-link" type="button" id="spaRe" disabled>' + t('resendIn', wait) + '</button>' + (r.backup ? '<button class="spa-link" type="button" id="spaBk">' + t('backup') + '</button>' : '') + (app === 'admin' && st.id === 'admin' ? '<button class="spa-link" type="button" id="spaMa">' + t('master') + '</button>' : '') + '<button class="spa-link" type="button" id="spaBack">' + t('backLogin') + '</button></div>', function () {
        var c = $('#spaC'); digits(c, 6, function () { $('#spaF').requestSubmit ? $('#spaF').requestSubmit() : $('#spaF button').click(); });
        timer = setInterval(function () { wait--; var b = $('#spaRe'); if (!b) return clearInterval(timer); if (wait <= 0) { clearInterval(timer); b.disabled = false; b.textContent = t('resend'); } else b.textContent = t('resendIn', wait); }, 1000);
        $('#spaF').onsubmit = function (e) { e.preventDefault(); if (c.value.length !== 6) return c.classList.add('bad'); run($('#spaF button'), async function () { var x = await call('crm_auth_otp', { code: c.value }); st.len = x.pin_len || st.len; st.name = x.name || st.name; afterTicket(x, purpose); }); };
        $('#spaRe').onclick = function () { run($('#spaRe'), async function () { showOtp(await call('crm_auth_resend', {}), purpose); }); };
        var bk = $('#spaBk'); if (bk) bk.onclick = function () { run(bk, async function () { showOtp(await call('crm_auth_resend', { backup: true }), purpose); }); };
        var ma = $('#spaMa'); if (ma) ma.onclick = showMaster;
        $('#spaBack').onclick = showId;
      });
    }
    function afterTicket(x, purpose) {
      if (x.has_pin && x.locked) return showForgot();
      if (x.has_pin) return showPin(x.ticket);
      showSetPin(x.ticket, !x.has_q && purpose !== 'register');
    }
    function showMaster() {
      show(head(t('masterTitle'), t('masterHint')) + '<form id="spaF"><input id="spaM" type="password" autocomplete="current-password"><button class="spa-btn" type="submit">' + t('next') + '</button></form><div class="spa-links"><button class="spa-link" type="button" id="spaBack">' + t('backLogin') + '</button></div>', function () {
        $('#spaF').onsubmit = function (e) { e.preventDefault(); run($('#spaF button'), async function () { var x = await call('crm_auth_master', { password: $('#spaM').value }); afterTicket(x); }); };
        $('#spaBack').onclick = showId;
      });
    }
    function showPin(ticket, locked) {
      if (locked) return showForgot();
      var nm = st.name || (ls('spa_last_' + app) || {}).name || '';
      show(head(t('pinTitle'), '') + (nm ? '<div class="spa-who"><span class="spa-av">' + esc(nm.charAt(0).toUpperCase()) + '</span><div><b>' + t('hello') + ', ' + esc(nm) + '</b><div style="font-size:13px;color:#5f6f64">' + esc(st.id) + '</div></div></div>' : '') +
        '<form id="spaF">' + pinInput('spaPin', st.len) + '<button class="spa-btn" type="submit">🔐 ' + t('login') + '</button></form><div class="spa-links"><button class="spa-link" type="button" id="spaFg">' + t('forgot') + '</button>' + (o.fixedId ? '' : '<button class="spa-link" type="button" id="spaOt">' + t('other') + '</button>') + '</div>', function () {
        var p = $('#spaPin'); digits(p, st.len, function () { $('#spaF button').click(); });
        $('#spaF').onsubmit = function (e) { e.preventDefault(); if (p.value.length !== st.len) return p.classList.add('bad'); run($('#spaF button'), async function () { try { done(await call('crm_auth_pin', { pin: p.value, ticket: ticket || '' })); } catch (x) { p.value = ''; if (/lock/i.test(x.message)) setTimeout(showForgot, 1200); throw x; } }); };
        $('#spaFg').onclick = showForgot;
        var ot = $('#spaOt'); if (ot) ot.onclick = function () { ls('spa_last_' + app, null); st.id = ''; st.name = ''; showId(); };
      });
    }
    /* Marketing ID: password + security sawal (bina OTP) */
    function whoBox() { var nm = st.name || ''; return nm ? '<div class="spa-who"><span class="spa-av">' + esc(nm.charAt(0).toUpperCase()) + '</span><div><b>' + t('hello') + ', ' + esc(nm) + '</b><div style="font-size:13px;color:#5f6f64">' + esc(st.id) + '</div></div></div>' : ''; }
    function showPass() {
      show(head(t('passTitle'), '') + whoBox() + '<form id="spaF"><label for="spaPw">' + t('password') + '</label><input id="spaPw" type="password" autocomplete="current-password"><button class="spa-btn" type="submit">🔐 ' + t('login') + '</button></form><div class="spa-links"><button class="spa-link" type="button" id="spaFg">' + t('passForgot') + '</button><button class="spa-link" type="button" id="spaBack">' + t('backLogin') + '</button></div>', function () {
        $('#spaF').onsubmit = function (e) { e.preventDefault(); var pw = $('#spaPw'); if (!pw.value) return pw.classList.add('bad'); run($('#spaF button'), async function () { var x; try { x = await call('crm_auth_mkt_login', { password: pw.value }); } catch (er) { pw.value = ''; throw er; } if (x.need_q) return showMktQ(x.ticket); done(x); }); };
        $('#spaFg').onclick = showPassForgot; $('#spaBack').onclick = function () { ls('spa_last_' + app, null); st.id = ''; st.name = ''; showId(); };
      });
    }
    function showMktQ(ticket) {
      show(head(t('setQ'), '') + '<form id="spaF">' + qBlock() + '<button class="spa-btn" type="submit">✔ ' + t('save') + '</button></form>', function () {
        $('#spaF').onsubmit = function (e) { e.preventDefault(); run($('#spaF button'), async function () { done(await call('crm_auth_mkt_setq', Object.assign({ ticket: ticket }, readQ()))); }); };
      });
    }
    function showPassForgot() {
      show(head(t('passFTitle'), '') + '<div class="spa-sub">…</div>');
      run(null, async function () {
        var r = await call('crm_auth_mkt_forgot', {});
        show(head(t('passFTitle'), '') + '<form id="spaF"><label>' + esc(r.q1) + '</label><input id="spaA1" autocomplete="off"><label>' + esc(r.q2) + '</label><input id="spaA2" autocomplete="off"><label for="spaN1">' + t('newPass') + '</label><input id="spaN1" type="password" autocomplete="new-password"><label for="spaN2">' + t('pass2') + '</label><input id="spaN2" type="password" autocomplete="new-password">' +
          '<button class="spa-btn" type="submit">✔ ' + t('save') + '</button></form><div class="spa-links"><button class="spa-link" type="button" id="spaBack">' + t('backLogin') + '</button></div>', function () {
          $('#spaBack').onclick = showPass;
          $('#spaF').onsubmit = function (e) { e.preventDefault(); run($('#spaF button'), async function () { var a = $('#spaN1').value, b = $('#spaN2').value; if (a.length < 8) { $('#spaN1').classList.add('bad'); throw new Error(t('passLen')); } if (a !== b) { $('#spaN2').classList.add('bad'); throw new Error(t('passMis')); } done(await call('crm_auth_mkt_answer', { a1: $('#spaA1').value, a2: $('#spaA2').value, password: a })); }); };
        });
      }).then(function () { if ($('#spaErr') && $('#spaErr').textContent && !el.querySelector('form')) { var b = document.createElement('button'); b.className = 'spa-link'; b.textContent = t('backLogin'); b.onclick = showPass; el.querySelector('.spa').appendChild(b); } });
    }
    function showSetPin(ticket, needQ) {
      show(head(t('setTitle'), t('setHint')) + '<form id="spaF"><label for="spaP1">' + t('newPin', st.len) + '</label>' + pinInput('spaP1', st.len) + '<label for="spaP2">' + t('pin2') + '</label>' + pinInput('spaP2', st.len) + (needQ ? qBlock() : '') + '<button class="spa-btn" type="submit">✔ ' + t('save') + '</button></form>', function () {
        digits($('#spaP1'), st.len); digits($('#spaP2'), st.len);
        $('#spaF').onsubmit = function (e) { e.preventDefault(); run($('#spaF button'), async function () { var pin = readPins(st.len), q = needQ ? readQ() : {}; done(await call('crm_auth_setpin', Object.assign({ ticket: ticket, pin: pin }, q))); }); };
      });
    }
    function showLinkSent(r) {
      show(head(t('linkSent'), '') + '<div class="spa-ok">📧 <b>' + esc(r.email || '') + '</b><br>' + t('linkHint') + '</div><div class="spa-links">' + (st.id === 'admin' ? '<button class="spa-link" type="button" id="spaBk">' + t('backup') + '</button>' : '') + '<button class="spa-link" type="button" id="spaBack">' + t('backLogin') + '</button></div>', function () {
        $('#spaBack').onclick = showId; var bk = $('#spaBk'); if (bk) bk.onclick = function () { run(bk, async function () { showLinkSent(await call('crm_auth_forgot', { backup: true })); }); };
      });
    }
    function showForgot() {
      show(head(t('fTitle'), '') + '<div class="spa-sub">…</div>');
      run(null, async function () {
        var r = await call('crm_auth_forgot', {}); st.len = r.pin_len || st.len;
        if (r.link) return showLinkSent(r);
        show(head(t('fTitle'), t('fHint')) + '<form id="spaF"><label>' + esc(r.q1) + '</label><input id="spaA1" autocomplete="off"><label>' + esc(r.q2) + '</label><input id="spaA2" autocomplete="off"><label for="spaP1">' + t('newPin', st.len) + '</label>' + pinInput('spaP1', st.len) + '<label for="spaP2">' + t('pin2') + '</label>' + pinInput('spaP2', st.len) +
          '<button class="spa-btn" type="submit">✔ ' + t('save') + '</button></form><div class="spa-links"><button class="spa-link" type="button" id="spaBack">' + t('backLogin') + '</button></div>', function () {
          digits($('#spaP1'), st.len); digits($('#spaP2'), st.len); $('#spaBack').onclick = showId;
          $('#spaF').onsubmit = function (e) { e.preventDefault(); run($('#spaF button'), async function () { var pin = readPins(st.len), x = await call('crm_auth_answer', { a1: $('#spaA1').value, a2: $('#spaA2').value, pin: pin }); if (x.link) return showLinkSent(x); done(x); }); };
        });
      });
    }
    function showRegister() {
      var roles = Array.isArray(o.register) ? o.register : null, role = roles ? roles[0][0] : 'consumer';
      show(head(t('regTitle'), o.regSub || '') + (roles ? '<label>' + t('role') + '</label><div class="spa-roles">' + roles.map(function (r, i) { return '<button type="button" data-r="' + r[0] + '" class="' + (i ? '' : 'on') + '">' + esc(r[1]) + '</button>'; }).join('') + '</div>' : '') +
        '<form id="spaF"><label for="spaN">' + t('name') + '</label><input id="spaN" maxlength="80" autocomplete="name"><div class="spa-g2"><div><label for="spaMo">' + t('mobile') + '</label><input id="spaMo" inputmode="tel" maxlength="14" autocomplete="tel"></div><div><label for="spaE">' + t('email') + '</label><input id="spaE" type="email" autocomplete="email"></div></div>' + qBlock() +
        '<button class="spa-btn" type="submit">✔ ' + t('regBtn') + '</button></form><div class="spa-links"><button class="spa-link" type="button" id="spaBack">' + t('backLogin') + '</button></div>', function () {
        el.querySelectorAll('[data-r]').forEach(function (b) { b.onclick = function () { role = b.getAttribute('data-r'); el.querySelectorAll('[data-r]').forEach(function (x) { x.classList.toggle('on', x === b); }); }; });
        $('#spaBack').onclick = showId;
        $('#spaF').onsubmit = function (e) {
          e.preventDefault(); run($('#spaF button'), async function () {
            var n = $('#spaN').value.trim(), m = mob($('#spaMo').value), em = $('#spaE').value.trim().toLowerCase();
            $('#spaN').classList.toggle('bad', n.length < 2); if (n.length < 2) throw new Error(t('need'));
            if (!/^[6-9]\d{9}$/.test(m)) { $('#spaMo').classList.add('bad'); throw new Error(t('mobBad')); }
            if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(em)) { $('#spaE').classList.add('bad'); throw new Error(t('emBad')); }
            var q = readQ(), r = await o.rpc('crm_auth_register', Object.assign({ app: app, role: role, name: n, mobile: m, email: em }, q)); if (r && r.error) throw new Error(r.error);
            st.id = m; st.name = n; st.len = 4; showOtp(r, 'register');
          });
        };
      });
    }
    function showPending() { show(head(t('pending'), '') + '<div class="spa-ok">' + t('pendingHint') + '</div><div class="spa-links"><button class="spa-link" type="button" id="spaBack">' + t('backLogin') + '</button></div>', function () { remember(); $('#spaBack').onclick = showId; }); }
    function showReset(tok) {
      show(head(t('resetTitle'), '') + '<div class="spa-sub">…</div>');
      run(null, async function () {
        var r = await o.rpc('crm_auth_reset_info', { token: tok }); if (r && r.error) throw new Error(r.error);
        st.len = r.pin_len; st.id = r.id; st.name = r.name;
        show(head(t('resetTitle'), t('hello') + ', <b>' + esc(r.name) + '</b>') + '<form id="spaF"><label for="spaP1">' + t('newPin', st.len) + '</label>' + pinInput('spaP1', st.len) + '<label for="spaP2">' + t('pin2') + '</label>' + pinInput('spaP2', st.len) + '<button class="spa-btn" type="submit">✔ ' + t('save') + '</button></form>', function () {
          digits($('#spaP1'), st.len); digits($('#spaP2'), st.len);
          $('#spaF').onsubmit = function (e) { e.preventDefault(); run($('#spaF button'), async function () { var pin = readPins(st.len), x = await o.rpc('crm_auth_reset', { token: tok, pin: pin, device: dev, dev_name: devName() }); if (x && x.error) throw new Error(x.error); done(x); }); };
        });
      }).then(function () { if ($('#spaErr') && $('#spaErr').textContent) { var b = document.createElement('button'); b.className = 'spa-link'; b.textContent = t('backLogin'); b.onclick = function () { clearReset(); showId(); }; el.querySelector('.spa').appendChild(b); } });
    }
    var rt = resetToken();
    if (rt) showReset(rt);
    else if (o.fixedId) { st.id = o.fixedId; el.innerHTML = '<div class="spa"><p class="spa-sub">…</p></div>'; go(null); }
    else { var last = ls('spa_last_' + app); if (last && last.id && o.quickPin !== false) { st.id = last.id; st.name = last.name || ''; el.innerHTML = '<div class="spa"><p class="spa-sub">…</p></div>'; run(null, async function () { var r = await call('crm_auth_start', {}); st.len = r.pin_len || st.len; if (r.step === 'pin') showPin(null, r.locked); else if (r.step === 'password') showPass(); else showOtp(r); }).then(function () { if (!el.querySelector('form')) showId(); }); } else showId(); }
    return { showId: showId };
  }
  if (window.SPI18N) { var pairs = [], fx = function (v) { return v == null ? v : String(v).replace(/\{[ns]\}/g, '{0}'); }; Object.keys(L.en).forEach(function (k) { pairs.push([fx(L.en[k]), fx(L.hi[k]), fx(L.hn[k])]); }); QS.en.forEach(function (q, i) { pairs.push([q, QS.hi[i], QS.hn[i]]); }); SPI18N.add(pairs); }
  window.SPAuth = { mount: mount, device: device, resetToken: resetToken, L: L, QS: QS };
})();
