/* Round 13-3 — Store Admin / Website Admin: filter-first downloads + sheet scope (code) for edit-and-upload sheets.
   SPSH.init({modal, toast, esc, rpc, pass, download, today})
   SPSH.dl(title, {head, rows}, opts) -> Promise<{head, rows, desc} | null>   (opts.multi: header names whose cells hold "a | b" lists)
   SPSH.issue(kind, ids, cols, note) -> {code, n, expires_at}        SPSH.check(code, kind) -> {ids, cols}
   SPSH.metaSheet(code, extra) -> sheet object for XLSXLite.write     SPSH.codeOf(workbook) -> code | ''           */
(function () {
  'use strict';
  var X = null;
  var EXCL = /id\b|^id$|title|name|नाम|phone|mobile|email|address|url|link|image|desc|text|note|sku|sub|tagline|body/i;
  var PREF = /section|सेक्शन|status|stock|visible|brand|category|kind|scope|state|district|source|type|city|rating|badge|action|product_name|unit|effect/i;
  var DT = /^(\d{1,2})[-\/](\d{1,2})[-\/](\d{4})/;
  function iso(s) { var t = String(s || ''), m = DT.exec(t); if (m) return m[3] + '-' + ('0' + m[2]).slice(-2) + '-' + ('0' + m[1]).slice(-2); m = /^(\d{4}-\d{2}-\d{2})/.exec(t); return m ? m[1] : ''; }
  function toks(v, multi) { var s = String(v == null ? '' : v).trim(); if (!s) return []; return multi ? s.split('|').map(function (x) { return x.trim(); }).filter(Boolean) : [s]; }
  function isNum(v) { return typeof v === 'number' || (v !== '' && v != null && String(v).trim() !== '' && !isNaN(Number(v))); }

  function analyse(x, multi) {
    return (x.head || []).map(function (h, i) {
      var mu = (multi || []).indexOf(String(h)) >= 0, cnt = {}, ne = 0, nd = 0, nn = 0;
      x.rows.forEach(function (r) { var v = r[i]; if (v == null || String(v).trim() === '') return; ne++; if (iso(v) && DT.test(String(v)) || /^\d{4}-\d{2}-\d{2}/.test(String(v))) nd++; if (isNum(v)) nn++; toks(v, mu).forEach(function (t) { cnt[t] = (cnt[t] || 0) + 1; }); });
      var dist = Object.keys(cnt).length, o = { i: i, h: String(h), multi: mu, cnt: cnt, dist: dist };
      o.date = ne > 0 && nd >= ne * 0.6; o.num = !o.date && ne > 0 && nn === ne;
      o.sel = !o.date && dist >= 2 && dist <= 40 && (!o.num || /rating|sort/i.test(o.h) === false && dist <= 8) && (PREF.test(o.h) || (!EXCL.test(o.h) && dist <= Math.max(2, x.rows.length * 0.6)));
      return o;
    });
  }

  function dl(title, x, opts) {
    opts = opts || {};
    return new Promise(function (res) {
      if (!x || !x.rows || !x.rows.length) { X.toast('डाउनलोड के लिए कोई लाइन नहीं है', true); return res(null); }
      var info = analyse(x, opts.multi), sels = info.filter(function (o) { return o.sel; }), dcol = info.filter(function (o) { return o.date; })[0], fields = '';
      if (dcol) fields += '<div class="fld" style="grid-column:1/-1"><label class="l">तारीख़ (' + X.esc(dcol.h) + ')</label><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap"><input type="date" data-df style="width:auto"><span>से</span><input type="date" data-dt style="width:auto"><span>तक</span><button type="button" class="btn sm out" data-q="m">इस महीने</button><button type="button" class="btn sm out" data-q="y">इस साल</button><button type="button" class="btn sm out" data-q="c">साफ़</button></div></div>';
      sels.forEach(function (o) {
        fields += '<div class="fld"><label class="l">' + X.esc(o.h) + '</label><select data-fs="' + o.i + '"><option value="">सब (' + o.dist + ')</option>' + Object.keys(o.cnt).sort(function (a, b) { return o.cnt[b] - o.cnt[a] || (a < b ? -1 : 1); }).map(function (k) { return '<option value="' + X.esc(k) + '">' + X.esc(k) + ' (' + o.cnt[k] + ')</option>'; }).join('') + '</select></div>';
      });
      fields += '<div class="fld"><label class="l">कुछ भी खोजें</label><input type="search" data-fq placeholder="नाम, शहर, आइटम…"></div>';
      var cols = '<details style="margin-top:10px"><summary style="cursor:pointer;font-weight:700">कॉलम चुनें (<span data-cn>' + x.head.length + '</span>/' + x.head.length + ') — प्राइवेसी के लिए जो न देना हो हटा दें</summary><div style="display:flex;flex-wrap:wrap;gap:6px 14px;margin-top:8px">' +
        x.head.map(function (h, i) { var lock = (opts.lock || []).indexOf(String(h)) >= 0; return '<label class="chk" style="margin:0"><input type="checkbox" data-col="' + i + '" checked' + (lock ? ' disabled' : '') + '> ' + X.esc(h) + '</label>'; }).join('') + '</div></details>';
      var done = false, m = X.modal('📥 डाउनलोड — ' + title, '<div class="note g">पहले फ़िल्टर लगाएँ — सिर्फ़ उतनी ही लाइनें डाउनलोड होंगी। <b data-cnt></b></div><div class="fg" style="margin-top:10px">' + fields + '</div>' + cols,
        [{ l: 'रद्द करें', cls: 'gray' }, { l: opts.okLabel || '⬇️ डाउनलोड', id: 'shOk', fn: function () {
          var s = state(); if (!s.rows.length || !s.keep.length) return false; done = true;
          var out = { head: s.keep.map(function (i) { return x.head[i]; }), rows: s.rows.map(function (r) { return s.keep.map(function (i) { return r[i]; }); }), srcRows: s.rows, desc: s.desc };
          try { X.rpc('sp_admin_export_log', { p_pass: X.pass(), p_name: title, p_rows: out.rows.length, p_filters: s.desc + (s.keep.length < x.head.length ? (s.desc ? ' · ' : '') + s.keep.length + '/' + x.head.length + ' columns' : '') }).catch(function () {}); } catch (e) {}
          res(out);
        } }]);
      var bg = m.el;
      var closeOrig = m.close; m.close = function () { closeOrig(); if (!done) { done = true; res(null); } };
      function q$(s) { return bg.querySelector(s); }
      function state() {
        var f = q$('[data-df]'), t = q$('[data-dt]'), q = (q$('[data-fq]').value || '').toLowerCase().trim(), sv = {};
        Array.prototype.forEach.call(bg.querySelectorAll('[data-fs]'), function (s) { if (s.value) sv[s.getAttribute('data-fs')] = s.value; });
        var rows = x.rows.filter(function (r) {
          if (dcol) { var d = iso(r[dcol.i]); if (f && f.value && (!d || d < f.value)) return false; if (t && t.value && (!d || d > t.value)) return false; }
          for (var k in sv) { var o = info[+k], tk = toks(r[+k], o.multi); if (tk.indexOf(sv[k]) < 0) return false; }
          if (q && r.join(' ').toLowerCase().indexOf(q) < 0) return false; return true;
        }), keep = Array.prototype.filter.call(bg.querySelectorAll('[data-col]'), function (c) { return c.checked; }).map(function (c) { return +c.getAttribute('data-col'); });
        var desc = []; if (f && f.value) desc.push('from ' + f.value); if (t && t.value) desc.push('to ' + t.value); for (var k2 in sv) desc.push(info[+k2].h + '=' + sv[k2]); if (q) desc.push('"' + q + '"');
        return { rows: rows, keep: keep, desc: desc.join(', ') };
      }
      function upd() { var s = state(); q$('[data-cnt]').textContent = s.rows.length + ' / ' + x.rows.length + ' लाइनें डाउनलोड होंगी'; q$('[data-cn]').textContent = s.keep.length; var ok = q$('#shOk'); if (ok) ok.disabled = !s.rows.length || !s.keep.length; }
      function d2(d) { return d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2); }
      bg.addEventListener('input', upd); bg.addEventListener('change', upd);
      bg.addEventListener('click', function (e) { var q = e.target.closest('[data-q]'); if (!q) return; var n = new Date(), f = q$('[data-df]'), t = q$('[data-dt]'), k = q.getAttribute('data-q'); if (k === 'm') { f.value = d2(new Date(n.getFullYear(), n.getMonth(), 1)); t.value = d2(new Date(n.getFullYear(), n.getMonth() + 1, 0)); } else if (k === 'y') { f.value = n.getFullYear() + '-01-01'; t.value = n.getFullYear() + '-12-31'; } else { f.value = ''; t.value = ''; } upd(); });
      upd();
    });
  }

  function issue(kind, ids, cols, note) { return X.rpc('sp_sheet_issue', { p_pass: X.pass(), p_kind: kind, p_ids: ids || [], p_cols: cols || [], p_note: note || '' }); }
  function check(code, kind) { return X.rpc('sp_sheet_check', { p_pass: X.pass(), p_code: code, p_kind: kind }); }
  function metaSheet(code, extra) { return { name: '_sp', rows: [['SPSHEET', code]].concat(extra || [], [['note', 'यह शीट सिर्फ़ "अपलोड" से वापस जाएगी। id न बदलें। सिर्फ़ ऊपर दी गई लाइनें/कॉलम बदलेंगे।']]), widths: [14, 70] }; }
  function codeOf(wb) { var c = ''; ((wb && wb._sp) || []).forEach(function (r) { if (String((r || [])[0]) === 'SPSHEET') c = String(r[1] || '').trim(); }); return c; }

  window.SPSH = { init: function (x) { X = x; }, dl: dl, issue: issue, check: check, metaSheet: metaSheet, codeOf: codeOf, analyse: analyse };
})();
