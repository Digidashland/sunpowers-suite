/* Sunpowers app switcher (shared file; same copy in admin, crm, store, website).
   Roles: public (bina login / customer) → Website + Store
          staff roles (manager, staff, dealer, influencer, marketing) → + CRM
          admin → + Admin
   Admin link public ko kabhi nahi dikhta. Ye sirf navigation hai; asli access server par role-check se hota hai. */
(function () {
  var LIVE = { website: 'https://www.sunpowers.in', store: 'https://store.sunpowers.in', admin: 'https://admin.sunpowers.in', crm: 'https://crm.sunpowers.in' };
  var ROLE_APPS = {
    public: ['website', 'store'],
    consumer: ['website', 'store'],
    manager: ['website', 'store', 'crm'],
    staff: ['website', 'store', 'crm'],
    dealer: ['website', 'store', 'crm'],
    influencer: ['website', 'store', 'crm'],
    marketing: ['website', 'store', 'crm'],
    admin: ['website', 'store', 'admin', 'crm']
  };
  var LABEL = { website: '🌐 Website', store: '🛒 Store', admin: '⚙️ Admin', crm: '📊 CRM' };

  function urlFor(app) {
    var h = location.hostname;
    if (/(^|\.)sunpowers\.in$/.test(h)) return LIVE[app];
    /* Preview: sunpowers-suite-<app>-git-<branch>-…vercel.app */
    var m = h.match(/^(.*?)-(website|store|admin|crm)(-git-.*)$/);
    if (m) return location.protocol + '//' + m[1] + '-' + app + m[3];
    return null; /* localhost ya kuch aur: switcher nahi dikhega */
  }

  function allowed(role) { return ROLE_APPS[role] || ROLE_APPS.public; }

  function mount(role, current) {
    unmount();
    if ((role === 'public' || role === 'consumer') && !isStaging()) return;   /* Round 66: customer ko live par ye button nahi dikhta (screen saaf) */
    var apps = allowed(role).filter(function (a) { return urlFor(a); });
    if (apps.length < 2) return;
    var st = document.createElement('style');
    st.id = 'spSwitchCss';
    st.textContent = '#spSw{position:fixed;left:12px;bottom:calc(12px + var(--spsw-b,0px) + env(safe-area-inset-bottom,0px));z-index:99999;font:600 13px system-ui,sans-serif}' +
      '#spSw button{background:#1b7f3b;color:#fff;border:0;border-radius:999px;padding:7px 12px;font-size:12.5px;box-shadow:0 4px 14px rgba(0,0,0,.25);cursor:pointer}' +
      '#spSw .spM{display:none;margin-bottom:8px;background:#fff;color:#1d2a20;border-radius:14px;padding:8px;box-shadow:0 8px 24px rgba(0,0,0,.25);min-width:170px}' +
      '#spSw.open .spM{display:block}' +
      '#spSw .spM a{display:block;padding:10px 12px;border-radius:10px;color:#1d2a20;text-decoration:none}' +
      '#spSw .spM a:hover{background:#eef6ee}' +
      '#spSw .spM a.cur{background:#dcefdc;font-weight:800}';
    document.head.appendChild(st);
    var w = document.createElement('div');
    w.id = 'spSw';
    w.innerHTML = '<div class="spM">' + apps.map(function (a) {
      return '<a href="' + urlFor(a) + '"' + (a === current ? ' class="cur" aria-current="page"' : '') + '>' + LABEL[a] + '</a>';
    }).join('') + '</div><button type="button" aria-expanded="false">☰ Sunpowers</button>';
    document.body.appendChild(w);
    function lift() { var n = document.querySelector('.nav,.sx-nav,nav.mbar'), h = 0; if (n && getComputedStyle(n).position === 'fixed' && getComputedStyle(n).display !== 'none') h = n.getBoundingClientRect().height; document.documentElement.style.setProperty('--spsw-b', h + 'px'); }
    lift(); setTimeout(lift, 800); window.addEventListener('resize', lift);
    var b = w.querySelector('button');
    b.onclick = function () {
      var open = w.classList.toggle('open');
      b.setAttribute('aria-expanded', open ? 'true' : 'false');
    };
  }

  function unmount() {
    var w = document.getElementById('spSw'); if (w) w.remove();
    var s = document.getElementById('spSwitchCss'); if (s) s.remove();
  }

  /* Live hosts (sirf ye 5). Baaki sab staging hai. */
  var LIVE_HOSTS = ['sunpowers.in', 'www.sunpowers.in', 'store.sunpowers.in', 'admin.sunpowers.in', 'crm.sunpowers.in'];
  function isStaging() { return LIVE_HOSTS.indexOf(location.hostname) === -1; }

  /* Staging par saaf banner + search engine se chhupana */
  function stagingBanner() {
    if (!isStaging() || document.getElementById('spStageBar')) return;
    var m = document.createElement('meta'); m.name = 'robots'; m.content = 'noindex,nofollow'; document.head.appendChild(m);
    var b = document.createElement('div');
    b.id = 'spStageBar';
    b.setAttribute('role', 'status');
    b.style.cssText = 'position:fixed;top:0;left:0;right:0;z-index:100000;background:#b45309;color:#fff;font:700 12px system-ui,sans-serif;text-align:center;padding:4px 8px;letter-spacing:.3px;pointer-events:none';
    b.textContent = 'STAGING: yeh test site hai. Live data yahan nahi hai.';
    document.body.appendChild(b);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', stagingBanner); else stagingBanner();

  window.SPSwitch = { mount: mount, unmount: unmount, allowed: allowed, urlFor: urlFor, isStaging: isStaging };
})();
