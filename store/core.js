/* =====================================================================
   SUNPOWERS — core.js  (shared by index.html and admin.html)
   Data layer, demo data, helpers. No external libraries.
   ===================================================================== */
(function () {
  'use strict';
  var CFG = window.SP_CONFIG || {};
  var SP = (window.SP = {});
  SP.cfg = CFG;
  SP.BUCKET = CFG.IMAGE_BUCKET || 'sp-images';

  /* ---------------- small helpers ---------------- */
  SP.esc = function (s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  };
  SP.uid = function (p) {
    return (p || 'id') + '_' + Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
  };
  SP.clone = function (o) { return JSON.parse(JSON.stringify(o)); };
  SP.num = function (v) {
    if (typeof v === 'number') return isFinite(v) ? v : 0;
    var n = parseFloat(String(v == null ? '' : v).replace(/[^0-9.\-]/g, ''));
    return isFinite(n) ? n : 0;
  };
  SP.money = function (n) { return '₹' + Math.round(SP.num(n)).toLocaleString('en-IN'); };
  SP.debounce = function (fn, ms) {
    var t; return function () { var a = arguments, me = this; clearTimeout(t); t = setTimeout(function () { fn.apply(me, a); }, ms); };
  };
  SP.digits = function (s) { return String(s || '').replace(/\D/g, ''); };
  SP.waNumber = function (s) { var d = SP.digits(s); if (d.length === 10) d = '91' + d; return d; };
  SP.waLink = function (num, text) {
    return 'https://wa.me/' + SP.waNumber(num) + (text ? '?text=' + encodeURIComponent(text) : '');
  };
  SP.ytId = function (url) {
    url = String(url || '').trim();
    if (/^[A-Za-z0-9_-]{11}$/.test(url)) return url;
    var m = url.match(/(?:youtube\.com\/(?:watch\?(?:.*&)?v=|embed\/|shorts\/|live\/|v\/)|youtu\.be\/)([A-Za-z0-9_-]{11})/);
    return m ? m[1] : '';
  };
  SP.isImg = function (s) { return !!s && /^(https?:\/\/|data:image\/|\/|\.\/)/i.test(String(s).trim()); };
  SP.safeUrl = function (u) {
    u = String(u || '').trim();
    if (!u) return '#';
    if (/^(https?:|mailto:|tel:|upi:|\/|\.\/|\?|#)/i.test(u)) return u;
    if (/^[a-z][a-z0-9+.-]*:/i.test(u)) return '#'; // block javascript: etc.
    return 'https://' + u;
  };
  SP.discount = function (p) {
    var m = SP.num(p.mrp), o = SP.num(p.offer);
    return m > 0 && o > 0 && o < m ? Math.round((1 - o / m) * 100) : 0;
  };
  SP.price = function (p) { var o = SP.num(p.offer); return o > 0 ? o : SP.num(p.mrp); };
  SP.ls = {
    get: function (k, d) { try { var v = localStorage.getItem(k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } },
    set: function (k, v) { try { localStorage.setItem(k, JSON.stringify(v)); return true; } catch (e) { return false; } },
    del: function (k) { try { localStorage.removeItem(k); } catch (e) {} }
  };
  SP.ss = {
    get: function (k) { try { return sessionStorage.getItem(k); } catch (e) { return null; } },
    set: function (k, v) { try { sessionStorage.setItem(k, v); } catch (e) {} },
    del: function (k) { try { sessionStorage.removeItem(k); } catch (e) {} }
  };

  /* ---------------- backend (Supabase REST, no SDK) ---------------- */
  SP.backendReady = function () { return !!(CFG.SUPABASE_URL && CFG.SUPABASE_KEY); };
  function base() { return String(CFG.SUPABASE_URL || '').replace(/\/+$/, ''); }
  function authHeaders(extra) {
    var key = String(CFG.SUPABASE_KEY || '').trim();
    var h = { apikey: key };
    // New Supabase keys (sb_publishable_...) are not JWTs: send only the apikey header.
    if (key.indexOf('sb_') !== 0) h.Authorization = 'Bearer ' + key;
    for (var k in extra || {}) h[k] = extra[k];
    return h;
  }
  SP.rpc = async function (fn, args, timeoutMs) {
    if (!SP.backendReady()) throw new Error('Database connect nahi hai (config.js check karein)');
    var ctrl = typeof AbortController !== 'undefined' ? new AbortController() : null;
    var timer = setTimeout(function () { if (ctrl) ctrl.abort(); }, timeoutMs || 20000);
    var res;
    try {
      res = await fetch(base() + '/rest/v1/rpc/' + fn, {
        method: 'POST',
        headers: authHeaders({ 'Content-Type': 'application/json' }),
        body: JSON.stringify(args || {}),
        signal: ctrl ? ctrl.signal : undefined
      });
    } catch (e) {
      throw new Error(e && e.name === 'AbortError' ? 'Server se jawab nahi aaya (timeout). Internet check karein.' : 'Network error — internet check karein.');
    } finally { clearTimeout(timer); }
    var txt = await res.text(), body = null;
    try { body = txt ? JSON.parse(txt) : null; } catch (e) { body = txt; }
    if (!res.ok) {
      var msg = (body && (body.message || body.msg || body.error_description || body.error)) || ('HTTP ' + res.status);
      var code = body && body.code;
      if (res.status === 404 || code === 'PGRST202' || /could not find the function/i.test(msg))
        msg = 'Database setup baaki hai — Supabase me setup.sql run karein.';
      var err = new Error(msg); err.status = res.status; err.code = code; throw err;
    }
    return body;
  };

  /* image helpers */
  SP.compressImage = function (file, maxDim, quality) {
    return new Promise(function (resolve, reject) {
      if (!file || !/^image\//.test(file.type || '')) return reject(new Error('Sirf image file chunein (JPG/PNG/WebP)'));
      if (file.type === 'image/gif' && file.size < 1.5e6) return resolve(file);
      var url = URL.createObjectURL(file), img = new Image();
      img.onload = function () {
        try {
          var w = img.naturalWidth, h = img.naturalHeight, s = Math.min(1, maxDim / Math.max(w, h));
          var cw = Math.max(1, Math.round(w * s)), ch = Math.max(1, Math.round(h * s));
          var c = document.createElement('canvas'); c.width = cw; c.height = ch;
          var ctx = c.getContext('2d'); ctx.fillStyle = '#ffffff'; ctx.fillRect(0, 0, cw, ch); ctx.drawImage(img, 0, 0, cw, ch);
          URL.revokeObjectURL(url);
          c.toBlob(function (b) { b ? resolve(b) : reject(new Error('Image process nahi ho payi')); }, 'image/jpeg', quality);
        } catch (e) { reject(e); }
      };
      img.onerror = function () { URL.revokeObjectURL(url); reject(new Error('Image read nahi ho payi')); };
      img.src = url;
    });
  };
  SP.blobToDataUrl = function (blob) {
    return new Promise(function (res, rej) {
      var r = new FileReader(); r.onload = function () { res(r.result); }; r.onerror = function () { rej(new Error('Image read error')); }; r.readAsDataURL(blob);
    });
  };
  SP.uploadImage = async function (blob) {
    if (!SP.backendReady()) throw new Error('no backend');
    var ext = blob.type === 'image/gif' ? 'gif' : blob.type === 'image/png' ? 'png' : blob.type === 'image/webp' ? 'webp' : 'jpg';
    var path = 'img/' + Date.now() + '-' + Math.random().toString(36).slice(2, 8) + '.' + ext;
    var res = await fetch(base() + '/storage/v1/object/' + SP.BUCKET + '/' + path, {
      method: 'POST',
      headers: authHeaders({ 'Content-Type': blob.type || 'image/jpeg', 'x-upsert': 'false', 'cache-control': 'max-age=31536000' }),
      body: blob
    });
    if (!res.ok) { var t = ''; try { t = await res.text(); } catch (e) {} throw new Error('Upload failed (' + res.status + ') ' + t.slice(0, 120)); }
    return base() + '/storage/v1/object/public/' + SP.BUCKET + '/' + path;
  };
  /* returns {url, fallback:boolean} */
  SP.storeImage = async function (file) {
    var big = await SP.compressImage(file, 1600, 0.85);
    try { return { url: await SP.uploadImage(big), fallback: false }; }
    catch (e) {
      var small = await SP.compressImage(file, 700, 0.7);
      return { url: await SP.blobToDataUrl(small), fallback: true, error: e.message };
    }
  };

  /* ---------------- store load / normalize ---------------- */
  SP.CACHE_KEY = 'sp_store_cache_v1';
  SP.loadStore = async function () {
    try {
      var d = await SP.rpc('sp_get_store', {}, 12000);
      if (d && typeof d === 'object' && !Array.isArray(d) && Array.isArray(d.layout)) {
        var n = SP.normalize(d);
        SP.ls.set(SP.CACHE_KEY, n);
        return { data: n, source: 'db' };
      }
      return { data: SP.normalize(SP.demo()), source: 'demo' };
    } catch (e) {
      var c = SP.ls.get(SP.CACHE_KEY, null);
      if (c && Array.isArray(c.layout)) return { data: SP.normalize(c), source: 'cache', error: e };
      return { data: SP.normalize(SP.demo()), source: 'demo', error: e };
    }
  };

  function isObj(o) { return o && typeof o === 'object' && !Array.isArray(o); }
  function mergeDefaults(def, val) {
    if (!isObj(def)) return val === undefined ? def : val;
    var out = {}, k;
    val = isObj(val) ? val : {};
    for (k in def) out[k] = isObj(def[k]) ? mergeDefaults(def[k], val[k]) : (val[k] === undefined || val[k] === null ? def[k] : val[k]);
    for (k in val) if (!(k in out)) out[k] = val[k];
    return out;
  }
  SP.BLOCK_TYPES = ['slideshow', 'section', 'services', 'chips', 'form', 'howto', 'feedback', 'videos'];
  SP.SINGLE_BLOCKS = ['services', 'chips', 'form', 'howto', 'feedback', 'videos'];
  SP.SLIDESHOW_DEF = { name: 'Slideshow', interval: 4, effect: 'slide', autoplay: true, dots: true, arrows: true, height: 190, visible: true };
  SP.SLIDE_DEF = { image: '', bg: '#1b5e20', emoji: '☀️', title: '', subtitle: '', button: '', ribbon: '', linkType: 'none', link: '', visible: true };
  SP.SECTION_DEF = { title: 'New Section', titleEn: '', subtitle: '', kind: 'category', limit: 8, icon: '', visible: true };
  SP.PRODUCT_DEF = { title: '', titleEn: '', sections: [], tagline: '', desc: '', descEn: '', mrp: 0, offer: 0, unit: '', badge: '',
    stock: 'in', visible: true, sort: 0, emoji: '☀️', bg: '#e8f5e9', image: '', images: [], link: '', sku: '', brand: '' };

  SP.normalize = function (d) {
    var def = SP.demo();
    d = isObj(d) ? SP.clone(d) : {};
    var out = d;
    out.settings = mergeDefaults(def.settings, d.settings);
    ['services', 'form', 'howto', 'feedback', 'videos'].forEach(function (k) {
      out[k] = isObj(d[k]) ? mergeDefaults(def[k], d[k]) : def[k];
    });
    ['services', 'feedback', 'videos'].forEach(function (k) {
      if (!Array.isArray(out[k].items)) out[k].items = [];
      out[k].items = out[k].items.filter(isObj).map(function (it) { if (!it.id) it.id = SP.uid('it'); return it; });
    });
    ['types', 'steps'].forEach(function (k) {
      var o = k === 'types' ? out.form : out.howto;
      if (!Array.isArray(o[k])) o[k] = String(o[k] || '').split('\n').map(function (s) { return s.trim(); }).filter(Boolean);
    });
    out.pages = (Array.isArray(d.pages) ? d.pages : SP.clone(SP.PAGES_DEF)).filter(isObj).map(function (pg) {
      pg = mergeDefaults({ id: '', title: '', titleEn: '', body: '', bodyEn: '', footer: true }, pg);
      pg.id = String(pg.id || '').replace(/[^a-z0-9_-]/gi, '').toLowerCase() || SP.uid('pg'); return pg;
    });
    if (!(SP.num(d.v) >= 2)) migrateV2(out);
    out.sections = (Array.isArray(d.sections) ? d.sections : []).filter(isObj).map(function (s) {
      s = mergeDefaults(SP.SECTION_DEF, s); if (!s.id) s.id = SP.uid('sec'); s.limit = Math.max(1, Math.min(40, Math.round(SP.num(s.limit)) || 8)); return s;
    });
    out.slideshows = (Array.isArray(d.slideshows) ? d.slideshows : []).filter(isObj).map(function (ss) {
      var slides = Array.isArray(ss.slides) ? ss.slides : [];
      ss = mergeDefaults(SP.SLIDESHOW_DEF, ss); if (!ss.id) ss.id = SP.uid('ss');
      ss.interval = Math.max(1, Math.min(60, SP.num(ss.interval) || 4));
      ss.height = Math.max(100, Math.min(600, SP.num(ss.height) || 190));
      ss.slides = slides.filter(isObj).map(function (sl) { sl = mergeDefaults(SP.SLIDE_DEF, sl); if (!sl.id) sl.id = SP.uid('sl'); return sl; });
      return ss;
    });
    var secIds = {}; out.sections.forEach(function (s) { secIds[s.id] = 1; });
    out.products = (Array.isArray(d.products) ? d.products : []).filter(isObj).map(function (p) {
      p = mergeDefaults(SP.PRODUCT_DEF, p); if (!p.id) p.id = SP.uid('p');
      if (!Array.isArray(p.sections)) p.sections = p.sections ? [String(p.sections)] : [];
      p.sections = p.sections.filter(function (id) { return secIds[id]; });
      if (!Array.isArray(p.images)) p.images = p.images ? [String(p.images)] : [];
      p.images = p.images.filter(Boolean);
      p.mrp = SP.num(p.mrp); p.offer = SP.num(p.offer); p.sort = SP.num(p.sort);
      p.stock = p.stock === 'out' ? 'out' : 'in';
      return p;
    });
    var ssIds = {}; out.slideshows.forEach(function (s) { ssIds[s.id] = 1; });
    var seenSingle = {}, seenRef = {};
    out.layout = (Array.isArray(d.layout) ? d.layout : def.layout).filter(function (b) {
      if (!isObj(b) || SP.BLOCK_TYPES.indexOf(b.type) < 0) return false;
      if (b.type === 'section') { if (!secIds[b.ref] || seenRef[b.ref]) return false; seenRef[b.ref] = 1; }
      else if (b.type === 'slideshow') { if (!ssIds[b.ref] || seenRef[b.ref]) return false; seenRef[b.ref] = 1; }
      else { if (seenSingle[b.type]) return false; seenSingle[b.type] = 1; }
      return true;
    }).map(function (b) { if (!b.id) b.id = SP.uid('b'); if (b.hidden !== true) b.hidden = false; return b; });
    out.v = 2;
    return out;
  };

  /* one-time upgrade of data saved by version 1 (only replaces untouched demo values) */
  function migrateV2(out) {
    var st = out.settings, def = SP.demo().settings;
    if (st.email === 'contact@sunpowers.in') st.email = def.email;
    if (st.siteUrl === 'https://www.sunpowers.in') st.siteUrl = def.siteUrl;
    if (st.location === 'India') st.location = def.location;
    if (!st.address) st.address = def.address;
    if (st.delivery === 'डिलीवरी चार्ज ऑर्डर कन्फ़र्म करते समय बताया जाएगा।') st.delivery = def.delivery;
    ['facebook', 'instagram', 'youtube', 'gmb'].forEach(function (k) { if (!st.social[k]) st.social[k] = def.social[k]; });
    var demoNames = { fb1: 'रमेश यादव', fb2: 'सुनीता शर्मा', fb3: 'मोहम्मद आरिफ़', fb4: 'Anil Verma', fb5: 'प्रिया सिंह' };
    out.feedback.items = out.feedback.items.filter(function (it) { return demoNames[it.id] !== it.name; });
    var swap = { 'सब्सिडी योजना योग्य*': 'DCR — सब्सिडी आवेदन के लिए', 'कुसुम योजना योग्य*': 'खेती के लिए बड़ा पंप', 'सब्सिडी सहायता उपलब्ध*': 'आवेदन में सहायता',
      'फ्री सर्वे बुक करें': 'सर्वे बुक करें', '☀️ फ्री साइट सर्वे • आसान EMI • सब्सिडी सहायता': '☀️ साइट सर्वे • इंस्टॉलेशन • सब्सिडी आवेदन में सहायता',
      'सब्सिडी के लिए पूरी मदद': 'सब्सिडी आवेदन में सहायता', '✅ आवेदन से इंस्टॉलेशन तक पूरी सहायता': '✅ आवेदन से इंस्टॉलेशन तक साथ',
      'फ्री साइट सर्वे': 'साइट सर्वे', 'घर/दुकान की छत का मुफ़्त निरीक्षण': 'घर/दुकान की छत का निरीक्षण', 'मुफ़्त': 'अभी बुक करें',
      'ट्रेंड टेक्नीशियन, AMC उपलब्ध': 'ट्रेंड टेक्नीशियन, 5 साल फ़ोन सपोर्ट', 'From ₹999': 'साइट देखकर रेट' };
    function fix(o, keys) { keys.forEach(function (k) { if (typeof o[k] === 'string' && swap[o[k]]) o[k] = swap[o[k]]; }); }
    (out.products || []).forEach(function (p) { if (isObj(p)) fix(p, ['tagline']); });
    (out.slideshows || []).forEach(function (ss) { if (isObj(ss)) (ss.slides || []).forEach(function (sl) { if (isObj(sl)) fix(sl, ['title', 'subtitle', 'button', 'ribbon']); }); });
    out.services.items.forEach(function (it) { fix(it, ['title', 'sub', 'price']); });
  }

  SP.sortProducts = function (list) {
    return list.slice().sort(function (a, b) { return (SP.num(a.sort) - SP.num(b.sort)); });
  };
  SP.productsOf = function (store, secId, includeHidden) {
    return SP.sortProducts(store.products.filter(function (p) {
      return (includeHidden || p.visible !== false) && p.sections.indexOf(secId) >= 0;
    }));
  };

  /* ---------------- default legal / info pages ({placeholders} filled from Settings) ---------------- */
  SP.PAGES_DEF = [
    { id: 'about', title: 'हमारे बारे में', titleEn: 'About Us', footer: true,
      body: [
        '## {storeName} के बारे में',
        '{legalName} लखनऊ, उत्तर प्रदेश की एक सोलर एनर्जी कंपनी है। हम {since} से काम कर रहे हैं — छोटे घरेलू सिस्टम से लेकर बड़े कमर्शियल और इंडस्ट्रियल सोलर प्लांट तक।',
        '## हम क्या करते हैं',
        '- सोलर पैनल, इन्वर्टर, बैटरी, सोलर पंप, लाइट, वाटर हीटर और एक्सेसरीज़ की बिक्री',
        '- घर, दुकान और फैक्ट्री के लिए ऑन-ग्रिड, ऑफ-ग्रिड और हाइब्रिड सोलर सिस्टम',
        '- आटा चक्की, पंप और कोल्ड स्टोरेज के लिए VFD सोलर समाधान',
        '- साइट सर्वे, इंस्टॉलेशन और बिक्री के बाद सपोर्ट',
        '- सब्सिडी आवेदन में सहायता (रजिस्टर्ड पार्टनर के माध्यम से)',
        '## ब्रांड',
        'हम Adani, Waaree, Tata Power Solar, Luminous, Polycab, Growatt जैसी कंपनियों के प्रोडक्ट बेचते हैं। हर प्रोडक्ट की वारंटी उसकी निर्माता कंपनी देती है।',
        '## बिज़नेस की जानकारी',
        '- नाम: {legalName}',
        '- प्रोप्राइटर: {ownerName}',
        '- GSTIN: {gstin}',
        '- पता: {address}',
        '- फ़ोन / WhatsApp: {phone}',
        '- ईमेल: {email}',
        '- समय: {hours}'].join('\n'),
      bodyEn: [
        '## About {storeName}',
        '{legalName} is a solar energy company based in Lucknow, Uttar Pradesh. We have been working {sinceEn} — from small home systems to large commercial and industrial solar plants.',
        '## What we do',
        '- Sale of solar panels, inverters, batteries, solar pumps, lights, water heaters and accessories',
        '- On-grid, off-grid and hybrid solar systems for homes, shops and factories',
        '- VFD solar solutions for flour mills, pumps and cold storage',
        '- Site survey, installation and after-sales support',
        '- Help with subsidy applications (through registered partners)',
        '## Brands',
        'We sell products of manufacturers such as Adani, Waaree, Tata Power Solar, Luminous, Polycab and Growatt. The warranty on every product is given by its manufacturer.',
        '## Business details',
        '- Name: {legalName}',
        '- Proprietor: {ownerName}',
        '- GSTIN: {gstin}',
        '- Address: {address}',
        '- Phone / WhatsApp: {phone}',
        '- Email: {email}',
        '- Working hours: {hoursEn}'].join('\n') },
    { id: 'contact', title: 'संपर्क करें', titleEn: 'Contact Us', footer: true,
      body: [
        '## संपर्क करें',
        '- फ़ोन / WhatsApp: {phone}',
        '- ईमेल: {email}',
        '- पता: {address}',
        '- समय: {hours}',
        '- Google Maps: {mapsLink}',
        'आप होम पेज पर "अपनी ज़रूरत बताएं" फ़ॉर्म भी भर सकते हैं या WhatsApp पर मैसेज कर सकते हैं। हम आमतौर पर एक कार्य-दिवस में जवाब देते हैं।',
        '## बिज़नेस',
        '{legalName} • GSTIN: {gstin}'].join('\n'),
      bodyEn: [
        '## Contact us',
        '- Phone / WhatsApp: {phone}',
        '- Email: {email}',
        '- Address: {address}',
        '- Working hours: {hoursEn}',
        '- Google Maps: {mapsLink}',
        'You can also fill the requirement form on our home page or message us on WhatsApp. We usually reply within one working day.',
        '## Business',
        '{legalName} • GSTIN: {gstin}'].join('\n') },
    { id: 'returns', title: 'रिटर्न, रिफ़ंड व कैंसिलेशन पॉलिसी', titleEn: 'Return, Refund & Cancellation Policy', footer: true,
      body: [
        'अंतिम अपडेट: {policyDate}',
        '## सार',
        '- {siteUrl} पर बिकने वाले प्रोडक्ट रिटर्न और रिफ़ंड योग्य नहीं हैं, सिवाय नीचे बताए गए मामलों के।',
        '- अगर प्रोडक्ट टूटा/खराब या ऑर्डर से अलग पहुँचे, तो हम उसे बदल (एक्सचेंज) देंगे।',
        '- डिस्पैच होने से पहले आप ऑर्डर कैंसिल कर सकते हैं।',
        '## टूटा, खराब या गलत प्रोडक्ट',
        '- डिलीवरी के {reportDays} दिन के अंदर WhatsApp ({phone}) या ईमेल ({email}) पर प्रोडक्ट और पैकिंग की फ़ोटो/वीडियो के साथ बताएँ।',
        '- जाँच के बाद हम प्रोडक्ट या खराब पार्ट मुफ़्त में बदल देंगे। एक्सचेंज वाले सामान पर नकद रिफ़ंड नहीं मिलता।',
        '- लगा हुआ, इस्तेमाल किया हुआ, काटा हुआ (जैसे केबल) या आपके लिए खास मंगाया गया सामान नहीं बदला जाएगा, जब तक उसमें वारंटी वाला निर्माण दोष न हो।',
        '## सोलर प्रोजेक्ट और इंस्टॉलेशन',
        '- पूरे सोलर सिस्टम/प्रोजेक्ट (सप्लाई + इंस्टॉलेशन) आपकी साइट के हिसाब से तैयार होते हैं, इन पर कोई रिटर्न पॉलिसी नहीं है। प्रोजेक्ट के बीच में कोई बदलाव कराने का खर्च अलग से लगेगा।',
        '## ऑर्डर कैंसिल करना',
        '- डिस्पैच से पहले: ऑर्डर कैंसिल कर सकते हैं, जमा की गई पूरी रकम (COD का {advancePct}% एडवांस भी) वापस मिलेगी।',
        '- डिस्पैच के बाद: सामान्यतः कैंसिल नहीं होता। हमारे द्वारा स्वीकार किए गए खास मामलों में डिलीवरी खर्च काटकर रकम वापस की जाएगी।',
        '## रिफ़ंड',
        '- मंज़ूर हुआ रिफ़ंड 7–10 कार्य-दिवस में उसी UPI ID या आपके बैंक खाते में भेजा जाएगा।',
        '## वारंटी',
        '- वारंटी प्रोडक्ट की निर्माता कंपनी अपनी शर्तों के अनुसार देती है। वारंटी क्लेम में Sunpowers पूरी मदद करेगा। हमारे द्वारा लगाए गए पूरे प्लांट के लिए 5 साल तक फ़ोन पर सपोर्ट मिलेगा।',
        '## संपर्क',
        '{legalName}, {address} • {phone} • {email}'].join('\n'),
      bodyEn: [
        'Last updated: {policyDate}',
        '## Summary',
        '- Products sold on {siteUrl} are non-returnable and non-refundable, except in the cases listed below.',
        '- If a product reaches you damaged, defective or different from what you ordered, we will replace (exchange) it.',
        '- You can cancel an order any time before it is dispatched.',
        '## Damaged, defective or wrong product',
        '- Tell us within {reportDays} days of delivery on WhatsApp ({phone}) or email ({email}), with photos/video of the product and packaging.',
        '- After checking, we will replace the product or the faulty part free of cost. Exchanged items are not refunded in cash.',
        '- Products that are installed, used, cut (e.g. cables) or specially ordered for you cannot be exchanged, unless they have a manufacturing defect covered by warranty.',
        '## Solar projects and installations',
        '- Complete solar system / project orders (supply + installation) are prepared for your site and have no return policy. Changes requested in the middle of a project are charged separately.',
        '## Order cancellation',
        '- Before dispatch: you may cancel the order; the full amount paid (including the {advancePct}% advance on Cash on Delivery orders) is refunded.',
        '- After dispatch: orders normally cannot be cancelled. In exceptional cases accepted by us, the amount is refunded after deducting delivery charges.',
        '## Refunds',
        '- Approved refunds are sent within 7–10 working days to the original UPI ID or to your bank account.',
        '## Warranty',
        '- Warranty is given by the product manufacturer as per its terms. Sunpowers will help you with warranty claims. For complete plants installed by us, phone support is available for 5 years.',
        '## Contact',
        '{legalName}, {address} • {phone} • {email}'].join('\n') },
    { id: 'shipping', title: 'शिपिंग व डिलीवरी पॉलिसी', titleEn: 'Shipping & Delivery Policy', footer: true,
      body: [
        'अंतिम अपडेट: {policyDate}',
        '## डिलीवरी कहाँ',
        '- पूरे उत्तर प्रदेश और भारत के दूसरे राज्यों में डिलीवरी।',
        '## डिलीवरी का समय',
        '- लखनऊ: 1–3 कार्य-दिवस',
        '- बाकी उत्तर प्रदेश: 3–7 कार्य-दिवस',
        '- दूसरे राज्य: 3–15 कार्य-दिवस',
        '- बड़े सिस्टम में ज़्यादा समय लग सकता है — ऑर्डर कन्फ़र्म करते समय बता दिया जाएगा।',
        '## डिलीवरी चार्ज',
        '- {localName} में: फ़्री',
        '- बाकी जगह: ₹{otherCharge} प्रति ऑर्डर',
        '- ₹{freeAbove} से ऊपर के ऑर्डर पर डिलीवरी फ़्री',
        'डिलीवरी चार्ज ऑर्डर करने से पहले कार्ट में दिख जाता है।',
        '## ऑर्डर कन्फ़र्मेशन',
        '- ऑर्डर के बाद हम WhatsApp/फ़ोन पर कन्फ़र्म करते हैं। Cash on Delivery में {advancePct}% एडवांस UPI से देकर ऑर्डर कन्फ़र्म होता है, बाकी डिलीवरी पर।',
        '## इंस्टॉलेशन',
        '- जब तक अलग से न लिखा हो, प्रोडक्ट की कीमत में इंस्टॉलेशन शामिल नहीं है। इंस्टॉलेशन चार्ज साइट देखकर बताया जाता है।',
        '## रास्ते में नुकसान',
        '- डिलीवरी के समय पैकिंग चेक करें। नुकसान होने पर रिटर्न पॉलिसी के अनुसार {reportDays} दिन के अंदर बताएँ।'].join('\n'),
      bodyEn: [
        'Last updated: {policyDate}',
        '## Delivery area',
        '- We deliver across Uttar Pradesh and to other states of India.',
        '## Delivery time',
        '- Lucknow: 1–3 working days',
        '- Rest of Uttar Pradesh: 3–7 working days',
        '- Other states: 3–15 working days',
        '- Large systems may take longer — we will tell you when we confirm the order.',
        '## Delivery charges',
        '- Delivery in {localNameEn}: free',
        '- Other locations: ₹{otherCharge} per order',
        '- Free delivery on orders above ₹{freeAbove}',
        'The delivery charge is shown in the cart before you place the order.',
        '## Order confirmation',
        '- After you order, we confirm it on WhatsApp/phone. For Cash on Delivery, {advancePct}% advance is paid by UPI to confirm the order and the balance is paid on delivery.',
        '## Installation',
        '- Unless stated, installation is not included in the product price. Installation charges are told after seeing the site.',
        '## Damage in transit',
        '- Please check the package at delivery. If anything is damaged, tell us within {reportDays} days as per our Return Policy.'].join('\n') },
    { id: 'privacy', title: 'प्राइवेसी पॉलिसी', titleEn: 'Privacy Policy', footer: true,
      body: [
        'अंतिम अपडेट: {policyDate}',
        '## हम कौन सी जानकारी लेते हैं',
        '- ऑर्डर करते या फ़ॉर्म भरते समय दी गई जानकारी: नाम, मोबाइल नंबर, पता, शहर, पिनकोड और संदेश।',
        '- अगर Analytics चालू हो तो वेबसाइट इस्तेमाल की सामान्य जानकारी (कौन से पेज देखे गए)।',
        '## जानकारी का इस्तेमाल',
        '- ऑर्डर पूरा करने और डिलीवरी के लिए; ऑर्डर, साइट सर्वे, इंस्टॉलेशन और सर्विस के बारे में संपर्क करने के लिए; और आपकी सहमति हो तो ऑफ़र भेजने के लिए।',
        '## जानकारी कहाँ रखी जाती है',
        '- ऑर्डर और फ़ॉर्म की जानकारी हमारे सुरक्षित डेटाबेस (Supabase) और हमारे कस्टमर मैनेजमेंट सिस्टम (CRM) में रखी जाती है। इसे सिर्फ़ Sunpowers की टीम देख सकती है।',
        '## जानकारी साझा करना',
        '- हम आपकी जानकारी बेचते नहीं हैं। ज़रूरत भर की जानकारी सिर्फ़ डिलीवरी पार्टनर, इंस्टॉलेशन पार्टनर, निर्माता कंपनी (वारंटी के लिए) और पेमेंट ऐप के साथ साझा होती है।',
        '## कुकीज़ और Analytics',
        '- वेबसाइट Google Analytics और Meta Pixel का इस्तेमाल कर सकती है। आपका कार्ट और पसंद की लिस्ट सिर्फ़ आपके ब्राउज़र में सेव रहती है।',
        '## आपके अधिकार',
        '- अपनी जानकारी देखने, सुधारने या हटवाने के लिए {email} पर लिखें।',
        '## शिकायत अधिकारी',
        '{ownerName}, {legalName}, {address} • {email} • {phone}'].join('\n'),
      bodyEn: [
        'Last updated: {policyDate}',
        '## Information we collect',
        '- Information you give when you order or fill a form: name, mobile number, address, city, pincode and messages.',
        '- Basic usage information (pages visited), if analytics is turned on.',
        '## How we use it',
        '- To process and deliver orders; to contact you about orders, site surveys, installation and service; and to send offers if you agree.',
        '## Where it is stored',
        '- Order and form data is stored in our secure database (Supabase) and in our customer management system (CRM). Only the Sunpowers team can access it.',
        '## Sharing',
        '- We do not sell your information. We share only what is needed with delivery partners, installation partners, product manufacturers (for warranty) and payment apps.',
        '## Cookies and analytics',
        '- The website may use Google Analytics and Meta Pixel. Your cart and wishlist are saved only in your own browser.',
        '## Your rights',
        '- To see, correct or delete your information, write to {email}.',
        '## Grievance officer',
        '{ownerName}, {legalName}, {address} • {email} • {phone}'].join('\n') },
    { id: 'terms', title: 'नियम व शर्तें', titleEn: 'Terms & Conditions', footer: true,
      body: [
        'अंतिम अपडेट: {policyDate}',
        '## परिचय',
        '- यह वेबसाइट ({siteUrl}) {legalName} (GSTIN {gstin}), {address} द्वारा चलाई जाती है। ऑर्डर करके आप इन शर्तों से सहमत होते हैं।',
        '## कीमत और GST',
        '- सभी कीमतें भारतीय रुपये में और GST सहित हैं। कीमत और ऑफ़र बिना सूचना बदल सकते हैं; ऑर्डर के समय दिखी कीमत लागू होगी।',
        '## ऑर्डर और पेमेंट',
        '- ऑर्डर तभी पक्का होता है जब हम फ़ोन/WhatsApp पर कन्फ़र्म करते हैं। प्रोडक्ट उपलब्ध न होने या कीमत गलत दिखने पर हम ऑर्डर कैंसिल कर सकते हैं, और जमा पूरी रकम वापस करेंगे।',
        '- पेमेंट: Cash on Delivery ({advancePct}% एडवांस UPI से) या पूरा भुगतान UPI से।',
        '## प्रोडक्ट की जानकारी',
        '- फ़ोटो सिर्फ़ संदर्भ के लिए हैं, असली प्रोडक्ट थोड़ा अलग हो सकता है। स्पेसिफ़िकेशन निर्माता कंपनी के अनुसार हैं।',
        '## वारंटी और ज़िम्मेदारी',
        '- वारंटी निर्माता कंपनी देती है। हमारी ज़िम्मेदारी खरीदे गए प्रोडक्ट की कीमत तक सीमित है। इंस्टॉलेशन के बीच में कराए गए बदलाव का खर्च अलग लगेगा।',
        '## रिटर्न',
        '- हमारी रिटर्न, रिफ़ंड व कैंसिलेशन पॉलिसी देखें।',
        '## कानून',
        '- ये शर्तें भारत के कानून के अधीन हैं। किसी भी विवाद का क्षेत्राधिकार लखनऊ, उत्तर प्रदेश की अदालतें होंगी।'].join('\n'),
      bodyEn: [
        'Last updated: {policyDate}',
        '## About these terms',
        '- This website ({siteUrl}) is run by {legalName} (GSTIN {gstin}), {address}. By placing an order you agree to these terms.',
        '## Prices and GST',
        '- All prices are in Indian Rupees and include GST. Prices and offers may change without notice; the price shown when you place the order applies.',
        '## Orders and payment',
        '- An order is confirmed only when we confirm it by phone/WhatsApp. We may cancel an order if a product is unavailable or a price was shown wrongly; any amount paid will be refunded in full.',
        '- Payment: Cash on Delivery ({advancePct}% advance via UPI) or full payment via UPI.',
        '## Product information',
        '- Photos are for reference; the actual product may look slightly different. Specifications are as given by the manufacturer.',
        '## Warranty and liability',
        '- Warranty is given by the manufacturer. Our liability is limited to the price of the product bought. Changes requested in the middle of an installation are charged separately.',
        '## Returns',
        '- See our Return, Refund & Cancellation Policy.',
        '## Governing law',
        '- These terms are governed by the laws of India. Courts at Lucknow, Uttar Pradesh have jurisdiction.'].join('\n') }
  ];
  SP.pageVars = function (st) {
    var sh = st.shipping || {}, adv = st.payments && st.payments.cod ? Math.round(SP.num(st.payments.cod.advancePct)) : 15;
    return {
      storeName: st.storeName, legalName: st.legalName || st.storeName, ownerName: st.ownerName, gstin: st.gstin || '—',
      address: st.address, phone: st.phone || st.whatsapp, email: st.email, hours: st.hours, hoursEn: st.hoursEn || st.hours,
      mapsLink: st.mapsLink || (st.social && st.social.gmb) || '', siteUrl: String(st.siteUrl || '').replace(/\/+$/, ''), mainSite: st.mainSite,
      since: st.since, sinceEn: st.sinceEn || st.since, policyDate: st.policyDate, reportDays: st.reportDays || 7, advancePct: adv,
      localName: sh.localName || 'लखनऊ', localNameEn: sh.localNameEn || 'Lucknow',
      otherCharge: Math.round(SP.num(sh.otherCharge)).toLocaleString('en-IN'), freeAbove: Math.round(SP.num(sh.freeAbove)).toLocaleString('en-IN')
    };
  };
  SP.fillVars = function (text, st) {
    var v = SP.pageVars(st);
    return String(text || '').replace(/\{(\w+)\}/g, function (m, k) { return v[k] !== undefined && v[k] !== null && v[k] !== '' ? String(v[k]) : m; });
  };
  /* delivery charge for a cart */
  SP.shippingFor = function (subtotal, pin, st) {
    var sh = st.shipping || {};
    if (sh.enabled === false) return { charge: 0, known: true, free: true, label: '' };
    var free = SP.num(sh.freeAbove) > 0 && subtotal >= SP.num(sh.freeAbove);
    pin = SP.digits(pin);
    var local = String(sh.localPins || '').split(/[,\s]+/).filter(Boolean).some(function (p) { return pin.indexOf(p) === 0; });
    if (free) return { charge: 0, known: true, free: true, reason: 'above' };
    if (pin.length !== 6) return { charge: SP.num(sh.otherCharge), known: false, free: false };
    if (local) return { charge: SP.num(sh.localCharge), known: true, free: SP.num(sh.localCharge) === 0, reason: 'local' };
    return { charge: SP.num(sh.otherCharge), known: true, free: SP.num(sh.otherCharge) === 0, reason: 'other' };
  };
  /* tiny safe renderer: "## heading", "- bullet", blank line = new paragraph, URLs/emails become links */
  SP.renderText = function (text) {
    var out = [], list = null;
    function inline(s) {
      return SP.esc(s).replace(/(https?:\/\/[^\s<]+[^\s<.,;:!?)])/g, '<a href="$1" target="_blank" rel="noopener">$1</a>')
        .replace(/([\w.+-]+@[\w-]+\.[\w.-]+[a-z])/gi, '<a href="mailto:$1">$1</a>');
    }
    String(text || '').split('\n').forEach(function (raw) {
      var l = raw.trim();
      if (/^-\s+/.test(l)) { if (!list) { list = []; } list.push('<li>' + inline(l.replace(/^-\s+/, '')) + '</li>'); return; }
      if (list) { out.push('<ul>' + list.join('') + '</ul>'); list = null; }
      if (!l) return;
      if (/^##\s+/.test(l)) out.push('<h2>' + inline(l.replace(/^##\s+/, '')) + '</h2>');
      else out.push('<p>' + inline(l) + '</p>');
    });
    if (list) out.push('<ul>' + list.join('') + '</ul>');
    return out.join('');
  };

  /* ---------------- DEMO DATA (editable from admin) ---------------- */
  SP.demo = function () {
    var pastel = ['#e8f5e9', '#fff3e0', '#e3f2fd', '#fce4ec', '#f3e5f5', '#fffde7', '#e0f7fa', '#f1f8e9'];
    var cats = [
      ['sec_c1', 'सोलर पैनल', 'Solar Panels', '☀️', 'हर छत के लिए सही पैनल', [
        ['मोनो PERC सोलर पैनल 540W', 'Mono PERC Solar Panel 540W', 16500, 13999, 'Tier-1 • 25 साल परफॉर्मेंस वारंटी', 'Bestseller'],
        ['बाइफेशियल सोलर पैनल 550W', 'Bifacial Solar Panel 550W', 19000, 15999, 'दोनों तरफ़ से बिजली', ''],
        ['TOPCon सोलर पैनल 580W', 'TOPCon Solar Panel 580W', 22000, 18499, 'नई टेक्नोलॉजी, ज़्यादा बिजली', 'New'],
        ['पॉली सोलर पैनल 335W', 'Poly Solar Panel 335W', 9500, 7999, 'बजट फ्रेंडली', ''],
        ['मोनो सोलर पैनल 200W', 'Mono Solar Panel 200W', 6500, 5299, 'छोटे घर / दुकान के लिए', ''],
        ['DCR सोलर पैनल 545W', 'DCR Solar Panel 545W', 24000, 20999, 'DCR — सब्सिडी आवेदन के लिए', '']]],
      ['sec_c2', 'सोलर इन्वर्टर', 'Solar Inverters', '🔌', 'ऑन-ग्रिड, ऑफ-ग्रिड और हाइब्रिड', [
        ['ऑन-ग्रिड इन्वर्टर 3kW', 'On-Grid Inverter 3kW', 42000, 34999, 'नेट मीटरिंग रेडी', 'Bestseller'],
        ['ऑन-ग्रिड इन्वर्टर 5kW', 'On-Grid Inverter 5kW', 58000, 48999, 'WiFi मॉनिटरिंग', ''],
        ['हाइब्रिड इन्वर्टर 5kW', 'Hybrid Inverter 5kW', 85000, 72999, 'बैटरी + ग्रिड दोनों', 'New'],
        ['ऑफ-ग्रिड PCU 2.5kVA', 'Off-Grid PCU 2.5kVA', 28000, 22999, 'MPPT चार्जर के साथ', ''],
        ['सोलर होम UPS 1100VA', 'Solar Home UPS 1100VA', 9500, 7499, 'घर के लिए पावर बैकअप', ''],
        ['थ्री-फेज़ इन्वर्टर 10kW', '3-Phase Inverter 10kW', 115000, 96999, 'दुकान / फैक्ट्री के लिए', '']]],
      ['sec_c3', 'सोलर बैटरी', 'Solar Batteries', '🔋', 'लंबा बैकअप, लंबी उम्र', [
        ['सोलर ट्यूबलर बैटरी 150Ah', 'Solar Tubular Battery 150Ah', 16500, 13499, '5 साल वारंटी', 'Bestseller'],
        ['सोलर ट्यूबलर बैटरी 200Ah', 'Solar Tubular Battery 200Ah', 21000, 17499, 'लंबा बैकअप', ''],
        ['लिथियम बैटरी 2.5kWh', 'Lithium Battery 2.5kWh', 65000, 54999, 'हल्की व मेंटेनेंस-फ्री', 'New'],
        ['लिथियम LFP बैटरी 5kWh', 'Lithium LFP Battery 5kWh', 120000, 99999, '6000+ साइकिल लाइफ़', ''],
        ['बैटरी ट्रॉली', 'Battery Trolley', 1500, 999, 'मज़बूत स्टील', ''],
        ['डिस्टिल्ड वाटर 5L', 'Battery Distilled Water 5L', 250, 180, 'बैटरी की देखभाल', '']]],
      ['sec_c4', 'सोलर वाटर पंप', 'Solar Water Pumps', '💧', 'किसानों के लिए मुफ़्त धूप से सिंचाई', [
        ['सोलर सबमर्सिबल पंप 1HP', 'Solar Submersible Pump 1HP', 65000, 54999, 'छोटे खेत के लिए', ''],
        ['सोलर सबमर्सिबल पंप 3HP', 'Solar Submersible Pump 3HP', 135000, 114999, 'खेती के लिए बड़ा पंप', 'Bestseller'],
        ['सोलर सरफेस पंप 1HP', 'Solar Surface Pump 1HP', 48000, 39999, 'कम गहराई के लिए', ''],
        ['सोलर पंप कंट्रोलर (VFD) 3HP', 'Solar Pump Controller (VFD) 3HP', 38000, 31999, 'पंप की पूरी सुरक्षा', ''],
        ['सोलर DC वाटर पंप 0.5HP', 'Solar DC Water Pump 0.5HP', 22000, 17999, 'घर की टंकी के लिए', ''],
        ['सोलर पंप सेट 5HP', 'Solar Pump Set 5HP', 240000, 205000, 'कम्प्लीट किट', '']]],
      ['sec_c5', 'सोलर लाइट्स', 'Solar Lights', '💡', 'बिना बिजली बिल के रोशनी', [
        ['सोलर स्ट्रीट लाइट 30W', 'Solar Street Light 30W', 6500, 4999, 'ऑटो ON/OFF', ''],
        ['सोलर फ्लड लाइट 100W', 'Solar Flood Light 100W', 4500, 2999, 'रिमोट के साथ', 'Bestseller'],
        ['सोलर गार्डन लाइट (4 पैक)', 'Solar Garden Light (Pack of 4)', 2400, 1499, 'बगीचे की शोभा', ''],
        ['सोलर होम लाइटिंग किट', 'Solar Home Lighting Kit', 3500, 2499, '3 बल्ब + मोबाइल चार्जिंग', ''],
        ['सोलर वॉल लाइट (मोशन सेंसर)', 'Solar Wall Light (Motion Sensor)', 1200, 799, 'आते ही जलेगी', ''],
        ['सोलर लालटेन', 'Solar Lantern', 1500, 999, 'कहीं भी ले जाएँ', '']]],
      ['sec_c6', 'चार्ज कंट्रोलर व DB', 'Charge Controllers & DB', '🎛️', 'सुरक्षित और सही चार्जिंग', [
        ['MPPT चार्ज कंट्रोलर 40A', 'MPPT Charge Controller 40A', 6500, 4999, '30% तक ज़्यादा चार्जिंग', ''],
        ['MPPT चार्ज कंट्रोलर 60A', 'MPPT Charge Controller 60A', 9500, 7499, 'बड़े सिस्टम के लिए', ''],
        ['PWM चार्ज कंट्रोलर 20A', 'PWM Charge Controller 20A', 1800, 1199, 'छोटे सिस्टम के लिए', ''],
        ['PWM चार्ज कंट्रोलर 30A', 'PWM Charge Controller 30A', 2400, 1599, 'LCD डिस्प्ले', ''],
        ['DC डिस्ट्रीब्यूशन बॉक्स (DCDB)', 'DC Distribution Box (DCDB)', 3500, 2699, 'SPD + फ्यूज़ के साथ', ''],
        ['AC डिस्ट्रीब्यूशन बॉक्स (ACDB)', 'AC Distribution Box (ACDB)', 3200, 2499, 'MCB + SPD', '']]],
      ['sec_c7', 'सोलर वाटर हीटर', 'Solar Water Heaters', '🚿', 'सर्दियों में मुफ़्त गर्म पानी', [
        ['सोलर वाटर हीटर 100L', 'Solar Water Heater 100L', 28000, 22999, '3-4 लोगों के परिवार के लिए', ''],
        ['सोलर वाटर हीटर 150L', 'Solar Water Heater 150L', 35000, 28999, '5-6 लोगों के लिए', 'Bestseller'],
        ['सोलर वाटर हीटर 200L', 'Solar Water Heater 200L', 42000, 34999, 'बड़े परिवार के लिए', ''],
        ['सोलर वाटर हीटर 300L', 'Solar Water Heater 300L', 62000, 52999, 'होटल / हॉस्टल के लिए', ''],
        ['ETC ट्यूब (रिप्लेसमेंट)', 'ETC Tube (Replacement)', 900, 650, 'सभी मॉडल के लिए', ''],
        ['हीटर स्टैंड किट', 'Water Heater Stand Kit', 4500, 3499, 'जंग-रोधी', '']]],
      ['sec_c8', 'वायर, केबल व एक्सेसरीज़', 'Cables & Accessories', '🧰', 'इंस्टॉलेशन का पूरा सामान', [
        ['सोलर DC केबल 4mm (100m)', 'Solar DC Cable 4mm (100m)', 9000, 7499, 'UV प्रोटेक्टेड', ''],
        ['सोलर DC केबल 6mm (100m)', 'Solar DC Cable 6mm (100m)', 13500, 10999, 'कॉपर कंडक्टर', ''],
        ['MC4 कनेक्टर (10 जोड़ी)', 'MC4 Connectors (10 Pairs)', 900, 599, 'वाटरप्रूफ़', 'Bestseller'],
        ['अर्थिंग किट', 'Earthing Kit', 4500, 3299, 'केमिकल अर्थिंग', ''],
        ['लाइटनिंग अरेस्टर', 'Lightning Arrester', 3800, 2799, 'आसमानी बिजली से सुरक्षा', ''],
        ['पैनल माउंटिंग स्ट्रक्चर (1kW)', 'Panel Mounting Structure (1kW)', 9000, 6999, 'GI हॉट-डिप', '']]],
      ['sec_c9', 'कम्प्लीट सोलर सिस्टम', 'Complete Solar Systems', '🏠', 'इंस्टॉलेशन सहित पूरा सेटअप', [
        ['1kW ऑन-ग्रिड सोलर सिस्टम', '1kW On-Grid Solar System', 75000, 62000, 'आवेदन में सहायता', ''],
        ['3kW ऑन-ग्रिड सोलर सिस्टम', '3kW On-Grid Solar System', 195000, 165000, 'आवेदन में सहायता', 'Bestseller'],
        ['5kW ऑन-ग्रिड सोलर सिस्टम', '5kW On-Grid Solar System', 310000, 265000, 'बड़े घर के लिए', ''],
        ['2kW ऑफ-ग्रिड सोलर सिस्टम', '2kW Off-Grid Solar System', 165000, 139000, 'बैटरी बैकअप के साथ', ''],
        ['5kW हाइब्रिड सोलर सिस्टम', '5kW Hybrid Solar System', 420000, 359000, 'ग्रिड + बैटरी', 'New'],
        ['10kW कमर्शियल सोलर सिस्टम', '10kW Commercial Solar System', 650000, 549000, 'दुकान / फैक्ट्री के लिए', '']]]
    ];
    var sections = [
      { id: 'sec_u1', title: 'आज के ऑफर 🔥', titleEn: "Today's Offers 🔥", subtitle: 'सीमित समय के लिए', kind: 'update', limit: 6, icon: '', visible: true },
      { id: 'sec_u2', title: 'बेस्ट सेलर ⭐', titleEn: 'Best Sellers ⭐', subtitle: 'ग्राहकों की पहली पसंद', kind: 'update', limit: 6, icon: '', visible: true }
    ];
    var products = [], n = 0;
    cats.forEach(function (c) {
      sections.push({ id: c[0], title: c[1], titleEn: c[2], subtitle: c[4], kind: 'category', limit: 8, icon: c[3], visible: true });
      c[5].forEach(function (p, i) {
        n++;
        products.push({
          id: 'p_' + c[0].slice(4) + '_' + (i + 1), title: p[0], titleEn: p[1], sections: [c[0]],
          tagline: p[4], desc: p[0] + ' — Sunpowers द्वारा भरोसेमंद क्वालिटी, सही दाम और इंस्टॉलेशन सपोर्ट। (यह डेमो विवरण है, Admin से बदलें)',
          descEn: p[1] + ' — trusted quality, fair price and installation support by Sunpowers. (Demo text — edit from Admin)',
          mrp: p[2], offer: p[3], unit: '', badge: p[5], stock: 'in', visible: true, sort: i + 1,
          emoji: c[3], bg: pastel[n % pastel.length], image: '', images: [], link: '', sku: 'SP-' + String(n).padStart(3, '0'), brand: 'Sunpowers'
        });
      });
    });
    function add(id, sec) { products.forEach(function (p) { if (p.id === id) p.sections.push(sec); }); }
    ['p_c9_2', 'p_c1_1', 'p_c3_1', 'p_c5_2', 'p_c4_2', 'p_c7_2'].forEach(function (id) { add(id, 'sec_u1'); });
    ['p_c2_1', 'p_c1_3', 'p_c8_3', 'p_c2_3', 'p_c3_3', 'p_c9_5'].forEach(function (id) { add(id, 'sec_u2'); });

    function sl(bg, emoji, title, subtitle, button, ribbon, linkType, link) {
      return { id: SP.uid('sl'), image: '', bg: bg, emoji: emoji, title: title, subtitle: subtitle, button: button, ribbon: ribbon, linkType: linkType, link: link, visible: true };
    }
    var slideshows = [
      { id: 'ss_1', name: 'Slideshow 1 (Top)', interval: 4, effect: 'slide', autoplay: true, dots: true, arrows: true, height: 190, visible: true, slides: [
        sl('#1b5e20', '🏡', 'घर पर सोलर लगवाएं', 'बिजली बिल में भारी बचत', 'सर्वे बुक करें', '☀️ साइट सर्वे • इंस्टॉलेशन • सब्सिडी आवेदन में सहायता', 'form', ''),
        sl('#0d47a1', '📄', 'PM सूर्य घर योजना', 'सब्सिडी आवेदन में सहायता', 'सिस्टम देखें', '✅ आवेदन से इंस्टॉलेशन तक साथ', 'section', 'sec_c9'),
        sl('#e65100', '🎉', 'फेस्टिव सोलर सेल', 'चुनिंदा प्रोडक्ट्स पर भारी छूट', 'ऑफर देखें', '🔥 सीमित समय का ऑफर', 'section', 'sec_u1')] },
      { id: 'ss_2', name: 'Slideshow 2', interval: 5, effect: 'fade', autoplay: true, dots: true, arrows: true, height: 170, visible: true, slides: [
        sl('#4a148c', '🔋', 'लिथियम बैटरी', 'हल्की, तेज़ चार्ज, लंबी उम्र', 'देखें', '⚡ 6000+ साइकिल लाइफ़', 'section', 'sec_c3'),
        sl('#004d40', '🔌', 'हाइब्रिड इन्वर्टर', 'ग्रिड + बैटरी, दोनों का फ़ायदा', 'देखें', '📶 WiFi मॉनिटरिंग', 'product', 'p_c2_3')] },
      { id: 'ss_3', name: 'Slideshow 3', interval: 4, effect: 'slide', autoplay: true, dots: true, arrows: true, height: 170, visible: true, slides: [
        sl('#01579b', '🚜', 'किसान भाइयों के लिए', 'सोलर पंप से मुफ़्त सिंचाई', 'पंप देखें', '💧 डीज़ल का ख़र्च ख़त्म', 'section', 'sec_c4'),
        sl('#f57f17', '🚿', 'सोलर वाटर हीटर', 'सर्दियों में मुफ़्त गर्म पानी', 'देखें', '♨️ 100L से 300L तक', 'section', 'sec_c7')] },
      { id: 'ss_4', name: 'Slideshow 4', interval: 4, effect: 'fade', autoplay: true, dots: true, arrows: true, height: 170, visible: true, slides: [
        sl('#2e7d32', '🛠️', 'इंस्टॉलेशन व सर्विस', 'ट्रेंड टेक्नीशियन, समय पर सर्विस', 'WhatsApp करें', '📞 एक कॉल पर सर्विस', 'whatsapp', 'नमस्ते, मुझे सोलर इंस्टॉलेशन/सर्विस चाहिए'),
        sl('#37474f', '🤝', 'डीलर / बल्क ऑर्डर', 'होलसेल रेट पर सोलर प्रोडक्ट्स', 'फ़ॉर्म भरें', '📦 पूरे भारत में डिलीवरी', 'form', '')] }
    ];
    var layout = [
      { type: 'slideshow', ref: 'ss_1' }, { type: 'services' }, { type: 'chips' },
      { type: 'section', ref: 'sec_u1' }, { type: 'section', ref: 'sec_u2' },
      { type: 'slideshow', ref: 'ss_2' },
      { type: 'section', ref: 'sec_c1' }, { type: 'section', ref: 'sec_c2' }, { type: 'section', ref: 'sec_c3' },
      { type: 'slideshow', ref: 'ss_3' },
      { type: 'section', ref: 'sec_c4' }, { type: 'section', ref: 'sec_c5' }, { type: 'section', ref: 'sec_c6' },
      { type: 'slideshow', ref: 'ss_4' },
      { type: 'section', ref: 'sec_c7' }, { type: 'section', ref: 'sec_c8' }, { type: 'section', ref: 'sec_c9' },
      { type: 'form' }, { type: 'howto' }, { type: 'feedback' }, { type: 'videos' }
    ].map(function (b, i) { b.id = 'b' + (i + 1); b.hidden = false; return b; });

    return {
      v: 2,
      settings: {
        storeName: 'Sunpowers', tagline: 'सोलर समाधान, भरोसे के साथ', logo: '☀️', logoImg: '', location: 'Lucknow',
        whatsapp: '9621050636', phone: '9621050636', email: 'helpsunpowers@gmail.com',
        address: 'Plot No. 49, Amrai Gaon, Faizabad Road, Lucknow, Uttar Pradesh - 226016',
        legalName: 'Sunpowers Enterprises', ownerName: 'Suraj Yadav', gstin: '09AQMPY6347CZ29',
        hours: 'सोम–शनि 9AM–8PM, रवि 10AM–6PM', hoursEn: 'Mon–Sat 9 AM–8 PM, Sun 10 AM–6 PM',
        since: '2016 से • 500+ प्रोजेक्ट', sinceEn: 'since 2016 and have completed 500+ projects',
        mapsLink: 'https://maps.app.goo.gl/9r7jtxRPokG3yKVw8', reviewLink: 'https://g.page/r/Ccdrza3K_Y_CEBM/review',
        googleRating: '5.0', googleReviews: '17', mainSite: 'https://www.sunpowers.in', gstNote: 'सभी कीमतें GST सहित',
        policyDate: '08-10-2026', reportDays: 7, policyConsent: true,
        shipping: { enabled: true, localPins: '226', localName: 'लखनऊ', localNameEn: 'Lucknow', localCharge: 0, otherCharge: 500, freeAbove: 10000 },
        siteUrl: 'https://shop.sunpowers.in', brand: 'Sunpowers', themeColor: '#1e8e3e', defaultLang: 'hi',
        searchPlaceholder: 'सोलर पैनल, इन्वर्टर, बैटरी खोजें', stickyTicker: true, whatsappButton: true,
        footerText: 'Sunpowers — सोलर पैनल, इन्वर्टर, बैटरी, पंप और कम्प्लीट सोलर सिस्टम। इंस्टॉलेशन सहित।',
        delivery: 'लखनऊ में फ़्री डिलीवरी • बाकी जगह ₹500 • ₹10,000 से ऊपर के ऑर्डर पर फ़्री',
        payments: {
          cod: { enabled: true, advancePct: 15, label: 'Cash on Delivery (15% एडवांस)' },
          upi: { enabled: true, upiId: 'Sunpowers@ybl', payeeName: 'Sunpowers', label: 'UPI पेमेंट (पूरा भुगतान)' }
        },
        social: { facebook: 'https://www.facebook.com/share/1HwbkZd1oK/', instagram: 'https://www.instagram.com/sunpowers.in', youtube: 'https://www.youtube.com/@sunpowers', gmb: 'https://maps.app.goo.gl/9r7jtxRPokG3yKVw8' },
        integrations: { ga4: '', metaPixel: '' }
      },
      sections: sections,
      products: products,
      slideshows: slideshows,
      services: { title: 'सर्विसेज़', items: [
        { id: 'sv1', icon: '🏠', title: 'साइट सर्वे', sub: 'घर/दुकान की छत का निरीक्षण', price: 'अभी बुक करें', bg: '#e8f5e9', linkType: 'form', link: '' },
        { id: 'sv2', icon: '🛠️', title: 'इंस्टॉलेशन व सर्विस', sub: 'ट्रेंड टेक्नीशियन, 5 साल फ़ोन सपोर्ट', price: 'साइट देखकर रेट', bg: '#fff8e1', linkType: 'whatsapp', link: 'नमस्ते, मुझे इंस्टॉलेशन/सर्विस चाहिए' },
        { id: 'sv3', icon: '📦', title: 'बल्क / डीलर ऑर्डर', sub: 'होलसेल रेट, GST बिल', price: 'स्पेशल रेट', bg: '#e3f2fd', linkType: 'form', link: '' },
        { id: 'sv4', icon: '📄', title: 'सब्सिडी सहायता', sub: 'सरकारी योजना आवेदन में मदद', price: '⚡ तुरंत सहायता', bg: '#fce4ec', linkType: 'section', link: 'sec_c9' }] },
      form: { title: 'अपनी ज़रूरत बताएं', subtitle: 'फ़ॉर्म भरें — हमारी टीम जल्द संपर्क करेगी', button: 'भेजें',
        types: ['घर के लिए सोलर सिस्टम', 'दुकान / फैक्ट्री के लिए सोलर', 'सोलर पंप (खेती)', 'बैटरी / इन्वर्टर', 'सर्विस / रिपेयर', 'डीलर / बल्क ऑर्डर', 'अन्य'] },
      howto: { title: 'ऑनलाइन ऑर्डर कैसे करें?', steps: [
        'होम पेज पर या 🔍 सर्च से अपना प्रोडक्ट चुनें।',
        'प्रोडक्ट पर क्लिक करके डिटेल, कीमत और फ़ोटो देखें।',
        '"कार्ट में डालें" बटन दबाएँ (या कार्ड पर + दबाएँ)।',
        'नीचे 🛒 कार्ट खोलें, मात्रा (Qty) चेक करें।',
        'नाम, मोबाइल नंबर और पूरा पता भरें।',
        'पेमेंट मोड चुनें और "ऑर्डर करें" दबाएँ — कन्फ़र्मेशन WhatsApp पर मिलेगा।'] },
      feedback: { title: 'ग्राहकों की राय', items: [] },
      videos: { title: 'हमारे वीडियो', items: [
        { id: 'vd1', title: 'सोलर सिस्टम इंस्टॉलेशन (लिंक बदलें)', url: '' },
        { id: 'vd2', title: 'ग्राहक अनुभव (लिंक बदलें)', url: '' },
        { id: 'vd3', title: 'सोलर पंप डेमो (लिंक बदलें)', url: '' }] },
      pages: SP.clone(SP.PAGES_DEF),
      layout: layout
    };
  };
})();
