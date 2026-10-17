/* =====================================================================
   sp-i18n.js — poori app ek hi bhasha me: English YA हिंदी (kabhi mix nahi)
   - Har app ke header me button: SPI18N.button()
   - Shabdkosh (dictionary): SPI18N.add([[english, hindi, ...purane roop (Hinglish / doosre)], ...])
       {0} {1} = number (apne aap), {s} = koi bhi naam / text
   - Nayi bhasha baad me: SPI18N.addLang('mr', 'मराठी', { 'English text': 'मराठी text', ... })
   - Jo element translate nahi karna: data-noi18n
   ===================================================================== */
(function () {
  'use strict';
  if (window.SPI18N) return;
  var LANGS = [{ code: 'en', label: 'Eng', short: 'EN' }, { code: 'hi', label: 'हिंदी', short: 'हिं' }, { code: 'hg', label: 'Hinglish', short: 'Hing' }];
  var KEY = 'sp_lang', ATTRS = ['placeholder', 'title', 'aria-label', 'alt'];
  var SKIP = { SCRIPT: 1, STYLE: 1, TEXTAREA: 1, CODE: 1, PRE: 1, NOSCRIPT: 1, svg: 1, SVG: 1, TEMPLATE: 1, IFRAME: 1 };
  var exact = {}, pats = [], extra = {}; // exact[norm] = {en, hi, ...}
  function store(k, v) { try { if (v === undefined) return localStorage.getItem(k); localStorage.setItem(k, v); } catch (e) { return null; } }
  function clean(v) { return String(v || '').replace(/"/g, '').trim(); }
  function valid(c) { return LANGS.some(function (l) { return l.code === c; }); }
  var OFF = clean(store(KEY)) === 'off'; // sirf testing: asli (source) text dikhaye
  var lang = (function () {
    var q = ''; try { q = new URLSearchParams(location.search).get('lang') || ''; } catch (e) {}
    if (valid(q)) { store(KEY, q); return q; }
    var s = clean(store(KEY)); if (valid(s)) return s; if (s === 'off') OFF = true;
    var d = clean(window.SP_LANG_DEFAULT || document.documentElement.getAttribute('data-lang-default') || 'en'); return valid(d) ? d : 'en';
  })();


  /* ---------------- Devanagari -> Hinglish (Roman) ---------------- */
  var XW = { 'में': 'mein', 'हैं': 'hain', 'है': 'hai', 'हूँ': 'hoon', 'नहीं': 'nahi', 'और': 'aur', 'का': 'ka', 'की': 'ki', 'के': 'ke', 'को': 'ko', 'से': 'se', 'पर': 'par', 'यह': 'yeh', 'ये': 'ye', 'वो': 'woh', 'वह': 'woh', 'कि': 'ki', 'भी': 'bhi', 'तो': 'to', 'या': 'ya', 'एक': 'ek', 'हम': 'hum', 'आप': 'aap', 'आपका': 'aapka', 'आपकी': 'aapki', 'आपके': 'aapke', 'हमारे': 'hamare', 'हमारी': 'hamari', 'हमारा': 'hamara', 'कृपया': 'kripya', 'ज़रूरी': 'zaroori', 'जरूरी': 'zaroori', 'फिर': 'phir', 'अभी': 'abhi', 'सब': 'sab', 'सभी': 'sabhi', 'कोई': 'koi', 'क्या': 'kya', 'कैसे': 'kaise', 'कौन': 'kaun', 'कब': 'kab', 'कहाँ': 'kahan', 'क्यों': 'kyon', 'लिए': 'liye', 'साथ': 'saath', 'बाद': 'baad', 'पहले': 'pehle', 'दें': 'den', 'करें': 'karein', 'करे': 'kare', 'चुनें': 'chunein', 'लिखें': 'likhein', 'डालें': 'daalein', 'देखें': 'dekhein', 'खोलें': 'kholein', 'जोड़ें': 'jodein', 'हटाएँ': 'hataein', 'बदलें': 'badlein', 'भेजें': 'bhejein', 'जाँचें': 'jaanchein', 'सेव': 'save', 'ऑर्डर': 'order', 'ऑर्डर्स': 'orders', 'कार्ट': 'cart', 'स्टोर': 'store', 'प्रोडक्ट': 'product', 'प्रोडक्ट्स': 'products', 'पेमेंट': 'payment', 'ऑफ़र': 'offer', 'ऑफर': 'offer', 'इन्वर्टर': 'inverter', 'पैनल': 'panel', 'बैटरी': 'battery', 'ग्रिड': 'grid', 'सोलर': 'solar', 'हाइब्रिड': 'hybrid', 'कोड': 'code', 'पिन': 'pin', 'एरर': 'error', 'ऐप': 'app', 'वेबसाइट': 'website', 'एडमिन': 'admin', 'लॉगिन': 'login', 'लॉगआउट': 'logout', 'पासवर्ड': 'password', 'मोबाइल': 'mobile', 'नंबर': 'number', 'ईमेल': 'email', 'अकाउंट': 'account', 'सेटिंग्स': 'settings', 'डिलीट': 'delete', 'एडिट': 'edit', 'कैंसल': 'cancel', 'फ़ोटो': 'photo', 'फोटो': 'photo', 'वीडियो': 'video', 'लिंक': 'link', 'बटन': 'button', 'पेज': 'page', 'होम': 'home', 'सर्विस': 'service', 'कोटेशन': 'quotation', 'बिल': 'bill', 'कस्टमर': 'customer', 'रेट': 'rate', 'सेक्शन': 'section', 'कैटेगरी': 'category', 'स्टॉक': 'stock', 'डिलीवरी': 'delivery', 'फ़ोन': 'phone', 'फोन': 'phone', 'कॉल': 'call', 'ऑनलाइन': 'online', 'ऑफ़लाइन': 'offline', 'स्टेटस': 'status', 'टेक्स्ट': 'text', 'फ़ॉर्म': 'form', 'फॉर्म': 'form', 'रिपोर्ट': 'report', 'डेटा': 'data', 'बैकअप': 'backup', 'रीस्टोर': 'restore', 'कंपनी': 'company', 'पता': 'pata', 'नाम': 'naam', 'दाम': 'daam', 'छूट': 'chhoot', 'ग्राहक': 'grahak', 'वापस': 'wapas', 'बंद': 'band', 'चालू': 'chalu', 'ठीक': 'theek', 'हाँ': 'haan', 'ना': 'na', 'जी': 'ji', 'रुपये': 'rupaye', 'किलोवाट': 'kilowatt', 'वारंटी': 'warranty', 'सब्सिडी': 'subsidy', 'पंप': 'pump', 'ड्राइव': 'drive', 'वी एफ डी': 'VFD', 'मिनट': 'minute', 'सिस्टम': 'system', 'इंजीनियर': 'engineer', 'डिस्प्ले': 'display', 'लोन': 'loan', 'प्रोजेक्ट': 'project', 'साइट': 'site', 'सर्वे': 'survey', 'सर्वे।': 'survey.', 'क्वालिटी': 'quality', 'सर्विसिंग': 'servicing', 'इंस्टॉलेशन': 'installation', 'इंस्टालेशन': 'installation', 'मेंटेनेंस': 'maintenance', 'ऑडिट': 'audit', 'कैलकुलेटर': 'calculator', 'सब्सक्राइब': 'subscribe', 'ऑर्डर्स': 'orders', 'इनवॉइस': 'invoice', 'रसीद': 'raseed', 'ट्रैक': 'track', 'डैशबोर्ड': 'dashboard', 'सपोर्ट': 'support', 'चैट': 'chat', 'व्हाट्सऐप': 'WhatsApp', 'व्हाट्सएप': 'WhatsApp', 'वॉट्सऐप': 'WhatsApp', 'गूगल': 'Google', 'रिव्यू': 'review', 'रेटिंग': 'rating', 'ब्रांड': 'brand', 'मॉडल': 'model', 'साइज़': 'size', 'वोल्टेज': 'voltage', 'करंट': 'current', 'फ़ॉल्ट': 'fault', 'फॉल्ट': 'fault', 'ओवरलोड': 'overload', 'मोटर': 'motor', 'वॉटर': 'water', 'लाइट': 'light', 'पावर': 'power', 'टेक्नीशियन': 'technician', 'कनेक्शन': 'connection', 'केबल': 'cable', 'स्विच': 'switch', 'ब्रेकर': 'breaker', 'रीसेट': 'reset', 'चेकलिस्ट': 'checklist', 'अपलोड': 'upload', 'डाउनलोड': 'download', 'प्रिंट': 'print', 'शेयर': 'share', 'कॉपी': 'copy', 'सर्च': 'search', 'फ़िल्टर': 'filter', 'लिस्ट': 'list', 'टैब': 'tab', 'मेन्यू': 'menu', 'ईएमआई': 'EMI', 'जीएसटी': 'GST', 'यूपीआई': 'UPI', 'ओटीपी': 'OTP', 'पैन': 'PAN', 'आधार': 'Aadhaar', 'कोड्स': 'codes', 'किट': 'kit', 'पैकेज': 'package', 'प्लान': 'plan', 'प्लांट': 'plant', 'रूफ': 'roof', 'रूफटॉप': 'rooftop', 'ग्राउंड': 'ground', 'माउंटेड': 'mounted', 'नेट': 'net', 'मीटर': 'meter', 'मीटरिंग': 'metering', 'डिस्कॉम': 'DISCOM', 'ऑटोमैटिक': 'automatic', 'फ्री': 'free', 'मुफ़्त': 'muft', 'मुफ्त': 'muft', 'कंफर्म': 'confirm', 'कन्फ़र्म': 'confirm', 'पेंडिंग': 'pending', 'डन': 'done', 'सक्सेस': 'success', 'फेल': 'fail', 'एक्टिव': 'active', 'इनएक्टिव': 'inactive', 'लखनऊ': 'Lucknow', 'कैंसलेशन': 'cancellation', 'ज़ीरो': 'zero', 'रिफ़ंड': 'refund', 'रिफंड': 'refund', 'ऑफ़िस': 'office', 'ऑफिस': 'office', 'फ़ैक्टरी': 'factory', 'फैक्ट्री': 'factory', 'फ़ैक्ट्री': 'factory', 'रेज़िडेंशियल': 'residential', 'कमर्शियल': 'commercial', 'इंडस्ट्रियल': 'industrial', 'मॉनिटरिंग': 'monitoring', 'फ़्री': 'free', 'लाइफ़': 'life', 'साइकिल': 'cycle', 'रिमोट': 'remote', 'एक्सपोर्ट': 'export', 'डिवाइस': 'device', 'सेफ़्टी': 'safety', 'स्ट्रक्चर': 'structure', 'एक्सपर्ट': 'expert', 'विज़िट': 'visit', 'मैन्युफ़ैक्चरर': 'manufacturer', 'क्लेम': 'claim', 'प्रीमियम': 'premium', 'पोर्टल': 'portal', 'रजिस्ट्रेशन': 'registration', 'डीज़ल': 'diesel', 'डायरेक्ट': 'direct', 'स्टोरेज': 'storage', 'कोल्ड': 'cold', 'वायरिंग': 'wiring', 'अर्थिंग': 'earthing', 'बाइडायरेक्शनल': 'bidirectional', 'ओपन': 'open', 'एक्सेस': 'access', 'प्लॉट': 'plot', 'रोड': 'road', 'मटेरियल': 'material', 'मिशन': 'mission', 'बिज़नेस': 'business', 'बेस्ट': 'best', 'ओरिजिनल': 'original', 'ग्रेड': 'grade', 'ऑटो': 'auto', 'मोड': 'mode', 'ऑन': 'on', 'ऑफ': 'off', 'ऑफ़': 'off', 'पीएम': 'PM', 'सूर्य': 'Surya', 'घर': 'ghar', 'योजना': 'yojana', 'सरकार': 'sarkar', 'लाख': 'lakh', 'करोड़': 'crore', 'हज़ार': 'hazaar', 'साल': 'saal', 'महीना': 'mahina', 'दिन': 'din', 'घंटे': 'ghante', 'बजे': 'baje' };
  var XC = { 'क': 'k', 'ख': 'kh', 'ग': 'g', 'घ': 'gh', 'ङ': 'n', 'च': 'ch', 'छ': 'chh', 'ज': 'j', 'झ': 'jh', 'ञ': 'n', 'ट': 't', 'ठ': 'th', 'ड': 'd', 'ढ': 'dh', 'ण': 'n', 'त': 't', 'थ': 'th', 'द': 'd', 'ध': 'dh', 'न': 'n', 'प': 'p', 'फ': 'ph', 'ब': 'b', 'भ': 'bh', 'म': 'm', 'य': 'y', 'र': 'r', 'ल': 'l', 'व': 'v', 'श': 'sh', 'ष': 'sh', 'स': 's', 'ह': 'h', 'ळ': 'l' };
  var XN = { 'क': 'q', 'ख': 'kh', 'ग': 'g', 'ज': 'z', 'ड': 'r', 'ढ': 'rh', 'फ': 'f' };
  var XV = { 'अ': 'a', 'आ': 'aa', 'इ': 'i', 'ई': 'i', 'उ': 'u', 'ऊ': 'u', 'ऋ': 'ri', 'ए': 'e', 'ऐ': 'ai', 'ओ': 'o', 'औ': 'au', 'ऑ': 'o', 'ऍ': 'e' };
  var XM = { 'ा': 'aa', 'ि': 'i', 'ी': 'i', 'ु': 'u', 'ू': 'u', 'ृ': 'ri', 'े': 'e', 'ै': 'ai', 'ो': 'o', 'ौ': 'au', 'ॉ': 'o', 'ॅ': 'e' };
  var DEV = /[ऀ-ॿ]+/g;
  function xword(w) {
    if (XW[w] != null) return XW[w];
    var u = [], i = 0, c = Array.from(w);
    while (i < c.length) {
      var ch = c[i], nx = c[i + 1];
      if (XV[ch] != null) { u.push({ r: XV[ch], v: 1 }); i++; continue; }
      if (XC[ch] != null) {
        var r = XC[ch], j = i + 1;
        if (c[j] === '़') { if (XN[ch]) r = XN[ch]; j++; }
        if (ch === 'क' && c[j] === '्' && c[j + 1] === 'ष') { r = 'ksh'; j += 2; if (c[j] === '़') j++; }
        else if (ch === 'ज' && c[j] === '्' && c[j + 1] === 'ञ') { r = 'gy'; j += 2; }
        var m = c[j];
        if (m === '्') { u.push({ r: r, v: 0 }); j++; }
        else if (m != null && XM[m] != null) { u.push({ r: r + XM[m], v: 1, long: m === 'ा' }); j++; }
        else u.push({ r: r + 'a', v: 1, sc: 1 });
        i = j; continue;
      }
      if (ch === 'ं' || ch === 'ँ') { var nn = nx && XC[nx]; u.push({ r: (nn && 'पबम'.indexOf(nx) >= 0) ? 'm' : 'n', v: 0 }); i++; continue; }
      if (ch === 'ः') { u.push({ r: 'h', v: 0 }); i++; continue; }
      if (ch === '।') { u.push({ r: '.', v: 0 }); i++; continue; }
      i++;
    }
    // schwa deletion: word end, then V C(a) C V pattern from the right
    for (var k = u.length - 1; k >= 0; k--) {
      var x = u[k]; if (!x.sc) continue;
      var last = k === u.length - 1;
      if (last && u.length > 1) { x.r = x.r.slice(0, -1); x.sc = 0; x.v = 0; continue; }
      var prev = u[k - 1], next = u[k + 1];
      if (prev && prev.v && next && next.v && k > 0 && k < u.length - 1 && !(k === u.length - 2 && next.sc === 0 && false)) { x.r = x.r.slice(0, -1); x.sc = 0; x.v = 0; }
    }
    var last2 = u[u.length - 1]; if (last2 && last2.long && u.length > 1) last2.r = last2.r.slice(0, -1);
    return u.map(function (x) { return x.r; }).join('');
  }
  function capFirst(s) { return String(s).replace(/(^\s*|[.?!]\s+)([a-z])/g, function (m, a, b) { return a + b.toUpperCase(); }); }
  function xlit(text) { var src = String(text == null ? '' : text), out = src.replace(DEV, function (w) { return xword(w); }).replace(/aaa+/g, 'aa'); return /^\s*[\u0900-\u097F]/.test(src) ? capFirst(out) : out; }

  /* ---------------- dictionary ---------------- */
  var NUM = /(₹\s?)?[-+]?\d[\d,]*(\.\d+)?%?/g;
  function norm(s) { return String(s).replace(/\s+/g, ' ').trim(); }
  function numKey(s) { var i = 0; return s.replace(NUM, function () { return '{' + (i++) + '}'; }); }
  function put(key, rec) { if (key && !exact[key]) exact[key] = rec; }
  function add(list) {
    (list || []).forEach(function (e) {
      if (!e) return; var rec = Array.isArray(e) ? { en: e[0], hi: e[1] != null ? e[1] : e[0] } : e; if (!rec.hg) { var olds = Array.isArray(e) ? e.slice(2) : (e.src || []); for (var oi = 0; oi < olds.length; oi++) { var ov = String(olds[oi] || ''); if (ov && !/[\u0900-\u097F]/.test(ov) && norm(ov) !== norm(rec.en) && /[a-z]/i.test(ov) && ov.indexOf('{s}') < 0) { rec.hg = norm(ov); break; } } }
      var vars = Array.isArray(e) ? e : [e.en, e.hi].concat(e.src || []);
      vars.forEach(function (v) {
        if (v == null || v === '') return; v = norm(v);
        if (v.indexOf('{s}') >= 0) {
          var re = '^' + v.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/\\\{s\\\}/g, '(.+?)').replace(/\\\{(\d)\\\}/g, '(\\S+)') + '$';
          try { pats.push({ re: new RegExp(re), rec: rec }); } catch (x) {}
        } else { put(v, rec); if (/\{\d\}/.test(v)) return; var nk = numKey(v); if (nk !== v) put(nk, rec); }
      });
    });
  }
  function addLang(code, label, map, opt) { if (!valid(code)) LANGS.push({ code: code, label: label, short: (opt && opt.short) || label.slice(0, 3), beta: !!(opt && opt.beta) }); NAMES[code] = label; extra[code] = Object.assign(extra[code] || {}, map || {});
    if (!OFF && clean(store(KEY)) === code && lang !== code) { if (started) set(code); else lang = code; } // the saved choice was a language that is registered a moment later
    paintButtons(); }
  function pick(rec, l) { if (l === 'en') return rec.en; if (l === 'hi') return rec.hi; if (l === 'hg') return rec.hg ? (/^[A-Z]/.test(rec.en || '') ? capFirst(rec.hg) : rec.hg) : xlit(rec.hi); return (extra[l] || {})[rec.en] || rec.en; }
  function fill(tpl, vals) { return String(tpl).replace(/\{(\d|s)\}/g, function (m, k) { var v = vals.shift(); return v == null ? '' : v; }); }
  function lookup(core, l) {
    var r = exact[core]; if (r) return pick(r, l);
    var nums = core.match(NUM); if (nums) { var k = numKey(core); r = exact[k]; if (r) { var i = 0; return pick(r, l).replace(/\{(\d)\}/g, function (m, n) { return nums[+n] != null ? nums[+n] : ''; }); } }
    for (var j = 0; j < pats.length; j++) { var m = pats[j].re.exec(core); if (m) return fill(pick(pats[j].rec, l), m.slice(1)); }
    return null;
  }
  var EDGE = /^([^\p{L}\p{N}]*)([\s\S]*?)([^\p{L}\p{N}]*)$/u;
  function tr(text, l) {
    if (OFF) return null; l = l || lang; var s = String(text); if (!/[A-Za-zऀ-ॿ]/.test(s)) return null;
    var lead = (s.match(/^\s*/) || [''])[0], tail = (s.match(/\s*$/) || [''])[0], body = norm(s);
    var out = lookup(body, l);
    if (out == null) { var m = EDGE.exec(body); if (m && m[2] && (m[1] || m[3])) { var o2 = lookup(m[2], l); if (o2 != null) out = m[1] + o2 + m[3]; } }
    if (out == null && l === 'hg' && /[\u0900-\u097F]/.test(body)) out = xlit(body);
    return out == null ? null : lead + out + tail;
  }

  /* ---------------- DOM ---------------- */
  var TXT = new WeakMap(), ATT = new WeakMap(), busy = false;
  function skip(el) { for (var e = el; e && e.nodeType === 1; e = e.parentNode) { if (SKIP[e.nodeName] || (e.hasAttribute && e.hasAttribute('data-noi18n')) || e.isContentEditable) return true; } return false; }
  function doText(n) {
    var st = TXT.get(n), v = n.nodeValue;
    if (st && v === st.out) { /* hamara hi likha hua */ }
    else st = { src: v, out: v };
    var r = tr(st.src); st.out = r == null ? st.src : r; TXT.set(n, st);
    if (n.nodeValue !== st.out) n.nodeValue = st.out;
  }
  function doAttrs(el) {
    var m = ATT.get(el) || {};
    ATTRS.forEach(function (a) {
      if (!el.hasAttribute(a)) return; var v = el.getAttribute(a), st = m[a];
      if (!(st && v === st.out)) st = { src: v, out: v };
      var r = tr(st.src); st.out = r == null ? st.src : r; m[a] = st; if (v !== st.out) el.setAttribute(a, st.out);
    });
    if (el.tagName === 'INPUT' && /^(button|submit|reset)$/i.test(el.type) && el.value) { var st2 = m.value; if (!(st2 && el.value === st2.out)) st2 = { src: el.value, out: el.value }; var r2 = tr(st2.src); st2.out = r2 == null ? st2.src : r2; m.value = st2; if (el.value !== st2.out) el.value = st2.out; }
    ATT.set(el, m);
  }
  function walk(root) {
    if (!root) return;
    if (root.nodeType === 3) { if (!skip(root.parentNode)) doText(root); return; }
    if (root.nodeType !== 1 && root.nodeType !== 9 && root.nodeType !== 11) return;
    if (root.nodeType === 1 && skip(root)) return;
    if (root.nodeType === 1) doAttrs(root);
    var w = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, { acceptNode: function (n) { if (n.nodeType === 1) return SKIP[n.nodeName] || n.hasAttribute('data-noi18n') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT; return NodeFilter.FILTER_ACCEPT; } }), n;
    while ((n = w.nextNode())) { if (n.nodeType === 3) { if (n.nodeValue && /\S/.test(n.nodeValue) && !(n.parentNode && n.parentNode.isContentEditable)) doText(n); } else doAttrs(n); }
  }
  function title() { var t = document.querySelector('title'); if (t && t.firstChild) walk(t.firstChild); }
  var mo = new MutationObserver(function (list) {
    if (busy) return; busy = true;
    try {
      for (var i = 0; i < list.length; i++) {
        var m = list[i];
        if (m.type === 'childList') { for (var j = 0; j < m.addedNodes.length; j++) { var an = m.addedNodes[j]; walk(an); if (an.nodeType === 1 && (an.hasAttribute('data-sp-lang') || an.querySelector('[data-sp-lang]'))) paintButtons(); } }
        else if (m.type === 'characterData') { if (!skip(m.target.parentNode)) doText(m.target); }
        else if (m.type === 'attributes') { if (!skip(m.target)) doAttrs(m.target); }
      }
    } finally { busy = false; }
  });
  function css() { if (!document.getElementById('sp-lang-css')) { var s = document.createElement('style'); s.id = 'sp-lang-css'; s.textContent = CSS; (document.head || document.documentElement).appendChild(s); } }
  var started = false;
  function start() {
    started = true; css(); if (!OFF) document.documentElement.lang = lang === 'hg' ? 'hi-Latn' : lang;
    walk(document.body); title();
    mo.observe(document.documentElement, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ATTRS.concat(['value']) });
    document.documentElement.classList.remove('i18n-wait');
    paintButtons();
  }
  function set(l) {
    if (!valid(l) || (l === lang && !OFF)) return; OFF = false; lang = l; store(KEY, l); document.documentElement.lang = l === 'hg' ? 'hi-Latn' : l;
    busy = true; try { walk(document.body); title(); } finally { busy = false; }
    paintButtons();
    try { document.dispatchEvent(new CustomEvent('sp-lang', { detail: { lang: l } })); } catch (e) {}
  }

  /* ---------------- header button ---------------- */
  var CSS = '.sp-lang{display:inline-flex;align-items:center;gap:6px;min-height:36px;padding:6px 12px;border-radius:999px;border:1.5px solid rgba(0,0,0,.14);background:#fff;color:#14231a;font:inherit;font-weight:800;font-size:13px;line-height:1;cursor:pointer;white-space:nowrap}.sp-lang:hover{border-color:#1e8e3e}.sp-lang svg{width:16px;height:16px;flex:none}.sp-lang.dark{background:rgba(255,255,255,.08);color:#fff;border-color:rgba(255,255,255,.28)}#sp-lm{position:fixed;z-index:2147483000;background:#fff;color:#14231a;border:1px solid rgba(0,0,0,.14);border-radius:14px;box-shadow:0 12px 34px rgba(0,0,0,.22);padding:6px;display:flex;flex-direction:column;min-width:170px;max-height:70vh;overflow:auto}#sp-lm button{display:flex;align-items:center;gap:8px;justify-content:space-between;border:0;background:none;font:inherit;font-weight:700;font-size:15px;padding:11px 14px;border-radius:10px;cursor:pointer;color:inherit;text-align:left}#sp-lm button:hover,#sp-lm button:focus-visible{background:#e7f3e9;outline:none}#sp-lm small{font-size:10px;background:#fff4da;color:#8a5a00;border-radius:999px;padding:1px 6px}';
  var NAMES = { en: 'English', hi: 'हिंदी', hg: 'Hinglish' };
  function curLang() { var c = OFF ? 'en' : lang; return LANGS.filter(function (x) { return x.code === c; })[0] || LANGS[0]; }
  function paintButtons() {
    var cur = curLang();
    Array.prototype.forEach.call(document.querySelectorAll('[data-sp-lang]'), function (b) {
      b.setAttribute('data-noi18n', ''); var lbl = b.getAttribute('data-sp-lang') === 'short' ? cur.short : cur.label; if (b.getAttribute('data-l') === cur.code + lbl) return; b.setAttribute('data-l', cur.code + lbl);
      b.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2a15 15 0 0 1 0 20M12 2a15 15 0 0 0 0 20"/></svg><span>' + lbl + '</span><span aria-hidden="true" style="font-size:10px">▾</span>';
      b.setAttribute('aria-label', 'Language: ' + (NAMES[cur.code] || cur.label)); b.setAttribute('aria-haspopup', 'menu'); b.setAttribute('lang', cur.code === 'hg' ? 'en' : cur.code);
    });
  }
  function closeMenu() { var m = document.getElementById('sp-lm'); if (m) m.remove(); document.removeEventListener('click', outside, true); document.removeEventListener('keydown', onKey, true); }
  function outside(e) { var m = document.getElementById('sp-lm'); if (m && !m.contains(e.target)) closeMenu(); }
  function onKey(e) { if (e.key === 'Escape') closeMenu(); }
  function menu(anchor) {
    closeMenu(); css(); var m = document.createElement('div'); m.id = 'sp-lm'; m.setAttribute('role', 'menu'); m.setAttribute('data-noi18n', '');
    var cur = curLang().code;
    m.innerHTML = LANGS.map(function (l) { return '<button type="button" role="menuitemradio" aria-checked="' + (l.code === cur) + '" data-lc="' + l.code + '" lang="' + (l.code === 'hg' ? 'en' : l.code) + '">' + (NAMES[l.code] || l.label) + (l.code === cur ? ' ✓' : '') + (l.beta ? ' <small>beta</small>' : '') + '</button>'; }).join('');
    document.body.appendChild(m);
    var r = anchor.getBoundingClientRect(), w = m.offsetWidth, left = Math.max(8, Math.min(window.innerWidth - w - 8, r.right - w));
    m.style.top = Math.min(window.innerHeight - m.offsetHeight - 8, r.bottom + 6) + 'px'; m.style.left = left + 'px';
    m.addEventListener('click', function (e) { var b = e.target.closest('[data-lc]'); if (!b) return; var c = b.getAttribute('data-lc'); closeMenu(); set(c); try { anchor.focus(); } catch (x) {} });
    setTimeout(function () { document.addEventListener('click', outside, true); document.addEventListener('keydown', onKey, true); }, 0);
    var f = m.querySelector('[aria-checked=true]') || m.firstChild; if (f && f.focus) f.focus();
  }
  function button(cls, short) {
    css(); var b = document.createElement('button'); b.type = 'button'; b.className = 'sp-lang' + (cls ? ' ' + cls : ''); b.setAttribute('data-sp-lang', short ? 'short' : 'long'); b.setAttribute('data-noi18n', '');
    b._spb = 1; b.addEventListener('click', function () { menu(b); });
    setTimeout(paintButtons, 0); return b;
  }
  document.addEventListener('click', function (e) { var b = e.target.closest && e.target.closest('[data-sp-lang]'); if (b && !b._spb) { e.preventDefault(); menu(b); } });

  window.SPI18N = { menu: menu, xlit: xlit, get lang() { return lang; }, get off() { return OFF; }, LANGS: LANGS, add: add, addLang: addLang, set: set, t: function (s) { var r = tr(s); return r == null ? s : r; }, tr: tr, walk: walk, button: button, _exact: exact };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
  setTimeout(function () { document.documentElement.classList.remove('i18n-wait'); }, 1500);
})();
