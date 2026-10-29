/* My profile — details, referral link, password, logout */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, esc = C.esc, money = C.money;
  C.mod('profile', {
    title: 'Meri Profile',
    render: async function (el) {
      var me = C.me, m = me.meta || {}, c = m.commission || {};
      var h = '<div class="ph"><div><h1>Meri Profile</h1><p>' + esc(C.ROLE[me.role] || me.role) + '</p></div><div class="row">' + (window.SPInstall && SPInstall.available() ? '<button class="btn btn-o" data-sp-install>' + C.ic('download') + ' App install karein</button>' : '') + '<button class="btn btn-r" data-act="out">' + C.ic('logout') + ' Logout</button></div></div>';
      h += '<div class="grid g2"><div class="card"><div class="row" style="gap:14px;margin-bottom:14px"><span class="li" style="padding:0;border:0"><span class="av" style="width:56px;height:56px;font-size:20px">' + esc(C.initials(me.name)) + '</span></span><div><h3>' + esc(me.name) + '</h3><p class="mute">@' + esc(me.username) + '</p></div></div><div class="fg">' +
        (me.mobile ? '<div><div class="xs mute">Mobile</div><b>' + esc(me.mobile) + '</b></div>' : '') + (me.email ? '<div><div class="xs mute">Email</div><b>' + esc(me.email) + '</b></div>' : '') + (me.ref_code ? '<div><div class="xs mute">Referral code</div><b>' + esc(me.ref_code) + '</b></div>' : '') +
        (c.mode ? '<div><div class="xs mute">Commission</div><b>' + (c.mode === 'per_kw' ? money(c.value) + ' / kW' : c.mode === 'fixed' ? money(c.value) + ' / plant' : c.value + '% deal value') + '</b></div>' : '') + (m.max_discount_pct ? '<div><div class="xs mute">Discount limit</div><b>' + esc(m.max_discount_pct) + '%</b></div>' : '') + (m.target_monthly ? '<div><div class="xs mute">Mahine ka target</div><b>' + money(m.target_monthly) + '</b></div>' : '') + '</div>' +
        (me.ref_code && C.storeUrl() ? '<div class="sec-t">Mera store link</div><p class="sm mute" style="margin-bottom:8px">Ye link customers ko bhejein — order / enquiry aapke code ke saath aayegi.</p><div class="row"><input class="inp" readonly value="' + esc(C.refLink()) + '"><button class="btn btn-o" data-act="copy">' + C.ic('copy') + '</button><a class="btn btn-wa" target="_blank" rel="noopener" href="' + C.wa('', 'Solar ke liye ' + (C.company().name || '') + ' ka online store dekhein: ' + C.refLink()) + '">' + C.ic('wa') + '</a></div>' : '') +
        '<div class="row wrap" style="margin-top:16px">' + (C.storeUrl() ? '<a class="btn btn-o" target="_blank" rel="noopener" href="' + esc(C.isPartner() ? C.refLink() : C.storeUrl()) + '">' + C.ic('store') + ' Visit Store</a>' : '') + (C.siteUrl() ? '<a class="btn btn-o" target="_blank" rel="noopener" href="' + esc(C.siteUrl()) + '">' + C.ic('globe') + ' Visit Website</a>' : '') + '</div></div>';
      var sec = await C.call('crm_auth_me', {}).catch(function () { return null; });
      h += '<div class="card"><h3 style="margin-bottom:6px">' + C.ic('shield') + ' Login &amp; Suraksha</h3>' + (sec ? '<p class="mute sm" style="margin-bottom:12px">OTP email: <b>' + esc(sec.email || '—') + '</b>' + (sec.email2 ? ' · Backup: <b>' + esc(sec.email2) + '</b>' : '') + '</p>' +
        '<div class="row wrap"><button class="btn btn-o" data-act="pin">' + C.ic('key') + ' PIN badlein</button><button class="btn btn-o" data-act="q">' + C.ic('lock') + ' Security sawal ' + (sec.has_q ? 'badlein' : 'set karein') + '</button></div>' +
        '<div class="sec-t">Mere phone / computer (' + sec.devices.length + ')</div><div class="list">' + sec.devices.map(function (d) { return '<div class="li"><span class="av ' + (d.current ? '' : 'b') + '">' + C.ic(/Android|iPhone/.test(d.name) ? 'phone' : 'grid') + '</span><span class="grow"><span class="t">' + esc(d.name || 'Device') + (d.current ? C.pill('Ye wala') : '') + '</span><span class="m"><span>Pehli baar ' + esc(C.fd(d.created_at)) + '</span><span>Aakhri ' + esc(C.ago(d.last_seen)) + '</span></span></span>' + (d.current ? '' : '<button class="btn btn-g btn-icon btn-sm" data-act="dev" data-id="' + d.id + '" title="Hatayein">' + C.ic('trash') + '</button>') + '</div>'; }).join('') + '</div>' +
        (sec.devices.length > 1 ? '<button class="btn btn-r" style="margin-top:12px" data-act="all">' + C.ic('logout') + ' Baaki sab jagah se logout</button>' : '') : '<p class="mute">Suraksha jaankari load nahi hui.</p>') + '</div></div>';
      if (C.me && C.me.id === 0) {
        var kept = !!C.ls('crm_tok');
        h += '<div class="card" style="margin-top:14px"><h3 style="margin-bottom:6px">' + C.ic('lock') + ' Login yaad rakhein</h3><p class="mute sm" style="margin-bottom:10px">Chalu karne par is phone / computer par CRM kholne par PIN baar-baar nahi maangega — jab tak aap khud <b>Logout</b> na karein. Sirf apne nijee device par chalu karein.</p>' +
          '<div class="row wrap"><span class="pill ' + (kept ? '' : 'g') + '">' + (kept ? 'Chalu hai' : 'Band hai') + '</span><button class="btn btn-o" data-act="keep">' + (kept ? 'Band karein' : 'Is device par yaad rakhein') + '</button></div></div>';
      }
      /* Round 45: staff ko apni salary / payslip yahin dikhti hai */
      var pays = (me.id && ['dealer', 'influencer', 'consumer'].indexOf(me.role) < 0) ? await C.call('crm_my_pay', {}).catch(function () { return []; }) : [];
      if (pays.length) h += '<div class="card" style="margin-top:14px"><h3 style="margin-bottom:6px">' + C.ic('rupee') + ' Meri salary / Payslip</h3><div class="list">' + pays.map(function (p) { return '<div class="li"><span class="grow"><span class="t">' + esc(new Date(+p.month.slice(0, 4), +p.month.slice(5) - 1, 1).toLocaleString('en-IN', { month: 'long', year: 'numeric' })) + '</span><span class="m"><span>' + money(p.net) + '</span><span>' + esc(p.mode) + '</span></span></span><button class="btn btn-o btn-sm" data-act="slip" data-id="' + p.id + '">Payslip</button></div>'; }).join('') + '</div></div>';
      h += '<div id="attbox"></div>';
      el.innerHTML = h;
      if (C.attMe) C.attMe($('#attbox', el));
      C.bind(el, { slip: function (id) { var p = pays.find(function (z) { return String(z.id) === String(id); }); if (p) C.sharePayslip(p, { name: me.name, role: me.role, mobile: me.mobile }); } });
      function pinFields(n) { return '<input class="inp" type="password" inputmode="numeric" maxlength="' + n + '" name="old" placeholder="Purana PIN" style="margin-bottom:8px"><input class="inp" type="password" inputmode="numeric" maxlength="' + n + '" name="new" placeholder="Naya PIN (' + n + ' ank)" style="margin-bottom:8px"><input class="inp" type="password" inputmode="numeric" maxlength="' + n + '" name="new2" placeholder="Naya PIN dobara">'; }
      async function authCall(fn, p, ok) { C.busy(true); try { var r = await C.call(fn, p); if (r && r.error) throw new Error(r.error); if (ok) C.toast(ok); return r; } catch (e) { C.toast(e.message, true); throw e; } finally { C.busy(false); } }
      C.bind(el, {
        pin: function () { var n = sec.pin_len, m = C.modal({ title: 'PIN badlein', size: 'sm', body: '<form id="pf">' + pinFields(n) + '</form>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Badlein</button>' }); $('[data-ok]', m.el).onclick = async function () { var f = $('#pf', m.el); if (f.new.value !== f.new2.value) return C.toast('Dono naye PIN same nahi', true); try { await authCall('crm_auth_change_pin', { old: f.old.value, new: f.new.value }, 'PIN badal gaya ✔'); m.close(); } catch (e) {} }; },
        q: function () { var Q = window.SPAuth.QS.hn, sel = function (n) { return '<select class="inp" name="q' + n + '"><option value="">— sawal ' + n + ' chunein —</option>' + Q.map(function (q) { return '<option>' + esc(q) + '</option>'; }).join('') + '</select>'; };
          var m = C.modal({ title: 'Security sawal', size: 'sm', body: '<form id="qf" class="stack">' + sel(1) + '<input class="inp" name="a1" placeholder="Jawab 1">' + sel(2) + '<input class="inp" name="a2" placeholder="Jawab 2">' + (sec.has_q ? '<input class="inp" type="password" inputmode="numeric" maxlength="' + sec.pin_len + '" name="pin" placeholder="Apna PIN (pakka karne ke liye)">' : '') + '</form>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Save</button>' });
          $('[data-ok]', m.el).onclick = async function () { var o = C.form($('#qf', m.el)); try { await authCall('crm_auth_questions', o, 'Security sawal save ✔'); m.close(); C.render(); } catch (e) {} }; },
        dev: async function (id) { if (!(await C.confirm('Is device ko hatayein? Wahan dobara OTP se login karna padega.', 'Hatao', true))) return; try { await authCall('crm_auth_device_remove', { id: id }, 'Hata diya'); C.render(); } catch (e) {} },
        all: async function () { if (!(await C.confirm('Is phone ko chhod kar baaki sab jagah se logout karein?', 'Haan, logout', true))) return; try { await authCall('crm_auth_logout_all', {}, 'Baaki sab jagah se logout ho gaya ✔'); C.render(); } catch (e) {} }
      });
      C.bind(el, {
        keep: async function () {
          var on = !C.ls('crm_tok'), m = C.modal({ title: on ? 'Login yaad rakhein' : 'Login yaad rakhna band', size: 'sm', body: '<form id="kf"><p class="sm mute" style="margin-bottom:8px">Admin PIN dalein</p><input class="inp" type="password" inputmode="numeric" maxlength="6" name="pin" placeholder="Admin PIN"></form>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Save</button>' });
          $('[data-ok]', m.el).onclick = async function () {
            var o = C.form($('#kf', m.el)); if (!o.pin) return C.toast('PIN likhein', true);
            try { var r = await C.call('crm_admin_keep', { pin: o.pin, on: on }); if (r && r.error) throw new Error(r.error);
              if (on) { C.ls('crm_tok', C.token); C.ss('crm_tok_s', null); } else { C.ss('crm_tok_s', C.token); C.ls('crm_tok', null); }
              m.close(); C.toast(on ? 'Is device par login yaad rakha ✔' : 'Band ho gaya ✔'); C.render();
            } catch (e) { C.toast(e.message, true); }
          };
        },
        out: function () { C.logout(); }, copy: function () { C.copy(C.refLink(), 'Link copy ho gaya ✔'); } });
    }
  });
})();
