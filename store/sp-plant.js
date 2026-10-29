/* Sunpowers "Meri Profile" — Customer Hub card (website shop page + store app), right under the header.
   Round 49: purana "My Plant" ab ek hi hub card hai — Project / Product / Service ke hisaab se alag home, status, Documents, AMC, Support, Checkup, Savings, Order page.
   Login (mobile / email) ke baad apne aap khulta hai; customer ke mobile se juda sab kuch server se aata hai (crm_consumer_hub). Customer sirf dekhta / download karta hai.
   Config: SPPlant.init({ getToken:()=>token|null, rpc:(fn,p)=>Promise, after:()=>element (card is element ke theek baad lagta hai) }) */
(function () {
  'use strict';
  var CS = document.currentScript, BASE = CS && CS.src ? CS.src.replace(/[^\/]*$/, '') : '';
  function withBen(cb) { if (window.SPBEN) return cb(); var e = document.createElement('script'); e.src = BASE + 'sp-benefits.js?v=1'; e.onload = cb; e.onerror = cb; document.head.appendChild(e); }
  function withShare(cb, fail) { if (window.SPSHARE) return cb(); var e = document.createElement('script'); e.src = BASE + 'sp-share.js?v=3'; e.onload = cb; e.onerror = fail; document.head.appendChild(e); }
  var P = window.SPPlant = {}, cfg = null, host = null, prof = null, jobs = [], sel = '', panel = '', loaded = false, failed = false, busy = false, flash = '', flashBad = false, showSw = false, shown = '', locked = false;
  var F = { complaint: '', priority: 'Normal', chk: {}, gen: '', cnote: '', rname: '', rmob: '', rnote: '' };

  /* ---------- icons (line icons, white) ---------- */
  var IC = {
    docs: '<path d="M7 3h7l5 5v13H7z"/><path d="M14 3v5h5M10 13h6M10 17h6"/>',
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M4.9 19.1L7 17M17 7l2.1-2.1"/>',
    cal: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4M8 15l2.5 2.5L16 13"/>',
    alert: '<path d="M12 3l10 18H2z"/><path d="M12 10v5M12 18v.5"/>',
    head: '<path d="M4 14v-2a8 8 0 0116 0v2"/><rect x="3" y="14" width="4" height="6" rx="1.5"/><rect x="17" y="14" width="4" height="6" rx="1.5"/><path d="M19 20c0 1.5-2 2-5 2"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    swap: '<path d="M7 7h12l-3-3M17 17H5l3 3"/>',
    wa: '<path d="M3 21l1.6-4.8A8.5 8.5 0 1112 20.5a8.4 8.4 0 01-4.2-1.1z"/><path d="M9 9c0 3 3 6 6 6l1.3-1.6-2-1-1 .8c-1-.5-1.9-1.4-2.4-2.4l.8-1-1-2z"/>',
    box: '<path d="M3 7l9-4 9 4v10l-9 4-9-4z"/><path d="M3 7l9 4 9-4M12 11v10"/>',
    truck: '<path d="M2 6h11v10H2zM13 9h5l3 3v4h-8"/><circle cx="7" cy="18" r="2"/><circle cx="17" cy="18" r="2"/>',
    shield: '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/><path d="M8.5 12l2.5 2.5L16 9.5"/>',
    wrench: '<path d="M14.5 6a4 4 0 005 5l-9.5 9.5a2.1 2.1 0 01-3-3L16.5 8z"/><path d="M14 6l3-3 3 3-3 3"/>',
    check: '<path d="M5 12.5l4.5 4.5L19 7"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    back: '<path d="M15 5l-7 7 7 7"/>',
    phone: '<path d="M5 4h4l2 5-2.5 1.5a11 11 0 005 5L15 13l5 2v4a2 2 0 01-2 2A16 16 0 013 6a2 2 0 012-2z"/>',
    gift: '<rect x="3" y="9" width="18" height="12" rx="1"/><path d="M3 13h18M12 9v12M12 9c-3 0-5-1-5-3s3-3 5 0c2-3 5-2 5 0s-2 3-5 3z"/>',
    list: '<path d="M8 6h13M8 12h13M8 18h13M3.5 6h.01M3.5 12h.01M3.5 18h.01"/>',
    pin: '<path d="M12 21s7-6 7-12a7 7 0 10-14 0c0 6 7 12 7 12z"/><circle cx="12" cy="9" r="2.5"/>',
    star: '<path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z"/>'
  };
  function ic(n, s) { return '<svg viewBox="0 0 24 24" width="' + (s || 26) + '" height="' + (s || 26) + '" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (IC[n] || '') + '</svg>'; }

  var CSS = '.sph{max-width:860px;margin:12px auto 0;padding:0 14px;font-family:inherit;color:#1c2a22;box-sizing:border-box}.sph *{box-sizing:border-box}' +
    'header[data-sph]{position:static!important}header[data-sph] #sp-plant{padding:0;margin:8px auto 12px}' +
    '.sph-wrap{container-type:inline-size;width:100%}' +
    '.sph-card{position:relative;aspect-ratio:16/9;width:100%;display:flex;flex-direction:column;justify-content:space-between;gap:1.2cqw;padding:12px 13px 11px;padding:3.2cqw 3.4cqw 3cqw;background:linear-gradient(135deg,#a85a05 0%,#c26b08 55%,#d98a1c 100%);color:#fff;border-radius:18px;border-radius:max(14px,4.4cqw);box-shadow:0 10px 28px rgba(150,80,0,.28);overflow:hidden}' +
    '.sph-card:before{content:"";position:absolute;right:-8%;top:-14%;width:42%;aspect-ratio:1;border-radius:50%;background:rgba(255,255,255,.07);pointer-events:none}' +
    '.sph-wrap.hasbn .sph-card{border-bottom-left-radius:0;border-bottom-right-radius:0}' +
    '.sph-top{display:flex;align-items:flex-start;justify-content:space-between;gap:7px;gap:2cqw;position:relative;min-height:0}.sph-hello{flex:1;min-width:0}' +
    '.sph-hello h2{margin:0;font-size:17px;font-size:clamp(15px,4.8cqw,32px);line-height:1.12;font-weight:800;color:#fff;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}' +
    '.sph-live{display:inline-flex;align-items:center;gap:6px;gap:1.5cqw;margin-top:5px;margin-top:1.3cqw;background:#fff8ec;color:#3b2a0f;border-radius:999px;padding:3px 9px;padding:.8cqw 2.4cqw;font-weight:800;font-size:11px;font-size:clamp(11px,2.7cqw,15px);max-width:100%}.sph-live i{width:8px;height:8px;width:clamp(7px,1.9cqw,11px);height:clamp(7px,1.9cqw,11px);border-radius:50%;background:#1fa355;box-shadow:0 0 0 3px rgba(31,163,85,.22);flex:none}.sph-live span{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}' +
    '.sph-live.o i{background:#e08a00;box-shadow:0 0 0 3px rgba(224,138,0,.25)}.sph-live.n i{background:#7b8794;box-shadow:none}' +
    '.sph-sub{font-size:11px;font-size:clamp(11px,2.4cqw,14px);opacity:.92;margin-top:4px;margin-top:1cqw;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}' +
    '.sph-qa{display:flex;gap:5px;gap:1.4cqw;flex:none}.sph-q{display:flex;flex-direction:column;align-items:center;gap:3px;width:40px;width:clamp(38px,11.4cqw,76px);background:none;border:0;color:#fff;cursor:pointer;font:inherit;font-size:10.5px;font-size:clamp(10.5px,2.2cqw,12px);font-weight:700;text-align:center;line-height:1.15;padding:0}' +
    '.sph-q span{width:27px;height:27px;width:clamp(26px,7.4cqw,46px);height:clamp(26px,7.4cqw,46px);border-radius:50%;background:rgba(255,255,255,.18);border:1.5px solid rgba(255,255,255,.55);display:grid;place-items:center;transition:transform .15s}.sph-q span svg{width:56%;height:56%}.sph-q:hover span{transform:scale(1.06)}.sph-q.on span{background:#fff;color:#a85a05}' +
    '.sph-tiles{display:grid;grid-template-columns:repeat(var(--n,5),1fr);gap:6px;gap:1.8cqw;position:relative}' +
    '.sph-t{position:relative;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;gap:.9cqw;min-height:52px;min-height:17cqw;border-radius:12px;border-radius:max(10px,3.2cqw);background:rgba(255,255,255,.14);border:1px solid rgba(255,255,255,.3);color:#fff;font:inherit;font-weight:800;font-size:10.5px;font-size:clamp(10.5px,2.5cqw,13.5px);cursor:pointer;padding:3px 2px;padding:.8cqw .4cqw;text-align:center;line-height:1.1;transition:background .15s,transform .15s;min-width:0}' +
    '.sph-t:hover{background:rgba(255,255,255,.24);transform:translateY(-1px)}.sph-t.on{background:#fff;color:#7a3f00;border-color:#fff}.sph-t .ti{width:24px;height:24px;width:clamp(22px,6.6cqw,44px);height:clamp(22px,6.6cqw,44px);border-radius:9px;background:rgba(255,255,255,.2);display:grid;place-items:center}.sph-t .ti svg{width:62%;height:62%}.sph-t.on .ti{background:#fde9cc}.sph-t>span:last-child,.sph-t .tl{display:block;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}' +
    '.sph-bdg{position:absolute;top:3px;right:3px;min-width:15px;height:15px;padding:0 4px;border-radius:8px;background:#c9382d;color:#fff;font-size:9.5px;font-weight:800;display:grid;place-items:center;line-height:1}' +
    '.sph-st{display:flex;align-items:center;gap:6px;gap:1.6cqw;position:relative}.sph-st>b{font-size:11px;font-size:clamp(11px,2.7cqw,14px);flex:none}.sph-strip{flex:1;min-width:0;display:flex;gap:5px;gap:1.3cqw;overflow-x:auto;background:#fff;border-radius:10px;border-radius:max(9px,2.6cqw);padding:3px 5px;padding:.8cqw 1.4cqw;scrollbar-width:none}.sph-strip::-webkit-scrollbar{display:none}' +
    '.sph-pill{flex:none;display:flex;align-items:center;gap:4px;gap:1cqw;border-radius:999px;padding:2px 8px 2px 2px;padding:.4cqw 2cqw .4cqw .4cqw;background:#eef1f5;color:#44505c;font-size:11px;font-size:clamp(11px,2.4cqw,13.5px);font-weight:700;white-space:nowrap}.sph-pill i{font-style:normal;width:16px;height:16px;width:clamp(15px,4.2cqw,24px);height:clamp(15px,4.2cqw,24px);border-radius:50%;background:#9aa6b2;color:#fff;display:grid;place-items:center;font-size:10.5px;font-size:clamp(10.5px,2.2cqw,12px)}' +
    '.sph-pill.d{background:#e6f6ec;color:#17613a}.sph-pill.d i{background:#1f8a4c}.sph-pill.now{background:#fff1d6;color:#7a3f00;box-shadow:0 0 0 2px #e08a00 inset}.sph-pill.now i{background:#e08a00}.sph-pill.x{background:#fde8e6;color:#9b2118}.sph-pill.x i{background:#c9382d}' +
    '.sph-bn{display:flex;align-items:center;gap:8px;background:#fff6e5;border:1px solid #f0d29a;border-top:0;border-radius:0 0 14px 14px;padding:4px 8px 4px 12px;color:#5b4a2e;min-height:34px}.sph-bn .bi{color:#c26b08;font-size:14px;line-height:1}.sph-bn b{flex:1;min-width:0;font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.sph-bn .sph-b{padding:4px 12px;font-size:12px;border-radius:999px;white-space:nowrap}' +
    '.sph-sheet{position:fixed;inset:0;z-index:9990;display:flex;align-items:flex-end;justify-content:center;animation:sphfade .18s ease-out}.sph-sov{position:absolute;inset:0;background:rgba(25,14,0,.55)}' +
    '.sph-sp{position:relative;background:#fffdf8;width:100%;height:100%;display:flex;flex-direction:column;color:#1c2a22;animation:sphup .22s ease-out}' +
    '@media(min-width:720px){.sph-sheet{align-items:center}.sph-sp{width:min(660px,94vw);height:auto;max-height:90vh;border-radius:22px;overflow:hidden;box-shadow:0 24px 60px rgba(0,0,0,.35)}}' +
    '.sph-sh{display:flex;align-items:center;gap:10px;padding:12px 14px 10px;padding-top:calc(12px + env(safe-area-inset-top,0px));background:#fff;border-bottom:1px solid #eee3d0;flex:none}@media(min-width:720px){.sph-sh{padding-top:12px}}.sph-sh h3{margin:0;font-size:18px;flex:1;min-width:0}' +
    '.sph-sb{overflow-y:auto;-webkit-overflow-scrolling:touch;overscroll-behavior:contain;padding:14px;padding-bottom:calc(18px + env(safe-area-inset-bottom,0px));flex:1;min-height:0}' +
    '.sph-x{width:36px;height:36px;border-radius:50%;border:1px solid #e0d3bd;background:#fff8ec;color:#7a3f00;display:grid;place-items:center;cursor:pointer;font-size:18px;line-height:1;padding:0}' +
    '@keyframes sphup{from{transform:translateY(24px);opacity:.4}to{transform:none;opacity:1}}@keyframes sphfade{from{opacity:0}to{opacity:1}}@media(prefers-reduced-motion:reduce){.sph-sheet,.sph-sp{animation:none}}' +
    '.sph-sw{display:flex;flex-direction:column;gap:8px}.sph-chip{display:flex;align-items:center;gap:10px;border:1.5px solid #e0d3bd;background:#fffdf8;color:#3b2a0f;border-radius:14px;padding:10px 12px;font:inherit;font-size:14px;font-weight:700;cursor:pointer;text-align:left;width:100%}' +
    '.sph-chip small{display:block;font-weight:600;opacity:.75;font-size:12px}.sph-chip b{display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.sph-chip>span{min-width:0}.sph-chip.on{background:#fff1d6;border-color:#b45f06}.sph-chip svg{flex:none;color:#a85a05}' +
    '.sph-pn{margin-top:12px;background:#fff;border:1px solid #e6dccb;border-radius:20px;padding:16px;box-shadow:0 6px 20px rgba(120,70,0,.08)}.sph-ph{display:flex;align-items:center;gap:10px;margin-bottom:12px}.sph-ph h3{margin:0;font-size:18px;flex:1}.sph-back{width:36px;height:36px;border-radius:50%;border:1px solid #e0d3bd;background:#fff8ec;color:#7a3f00;display:grid;place-items:center;cursor:pointer}' +
    '.sph-msg{margin:0 0 10px;padding:9px 12px;border-radius:12px;font-size:14px;background:#e6f6ec;color:#17613a}.sph-msg.bad{background:#fde8e6;color:#9b2118}.sph-note{margin:10px 0 0;padding:9px 12px;border-radius:12px;font-size:12.5px;background:#fff8ec;color:#6b4a1c;line-height:1.5}' +
    '.sph-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}@media(max-width:700px){.sph-grid{grid-template-columns:1fr 1fr}}@media(max-width:420px){.sph-grid{grid-template-columns:1fr}}' +
    '.sph-k{border:1px solid #eadfcb;background:#fffdf8;border-radius:16px;padding:13px 14px}.sph-k h4{margin:0 0 4px;font-size:12px;letter-spacing:.05em;text-transform:uppercase;color:#8a6a3a}.sph-k .big{font-size:25px;font-weight:800;line-height:1.1;color:#3b2a0f}.sph-k small{display:block;color:#7a6a52;font-size:12.5px;margin-top:3px}.sph-k.g{background:#f2fbf5;border-color:#bfe3cc}.sph-k.w{background:#fff6e5;border-color:#f0d29a}' +
    '.sph-li{display:flex;align-items:center;gap:10px;flex-wrap:wrap;border:1px solid #eadfcb;border-radius:14px;padding:10px 12px;margin-top:8px;background:#fff}.sph-li .ico{width:38px;height:38px;border-radius:11px;background:#fff1d6;color:#a85a05;display:grid;place-items:center;flex:none}.sph-li .m{flex:1;min-width:150px}.sph-li .m b{display:block;font-size:14.5px}.sph-li .m span{font-size:12.5px;color:#7a6a52}' +
    '.sph-b{border:0;border-radius:11px;background:#b45f06;color:#fff;font:inherit;font-size:13.5px;font-weight:700;padding:8px 14px;cursor:pointer;display:inline-flex;align-items:center;gap:6px;text-decoration:none}.sph-b.g{background:#fff;color:#7a3f00;border:1px solid #e0d3bd}.sph-b.wa{background:#1fa355}.sph-b:disabled{opacity:.6;cursor:default}.sph-b.sm{padding:6px 11px;font-size:12.5px}' +
    '.sph-tag{border-radius:999px;padding:3px 11px;font-size:12px;font-weight:800;background:#eef1f5;color:#44505c;white-space:nowrap}.sph-tag.g{background:#e6f6ec;color:#17613a}.sph-tag.o{background:#fff1d6;color:#7a3f00}.sph-tag.r{background:#fde8e6;color:#9b2118}.sph-tag.b{background:#e3effd;color:#17508f}' +
    '.sph-f{display:flex;flex-direction:column;gap:5px;margin-top:10px}.sph-f label{font-size:13px;font-weight:700;color:#5b4a2e}.sph-f input,.sph-f textarea,.sph-f select{width:100%;border:1.5px solid #e0d3bd;border-radius:12px;padding:10px 12px;font:inherit;font-size:15px;background:#fff;color:#1c2a22}.sph-f textarea{min-height:76px;resize:vertical}' +
    '.sph-chk{border-top:1px solid #f0e6d4;padding:10px 0;display:flex;align-items:center;gap:10px;flex-wrap:wrap}.sph-chk:first-of-type{border-top:0}.sph-chk .q{flex:1;min-width:200px;font-size:14.5px;font-weight:600}.sph-seg{display:inline-flex;border:1.5px solid #e0d3bd;border-radius:12px;overflow:hidden}.sph-seg button{border:0;background:#fff;padding:7px 12px;font:inherit;font-size:13px;font-weight:700;cursor:pointer;color:#5b4a2e}.sph-seg button+button{border-left:1px solid #e0d3bd}.sph-seg button.ok.on{background:#1f8a4c;color:#fff}.sph-seg button.bad.on{background:#c9382d;color:#fff}.sph-seg button.na.on{background:#7b8794;color:#fff}' +
    '.sph-tl{position:relative;margin:6px 0 0 8px;padding-left:22px;border-left:2px solid #eadfcb}.sph-tl .s{position:relative;padding:0 0 14px}.sph-tl .s:before{content:"";position:absolute;left:-30px;top:1px;width:16px;height:16px;border-radius:50%;background:#e9e1d2;border:2px solid #fff;box-shadow:0 0 0 2px #e9e1d2}.sph-tl .s.d:before{background:#1f8a4c;box-shadow:0 0 0 2px #1f8a4c}.sph-tl .s.now:before{background:#e08a00;box-shadow:0 0 0 2px #e08a00}.sph-tl b{font-size:14.5px}.sph-tl span{display:block;font-size:12.5px;color:#7a6a52}' +
    '.sph-empty{text-align:center;padding:26px 14px;color:#6b4a1c}.sph-empty .ei{width:70px;height:70px;border-radius:50%;background:#fff1d6;color:#a85a05;display:grid;place-items:center;margin:0 auto 10px}.sph-empty h3{margin:0 0 6px;font-size:19px}.sph-cta{display:flex;gap:8px;flex-wrap:wrap;justify-content:center;margin-top:12px}' +
    '.sph-sk{aspect-ratio:16/9;width:100%;border-radius:20px;background:linear-gradient(90deg,#f1e3cc,#fbf1df,#f1e3cc);background-size:200% 100%;animation:sphsk 1.2s infinite}@keyframes sphsk{to{background-position:-200% 0}}';

  /* host page ke generic button/input CSS se bachne ke liye har rule #sp-plant ke andar scope */
  function scope(c) { return c.replace(/\.sph\{/g, '#sp-plant{').replace(/\.sph \*\{/g, '#sp-plant *{').replace(/\.sph-/g, '#sp-plant .sph-'); }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function tok() { try { return cfg && cfg.getToken && cfg.getToken(); } catch (e) { return null; } }
  function call(fn, p) { p = p || {}; p.token = tok(); return cfg.rpc(fn, p); }
  function fd(s) { if (!s) return '—'; var d = new Date(String(s).length <= 10 ? s + 'T00:00:00' : s); if (isNaN(d)) return esc(String(s).slice(0, 10)); return d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }); }
  function money(n) { return '₹' + Number(n || 0).toLocaleString('en-IN', { maximumFractionDigits: 2 }); }
  function rs(n) { return '₹' + Math.round(Number(n || 0)).toLocaleString('en-IN'); }
  function ym(s) { var m = /^(\d{4})-(\d{2})$/.exec(s || ''); if (!m) return esc(s || ''); return ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][+m[2] - 1] + ' ' + m[1]; }
  var parkNode = null;
  function parkEl() { if (!parkNode || !document.body.contains(parkNode)) { parkNode = document.createElement('div'); parkNode.id = 'sp-plant-park'; parkNode.hidden = true; document.body.appendChild(parkNode); } return parkNode; }
  function ensureHost() {
    if (!document.getElementById('sph-css')) { var st = document.createElement('style'); st.id = 'sph-css'; st.textContent = scope(CSS); document.head.appendChild(st); }
    if (host && document.body.contains(host)) return host;
    if (cfg.manual) { host = document.createElement('section'); host.className = 'sph'; host.id = 'sp-plant'; host.setAttribute('data-noi18n', ''); parkEl().appendChild(host); return host; }
    var into = cfg.into && cfg.into(), a = into ? null : (cfg.after && cfg.after()); if (!(into && into.parentNode) && !(a && a.parentNode)) return null;
    host = document.createElement('section'); host.className = 'sph'; host.id = 'sp-plant'; host.setAttribute('data-noi18n', '');
    if (into && into.parentNode) into.parentNode.insertBefore(host, into); else a.parentNode.insertBefore(host, a.nextSibling);
    return host;
  }

  /* ---------- data ---------- */
  var STL = { new: 'Order mila', confirmed: 'Order confirm', paid: 'Payment mila', shipped: 'Dispatch ho gaya', delivered: 'Delivered', cancelled: 'Cancelled' };
  function firstName() { var n = String((prof && prof.name) || '').trim().split(/\s+/)[0] || 'Customer'; return n.charAt(0).toUpperCase() + n.slice(1); }
  function build() {
    jobs = [];
    ((prof && prof.projects) || []).forEach(function (p) { jobs.push({ k: 'proj', key: 'p' + p.id, p: p }); });
    ((prof && prof.services) || []).forEach(function (p) { jobs.push({ k: 'serv', key: 's' + p.id, p: p }); });
    if (((prof && prof.products) || []).length || ((prof && prof.orders) || []).length) jobs.push({ k: 'prod', key: 'prod' });
    if (((prof && prof.inquiries) || []).length) jobs.push({ k: 'inq', key: 'inq' });
    if (!jobs.some(function (j) { return j.key === sel; })) sel = jobs.length ? jobs[0].key : '';
  }
  function curJob() { for (var i = 0; i < jobs.length; i++) if (jobs[i].key === sel) return jobs[i]; return null; }
  function curP() { var j = curJob(); return j && j.p || null; }
  function load() {
    if (!tok()) { prof = null; jobs = []; loaded = false; failed = false; render(); return Promise.resolve(); }
    if (!loaded) render();
    return call('crm_consumer_hub').then(function (r) {
      prof = r || null; failed = !prof; loaded = true; build(); render();
    }, function () { loaded = true; failed = true; render(); });
  }
  function say(m, bad) { flash = m || ''; flashBad = !!bad; busy = false; render(); }
  function openCompl() { return ((prof && prof.complaints) || []).filter(function (c) { return c.status !== 'Resolved'; }); }
  function pendBills() { return ((prof && prof.bills) || []).filter(function (b) { return b.state === 'pending'; }); }
  function lastOrder() { return ((prof && prof.orders) || [])[0] || null; }
  function co() { return (prof && prof.company) || {}; }
  function digits(s) { return String(s || '').replace(/\D/g, ''); }
  function waLink(txt) { var d = digits(co().whatsapp || co().phone); if (d.length === 10) d = '91' + d; return d ? 'https://wa.me/' + d + '?text=' + encodeURIComponent(txt || 'Namaste, mujhe madad chahiye.') : ''; }
  function telLink() { var d = digits(co().phone); return d ? 'tel:+' + (d.length === 10 ? '91' + d : d) : ''; }
  function nowYm() { return new Date(Date.now() + 19800000).toISOString().slice(0, 7); }

  /* ---------- card pieces ---------- */
  function liveChip(j) {
    var t = '', c = '';
    if (!j) { t = 'Swagat hai — aapka account taiyar hai'; c = 'o'; }
    else if (j.k === 'proj') { var p = j.p; t = (p.finished ? 'Plant poora' : p.installed ? 'Plant Live' : 'Kaam chal raha hai') + (p.kw ? ' · ' + p.kw + ' kW' : ''); c = p.installed || p.finished ? '' : 'o'; }
    else if (j.k === 'serv') { t = (j.p.title || j.p.ctype || 'Service') + ' · ' + (j.p.job_status || 'Chal raha hai'); c = j.p.job_status === 'Poora hua' ? '' : 'o'; }
    else if (j.k === 'prod') { var o = lastOrder(); if (o) { t = 'Order ' + (STL[o.status] || o.status); c = o.status === 'delivered' ? '' : o.status === 'cancelled' ? 'n' : 'o'; } else { t = 'Aapke products surakshit hain'; c = ''; } }
    else { t = 'Quotation process me'; c = 'o'; }
    return '<div class="sph-live ' + c + '"><i></i><span>' + esc(t) + '</span></div>';
  }
  function tiles(j) {
    var T = [];
    if (!j) T = [['link', 'plus', 'Plant ID jodein'], ['support', 'head', 'Support']];
    else if (j.k === 'proj') T = [['docs', 'docs', 'Documents'], ['savings', 'sun', 'Savings'], ['amc', 'cal', 'AMC Plan'], ['error', 'alert', 'Find Error'], ['support', 'head', 'Support']];
    else if (j.k === 'serv') T = [['docs', 'docs', 'Documents'], ['amc', 'cal', 'AMC Plan'], ['error', 'alert', 'Find Error'], ['support', 'head', 'Support']];
    else if (j.k === 'prod') T = [['orders', 'box', 'Orders'], ['bills', 'docs', 'Bills'], ['warranty', 'shield', 'Warranty'], ['error', 'alert', 'Find Error'], ['support', 'head', 'Support']];
    else T = [['inq', 'list', 'Quotations'], ['support', 'head', 'Support'], ['refer', 'gift', 'Dost ko refer']];
    var oc = openCompl().length;
    return '<div class="sph-tiles" style="--n:' + T.length + '">' + T.map(function (t) {
      var attr = t[0] === 'error' ? ' data-doctor="inverter"' : ' data-act="tile" data-v="' + t[0] + '"';
      var n = t[0] === 'support' ? oc : (t[0] === 'bills' || t[0] === 'docs') ? pendBills().length : 0, bd = n ? '<em class="sph-bdg" aria-label="' + n + (t[0] === 'support' ? ' khuli' : ' bill pending') + '">' + n + '</em>' : '';
      return '<button type="button" class="sph-t' + (panel === t[0] ? ' on' : '') + '"' + attr + '><span class="ti">' + ic(t[1], 26) + '</span><span class="tl">' + t[2] + '</span>' + bd + '</button>';
    }).join('') + '</div>';
  }
  function steps(j) {
    var out = [];
    if (j && (j.k === 'proj' || j.k === 'serv')) {
      var tl = (j.p.timeline || []).filter(function (s) { return !(s.n === 13 && j.p.ctype !== 'Residential'); }), now = -1;
      tl.forEach(function (s, i) { if (now < 0 && !s.done) now = i; });
      out = tl.map(function (s, i) { return { t: s.name, c: s.done ? 'd' : i === now ? 'now' : '', i: s.done ? '✓' : (i + 1) }; });
    } else if (j && j.k === 'prod') {
      var o = lastOrder();
      if (!o) out = [{ t: 'Kharid poora', c: 'd', i: '✓' }];
      else if (o.status === 'cancelled') out = [{ t: 'Order cancelled', c: 'x', i: '×' }];
      else {
        var names = ['Order', 'Confirm', 'Payment', o.pickup ? 'Pickup ready' : 'Dispatch', 'Delivered'], idx = { new: 0, confirmed: 1, paid: 2, shipped: 3, delivered: 4 }[o.status]; if (idx == null) idx = 0;
        out = names.map(function (n, i) { return { t: n, c: i <= idx && (i < idx || o.status === 'delivered') ? 'd' : i === idx ? 'now' : '', i: i < idx || (i === idx && o.status === 'delivered') ? '✓' : (i + 1) }; });
      }
    } else if (j) out = [{ t: 'Quotation', c: 'd', i: '✓' }, { t: 'Confirmation', c: 'now', i: 2 }, { t: 'Kaam shuru', c: '', i: 3 }];
    if (!out.length) return '';
    return '<div class="sph-st"><b>Status</b><div class="sph-strip">' + out.map(function (s) { return '<span class="sph-pill ' + s.c + '"><i>' + s.i + '</i>' + esc(s.t) + '</span>'; }).join('') + '</div></div>';
  }
  function switcher() {
    var h = jobs.map(function (j) {
      var ty = j.k === 'proj' ? 'Project' : j.k === 'serv' ? 'Service' : j.k === 'prod' ? 'Products' : 'Quotations', nm = j.k === 'proj' || j.k === 'serv' ? (j.p.title || j.p.plant_id) : j.k === 'prod' ? ((prof.orders || []).length + (prof.products || []).length) + ' kharid' : (prof.inquiries || []).length + ' pending';
      return '<button type="button" class="sph-chip' + (j.key === sel ? ' on' : '') + '" data-act="pick" data-v="' + esc(j.key) + '">' + ic(j.k === 'proj' ? 'sun' : j.k === 'serv' ? 'wrench' : j.k === 'prod' ? 'box' : 'list', 20) + '<span><small>' + ty + (j.p && j.p.plant_id ? ' · ' + esc(j.p.plant_id) : '') + '</small><b>' + esc(nm) + '</b></span></button>';
    }).join('');
    h += '<button type="button" class="sph-chip" data-act="tile" data-v="link">' + ic('plus', 20) + '<span><small>Naya</small><b>Plant ID jodein</b></span></button>';
    return '<div class="sph-sw">' + h + '</div>';
  }
  function bannerBills() {
    var b = pendBills(); if (!b.length) return '';
    var tot = b.reduce(function (a, x) { return a + Number(x.balance || 0); }, 0);
    return '<div class="sph-bn"><span class="bi" aria-hidden="true">⚠</span><b>' + b.length + ' bill baaki · ' + rs(tot) + '</b><button type="button" class="sph-b sm" data-act="tile" data-v="bills">Bills dekhein</button></div>';
  }

  /* ---------- panels ---------- */
  function li(icon, title, sub, btns) { return '<div class="sph-li"><span class="ico">' + ic(icon, 22) + '</span><div class="m"><b>' + esc(title) + '</b><span>' + sub + '</span></div>' + (btns || '') + '</div>'; }
  function bt(act, v, label, cls) { return '<button type="button" class="sph-b ' + (cls || 'g') + ' sm" data-act="' + act + '" data-v="' + esc(v) + '">' + label + '</button>'; }
  function dbtn(kind) { return bt('dprint', kind, 'Dekhein / Download') + bt('dsend', kind, 'Bhejein'); }
  function empty(icon, title, text, cta) { return '<div class="sph-empty"><div class="ei">' + ic(icon, 34) + '</div><h3>' + esc(title) + '</h3><div>' + text + '</div>' + (cta ? '<div class="sph-cta">' + cta + '</div>' : '') + '</div>'; }
  function contactBtns() {
    var t = telLink(), w = waLink(), h = '';
    if (t) h += '<a class="sph-b" href="' + t + '">' + ic('phone', 16) + ' Call karein</a>';
    if (w) h += '<a class="sph-b wa" href="' + w + '" target="_blank" rel="noopener">' + ic('wa', 16) + ' WhatsApp</a>';
    return h;
  }
  function warrantyList(arr) {
    if (!arr.length) return empty('shield', 'Warranty ki jaankari abhi nahi', 'Bill banne ke baad products ki warranty yahan dikhegi.');
    return arr.map(function (x) { return li('shield', x.name, x.brand ? esc(x.brand) : 'Warranty', '<span class="sph-tag g">' + esc(x.warranty) + '</span>'); }).join('');
  }
  function fileIcon(n) { return /\.(png|jpe?g|webp|gif)$/i.test(n || '') ? 'star' : 'docs'; }
  var UCATS = ['ID proof', 'Bijli bill', 'Chhat ki photo', 'Payment screenshot', 'Other'], MINE = 'Customer ne bheja';
  function dOn(k) { var c = (prof && prof.docs_cfg) || {}; return String(c[k]) !== '0'; }
  function dHidden(cat) { var c = (prof && prof.docs_cfg) || {}; return Array.isArray(c.hide_cats) && c.hide_cats.indexOf(cat) >= 0; }
  function pDocs(j) {
    var p = j.p, h = '<p class="sph-note" style="margin:0 0 6px">Yahan aapke is kaam ke saare documents hain — Sunpowers jo bhejti hai wo apne aap yahin judta hai' + (dOn('upload') ? ', aur aap apni file bhi bhej sakte hain' : '') + '.</p>';
    var H = function (t) { return '<h4 style="margin:14px 0 2px;font-size:13px;color:#8a6a3a;text-transform:uppercase;letter-spacing:.05em">' + esc(t) + '</h4>'; };
    if (p.online) { if (!p.has_bill && dOn('quotation')) h += li('docs', 'Order bill (payment baaki)', esc(p.plant_id || ''), dbtn('quotation')); }
    else if (dOn('quotation')) h += li('docs', 'Final Quotation', esc(p.plant_id || ''), dbtn('quotation'));
    if (p.has_bill && dOn('bill')) h += li('docs', 'Bill / Invoice', esc(p.bill_ref || ''), dbtn('bill'));
    var rcs = ((prof.receipts) || []).filter(function (r) { return r.quote_id === p.id; });
    if (rcs.length && dOn('receipt')) { h += H('Rasid (payment receipt)'); rcs.forEach(function (r) { h += li('check', 'Rasid ' + (r.ref || ''), fd(r.date) + ' · ' + rs(r.amount) + (r.mode ? ' · ' + esc(r.mode) : '') + (r.bill ? ' · Bill ' + esc(r.bill) : ''), bt('rprint', r.id, 'Dekhein / Download')); }); }
    if (dOn('maintenance')) h += li('wrench', 'Maintenance summary', 'AMC aur service visits ka record', dbtn('maintenance'));
    var cks = dOn('checkup') ? ((prof.checkups) || []).filter(function (c) { return c.quote_id === p.id; }) : [];
    cks.forEach(function (c) { h += li('cal', 'Routine Checkup — ' + ym(c.ym), 'Aapne khud bhara' + (c.gen_kwh != null ? ' · generation ' + c.gen_kwh + ' kWh' : ''), bt('cprint', c.ym, 'Dekhein / Download')); });
    var files = (p.files || []).filter(function (f) { var c = (prof.doc_cats || {})[f.id] || 'Anya documents'; return c === MINE || (dOn('files') && !dHidden(c)); }), cats = prof.doc_cats || {}, by = {}, order = [];
    files.forEach(function (f) { var c = cats[f.id] || 'Anya documents'; if (!by[c]) { by[c] = []; order.push(c); } by[c].push(f); });
    order.forEach(function (c) {
      h += H(c === MINE ? 'Aapki bheji hui files' : c);
      by[c].forEach(function (f) { h += li(fileIcon(f.name), f.name, f.size ? Math.round(f.size / 1024) + ' KB' : 'File', bt('fget', f.id, 'Download') + bt('fsend', f.id, 'Bhejein') + (c === MINE ? bt('udel', f.id, 'Hatayein', 'r') : '')); });
    });
    if (!files.length && dOn('files')) h += '<p class="sph-note">Blueprint, plant ki photo, certificate jaisi files team upload karte hi yahan dikhengi.</p>';
    if ((p.warranty || []).length && dOn('warranty')) h += H('Warranty') + warrantyList(p.warranty);
    if (dOn('upload')) {
      h += H('Apni file Sunpowers ko bhejein') + '<p class="sph-note" style="margin:0 0 6px">ID, bijli bill, chhat ki photo jaisi files yahin se bhejein — seedhe team tak pahunchengi. Photo (JPG / PNG) ya PDF, 3 MB tak.</p>' +
        '<div class="sph-f"><label for="sphUc">Kya bhej rahe hain?</label><select id="sphUc" data-f="ucat">' + UCATS.map(function (x) { return '<option' + ((F.ucat || UCATS[0]) === x ? ' selected' : '') + '>' + x + '</option>'; }).join('') + '</select></div>' +
        '<div style="margin-top:8px"><button type="button" class="sph-b" data-act="upl"' + (busy ? ' disabled' : '') + '>' + (busy ? 'Bhej rahe hain…' : '📤 File chunein aur bhejein') + '</button></div>';
    }
    return h;
  }
  function pBills() {
    var a = (prof.bills || []).slice().sort(function (x, y) { return ({ pending: 0, paid: 1, cancelled: 2 }[x.state] - { pending: 0, paid: 1, cancelled: 2 }[y.state]) || (y.id - x.id); });
    if (!a.length) return empty('docs', 'Abhi koi bill nahi', 'Quotation confirm ya order hone ke baad bill yahan dikhega.');
    return a.map(function (x) {
      var tag = x.state === 'pending' ? '<span class="sph-tag o">Baaki ' + rs(x.balance) + '</span>' : x.state === 'paid' ? '<span class="sph-tag g">✓ Poora bhugtan</span>' : '<span class="sph-tag r">Cancelled</span>';
      return li('docs', x.title || x.ref, 'Bill ' + esc(x.ref || '') + (x.date ? ' · ' + fd(x.date) : '') + ' · Kul ' + rs(x.amount) + ' · Mila ' + rs(x.paid) + (x.state === 'pending' && x.due_date ? ' · due ' + fd(x.due_date) : '') + (x.nonrefundable ? '<br>Non-refundable — jama paisa wapas nahi hota' : ''), tag + bt('bprint', x.id, 'Dekhein') + bt('bsend', x.id, 'Bhejein'));
    }).join('');
  }
  function pSavings(j) {
    var p = j.p, kw = parseFloat(p.kw) || 0, t = Number((prof.cfg || {}).tariff) || 7, g = Number((prof.cfg || {}).gen) || 4;
    if (!kw) return empty('sun', 'Savings abhi nikal nahi sakte', 'Aapke plant ki capacity (kW) judne ke baad yahan lagbhag bachat dikhegi.');
    var mu = kw * g * 30, yu = kw * g * 365, h = '<div class="sph-grid">' +
      '<div class="sph-k g"><h4>Mahine me lagbhag</h4><div class="big">' + rs(mu * t) + '</div><small>≈ ' + Math.round(mu) + ' unit bijli</small></div>' +
      '<div class="sph-k g"><h4>Saal me lagbhag</h4><div class="big">' + rs(yu * t) + '</div><small>≈ ' + Math.round(yu).toLocaleString('en-IN') + ' unit bijli</small></div>' +
      '<div class="sph-k"><h4>Aapka plant</h4><div class="big">' + esc(p.kw) + ' kW</div><small>Maan: ' + g + ' unit/kW/din · ₹' + t + '/unit</small></div></div>';
    var last = (prof.checkups || []).filter(function (c) { return c.quote_id === p.id && c.gen_kwh != null; })[0];
    if (last) h += '<div class="sph-k" style="margin-top:10px"><h4>Aapka khud ka likha (' + ym(last.ym) + ')</h4><div class="big">' + esc(last.gen_kwh) + ' kWh</div><small>Checkup me aapne yeh generation likhi thi</small></div>';
    return h + '<p class="sph-note"><b>Dhyan dein:</b> yeh sirf <b>anumaan (estimate)</b> hai — dhoop, mausam aur bijli tariff par nirbhar. Isme koi asli data nahi hai. <b>Asli generation ke liye apne inverter ki screen par dekhein.</b> Is jagah par kuch badla nahi ja sakta.</p>';
  }
  function pAmc(j) {
    var p = j.p, m = p.maintenance || {}, v = m.visits || [], done = v.filter(function (x) { return x.done; }).length;
    var h = '<div class="sph-grid"><div class="sph-k ' + (m.next_due ? 'w' : '') + '"><h4>Agli visit</h4><div class="big">' + (m.next_due ? fd(m.next_due) : '—') + '</div><small>' + (m.next_due ? 'Technician is date tak aayega' : 'Abhi koi visit tay nahi') + '</small></div>' +
      '<div class="sph-k"><h4>Pichli visit</h4><div class="big">' + (m.last_done ? fd(m.last_done) : '—') + '</div><small>Service ka record</small></div>' +
      '<div class="sph-k g"><h4>Visits poori</h4><div class="big">' + done + ' / ' + v.length + '</div><small>AMC plan ke hisaab se</small></div></div>';
    if (v.length) h += '<div style="margin-top:8px">' + v.map(function (x) { return li('cal', 'Visit ' + (x.visit || ''), esc(x.plan || 'AMC') + ' · due ' + fd(x.due), x.done ? '<span class="sph-tag g">✓ ' + fd(x.done_on) + '</span>' : '<span class="sph-tag o">Baaki</span>'); }).join('') + '</div>';
    else h += empty('cal', 'Abhi AMC plan active nahi', 'AMC me saal bhar ki regular safai aur jaanch hoti hai — plant ki performance achhi rehti hai aur kharabi pehle hi pakad me aati hai.', '<button type="button" class="sph-b" data-act="req" data-v="amc"' + (busy ? ' disabled' : '') + '>AMC plan maangein</button><button type="button" class="sph-b g" data-act="req" data-v="callback">Call back chahiye</button>');
    return h;
  }
  function pSupport(j) {
    var pid = j && j.p && j.p.id, all = prof.complaints || [], list = j && (j.k === 'proj' || j.k === 'serv') ? all.filter(function (c) { return c.quote_id === pid; }) : all;
    var h = '<div class="sph-cta" style="justify-content:flex-start;margin:0 0 4px">' + contactBtns() + '</div>';
    h += '<h4 style="margin:12px 0 2px;font-size:13px;color:#8a6a3a;text-transform:uppercase;letter-spacing:.05em">Nayi complaint</h4>' +
      '<div class="sph-f"><label for="sphIss">Kya dikkat hai?</label><textarea id="sphIss" data-f="complaint" placeholder="Jaise: inverter par error aa raha hai, generation kam hai…">' + esc(F.complaint) + '</textarea></div>' +
      '<div class="sph-f"><label for="sphPr">Kitna zaroori hai?</label><select id="sphPr" data-f="priority"><option' + (F.priority === 'Normal' ? ' selected' : '') + '>Normal</option><option' + (F.priority === 'Urgent' ? ' selected' : '') + '>Urgent</option></select></div>' +
      '<div style="margin-top:12px"><button type="button" class="sph-b" data-act="cmp"' + (busy ? ' disabled' : '') + '>' + (busy ? 'Bhej rahe hain…' : 'Complaint darj karein') + '</button></div>';
    h += '<h4 style="margin:16px 0 2px;font-size:13px;color:#8a6a3a;text-transform:uppercase;letter-spacing:.05em">Aapki complaints</h4>';
    h += list.length ? list.map(function (c) { var done = c.status === 'Resolved'; return li('head', (c.no || 'Complaint') + ' — ' + (c.issue || ''), (c.date ? fd(c.date) : '') + (c.resolution ? ' · ' + esc(c.resolution) : ''), '<span class="sph-tag ' + (done ? 'g' : 'o') + '">' + esc(c.status || 'Khuli') + '</span>'); }).join('') : '<p class="sph-note">Abhi koi complaint nahi hai. Koi bhi dikkat ho to upar likhkar bhejein — hum jaldi sampark karenge.</p>';
    return h;
  }
  function pCheckup(j) {
    var p = j.p, keys = prof.checkup_keys || {}, cur = nowYm(), mine = (prof.checkups || []).filter(function (c) { return c.quote_id === p.id; }), now = mine.filter(function (c) { return c.ym === cur; })[0];
    if (!p.installed) return empty('cal', 'Checkup install ke baad shuru hoga', 'Plant lagne ke baad har mahine aap yahan 1 minute me apne plant ki jaanch bhar sakte hain.');
    if (!F.chkInit) { F.chk = now ? JSON.parse(JSON.stringify(now.items || {})) : {}; F.gen = now && now.gen_kwh != null ? String(now.gen_kwh) : ''; F.cnote = now ? now.note || '' : ''; F.chkInit = true; }
    var h = now ? '<div class="sph-msg">✓ ' + ym(cur) + ' ka checkup ho chuka hai — chahein to badal kar dobara save kar sakte hain.</div>' : '<p class="sph-note" style="margin:0 0 6px">Apne plant ko dekhkar har sawal ka jawab chunein. Save karte hi yeh aapke <b>Documents</b> me aa jayega. Kuch kharab ho to complaint apne aap darj ho jati hai.</p>';
    Object.keys(keys).forEach(function (k) {
      var v = F.chk[k];
      h += '<div class="sph-chk"><div class="q">' + esc(keys[k]) + '</div><div class="sph-seg"><button type="button" class="ok' + (v === 'ok' ? ' on' : '') + '" data-act="chk" data-k="' + k + '" data-v="ok">✓ Theek</button><button type="button" class="bad' + (v === 'bad' ? ' on' : '') + '" data-act="chk" data-k="' + k + '" data-v="bad">✕ Dikkat</button><button type="button" class="na' + (v === 'na' ? ' on' : '') + '" data-act="chk" data-k="' + k + '" data-v="na">Lagu nahi</button></div></div>';
    });
    h += '<div class="sph-f"><label for="sphGen">Is mahine ki generation (kWh, optional)</label><input id="sphGen" data-f="gen" inputmode="decimal" value="' + esc(F.gen) + '" placeholder="Inverter ki screen se dekhkar likhein"></div>' +
      '<div class="sph-f"><label for="sphCn">Koi baat likhni ho (optional)</label><textarea id="sphCn" data-f="cnote" maxlength="300">' + esc(F.cnote) + '</textarea></div>' +
      '<div style="margin-top:12px"><button type="button" class="sph-b" data-act="chksave"' + (busy ? ' disabled' : '') + '>' + (busy ? 'Save ho raha hai…' : ic('check', 16) + ' Checkup publish karein') + '</button></div>';
    if (mine.length) h += '<h4 style="margin:16px 0 2px;font-size:13px;color:#8a6a3a;text-transform:uppercase;letter-spacing:.05em">Pichle checkups</h4>' + mine.map(function (c) {
      var bad = Object.keys(c.items || {}).filter(function (k) { return c.items[k] === 'bad'; }).length;
      return li('cal', ym(c.ym), bad ? bad + ' jagah dikkat' + (c.ticket ? ' · complaint ' + esc(c.ticket) : '') : 'Sab theek', bt('cprint', c.ym, 'Dekhein / Download'));
    }).join('');
    return h;
  }
  function pOrders() {
    var a = prof.orders || [];
    if (!a.length) return empty('box', 'Abhi koi online order nahi', 'Shop se order karte hi uska poora status, dispatch aur tracking yahan dikhega.');
    return a.map(function (o) {
      var cls = o.status === 'delivered' ? 'g' : o.status === 'cancelled' ? 'r' : o.status === 'shipped' ? 'b' : 'o';
      return li('box', o.order_no || ('Order #' + o.id), fd(o.created_at) + ' · ' + (o.first ? esc(o.first) + (o.n > 1 ? ' +' + (o.n - 1) + ' aur' : '') : o.n + ' item') + ' · ' + money(o.total), '<span class="sph-tag ' + cls + '">' + esc(STL[o.status] || o.status) + '</span>' + bt('ord', o.id, 'Order dekhein', 'sm'));
    }).join('');
  }
  function pOrder() {
    var o = ord; if (!o) return '<div class="sph-sk"></div>';
    var st = o.status, idx = { new: 0, confirmed: 1, paid: 2, shipped: 3, delivered: 4 }[st], dsp = o.dispatch || {}, paidOk = o.payment_status === 'paid' || st === 'paid' || st === 'delivered';
    var stp = [['Order place hua', fd(o.created_at), true], ['Confirm hua', '', idx >= 1], ['Payment', paidOk ? 'Mil gaya' : (Number(o.due) > 0 ? 'Baaki ' + money(o.due) : ''), !!paidOk], [o.pickup ? 'Pickup ke liye taiyar' : 'Dispatch', dsp.disp_date ? fd(dsp.disp_date) : '', idx >= 3], [o.pickup ? 'Pickup ho gaya' : 'Delivered', dsp.deliv_date ? fd(dsp.deliv_date) : (dsp.eta_date && idx < 4 ? 'Anumaan ' + fd(dsp.eta_date) : ''), idx >= 4]];
    var cur = -1; stp.forEach(function (s, i) { if (cur < 0 && !s[2]) cur = i; });
    var h = '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:8px"><b style="font-size:17px">' + esc(o.order_no || '') + '</b><span class="sph-tag ' + (st === 'delivered' ? 'g' : st === 'cancelled' ? 'r' : 'o') + '">' + esc(STL[st] || st) + '</span>' + (o.invoice_no ? '<span class="sph-tag">Bill ' + esc(o.invoice_no) + '</span>' : '') + '</div>';
    if (st === 'cancelled') h += '<div class="sph-msg bad">Yeh order cancel ho chuka hai.</div>';
    else h += '<div class="sph-tl">' + stp.map(function (s, i) { return '<div class="s ' + (s[2] ? 'd' : i === cur ? 'now' : '') + '"><b>' + esc(s[0]) + '</b>' + (s[1] ? '<span>' + esc(s[1]) + '</span>' : '') + '</div>'; }).join('') + '</div>';
    if (dsp.courier || dsp.tracking) h += '<div class="sph-k w" style="margin:6px 0 10px"><h4>Courier / Tracking</h4><div style="font-weight:800">' + esc(dsp.courier || '') + (dsp.tracking ? ' · ' + esc(dsp.tracking) : '') + '</div>' + (dsp.track_url ? '<div style="margin-top:6px"><a class="sph-b sm" href="' + esc(dsp.track_url) + '" target="_blank" rel="noopener">' + ic('truck', 16) + ' Track karein</a></div>' : '') + (dsp.note ? '<small>' + esc(dsp.note) + '</small>' : '') + '</div>';
    h += '<h4 style="margin:10px 0 2px;font-size:13px;color:#8a6a3a;text-transform:uppercase;letter-spacing:.05em">Saman</h4>' + (o.items || []).map(function (i) { return li('box', i.title, 'Qty ' + esc(i.qty) + ' × ' + money(i.price), '<b>' + money(i.amount) + '</b>'); }).join('');
    (o.install || []).forEach(function (n) { h += li('wrench', 'Installation add-on', esc(typeof n === 'string' ? n : (n.title || n.name || '')), '<span class="sph-tag b">Add-on</span>'); });
    h += '<div class="sph-grid" style="margin-top:10px"><div class="sph-k"><h4>Delivery pata</h4><small style="color:#1c2a22;font-size:14px">' + (o.pickup ? 'Dukaan se pickup' : esc([o.name, o.address, o.city, o.pincode].filter(Boolean).join(', '))) + '</small><small>' + esc(o.phone || '') + '</small></div>' +
      '<div class="sph-k"><h4>Bhugtan</h4><small style="color:#1c2a22;font-size:14px">Saman ' + money(o.subtotal) + '</small><small>Shipping ' + (Number(o.shipping) ? money(o.shipping) : 'Free') + '</small><div class="big" style="font-size:20px;margin-top:4px">Kul ' + money(o.total) + '</div>' + (Number(o.due) > 0 ? '<small>Baaki ' + money(o.due) + '</small>' : '') + '</div></div>';
    if (o.subsidy && Number(o.subsidy.total) > 0) {
      var sb = o.subsidy, sn = Math.max(0, Number(o.total) - Number(sb.total));
      h += '<div class="sph-k w" style="margin-top:10px"><h4>Sarkari subsidy (sirf jankari)</h4><small style="color:#1c2a22;font-size:14px">Central ' + money(sb.central) + (Number(sb.state_amt) > 0 ? ' + Rajya' + (sb.state ? ' (' + esc(sb.state) + ')' : '') + ' ' + money(sb.state_amt) : '') + '</small><div class="big" style="font-size:18px;margin-top:4px">Kul anumanit ' + money(sb.total) + '</div><small>Subsidy ke baad anumanit asli kharch: ' + money(sn) + '</small><small>Ye rakam order ke total me se kam nahi hui. Sarkar shartein poori hone par seedha aapke bank khate me deti hai; Sunpowers koi subsidy nahi deta.</small></div>';
    }
    return h;
  }
  function pInq() {
    var a = prof.inquiries || []; if (!a.length) return empty('list', 'Koi pending quotation nahi', 'Quotation banne par yahan dikhegi.');
    return a.map(function (x) { return li('list', x.title || x.ref, esc(x.ref || ''), '<span class="sph-tag o">' + esc(x.status) + '</span>'); }).join('');
  }
  function pRefer() {
    return '<p class="sph-note" style="margin:0 0 4px">Kisi dost ya parivaar ko solar chahiye? Unka naam aur mobile likhein — hamari team unse sampark karegi.</p>' +
      '<div class="sph-f"><label for="sphRn">Dost ka naam</label><input id="sphRn" data-f="rname" value="' + esc(F.rname) + '" maxlength="80"></div>' +
      '<div class="sph-f"><label for="sphRm">Dost ka mobile (10 ank)</label><input id="sphRm" data-f="rmob" inputmode="numeric" maxlength="10" value="' + esc(F.rmob) + '"></div>' +
      '<div class="sph-f"><label for="sphRt">Koi baat (optional)</label><input id="sphRt" data-f="rnote" value="' + esc(F.rnote) + '" maxlength="150"></div>' +
      '<div style="margin-top:12px"><button type="button" class="sph-b" data-act="refer"' + (busy ? ' disabled' : '') + '>' + ic('gift', 16) + ' Refer karein</button></div>';
  }
  function pLink() {
    return '<p class="sph-note" style="margin:0 0 4px">Plant ID aapki confirmed quotation ka number hai (jaise QT/26-27/0001). Sirf aapke mobile number se juda Plant ID hi judta hai.</p>' +
      '<div class="sph-f"><label for="sphPid">Plant ID</label><input id="sphPid" data-f="pid" value="' + esc(F.pid || '') + '" autocomplete="off" style="text-transform:uppercase" placeholder="QT/26-27/0001"></div>' +
      '<div style="margin-top:12px"><button type="button" class="sph-b" data-act="link"' + (busy ? ' disabled' : '') + '>' + (busy ? 'Jaanch rahe hain…' : 'Jodein') + '</button></div>';
  }
  var PT = { docs: ['docs', 'Documents'], bills: ['docs', 'Bills'], savings: ['sun', 'Bachat ka anumaan'], amc: ['cal', 'AMC Plan'], support: ['head', 'Support'], checkup: ['cal', 'Routine Checkup'], orders: ['box', 'Mere Orders'], order: ['truck', 'Order ki jaankari'], warranty: ['shield', 'Warranty'], inq: ['list', 'Quotations'], refer: ['gift', 'Dost ko refer karein'], link: ['plus', 'Plant ID jodein'], 'switch': ['swap', 'Plant / Project badlein ya jodein'] };
  function panelHtml(j) {
    if (!panel || !PT[panel]) return '';
    var b = '';
    try {
      if (panel === 'docs') b = j && j.p ? pDocs(j) : pBills();
      else if (panel === 'bills') b = pBills();
      else if (panel === 'savings') b = j && j.k === 'proj' ? pSavings(j) : '';
      else if (panel === 'amc') b = j && j.p ? pAmc(j) : '';
      else if (panel === 'support') b = pSupport(j);
      else if (panel === 'checkup') b = j && j.k === 'proj' ? pCheckup(j) : '';
      else if (panel === 'orders') b = pOrders();
      else if (panel === 'order') b = pOrder();
      else if (panel === 'warranty') b = warrantyList(prof.products ? prof.products.filter(function (x) { return x.warranty; }).map(function (x) { return { name: x.name, brand: x.brand, warranty: x.warranty }; }) : []);
      else if (panel === 'inq') b = pInq();
      else if (panel === 'refer') b = pRefer();
      else if (panel === 'link') b = pLink();
      else if (panel === 'switch') b = switcher();
    } catch (e) { b = '<div class="sph-msg bad">Yeh hissa abhi khul nahi paya — dobara koshish karein.</div>'; }
    return '<div class="sph-sheet" role="dialog" aria-modal="true" aria-label="' + esc(PT[panel][1]) + '"><div class="sph-sov" data-act="close"></div><div class="sph-sp"><div class="sph-sh"><button type="button" class="sph-back" data-act="back" aria-label="Wapas">' + ic('back', 18) + '</button><h3>' + PT[panel][1] + '</h3><button type="button" class="sph-x" data-act="close" aria-label="Band karein">×</button></div><div class="sph-sb" id="sphPn">' + (flash ? '<div class="sph-msg' + (flashBad ? ' bad' : '') + '" role="status">' + esc(flash) + '</div>' : '') + b + '</div></div></div>';
  }
  var ord = null;

  function onboard() { return '<div class="sph-pn">' + empty('sun', 'Aapka Sunpowers account taiyar hai', 'Jaise hi aap koi solar project, service ya product lenge — uska status, documents, AMC plan aur support yahin dikhega. Pehle se koi kaam hai to Plant ID jodein.', '') + '</div>'; }
  /* ---------- render ---------- */
  function render() {
    var h = ensureHost(); if (!h) return;
    var hd = h.closest ? h.closest('header') : null;
    if (!tok()) { h.innerHTML = ''; h.style.display = 'none'; lock(false); shown = ''; if (hd) hd.removeAttribute('data-sph'); return; }
    h.style.display = ''; if (hd) hd.setAttribute('data-sph', '1');
    if (!loaded) { h.innerHTML = '<div class="sph-sk" aria-busy="true"></div>'; return; }
    if (failed || !prof) { lock(false); h.innerHTML = '<div class="sph-wrap"><div class="sph-card"><div class="sph-hello"><h2 style="white-space:normal">Profile abhi khul nahi payi</h2><div class="sph-live o"><i></i><span>Internet ya server ki dikkat ho sakti hai</span></div></div><div class="sph-cta" style="justify-content:flex-start"><button type="button" class="sph-b g" data-act="retry">Dobara koshish karein</button></div></div></div>'; wire(h); return; }
    var j = curJob(), qa = '';
    if (j && j.k === 'proj') qa += '<button type="button" class="sph-q' + (panel === 'checkup' ? ' on' : '') + '" data-act="tile" data-v="checkup"><span>' + ic('cal', 26) + '</span>Checkups</button>';
    qa += '<button type="button" class="sph-q' + (panel === 'refer' ? ' on' : '') + '" data-act="tile" data-v="refer"><span>' + ic('gift', 26) + '</span>Refer</button>';
    qa += '<button type="button" class="sph-q' + (panel === 'switch' ? ' on' : '') + '" data-act="sw" aria-expanded="' + (panel === 'switch' ? 'true' : 'false') + '"><span>' + ic('swap', 26) + '</span>Switch</button>';
    var sub = j && (j.k === 'proj' || j.k === 'serv') ? esc(j.p.title || '') + ' · Plant ID ' + esc(j.p.plant_id || '') : 'Customer ID ' + esc(prof.cust_id || '—');
    var sbOld = h.querySelector('.sph-sb'), stTop = sbOld ? sbOld.scrollTop : 0, same = !!sbOld && shown === panel;
    var bn = bannerBills();
    h.innerHTML = '<div class="sph-wrap' + (bn ? ' hasbn' : '') + '"><div class="sph-card"><div class="sph-top"><div class="sph-hello"><h2>Hello, ' + esc(firstName()) + ' 👋</h2>' + liveChip(j) + '<div class="sph-sub">' + sub + '</div></div><div class="sph-qa">' + qa + '</div></div>' +
      tiles(j) + steps(j) + '</div>' + bn + '</div>' + panelHtml(j) + (!j && !panel ? onboard() : '');
    shown = panel; lock(!!panel);
    var sbNew = h.querySelector('.sph-sb'); if (sbNew && same) sbNew.scrollTop = stTop;
    wire(h);
  }
  function wire(h) {
    h.onclick = function (e) {
      var t = e.target.closest ? e.target.closest('[data-act]') : null; if (!t || !h.contains(t) || t.disabled) return;
      act(t.getAttribute('data-act'), t.getAttribute('data-v'), t.getAttribute('data-k'));
    };
    h.oninput = h.onchange = function (e) { var f = e.target.getAttribute && e.target.getAttribute('data-f'); if (f) F[f] = e.target.value; };
  }
  function lock(on) { if (on === locked) return; locked = on; try { document.documentElement.style.overflow = on ? 'hidden' : ''; } catch (e) {} }
  function scrollPn() { setTimeout(function () { var b = host && host.querySelector('.sph-sh .sph-back'); if (b && b.focus) try { b.focus({ preventScroll: true }); } catch (e) {} }, 40); }
  function fail(e) { say((e && e.message) || 'Dobara koshish karein', true); }
  function res(r, okMsg, then) { if (r && r.error) return say(r.error, true); busy = false; if (then) then(r); else say(okMsg); }
  function act(a, v, k) {
    var j = curJob(), p = j && j.p;
    if (a === 'sw') { panel = panel === 'switch' ? '' : 'switch'; showSw = panel === 'switch'; flash = ''; render(); if (panel) scrollPn(); return; }
    if (a === 'close') { panel = ''; showSw = false; flash = ''; return render(); }
    if (a === 'pick') { sel = v; panel = ''; flash = ''; showSw = false; ord = null; F.chkInit = false; return render(); }
    if (a === 'tile') { panel = (panel === v && v !== 'link') ? '' : v; flash = ''; if (v === 'checkup') F.chkInit = false; showSw = false; render(); if (panel) scrollPn(); return; }
    if (a === 'back') { panel = panel === 'order' ? 'orders' : ''; showSw = false; flash = ''; return render(); }
    if (a === 'retry') { loaded = false; return load(); }
    if (a === 'dprint') return printDoc(v);
    if (a === 'dsend') return sendDoc(v);
    if (a === 'bprint') return printDoc('bill', v);
    if (a === 'bsend') return sendDoc('bill', v);
    if (a === 'rprint') return printReceipt(v);
    if (a === 'upl') return uploadFile();
    if (a === 'udel') { if (busy) return; busy = true; return call('crm_consumer_doc_delete', { id: +v }).then(function (r) { if (r && r.error) return say(r.error, true); busy = false; load().then(function () { say('File hata di gayi.'); }); }, fail); }
    if (a === 'fget') return getFile(v);
    if (a === 'fsend') return sendFile(v);
    if (a === 'cprint') return printCheckup(v);
    if (a === 'chk') { F.chk[k] = v; return render(); }
    if (busy) return;
    if (a === 'ord') { ord = null; panel = 'order'; flash = ''; render(); scrollPn(); return call('crm_consumer_order', { id: +v }).then(function (r) { if (r && r.error) return say(r.error, true); ord = r; render(); }, fail); }
    if (a === 'req') { busy = true; flash = ''; render(); return call('crm_consumer_request', { kind: v }).then(function (r) { res(r, v === 'amc' ? 'AMC ki maang mil gayi — hamari team jaldi sampark karegi.' : 'Theek hai — hum aapko jaldi call karenge.'); }, fail); }
    if (a === 'cmp') {
      if (String(F.complaint).trim().length < 5) return say('Samasya thodi detail me likhein (kam se kam 5 akshar)', true);
      busy = true; flash = ''; render();
      return call('crm_consumer_complaint_new', { issue: F.complaint, priority: F.priority, quote_id: p && p.id ? p.id : null }).then(function (r) {
        if (r && r.error) return say(r.error, true);
        F.complaint = ''; F.priority = 'Normal'; busy = false; var m = 'Complaint darj ho gayi — number ' + (r && r.ticket || '') + '. Hum jaldi sampark karenge.'; load().then(function () { say(m); });
      }, fail);
    }
    if (a === 'chksave') {
      var keys = Object.keys(prof.checkup_keys || {}), miss = keys.filter(function (x) { return !F.chk[x]; });
      if (miss.length) return say('Har sawal ka jawab chunein (' + miss.length + ' baaki)', true);
      busy = true; flash = ''; render();
      return call('crm_checkup_save', { quote_id: p.id, items: F.chk, gen_kwh: F.gen, note: F.cnote }).then(function (r) {
        if (r && r.error) return say(r.error, true);
        busy = false; var m = '✓ Checkup save ho gaya aur Documents me jud gaya.' + (r && r.bad ? ' ' + r.bad + ' jagah dikkat thi — complaint ' + (r.ticket || '') + ' darj ho gayi.' : ''); F.chkInit = false; load().then(function () { say(m); });
      }, fail);
    }
    if (a === 'refer') {
      busy = true; flash = ''; render();
      return call('crm_consumer_refer', { name: F.rname, mobile: F.rmob, note: F.rnote }).then(function (r) { res(r, 'Shukriya! Hum aapke dost se sampark karenge.', function () { F.rname = F.rmob = F.rnote = ''; say('Shukriya! Hum aapke dost se sampark karenge.'); }); }, fail);
    }
    if (a === 'link') {
      var pid = String(F.pid || '').trim(); if (!pid) return say('Plant ID likhein', true);
      busy = true; flash = ''; render();
      return call('crm_consumer_link_plant', { plant_id: pid }).then(function (r) {
        if (r && r.error) return say(r.error, true);
        busy = false; F.pid = ''; load().then(function () { var f = jobs.filter(function (x) { return x.p && x.p.id === (r && r.id); })[0]; if (f) sel = f.key; panel = ''; flash = ''; render(); });
      }, fail);
    }
  }

  /* ---------- documents / files ---------- */
  function save(blob, name) {
    var u = URL.createObjectURL(blob), a = document.createElement('a'); a.href = u; a.download = name; document.body.appendChild(a); a.click(); setTimeout(function () { a.remove(); URL.revokeObjectURL(u); }, 3000);
  }
  function b2blob(r) { var bin = atob(r.b64), arr = new Uint8Array(bin.length); for (var i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i); return new Blob([arr], { type: r.mime || 'application/octet-stream' }); }
  function getFile(id) { call('crm_consumer_file', { id: id }).then(function (r) { if (r && r.error) return say(r.error, true); save(b2blob(r), r.name || 'file'); }, fail); }
  function sendFile(id) {
    call('crm_consumer_file', { id: id }).then(function (r) {
      if (r && r.error) return say(r.error, true);
      var blob = b2blob(r); withShare(function () { SPSHARE.open({ kind: 'doc', title: r.name || 'Document', name: r.name || 'file', blob: blob, details: [['File', r.name || 'file']], phone: '' }); }, function () { save(blob, r.name || 'file'); });
    }, fail);
  }
  function docHtml(d) {
    var co = d.company || {}, cu = d.customer || {}, bill = d.kind === 'bill', mt = d.kind === 'maintenance', t = mt ? 'Maintenance Summary' : (bill ? 'Bill / Invoice' : (d.online ? 'Order Bill (Payment pending)' : 'Quotation'));
    var rows = (d.lines || []).map(function (l, i) { var q = Number(l.qty || 0), pr = Number(l.price || 0); return '<tr><td>' + (i + 1) + '</td><td>' + esc(l.name) + (l.spec ? '<br><small style="color:#555">' + esc(l.spec) + '</small>' : '') + '</td><td style="text-align:right">' + q + '</td><td style="text-align:right">' + money(pr) + '</td><td style="text-align:right">' + (l.gst != null ? esc(l.gst) + '%' : '') + '</td><td style="text-align:right">' + money(q * pr) + '</td></tr>'; }).join('');
    var h = '<!doctype html><meta charset="utf-8"><title>' + esc(t + ' ' + (d.ref || '')) + '</title><style>body{font:14px Arial,sans-serif;color:#111;margin:24px}h1{margin:0;font-size:22px}table{width:100%;border-collapse:collapse;margin-top:12px}td,th{border:1px solid #bbb;padding:6px 8px;text-align:left}th{background:#eef5f0}.r{text-align:right}.b{display:flex;justify-content:space-between;gap:20px}small{color:#555}</style>' +
      '<div class="b"><div><h1>' + esc(co.name || 'Sunpowers') + '</h1><small>' + esc(co.address || '') + '<br>' + (co.gstin ? 'GSTIN: ' + esc(co.gstin) + ' · ' : '') + esc(co.phone || '') + '</small></div><div style="text-align:right"><h1>' + t + '</h1><b>' + esc(d.ref || '') + '</b><br><small>' + fd(d.date) + '</small></div></div>' +
      '<p><b>Customer:</b> ' + esc(cu.name) + '<br><small>' + esc(cu.address || '') + ' ' + esc(cu.city || '') + ' · ' + esc(cu.mobile || '') + '</small></p>';
    if (mt) {
      var v = (d.maintenance && d.maintenance.visits) || [];
      h += '<table><tr><th>Visit</th><th>Plan</th><th>Due</th><th>Status</th></tr>' + (v.length ? v.map(function (x) { return '<tr><td>' + esc(x.visit || '') + '</td><td>' + esc(x.plan || '') + '</td><td>' + fd(x.due) + '</td><td>' + (x.done ? 'Done ' + fd(x.done_on) : 'Baaki') + '</td></tr>'; }).join('') : '<tr><td colspan="4">Abhi koi visit schedule nahi hai</td></tr>') + '</table>';
    } else {
      h += '<table><tr><th>#</th><th>Item</th><th class="r">Qty</th><th class="r">Rate</th><th class="r">GST</th><th class="r">Amount</th></tr>' + rows + '</table>' +
        '<p class="r">' + (d.discount ? 'Discount: ' + money(d.discount) + '<br>' : '') + (d.gst_total != null ? 'GST: ' + money(d.gst_total) + '<br>' : '') + '<b style="font-size:16px">Total: ' + money(d.grand) + '</b>' + (bill ? '<br>Jama: ' + money(d.paid) + ' · Baaki: ' + money(d.balance) : '') + '</p>';
      if (d.ctype === 'Residential' && d.subsidy && Number(d.subsidy.total) > 0 && d.subsidy.sys !== 'off') {
        var sb = d.subsidy, sn = Math.max(0, Number(d.grand) - Number(sb.total));
        h += '<div style="margin:10px 0;padding:8px 10px;border:1px solid #bfe0c7;background:#f2faf4;border-radius:6px;font-size:12px"><b>Sarkari subsidy — sirf jankari</b> <span style="color:#555">(upar ke bill me se kam nahi ki gayi; Sunpowers subsidy nahi deta)</span>' +
          '<table style="margin-top:6px"><tr><td>Central sarkar (PM Surya Ghar)</td><td style="text-align:right">' + money(sb.central) + '</td></tr>' + (Number(sb.state) > 0 ? '<tr><td>Rajya sarkar' + (sb.state_name ? ' (' + esc(sb.state_name) + ')' : '') + '</td><td style="text-align:right">' + money(sb.state) + '</td></tr>' : '') +
          '<tr><td><b>Kul anumanit subsidy</b></td><td style="text-align:right"><b>' + money(sb.total) + '</b></td></tr><tr><td>Subsidy milne ke baad anumanit asli kharch</td><td style="text-align:right">' + money(sn) + '</td></tr></table>' +
          '<div style="margin-top:4px;color:#555;font-size:10.5px">Sharten: ghar (Residential), grid se juda On-Grid / Hybrid plant, DCR modules, DISCOM / sarkari portal ki manzoori. Subsidy sarkar se seedhe milti hai.</div></div>';
      }
      if (!d.no_ben && window.SPBEN) { var hb = d.hub || {}; h += SPBEN.html(d.benefits || SPBEN.build({ lines: d.lines || [], ctype: d.ctype, kw: d.kw, sys: d.sys, tariff: hb.tariff, gen: hb.gen, grand: d.grand, subsidy: (d.subsidy || {}).total, ov: hb.ben })); }
      if (d.notes) h += '<p><small>' + esc(d.notes) + '</small></p>';
    }
    return h + '<p style="margin-top:30px"><small>Computer-generated copy · ' + esc(co.name || 'Sunpowers') + '</small></p>';
  }
  function fetchDoc(kind, id) { var pr = id ? call('crm_consumer_bill_doc', { id: +id }) : call('crm_consumer_plant_doc', { id: (curP() || {}).id, kind: kind }); return pr.then(function (d) { return new Promise(function (ok) { withBen(function () { ok(d); }); }); }); }
  function printReceipt(id) {
    call('crm_consumer_receipt', { id: +id }).then(function (d) {
      if (d && d.error) return say(d.error, true);
      var c = d.company || {}, cu = d.customer || {};
      var html = '<!doctype html><meta charset="utf-8"><title>Rasid ' + esc(d.ref || '') + '</title><style>body{font:14px Arial,sans-serif;color:#111;margin:24px}h1{margin:0;font-size:22px}table{width:100%;border-collapse:collapse;margin-top:12px}td,th{border:1px solid #bbb;padding:6px 8px;text-align:left}th{background:#f3f3f3;width:40%}</style>' +
        '<h1>' + esc(c.name || 'Sunpowers') + '</h1><small>' + esc(c.address || '') + (c.gstin ? '<br>GSTIN: ' + esc(c.gstin) : '') + (c.phone ? ' · ' + esc(c.phone) : '') + '</small><h2 style="margin:16px 0 0">Payment Receipt (Rasid)</h2>' +
        '<table><tr><th>Rasid no</th><td>' + esc(d.ref || '') + '</td></tr><tr><th>Date</th><td>' + fd(d.date) + '</td></tr><tr><th>Customer</th><td>' + esc(cu.name) + ' · ' + esc(cu.mobile || '') + '</td></tr><tr><th>Bill no</th><td>' + esc(d.bill || '') + '</td></tr>' +
        '<tr><th>Payment ka tareeka</th><td>' + esc(d.mode || '—') + '</td></tr><tr><th>Mili rakam</th><td><b style="font-size:16px">' + money(d.amount) + '</b></td></tr><tr><th>Bill ka kul / ab tak mila / baaki</th><td>' + money(d.bill_total) + ' / ' + money(d.bill_paid) + ' / ' + money(d.bill_balance) + '</td></tr></table>' +
        '<p style="margin-top:30px"><small>Computer-generated receipt · ' + esc(c.name || 'Sunpowers') + '</small></p>';
      openHtml(html, 'rasid-' + (d.ref || id));
    }, fail);
  }
  /* customer ki apni file: photo ho to chhoti karke (<=450 KB), PDF seedha (<=3 MB) */
  function compressImg(file, cb) {
    var r = new FileReader(); r.onerror = function () { cb(null); };
    r.onload = function () {
      var im = new Image(); im.onerror = function () { cb(null); };
      im.onload = function () {
        var w = im.width, hh = im.height, m = Math.max(w, hh), sc = m > 1600 ? 1600 / m : 1, cv = document.createElement('canvas'); cv.width = Math.round(w * sc); cv.height = Math.round(hh * sc);
        var g = cv.getContext('2d'); g.fillStyle = '#fff'; g.fillRect(0, 0, cv.width, cv.height); g.drawImage(im, 0, 0, cv.width, cv.height);
        var q = 0.82, out = cv.toDataURL('image/jpeg', q); while (out.length * 0.75 > 450 * 1024 && q > 0.4) { q -= 0.1; out = cv.toDataURL('image/jpeg', q); }
        cb({ b64: out.split(',')[1], mime: 'image/jpeg' });
      };
      im.src = r.result;
    };
    r.readAsDataURL(file);
  }
  function uploadFile() {
    var p = curP(); if (!p || busy) return;
    var i = document.createElement('input'); i.type = 'file'; i.accept = 'image/jpeg,image/png,image/webp,application/pdf';
    i.onchange = function () {
      var f = i.files && i.files[0]; if (!f) return;
      var send = function (o, nm) {
        busy = true; render();
        call('crm_consumer_doc_upload', { quote_id: p.id, name: nm, mime: o.mime, b64: o.b64, ccat: F.ucat || UCATS[0] }).then(function (r) {
          if (r && r.error) return say(r.error, true);
          busy = false; load().then(function () { say('✓ File Sunpowers team ko pahunch gayi.'); });
        }, fail);
      };
      if (/^image\//.test(f.type)) return compressImg(f, function (o) { if (!o) return say('Photo padh nahi paye — dusri file chunein', true); send(o, f.name.replace(/\.[^.]+$/, '') + '.jpg'); });
      if (f.type !== 'application/pdf') return say('Sirf photo (JPG / PNG) ya PDF bhejein', true);
      if (f.size > 3 * 1024 * 1024) return say('PDF 3 MB se badi hai — chhoti karke bhejein', true);
      var r = new FileReader(); r.onload = function () { send({ b64: String(r.result).split(',')[1], mime: 'application/pdf' }, f.name); }; r.onerror = function () { say('File padh nahi paye', true); }; r.readAsDataURL(f);
    };
    i.click();
  }
  function openHtml(html, name) {
    var blob = new Blob([html], { type: 'text/html' }), w = window.open(URL.createObjectURL(blob), '_blank');
    if (!w) save(blob, name + '.html');
  }
  function printDoc(kind, id) {
    fetchDoc(kind, id).then(function (d) { if (d && d.error) return say(d.error, true); openHtml(docHtml(d), (kind + '-' + (d.ref || 'plant')).replace(/[\/\\ ]/g, '-')); }, fail);
  }
  function sendDoc(kind, id) {
    fetchDoc(kind, id).then(function (d) {
      if (d && d.error) return say(d.error, true);
      var c = d.company || {}, cu = d.customer || {}, nm = kind === 'bill' ? 'Bill' : (kind === 'maintenance' ? 'Maintenance summary' : 'Quotation');
      var det = [[nm + ' no', d.ref || ''], ['Customer', cu.name || '']]; if (d.grand != null) det.push(['Total', rs(d.grand)]); if (kind === 'bill' && d.balance != null) det.push(['Baaki', rs(d.balance)]);
      var html = docHtml(d);
      withShare(function () { SPSHARE.open({ kind: kind === 'bill' ? 'bill' : (kind === 'maintenance' ? 'service' : 'quote'), title: nm + ' ' + (d.ref || ''), subtitle: c.name || 'Sunpowers', amount: kind === 'maintenance' ? null : d.grand, name: (nm + '-' + (d.ref || 'plant')).replace(/[^\w-]+/g, '-') + '.pdf', html: html, details: det, brand: c.name, brandPhone: c.phone, print: function () { openHtml(html, 'doc'); }, phone: '' }); }, function () { openHtml(html, 'doc'); });
    }, fail);
  }
  function printCheckup(ymv) {
    var c = ((prof && prof.checkups) || []).filter(function (x) { return x.ym === ymv && (!curP() || x.quote_id === curP().id); })[0]; if (!c) return;
    var keys = prof.checkup_keys || {}, p = curP() || {}, L = { ok: 'Theek', bad: 'Dikkat', na: 'Lagu nahi' };
    var html = '<!doctype html><meta charset="utf-8"><title>Routine Checkup ' + esc(c.ym) + '</title><style>body{font:14px Arial,sans-serif;color:#111;margin:24px}h1{margin:0 0 4px;font-size:22px}table{width:100%;border-collapse:collapse;margin-top:12px}td,th{border:1px solid #bbb;padding:6px 8px;text-align:left}th{background:#fdf2dd}.bad{color:#b3261e;font-weight:700}</style>' +
      '<h1>Routine Checkup — ' + ym(c.ym) + '</h1><div>' + esc(co().name || 'Sunpowers') + ' · ' + esc(prof.name || '') + ' · Plant ' + esc(p.plant_id || '') + '</div><table><tr><th>Jaanch</th><th>Natija</th></tr>' +
      Object.keys(keys).map(function (k) { var v = (c.items || {})[k]; return '<tr><td>' + esc(keys[k]) + '</td><td class="' + (v === 'bad' ? 'bad' : '') + '">' + esc(L[v] || '—') + '</td></tr>'; }).join('') + '</table>' +
      '<p>' + (c.gen_kwh != null ? 'Generation: <b>' + esc(c.gen_kwh) + ' kWh</b><br>' : '') + (c.note ? 'Note: ' + esc(c.note) + '<br>' : '') + (c.ticket ? 'Complaint: ' + esc(c.ticket) : '') + '</p><p><small>Customer ne khud bhara · ' + fd(c.at) + '</small></p>';
    openHtml(html, 'checkup-' + c.ym);
  }

  P.init = function (c) {
    cfg = c; P.refresh();
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && panel) { panel = panel === 'order' ? 'orders' : ''; showSw = false; flash = ''; render(); } });
    document.addEventListener('sp-auth', function () { prof = null; jobs = []; loaded = false; failed = false; sel = ''; panel = ''; flash = ''; showSw = false; ord = null; F.chkInit = false; busy = false; P.refresh(); });
  };
  P.refresh = function () { return load(); };
  /* Round 64: card ab header me chipka nahi rehta — page sirf jahan chahe wahan P.place(slot) se rakhta hai, baaki jagah P.park() se chhupa deta hai */
  P.place = function (el) { if (!cfg) return; var h = ensureHost(); if (!h) return; if (!el) return P.park(); if (h.parentNode !== el) el.insertBefore(h, el.firstChild); };
  P.park = function () { var h = host && document.body.contains(host) ? host : null; if (h && h.parentNode !== parkEl()) parkEl().appendChild(h); };
  P.plants = function () { return (prof && prof.projects) || []; };
})();
