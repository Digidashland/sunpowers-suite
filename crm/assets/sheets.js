/* Round 13-3 — one filter dialog for EVERY download (Excel) in the CRM.
   C.dlFilter(name, {head, rows}, mode) -> Promise<{head, rows, desc} | null>
   Filters are built from the data itself: date range, category / status / user / brand ... (any column with few distinct values),
   free-text search, and a column picker (to hide columns before sharing a sheet). Every download is written to Activity Record. */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc;
  var EXCL = /mobile|phone|number|^no$|\bid\b|^naam|name|customer|email|address|gstin|note|utr|^ref|detail|desc|link|^pan$|sku|title|item|pata|bill no|rasid/i;
  var PREF = /categ|status|stage|source|user|role|owner|banane|kiske|assigned|type|prakar|mode|brand|city|shahar|district|state|section|level|halat|month|mahina|gst|unit|group|sub|kaam|action/i;
  var DT = /^(\d{2})-(\d{2})-(\d{4})$/;
  function iso(s) { var m = DT.exec(String(s || '').slice(0, 10)); return m ? m[3] + '-' + m[2] + '-' + m[1] : ''; }
  function isNum(v) { return typeof v === 'number' || (v !== '' && v != null && !isNaN(Number(v)) && String(v).trim() !== ''); }

  function analyse(x) {
    var head = x.head || [], rows = x.rows || [], info = [];
    head.forEach(function (h, i) {
      var vals = rows.map(function (r) { return r[i] == null ? '' : r[i]; }), ne = vals.filter(function (v) { return String(v).trim() !== ''; });
      var nd = ne.filter(function (v) { return DT.test(String(v).slice(0, 10)); }).length, nn = ne.filter(isNum).length, cnt = {};
      ne.forEach(function (v) { var k = String(v).trim(); cnt[k] = (cnt[k] || 0) + 1; });
      var dist = Object.keys(cnt).length, o = { i: i, h: String(h), date: ne.length > 0 && nd >= ne.length * 0.6, cnt: cnt, dist: dist, ne: ne.length };
      o.num = !o.date && ne.length > 0 && nn === ne.length;
      o.sel = !o.date && dist >= 2 && dist <= 40 && (!o.num || /gst|%/i.test(o.h)) && (PREF.test(o.h) || (!EXCL.test(o.h) && dist <= Math.max(2, rows.length * 0.6)));
      info.push(o);
    });
    return info;
  }

  C.dlFilter = function (name, x, mode) {
    return new Promise(function (res) {
      if (!x || !x.rows) return res(null);
      if (!x.rows.length) { C.toast('Download ke liye koi row nahi hai', true); return res(null); }
      var info = analyse(x), sels = info.filter(function (o) { return o.sel; }), dcol = info.filter(function (o) { return o.date; })[0];
      var fields = '';
      if (dcol) fields += '<div class="f full"><label>Tareekh (' + esc(dcol.h) + ')</label><div class="row wrap" style="gap:8px;align-items:center"><input class="inp" type="date" data-df style="width:auto"><span class="xs mute">se</span><input class="inp" type="date" data-dt style="width:auto"><span class="xs mute">tak</span></div><div class="chips" style="margin-top:6px"><button type="button" data-q="m">Is mahina</button><button type="button" data-q="pm">Pichla mahina</button><button type="button" data-q="y">Is saal</button><button type="button" data-q="c">Saaf karein</button></div></div>';
      sels.forEach(function (o) {
        fields += '<div class="f"><label>' + esc(o.h) + '</label><select class="inp" data-fs="' + o.i + '"><option value="">Sab (' + o.dist + ')</option>' + Object.keys(o.cnt).sort(function (a, b) { return o.cnt[b] - o.cnt[a] || (a < b ? -1 : 1); }).map(function (k) { return '<option value="' + esc(k) + '">' + esc(k) + ' (' + o.cnt[k] + ')</option>'; }).join('') + '</select></div>';
      });
      fields += '<div class="f' + (sels.length % 2 ? '' : ' full') + '"><label>Kuch bhi khojein</label><input class="inp" type="search" data-fq placeholder="naam, shahar, item ..."></div>';
      var cols = '<details class="dlcols" style="margin-top:10px"><summary class="sm b" style="cursor:pointer;color:var(--leaf-d)">Columns chunein (<span data-cn>' + x.head.length + '</span>/' + x.head.length + ') — privacy ke liye jo na dena ho hata dein</summary><div class="row wrap" style="gap:6px 14px;margin-top:8px">' +
        x.head.map(function (h, i) { return '<label class="ck" style="margin:0"><input type="checkbox" data-col="' + i + '" checked> ' + esc(h) + '</label>'; }).join('') + '</div></details>';
      var m = C.modal({ title: 'Download — ' + esc(name), size: 'wide', body: '<div class="note g" style="margin-bottom:12px">' + C.ic('filter') + ' Pehle filter lagayein — sirf utni hi rows download hongi. <b data-cnt></b></div><div class="fg dlf">' + fields + '</div>' + cols,
        foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('download') + (mode === 'acc' ? ' Download &amp; Share' : ' Download') + '</button>', onClose: function () { if (!done) res(null); } }), done = false;
      function state() {
        var f = $('[data-df]', m.el), t = $('[data-dt]', m.el), q = ($('[data-fq]', m.el).value || '').toLowerCase().trim(), sv = {};
        $$('[data-fs]', m.el).forEach(function (s) { if (s.value) sv[s.getAttribute('data-fs')] = s.value; });
        var rows = x.rows.filter(function (r) {
          if (dcol) { var d = iso(r[dcol.i]); if (f && f.value && (!d || d < f.value)) return false; if (t && t.value && (!d || d > t.value)) return false; }
          for (var k in sv) if (String(r[+k] == null ? '' : r[+k]).trim() !== sv[k]) return false;
          if (q && r.join(' ').toLowerCase().indexOf(q) < 0) return false;
          return true;
        }), keep = $$('[data-col]', m.el).filter(function (c) { return c.checked; }).map(function (c) { return +c.getAttribute('data-col'); });
        var desc = []; if (f && f.value) desc.push('se ' + f.value); if (t && t.value) desc.push('tak ' + t.value); for (var k2 in sv) desc.push(info[+k2].h + '=' + sv[k2]); if (q) desc.push('"' + q + '"');
        return { rows: rows, keep: keep, desc: desc.join(', ') };
      }
      function upd() { var s = state(); $('[data-cnt]', m.el).textContent = s.rows.length + ' / ' + x.rows.length + ' rows download hongi'; $('[data-cn]', m.el).textContent = s.keep.length; $('[data-ok]', m.el).disabled = !s.rows.length || !s.keep.length; }
      function iso0(d) { return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); }
      m.el.addEventListener('input', upd); m.el.addEventListener('change', upd);
      m.el.addEventListener('click', function (e) {
        var q = e.target.closest('[data-q]'); if (!q) return; var n = new Date(), f = $('[data-df]', m.el), t = $('[data-dt]', m.el), k = q.getAttribute('data-q');
        if (k === 'm') { f.value = iso0(new Date(n.getFullYear(), n.getMonth(), 1)); t.value = iso0(new Date(n.getFullYear(), n.getMonth() + 1, 0)); }
        else if (k === 'pm') { f.value = iso0(new Date(n.getFullYear(), n.getMonth() - 1, 1)); t.value = iso0(new Date(n.getFullYear(), n.getMonth(), 0)); }
        else if (k === 'y') { f.value = n.getFullYear() + '-01-01'; t.value = n.getFullYear() + '-12-31'; } else { f.value = ''; t.value = ''; }
        upd();
      });
      $('[data-ok]', m.el).onclick = function () {
        var s = state(); if (!s.rows.length) return; done = true; m.close();
        var out = { head: s.keep.map(function (i) { return x.head[i]; }), rows: s.rows.map(function (r) { return s.keep.map(function (i) { return r[i]; }); }), desc: s.desc, text: x.text };
        try { C.call('crm_export_log', { name: name, rows: out.rows.length, filters: s.desc + (s.keep.length < x.head.length ? (s.desc ? ' · ' : '') + s.keep.length + '/' + x.head.length + ' columns' : '') }).catch(function () {}); } catch (e) {}
        res(out);
      };
      upd();
    });
  };
})();
