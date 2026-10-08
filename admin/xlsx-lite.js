/* =====================================================================
   xlsx-lite.js — tiny Excel (.xlsx) writer + reader, no dependencies.
   Write: XLSXLite.write([{name, rows:[[...]], widths:[..]}]) -> Blob
   Read : await XLSXLite.read(arrayBuffer) -> { sheetName: [[...]] }
   ===================================================================== */
(function () {
  'use strict';
  var XL = (window.XLSXLite = {});
  var MAIN_NS = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  var REL_NS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  var CRC = (function () {
    var t = new Uint32Array(256);
    for (var n = 0; n < 256; n++) { var c = n; for (var k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; }
    return t;
  })();
  function crc32(u8) { var c = 0xffffffff; for (var i = 0; i < u8.length; i++) c = CRC[(c ^ u8[i]) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; }
  var enc = new TextEncoder();

  function zipStore(files) {
    var parts = [], central = [], offset = 0;
    files.forEach(function (f) {
      var name = enc.encode(f.name), data = f.data, crc = crc32(data);
      var h = new DataView(new ArrayBuffer(30));
      h.setUint32(0, 0x04034b50, true); h.setUint16(4, 20, true); h.setUint16(6, 0x0800, true); h.setUint16(8, 0, true);
      h.setUint16(10, 0, true); h.setUint16(12, 33, true); h.setUint32(14, crc, true);
      h.setUint32(18, data.length, true); h.setUint32(22, data.length, true); h.setUint16(26, name.length, true); h.setUint16(28, 0, true);
      parts.push(new Uint8Array(h.buffer), name, data);
      var c = new DataView(new ArrayBuffer(46));
      c.setUint32(0, 0x02014b50, true); c.setUint16(4, 20, true); c.setUint16(6, 20, true); c.setUint16(8, 0x0800, true);
      c.setUint16(10, 0, true); c.setUint16(12, 0, true); c.setUint16(14, 33, true); c.setUint32(16, crc, true);
      c.setUint32(20, data.length, true); c.setUint32(24, data.length, true); c.setUint16(28, name.length, true);
      c.setUint16(30, 0, true); c.setUint16(32, 0, true); c.setUint16(34, 0, true); c.setUint16(36, 0, true);
      c.setUint32(38, 0, true); c.setUint32(42, offset, true);
      central.push(new Uint8Array(c.buffer), name);
      offset += 30 + name.length + data.length;
    });
    var cdSize = central.reduce(function (s, a) { return s + a.length; }, 0);
    var e = new DataView(new ArrayBuffer(22));
    e.setUint32(0, 0x06054b50, true); e.setUint16(8, files.length, true); e.setUint16(10, files.length, true);
    e.setUint32(12, cdSize, true); e.setUint32(16, offset, true);
    return new Blob(parts.concat(central, [new Uint8Array(e.buffer)]), { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
  }

  function xmlEsc(s) {
    return String(s).replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F￾￿]/g, '')
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function colName(i) { var s = ''; i++; while (i > 0) { var m = (i - 1) % 26; s = String.fromCharCode(65 + m) + s; i = Math.floor((i - 1) / 26); } return s; }
  function cleanSheetName(n, used) {
    var s = String(n || 'Sheet').replace(/[\[\]:*?\/\\]/g, ' ').slice(0, 31) || 'Sheet', base = s, k = 2;
    while (used[s.toLowerCase()]) { s = base.slice(0, 28) + ' ' + k++; }
    used[s.toLowerCase()] = 1; return s;
  }

  XL.write = function (sheets) {
    var used = {}, files = [], sheetEntries = '', relEntries = '', overrides = '';
    sheets.forEach(function (sh, idx) {
      var n = idx + 1, name = cleanSheetName(sh.name, used), rows = sh.rows || [];
      var cols = '';
      if (sh.widths && sh.widths.length) {
        cols = '<cols>' + sh.widths.map(function (w, i) { return '<col min="' + (i + 1) + '" max="' + (i + 1) + '" width="' + (w || 12) + '" customWidth="1"/>'; }).join('') + '</cols>';
      }
      var data = rows.map(function (r, ri) {
        return '<row r="' + (ri + 1) + '">' + (r || []).map(function (v, ci) {
          var ref = colName(ci) + (ri + 1), st = ri === 0 ? ' s="1"' : '';
          if (v === null || v === undefined || v === '') return '';
          if (typeof v === 'number' && isFinite(v)) return '<c r="' + ref + '"' + st + '><v>' + v + '</v></c>';
          var s = String(v); if (s.length > 32000) s = s.slice(0, 32000);
          return '<c r="' + ref + '" t="inlineStr"' + st + '><is><t xml:space="preserve">' + xmlEsc(s) + '</t></is></c>';
        }).join('') + '</row>';
      }).join('');
      var xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<worksheet xmlns="' + MAIN_NS + '" xmlns:r="' + REL_NS + '">' +
        '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>' +
        cols + '<sheetData>' + data + '</sheetData></worksheet>';
      files.push({ name: 'xl/worksheets/sheet' + n + '.xml', data: enc.encode(xml) });
      sheetEntries += '<sheet name="' + xmlEsc(name) + '" sheetId="' + n + '" r:id="rId' + n + '"/>';
      relEntries += '<Relationship Id="rId' + n + '" Type="' + REL_NS + '/worksheet" Target="worksheets/sheet' + n + '.xml"/>';
      overrides += '<Override PartName="/xl/worksheets/sheet' + n + '.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>';
    });
    var sN = sheets.length + 1;
    relEntries += '<Relationship Id="rId' + sN + '" Type="' + REL_NS + '/styles" Target="styles.xml"/>';
    var head = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
    files.unshift(
      { name: '[Content_Types].xml', data: enc.encode(head + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>' +
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>' + overrides + '</Types>') },
      { name: '_rels/.rels', data: enc.encode(head + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
        '<Relationship Id="rId1" Type="' + REL_NS + '/officeDocument" Target="xl/workbook.xml"/></Relationships>') },
      { name: 'xl/workbook.xml', data: enc.encode(head + '<workbook xmlns="' + MAIN_NS + '" xmlns:r="' + REL_NS + '"><sheets>' + sheetEntries + '</sheets></workbook>') },
      { name: 'xl/_rels/workbook.xml.rels', data: enc.encode(head + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' + relEntries + '</Relationships>') },
      { name: 'xl/styles.xml', data: enc.encode(head + '<styleSheet xmlns="' + MAIN_NS + '">' +
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>' +
        '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>' +
        '<fill><patternFill patternType="solid"><fgColor rgb="FFC8E6C9"/><bgColor indexed="64"/></patternFill></fill></fills>' +
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>' +
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' +
        '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>' +
        '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/></cellXfs>' +
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>') }
    );
    return zipStore(files);
  };

  /* ------------------------------ reader ------------------------------ */
  async function inflateRaw(u8) {
    if (typeof DecompressionStream === 'undefined') throw new Error('Ye browser Excel read nahi kar sakta — Chrome use karein');
    var ds = new Blob([u8]).stream().pipeThrough(new DecompressionStream('deflate-raw'));
    return new Uint8Array(await new Response(ds).arrayBuffer());
  }
  async function unzip(buf) {
    var u8 = new Uint8Array(buf), dv = new DataView(buf), eocd = -1;
    for (var i = u8.length - 22; i >= Math.max(0, u8.length - 70000); i--) { if (dv.getUint32(i, true) === 0x06054b50) { eocd = i; break; } }
    if (eocd < 0) throw new Error('Ye valid .xlsx file nahi hai');
    var count = dv.getUint16(eocd + 10, true), p = dv.getUint32(eocd + 16, true), out = {}, dec = new TextDecoder();
    for (var k = 0; k < count; k++) {
      if (dv.getUint32(p, true) !== 0x02014b50) throw new Error('Excel file kharab hai (zip)');
      var method = dv.getUint16(p + 10, true), csize = dv.getUint32(p + 20, true);
      var nlen = dv.getUint16(p + 28, true), elen = dv.getUint16(p + 30, true), clen = dv.getUint16(p + 32, true), loff = dv.getUint32(p + 42, true);
      var name = dec.decode(u8.subarray(p + 46, p + 46 + nlen));
      var start = loff + 30 + dv.getUint16(loff + 26, true) + dv.getUint16(loff + 28, true);
      out[name.replace(/^\//, '')] = { method: method, data: u8.subarray(start, start + csize) };
      p += 46 + nlen + elen + clen;
    }
    return out;
  }
  async function fileText(entries, name) {
    var e = entries[name]; if (!e) return null;
    var d = e.method === 0 ? e.data : e.method === 8 ? await inflateRaw(e.data) : null;
    if (!d) throw new Error('Unsupported compression in Excel file');
    return new TextDecoder().decode(d);
  }
  function parseXml(s) {
    var d = new DOMParser().parseFromString(s, 'application/xml');
    if (d.getElementsByTagName('parsererror').length) throw new Error('Excel XML read error');
    return d;
  }
  function els(node, tag) { return Array.prototype.slice.call(node.getElementsByTagNameNS('*', tag)); }
  function kids(node, tag) { return Array.prototype.filter.call(node.childNodes, function (c) { return c.nodeType === 1 && c.localName === tag; }); }
  function textOf(si) {
    var ts = els(si, 't').filter(function (t) { var p = t.parentNode; while (p && p !== si) { if (p.localName === 'rPh') return false; p = p.parentNode; } return true; });
    return ts.map(function (t) { return t.textContent; }).join('');
  }
  function colIndex(ref) { var m = /^([A-Z]+)/.exec(ref || ''), n = 0; if (!m) return -1; for (var i = 0; i < m[1].length; i++) n = n * 26 + (m[1].charCodeAt(i) - 64); return n - 1; }

  XL.read = async function (buf) {
    var z = await unzip(buf);
    var wb = await fileText(z, 'xl/workbook.xml');
    if (!wb) throw new Error('Ye Excel (.xlsx) file nahi hai');
    var rels = parseXml(await fileText(z, 'xl/_rels/workbook.xml.rels') || '<Relationships/>'), relMap = {};
    els(rels, 'Relationship').forEach(function (r) { relMap[r.getAttribute('Id')] = r.getAttribute('Target'); });
    var ssTxt = await fileText(z, 'xl/sharedStrings.xml'), ss = [];
    if (ssTxt) { var ssd = parseXml(ssTxt); ss = kids(ssd.documentElement, 'si').map(textOf); }
    var result = {}, sheets = els(parseXml(wb), 'sheet');
    for (var i = 0; i < sheets.length; i++) {
      var sh = sheets[i], name = sh.getAttribute('name');
      var rid = sh.getAttributeNS(REL_NS, 'id') || sh.getAttribute('r:id');
      var target = relMap[rid]; if (!target) continue;
      var path = target.charAt(0) === '/' ? target.slice(1) : 'xl/' + target.replace(/^\.\//, '');
      var txt = await fileText(z, path); if (!txt) continue;
      var doc = parseXml(txt), rows = [];
      els(doc, 'row').forEach(function (row, ri) {
        var rn = parseInt(row.getAttribute('r'), 10); rn = isFinite(rn) ? rn - 1 : ri;
        var arr = [], ci = 0;
        kids(row, 'c').forEach(function (c) {
          var idx = colIndex(c.getAttribute('r')); if (idx < 0) idx = ci; ci = idx + 1;
          var t = c.getAttribute('t'), v = kids(c, 'v')[0], val = '';
          if (t === 's') val = v ? (ss[parseInt(v.textContent, 10)] || '') : '';
          else if (t === 'inlineStr') { var is = kids(c, 'is')[0]; val = is ? textOf(is) : ''; }
          else if (t === 'b') val = v ? v.textContent === '1' : '';
          else if (t === 'e') val = '';
          else if (t === 'str') val = v ? v.textContent : '';
          else val = v ? (isFinite(parseFloat(v.textContent)) ? parseFloat(v.textContent) : v.textContent) : '';
          arr[idx] = val;
        });
        for (var q = 0; q < arr.length; q++) if (arr[q] === undefined) arr[q] = '';
        rows[rn] = arr;
      });
      for (var r = 0; r < rows.length; r++) if (!rows[r]) rows[r] = [];
      result[name] = rows;
    }
    return result;
  };
})();
