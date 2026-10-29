/* Website: My Orders — prepaid orders, Solar Designer payments and GST invoices (login required) */
(function () {
  'use strict';
  var root = document.getElementById('ordPage'); if (!root) return;
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function money(n) { return '₹' + Math.round(Number(n) || 0).toLocaleString('en-IN'); }
  var ME = null, SET = {};
  function stl(s) { return ({ new: 'New', paid: 'Paid', packed: 'Packed', shipped: 'Shipped', delivered: 'Delivered', cancelled: 'Cancelled' })[s] || s; }
  function payLine(o) {
    if (o.invoice_no) return '<button class="btn btn-line btn-sm" data-io="' + o.id + '">🧾 Download Invoice ' + esc(o.invoice_no) + '</button>';
    return '<span class="wc-note">⏳ After verification of payment &amp; location, Invoice will appear here — you can download it from here.</span>';
  }
  function render() {
    var os = ME.orders || [], ds = ME.designs || [];
    root.innerHTML = '<h2 style="margin:0 0 10px">📦 My Orders (' + os.length + ')</h2>' + (os.length ? os.map(function (o) {
      return '<div class="co-i" style="display:block;border:1px solid var(--line,#e6ece4);border-radius:12px;padding:12px;margin-bottom:10px"><div style="display:flex;justify-content:space-between;gap:8px;flex-wrap:wrap"><b>' + esc(o.order_no || '#' + o.id) + '</b><span>' + esc(stl(o.status)) + '</span></div><div class="wc-note">' + esc(new Date(o.created_at).toLocaleDateString('en-IN')) + ' • Prepaid • <b>' + money(o.total) + '</b></div><div style="margin:6px 0">' + esc((o.items || []).map(function (i) { return i.title + ' × ' + i.qty; }).join(', ')) + '</div>' + payLine(o) + '</div>';
    }).join('') : '<p class="wc-note">No orders yet. <a href="shop.html">Go to shop</a></p>') +
      (ds.length ? '<h2 style="margin:22px 0 10px">📐 Solar Designer payments (' + ds.length + ')</h2>' + ds.map(function (d) {
        return '<div class="co-i" style="display:block;border:1px solid var(--line,#e6ece4);border-radius:12px;padding:12px;margin-bottom:10px"><div style="display:flex;justify-content:space-between;gap:8px;flex-wrap:wrap"><b>' + esc(d.order_no) + '</b><span>' + (d.status === 'verified' ? 'Verified' : d.status === 'submitted' ? 'Checking' : d.status === 'rejected' ? 'Rejected' : 'Payment pending') + '</span></div><div class="wc-note">' + esc(new Date(d.created_at).toLocaleDateString('en-IN')) + ' • <b>' + money(d.amount) + '</b>' + (d.location && d.location.addr ? ' • 📍 ' + esc(d.location.addr) : '') + '</div>' +
          (d.invoice_no ? '<button class="btn btn-line btn-sm" data-id="' + d.id + '">🧾 Download Invoice ' + esc(d.invoice_no) + '</button>' : '<span class="wc-note">⏳ After verification of payment &amp; location, Invoice will appear here.</span>') + '</div>';
      }).join('') : '');
  }
  root.addEventListener('click', function (e) {
    var a = e.target.closest('[data-io],[data-id]'); if (!a || !ME || !window.SPInvoice) return;
    var sel = { name: SET.legalName || SET.storeName || 'Sunpowers', gstin: SET.gstin, address: SET.address, phone: SET.phone, email: SET.email };
    if (a.hasAttribute('data-io')) { var o = (ME.orders || []).filter(function (x) { return String(x.id) === a.getAttribute('data-io'); })[0]; if (o && o.invoice) SPInvoice.shop(o.invoice); }
    else { var d = (ME.designs || []).filter(function (x) { return String(x.id) === a.getAttribute('data-id'); })[0]; if (d) SPInvoice.design(d, sel); }
  });
  function go() {
    if (!window.SPGate || !SPGate.active()) { root.innerHTML = '<p>Login could not load. Please refresh.</p>'; return; }
    SPGate.require('orders', function () {
      SPGate.me().then(function (r) { ME = (r && r.me) || {}; return window.SPCART && SPCART.load ? SPCART.load().catch(function () { return null; }) : null; })
        .then(function (s) { SET = (s && s.settings) || {}; render(); });
    });
  }
  root.innerHTML = '<p class="wc-note">…</p>'; go();
})();
