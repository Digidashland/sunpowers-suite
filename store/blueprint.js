/* =====================================================================
   Sunpowers Project Blueprint — ek hi file CRM, Store aur Website teeno me chalti hai.
   - Location: browser ki "Allow location" (GPS) ya search; koi Google API key nahi chahiye.
   - Map: satellite tiles (key-free) par roof/ground ka area khud mark karein.
   - Panel layout, structure, inverter/ACDB/DCDB jagah, photos/video, PDF, quotation.
   Use: SPBlueprint.mount(el, { mode:'public'|'crm', whatsapp:'919621050636', onSubmit, onSave, ... })
   ===================================================================== */
(function () {
  'use strict';
  if (window.SPBlueprint) return;
  var D = document, WA_DEFAULT = '919621050636', DRAFT_KEY = 'sp_bp_draft';

  /* ---------- Hindi translations (English is the source text) ---------- */
  var HI = [
    ['Project Blueprint', 'प्रोजेक्ट ब्लूप्रिंट'], ['Free solar site survey — mark your roof or land, choose panels and structure, and get a downloadable blueprint.', 'मुफ़्त सोलर साइट सर्वे — अपनी छत या ज़मीन मार्क करें, पैनल और स्ट्रक्चर चुनें और ब्लूप्रिंट डाउनलोड करें।'],
    ['Location & Area', 'लोकेशन और एरिया'], ['Site details', 'साइट की जानकारी'], ['Panels & Structure', 'पैनल और स्ट्रक्चर'], ['Equipment', 'इक्विपमेंट'], ['Photos & Video', 'फ़ोटो और वीडियो'], ['Blueprint', 'ब्लूप्रिंट'],
    ['Use my GPS location', 'मेरी GPS लोकेशन लें'], ['Search place / address', 'जगह / पता खोजें'], ['Search', 'खोजें'], ['Satellite', 'सैटेलाइट'], ['Street map', 'स्ट्रीट मैप'],
    ['Draw area', 'एरिया बनाएँ'], ['Move map', 'मैप हिलाएँ'], ['Undo point', 'आख़िरी पॉइंट हटाएँ'], ['Clear', 'साफ़ करें'],
    ['Tap on the map to mark each corner of your roof / land. Drag a point to adjust it.', 'अपनी छत / ज़मीन का हर कोना मैप पर टैप करके मार्क करें। पॉइंट को खींचकर ठीक कर सकते हैं।'],
    ['Or enter the area manually (sq ft)', 'या एरिया हाथ से लिखें (sq ft)'], ['Use this area', 'यही एरिया लें'],
    ['Open in Google Maps (satellite)', 'Google Maps में खोलें (सैटेलाइट)'], ['Open Google 3D view', 'Google 3D व्यू खोलें'], ['Show Google view here', 'Google व्यू यहीं दिखाएँ'], ['Back to drawing map', 'ड्रॉइंग मैप पर वापस'],
    ['Area marked', 'मार्क किया एरिया'], ['sq ft', 'sq ft'], ['sq m', 'sq m'], ['Perimeter', 'परिधि'], ['Location', 'लोकेशन'], ['Not set', 'तय नहीं'],
    ['Allow location access in your browser to use GPS, or search the address.', 'GPS के लिए ब्राउज़र में लोकेशन की अनुमति दें, या पता खोजें।'], ['Place not found. Try a nearby landmark or city.', 'जगह नहीं मिली। पास का लैंडमार्क या शहर लिखकर देखें।'],
    ['Imagery © Esri, Maxar, Earthstar Geographics', 'इमेजरी © Esri, Maxar, Earthstar Geographics'], ['Map © OpenStreetMap contributors', 'मैप © OpenStreetMap contributors'],
    ['Where will the plant be installed?', 'प्लांट कहाँ लगेगा?'], ['Roof (RCC)', 'छत (RCC)'], ['Ground / open land', 'ज़मीन / खुली जगह'], ['Tin shed', 'टिन शेड'],
    ['Number of floors', 'मंज़िलें'], ['Parapet height (m)', 'पैरापेट ऊँचाई (m)'], ['Roof tilt for panels (degrees)', 'पैनल का झुकाव (डिग्री)'], ['Shadow-free usable area (%)', 'छाया-मुक्त उपयोगी एरिया (%)'],
    ['Obstacles on roof', 'छत पर रुकावटें'], ['Water tank', 'पानी की टंकी'], ['Staircase room', 'सीढ़ी का कमरा'], ['AC / outdoor units', 'AC / आउटडोर यूनिट'], ['Trees / tall buildings nearby', 'पास के पेड़ / ऊँची बिल्डिंग'],
    ['Slope of land', 'ज़मीन की ढलान'], ['Flat', 'समतल'], ['Mild slope', 'हल्की ढलान'], ['Steep slope', 'तेज़ ढलान'], ['Soil type', 'मिट्टी का प्रकार'], ['Normal', 'सामान्य'], ['Hard / rocky', 'सख़्त / पथरीली'], ['Sandy', 'रेतीली'], ['Black cotton', 'काली मिट्टी'],
    ['Fencing available', 'फ़ेंसिंग है'], ['Distance to electric meter (m)', 'बिजली मीटर से दूरी (m)'], ['Sheet type', 'शीट का प्रकार'], ['GI / metal sheet', 'GI / मेटल शीट'], ['Cement sheet', 'सीमेंट शीट'], ['Polycarbonate / other', 'पॉलीकार्बोनेट / अन्य'],
    ['Roof pitch (degrees)', 'छत की ढलान (डिग्री)'], ['Purlin gap (mm)', 'पर्लिन गैप (mm)'], ['Shed age (years)', 'शेड की उम्र (साल)'], ['Shed strength', 'शेड की मज़बूती'], ['Good', 'अच्छी'], ['Needs engineer check', 'इंजीनियर चेक चाहिए'],
    ['Roof faces', 'छत किस तरफ़'], ['South', 'दक्षिण'], ['South-East', 'दक्षिण-पूर्व'], ['South-West', 'दक्षिण-पश्चिम'], ['East', 'पूर्व'], ['West', 'पश्चिम'], ['North', 'उत्तर'], ['Flat roof', 'सपाट छत'],
    ['Monthly electricity bill (₹)', 'मासिक बिजली बिल (₹)'], ['Target capacity (kW) — optional', 'लक्ष्य क्षमता (kW) — वैकल्पिक'], ['Electric connection', 'बिजली कनेक्शन'], ['Single phase', 'सिंगल फ़ेज़'], ['Three phase', 'थ्री फ़ेज़'],
    ['Panel size', 'पैनल साइज़'], ['Custom panel', 'कस्टम पैनल'], ['Panel watt', 'पैनल वॉट'], ['Length (mm)', 'लंबाई (mm)'], ['Width (mm)', 'चौड़ाई (mm)'], ['Structure type', 'स्ट्रक्चर का प्रकार'], ['Sunpowers recommended', 'Sunpowers की सलाह'],
    ['Pre-GI', 'Pre-GI'], ['HDGI', 'HDGI'], ['Cyclone', 'Cyclone'], ['Cyclone Pro GISS', 'Cyclone Pro GISS'],
    ['Pre-galvanised pipes — economical, best for dry, low-wind places.', 'प्री-गैल्वनाइज़्ड पाइप — किफ़ायती, सूखी और कम हवा वाली जगह के लिए।'],
    ['Hot-dip galvanised — long life, good for most homes and shops.', 'हॉट-डिप गैल्वनाइज़्ड — लंबी उम्र, ज़्यादातर घर और दुकान के लिए।'],
    ['Wind-load designed structure for open and high-wind locations.', 'खुली और तेज़ हवा वाली जगह के लिए विंड-लोड डिज़ाइन स्ट्रक्चर।'],
    ['Heavy-duty hot-dip galvanised structure with stainless-steel hardware — our top choice for long life and strong wind.', 'हेवी-ड्यूटी हॉट-डिप गैल्वनाइज़्ड स्ट्रक्चर और स्टेनलेस-स्टील फ़िटिंग — लंबी उम्र और तेज़ हवा के लिए हमारी पहली पसंद।'],
    ['Place inverter, ACDB and DCDB', 'इन्वर्टर, ACDB और DCDB की जगह'], ['Inverter', 'इन्वर्टर'], ['ACDB', 'ACDB'], ['DCDB', 'DCDB'], ['Earthing pit', 'अर्थिंग पिट'],
    ['Tap on the layout below to place the selected item.', 'चुनी हुई चीज़ रखने के लिए नीचे लेआउट पर टैप करें।'], ['Note for installer (optional)', 'इंस्टॉलर के लिए नोट (वैकल्पिक)'], ['Not placed yet', 'अभी नहीं रखा'], ['Placed', 'रख दिया'],
    ['Take photos of the site (roof, shadow areas, meter, DB). The location and time are stamped on each photo.', 'साइट की फ़ोटो लें (छत, छाया वाली जगह, मीटर, DB)। हर फ़ोटो पर लोकेशन और समय अंकित होता है।'],
    ['Add photo', 'फ़ोटो जोड़ें'], ['Record video (max 30 seconds)', 'वीडियो रिकॉर्ड करें (अधिकतम 30 सेकंड)'], ['Video must be 30 seconds or shorter.', 'वीडियो 30 सेकंड या उससे छोटा होना चाहिए।'],
    ['Photos and video stay on your phone — nothing is uploaded to our server. Send them to our engineer on WhatsApp using the button on the last step.', 'फ़ोटो और वीडियो आपके फ़ोन में ही रहते हैं — हमारे सर्वर पर कुछ अपलोड नहीं होता। आख़िरी स्टेप के बटन से उन्हें WhatsApp पर हमारे इंजीनियर को भेजें।'], ['Remove', 'हटाएँ'],
    ['Back', 'पीछे'], ['Next', 'आगे'], ['Please mark the area on the map (at least 3 points) or enter it manually.', 'कृपया मैप पर एरिया मार्क करें (कम से कम 3 पॉइंट) या हाथ से लिखें।'],
    ['Your solar plant plan', 'आपके सोलर प्लांट का प्लान'], ['Panels that fit', 'लगने वाले पैनल'], ['Plant size', 'प्लांट की क्षमता'], ['Estimated units / year', 'अनुमानित यूनिट / साल'], ['Area used', 'उपयोग हुआ एरिया'], ['Cable run (approx.)', 'केबल (लगभग)'],
    ['Suggested size from your bill', 'आपके बिल के हिसाब से सुझाव'], ['Download blueprint PDF', 'ब्लूप्रिंट PDF डाउनलोड करें'], ['Get quotation according to this blueprint', 'इस ब्लूप्रिंट के अनुसार कोटेशन पाएँ'],
    ['Want to Edit Blue Print By Experts/Engineers', 'ब्लूप्रिंट विशेषज्ञ / इंजीनियर से एडिट करवाना है'], ['Chat with our engineer on WhatsApp — they will make it exactly accurate.', 'WhatsApp पर हमारे इंजीनियर से बात करें — वे इसे बिल्कुल सटीक करेंगे।'],
    ['This is a planning estimate from your inputs. The final design is confirmed by a Sunpowers engineer after a site survey.', 'यह आपकी दी हुई जानकारी से बना प्लानिंग अनुमान है। अंतिम डिज़ाइन साइट सर्वे के बाद Sunpowers इंजीनियर तय करते हैं।'],
    ['Your name', 'आपका नाम'], ['Mobile number', 'मोबाइल नंबर'], ['City / village', 'शहर / गाँव'], ['Anything we should know? (optional)', 'कुछ और बताना है? (वैकल्पिक)'], ['Send request', 'रिक्वेस्ट भेजें'], ['Cancel', 'रद्द करें'],
    ['Thank you! Our team will contact you with a quotation based on this blueprint.', 'धन्यवाद! हमारी टीम इस ब्लूप्रिंट के आधार पर कोटेशन के लिए आपसे संपर्क करेगी।'], ['Enter your name and a valid 10-digit mobile number.', 'अपना नाम और सही 10 अंकों का मोबाइल नंबर लिखें।'],
    ['Save blueprint', 'ब्लूप्रिंट सेव करें'], ['Save and create lead', 'सेव करें और लीड बनाएँ'], ['Customer name', 'कस्टमर का नाम'], ['Saved ✔', 'सेव हो गया ✔'], ['Start a new blueprint', 'नया ब्लूप्रिंट शुरू करें'],
    ['Preparing PDF…', 'PDF बन रही है…'], ['Could not create the PDF.', 'PDF नहीं बन पाई।'], ['Sending…', 'भेज रहे हैं…'], ['Getting location…', 'लोकेशन ले रहे हैं…'], ['Saving…', 'सेव हो रहा है…']
  ];
  function addI18n() { try { if (window.SPI18N && typeof SPI18N.add === 'function') SPI18N.add(HI); } catch (e) {} }
  addI18n();

  /* ---------- data tables ---------- */
  var PANELS = [
    { id: 'p335', name: '335 W Poly (72 cell)', w: 335, l: 1956, wd: 992 },
    { id: 'p440', name: '440 W Mono PERC', w: 440, l: 2094, wd: 1038 },
    { id: 'p540', name: '540 W Mono PERC', w: 540, l: 2278, wd: 1134 },
    { id: 'p545', name: '545 W Mono PERC', w: 545, l: 2279, wd: 1134 },
    { id: 'p550', name: '550 W Bifacial', w: 550, l: 2278, wd: 1134 },
    { id: 'p575', name: '575 W TOPCon', w: 575, l: 2278, wd: 1134 },
    { id: 'p600', name: '600 W TOPCon', w: 600, l: 2384, wd: 1303 },
    { id: 'custom', name: 'Custom panel', w: 540, l: 2278, wd: 1134 }
  ];
  var STRUCT = [
    { id: 'Pre-GI', d: 'Pre-galvanised pipes — economical, best for dry, low-wind places.' },
    { id: 'HDGI', d: 'Hot-dip galvanised — long life, good for most homes and shops.' },
    { id: 'Cyclone', d: 'Wind-load designed structure for open and high-wind locations.' },
    { id: 'Cyclone Pro GISS', d: 'Heavy-duty hot-dip galvanised structure with stainless-steel hardware — our top choice for long life and strong wind.', rec: true }
  ];
  var STEPS = ['Location & Area', 'Site details', 'Panels & Structure', 'Equipment', 'Photos & Video', 'Blueprint'];

  /* ---------- tiny helpers ---------- */
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function num(v) { v = parseFloat(v); return isFinite(v) ? v : 0; }
  function r2(v) { return Math.round(v * 100) / 100; }
  function clone(o) { return JSON.parse(JSON.stringify(o)); }
  function lsGet(k) { try { return JSON.parse(localStorage.getItem(k)); } catch (e) { return null; } }
  function lsSet(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} }
  function lsDel(k) { try { localStorage.removeItem(k); } catch (e) {} }
  function waNum(n) { n = String(n || WA_DEFAULT).replace(/\D/g, ''); if (n.length === 10) n = '91' + n; if (n.length === 11 && n[0] === '0') n = '91' + n.slice(1); return n; }

  /* ---------- geometry ---------- */
  var G = {};
  G.toLocal = function (pts) {
    var la = 0, ln = 0; pts.forEach(function (p) { la += p[0]; ln += p[1]; }); la /= pts.length; ln /= pts.length;
    var c = Math.cos(la * Math.PI / 180);
    return pts.map(function (p) { return [(p[1] - ln) * 111320 * c, (p[0] - la) * 110540]; });
  };
  G.area = function (L) { var a = 0; for (var i = 0; i < L.length; i++) { var j = (i + 1) % L.length; a += L[i][0] * L[j][1] - L[j][0] * L[i][1]; } return Math.abs(a) / 2; };
  G.perimeter = function (L) { var s = 0; for (var i = 0; i < L.length; i++) { var j = (i + 1) % L.length; s += Math.hypot(L[j][0] - L[i][0], L[j][1] - L[i][1]); } return s; };
  G.inside = function (pt, L) { var x = pt[0], y = pt[1], c = false; for (var i = 0, j = L.length - 1; i < L.length; j = i++) { var xi = L[i][0], yi = L[i][1], xj = L[j][0], yj = L[j][1]; if (((yi > y) !== (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi)) c = !c; } return c; };
  G.bbox = function (L) { var a = [1e9, 1e9, -1e9, -1e9]; L.forEach(function (p) { a[0] = Math.min(a[0], p[0]); a[1] = Math.min(a[1], p[1]); a[2] = Math.max(a[2], p[0]); a[3] = Math.max(a[3], p[1]); }); return a; };
  /* rectangle polygon (lat/lng) of a given area in sq ft around a point — for manual area entry */
  G.rectFromArea = function (lat, lng, sqft) {
    var sqm = Math.max(1, sqft) * 0.092903, w = Math.sqrt(sqm * 1.5), h = sqm / w, c = Math.cos(lat * Math.PI / 180);
    var dx = w / 2 / (111320 * c), dy = h / 2 / 110540;
    return [[lat - dy, lng - dx], [lat - dy, lng + dx], [lat + dy, lng + dx], [lat + dy, lng - dx]].map(function (p) { return [+p[0].toFixed(7), +p[1].toFixed(7)]; });
  };
  /* panel layout — rows run east-west (face south). Tries portrait and landscape, keeps the better one. */
  G.layout = function (L, o) {
    var best = null;
    [false, true].forEach(function (land) {
      var pw = (land ? o.l : o.wd) / 1000, pl = (land ? o.wd : o.l) / 1000, tilt = o.flush ? 0 : (o.tilt || 15) * Math.PI / 180;
      var fh = o.flush ? pl : pl * Math.cos(tilt), alt = Math.max(15, 90 - Math.abs(o.lat || 26.8) - 23.4) * Math.PI / 180;
      var pitch = o.flush ? pl + 0.03 : pl * Math.cos(tilt) + pl * Math.sin(tilt) / Math.tan(alt) + 0.05;
      var bb = G.bbox(L), sb = o.setback == null ? 0.5 : o.setback, out = [], gap = 0.03;
      for (var y = bb[1] + sb; y + fh <= bb[3] - sb + 1e-9; y += pitch) {
        for (var x = bb[0] + sb; x + pw <= bb[2] - sb + 1e-9; x += pw + gap) {
          var ok = true, pts = [[x - sb, y - sb], [x + pw + sb, y - sb], [x + pw + sb, y + fh + sb], [x - sb, y + fh + sb]];
          for (var k = 0; k < 4; k++) if (!G.inside(pts[k], L)) { ok = false; break; }
          if (ok) out.push({ x: r2(x), y: r2(y), w: r2(pw), h: r2(fh) });
        }
      }
      if (!best || out.length > best.panels.length) best = { panels: out, land: land, pitch: r2(pitch) };
    });
    return best;
  };
  G.PANELS = PANELS; G.STRUCT = STRUCT;

  /* ---------- blueprint state ---------- */
  function emptyBp() {
    return { v: 1, created: new Date().toISOString(), location: null, area: null,
      site: { type: 'roof', floors: 1, parapet: 1, tilt: 15, usable: 80, obstacles: [], direction: 'South', slope: 'Flat', soil: 'Normal', fence: false, meter_dist: 20, sheet: 'GI / metal sheet', pitch: 10, purlin: 1000, age: 5, strength: 'Good', bill: '', target_kw: '', phase: 'Single phase' },
      panel: { id: 'p540', w: 540, l: 2278, wd: 1134 }, structure: { type: 'Cyclone Pro GISS', recommended: true },
      equipment: { inverter: null, acdb: null, dcdb: null, earthing: null, note: '' }, result: null, photos: [], video: null };
  }
  function derive(bp) {
    if (!bp.area || !bp.area.points || bp.area.points.length < 3) { bp.result = null; return bp; }
    var L = G.toLocal(bp.area.points), sqm = G.area(L); bp.area.sqm = r2(sqm); bp.area.sqft = Math.round(sqm / 0.092903); bp.area.perimeter_m = r2(G.perimeter(L));
    var s = bp.site, p = bp.panel, lat = bp.location ? bp.location.lat : 26.8;
    var flush = s.type === 'tinshed', tilt = s.type === 'ground' ? 25 : (flush ? 0 : num(s.tilt) || 15);
    var lay = G.layout(L, { l: p.l, wd: p.wd, tilt: tilt, flush: flush, lat: lat, setback: s.type === 'ground' ? 1 : 0.5 });
    var usable = Math.min(100, Math.max(10, num(s.usable) || 80)), fit = Math.floor(lay.panels.length * usable / 100);
    var tgt = num(s.target_kw) > 0 ? Math.max(1, Math.round(num(s.target_kw) * 1000 / p.w)) : 0, n = tgt ? Math.min(fit, tgt) : fit;
    var kw = r2(n * p.w / 1000), shown = lay.panels.slice(0, n);
    var gx = 0, gy = 0; shown.forEach(function (q) { gx += q.x + q.w / 2; gy += q.y + q.h / 2; }); if (shown.length) { gx /= shown.length; gy /= shown.length; }
    var e = bp.equipment, cab = 0;
    if (shown.length && e.dcdb) cab += (Math.abs(gx - e.dcdb.x) + Math.abs(gy - e.dcdb.y)) * 1.15;
    if (e.dcdb && e.inverter) cab += (Math.abs(e.dcdb.x - e.inverter.x) + Math.abs(e.dcdb.y - e.inverter.y)) * 1.15;
    if (e.inverter && e.acdb) cab += (Math.abs(e.inverter.x - e.acdb.x) + Math.abs(e.inverter.y - e.acdb.y)) * 1.15;
    if (e.acdb) cab += num(s.meter_dist) || 15;
    var billKw = num(s.bill) > 0 ? r2((num(s.bill) / 7.5) / (30 * 4)) : 0;
    bp.result = { panels: n, fits: lay.panels.length, kw: kw, units_year: Math.round(kw * 1450), used_sqm: r2(n * (lay.panels[0] ? lay.panels[0].w * lay.panels[0].h : 0)), orientation: lay.land ? 'landscape' : 'portrait',
      row_pitch_m: lay.pitch, cable_m: Math.round(cab), bill_kw: billKw, layout: shown, local: L.map(function (q) { return [r2(q[0]), r2(q[1])]; }) };
    return bp;
  }
  G.derive = derive; G.emptyBp = emptyBp;

  /* ---------- layout drawing (SVG string, used on screen and in the PDF) ---------- */
  function layoutSvg(bp, o) {
    o = o || {}; var W = o.w || 640, H = o.h || 440, pad = 34;
    if (!bp.result || !bp.result.local) return '';
    var L = bp.result.local, bb = G.bbox(L), bw = Math.max(1, bb[2] - bb[0]), bh = Math.max(1, bb[3] - bb[1]);
    var sc = Math.min((W - pad * 2) / bw, (H - pad * 2) / bh), ox = (W - bw * sc) / 2 - bb[0] * sc, oy = (H + bh * sc) / 2 + bb[1] * sc;
    function X(x) { return ox + x * sc; } function Y(y) { return oy - y * sc; }
    var s = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + W + ' ' + H + '" width="' + W + '" height="' + H + '" font-family="Arial,Helvetica,sans-serif"><rect width="' + W + '" height="' + H + '" fill="#f7faf6"/>';
    s += '<polygon points="' + L.map(function (p) { return X(p[0]).toFixed(1) + ',' + Y(p[1]).toFixed(1); }).join(' ') + '" fill="#e9efe6" stroke="#2f7d4f" stroke-width="2" stroke-dasharray="7 4"/>';
    bp.result.layout.forEach(function (q) { s += '<rect x="' + X(q.x).toFixed(1) + '" y="' + Y(q.y + q.h).toFixed(1) + '" width="' + (q.w * sc).toFixed(1) + '" height="' + (q.h * sc).toFixed(1) + '" fill="#1d4f91" stroke="#cfe0f7" stroke-width="0.6"/>'; });
    for (var i = 0; i < L.length; i++) { var j = (i + 1) % L.length, d = Math.hypot(L[j][0] - L[i][0], L[j][1] - L[i][1]); if (d < 0.5) continue; s += '<text x="' + X((L[i][0] + L[j][0]) / 2).toFixed(1) + '" y="' + (Y((L[i][1] + L[j][1]) / 2) - 5).toFixed(1) + '" font-size="11" fill="#0b2e1f" text-anchor="middle" font-weight="bold">' + d.toFixed(1) + ' m</text>'; }
    var eq = bp.equipment || {}, cols = { inverter: ['INV', '#d97706'], acdb: ['ACDB', '#7c3aed'], dcdb: ['DCDB', '#dc2626'], earthing: ['E', '#0f766e'] };
    Object.keys(cols).forEach(function (k) { var p = eq[k]; if (!p) return; s += '<g><rect x="' + (X(p.x) - 17).toFixed(1) + '" y="' + (Y(p.y) - 10).toFixed(1) + '" width="34" height="20" rx="4" fill="' + cols[k][1] + '"/><text x="' + X(p.x).toFixed(1) + '" y="' + (Y(p.y) + 4).toFixed(1) + '" font-size="10" fill="#fff" text-anchor="middle" font-weight="bold">' + cols[k][0] + '</text></g>'; });
    s += '<text x="' + (W / 2) + '" y="' + (H / 2 + 14) + '" font-size="30" font-weight="bold" text-anchor="middle" fill="#0b2e1f" fill-opacity="0.07" transform="rotate(-25 ' + (W / 2) + ' ' + (H / 2) + ')">Powered by Digidashland.in</text>';
    s += '<g transform="translate(' + (W - 40) + ',34)"><polygon points="0,-20 7,6 0,2 -7,6" fill="#0b2e1f"/><text y="22" font-size="11" text-anchor="middle" fill="#0b2e1f" font-weight="bold">N</text></g>';
    var bar = Math.pow(10, Math.floor(Math.log10(bw / 3))) || 1; if (bar * sc < 30) bar *= 2;
    s += '<g transform="translate(14,' + (H - 16) + ')"><rect width="' + (bar * sc).toFixed(1) + '" height="5" fill="#0b2e1f"/><text y="-4" font-size="10" fill="#0b2e1f">' + bar + ' m</text></g>';
    s += '<text x="' + (W / 2) + '" y="16" text-anchor="middle" font-size="12" fill="#0b2e1f" font-weight="bold">' + esc(bp.result.panels) + ' panels · ' + esc(bp.result.kw) + ' kW · ' + esc(bp.structure.type) + '</text>';
    s += '</svg>';
    s = s.replace(/<svg /, '<svg data-sc="' + sc.toFixed(5) + '" data-ox="' + ox.toFixed(2) + '" data-oy="' + oy.toFixed(2) + '" ');
    return s;
  }
  G.layoutSvg = layoutSvg;

  /* ---------- slippy map (key-free satellite tiles) ---------- */
  function SlipMap(el, opt) {
    var self = this, TS = 256, tiles = {}, z = opt.zoom || 18, lat = opt.lat, lng = opt.lng, w = 600, h = 380, layer = 'sat', pts = (opt.points || []).slice(), mode = 'draw';
    el.classList.add('bp-map'); el.innerHTML = '<div class="bp-tiles"></div><svg class="bp-ov"></svg><div class="bp-zoom"><button type="button" data-z="1" aria-label="Zoom in">+</button><button type="button" data-z="-1" aria-label="Zoom out">−</button></div><div class="bp-attr"></div>';
    var tl = el.querySelector('.bp-tiles'), ov = el.querySelector('.bp-ov'), at = el.querySelector('.bp-attr');
    function wp(la, ln, zz) { var s = TS * Math.pow(2, zz), sn = Math.sin(la * Math.PI / 180); return [(ln + 180) / 360 * s, (0.5 - Math.log((1 + sn) / (1 - sn)) / (4 * Math.PI)) * s]; }
    function ll(x, y, zz) { var s = TS * Math.pow(2, zz), n = Math.PI - 2 * Math.PI * y / s; return [180 / Math.PI * Math.atan(0.5 * (Math.exp(n) - Math.exp(-n))), x / s * 360 - 180]; }
    function size() { var r = el.getBoundingClientRect(); w = r.width || 600; h = r.height || 380; ov.setAttribute('viewBox', '0 0 ' + w + ' ' + h); }
    function url(zz, x, y) { return layer === 'sat' ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/' + zz + '/' + y + '/' + x : 'https://tile.openstreetmap.org/' + zz + '/' + x + '/' + y + '.png'; }
    function draw() {
      size(); var c = wp(lat, lng, z), x0 = c[0] - w / 2, y0 = c[1] - h / 2, n = Math.pow(2, z), keep = {};
      for (var tx = Math.floor(x0 / TS); tx <= Math.floor((x0 + w) / TS); tx++) for (var ty = Math.floor(y0 / TS); ty <= Math.floor((y0 + h) / TS); ty++) {
        if (ty < 0 || ty >= n) continue; var wx = ((tx % n) + n) % n, key = layer + '/' + z + '/' + wx + '/' + ty; keep[key + '@' + tx] = 1;
        var im = tiles[key + '@' + tx]; if (!im) { im = D.createElement('img'); im.alt = ''; im.draggable = false; im.referrerPolicy = 'no-referrer'; im.src = url(z, wx, ty); im.onerror = function () { this.style.visibility = 'hidden'; }; tl.appendChild(im); tiles[key + '@' + tx] = im; }
        im.style.cssText = 'left:' + Math.round(tx * TS - x0) + 'px;top:' + Math.round(ty * TS - y0) + 'px';
      }
      Object.keys(tiles).forEach(function (k) { if (!keep[k]) { tiles[k].remove(); delete tiles[k]; } });
      at.textContent = layer === 'sat' ? 'Imagery © Esri, Maxar, Earthstar Geographics' : 'Map © OpenStreetMap contributors';
      drawPoly(x0, y0);
    }
    function px(p, x0, y0) { var q = wp(p[0], p[1], z); return [q[0] - x0, q[1] - y0]; }
    function drawPoly(x0, y0) {
      var c = wp(lat, lng, z); x0 = c[0] - w / 2; y0 = c[1] - h / 2; var P = pts.map(function (p) { return px(p, x0, y0); }), s = '';
      if (P.length >= 3) s += '<polygon points="' + P.map(function (q) { return q[0].toFixed(1) + ',' + q[1].toFixed(1); }).join(' ') + '" fill="rgba(245,166,35,.28)" stroke="#f5a623" stroke-width="2.5"/>';
      else if (P.length === 2) s += '<line x1="' + P[0][0] + '" y1="' + P[0][1] + '" x2="' + P[1][0] + '" y2="' + P[1][1] + '" stroke="#f5a623" stroke-width="2.5"/>';
      P.forEach(function (q, i) { s += '<circle data-i="' + i + '" cx="' + q[0].toFixed(1) + '" cy="' + q[1].toFixed(1) + '" r="9" fill="#fff" stroke="#f5a623" stroke-width="3" style="pointer-events:all;cursor:grab"/>'; });
      if (opt.marker) { var m = px(opt.marker, x0, y0); s += '<g transform="translate(' + m[0].toFixed(1) + ',' + m[1].toFixed(1) + ')"><path d="M0 0C-8-12-10-18 0-26 10-18 8-12 0 0Z" fill="#dc2626"/><circle cy="-17" r="3.5" fill="#fff"/></g>'; }
      ov.innerHTML = s;
    }
    var drag = null, ptrs = {}, pinch = 0;
    function changed() { if (opt.onChange) opt.onChange(pts.slice()); }
    el.addEventListener('pointerdown', function (e) {
      if (e.target.closest('.bp-zoom')) return; ptrs[e.pointerId] = [e.clientX, e.clientY];
      var vi = e.target.getAttribute && e.target.getAttribute('data-i');
      if (Object.keys(ptrs).length === 2) { var a = Object.keys(ptrs).map(function (k) { return ptrs[k]; }); pinch = Math.hypot(a[0][0] - a[1][0], a[0][1] - a[1][1]); drag = null; return; }
      drag = { x: e.clientX, y: e.clientY, moved: 0, vi: vi == null ? null : +vi, lat: lat, lng: lng }; try { el.setPointerCapture(e.pointerId); } catch (x) {}
    });
    el.addEventListener('pointermove', function (e) {
      if (!ptrs[e.pointerId]) return; ptrs[e.pointerId] = [e.clientX, e.clientY];
      if (Object.keys(ptrs).length === 2) { var a = Object.keys(ptrs).map(function (k) { return ptrs[k]; }), d = Math.hypot(a[0][0] - a[1][0], a[0][1] - a[1][1]); if (pinch && Math.abs(d - pinch) > 40) { self.zoom(d > pinch ? 1 : -1); pinch = d; } return; }
      if (!drag) return; var dx = e.clientX - drag.x, dy = e.clientY - drag.y; drag.moved = Math.max(drag.moved, Math.hypot(dx, dy));
      if (drag.vi != null) { var r = el.getBoundingClientRect(), c = wp(lat, lng, z), q = ll(c[0] - w / 2 + (e.clientX - r.left), c[1] - h / 2 + (e.clientY - r.top), z); pts[drag.vi] = [+q[0].toFixed(7), +q[1].toFixed(7)]; drawPoly(); return; }
      if (drag.moved > 4 || mode === 'move') { var c0 = wp(drag.lat, drag.lng, z), q2 = ll(c0[0] - dx, c0[1] - dy, z); lat = q2[0]; lng = q2[1]; draw(); }
    });
    function up(e) {
      delete ptrs[e.pointerId]; pinch = 0; if (!drag) return; var d = drag; drag = null;
      if (d.vi != null) { changed(); return; }
      if (d.moved <= 4 && mode === 'draw') { var r = el.getBoundingClientRect(), c = wp(lat, lng, z), q = ll(c[0] - w / 2 + (e.clientX - r.left), c[1] - h / 2 + (e.clientY - r.top), z); pts.push([+q[0].toFixed(7), +q[1].toFixed(7)]); drawPoly(); changed(); }
    }
    el.addEventListener('pointerup', up); el.addEventListener('pointercancel', function (e) { delete ptrs[e.pointerId]; drag = null; });
    el.addEventListener('wheel', function (e) { e.preventDefault(); self.zoom(e.deltaY < 0 ? 1 : -1); }, { passive: false });
    el.querySelector('.bp-zoom').addEventListener('click', function (e) { var b = e.target.closest('button'); if (b) self.zoom(+b.getAttribute('data-z')); });
    self.zoom = function (d) { z = Math.max(3, Math.min(19, z + d)); draw(); };
    self.setView = function (la, ln, zz) { lat = la; lng = ln; if (zz) z = zz; draw(); };
    self.setLayer = function (l) { layer = l; Object.keys(tiles).forEach(function (k) { tiles[k].remove(); }); tiles = {}; draw(); };
    self.setMode = function (m) { mode = m; el.style.cursor = m === 'draw' ? 'crosshair' : 'grab'; };
    self.setMarker = function (m) { opt.marker = m; drawPoly(); };
    self.undo = function () { pts.pop(); drawPoly(); changed(); };
    self.clear = function () { pts = []; drawPoly(); changed(); };
    self.setPoints = function (p) { pts = (p || []).slice(); drawPoly(); changed(); };
    self.points = function () { return pts.slice(); };
    self.fit = function () { if (pts.length < 2) return; var la = pts.map(function (p) { return p[0]; }), ln = pts.map(function (p) { return p[1]; }); lat = (Math.min.apply(0, la) + Math.max.apply(0, la)) / 2; lng = (Math.min.apply(0, ln) + Math.max.apply(0, ln)) / 2; size();
      for (var zz = 19; zz > 3; zz--) { var a = wp(Math.max.apply(0, la), Math.min.apply(0, ln), zz), b = wp(Math.min.apply(0, la), Math.max.apply(0, ln), zz); if (Math.abs(b[0] - a[0]) < w * 0.7 && Math.abs(b[1] - a[1]) < h * 0.7) { z = zz; break; } } draw(); };
    self.center = function () { return { lat: lat, lng: lng, z: z }; };
    self.setMode('draw'); draw(); self.redraw = draw;
    if (window.ResizeObserver) { try { new ResizeObserver(function () { draw(); }).observe(el); } catch (e) {} }
  }

  /* ---------- photo helpers ---------- */
  function getPos(timeout) {
    return new Promise(function (res) {
      if (!navigator.geolocation) return res(null);
      navigator.geolocation.getCurrentPosition(function (p) { res({ lat: +p.coords.latitude.toFixed(6), lng: +p.coords.longitude.toFixed(6), acc: Math.round(p.coords.accuracy || 0) }); }, function () { res(null); }, { enableHighAccuracy: true, timeout: timeout || 12000, maximumAge: 30000 });
    });
  }
  function shrinkPhoto(file, stamp) {
    return new Promise(function (res, rej) {
      var fr = new FileReader(); fr.onerror = function () { rej(new Error('read')); };
      fr.onload = function () {
        var im = new Image(); im.onerror = function () { rej(new Error('image')); };
        im.onload = function () {
          var m = 900, s = Math.min(1, m / Math.max(im.width, im.height)), c = D.createElement('canvas'); c.width = Math.round(im.width * s); c.height = Math.round(im.height * s);
          var x = c.getContext('2d'); x.drawImage(im, 0, 0, c.width, c.height);
          if (stamp) { x.fillStyle = 'rgba(0,0,0,.55)'; x.fillRect(0, c.height - 24, c.width, 24); x.fillStyle = '#fff'; x.font = '13px Arial'; x.fillText(stamp, 8, c.height - 8); }
          res(c.toDataURL('image/jpeg', 0.62));
        };
        im.src = fr.result;
      };
      fr.readAsDataURL(file);
    });
  }

  /* ---------- PDF (pdf-lib) ---------- */
  function loadScript(src) {
    return new Promise(function (res, rej) {
      if (window.PDFLib) return res();
      var s = D.createElement('script'); s.src = src; s.onload = function () { res(); }; s.onerror = function () { rej(new Error('pdf lib missing')); }; D.head.appendChild(s);
    });
  }
  function ascii(t) { return String(t == null ? '' : t).replace(/₹/g, 'Rs.').replace(/[–—]/g, '-').replace(/[^\x20-\x7E]/g, '?'); }
  function svgToPng(svg, w, h) {
    return new Promise(function (res, rej) {
      var blob = new Blob([svg], { type: 'image/svg+xml;charset=utf-8' }), u = URL.createObjectURL(blob), im = new Image();
      im.onload = function () { var c = D.createElement('canvas'); c.width = w * 2; c.height = h * 2; var x = c.getContext('2d'); x.fillStyle = '#fff'; x.fillRect(0, 0, c.width, c.height); x.drawImage(im, 0, 0, c.width, c.height); URL.revokeObjectURL(u); c.toBlob(function (b) { b.arrayBuffer().then(res, rej); }, 'image/png'); };
      im.onerror = function () { URL.revokeObjectURL(u); rej(new Error('svg')); }; im.src = u;
    });
  }
  async function makePdf(bp, o) {
    await loadScript(o.pdfLibUrl || 'pdf-lib.min.js');
    var P = window.PDFLib, doc = await P.PDFDocument.create(), F = await doc.embedFont(P.StandardFonts.Helvetica), B = await doc.embedFont(P.StandardFonts.HelveticaBold);
    var green = P.rgb(0.043, 0.18, 0.12), amber = P.rgb(0.96, 0.65, 0.14), grey = P.rgb(0.35, 0.4, 0.37);
    var pg = doc.addPage([595, 842]), y = 842;
    pg.drawRectangle({ x: 0, y: 842 - 70, width: 595, height: 70, color: green });
    pg.drawText('SUNPOWERS', { x: 36, y: 842 - 36, size: 22, font: B, color: P.rgb(1, 1, 1) });
    pg.drawText('Solar Site Blueprint', { x: 36, y: 842 - 56, size: 12, font: F, color: amber });
    pg.drawText(ascii(new Date(bp.created || Date.now()).toLocaleDateString('en-IN')), { x: 595 - 120, y: 842 - 40, size: 10, font: F, color: P.rgb(1, 1, 1) });
    y = 842 - 100;
    function head(t) { pg.drawText(ascii(t), { x: 36, y: y, size: 12, font: B, color: green }); pg.drawLine({ start: { x: 36, y: y - 4 }, end: { x: 559, y: y - 4 }, thickness: 0.8, color: amber }); y -= 22; }
    function row(k, v) { pg.drawText(ascii(k), { x: 40, y: y, size: 10, font: F, color: grey }); pg.drawText(ascii(v), { x: 200, y: y, size: 10, font: B, color: P.rgb(0.08, 0.14, 0.1) }); y -= 16; }
    var c = bp.customer || {}, s = bp.site, r = bp.result || {}, loc = bp.location || {};
    head('Customer'); row('Name', c.name || '-'); row('Mobile', c.mobile || '-'); row('City', c.city || '-');
    y -= 6; head('Location'); row('Latitude / Longitude', loc.lat ? loc.lat + ', ' + loc.lng : '-'); row('Address', (loc.addr || '-').slice(0, 70)); row('Google Maps', loc.lat ? 'https://www.google.com/maps?q=' + loc.lat + ',' + loc.lng : '-');
    y -= 6; head('Site'); row('Installation type', s.type === 'roof' ? 'Roof (RCC)' : s.type === 'ground' ? 'Ground / open land' : 'Tin shed');
    row('Area marked', bp.area ? bp.area.sqft + ' sq ft (' + bp.area.sqm + ' sq m), perimeter ' + bp.area.perimeter_m + ' m' : '-');
    if (s.type === 'roof') { row('Floors / parapet', s.floors + ' / ' + s.parapet + ' m'); row('Panel tilt', s.tilt + ' deg'); row('Obstacles', (s.obstacles || []).join(', ') || 'None noted'); }
    if (s.type === 'ground') { row('Slope / soil', s.slope + ' / ' + s.soil); row('Fencing', s.fence ? 'Yes' : 'No'); }
    if (s.type === 'tinshed') { row('Sheet / roof pitch', s.sheet + ' / ' + s.pitch + ' deg'); row('Purlin gap / age', s.purlin + ' mm / ' + s.age + ' yrs'); row('Shed strength', s.strength); }
    row('Roof faces / usable', s.direction + ' / ' + s.usable + '%'); row('Connection / bill', s.phase + (s.bill ? ' / Rs.' + s.bill + ' per month' : ''));
    y -= 6; head('Plant design'); var pn = (PANELS.filter(function (x) { return x.id === bp.panel.id; })[0] || {}).name || 'Custom';
    row('Panel', pn + ' (' + bp.panel.w + ' W, ' + bp.panel.l + ' x ' + bp.panel.wd + ' mm)'); row('Structure', bp.structure.type + (bp.structure.recommended ? ' (Sunpowers recommended)' : ''));
    row('Panels / capacity', (r.panels || 0) + ' panels = ' + (r.kw || 0) + ' kW'); row('Est. generation', (r.units_year || 0) + ' units per year'); row('Cable run (approx.)', (r.cable_m || 0) + ' m');
    var e = bp.equipment || {}; row('Inverter / ACDB / DCDB', (e.inverter ? 'placed' : 'not placed') + ' / ' + (e.acdb ? 'placed' : 'not placed') + ' / ' + (e.dcdb ? 'placed' : 'not placed')); if (e.note) row('Installer note', e.note.slice(0, 80));
    pg.drawText('Planning estimate from the details given. Final design is confirmed by a Sunpowers engineer after a site survey.', { x: 36, y: 40, size: 8.5, font: F, color: grey });
    if (r.layout) {
      var p2 = doc.addPage([595, 842]); p2.drawText('Panel layout', { x: 36, y: 800, size: 16, font: B, color: green });
      try { var png = await svgToPng(layoutSvg(bp, { w: 640, h: 440 }), 640, 440), img = await doc.embedPng(png); p2.drawImage(img, { x: 36, y: 800 - 24 - 360, width: 523, height: 360 }); } catch (x) { p2.drawText('Layout image could not be drawn here.', { x: 36, y: 760, size: 10, font: F }); }
      p2.drawText('Blue = panels, dashed = marked boundary, INV / ACDB / DCDB = equipment, N = north. Dimensions in metres.', { x: 36, y: 800 - 24 - 376, size: 9, font: F, color: grey });
    }
    if (bp.photos && bp.photos.length) {
      var p3 = doc.addPage([595, 842]); p3.drawText('Site photos', { x: 36, y: 800, size: 16, font: B, color: green });
      for (var i = 0; i < Math.min(6, bp.photos.length); i++) {
        try { var d = bp.photos[i].data || bp.photos[i], raw = Uint8Array.from(atob(d.split(',')[1]), function (ch) { return ch.charCodeAt(0); }), im = await doc.embedJpg(raw), col = i % 2, rw = Math.floor(i / 2), k = Math.min(250 / im.width, 230 / im.height);
          p3.drawImage(im, { x: 36 + col * 270, y: 770 - 230 - rw * 250, width: im.width * k, height: im.height * k }); } catch (x) {}
      }
    }
    doc.getPages().forEach(function (pg2) {
      var wmT = 'Powered by Digidashland.in', wmS = 34, wmW = B.widthOfTextAtSize(wmT, wmS), wmA = 35 * Math.PI / 180;
      pg2.drawText(wmT, { x: 297 - (wmW / 2) * Math.cos(wmA), y: 421 - (wmW / 2) * Math.sin(wmA), size: wmS, font: B, color: P.rgb(0.78, 0.86, 0.8), opacity: 0.3, rotate: P.degrees(35) });
      pg2.drawText('www.sunpowers.in', { x: 36, y: 22, size: 9, font: B, color: green });
    });
    return await doc.save();
  }
  function download(bytes, name) { var b = new Blob([bytes], { type: 'application/pdf' }), u = URL.createObjectURL(b), a = D.createElement('a'); a.href = u; a.download = name; D.body.appendChild(a); a.click(); setTimeout(function () { a.remove(); URL.revokeObjectURL(u); }, 1500); }

  /* ---------- styles ---------- */
  var CSS = '.bp-wm{position:relative}.bp-wm::after{content:"Powered by Digidashland.in";position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-size:clamp(20px,6.5vw,52px);font-weight:800;color:rgba(11,46,31,.05);transform:rotate(-24deg);pointer-events:none;z-index:2;white-space:nowrap}.bp-links{display:flex;gap:8px;flex-wrap:wrap;margin:0 0 10px}.bp-links a{font-size:13px;font-weight:700;padding:6px 12px;border-radius:99px;border:1px solid var(--bp-l);color:var(--bp-g);text-decoration:none;background:#fff}.bp{--bp-g:#0b6e4f;--bp-d:#0b2e1f;--bp-a:#f5a623;--bp-l:#e3ebe3;font-family:inherit;color:#14231a;max-width:980px;margin:0 auto}.bp *{box-sizing:border-box}.bp h2{margin:0 0 4px;font-size:22px}.bp p.sub{margin:0 0 14px;color:#4d5f54}' +
    '.bp-steps{display:flex;gap:6px;overflow-x:auto;margin:0 0 14px;padding-bottom:4px}.bp-steps button{flex:1 0 auto;min-width:110px;border:1px solid var(--bp-l);background:#fff;border-radius:10px;padding:8px 10px;font:inherit;font-size:13px;font-weight:600;color:#4d5f54;cursor:pointer}.bp-steps button.on{background:var(--bp-d);color:#fff;border-color:var(--bp-d)}.bp-steps button.done{border-color:var(--bp-g);color:var(--bp-g)}' +
    '.bp-card{background:#fff;border:1px solid var(--bp-l);border-radius:14px;padding:14px;margin-bottom:12px}.bp-row{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.bp-row>.grow{flex:1;min-width:140px}' +
    '.bp input[type=text],.bp input[type=number],.bp input[type=tel],.bp select,.bp textarea{width:100%;padding:10px 11px;border:1px solid #c9d6cb;border-radius:10px;font:inherit;font-size:15px;background:#fff;color:#14231a}.bp label.l{display:block;font-size:13px;font-weight:600;margin:10px 0 4px;color:#33483a}' +
    '.bp-btn{border:0;border-radius:10px;padding:10px 14px;font:inherit;font-size:14px;font-weight:700;cursor:pointer;background:var(--bp-g);color:#fff;text-decoration:none;display:inline-flex;align-items:center;justify-content:center;gap:6px;min-height:40px}.bp-btn.o{background:#fff;color:var(--bp-d);border:1px solid #b9c9bc}.bp-btn.a{background:var(--bp-a);color:#2a1c00}.bp-btn.wa{background:#25d366;color:#04361a}.bp-btn.sm{padding:7px 10px;font-size:13px;min-height:34px}.bp-btn[disabled]{opacity:.55;cursor:default}' +
    '.bp-map{position:relative;height:380px;border-radius:12px;overflow:hidden;background:#cfd8cf;touch-action:none;user-select:none;border:1px solid #b9c9bc}.bp-tiles{position:absolute;inset:0}.bp-tiles img{position:absolute;width:256px;height:256px;max-width:none}.bp-ov{position:absolute;inset:0;width:100%;height:100%;pointer-events:none}.bp-zoom{position:absolute;right:8px;top:8px;display:flex;flex-direction:column;gap:4px}.bp-zoom button{width:34px;height:34px;border:0;border-radius:8px;background:#fff;font-size:20px;font-weight:700;cursor:pointer;box-shadow:0 1px 4px rgba(0,0,0,.3)}.bp-attr{position:absolute;left:0;bottom:0;background:rgba(255,255,255,.8);font-size:10px;padding:2px 6px;color:#333}' +
    '.bp-kpi{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:8px;margin:10px 0}.bp-kpi div{background:#f2f7f1;border-radius:10px;padding:10px}.bp-kpi b{display:block;font-size:20px;color:var(--bp-d)}.bp-kpi span{font-size:12px;color:#4d5f54}' +
    '.bp-opts{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:8px}.bp-opt{border:2px solid var(--bp-l);border-radius:12px;padding:10px;cursor:pointer;background:#fff;position:relative}.bp-opt.on{border-color:var(--bp-g);background:#f0f8f3}.bp-opt b{display:block;font-size:15px}.bp-opt small{color:#4d5f54;display:block;margin-top:3px;line-height:1.35}.bp-badge{position:absolute;right:8px;top:8px;background:var(--bp-a);color:#2a1c00;font-size:11px;font-weight:800;border-radius:20px;padding:2px 8px}' +
    '.bp-ck{display:flex;gap:8px;align-items:center;margin:6px 0;font-size:14px}.bp-ck input{width:18px;height:18px}.bp-msg{font-size:13px;margin-top:8px;padding:8px 10px;border-radius:8px;background:#fff6e0;color:#5b3d00}.bp-msg.ok{background:#e4f6ea;color:#0b5a2b}.bp-msg.er{background:#fde8e8;color:#8a1f1f}' +
    '.bp-ph{display:grid;grid-template-columns:repeat(auto-fill,minmax(110px,1fr));gap:8px;margin-top:10px}.bp-ph div{position:relative}.bp-ph img{width:100%;height:96px;object-fit:cover;border-radius:8px;display:block}.bp-ph button{position:absolute;right:3px;top:3px;border:0;background:rgba(0,0,0,.65);color:#fff;border-radius:6px;font-size:11px;padding:2px 6px;cursor:pointer}' +
    '.bp-lay svg{width:100%;height:auto;border-radius:12px;border:1px solid var(--bp-l);display:block}.bp-gf{width:100%;height:380px;border:1px solid #b9c9bc;border-radius:12px}.bp-nav{display:flex;justify-content:space-between;gap:8px;margin-top:6px}.bp-modal{position:fixed;inset:0;background:rgba(0,0,0,.55);z-index:9999;display:flex;align-items:center;justify-content:center;padding:14px}.bp-modal>div{background:#fff;border-radius:14px;padding:16px;width:100%;max-width:420px;max-height:92vh;overflow:auto}' +
    '@media(max-width:560px){.bp-map,.bp-gf{height:320px}.bp h2{font-size:19px}}';

  /* ---------- the wizard ---------- */
  function mount(el, o) {
    o = o || {}; if (!D.getElementById('bp-css')) { var st = D.createElement('style'); st.id = 'bp-css'; st.textContent = CSS; D.head.appendChild(st); }
    addI18n();
    var bp = o.initial ? derive(clone(o.initial)) : (lsGet(DRAFT_KEY) || emptyBp()); if (!bp.site) bp = emptyBp(); if (!bp.photos) bp.photos = [];
    if (o.customer) bp.customer = Object.assign({}, bp.customer || {}, o.customer);
    if (o.targetKw && bp.site && !num(bp.site.target_kw)) bp.site.target_kw = String(o.targetKw);
    var step = 0, maxStep = 0, map = null, gview = false, placing = 'inverter', msg = {}, busy = false, wa = waNum(o.whatsapp);
    function save() { if (o.noDraft) return; var d = clone(bp); d.photos = []; d.video = null; lsSet(DRAFT_KEY, d); }
    function ready() { return bp.area && bp.area.points && bp.area.points.length >= 3; }
    function field(label, inner) { return '<label class="l">' + label + '</label>' + inner; }
    function opts(arr, cur) { return arr.map(function (a) { return '<option' + (String(a) === String(cur) ? ' selected' : '') + '>' + a + '</option>'; }).join(''); }
    function ck(name, label, on) { return '<label class="bp-ck"><input type="checkbox" data-ck="' + name + '"' + (on ? ' checked' : '') + '><span>' + label + '</span></label>'; }

    function glinks() {
      var loc = bp.location; if (!loc) return '';
      return '<a class="bp-btn sm o" target="_blank" rel="noopener" href="https://www.google.com/maps?q=' + loc.lat + ',' + loc.lng + '&t=k&z=20">Open in Google Maps (satellite)</a><a class="bp-btn sm o" target="_blank" rel="noopener" href="https://www.google.com/maps/@' + loc.lat + ',' + loc.lng + ',120a,35y,0h,60t/data=!3m1!1e3">Open Google 3D view</a><button type="button" class="bp-btn sm o" data-gview>' + (gview ? 'Back to drawing map' : 'Show Google view here') + '</button>';
    }
    function linksBar() { var L = o.links || {}; return (L.site || L.store) ? '<div class="bp-links">' + (L.site ? '<a href="' + esc(L.site) + '" target="_blank" rel="noopener">🌐 ' + esc(L.siteLabel || 'Go to website') + '</a>' : '') + (L.store ? '<a href="' + esc(L.store) + '" target="_blank" rel="noopener">🛒 ' + esc(L.storeLabel || 'Go to store') + '</a>' : '') + '</div>' : ''; }
    function render() {
      derive(bp); save();
      var h = '<div class="bp bp-wm">' + linksBar() + '<h2>Project Blueprint</h2><p class="sub">Free solar site survey — mark your roof or land, choose panels and structure, and get a downloadable blueprint.</p><div class="bp-steps">' +
        STEPS.map(function (s, i) { return '<button type="button" data-step="' + i + '" class="' + (i === step ? 'on' : i < maxStep ? 'done' : '') + '">' + '<span>' + (i + 1) + '.</span> <span>' + s + '</span></button>'; }).join('') + '</div><div id="bp-body"></div>' +
        '<div class="bp-nav"><button type="button" class="bp-btn o" data-prev' + (step === 0 ? ' disabled' : '') + '>Back</button>' + (step < 5 ? '<button type="button" class="bp-btn" data-next>Next</button>' : '<span></span>') + '</div><div id="bp-gmsg"></div></div>';
      el.innerHTML = h; body(); wire();
    }
    function body() {
      var b = el.querySelector('#bp-body'), s = bp.site; map = null;
      if (step === 0) {
        var loc = bp.location, a = bp.area;
        b.innerHTML = '<div class="bp-card"><div class="bp-row"><button type="button" class="bp-btn a" data-gps>Use my GPS location</button><div class="grow"><input type="text" id="bp-q" placeholder="Search place / address"></div><button type="button" class="bp-btn o" data-search>Search</button></div><div id="bp-lmsg">' + (msg.loc ? '<div class="bp-msg ' + (msg.locOk ? 'ok' : '') + '">' + msg.loc + '</div>' : '') + '</div>' +
          '<div class="bp-row" style="margin:10px 0 8px"><button type="button" class="bp-btn sm o" data-layer="sat">Satellite</button><button type="button" class="bp-btn sm o" data-layer="osm">Street map</button><button type="button" class="bp-btn sm" data-mode="draw">Draw area</button><button type="button" class="bp-btn sm o" data-mode="move">Move map</button><button type="button" class="bp-btn sm o" data-undo>Undo point</button><button type="button" class="bp-btn sm o" data-clear>Clear</button></div>' +
          (gview && loc ? '<iframe class="bp-gf" loading="lazy" referrerpolicy="no-referrer" src="https://maps.google.com/maps?q=' + loc.lat + ',' + loc.lng + '&t=k&z=19&output=embed" title="Google view"></iframe>' : '<div id="bp-map"></div>') +
          '<p class="sub" style="margin:8px 0 0;font-size:13px">Tap on the map to mark each corner of your roof / land. Drag a point to adjust it.</p>' +
          '<div class="bp-row" id="bp-glinks" style="margin-top:8px">' + glinks() + '</div></div>' +
          '<div class="bp-card"><div class="bp-kpi"><div><b id="k-sqft">' + (a ? a.sqft : '—') + '</b><span>sq ft</span></div><div><b id="k-sqm">' + (a ? a.sqm : '—') + '</b><span>sq m</span></div><div><b id="k-per">' + (a ? a.perimeter_m : '—') + '</b><span>Perimeter</span></div><div><b style="font-size:13px" id="k-loc">' + (loc ? loc.lat + ', ' + loc.lng : 'Not set') + '</b><span>Location</span></div></div>' +
          field('Or enter the area manually (sq ft)', '<div class="bp-row"><div class="grow"><input type="number" id="bp-man" min="20" step="1" inputmode="decimal"></div><button type="button" class="bp-btn o" data-man>Use this area</button></div>') + '</div>';
        if (!gview) { var c0 = loc || { lat: 26.8467, lng: 80.9462 }; map = new SlipMap(b.querySelector('#bp-map'), { lat: c0.lat, lng: c0.lng, zoom: loc ? 19 : 12, points: a ? a.points : [], marker: loc ? [loc.lat, loc.lng] : null, onChange: function (p) { setPoints(p); } }); if (a && a.points.length > 2) map.fit(); }
      } else if (step === 1) {
        var t = s.type;
        b.innerHTML = '<div class="bp-card"><label class="l">Where will the plant be installed?</label><div class="bp-opts">' + [['roof', 'Roof (RCC)'], ['ground', 'Ground / open land'], ['tinshed', 'Tin shed']].map(function (x) { return '<div class="bp-opt' + (t === x[0] ? ' on' : '') + '" data-type="' + x[0] + '"><b>' + x[1] + '</b></div>'; }).join('') + '</div>' +
          (t === 'roof' ? '<div class="bp-row"><div class="grow">' + field('Number of floors', '<input type="number" data-f="floors" min="1" max="30" value="' + esc(s.floors) + '">') + '</div><div class="grow">' + field('Parapet height (m)', '<input type="number" data-f="parapet" step="0.1" min="0" value="' + esc(s.parapet) + '">') + '</div><div class="grow">' + field('Roof tilt for panels (degrees)', '<input type="number" data-f="tilt" min="0" max="45" value="' + esc(s.tilt) + '">') + '</div></div><label class="l">Obstacles on roof</label>' +
            [['Water tank', 'Water tank'], ['Staircase room', 'Staircase room'], ['AC / outdoor units', 'AC / outdoor units'], ['Trees / tall buildings nearby', 'Trees / tall buildings nearby']].map(function (x) { return ck('ob:' + x[0], x[1], (s.obstacles || []).indexOf(x[0]) >= 0); }).join('') : '') +
          (t === 'ground' ? '<div class="bp-row"><div class="grow">' + field('Slope of land', '<select data-f="slope">' + opts(['Flat', 'Mild slope', 'Steep slope'], s.slope) + '</select>') + '</div><div class="grow">' + field('Soil type', '<select data-f="soil">' + opts(['Normal', 'Hard / rocky', 'Sandy', 'Black cotton'], s.soil) + '</select>') + '</div><div class="grow">' + field('Distance to electric meter (m)', '<input type="number" data-f="meter_dist" min="0" value="' + esc(s.meter_dist) + '">') + '</div></div>' + ck('fence', 'Fencing available', s.fence) : '') +
          (t === 'tinshed' ? '<div class="bp-row"><div class="grow">' + field('Sheet type', '<select data-f="sheet">' + opts(['GI / metal sheet', 'Cement sheet', 'Polycarbonate / other'], s.sheet) + '</select>') + '</div><div class="grow">' + field('Roof pitch (degrees)', '<input type="number" data-f="pitch" min="0" max="45" value="' + esc(s.pitch) + '">') + '</div><div class="grow">' + field('Purlin gap (mm)', '<input type="number" data-f="purlin" min="300" value="' + esc(s.purlin) + '">') + '</div><div class="grow">' + field('Shed age (years)', '<input type="number" data-f="age" min="0" value="' + esc(s.age) + '">') + '</div><div class="grow">' + field('Shed strength', '<select data-f="strength">' + opts(['Good', 'Needs engineer check'], s.strength) + '</select>') + '</div></div>' : '') +
          '<div class="bp-row"><div class="grow">' + field('Roof faces', '<select data-f="direction">' + opts(['South', 'South-East', 'South-West', 'East', 'West', 'North', 'Flat roof'], s.direction) + '</select>') + '</div><div class="grow">' + field('Shadow-free usable area (%)', '<input type="number" data-f="usable" min="10" max="100" value="' + esc(s.usable) + '">') + '</div></div>' +
          '<div class="bp-row"><div class="grow">' + field('Monthly electricity bill (₹)', '<input type="number" data-f="bill" min="0" value="' + esc(s.bill) + '">') + '</div><div class="grow">' + field('Target capacity (kW) — optional', '<input type="number" data-f="target_kw" min="0" step="0.5" value="' + esc(s.target_kw) + '">') + '</div><div class="grow">' + field('Electric connection', '<select data-f="phase">' + opts(['Single phase', 'Three phase'], s.phase) + '</select>') + '</div></div></div>';
      } else if (step === 2) {
        var pc = bp.panel;
        b.innerHTML = '<div class="bp-card">' + field('Panel size', '<select id="bp-pn">' + PANELS.map(function (p) { return '<option value="' + p.id + '"' + (p.id === pc.id ? ' selected' : '') + '>' + p.name + (p.id === 'custom' ? '' : ' — ' + p.l + ' x ' + p.wd + ' mm') + '</option>'; }).join('') + '</select>') +
          (pc.id === 'custom' ? '<div class="bp-row"><div class="grow">' + field('Panel watt', '<input type="number" data-p="w" value="' + pc.w + '">') + '</div><div class="grow">' + field('Length (mm)', '<input type="number" data-p="l" value="' + pc.l + '">') + '</div><div class="grow">' + field('Width (mm)', '<input type="number" data-p="wd" value="' + pc.wd + '">') + '</div></div>' : '') +
          '<label class="l" style="margin-top:14px">Structure type</label><div class="bp-opts">' + STRUCT.map(function (x) { return '<div class="bp-opt' + (bp.structure.type === x.id ? ' on' : '') + '" data-struct="' + x.id + '">' + (x.rec ? '<span class="bp-badge">Sunpowers recommended</span>' : '') + '<b>' + x.id + '</b><small>' + x.d + '</small></div>'; }).join('') + '</div></div>' + resultCard(true);
      } else if (step === 3) {
        var eq = bp.equipment;
        b.innerHTML = '<div class="bp-card"><label class="l" style="margin-top:0">Place inverter, ACDB and DCDB</label><p class="sub" style="font-size:13px">Tap on the layout below to place the selected item.</p><div class="bp-row" id="bp-eq">' +
          [['inverter', 'Inverter'], ['acdb', 'ACDB'], ['dcdb', 'DCDB'], ['earthing', 'Earthing pit']].map(function (x) { return '<button type="button" class="bp-btn sm ' + (placing === x[0] ? '' : 'o') + '" data-place="' + x[0] + '">' + '<span>' + x[1] + '</span> · <span>' + (eq[x[0]] ? 'Placed' : 'Not placed') + '</span></button>'; }).join('') + '</div>' +
          '<div class="bp-lay" id="bp-lay" style="margin-top:10px">' + (bp.result ? layoutSvg(bp) : '<div class="bp-msg">Please mark the area on the map (at least 3 points) or enter it manually.</div>') + '</div>' + field('Note for installer (optional)', '<textarea rows="2" data-eq="note" maxlength="200">' + esc(eq.note) + '</textarea>') + '</div>';
      } else if (step === 4) {
        b.innerHTML = '<div class="bp-card"><p class="sub">Take photos of the site (roof, shadow areas, meter, DB). The location and time are stamped on each photo.</p><div class="bp-row"><label class="bp-btn" style="cursor:pointer">Add photo<input type="file" id="bp-ph" accept="image/*" capture="environment" multiple hidden></label><label class="bp-btn o" style="cursor:pointer">Record video (max 30 seconds)<input type="file" id="bp-vd" accept="video/*" capture="environment" hidden></label></div><div id="bp-pmsg">' + (msg.photo ? '<div class="bp-msg er">' + msg.photo + '</div>' : '') + '</div>' +
          '<div class="bp-ph" id="bp-phs">' + bp.photos.map(function (p, i) { return '<div><img alt="" src="' + p.data + '"><button type="button" data-rmph="' + i + '">Remove</button></div>'; }).join('') + '</div>' +
          (bp.video ? '<div class="bp-msg ok" style="margin-top:10px">🎥 ' + esc(bp.video.name) + ' · ' + bp.video.duration + 's · ' + Math.round(bp.video.size / 1024 / 1024 * 10) / 10 + ' MB <button type="button" class="bp-btn sm o" data-rmvd>Remove</button></div>' : '') +
          '<p class="sub" style="font-size:13px;margin-top:10px">Photos and video stay on your phone — nothing is uploaded to our server. Send them to our engineer on WhatsApp using the button on the last step.</p></div>';
      } else {
        b.innerHTML = '<div class="bp-card"><h2 style="font-size:19px">Your solar plant plan</h2>' + (bp.result ? resultCard(false) + '<div class="bp-lay" style="margin:10px 0">' + layoutSvg(bp) + '</div>' : '<div class="bp-msg">Please mark the area on the map (at least 3 points) or enter it manually.</div>') +
          '<div class="bp-row" style="margin-top:8px"><button type="button" class="bp-btn" data-pdf>Download blueprint PDF</button>' + (o.mode === 'crm' ? '<button type="button" class="bp-btn o" data-save>Save blueprint</button><button type="button" class="bp-btn a" data-savelead>Save and create lead</button>' : '<button type="button" class="bp-btn a" data-quote>Get quotation according to this blueprint</button>') + '</div>' +
          '<div class="bp-card" style="margin:12px 0 0;background:#f0fbf4"><button type="button" class="bp-btn wa" data-expert style="width:100%">Want to Edit Blue Print By Experts/Engineers</button><p class="sub" style="margin:8px 0 0;font-size:13px">Chat with our engineer on WhatsApp — they will make it exactly accurate.</p></div><div id="bp-smsg">' + (msg.save || '') + '</div>' +
          '<p class="sub" style="font-size:12px;margin-top:10px">This is a planning estimate from your inputs. The final design is confirmed by a Sunpowers engineer after a site survey.</p></div>';
      }
    }
    function resultCard(compact) {
      var r = bp.result; if (!r) return '<div class="bp-msg">Please mark the area on the map (at least 3 points) or enter it manually.</div>';
      return '<div class="bp-kpi" id="bp-res"><div><b>' + r.panels + '</b><span>Panels that fit</span></div><div><b>' + r.kw + ' kW</b><span>Plant size</span></div><div><b>' + r.units_year + '</b><span>Estimated units / year</span></div><div><b>' + bp.area.sqft + ' sq ft</b><span>Area marked</span></div>' + (r.cable_m ? '<div><b>' + r.cable_m + ' m</b><span>Cable run (approx.)</span></div>' : '') + (r.bill_kw ? '<div><b>' + r.bill_kw + ' kW</b><span>Suggested size from your bill</span></div>' : '') + '</div>';
    }
    function setPoints(p) {
      if (p.length >= 3) { bp.area = { points: p }; } else bp.area = p.length ? { points: p } : null;
      if (bp.area && p.length >= 3) { var L = G.toLocal(p), sq = G.area(L); bp.area.sqm = r2(sq); bp.area.sqft = Math.round(sq / 0.092903); bp.area.perimeter_m = r2(G.perimeter(L)); }
      var g = function (id, v) { var n = el.querySelector(id); if (n) n.textContent = v; };
      g('#k-sqft', bp.area && bp.area.sqft ? bp.area.sqft : '—'); g('#k-sqm', bp.area && bp.area.sqm ? bp.area.sqm : '—'); g('#k-per', bp.area && bp.area.perimeter_m ? bp.area.perimeter_m : '—');
      if (!bp.location && p.length) { bp.location = { lat: +p[0][0].toFixed(6), lng: +p[0][1].toFixed(6), source: 'map' }; g('#k-loc', bp.location.lat + ', ' + bp.location.lng); }
      derive(bp); save();
    }
    function setLoc(la, ln, src, acc, addr) { bp.location = { lat: +(+la).toFixed(6), lng: +(+ln).toFixed(6), source: src, acc: acc || 0, addr: addr || (bp.location && bp.location.addr) || '' }; if (map) { map.setView(bp.location.lat, bp.location.lng, 19); map.setMarker([bp.location.lat, bp.location.lng]); } var n = el.querySelector('#k-loc'); if (n) n.textContent = bp.location.lat + ', ' + bp.location.lng; var gl = el.querySelector('#bp-glinks'); if (gl) gl.innerHTML = glinks(); save(); }
    function say(sel, html, cls) { var n = el.querySelector(sel); if (n) n.innerHTML = html ? '<div class="bp-msg ' + (cls || '') + '">' + html + '</div>' : ''; }

    function wire() {
      el.onclick = async function (e) {
        var t = e.target, q = function (s) { return t.closest(s); }, x;
        if ((x = q('[data-step]'))) { var n = +x.getAttribute('data-step'); if (n > 0 && !ready() && n >= 3) { say('#bp-gmsg', 'Please mark the area on the map (at least 3 points) or enter it manually.'); return; } step = n; maxStep = Math.max(maxStep, n); render(); return; }
        if (q('[data-prev]')) { step = Math.max(0, step - 1); render(); return; }
        if (q('[data-next]')) { if (step === 0 && !ready()) { say('#bp-gmsg', 'Please mark the area on the map (at least 3 points) or enter it manually.'); return; } step = Math.min(5, step + 1); maxStep = Math.max(maxStep, step); render(); return; }
        if (q('[data-gps]')) { say('#bp-lmsg', 'Getting location…', ''); var p = await getPos(15000); if (p) { setLoc(p.lat, p.lng, 'gps', p.acc); msg.loc = ''; say('#bp-lmsg', 'Location found (±' + p.acc + ' m). Now mark your roof / land on the map.', 'ok'); } else say('#bp-lmsg', 'Allow location access in your browser to use GPS, or search the address.'); return; }
        if (q('[data-search]')) { doSearch(); return; }
        if ((x = q('[data-layer]'))) { if (map) map.setLayer(x.getAttribute('data-layer')); return; }
        if ((x = q('[data-mode]'))) { if (map) map.setMode(x.getAttribute('data-mode')); return; }
        if (q('[data-undo]')) { if (map) map.undo(); return; }
        if (q('[data-clear]')) { if (map) map.clear(); return; }
        if (q('[data-gview]')) { gview = !gview; render(); return; }
        if (q('[data-man]')) { var v = num(el.querySelector('#bp-man').value); if (v < 20) { say('#bp-lmsg', 'Enter the area in sq ft (at least 20).'); return; } var c = bp.location || (map ? map.center() : { lat: 26.8467, lng: 80.9462 }); if (!bp.location) setLoc(c.lat, c.lng, 'manual'); var pts = G.rectFromArea(bp.location.lat, bp.location.lng, v); if (map) { map.setPoints(pts); map.fit(); } else { setPoints(pts); } setPoints(pts); say('#bp-lmsg', 'Area set to ' + bp.area.sqft + ' sq ft.', 'ok'); return; }
        if ((x = q('[data-type]'))) { bp.site.type = x.getAttribute('data-type'); if (bp.site.type === 'ground') bp.site.tilt = 25; render(); return; }
        if ((x = q('[data-struct]'))) { var id = x.getAttribute('data-struct'); bp.structure = { type: id, recommended: !!(STRUCT.filter(function (s) { return s.id === id; })[0] || {}).rec }; render(); return; }
        if ((x = q('[data-place]'))) { placing = x.getAttribute('data-place'); body(); wire(); return; }
        if (q('#bp-lay svg') && step === 3) { placeAt(e); return; }
        if ((x = q('[data-rmph]'))) { bp.photos.splice(+x.getAttribute('data-rmph'), 1); render(); return; }
        if (q('[data-rmvd]')) { bp.video = null; render(); return; }
        if (q('[data-pdf]')) { await doPdf(); return; }
        if (q('[data-expert]')) { window.open('https://wa.me/' + wa + '?text=' + encodeURIComponent(expertText()), '_blank', 'noopener'); return; }
        if (q('[data-quote]')) { quoteModal(); return; }
        if (q('[data-save]')) { await doSave(false); return; }
        if (q('[data-savelead]')) { await doSave(true); return; }
      };
      el.onchange = async function (e) {
        var t = e.target, k;
        if ((k = t.getAttribute('data-f'))) { bp.site[k] = t.type === 'number' ? (t.value === '' ? '' : num(t.value)) : t.value; derive(bp); save(); return; }
        if ((k = t.getAttribute('data-ck'))) { if (k.indexOf('ob:') === 0) { var nm = k.slice(3), a = bp.site.obstacles || (bp.site.obstacles = []), i = a.indexOf(nm); if (t.checked && i < 0) a.push(nm); if (!t.checked && i >= 0) a.splice(i, 1); } else if (k === 'fence') bp.site.fence = t.checked; save(); return; }
        if (t.id === 'bp-pn') { var pn = PANELS.filter(function (p) { return p.id === t.value; })[0]; bp.panel = { id: pn.id, w: pn.w, l: pn.l, wd: pn.wd }; render(); return; }
        if ((k = t.getAttribute('data-p'))) { bp.panel[k] = Math.max(1, num(t.value)); derive(bp); save(); var rc = el.querySelector('#bp-res'); if (rc) rc.outerHTML = resultCard(true).replace(/^$/, ''); return; }
        if ((k = t.getAttribute('data-eq'))) { bp.equipment[k] = t.value; save(); return; }
        if (t.id === 'bp-ph') { await addPhotos(t.files); t.value = ''; return; }
        if (t.id === 'bp-vd') { await addVideo(t.files && t.files[0]); t.value = ''; return; }
      };
      var qi = el.querySelector('#bp-q'); if (qi) qi.onkeydown = function (e) { if (e.key === 'Enter') { e.preventDefault(); doSearch(); } };
    }
    async function doSearch() {
      var q = (el.querySelector('#bp-q').value || '').trim(); if (!q) return; say('#bp-lmsg', 'Getting location…', '');
      try { var r = await fetch('https://nominatim.openstreetmap.org/search?format=json&limit=1&q=' + encodeURIComponent(q), { headers: { Accept: 'application/json' } }), j = await r.json(); if (!j.length) throw 0; setLoc(j[0].lat, j[0].lon, 'search', 0, j[0].display_name); say('#bp-lmsg', esc(j[0].display_name), 'ok'); } catch (e) { say('#bp-lmsg', 'Place not found. Try a nearby landmark or city.'); }
    }
    function placeAt(e) {
      var svg = el.querySelector('#bp-lay svg'); if (!svg) return; var r = svg.getBoundingClientRect(), vb = svg.viewBox.baseVal, sx = vb.width / r.width, sy = vb.height / r.height, px = (e.clientX - r.left) * sx, py = (e.clientY - r.top) * sy;
      var sc = +svg.getAttribute('data-sc'), ox = +svg.getAttribute('data-ox'), oy = +svg.getAttribute('data-oy'); bp.equipment[placing] = { x: r2((px - ox) / sc), y: r2((oy - py) / sc) }; derive(bp); save(); body(); wire();
    }
    async function addPhotos(files) {
      msg.photo = ''; var left = 6 - bp.photos.length; if (left <= 0) { msg.photo = 'Maximum 6 photos.'; render(); return; }
      var pos = await getPos(6000);
      for (var i = 0; i < Math.min(left, files.length); i++) {
        try { var st = (pos ? pos.lat + ', ' + pos.lng + '  ' : 'GPS off  ') + new Date().toLocaleString('en-IN') + '  sunpowers.in'; bp.photos.push({ data: await shrinkPhoto(files[i], st), lat: pos && pos.lat, lng: pos && pos.lng, at: new Date().toISOString() }); } catch (e) { msg.photo = 'Could not read that photo.'; }
      }
      render();
    }
    function addVideo(f) {
      return new Promise(function (res) {
        if (!f) return res(); var v = D.createElement('video'), u = URL.createObjectURL(f); v.preload = 'metadata';
        v.onloadedmetadata = async function () { var d = v.duration; URL.revokeObjectURL(u); if (isFinite(d) && d > 30.5) { msg.photo = 'Video must be 30 seconds or shorter.'; } else { var p = await getPos(4000); bp.video = { name: f.name || 'video', duration: Math.round(d || 0), size: f.size, lat: p && p.lat, lng: p && p.lng, at: new Date().toISOString() }; msg.photo = ''; } render(); res(); };
        v.onerror = function () { URL.revokeObjectURL(u); msg.photo = 'Could not read that video.'; render(); res(); }; v.src = u;
      });
    }
    function expertText() {
      var r = bp.result || {}, c = bp.customer || {}, l = bp.location;
      return 'Hello Sunpowers, I made a solar blueprint and want an engineer to edit it and make it exactly accurate.\n' + (c.name ? 'Name: ' + c.name + '\n' : '') + (c.mobile ? 'Mobile: ' + c.mobile + '\n' : '') + 'Site: ' + (bp.site.type === 'roof' ? 'Roof' : bp.site.type === 'ground' ? 'Ground' : 'Tin shed') + (bp.area ? ', area ' + bp.area.sqft + ' sq ft' : '') + '\n' +
        (r.panels ? 'Plan: ' + r.panels + ' panels = ' + r.kw + ' kW, ' + bp.structure.type + ' structure\n' : '') + (l ? 'Location: https://www.google.com/maps?q=' + l.lat + ',' + l.lng + '\n' : '') + (bp.photos.length ? 'I am sending ' + bp.photos.length + ' site photo(s)' + (bp.video ? ' and a video' : '') + ' here.' : (bp.video ? 'I am sending a site video here.' : ''));
    }
    async function doPdf() {
      var b = el.querySelector('[data-pdf]'); if (b) { b.disabled = true; b.textContent = 'Preparing PDF…'; } say('#bp-smsg', '');
      try { derive(bp); var bytes = await makePdf(bp, o); download(bytes, 'Sunpowers-Blueprint-' + new Date().toISOString().slice(0, 10) + '.pdf'); if (o.onPdf) o.onPdf(bytes); } catch (e) { say('#bp-smsg', 'Could not create the PDF.', 'er'); }
      var b2 = el.querySelector('[data-pdf]'); if (b2) { b2.disabled = false; b2.textContent = 'Download blueprint PDF'; }
    }
    function slim() { var d = clone(bp); if (d.result) { delete d.result.local; } d.photo_count = (d.photos || []).length; d.photos = []; d.video = null; return d; }
    function quoteModal() {
      var c = bp.customer || {}, m = D.createElement('div'); m.className = 'bp-modal bp';
      m.innerHTML = '<div><h2 style="font-size:18px">Get quotation according to this blueprint</h2>' + field('Your name', '<input type="text" id="q-n" maxlength="80" value="' + esc(c.name || '') + '"' + (c.locked ? ' readonly' : '') + '>') + field('Mobile number', '<input type="tel" id="q-m" maxlength="12" inputmode="numeric" value="' + esc(c.mobile || '') + '"' + (c.locked ? ' readonly' : '') + '>') + field('City / village', '<input type="text" id="q-c" maxlength="80" value="' + esc(c.city || '') + '">') + field('Anything we should know? (optional)', '<textarea id="q-t" rows="2" maxlength="300"></textarea>') + '<div id="q-msg"></div><div class="bp-row" style="margin-top:12px"><button type="button" class="bp-btn" id="q-go">Send request</button><button type="button" class="bp-btn o" id="q-x">Cancel</button></div></div>';
      D.body.appendChild(m); addI18nSoon();
      m.querySelector('#q-x').onclick = function () { m.remove(); };
      m.querySelector('#q-go').onclick = async function () {
        var n = m.querySelector('#q-n').value.trim(), mo = m.querySelector('#q-m').value.replace(/\D/g, '').replace(/^(91|0)(?=\d{10}$)/, ''), city = m.querySelector('#q-c').value.trim(), nt = m.querySelector('#q-t').value.trim(), mg = m.querySelector('#q-msg');
        if (n.length < 2 || !/^[6-9]\d{9}$/.test(mo)) { mg.innerHTML = '<div class="bp-msg er">Enter your name and a valid 10-digit mobile number.</div>'; return; }
        var btn = this; btn.disabled = true; btn.textContent = 'Sending…'; bp.customer = { name: n, mobile: mo, city: city, locked: c.locked };
        try { if (!o.onSubmit) throw new Error('not connected'); await o.onSubmit({ name: n, mobile: mo, city: city, note: nt, blueprint: slim() }); mg.innerHTML = '<div class="bp-msg ok">Thank you! Our team will contact you with a quotation based on this blueprint.</div>'; btn.style.display = 'none'; lsDel(DRAFT_KEY); }
        catch (e) { mg.innerHTML = '<div class="bp-msg er">' + esc(e && e.message || 'Error') + '</div>'; btn.disabled = false; btn.textContent = 'Send request'; }
      };
    }
    function addI18nSoon() { addI18n(); }
    async function doSave(lead) {
      if (!o.onSave) return; var c = bp.customer || {}, n = c.name || '', mo = c.mobile || '';
      if (lead || true) {
        var m = D.createElement('div'); m.className = 'bp-modal bp';
        m.innerHTML = '<div><h2 style="font-size:18px">' + (lead ? 'Save and create lead' : 'Save blueprint') + '</h2>' + field('Customer name', '<input type="text" id="s-n" maxlength="80" value="' + esc(n) + '">') + field('Mobile number', '<input type="tel" id="s-m" maxlength="12" inputmode="numeric" value="' + esc(mo) + '">') + field('City / village', '<input type="text" id="s-c" maxlength="80" value="' + esc(c.city || '') + '">') + '<div id="s-msg"></div><div class="bp-row" style="margin-top:12px"><button type="button" class="bp-btn" id="s-go">' + (lead ? 'Save and create lead' : 'Save blueprint') + '</button><button type="button" class="bp-btn o" id="s-x">Cancel</button></div></div>';
        D.body.appendChild(m); addI18nSoon(); m.querySelector('#s-x').onclick = function () { m.remove(); };
        m.querySelector('#s-go').onclick = async function () {
          var nn = m.querySelector('#s-n').value.trim(), mm = m.querySelector('#s-m').value.replace(/\D/g, '').replace(/^(91|0)(?=\d{10}$)/, ''), cc = m.querySelector('#s-c').value.trim(), mg = m.querySelector('#s-msg');
          if (nn.length < 2) { mg.innerHTML = '<div class="bp-msg er">Enter your name and a valid 10-digit mobile number.</div>'; return; }
          if ((lead || mm) && !/^[6-9]\d{9}$/.test(mm)) { mg.innerHTML = '<div class="bp-msg er">Enter your name and a valid 10-digit mobile number.</div>'; return; }
          var btn = this; btn.disabled = true; btn.textContent = 'Saving…'; bp.customer = { name: nn, mobile: mm, city: cc };
          try { var res = await o.onSave({ name: nn, mobile: mm, city: cc, make_lead: !!lead, blueprint: slim(), id: o.recordId || null }); if (res && res.id) o.recordId = res.id; m.remove(); say('#bp-smsg', 'Saved ✔', 'ok'); if (o.onSaved) o.onSaved(res); }
          catch (e) { mg.innerHTML = '<div class="bp-msg er">' + esc(e && e.message || 'Error') + '</div>'; btn.disabled = false; btn.textContent = lead ? 'Save and create lead' : 'Save blueprint'; }
        };
      }
    }
    render();
    return { get: function () { return derive(clone(bp)); }, set: function (b) { bp = b; render(); }, reset: function () { bp = emptyBp(); lsDel(DRAFT_KEY); step = 0; maxStep = 0; render(); } };
  }

  window.SPBlueprint = { mount: mount, G: G, PANELS: PANELS, STRUCT: STRUCT, makePdf: makePdf, layoutSvg: layoutSvg, HI: HI };
})();
