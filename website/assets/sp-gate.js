/* Sunpowers tools gate — Project Blueprint and Solar Error Detector need a login (email OTP).
   Used by the Website and the Online Store. The first use of an account is sent to the CRM as ONE lead; later use creates no new lead.
   Photos and videos never leave the phone. */
(function () {
  'use strict';
  var G = window.SPGate = { cfg: null };
  var T = {
    en: { title: 'Login to use this Sunpowers tool', sub: 'Free tool. A quick email OTP login is needed so our engineers can help you with your solar plan.', close: 'Close', fail: 'Login could not load. Please refresh the page.', off: 'Could not check your login. Check your internet and try again.' },
    hi: { title: 'यह Sunpowers टूल इस्तेमाल करने के लिए लॉगिन करें', sub: 'यह टूल फ़्री है। ईमेल OTP से छोटा-सा लॉगिन ज़रूरी है ताकि हमारे इंजीनियर आपकी सोलर योजना में मदद कर सकें।', close: 'बंद करें', fail: 'लॉगिन नहीं खुल पाया। पेज रीफ़्रेश करें।', off: 'आपका लॉगिन जाँचा नहीं जा सका। इंटरनेट देखकर दोबारा कोशिश करें।' }
  };
  function L() { return (G.cfg && G.cfg.lang && G.cfg.lang() === 'en') ? 'en' : (G.cfg && G.cfg.lang && G.cfg.lang() === 'hi' ? 'hi' : 'en'); }
  function t(k) { return T[L()][k]; }
  var CSS = '.spg-ov{position:fixed;inset:0;background:rgba(10,30,20,.62);z-index:99999;display:flex;align-items:flex-end;justify-content:center;padding:0}.spg-box{background:#fff;color:#14231a;width:100%;max-width:460px;max-height:92vh;overflow:auto;border-radius:18px 18px 0 0;padding:18px 16px 24px;position:relative}' +
    '@media(min-width:600px){.spg-ov{align-items:center;padding:16px}.spg-box{border-radius:18px}}.spg-x{position:absolute;right:10px;top:8px;border:0;background:#eef3ee;border-radius:99px;width:34px;height:34px;font-size:20px;cursor:pointer;color:#14231a}' +
    '.spg-h{font-weight:800;font-size:18px;margin:0 36px 4px 0}.spg-s{margin:0 0 12px;color:#4d5f54;font-size:14px}';
  /* One login for www + store: a cookie on .sunpowers.in carries the session token (localStorage stays the main copy). */
  G.cookie = {
    get: function () { try { var m = document.cookie.match(/(?:^|; )sp_ctok=([^;]*)/); return m && m[1] ? decodeURIComponent(m[1]) : null; } catch (e) { return null; } },
    set: function (v) { try { var d = /(^|\.)sunpowers\.in$/.test(location.hostname) ? '; Domain=.sunpowers.in' : ''; document.cookie = 'sp_ctok=' + (v ? encodeURIComponent(v) : '') + '; Path=/; Max-Age=' + (v ? 31536000 : 0) + d + '; SameSite=Lax' + (location.protocol === 'https:' ? '; Secure' : ''); } catch (e) {} }
  };
  G.init = function (o) { G.cfg = o; };
  /* Manual logout only: ends the server session and clears the token everywhere. */
  G.logout = async function () {
    var tk = G.token(); if (G.cfg) G.cfg.setToken(null);
    if (tk && G.cfg) { try { await G.cfg.rpc('crm_logout', { token: tk }); } catch (e) {} }
    try { document.dispatchEvent(new CustomEvent('sp-auth', { detail: { me: null } })); } catch (e) {}
  };
  G.active = function () { return !!G.cfg; };
  G.token = function () { return G.cfg ? G.cfg.getToken() : null; };
  G.me = async function () {
    var tk = G.token(); if (!tk) return { me: null };
    try { return { me: await G.cfg.rpc('crm_consumer_me', { token: tk }) }; }
    catch (e) { if (/expired|active nahi|Login/i.test((e && e.message) || '')) { G.cfg.setToken(null); return { me: null }; } return { me: null, offline: true }; }
  };
  function loadAuth(cb, bad) {
    if (window.SPAuth) return cb();
    var s = document.createElement('script'); s.src = G.cfg.authUrl || 'assets/auth.js'; s.onload = cb; s.onerror = bad; document.head.appendChild(s);
  }
  function loginBox(done) {
    if (G.cfg && G.cfg.loginUi) return G.cfg.loginUi(done); /* the Store App has its own quick "Create ID with PIN" login */
    if (!document.getElementById('spgCss')) { var st = document.createElement('style'); st.id = 'spgCss'; st.textContent = CSS; document.head.appendChild(st); }
    var ov = document.createElement('div'); ov.className = 'spg-ov'; ov.setAttribute('data-noi18n', '');
    ov.innerHTML = '<div class="spg-box" role="dialog" aria-modal="true"><button type="button" class="spg-x" aria-label="' + t('close') + '">×</button><p class="spg-h">' + t('title') + '</p><p class="spg-s">' + t('sub') + '</p><div id="spgBox"></div></div>';
    document.body.appendChild(ov); document.documentElement.style.overflow = 'hidden';
    function close() { ov.remove(); document.documentElement.style.overflow = ''; }
    ov.querySelector('.spg-x').onclick = close;
    ov.addEventListener('click', function (e) { if (e.target === ov) close(); });
    var box = ov.querySelector('#spgBox');
    loadAuth(function () {
      SPAuth.mount(box, { app: 'store', lang: L() === 'en' ? 'en' : 'hi', title: '', sub: '', register: true, rpc: G.cfg.rpc,
        onDone: function (r) { G.cfg.setToken(r.token); close(); try { document.dispatchEvent(new CustomEvent('sp-auth', { detail: { me: { name: r.name } } })); } catch (e) {} done(); } });
    }, function () { box.innerHTML = '<p>' + t('fail') + '</p>'; });
  }
  /* Run cb(me) only for a logged-in customer; otherwise show the login box first. */
  G.require = async function (tool, cb) {
    if (!G.cfg) return cb(null);
    var r = await G.me();
    if (r.me) return cb(r.me);
    if (r.offline) { if (G.cfg.toast) G.cfg.toast(t('off')); else alert(t('off')); return; }
    loginBox(async function () { var r2 = await G.me(); if (r2.me) cb(r2.me); });
  };
  /* Tell the CRM this account used a tool (the server creates a lead only on the account's first use). */
  G.log = function (tool, info) {
    if (!G.cfg || !G.token()) return;
    try { Promise.resolve(G.cfg.rpc('sp_tool_use', { token: G.token(), tool: tool, info: String(info || '').slice(0, 480) })).catch(function () {}); } catch (e) {}
  };
})();
