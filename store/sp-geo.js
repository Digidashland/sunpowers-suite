/* Sunpowers — "Use my current location" (Round 64). Ek hi file: Store App, Web Shop, CRM teeno me wahi.
   - Browser/phone se location ki permission maangta hai (sirf button dabane par), phir latitude/longitude se pata nikalta hai
     (photon.komoot.io, na mile to nominatim.openstreetmap.org) aur pin, shahar, state, district, pata apne-aap bhar deta hai.
   - Button sirf wahan aata hai jahan pata / pin / shahar bharna hota hai (neeche DEFAULT RULES). Baaki jagah kuch nahi badalta.
   - Pata (address) wali box me pehle se likha ho to use nahi mitata; sirf khali ho tab bharta hai (makaan / flat no. customer khud jode).
   Public: SPGeo.locate() -> Promise<{lat,lon,pin,city,district,state,line}>, SPGeo.fill(map, data), SPGeo.msg(code), SPGeo.errCode */
(function () {
  'use strict';
  if (window.SPGeo) return;
  var G = window.SPGeo = { errCode: '' };
  var TX = {
    en: { btn: '📍 Use my current location', ing: 'Finding your location…', ok: 'Filled from your location — please check it and add house / flat number.',
      denied: 'Location is blocked. Allow location for this site (address-bar lock icon or phone Settings) and try again.', nosup: 'This browser / device cannot give location here (needs a secure https page). Please type it.',
      fail: 'Could not read the address from your location. Please type it.', tmo: 'Location took too long. Try again (GPS on / outdoors) or type it.', pinOnly: 'Pin code could not be found for this spot. Please type it.' },
    hi: { btn: '📍 मेरी मौजूदा लोकेशन इस्तेमाल करें', ing: 'आपकी लोकेशन देख रहे हैं…', ok: 'आपकी लोकेशन से भर दिया — कृपया जाँच लें और मकान / फ़्लैट नंबर जोड़ें।',
      denied: 'लोकेशन बंद है। इस साइट के लिए लोकेशन की अनुमति दें (एड्रेस-बार का ताला या फ़ोन Settings) और फिर कोशिश करें।', nosup: 'यहाँ इस ब्राउज़र / फ़ोन से लोकेशन नहीं मिल सकती (https पेज चाहिए)। कृपया ख़ुद लिखें।',
      fail: 'लोकेशन से पता नहीं पढ़ पाए। कृपया ख़ुद लिखें।', tmo: 'लोकेशन में बहुत समय लगा। दोबारा कोशिश करें (GPS चालू / खुले में) या ख़ुद लिखें।', pinOnly: 'इस जगह का पिन कोड नहीं मिला। कृपया ख़ुद लिखें।' },
    hg: { btn: '📍 Meri location se bharein', ing: 'Location dekh rahe hain…', ok: 'Location se bhar diya — jaanch lein aur makaan / flat number jodein.',
      denied: 'Location band hai. Is site ke liye location allow karein (address-bar ka taala ya phone Settings) phir dobara dabayein.', nosup: 'Is browser / phone se yahan location nahi mil sakti (https page chahiye). Khud likhein.',
      fail: 'Location se pata nahi padh paye. Khud likhein.', tmo: 'Location me der lagi. Dobara koshish karein (GPS on / khule me) ya khud likhein.', pinOnly: 'Is jagah ka pincode nahi mila. Khud likhein.' }
  };
  function lang() { if (window.CRM) return 'hg'; var l = window.SPI18N && window.SPI18N.lang; if (l === 'hi' || l === 'hg') return 'hi'; try { var s = localStorage.getItem('sp_lang'); if (s === 'hi') return 'hi'; } catch (e) {} return 'en'; }
  function tx(k) { return (TX[lang()] || TX.en)[k]; }
  G.msg = function (code) { return tx(code === 'denied' ? 'denied' : code === 'nosup' ? 'nosup' : code === 'tmo' ? 'tmo' : 'fail'); };

  function position() {
    return new Promise(function (res, rej) {
      if (!navigator.geolocation || window.isSecureContext === false) return rej('nosup');
      navigator.geolocation.getCurrentPosition(function (g) { res(g.coords); }, function (e) { rej(e && e.code === 1 ? 'denied' : e && e.code === 3 ? 'tmo' : 'fail'); }, { enableHighAccuracy: true, timeout: 14000, maximumAge: 60000 });
    });
  }
  function getJson(url) {
    return new Promise(function (res, rej) {
      var ctl = window.AbortController ? new AbortController() : null, to = setTimeout(function () { if (ctl) ctl.abort(); rej('fail'); }, 9000);
      fetch(url, ctl ? { signal: ctl.signal } : {}).then(function (r) { if (!r.ok) throw 0; return r.json(); }).then(function (d) { clearTimeout(to); res(d); }, function () { clearTimeout(to); rej('fail'); });
    });
  }
  function dig(s) { s = String(s || '').replace(/\D/g, ''); return /^[1-9]\d{5}$/.test(s) ? s : ''; }
  function join(a) { return a.filter(function (x) { return x && String(x).trim(); }).map(function (x) { return String(x).trim(); }).filter(function (x, i, arr) { return arr.indexOf(x) === i; }).join(', '); }
  function photon(c) {
    return getJson('https://photon.komoot.io/reverse?lang=en&lat=' + c.latitude + '&lon=' + c.longitude).then(function (d) {
      var f = d && d.features && d.features[0], p = f && f.properties; if (!p) throw 'fail';
      return { pin: dig(p.postcode), city: p.city || p.town || p.village || p.county || '', district: p.county || p.district || '', state: p.state || '', line: join([p.housenumber, p.street || p.name, p.locality || p.district]) };
    });
  }
  function nomi(c) {
    return getJson('https://nominatim.openstreetmap.org/reverse?format=jsonv2&addressdetails=1&accept-language=en&lat=' + c.latitude + '&lon=' + c.longitude).then(function (d) {
      var a = d && d.address; if (!a) throw 'fail';
      return { pin: dig(a.postcode), city: a.city || a.town || a.village || a.suburb || a.state_district || '', district: a.state_district || a.county || '', state: a.state || '', line: join([a.house_number, a.road, a.neighbourhood || a.suburb || a.hamlet]) };
    });
  }
  G.locate = function () {
    G.errCode = '';
    return position().then(function (c) {
      return photon(c).catch(function () { return null; }).then(function (r) {
        if (r && r.pin && r.city) return r;
        return nomi(c).catch(function () { return null; }).then(function (r2) {
          var m = r || r2; if (!m) throw 'fail';
          if (r && r2) { ['pin', 'city', 'district', 'state', 'line'].forEach(function (k) { if (!m[k]) m[k] = r2[k] || ''; }); }
          m.lat = c.latitude; m.lon = c.longitude; return m;
        });
      }).then(function (m) { m.lat = c.latitude; m.lon = c.longitude; return m; });
    }).catch(function (e) { G.errCode = typeof e === 'string' ? e : 'fail'; throw G.errCode; });
  };

  function fire(el) { ['input', 'change'].forEach(function (n) { try { el.dispatchEvent(new Event(n, { bubbles: true })); } catch (e) {} }); }
  function norm(s) { return String(s || '').toLowerCase().replace(/&/g, 'and').replace(/[^a-z0-9]/g, ''); }
  function pickOption(sel, want) {
    var w = norm(want).replace(/^nctof/, '').replace('orissa', 'odisha').replace('uttaranchal', 'uttarakhand'); if (!w) return false;
    var o = Array.prototype.slice.call(sel.options).filter(function (x) { var v = norm(x.value), t = norm(x.text); return (v && (v === w || w.indexOf(v) === 0 || v.indexOf(w) === 0)) || (t && (t === w || t.indexOf(w) === 0 || w.indexOf(t) === 0)); })[0];
    if (!o) return false; sel.value = o.value; return true;
  }
  function setVal(el, v) {
    if (!el || v == null || v === '') return false;
    if (el.tagName === 'SELECT') { var ok = pickOption(el, v); if (ok) fire(el); return ok; }
    el.value = v; fire(el); return true;
  }
  /* map = { pin, city, state, district, addr, stateX, districtX, country } — elements. State / district select ho to option chunta hai; na mile to "Other" + khud likhne wali box. */
  G.fill = function (map, d) {
    var got = [];
    if (map.country && map.country.tagName === 'SELECT') { if (pickOption(map.country, 'India')) fire(map.country); }
    if (map.state) {
      var ok = setVal(map.state, d.state);
      if (!ok && map.state.tagName === 'SELECT' && map.stateX && d.state) { var oth = Array.prototype.slice.call(map.state.options).filter(function (o) { return /other|__other/i.test(o.value + o.text); })[0]; if (oth) { map.state.value = oth.value; fire(map.state); map.stateX.value = d.state; fire(map.stateX); ok = true; } }
      if (ok) got.push('state');
    }
    if (map.district) {
      var ok2 = setVal(map.district, d.district);
      if (!ok2 && map.district.tagName === 'SELECT' && map.districtX && d.district) { var oth2 = Array.prototype.slice.call(map.district.options).filter(function (o) { return /other|__other/i.test(o.value + o.text); })[0]; if (oth2) { map.district.value = oth2.value; fire(map.district); map.districtX.value = d.district; fire(map.districtX); ok2 = true; } }
      if (!ok2 && d.city) ok2 = setVal(map.district, d.city);
      if (ok2) got.push('district');
    }
    if (map.city && setVal(map.city, d.city)) got.push('city');
    if (map.pin && setVal(map.pin, d.pin)) got.push('pin');
    if (map.addr && !String(map.addr.value || '').trim() && d.line && setVal(map.addr, d.line)) got.push('addr');
    return got;
  };

  var css = '.spg{margin:2px 0 8px;display:block}.spg .spg-b{display:inline-flex;align-items:center;gap:6px;min-height:36px;padding:6px 14px;border:1.5px solid #1e8e3e;border-radius:999px;background:#fff;color:#14683a;font:inherit;font-size:13px;font-weight:700;cursor:pointer;-webkit-tap-highlight-color:transparent}' +
    '.spg .spg-b:active{transform:scale(.97)}.spg .spg-b[disabled]{opacity:.65;cursor:default}.spg .spg-m{display:block;margin-top:6px;font-size:12.5px;line-height:1.45;color:#5b6b61}.spg .spg-m.ok{color:#14683a}.spg .spg-m.bad{color:#c0392b}.spg.full{grid-column:1/-1}';
  function ensureCss() { if (document.getElementById('spg-css')) return; var s = document.createElement('style'); s.id = 'spg-css'; s.textContent = css; (document.head || document.documentElement).appendChild(s); }

  /* button + status; mapFn() = elements ab (form dubara bane to taaza) */
  G.button = function (mapFn, opt) {
    ensureCss(); opt = opt || {};
    var w = document.createElement('div'); w.className = 'spg' + (opt.full ? ' full' : ''); w.setAttribute('data-noi18n', ''); w.setAttribute('data-geo-box', '');
    w.innerHTML = '<button type="button" class="spg-b"></button><small class="spg-m" aria-live="polite"></small>';
    var b = w.firstChild, m = w.lastChild;
    function label() { b.textContent = tx('btn'); } label();
    b.onclick = function () {
      b.disabled = true; b.textContent = tx('ing'); m.textContent = ''; m.className = 'spg-m';
      G.locate().then(function (d) {
        var got = G.fill(mapFn(), d);
        if (!got.length) { m.className = 'spg-m bad'; m.textContent = tx('fail'); }
        else if (mapFn().pin && got.indexOf('pin') < 0) { m.className = 'spg-m bad'; m.textContent = tx('pinOnly'); }
        else { m.className = 'spg-m ok'; m.textContent = '✓ ' + (opt.okOnly ? [d.city, d.state, d.pin].filter(Boolean).join(', ') : tx('ok')); }
      }, function (code) { m.className = 'spg-m bad'; m.textContent = G.msg(code); }).then(function () { b.disabled = false; label(); });
    };
    w._relabel = label;
    return w;
  };

  /* ---------- DEFAULT RULES: kis page me kahan button aata hai ---------- */
  function q(root, s) { return root.querySelector(s); }
  function holder(el) { return el.closest('.co-f,.fld,.field,.f') || el; }
  var RULES = [
    /* Checkout / Profile (Store App + Web Shop): pata + shahar + pin */
    { find: '#co-addr', map: function (a, r) { return { addr: a, city: q(r, '#co-city'), pin: q(r, '#co-pin') }; } },
    { find: '#pf-addr', map: function (a, r) { return { addr: a, city: q(r, '#pf-city'), pin: q(r, '#pf-pin') }; } },
    /* CRM: Country / State / District / Shahar / Pincode / Pata ka poora block */
    { find: '[data-addr]', crm: true },
    /* Sirf shahar wale form (enquiry, contact, site-visit popup, CRM lead): shahar ke neeche chhota button */
    { find: '#ef-city', one: true, map: function (a) { return { city: a }; } },
    { find: 'input[name="city"]', one: true, skip: '[data-addr],#coForm', map: function (a) { return { city: a }; } }
  ];
  function scan() {
    RULES.forEach(function (R) {
      Array.prototype.slice.call(document.querySelectorAll(R.find)).forEach(function (el) {
        if (el.getAttribute('data-geo') || (R.skip && el.closest(R.skip))) return;
        el.setAttribute('data-geo', '1');
        var root = el.closest('form') || document;
        if (R.crm) {
          var box = el, sc = function (n) { return box.querySelector('[data-ac="' + n + '"]'); };
          var w = G.button(function () { return { country: sc('country'), state: sc('state'), stateX: sc('state_x'), district: sc('district'), districtX: sc('district_x'), city: box.querySelector('[name$="city"]'), pin: box.querySelector('[name$="pincode"]'), addr: box.querySelector('[name$="address"]') }; }, { full: true });
          box.insertBefore(w, box.firstChild); return;
        }
        var wrap = G.button(function () { return R.map(el, root); }, { okOnly: !!R.one });
        var h = holder(el);
        var host0 = R.one ? (h === el ? el.parentNode : h) : h.parentNode; Array.prototype.forEach.call(host0.querySelectorAll(':scope > [data-geo-box]'), function (o) { o.remove(); });
        if (R.one) { /* shahar akela: usi field ke andar, neeche */ (h === el ? el.parentNode : h).appendChild(wrap); }
        else h.parentNode.insertBefore(wrap, h);
      });
    });
  }
  var tm = null; function later() { clearTimeout(tm); tm = setTimeout(scan, 120); }
  G.scan = scan;
  function start() { scan(); try { new MutationObserver(later).observe(document.body, { childList: true, subtree: true }); } catch (e) {} document.addEventListener('sp-lang', function () { Array.prototype.forEach.call(document.querySelectorAll('[data-geo-box]'), function (w) { if (w._relabel) w._relabel(); }); }); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
