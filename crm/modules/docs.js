/* Documents — folders (lockable by Admin), upload, open, share, move */
(function () {
  'use strict';
  var C = window.CRM, $ = C.$, $$ = C.$$, esc = C.esc;
  var ROLES = ['manager', 'staff', 'dealer', 'influencer'];

  async function folderForm(rec, parent) {
    rec = rec || { data: { parent_id: parent || '' } }; var d = Object.assign({ roles: [], users: [] }, rec.data || {});
    /* Round 53: "Customer Samples" ke andar ka folder = customer link me dikhne wala topic (kis type ko dikhe + chhota text) */
    var pr0 = null, pidS = d.parent_id || parent || ''; if (pidS) { try { pr0 = await C.get(pidS); } catch (e) { pr0 = null; } }
    var isTopic = !!(pr0 && pr0.data && pr0.data.sample_root), sTypes = Array.isArray(d.types) ? d.types : [];
    var topicHtml = isTopic ? '<div class="sec-t">Customer link me kise dikhe?</div><div class="row wrap">' + [['project', 'Project (solar plant)'], ['product', 'Product'], ['service', 'Service / AMC']].map(function (t) { return '<label class="ck"><input type="checkbox" data-st="' + t[0] + '"' + (!sTypes.length || sTypes.indexOf(t[0]) >= 0 ? ' checked' : '') + '> ' + t[1] + '</label>'; }).join('') + '</div>' + C.f('Customer ko dikhne wala chhota text', '<textarea class="inp" name="snote" rows="2" maxlength="300">' + esc(d.note || '') + '</textarea>', 'full') + '<p class="hint">Is folder ki images / PDF customer ke quotation link ke "Hum kaise kaam karte hain" page par dikhti hain.</p>' : '';
    return new Promise(function (res) {
      var admin = C.isAdmin();
      var body = '<form id="ff" class="stack">' + C.f('Folder ka naam *', C.inp('name', rec.title || d.name || '', 'maxlength="80"')) + topicHtml +
        (admin ? '<label class="ck"><input type="checkbox" name="locked"' + (d.locked ? ' checked' : '') + '> ' + C.ic('lock') + ' <b>Lock karein</b> — sirf neeche chune hue log dekh payenge</label><div id="lk"' + (d.locked ? '' : ' hidden') + ' class="stack"><div class="sec-t">Ye role dekh sakte hain</div><div class="row wrap">' + ROLES.map(function (r) { return '<label class="ck"><input type="checkbox" data-role="' + r + '"' + (d.roles.indexOf(r) >= 0 ? ' checked' : '') + '> ' + C.ROLE[r] + '</label>'; }).join('') + '</div><div class="sec-t">Ya sirf ye users</div><div class="perm-grid" style="max-height:220px;overflow:auto">' + (C.cache.users || []).filter(function (u) { return u.role !== 'consumer' && u.status === 'active'; }).map(function (u) { return '<label class="ck"><input type="checkbox" data-uid="' + u.id + '"' + (d.users.indexOf(u.id) >= 0 ? ' checked' : '') + '> ' + esc(u.name) + ' <span class="xs mute">' + esc(C.ROLE[u.role]) + '</span></label>'; }).join('') + '</div></div>' : '<p class="hint">Folder lock sirf Admin laga sakta hai.</p>') + '</form>';
      var m = C.modal({ title: rec.id ? 'Folder badlein' : 'Naya folder', body: body, foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Save</button>', onClose: function () { res(null); } });
      var lk = $('[name=locked]', m.el); if (lk) lk.onchange = function () { $('#lk', m.el).hidden = !lk.checked; };
      $('[data-ok]', m.el).onclick = async function () {
        var f = $('#ff', m.el), o = C.form(f); if (!C.need(f, ['name'])) return;
        var data = Object.assign({}, rec.data || {}, { name: o.name, parent_id: d.parent_id || '' });
        if (isTopic) { var tsel = $$('[data-st]', m.el).filter(function (x) { return x.checked; }).map(function (x) { return x.getAttribute('data-st'); }); data.types = tsel.length === 3 ? [] : tsel; data.note = o.snote || ''; if (!tsel.length) return C.toast('Kam se kam ek type chunein', true); }
        if (admin) { data.locked = !!o.locked; data.roles = $$('[data-role]', m.el).filter(function (x) { return x.checked; }).map(function (x) { return x.getAttribute('data-role'); }); data.users = $$('[data-uid]', m.el).filter(function (x) { return x.checked; }).map(function (x) { return +x.getAttribute('data-uid'); }); }
        try { var r = await C.save('folder', rec.id, data); m.el.remove(); document.documentElement.style.overflow = ''; res(r); } catch (e) {}
      };
    });
  }

  async function pickFolder(cur) {
    var fs = await C.list('folder', { limit: 2000 }), byP = {};
    fs.forEach(function (f) { var p = f.data.parent_id || ''; (byP[p] = byP[p] || []).push(f); });
    function tree(p, lvl) { return (byP[p] || []).map(function (f) { return '<button type="button" class="li click" style="width:100%;text-align:left;padding-left:' + (14 + lvl * 20) + 'px" data-f="' + f.id + '">' + C.ic('folder') + '<span class="grow">' + esc(f.title) + '</span>' + (f.data.locked ? C.ic('lock') : '') + '</button>' + tree(String(f.id), lvl + 1); }).join(''); }
    return new Promise(function (res) {
      var m = C.modal({ title: 'Kis folder me?', body: '<div class="list"><button type="button" class="li click" style="width:100%;text-align:left" data-f="">' + C.ic('home') + '<span class="grow b">Sabse upar (All Documents)</span></button>' + tree('', 0) + '</div>', foot: false, onClose: function () { res(null); } });
      m.el.addEventListener('click', function (e) { var b = e.target.closest('[data-f]'); if (!b) return; m.el.remove(); document.documentElement.style.overflow = ''; res({ id: b.getAttribute('data-f') }); });
    });
  }

  C.mod('docs', {
    title: 'Documents & Gallery',
    allowed: function () { return C.can('docs.view'); },
    render: async function (el, params, q) {
      var fid = params[0] || '', folder = null, chain = [], pf = q.all ? '' : (q.party || q.cf || ''), pfp = null, pcq = q.cq || '';
      if (pf) { try { pfp = await C.get(pf); } catch (e) { pf = ''; } }
      if (fid) { folder = await C.get(fid); var cur = folder, i = 0; while (cur && i < 10) { chain.unshift(cur); var pid = cur.data.parent_id; cur = pid ? await C.get(pid).catch(function () { return null; }) : null; i++; } }
      var res = await Promise.all([C.list('folder', { folder_id: fid, limit: 1000 }), C.list('doc', { folder_id: fid, limit: 2000 })]), fs = res[0], ds = res[1], mgF = C.can('docs.folders'), up = C.can('docs.upload');
      var h = '<div class="crumb"><a href="#/docs">All Documents</a>' + chain.map(function (c) { return C.ic('right') + '<a href="#/docs/' + c.id + '">' + esc(c.title) + '</a>'; }).join('') + '</div>' +
        '<div class="ph"><div><h1>' + (folder ? esc(folder.title) + (folder.data.locked ? ' ' + C.ic('lock') : '') : 'Documents &amp; Gallery') + '</h1><p>' + (folder && folder.data.locked ? 'Locked folder — sirf chune hue log dekh sakte hain.' : 'Company ke saare documents — folder banayein, upload karein, kisi ko bhi bhejein.') + '</p></div><div class="row">' +
        (folder && mgF ? '<button class="btn btn-o" data-act="fedit" data-id="' + folder.id + '">' + C.ic('settings') + ' Folder</button>' : '') + (mgF ? '<button class="btn btn-o" data-act="fnew">' + C.ic('folder') + ' Naya folder</button>' : '') + (up ? '<button class="btn btn-p" data-act="up">' + C.ic('upload') + ' Upload</button>' : '') + '</div></div>';
      if (chain.length && chain[0].data && chain[0].data.sample_root) h += '<div class="note g" style="margin-bottom:12px">' + C.ic('eye') + ' <b>Customer ko dikhne wali folder.</b> Yahan ki images / PDF customer ke quotation link ke <b>"Hum kaise kaam karte hain"</b> page par dikhti hain' + (chain.length > 1 ? ' (is topic ke naam ke saath)' : '. Har topic ka alag folder hai — folder ke "Folder" button se batayein ki kis type ke customer ko dikhe') + '. File badalne ke liye nayi file upload karein aur purani hata dein. Is folder me customer ke asli document kabhi na rakhein.</div>';
      h += '<div class="bar"><input class="inp" type="search" data-q placeholder="Is folder me khojein (poore CRM me khojne ke liye upar search)"></div>';
      if (fs.length) h += '<div class="folders">' + fs.map(function (f) { return '<a class="folder" href="#/docs/' + f.id + '"><span class="fi">' + C.ic('folder') + '</span><b>' + esc(f.title) + '</b><span class="xs mute">' + esc(f.owner_name || '') + '</span>' + (f.data.locked ? '<span class="lock" title="Locked">' + C.ic('lock') + '</span>' : '') + '</a>'; }).join('') + '</div>';
      h += ds.length ? '<div class="list" id="dl">' + ds.map(function (x) { var mine = x.owner_id === C.me.id; return '<div class="li"><span class="av o">' + C.ic(C.mimeIcon(x.data.mime)) + '</span><span class="grow"><span class="t">' + esc(x.title) + '</span><span class="m"><span>' + C.fsize(x.data.size) + '</span><span>' + esc(C.fd(x.created_at)) + '</span><span>' + C.ic('user') + esc(x.owner_name || '') + '</span>' + (x.data.note ? '<span>' + esc(x.data.note) + '</span>' : '') + '</span></span><span class="acts"><button class="btn btn-o btn-sm" data-act="open" data-id="' + x.id + '" style="display:inline-flex">' + C.ic('eye') + '<span class="desk-only">Kholein</span></button>' + C.dlMenu([['download', 'Download', 'data-act="dl" data-id="' + x.id + '"'], ['share', 'Share (WhatsApp / Link)', 'data-act="share" data-id="' + x.id + '"'], ['users', 'Customer ko bhejein', 'data-act="tocust" data-id="' + x.id + '"']], { sm: true, cls: 'btn-wa' }) + (mine || mgF ? '<button class="btn btn-g btn-icon btn-sm" data-act="edit" data-id="' + x.id + '" aria-label="Badlein">' + C.ic('edit') + '</button>' : '') + (mine || C.can('docs.delete') ? '<button class="btn btn-g btn-icon btn-sm" data-act="del" data-id="' + x.id + '" aria-label="Hatayein">' + C.ic('trash') + '</button>' : '') + '</span></div>'; }).join('') + '</div>' : (fs.length ? '' : '<div class="card">' + C.empty('folder', 'Yahan abhi kuch nahi', up ? 'Upload dabakar PDF, photo, Excel daalein (max 3 MB / file)' : '') + '</div>');
      if (folder && mgF && !fs.length && !ds.length) h += '<div style="margin-top:12px"><button class="btn btn-r btn-sm" data-act="fdel" data-id="' + folder.id + '">' + C.ic('trash') + ' Khaali folder hatayein</button></div>';
      if (pfp) h = h.replace('<div class="bar">', '<div class="note g" style="margin-bottom:10px">' + C.ic('user') + ' <b>' + esc(pfp.title) + '</b> ko file bhejni hai? File ke saamne <b>Customer ko bhejein</b> dabayein — Plant ID aur naam apne aap lagega. <a href="#/docs?all=1">Preset hatayein</a></div><div class="bar">');
      el.innerHTML = h;
      var dl = $('#dl', el), qi = $('[data-q]', el);
      qi.addEventListener('input', function () { var v = qi.value.toLowerCase(); $$('.folder', el).forEach(function (f) { f.hidden = !!v && f.textContent.toLowerCase().indexOf(v) < 0; }); });
      if (dl) C.filterList(qi, dl);
      function doc(id) { return ds.find(function (x) { return String(x.id) === String(id); }); }
      C.bind(el, {
        up: function () { var i = document.createElement('input'); i.type = 'file'; i.multiple = true; i.onchange = async function () { if (await C.uploadFiles(i.files, { folder_id: fid || null })) C.render(); }; i.click(); },
        fnew: function () { folderForm(null, fid).then(function (r) { if (r) C.render(); }); },
        fedit: function () { folderForm(folder).then(function (r) { if (r) C.render(); }); },
        fdel: async function () { if (await C.delWithReason(folder, 'Folder "' + folder.title + '"')) C.go(folder.data.parent_id ? '#/docs/' + folder.data.parent_id : '#/docs'); },
        open: function (id) { C.openFile(id); }, dl: function (id) { C.openFile(id, 'download'); }, share: function (id) { C.openFile(id, 'share'); }, tocust: function (id) { C.shareToCustomer([doc(id)], pfp ? { party: pfp, quote_id: pcq ? +pcq : undefined } : undefined); },
        del: async function (id) { var x = doc(id); if (await C.delWithReason(x, x.title)) C.render(); },
        edit: async function (id) {
          var x = doc(id), m = C.modal({ title: 'Document badlein', body: '<form id="de" class="stack">' + C.f('Naam', C.inp('name', x.title)) + C.f('Note', C.inp('note', x.data.note || '')) + '<button type="button" class="btn btn-o" data-mv>' + C.ic('folder') + ' Doosre folder me bhejein</button></form>', foot: '<button class="btn btn-o" data-close>Cancel</button><button class="btn btn-p" data-ok>Save</button>' }), nf = null;
          $('[data-mv]', m.el).onclick = async function () { var f = await pickFolder(); if (f) { nf = f.id; $('[data-mv]', m.el).innerHTML = C.ic('check') + ' Folder chun liya'; } };
          $('[data-ok]', m.el).onclick = async function () { var o = C.form($('#de', m.el)), data = { title: o.name, note: o.note }; if (nf != null) data.folder_id = nf || null; try { await C.save('doc', x.id, data); m.close(); C.render(); } catch (e) {} };
        }
      });
      if (q.doc) { C.setQuery({ doc: '' }); try { var dx = await C.get(q.doc); C.modal({ title: dx.title, size: 'sm', body: '<p class="mute">' + C.fsize(dx.data.size) + ' · ' + esc(dx.owner_name || '') + ' · ' + esc(C.fd(dx.created_at)) + '</p>', foot: '<button class="btn btn-o" id="dxo">' + C.ic('eye') + ' Kholein</button>' + C.dlMenu([['download', 'Download', 'id="dxd"'], ['share', 'Share (WhatsApp / Link)', 'id="dxs"']], { up: true, cls: 'btn-wa' }) }); $('#dxo').onclick = function () { C.openFile(dx.id); }; $('#dxd').onclick = function () { C.openFile(dx.id, 'download'); }; $('#dxs').onclick = function () { C.openFile(dx.id, 'share'); }; } catch (e) { C.toast(e.message, true); } }
    }
  });
})();
