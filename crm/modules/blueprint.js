/* Project Blueprint — free site survey + layout + PDF + quotation lead (CRM menu) */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, esc = C.esc;
  try { if (window.SPI18N && SPI18N.add) SPI18N.add([
    ['Project blue print', 'प्रोजेक्ट ब्लूप्रिंट'], ['New blueprint', 'नया ब्लूप्रिंट'], ['Who can see blueprint leads', 'ब्लूप्रिंट लीड कौन देख सकता है'],
    ['Saved blueprints', 'सेव किए ब्लूप्रिंट'], ['No blueprints yet', 'अभी कोई ब्लूप्रिंट नहीं'], ['Make a site survey for a customer — area, panels, structure, PDF and lead.', 'कस्टमर के लिए साइट सर्वे बनाएँ — एरिया, पैनल, स्ट्रक्चर, PDF और लीड।'],
    ['Open', 'खोलें'], ['Delete', 'हटाएँ'], ['Lead', 'लीड'], ['From website', 'वेबसाइट से'], ['From store', 'स्टोर से'], ['From CRM', 'CRM से'],
    ['Admin always sees everything. Choose which other roles can see blueprints and the leads created from them.', 'एडमिन हमेशा सब देखता है। चुनें कि और कौन से रोल ब्लूप्रिंट और उनसे बनी लीड देख सकते हैं।'],
    ['New blueprint leads go to', 'नई ब्लूप्रिंट लीड किसे मिले'], ['Nobody (company lead)', 'कोई नहीं (कंपनी लीड)'], ['Save', 'सेव करें'], ['Cancel', 'रद्द करें'], ['Back to list', 'लिस्ट पर वापस'],
    ['Delete this blueprint?', 'यह ब्लूप्रिंट हटाएँ?'], ['Manager', 'मैनेजर'], ['Staff', 'स्टाफ़'], ['Dealer', 'डीलर'], ['Influencer', 'इन्फ्लुएंसर'], ['Settings saved ✔', 'सेटिंग सेव हो गई ✔']
  ]); } catch (e) {}
  var SRC = { website: 'From website', store: 'From store', crm: 'From CRM' };

  function loadLib() {
    return new Promise(function (res, rej) {
      if (window.SPBlueprint) return res();
      var s = document.createElement('script'); s.src = 'assets/blueprint.js?v=8'; s.onload = function () { res(); }; s.onerror = function () { rej(new Error('Blueprint file load nahi hui')); }; document.head.appendChild(s);
    });
  }

  C.mod('blueprint', {
    title: 'Project blue print',
    allowed: function () { return C.canAny('leads.create', 'leads.view_all'); },
    render: async function (el, params, q) {
      if (q.new || q.open) return editor(el, q);
      var list = [], err = '';
      try { list = await C.call('crm_blueprint_list', {}); } catch (e) { err = e.message; }
      var adm = C.isAdmin();
      var h = '<div class="ph"><div><h1>Project blue print</h1><p>Make a site survey for a customer — area, panels, structure, PDF and lead.</p></div><div class="row">' +
        (adm ? '<button class="btn btn-o" data-act="cfg">' + C.ic('shield') + ' Who can see blueprint leads</button>' : '') +
        '<button class="btn btn-p" data-act="new">' + C.ic('plus') + ' New blueprint</button></div></div>';
      if (err) h += '<div class="note r">' + esc(err) + '</div>';
      h += list.length ? '<div class="list">' + list.map(function (b) {
        var d = b.data || {}, r = d.result || {}, a = d.area || {}, c = d.customer || {};
        return '<div class="li click" data-act="open" data-id="' + b.id + '"><span class="av">' + C.ic('plant') + '</span><span class="grow"><span class="t">' + esc(b.title || 'Blueprint') + (d.lead_id ? ' ' + C.pill('Lead', 'v') : '') + '</span>' +
          '<span class="m"><span>' + esc(r.kw || 0) + ' kW</span><span>' + esc(r.panels || 0) + ' panels</span><span>' + esc(a.sqft || 0) + ' sq ft</span><span>' + esc((d.structure || {}).type || '') + '</span><span>' + esc(b.mobile || c.mobile || '') + '</span><span>' + esc(SRC[d.from] || '') + '</span><span>' + esc(C.fd(b.created_at)) + '</span></span></span>' +
          '<span class="acts"><button class="btn btn-g btn-icon btn-sm" data-act="del" data-id="' + b.id + '" title="Delete">' + C.ic('trash') + '</button></span></div>';
      }).join('') + '</div>' : '<div class="card">' + C.empty('plant', 'No blueprints yet', 'Make a site survey for a customer — area, panels, structure, PDF and lead.') + '</div>';
      el.innerHTML = h;
      C.bind(el, {
        new: function () { C.go('#/blueprint' + C.qs({ new: 1 })); },
        open: function (id) { C.go('#/blueprint' + C.qs({ open: id })); },
        del: async function (id) { if (await C.confirm('Delete this blueprint?', 'Delete', true)) { try { await C.run('crm_blueprint_delete', { id: id }, 'Deleted'); C.render(); } catch (e) {} } },
        cfg: async function () {
          await C.users(); var cfg = await C.call('crm_blueprint_cfg', {}), roles = [['manager', 'Manager'], ['staff', 'Staff'], ['dealer', 'Dealer'], ['influencer', 'Influencer']];
          var m = C.modal({ title: 'Who can see blueprint leads', body: '<p class="mute sm" style="margin-bottom:10px">Admin always sees everything. Choose which other roles can see blueprints and the leads created from them.</p><form id="bpc">' +
            roles.map(function (r) { return '<label class="ck" style="display:block;margin:6px 0"><input type="checkbox" name="r_' + r[0] + '"' + (cfg.visible_roles.indexOf(r[0]) >= 0 ? ' checked' : '') + '> ' + r[1] + '</label>'; }).join('') +
            C.f('New blueprint leads go to', '<select class="inp" name="assign_to">' + C.userOpts(cfg.assign_to || '', 'Nobody (company lead)') + '</select>') + '</form>',
            foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>' + C.ic('check') + ' Save</button>' });
          $('[data-ok]', m.el).onclick = async function () {
            var f = $('#bpc', m.el), vr = ['admin']; roles.forEach(function (r) { if (f.elements['r_' + r[0]].checked) vr.push(r[0]); });
            try { await C.run('crm_blueprint_cfg', { visible_roles: vr, assign_to: f.elements.assign_to.value }, 'Settings saved ✔'); m.el.remove(); document.documentElement.style.overflow = ''; } catch (e) {}
          };
        }
      });
    }
  });

  async function editor(el, q) {
    el.innerHTML = '<div class="loading"><span class="spin"></span></div>';
    var initial = null, id = q.open || null, rec = null, pty = null, pid = q.party || null; /* Round 37: customer ke flow se khulne par wahi customer judta hai */
    if (!id && pid) { try { pty = await C.get(pid); } catch (e) { pid = null; } }
    try { await loadLib(); if (id) { rec = await C.call('crm_blueprint_get', { id: id }); initial = rec.data; initial.customer = Object.assign({ name: rec.title, mobile: rec.mobile }, initial.customer || {}); if (rec.party_id && !pty) { try { pty = await C.get(rec.party_id); pid = pid || rec.party_id; } catch (x) {} } } } catch (e) { el.innerHTML = '<div class="note r">' + esc(e.message) + '</div>'; return; }
    /* Round 38: customer juda ho to designer me uski saari details (Conversation wali) apne aap — naam, mobile, pata, email, prakar, kW. Dobara likhna nahi. */
    var pd = pty ? pty.data || {} : {}, cust = pty ? { name: pty.title, mobile: pty.mobile || '', city: pd.city || '', address: C.addrText(pd) || pd.address || '', email: pd.email || '', type: String(pd.project_type || '').toLowerCase(), locked: true } : null;
    if (cust && initial) cust = Object.assign({}, initial.customer || {}, cust);
    el.innerHTML = '<div class="ph"><div><a class="btn btn-o btn-sm" href="#/blueprint">' + C.ic('left') + ' Back to list</a></div></div><div id="bp-root"></div>';
    SPBlueprint.mount($('#bp-root', el), { mode: 'crm', pdfLibUrl: 'assets/pdf-lib.min.js', initial: initial, noDraft: !!initial, recordId: id, customer: cust || (initial ? initial.customer : undefined), targetKw: !initial && parseFloat(pd.kw) > 0 ? pd.kw : '',
      onSave: function (p) { return C.run('crm_blueprint_save', { id: p.id || id, name: p.name, mobile: p.mobile, city: p.city, make_lead: p.make_lead, blueprint: p.blueprint, party_id: pid || (rec && rec.party_id) || null }, p.make_lead ? 'Blueprint saved + lead created ✔' : 'Blueprint saved ✔'); } });
  }
})();
