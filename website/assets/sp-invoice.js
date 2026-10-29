/* Sunpowers — printable GST invoice (shop orders + Solar Designer). Opens the browser's Print / "Save as PDF" sheet.
   Same file in Website and Store.  SPInvoice.shop(invoice)  |  SPInvoice.design(designPayment, seller) */
(function () {
  'use strict';
  if (window.SPInvoice) return;
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function m2(n) { n = Number(n) || 0; return '₹' + n.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); }
  var CSS = 'body{font-family:Arial,Helvetica,sans-serif;color:#14231a;font-size:13px;margin:0;padding:18px}h1{margin:0;font-size:22px;color:#0b2e1f}.hd{display:flex;justify-content:space-between;gap:16px;border-bottom:3px solid #1e8e3e;padding-bottom:10px;margin-bottom:12px}.t{font-size:20px;font-weight:700;color:#1e8e3e;text-align:right}.sm{font-size:12px;color:#3d4b42;line-height:1.5}' +
    'table{width:100%;border-collapse:collapse;margin-top:10px}th{background:#0b2e1f;color:#fff;padding:7px;text-align:left;font-size:12px}td{border:1px solid #d7e3d5;padding:7px;vertical-align:top}.r{text-align:right}.g{background:#e7f3e9;font-weight:700}.two{display:flex;gap:12px;margin-top:10px}.two>div{flex:1;border:1px solid #d7e3d5;border-radius:6px;padding:8px 10px}b.h{display:block;color:#1e8e3e;font-size:11px;text-transform:uppercase;letter-spacing:.05em;margin-bottom:3px}.note{margin-top:14px;font-size:11.5px;color:#4d5b52}@page{size:A4;margin:10mm}';
  function seller(s) { s = s || {}; return '<h1>' + esc(s.name || 'Sunpowers') + '</h1><div class="sm">' + esc(s.address || '') + (s.phone ? '<br>Ph: ' + esc(s.phone) : '') + (s.email ? ' · ' + esc(s.email) : '') + (s.gstin ? '<br>GSTIN: <b>' + esc(s.gstin) + '</b>' : '') + '</div>'; }
  function page(title, body) { return '<!doctype html><html><head><meta charset="utf-8"><title>' + esc(title) + '</title><style>' + CSS + '</style></head><body>' + body + '</body></html>'; }
  function shopHtml(v) {
    var b = v.buyer || {}, rows = (v.lines || []).map(function (l, i) {
      return '<tr><td>' + (i + 1) + '</td><td>' + esc(l.title) + (l.sku ? '<div class="sm">' + esc(l.sku) + '</div>' : '') + '</td><td class="r">' + esc(l.qty) + '</td><td class="r">' + m2(l.taxable) + '</td><td class="r">' + esc(l.gst_pct) + '%</td><td class="r">' + m2(l.gst_amt) + '</td><td class="r">' + m2(l.amount) + '</td></tr>';
    }).join('');
    return page('Invoice ' + v.no, '<div class="hd"><div>' + seller(v.seller) + '</div><div><div class="t">TAX INVOICE</div><div class="sm r">No: <b>' + esc(v.no) + '</b><br>Date: ' + esc(v.date) + '<br>Order: ' + esc(v.order_no || '') + '</div></div></div>' +
      '<div class="two"><div><b class="h">Bill to</b><b>' + esc(b.name || '') + '</b><div class="sm">' + esc([b.address, b.city, b.pincode].filter(Boolean).join(', ')) + (b.phone ? '<br>Ph: ' + esc(b.phone) : '') + '</div></div><div><b class="h">Payment</b><div class="sm">Prepaid — payment & location verified</div></div></div>' +
      '<table><thead><tr><th>#</th><th>Item</th><th class="r">Qty</th><th class="r">Taxable</th><th class="r">GST</th><th class="r">GST amt</th><th class="r">Amount</th></tr></thead><tbody>' + rows + '</tbody></table>' +
      '<table style="width:55%;margin-left:auto"><tr><td>Taxable value</td><td class="r">' + m2(v.taxable) + '</td></tr><tr><td>Total GST</td><td class="r">' + m2(v.gst) + '</td></tr>' + (Number(v.shipping) ? '<tr><td>Delivery</td><td class="r">' + m2(v.shipping) + '</td></tr>' : '') + '<tr class="g"><td>Grand total (paid)</td><td class="r">' + m2(v.total) + '</td></tr></table>' +
      '<div class="note">Prices include GST. This is a computer generated invoice.</div>');
  }
  function designHtml(d, s) {
    var loc = d.location || {};
    return page('Invoice ' + d.invoice_no, '<div class="hd"><div>' + seller(s) + '</div><div><div class="t">TAX INVOICE</div><div class="sm r">No: <b>' + esc(d.invoice_no) + '</b><br>Date: ' + esc(d.invoice_at ? new Date(d.invoice_at).toLocaleDateString('en-IN') : '') + '<br>Order: ' + esc(d.order_no) + '</div></div></div>' +
      '<div class="two"><div><b class="h">Bill to</b><b>' + esc(d.name || '') + '</b><div class="sm">' + (d.mobile ? 'Ph: ' + esc(d.mobile) : '') + '</div></div><div><b class="h">Design location</b><div class="sm">' + esc(loc.addr || '') + (loc.lat ? '<br>' + esc(loc.lat) + ', ' + esc(loc.lng) : '') + '</div></div></div>' +
      '<table><thead><tr><th>#</th><th>Description</th><th class="r">Taxable</th><th class="r">GST</th><th class="r">GST amt</th><th class="r">Amount</th></tr></thead><tbody><tr><td>1</td><td>Sunpowers Solar Designer — 1 rooftop solar design (2D plan, 3D view, drawing sheet &amp; quotation PDF)</td><td class="r">' + m2(d.taxable) + '</td><td class="r">' + esc(d.gst_pct) + '%</td><td class="r">' + m2(d.gst_amt) + '</td><td class="r">' + m2(d.amount) + '</td></tr></tbody></table>' +
      '<table style="width:55%;margin-left:auto"><tr class="g"><td>Total paid (incl. GST)</td><td class="r">' + m2(d.amount) + '</td></tr></table><div class="note">Digital service — no refund after the design file is downloaded. Computer generated invoice.</div>');
  }
  function print(html) {
    var f = document.createElement('iframe'); f.style.cssText = 'position:fixed;right:0;bottom:0;width:0;height:0;border:0'; document.body.appendChild(f);
    var d = f.contentWindow.document; d.open(); d.write(html); d.close();
    setTimeout(function () { try { f.contentWindow.focus(); f.contentWindow.print(); } catch (e) {} setTimeout(function () { f.remove(); }, 3000); }, 350);
  }
  /* Round 32: a customer can also SEND the invoice (link page or real PDF file) — the Send sheet loads on demand */
  var CS = document.currentScript, BASE = CS && CS.src ? CS.src.replace(/[^\/]*$/, '') : '';
  function withShare(cb, fail) {
    if (window.SPSHARE) return cb();
    var s = document.createElement('script'); s.src = BASE + 'sp-share.js?v=3'; s.onload = cb; s.onerror = fail; document.head.appendChild(s);
  }
  function inr(n) { return '\u20B9' + Math.round(Number(n) || 0).toLocaleString('en-IN'); }
  function sendDoc(html, meta) { withShare(function () { SPSHARE.open(Object.assign({ html: html, print: function () { print(html); }, phone: '' }, meta)); }, function () { print(html); }); }
  function shopSend(v) {
    var s = v.seller || {}, no = String(v.no || ''), L = v.lines || [], det = [['Invoice no', no], ['Date', v.date || ''], ['Order no', v.order_no || '']];
    L.slice(0, 8).forEach(function (l, i) { det.push(['Item ' + (i + 1), String(l.title || '') + ' \u00D7 ' + (l.qty || 1)]); });
    det.push(['Total paid', inr(v.total)]);
    sendDoc(shopHtml(v), { kind: 'invoice', title: 'Tax Invoice ' + no, subtitle: 'Order ' + (v.order_no || '') + (s.name ? ' \u00B7 ' + s.name : ''), amount: v.total, name: 'Invoice-' + no.replace(/[^\w-]+/g, '-') + '.pdf', details: det, brand: s.name, brandPhone: s.phone, ref: null,
      text: (s.name || 'Sunpowers') + ' \u2014 Tax Invoice ' + no + '\nAmount: ' + inr(v.total) + (v.date ? '\nDate: ' + v.date : '') });
  }
  function designSend(d, s0) {
    var s = s0 || {}, no = String(d.invoice_no || '');
    sendDoc(designHtml(d, s0), { kind: 'invoice', title: 'Tax Invoice ' + no, subtitle: 'Solar Designer \u00B7 Order ' + (d.order_no || ''), amount: d.amount, name: 'Invoice-' + no.replace(/[^\w-]+/g, '-') + '.pdf',
      details: [['Invoice no', no], ['Order no', d.order_no || ''], ['Service', 'Sunpowers Solar Designer \u2014 1 rooftop solar design'], ['Total paid', inr(d.amount)]], brand: s.name, brandPhone: s.phone,
      text: (s.name || 'Sunpowers') + ' \u2014 Tax Invoice ' + no + '\nAmount: ' + inr(d.amount) });
  }
  window.SPInvoice = { shopHtml: shopHtml, designHtml: designHtml, shop: shopSend, design: designSend, printShop: function (v) { print(shopHtml(v)); }, printDesign: function (d, s) { print(designHtml(d, s)); } };
})();
