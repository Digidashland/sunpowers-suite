/* Sunpowers — "Send" sheet for EVERY document (Round 32). Same file in CRM, Store and Website.
   SPSHARE.open({ kind, title, subtitle, amount, valid_till, details:[[label,value]], name:'Quotation-1042.pdf',
                  getBlob:async()=>Blob | blob | html, phone, customer, text, ref, brand, brandPhone, viewUrl })
   Two ways to send on WhatsApp, no API:
     1) 🔗 Send via Link        — PDF is stored, a short page  <site>/d/<code>  shows the details + Download button + WhatsApp preview card
     2) 📎 Send from Local Storage — the real PDF file goes into WhatsApp (phone share sheet); on a computer it downloads and WhatsApp opens
   Plus ⬇ Download. CRM keeps a history (how many times the customer opened the link) and can close a link. */
(function () {
  'use strict';
  if (window.SPSHARE) return;
  var LIVE = ['sunpowers.in', 'www.sunpowers.in', 'store.sunpowers.in', 'admin.sunpowers.in', 'crm.sunpowers.in'];
  var KIND = { quote: 'quotation', bill: 'bill', invoice: 'tax invoice', receipt: 'payment receipt', ledger: 'ledger statement', design: 'solar design', blueprint: 'project blueprint', doctor: 'error report', plan: 'proposal', report: 'report', service: 'service report', visit: 'site visit report', order: 'order', doc: 'document' };
  var ov = null;

  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return '&#' + c.charCodeAt(0) + ';'; }); }
  function isCrm() { return !!(window.CRM && typeof window.CRM.call === 'function' && typeof window.CRM.pdfLink === 'function' && window.CRM_CONFIG); }
  function staging() { return LIVE.indexOf(location.hostname) < 0; }
  function conf() { return window.CRM_CONFIG || window.SITE || window.SP_CONFIG || {}; }
  function sb() { var c = conf(); return { url: String(c.SUPABASE_URL || '').replace(/\/+$/, ''), key: String(c.SUPABASE_KEY || '').trim() }; }
  function digits(s) { return String(s || '').replace(/\D/g, ''); }
  function wa10(s) { var d = digits(s); if (d.length === 12 && d.indexOf('91') === 0) d = d.slice(2); if (d.length === 11 && d[0] === '0') d = d.slice(1); return d.length === 10 ? d : ''; }
  function waUrl(num, text) { var n = wa10(num); return 'https://wa.me/' + (n ? '91' + n : '') + (text ? '?text=' + encodeURIComponent(text) : ''); }
  function money(n) { var x = Number(n); return isFinite(x) ? '₹' + Math.round(x).toLocaleString('en-IN') : ''; }
  function dmy(d) { var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(d || ''); return m ? m[3] + '/' + m[2] + '/' + m[1] : String(d || ''); }
  function slug(n) { return String(n || 'document.pdf').replace(/[^\w.\-() ]+/g, '-'); }

  /* ---- where the share page lives: <site>/d/<code>   (staging links carry ?e=s so they read the staging database) ---- */
  function siteBase() {
    var c = window.CRM_CONFIG || {}, s = '';
    if (isCrm()) s = (staging() && c.SITE_URL_STAGING) || c.SITE_URL;
    else if (window.SITE) s = location.origin;                                   /* Website pages */
    else if (window.SPGate && SPGate.cfg && SPGate.cfg.links && SPGate.cfg.links.site) s = SPGate.cfg.links.site;   /* Store app */
    /* Round 37: staging par bane link staging ki apni Website par jayein (live Website par abhi /d/ page nahi hota -> 404 / ulta page) */
    if (staging() && !(isCrm() && c.SITE_URL_STAGING) && /-(crm|store|admin)(-|\.)/.test(location.hostname) && /\.vercel\.app$/.test(location.hostname)) s = location.origin.replace(/-(crm|store|admin)(?=-|\.)/, '-website');
    return String(s || 'https://www.sunpowers.in').replace(/\/+$/, '');
  }
  function linkFor(code) { return siteBase() + '/d/' + code + (staging() ? '?e=s' : ''); }

  /* ---- database / storage adapters ---- */
  function rpcPub(fn, p) {
    var s = sb(), h = { 'Content-Type': 'application/json', apikey: s.key };
    if (s.key.indexOf('sb_') !== 0) h.Authorization = 'Bearer ' + s.key;
    return fetch(s.url + '/rest/v1/rpc/' + fn, { method: 'POST', headers: h, body: JSON.stringify({ p: p || {} }) }).then(function (r) {
      return r.text().then(function (t) { var j = null; try { j = JSON.parse(t); } catch (e) {} if (!r.ok) throw new Error((j && (j.message || j.hint)) || ('error ' + r.status)); return j; });
    });
  }
  function pubUpload(blob, name) {
    return rpcPub('sp_share_pub_token', {}).then(function (r) {
      var tk = r && r.token; if (!tk) throw new Error('upload token nahi mila');
      var s = sb(), path = 'u/' + tk + '/' + Date.now() + '-' + slug(name).replace(/\s+/g, '-'), h = { apikey: s.key, 'Content-Type': 'application/pdf', 'x-upsert': 'false' };
      if (s.key.indexOf('sb_') !== 0) h.Authorization = 'Bearer ' + s.key;
      return fetch(s.url + '/storage/v1/object/sp-images/' + path, { method: 'POST', headers: h, body: blob }).then(function (res) {
        if (!res.ok) throw new Error('upload ' + res.status); return s.url + '/storage/v1/object/public/sp-images/' + path;
      });
    });
  }
  var A = {
    upload: function (b, n) { return isCrm() ? window.CRM.pdfLink(b, n) : pubUpload(b, n); },
    create: function (p) { return (isCrm() ? window.CRM.call('crm_share_create', p) : rpcPub('sp_share_pub_create', p)).then(function (r) { var t = r && (r.token || r); if (!t || typeof t !== 'string') throw new Error('link nahi bana'); return t; }); },
    list: function (ref) { return isCrm() && ref ? window.CRM.call('crm_share_list', { ref: ref }) : Promise.resolve([]); },
    revoke: function (code, on) { return window.CRM.call('crm_share_revoke', { code: code, on: on }); }
  };

  /* ---- PDF from html (Website / Store; the CRM has its own C.pdfBlob) ---- */
  function loadScript(src) { return new Promise(function (res, rej) { var s = document.createElement('script'); s.src = src; s.onload = res; s.onerror = function () { s.remove(); rej(new Error('load')); }; document.head.appendChild(s); }); }
  function pdfFromHtml(html, name) {
    if (isCrm() && window.CRM.pdfBlob) return window.CRM.pdfBlob(html, name);
    var p = window.html2pdf ? Promise.resolve() : loadScript('https://cdnjs.cloudflare.com/ajax/libs/html2pdf.js/0.10.1/html2pdf.bundle.min.js').catch(function () { return loadScript('https://cdn.jsdelivr.net/npm/html2pdf.js@0.10.1/dist/html2pdf.bundle.min.js'); });
    return p.then(function () {
      return new Promise(function (res, rej) {
        var f = document.createElement('iframe'); f.style.cssText = 'position:fixed;left:-10000px;top:0;width:794px;height:1123px;border:0;background:#fff'; document.body.appendChild(f);
        var d = f.contentWindow.document; d.open(); d.write(/<html/i.test(html) ? html : '<!doctype html><html><head><meta charset="utf-8"></head><body style="margin:0">' + html + '</body></html>'); d.close();
        setTimeout(function () {
          var el = d.body; el.style.background = '#fff';
          window.html2pdf().set({ margin: [8, 8, 10, 8], filename: name, image: { type: 'jpeg', quality: 0.95 }, html2canvas: { scale: 2, useCORS: true, backgroundColor: '#ffffff', windowWidth: 794 }, jsPDF: { unit: 'mm', format: 'a4', orientation: 'portrait' }, pagebreak: { mode: ['css', 'legacy'] } }).from(el).outputPdf('blob').then(function (b) { f.remove(); res(b); }, function (e) { f.remove(); rej(e); });
        }, 500);
      });
    });
  }

  function saveBlob(blob, name) { var a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; document.body.appendChild(a); a.click(); setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 1500); }

  /* ---- sheet ---- */
  function css() {
    if (document.getElementById('spsCss')) return; var s = document.createElement('style'); s.id = 'spsCss';
    s.textContent = '.sps{position:fixed;inset:0;z-index:2147483600;background:rgba(10,20,12,.55);display:flex;align-items:flex-end;justify-content:center;font:500 15px/1.4 system-ui,-apple-system,"Segoe UI",Roboto,"Noto Sans Devanagari",sans-serif;color:#1c2b20}' +
      '@media(min-width:600px){.sps{align-items:center}}.sps *{box-sizing:border-box}.sps-c{background:#fff;width:100%;max-width:460px;max-height:92vh;overflow:auto;border-radius:22px 22px 0 0;padding:18px 16px calc(16px + env(safe-area-inset-bottom,0px))}@media(min-width:600px){.sps-c{border-radius:22px}}' +
      '.sps-h{display:flex;align-items:flex-start;gap:10px}.sps-h h3{margin:0;font-size:18px;line-height:1.25;flex:1;min-width:0;overflow-wrap:anywhere}.sps-h small{display:block;color:#5d6f62;font-weight:600;font-size:13px;margin-top:2px}.sps-x{border:0;background:#eef3ee;border-radius:50%;width:34px;height:34px;font-size:16px;cursor:pointer;color:#1c2b20}' +
      '.sps-amt{font-weight:800;color:#0f4d2b;font-size:20px;margin:8px 0 0}.sps label{display:block;font-weight:700;font-size:13px;margin:12px 0 4px;color:#34463a}.sps input{width:100%;border:1.5px solid #cfd8cf;border-radius:12px;padding:11px 12px;font:inherit;background:#fff;color:#1c2b20}' +
      '.sps-b{display:flex;flex-direction:column;align-items:center;gap:1px;width:100%;border:0;border-radius:14px;padding:13px 14px;margin-top:10px;font-weight:800;font-size:16px;line-height:1.2;font-family:inherit;cursor:pointer;text-align:center;text-decoration:none}.sps-b small{font-weight:600;font-size:12.5px;opacity:.9}' +
      '.sps-b.g{background:#1e8e3e;color:#fff}.sps-b.o{background:#fff;color:#0f4d2b;border:2px solid #1e8e3e}.sps-b.w{background:#25d366;color:#fff}.sps-b[disabled]{opacity:.55;cursor:wait}' +
      '.sps-r{display:flex;gap:8px;margin-top:10px}.sps-r .sps-b{margin-top:0;font-size:14px;padding:10px 8px}.sps-r .sps-b.s{background:#eef3ee;color:#1c2b20}' +
      '.sps-st{margin-top:10px;font-weight:600;font-size:13.5px;min-height:18px;color:#34463a}.sps-st.bad{color:#c8372d}.sps-st.ok{color:#15702f}.sps-lk{margin-top:8px;background:#f3f7f3;border-radius:12px;padding:10px 12px;word-break:break-all;font-size:13px;color:#0f4d2b;font-weight:700}' +
      '.sps-hi{margin-top:14px;border-top:1px solid #e1e9e2;padding-top:10px}.sps-hi b{font-size:13px}.sps-hi div.row{display:flex;gap:8px;align-items:center;justify-content:space-between;padding:6px 0;border-bottom:1px solid #eef3ee;font-size:13px}.sps-hi button{border:1px solid #d6dfd7;background:#fff;border-radius:999px;padding:3px 10px;font-weight:600;font-size:12px;font-family:inherit;cursor:pointer}';
    document.head.appendChild(s);
  }
  function close() { if (ov) { ov.remove(); ov = null; document.removeEventListener('keydown', onKey, true); } }
  function onKey(e) { if (e.key === 'Escape') close(); }

  function open(o) {
    o = o || {}; close(); css();
    var st = { pdfP: null, link: '', busy: false }, kind = o.kind || 'doc', name = slug(o.name || (String(o.title || 'document').replace(/[^\w\-]+/g, '-').slice(0, 50) + '.pdf')),
        brand = o.brand || (isCrm() && window.CRM.company && window.CRM.company().name) || 'Sunpowers',
        bphone = o.brandPhone || (isCrm() && window.CRM.company && window.CRM.company().phone) || (window.SITE && window.SITE.WHATSAPP) || '';
    function baseText() {
      if (o.text) return String(o.text);
      var L = ['Hi ' + (o.customer ? o.customer + ' ji' : 'ji') + ',', 'Aapka ' + (KIND[kind] || 'document') + ' taiyar hai.'];
      if (o.amount != null && isFinite(Number(o.amount))) L.push('Amount: ' + money(o.amount));
      L.push('Date: ' + dmy(o.date || new Date().toISOString().slice(0, 10)));
      if (o.valid_till) L.push('Valid till: ' + dmy(o.valid_till));
      L.push('Please check and confirm.'); return L.join('\n');
    }
    function prep() {
      if (st.pdfP) return st.pdfP;
      st.pdfP = Promise.resolve().then(function () {
        if (o.blob) return o.blob; if (typeof o.getBlob === 'function') return o.getBlob(); if (o.html) return pdfFromHtml(o.html, name); return null;
      }).then(function (b) { return b || null; }, function (e) { st.err = e; return null; });
      return st.pdfP;
    }
    ov = document.createElement('div'); ov.className = 'sps'; ov.setAttribute('data-noi18n', ''); ov.setAttribute('role', 'dialog'); ov.setAttribute('aria-modal', 'true');
    ov.innerHTML = '<div class="sps-c"><div class="sps-h"><h3>' + esc(o.title || 'Document') + '<small>' + esc(o.subtitle || (KIND[kind] || 'Document')) + '</small></h3><button type="button" class="sps-x" data-x aria-label="Close">✕</button></div>' +
      (o.amount != null && isFinite(Number(o.amount)) ? '<div class="sps-amt">' + esc(money(o.amount)) + '</div>' : '') +
      '<label for="spsPh">WhatsApp number <span style="font-weight:500;color:#5d6f62">(optional · वैकल्पिक)</span></label><input id="spsPh" type="tel" inputmode="numeric" maxlength="15" placeholder="10-digit mobile" value="' + esc(wa10(o.phone)) + '">' +
      '<button type="button" class="sps-b g" data-link>🔗 Send via Link<small>लिंक से भेजें — details + download page</small></button>' +
      '<button type="button" class="sps-b o" data-local>📎 Send from Local Storage<small>फ़ाइल से भेजें — असली PDF WhatsApp में</small></button>' +
      '<div class="sps-r"><button type="button" class="sps-b s" data-dl>⬇ Download<small>डाउनलोड</small></button><button type="button" class="sps-b s" data-copy hidden>📋 Copy link<small>लिंक कॉपी</small></button><button type="button" class="sps-b s" data-print hidden>🖨 Print<small>प्रिंट</small></button></div>' +
      '<div class="sps-st" data-st role="status"></div><div class="sps-lk" data-lk hidden></div><a class="sps-b w" data-wa hidden target="_blank" rel="noopener">💬 Open WhatsApp<small>WhatsApp खोलें</small></a><div class="sps-hi" data-hi hidden></div></div>';
    document.body.appendChild(ov); document.addEventListener('keydown', onKey, true);
    var $ = function (s) { return ov.querySelector(s); }, ph = $('#spsPh'), stl = $('[data-st]');
    function say(t, k) { stl.textContent = t || ''; stl.className = 'sps-st' + (k ? ' ' + k : ''); }
    function busy(on, t) { st.busy = on; ['[data-link]', '[data-local]', '[data-dl]'].forEach(function (s) { var b = $(s); if (b) b.disabled = on; }); if (t !== undefined) say(t); }
    function hasSrc() { return !!(o.blob || o.getBlob || o.html); }
    if (!hasSrc()) { $('[data-local]').hidden = true; $('[data-dl]').hidden = true; }
    if (!isCrm() && !sb().url) { $('[data-link]').hidden = true; $('[data-local]').classList.remove('o'); $('[data-local]').classList.add('g'); }   /* no database connection on this page (standalone designer): file / download only */
    if (o.blob && !/pdf/i.test(o.blob.type || name)) { $('[data-link]').hidden = true; $('[data-local]').classList.remove('o'); $('[data-local]').classList.add('g'); }   /* link page can only carry a PDF */
    if (hasSrc()) { say('PDF taiyar ho rahi hai… / PDF बन रही है…'); prep().then(function (b) { if (!ov) return; if (b) say('PDF ready ✔ / PDF तैयार ✔', 'ok'); else say('PDF nahi ban saki' + (st.err && st.err.message ? ' (' + st.err.message + ')' : '') + ' — link me sirf details jayengi', 'bad'); }); }

    function payload(pdfUrl) {
      var det = Array.isArray(o.details) ? o.details.slice(0, 30) : [];
      if (!det.length) { if (o.customer) det.push(['Customer', o.customer]); if (o.date) det.push(['Date', dmy(o.date)]); }
      return { kind: kind, title: String(o.title || 'Document').slice(0, 200), subtitle: o.subtitle || '', amount: o.amount != null && isFinite(Number(o.amount)) ? Number(o.amount) : null, valid_till: o.valid_till || null, details: det,
        pdf_url: pdfUrl || null, view_url: o.viewUrl || null, file_name: name, brand: brand, phone: wa10(bphone) || digits(bphone), ref: o.ref || null };
    }
    function waMsg(link) { return baseText() + (link ? '\n\n📄 PDF download aur poori detail yahan dekhein:\n' + link : ''); }
    function showLink(link) {
      st.link = link; var lk = $('[data-lk]'); lk.hidden = false; lk.textContent = link; $('[data-copy]').hidden = false;
      var a = $('[data-wa]'); a.hidden = false; a.href = waUrl(ph.value, waMsg(link));
    }
    function history() {
      if (!isCrm() || !o.ref) return; var box = $('[data-hi]');
      A.list(o.ref).then(function (rows) {
        if (!ov || !rows || !rows.length) return; box.hidden = false;
        box.innerHTML = '<b>Pehle bheje gaye links / पहले भेजे गए लिंक</b>' + rows.map(function (r) {
          var when = window.CRM.fdt ? window.CRM.fdt(r.at) : r.at;
          return '<div class="row"><span>' + esc(when) + ' · ' + (r.revoked ? '🔒 band' : r.expired ? '⌛ expire' : '👁 ' + (r.views || 0) + ' baar dekha' + (r.last_view ? ' (aakhri ' + esc(window.CRM.fdt ? window.CRM.fdt(r.last_view) : r.last_view) + ')' : '')) + '</span>' +
            (r.expired ? '' : '<button type="button" data-rv="' + esc(r.token) + '" data-on="' + (r.revoked ? '0' : '1') + '">' + (r.revoked ? 'Dobara chalu' : 'Band karein') + '</button>') + '</div>';
        }).join('');
      }, function () {});
    }
    history();

    if (typeof o.print === 'function') { var pb = $('[data-print]'); pb.hidden = false; pb.onclick = function () { try { o.print(); } catch (e) {} }; }
    $('[data-x]').onclick = close; ov.addEventListener('mousedown', function (e) { if (e.target === ov) close(); });
    ov.addEventListener('click', function (e) {
      var b = e.target.closest && e.target.closest('[data-rv]'); if (!b) return;
      A.revoke(b.getAttribute('data-rv'), b.getAttribute('data-on') === '1').then(function () { history(); }, function (er) { say(er.message || 'nahi hua', 'bad'); });
    });
    $('[data-copy]').onclick = function () {
      var done = function () { say('Link copy ho gaya ✔ / लिंक कॉपी हो गया', 'ok'); };
      try { navigator.clipboard.writeText(st.link).then(done, function () { var r = document.createRange(); r.selectNodeContents($('[data-lk]')); var s = getSelection(); s.removeAllRanges(); s.addRange(r); say('Link ko select karke copy karein'); }); } catch (e) { done(); }
    };
    $('[data-dl]').onclick = async function () {
      busy(true, 'Taiyar ho raha hai…'); var b = await prep(); busy(false);
      if (!b) return say('File nahi ban saki — dobara koshish karein', 'bad'); saveBlob(b, name); say('Download ho gaya ✔ / डाउनलोड हो गया', 'ok');
    };
    $('[data-link]').onclick = async function () {
      busy(true, 'Link ban raha hai… / लिंक बन रहा है…');
      try {
        var b = hasSrc() ? await prep() : null, pdfUrl = '';
        if (hasSrc() && !b) { say('PDF nahi ban saki' + (st.err && st.err.message ? ' (' + st.err.message + ')' : '') + ' — bina PDF ka link nahi banaya. Dobara koshish karein ya “Send from Local Storage” use karein', 'bad'); busy(false); return; }   /* Round 37: customer ko bina Download wala link kabhi nahi jata */
        if (b && /pdf/i.test(b.type || name)) pdfUrl = await A.upload(b, name);
        var code = await A.create(payload(pdfUrl)), link = linkFor(code);
        showLink(link); say('Link ban gaya ✔ — WhatsApp khul raha hai / लिंक बन गया', 'ok');
        var w = null; try { w = window.open(waUrl(ph.value, waMsg(link)), '_blank'); } catch (e) {} if (!w) say('Link ban gaya ✔ — neeche “Open WhatsApp” dabayein / लिंक बन गया — नीचे बटन दबाएँ', 'ok');
        if (typeof o.onShared === 'function') { try { o.onShared('link', link); } catch (e) {} }
        history();
      } catch (e) { say('Link nahi ban saka: ' + (e && e.message ? e.message : 'error') + ' — local file se bhejein', 'bad'); }
      busy(false);
    };
    $('[data-local]').onclick = async function () {
      busy(true, 'File taiyar ho rahi hai…'); var b = await prep(); busy(false);
      if (!b) return say('File nahi ban saki — dobara koshish karein', 'bad');
      var file = null; try { file = new File([b], name, { type: b.type || 'application/pdf' }); } catch (e) {}
      if (file && navigator.canShare && navigator.canShare({ files: [file] })) {
        try { await navigator.share({ files: [file], text: baseText() }); say('Share ho gaya ✔ / शेयर हो गया', 'ok'); if (typeof o.onShared === 'function') { try { o.onShared('file'); } catch (e) {} } return; }
        catch (e) { if (e && e.name === 'AbortError') return; }
      }
      saveBlob(b, name); var w = null; try { w = window.open(waUrl(ph.value, baseText() + '\n\n(' + name + ' attach kar raha hoon)'), '_blank'); } catch (e) {}
      var a = $('[data-wa]'); a.hidden = false; a.href = waUrl(ph.value, baseText() + '\n\n(' + name + ' attach kar raha hoon)');
      say('File download ho gayi ✔ — WhatsApp me 📎 se attach karein / फ़ाइल डाउनलोड हुई — 📎 से जोड़ें', 'ok');
      if (typeof o.onShared === 'function') { try { o.onShared('file'); } catch (e) {} }
    };
    ph.addEventListener('input', function () { var a = $('[data-wa]'); if (!a.hidden && st.link) a.href = waUrl(ph.value, waMsg(st.link)); });
    setTimeout(function () { var b = $('[data-link]'); if (b) b.focus(); }, 50);
    return { close: close };
  }
  window.SPSHARE = { open: open, close: close, pdfFromHtml: pdfFromHtml, siteBase: siteBase, linkFor: linkFor, _A: A };
})();
