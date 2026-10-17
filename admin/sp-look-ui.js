/* Sunpowers — Look settings screen (colour theme of THIS panel + greeting banner for all panels).
   Used inside Admin (Website Admin / Store Admin / Admin) and CRM → Settings. Only an Admin can reach it.
   SPLOOKUI.mount(host, { app, lang:'hi'|'en', load(), save(cfg), users(), toast(msg,bad), label })                                   */
(function () {
  'use strict';
  var L = window.SPLOOK; if (!L || window.SPLOOKUI) return;
  var esc = L.esc;
  var TXT = {
    th: ['Colour theme', 'कलर थीम'], thSub: ['Pick one ready-made combo — backgrounds, buttons, text and borders all change together so everything stays matching.', 'एक रेडी कॉम्बो चुनिए — बैकग्राउंड, बटन, टेक्स्ट और बॉर्डर सब साथ में बदलते हैं, इसलिए पूरा पेज मैच करता रहता है।'],
    only: ['This colour applies only to', 'यह रंग सिर्फ़ इस पर लागू होगा'], custom: ['Custom', 'अपना रंग'], main: ['Main colour', 'मुख्य रंग'], acc: ['Accent (buttons / highlights)', 'एक्सेंट (बटन / हाइलाइट)'],
    gr: ['Greeting banner', 'ग्रीटिंग बैनर'], grSub: ['A message strip at the top (Diwali, Holi, offer…). Only you can edit it; visitors and users just see it where you tick.', 'सबसे ऊपर एक मैसेज पट्टी (दिवाली, होली, ऑफ़र…)। इसे सिर्फ़ आप बदल सकते हैं; बाकी लोग वहीं देखेंगे जहाँ आप टिक करेंगे।'],
    on: ['Show the greeting', 'ग्रीटिंग दिखाएँ'], text: ['Message', 'मैसेज'], ph: ['Happy Diwali! Sunpowers wishes you a bright year ✨', 'दीपावली की हार्दिक शुभकामनाएँ! सनपावर्स परिवार की ओर से ✨'],
    icon: ['Icon / live emoji', 'आइकन / लाइव इमोजी'], anim: ['Animation', 'एनिमेशन'], sty: ['Band style', 'बैनर स्टाइल'], from: ['Show from', 'कब से दिखाएँ'], to: ['Hide after', 'कब तक दिखाएँ'], dates: ['(optional — it hides itself after the last date)', '(ज़रूरी नहीं — आख़िरी तारीख़ के बाद अपने आप हट जाएगा)'],
    close: ['Allow visitors to close it (×)', '× से बंद करने दें'], where: ['Where to show', 'कहाँ दिखाना है'],
    wHome: ['Website — Home page', 'वेबसाइट — होम पेज'], wInner: ['Website — all other pages', 'वेबसाइट — बाकी सभी पेज'], wShop: ['Website — Shop page', 'वेबसाइट — शॉप पेज'], wStore: ['Online Store', 'ऑनलाइन स्टोर'], wAdmin: ['Admin panel (all pages)', 'एडमिन पैनल (सभी पेज)'],
    crm: ['CRM users', 'CRM यूज़र'], crmAll: ['All CRM users', 'CRM के सभी यूज़र'], crmNo: ['(user list not loaded)', '(यूज़र लिस्ट लोड नहीं हुई)'],
    prev: ['Preview', 'प्रीव्यू'], save: ['💾 Save', '💾 सेव करें'], reset: ['Back to default colours', 'डिफ़ॉल्ट रंग पर लौटें'], saved: ['✅ Saved — live within a minute', '✅ सेव हो गया — 1 मिनट में लाइव'], none: ['None', 'कोई नहीं'],
    wait: ['Loading…', 'लोड हो रहा है…'], err: ['Could not load settings. Run phase9-analytics-look.sql (included in MASTER-UPDATE.sql) in Supabase.', 'सेटिंग लोड नहीं हुई। Supabase में phase9-analytics-look.sql (MASTER-UPDATE.sql में शामिल) चलाएँ।'], pub: ['Not public: only an Admin can see this screen.', 'यह सेटिंग पब्लिक नहीं है: इसे सिर्फ़ Admin देख सकता है।']
  };
  var CSS = '.lk{display:grid;gap:14px}.lk .lk-card{background:#fff;border:1px solid var(--line,#dce5da);border-radius:16px;padding:16px}.lk h3{font-size:17px;margin:0 0 4px}.lk .lk-sub{color:var(--mut,var(--mute,#5a6b5f));font-size:13.5px;margin:0 0 12px}' +
    '.lk-tiles{display:grid;grid-template-columns:repeat(auto-fill,minmax(132px,1fr));gap:10px}.lk-tile{border:2px solid var(--line,#dce5da);border-radius:14px;background:#fff;padding:8px;text-align:left;cursor:pointer;display:flex;flex-direction:column;gap:7px;font:inherit}.lk-tile.on{border-color:var(--g,var(--leaf,#1e8e3e));box-shadow:0 0 0 3px rgba(30,142,62,.16)}' +
    '.lk-mock{border-radius:9px;overflow:hidden;border:1px solid rgba(0,0,0,.08);height:62px;display:flex;flex-direction:column}.lk-mock i{display:block;height:15px;background:var(--a)}.lk-mock s{flex:1;background:var(--b);padding:7px 8px;display:flex;gap:6px;align-items:flex-end;text-decoration:none}.lk-mock em{display:block;height:15px;width:36px;border-radius:7px;background:var(--c)}.lk-mock u{display:block;height:15px;width:22px;border-radius:7px;background:var(--d);text-decoration:none}' +
    '.lk-tile b{font-size:13px;line-height:1.2}.lk-row{display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin:8px 0}.lk-row label{font-size:13px;font-weight:700}.lk-row input[type=color]{width:46px;height:36px;border:1px solid var(--line,#dce5da);border-radius:8px;padding:2px;background:#fff}' +
    '.lk-f{display:flex;flex-direction:column;gap:5px;margin:10px 0}.lk-f>label{font-size:13px;font-weight:700}.lk-f input[type=text],.lk-f input[type=date],.lk-f select{border:1.5px solid var(--line,#dce5da);border-radius:10px;padding:9px 11px;font:inherit;background:#fff;width:100%;min-width:0}' +
    '.lk-icons{display:flex;flex-wrap:wrap;gap:6px}.lk-icons button{width:42px;height:42px;border-radius:10px;border:2px solid var(--line,#dce5da);background:#fff;font-size:22px;cursor:pointer}.lk-icons button.on{border-color:var(--g,var(--leaf,#1e8e3e));background:var(--g-l,var(--mint,#e8f5e9))}' +
    '.lk-chk{display:flex;align-items:center;gap:9px;padding:8px 4px;font-size:14px}.lk-chk input{width:19px;height:19px;accent-color:var(--g,var(--leaf,#1e8e3e));flex:none}.lk-ul{border:1px solid var(--line,#dce5da);border-radius:12px;padding:4px 10px;max-height:240px;overflow:auto;margin-top:4px}' +
    '.lk-prev{border-radius:12px;overflow:hidden;border:1px solid var(--line,#dce5da)}.lk-prev .sp-greet{position:relative}.lk-2{display:grid;grid-template-columns:1fr 1fr;gap:10px}@media(max-width:520px){.lk-2{grid-template-columns:1fr}}' +
    '.lk-bar{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.lk-bar .lk-b{border:0;border-radius:12px;padding:11px 18px;font:700 15px/1 inherit;cursor:pointer;background:var(--g,var(--leaf,#1e8e3e));color:#fff}.lk-bar .lk-b.o{background:#fff;color:var(--g-d,var(--leaf-d,#14692c));border:1.5px solid var(--g,var(--leaf,#1e8e3e))}.lk-lock{font-size:12.5px;color:var(--mut,var(--mute,#5a6b5f))}';
  function styleOnce() { if (document.getElementById('lk-css')) return; var s = document.createElement('style'); s.id = 'lk-css'; s.textContent = CSS; (document.head || document.documentElement).appendChild(s); }
  function defG() { return { on: false, text: '', icon: '🪔', anim: 'bounce', style: 'festive', from: '', to: '', close: true, id: '', t: { home: true, inner: true, shop: true, store: true, admin: false, crm: { all: false, users: {} } } }; }
  function clone(x) { return JSON.parse(JSON.stringify(x)); }

  function mount(host, o) {
    styleOnce(); L.styleOnce();
    var hi = o.lang === 'hi', T = function (k) { return TXT[k][hi ? 1 : 0]; }, S = { cfg: {}, th: { preset: 'green' }, g: defG(), users: null, busy: false };
    host.innerHTML = '<div class="lk-sub">' + esc(T('wait')) + '</div>';
    function tile(p) {
      var d = L.derive(p), on = (S.th.preset || 'green') === p.id;
      return '<button type="button" class="lk-tile' + (on ? ' on' : '') + '" data-pre="' + p.id + '" aria-pressed="' + on + '"><span class="lk-mock" style="--a:' + (p.base ? '#0b2e1f' : d.forest) + ';--b:' + (p.base ? '#f6f8f3' : d.paper) + ';--c:' + (p.base ? '#1e8e3e' : d.leaf) + ';--d:' + (p.base ? '#f4b740' : d.sun) + '"><i></i><s><em></em><u></u></s></span><b>' + esc(p.n[hi ? 1 : 0]) + '</b></button>';
    }
    function customTile() {
      var c = S.th.preset === 'custom', P = L.presetOf(S.th), d = L.derive(P);
      return '<div class="lk-tile' + (c ? ' on' : '') + '" data-pre="custom" role="button" tabindex="0"><span class="lk-mock" style="--a:' + d.forest + ';--b:' + d.paper + ';--c:' + d.leaf + ';--d:' + d.sun + '"><i></i><s><em></em><u></u></s></span><b>' + esc(T('custom')) + '</b></div>';
    }
    function crmBox() {
      var c = S.g.t.crm || (S.g.t.crm = { all: false, users: {} });
      return '<label class="lk-chk"><input type="checkbox" data-t="crm.all"' + (c.all ? ' checked' : '') + '> <b>' + esc(T('crmAll')) + '</b></label>' +
        '<div class="lk-ul">' + (S.users ? S.users.map(function (u) { return '<label class="lk-chk"><input type="checkbox" data-u="' + esc(u.id) + '"' + (c.users && c.users[String(u.id)] ? ' checked' : '') + '> <span>' + esc(u.name) + ' <small style="opacity:.65">· ' + esc(u.role) + '</small></span></label>'; }).join('') || '<div class="lk-lock">—</div>' : '<div class="lk-lock">' + esc(T('crmNo')) + '</div>') + '</div>';
    }
    function prevHtml() {
      var g = S.g; if (!String(g.text || '').trim()) return '<div class="lk-lock" style="padding:12px">' + esc(T('ph')) + '</div>';
      return '<div class="sp-greet sp-g-' + esc(g.style) + (o.app === 'store' || o.app === 'admin' ? ' g2' : '') + '">' + L.bannerHtml(Object.assign({}, g, { close: false }), o.app) + '</div>';
    }
    function draw() {
      var g = S.g, t = g.t, ck = function (v) { return v ? ' checked' : ''; };
      var tiles = L.PRESETS.map(tile).join('') + customTile();
      var cust = S.th.preset === 'custom' ? '<div class="lk-row"><label>' + esc(T('main')) + '</label><input type="color" data-c="primary" value="' + esc(S.th.primary || '#1e8e3e') + '"><label>' + esc(T('acc')) + '</label><input type="color" data-c="accent" value="' + esc(S.th.accent || '#f4b740') + '"></div>' : '';
      host.innerHTML = '<div class="lk">' +
        '<div class="lk-card"><h3>🎨 ' + esc(T('th')) + ' — ' + esc(o.label || o.app) + '</h3><p class="lk-sub">' + esc(T('thSub')) + '</p><div class="lk-tiles">' + tiles + '</div>' + cust +
        '<div class="lk-row"><span class="lk-lock">' + esc(T('only')) + ': <b>' + esc(o.label || o.app) + '</b></span><button type="button" class="lk-b o" data-reset style="margin-left:auto;border:1.5px solid var(--g,var(--leaf,#1e8e3e));border-radius:10px;padding:7px 12px;background:#fff;font:700 13px inherit;cursor:pointer">' + esc(T('reset')) + '</button></div></div>' +
        '<div class="lk-card"><h3>🎉 ' + esc(T('gr')) + '</h3><p class="lk-sub">' + esc(T('grSub')) + '</p>' +
        '<label class="lk-chk"><input type="checkbox" data-g="on"' + ck(g.on) + '> <b>' + esc(T('on')) + '</b></label>' +
        '<div class="lk-f"><label>' + esc(T('text')) + '</label><input type="text" data-g="text" maxlength="160" value="' + esc(g.text) + '" placeholder="' + esc(T('ph')) + '"></div>' +
        '<div class="lk-f"><label>' + esc(T('icon')) + '</label><div class="lk-icons"><button type="button" data-ic="" class="' + (!g.icon ? 'on' : '') + '" aria-label="' + esc(T('none')) + '" style="font-size:12px">' + esc(T('none')) + '</button>' + L.ICONS.map(function (e) { return '<button type="button" data-ic="' + e + '" class="' + (g.icon === e ? 'on' : '') + '"><span class="' + (g.icon === e ? 'sp-gi sp-a-' + esc(g.anim) : '') + '">' + e + '</span></button>'; }).join('') + '</div></div>' +
        '<div class="lk-2"><div class="lk-f"><label>' + esc(T('anim')) + '</label><select data-g="anim">' + L.ANIMS.map(function (a) { return '<option value="' + a[0] + '"' + (g.anim === a[0] ? ' selected' : '') + '>' + esc(a[hi ? 2 : 1]) + '</option>'; }).join('') + '</select></div>' +
        '<div class="lk-f"><label>' + esc(T('sty')) + '</label><select data-g="style">' + L.STYLES.map(function (a) { return '<option value="' + a[0] + '"' + (g.style === a[0] ? ' selected' : '') + '>' + esc(a[hi ? 2 : 1]) + '</option>'; }).join('') + '</select></div></div>' +
        '<div class="lk-2"><div class="lk-f"><label>' + esc(T('from')) + '</label><input type="date" data-g="from" value="' + esc(g.from) + '"></div><div class="lk-f"><label>' + esc(T('to')) + '</label><input type="date" data-g="to" value="' + esc(g.to) + '"></div></div><div class="lk-lock">' + esc(T('dates')) + '</div>' +
        '<label class="lk-chk"><input type="checkbox" data-g="close"' + ck(g.close !== false) + '> ' + esc(T('close')) + '</label>' +
        '<div class="lk-f"><label>' + esc(T('prev')) + '</label><div class="lk-prev" id="lkPrev">' + prevHtml() + '</div></div>' +
        '<div class="lk-f"><label>' + esc(T('where')) + '</label>' +
        [['home', 'wHome'], ['inner', 'wInner'], ['shop', 'wShop'], ['store', 'wStore'], ['admin', 'wAdmin']].map(function (r) { return '<label class="lk-chk"><input type="checkbox" data-t="' + r[0] + '"' + ck(t[r[0]]) + '> ' + esc(T(r[1])) + '</label>'; }).join('') +
        '<label style="font-size:13px;font-weight:700;margin-top:6px">' + esc(T('crm')) + '</label>' + crmBox() + '</div></div>' +
        '<div class="lk-bar"><button type="button" class="lk-b" data-save' + (S.busy ? ' disabled' : '') + '>' + esc(T('save')) + '</button><span class="lk-lock">🔒 ' + esc(T('pub')) + '</span></div></div>';
    }
    function livePrev() { var p = host.querySelector('#lkPrev'); if (p) p.innerHTML = prevHtml(); }
    function applyHere() { var tmp = { theme: {} }; tmp.theme[o.app] = S.th; L.apply(o.app, tmp); }

    host.addEventListener('click', function (e) {
      var b = e.target.closest('[data-pre]'); if (b) { var id = b.getAttribute('data-pre'); if (id === 'custom') { if (S.th.preset !== 'custom') S.th = { preset: 'custom', primary: S.th.primary || '#1e8e3e', accent: S.th.accent || '#f4b740' }; } else S.th = { preset: id }; draw(); if (o.livePanel) applyHere(); return; }
      if (e.target.closest('[data-reset]')) { S.th = { preset: 'green' }; draw(); if (o.livePanel) applyHere(); return; }
      var ic = e.target.closest('[data-ic]'); if (ic) { S.g.icon = ic.getAttribute('data-ic'); draw(); return; }
      if (e.target.closest('[data-save]')) save();
    });
    host.addEventListener('input', function (e) {
      var c = e.target.closest('[data-c]'); if (c) { S.th[c.getAttribute('data-c')] = c.value; if (o.livePanel) applyHere(); var tl = host.querySelector('[data-pre=custom] .lk-mock'); if (tl) { var d = L.derive(L.presetOf(S.th)); tl.style.cssText = '--a:' + d.forest + ';--b:' + d.paper + ';--c:' + d.leaf + ';--d:' + d.sun; } return; }
      var g = e.target.closest('input[data-g][type=text],input[data-g][type=date]'); if (g) { S.g[g.getAttribute('data-g')] = g.value; livePrev(); }
    });
    host.addEventListener('change', function (e) {
      var g = e.target.closest('[data-g]'); if (g && g.type === 'checkbox') { S.g[g.getAttribute('data-g')] = g.checked; return; }
      if (g && g.tagName === 'SELECT') { S.g[g.getAttribute('data-g')] = g.value; draw(); return; }
      var t = e.target.closest('[data-t]'); if (t) { var k = t.getAttribute('data-t'); if (k === 'crm.all') S.g.t.crm.all = t.checked; else S.g.t[k] = t.checked; return; }
      var u = e.target.closest('[data-u]'); if (u) { S.g.t.crm.users[u.getAttribute('data-u')] = u.checked; }
    });
    async function save() {
      if (S.busy) return; S.busy = true;
      try {
        var cur = await o.load(); if (!cur || typeof cur !== 'object') cur = {};
        cur.theme = cur.theme || {}; if ((S.th.preset || 'green') === 'green') delete cur.theme[o.app]; else cur.theme[o.app] = clone(S.th);
        var g = clone(S.g), old = cur.greet || {}; if (g.text !== old.text || g.on !== old.on || g.icon !== old.icon) g.id = String(Date.now());
        else g.id = old.id || String(Date.now());
        g.text = String(g.text || '').trim(); cur.greet = g;
        await o.save(cur); S.cfg = cur; L.setCur(cur); if (o.toast) o.toast(T('saved'));
      } catch (er) { if (o.toast) o.toast('❌ ' + (er && er.message || er), true); }
      S.busy = false;
    }
    (async function () {
      try {
        var cfg = await o.load(); S.cfg = cfg || {};
        S.th = clone((cfg && cfg.theme && cfg.theme[o.app]) || { preset: 'green' }); if (!S.th.preset) S.th.preset = 'green';
        S.g = Object.assign(defG(), clone((cfg && cfg.greet) || {})); S.g.t = Object.assign(defG().t, S.g.t || {}); S.g.t.crm = Object.assign({ all: false, users: {} }, S.g.t.crm || {}); S.g.t.crm.users = S.g.t.crm.users || {};
        try { S.users = o.users ? await o.users() : null; } catch (e) { S.users = null; }
        draw();
      } catch (er) { host.innerHTML = '<div class="lk-sub" style="color:#c8372d">' + esc(T('err')) + '</div>'; }
    })();
  }
  /* helper for the Admin panel: load / save / users through the admin session (token or password) */
  function adminIO(rpc, pass) {
    return {
      load: function () { return rpc('sp_get_cfg', {}); },
      save: function (cfg) { return rpc('sp_save_cfg', { p_pass: pass(), p_data: cfg }); },
      users: function () { return rpc('crm_users_list', { p: { token: pass() } }).then(function (l) { return (l || []).filter(function (u) { return u.status !== 'blocked'; }); }); }
    };
  }
  window.SPLOOKUI = { mount: mount, adminIO: adminIO };
})();
