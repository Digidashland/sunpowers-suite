/* =====================================================================
   sp-voice.js — 🎤 voice search on EVERY search box (website · store · CRM · admin)
   - Automatic: any <input type="search">, and any text input whose id / name / placeholder / aria-label says search / khoj / खोज / find / filter,
     gets a mic button — also boxes that are created later (lists re-drawn, pop-ups, new modules). Nothing to add by hand.
   - Manual / special case:  SPVOICE.attach(inputEl)   or   <input data-voice>   (opt out with data-novoice)
   - Speaks in the visitor's chosen language (English / हिंदी / Hinglish / Bangla / Punjabi / Marathi / Gujarati / Tamil / Telugu / Kannada / Malayalam / Odia / Urdu / Assamese).
     Hinglish = Hindi speech written in Roman letters.
   - The recognised words are typed into the box and the normal "input" / "change" events fire, so each page's own search runs by itself.
   ===================================================================== */
(function () {
  'use strict';
  if (window.SPVOICE) return;
  var SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  var LANGMAP = { en: 'en-IN', hi: 'hi-IN', hg: 'hi-IN', bn: 'bn-IN', pa: 'pa-IN', mr: 'mr-IN', gu: 'gu-IN', ta: 'ta-IN', te: 'te-IN', kn: 'kn-IN', ml: 'ml-IN', or: 'or-IN', ur: 'ur-IN', as: 'as-IN' };
  var NAME_RE = /search|khoj|खोज|ढूँढ|ढूंढ|\bfind\b|filter|\bflt\b|\bfq\b|\bpq\b|\bcq\b|\biq\b|\boq\b|^q$|^q[-_]|[-_]q$|\bsch/i;
  var SKIP_TYPES = /^(hidden|password|number|checkbox|radio|file|range|color|date|time|datetime-local|email|tel|url|submit|button|reset|image)$/i;
  var tip = null, tipT = 0, active = null, rec = null;

  function I() { return window.SPI18N || null; }
  function curLang() { var i = I(); return i && !i.off ? i.lang : 'en'; }
  function T(s) { var i = I(); if (!i) return s; var r = i.tr ? i.tr(s) : null; return r == null ? s : r; }

  if (window.SPI18N && SPI18N.add) {
    SPI18N.add([
      ['Voice search', 'वॉइस सर्च'],
      ['Speak now…', 'अब बोलिए…'],
      ['Listening… tap again to stop', 'सुन रहा हूँ… रोकने के लिए फिर दबाएँ'],
      ['Voice search is not supported in this browser — please use Chrome, Edge or Safari.', 'इस ब्राउज़र में वॉइस सर्च नहीं चलता — कृपया Chrome, Edge या Safari इस्तेमाल करें।'],
      ['Microphone is blocked — allow the microphone in your browser settings.', 'माइक्रोफ़ोन बंद है — ब्राउज़र की सेटिंग में माइक्रोफ़ोन की अनुमति दें।'],
      ['Nothing heard — please try again.', 'कुछ सुनाई नहीं दिया — कृपया फिर से कोशिश करें।'],
      ['Voice search stopped — please try again.', 'वॉइस सर्च रुक गया — कृपया फिर से कोशिश करें।']
    ]);
  }

  function css() {
    if (document.getElementById('spv-css')) return;
    var s = document.createElement('style'); s.id = 'spv-css';
    s.textContent = 'input.spv-i{padding-right:42px!important}' +
      '.spv-b{position:absolute;z-index:3;width:32px;height:32px;min-width:0;padding:0;margin:0;border:0;border-radius:50%;background:transparent;color:inherit;font:inherit;font-size:17px;line-height:1;display:grid;place-items:center;cursor:pointer;opacity:.78;-webkit-tap-highlight-color:transparent}' +
      '.spv-b:hover,.spv-b:focus-visible{opacity:1;background:rgba(127,127,127,.18);outline:none}' +
      '.spv-b svg{width:18px;height:18px;display:block;pointer-events:none}' +
      '.spv-b.on{opacity:1;background:#d93025;color:#fff;animation:spvp 1.1s ease-in-out infinite}' +
      '@keyframes spvp{0%,100%{box-shadow:0 0 0 0 rgba(217,48,37,.5)}50%{box-shadow:0 0 0 8px rgba(217,48,37,0)}}' +
      '.spv-toast{position:fixed;left:50%;bottom:calc(22px + env(safe-area-inset-bottom,0px));transform:translateX(-50%);z-index:2147483000;max-width:min(92vw,420px);background:#14231a;color:#fff;padding:10px 16px;border-radius:12px;font:600 14px/1.35 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;box-shadow:0 6px 24px rgba(0,0,0,.28);text-align:center}' +
      '.spv-toast.bad{background:#b3261e}';
    (document.head || document.documentElement).appendChild(s);
  }
  var MIC = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v4M8 22h8"/></svg>';

  function say(msg, bad) {
    css(); if (!tip) { tip = document.createElement('div'); tip.className = 'spv-toast'; tip.setAttribute('role', 'status'); tip.setAttribute('aria-live', 'polite'); document.body.appendChild(tip); }
    tip.className = 'spv-toast' + (bad ? ' bad' : ''); tip.textContent = T(msg); tip.hidden = false; clearTimeout(tipT); tipT = setTimeout(function () { if (tip) tip.hidden = true; }, bad ? 4200 : 2200);
  }
  function setVal(inp, v) {
    var d = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(inp), 'value'); if (d && d.set) d.set.call(inp, v); else inp.value = v;
    inp.dispatchEvent(new Event('input', { bubbles: true }));
  }
  function stop() { if (rec) { try { rec.stop(); } catch (e) {} } }
  function done() { if (active) { active.btn.classList.remove('on'); active.btn.setAttribute('aria-pressed', 'false'); } active = null; rec = null; }

  function listen(inp, btn) {
    if (!SR) return say('Voice search is not supported in this browser — please use Chrome, Edge or Safari.', true);
    if (active && active.inp === inp) { stop(); return; }
    stop(); done();
    var r = new SR(), L = curLang(), got = false;
    r.lang = LANGMAP[L] || 'en-IN'; r.interimResults = true; r.continuous = false; r.maxAlternatives = 1;
    active = { inp: inp, btn: btn }; rec = r; btn.classList.add('on'); btn.setAttribute('aria-pressed', 'true');
    r.onstart = function () { say('Listening… tap again to stop'); };
    r.onresult = function (e) {
      var t = ''; for (var i = e.resultIndex; i < e.results.length; i++) t += e.results[i][0].transcript;
      for (var k = 0; k < e.resultIndex; k++) t = e.results[k][0].transcript + ' ' + t;
      t = String(t).replace(/\s+/g, ' ').trim(); if (!t) return; got = true;
      var i18 = I(); if (L === 'hg' && i18 && i18.xlit && /[ऀ-ॿ]/.test(t)) t = i18.xlit(t);
      setVal(inp, t);
      if (e.results[e.results.length - 1].isFinal) { inp.dispatchEvent(new Event('change', { bubbles: true })); try { inp.dispatchEvent(new Event('search', { bubbles: true })); } catch (x) {} }
    };
    r.onerror = function (e) {
      if (e.error === 'not-allowed' || e.error === 'service-not-allowed') say('Microphone is blocked — allow the microphone in your browser settings.', true);
      else if (e.error === 'no-speech') say('Nothing heard — please try again.', true);
      else if (e.error !== 'aborted') say('Voice search stopped — please try again.', true);
      got = true;
    };
    r.onend = function () { if (tip) tip.hidden = true; if (!got) say('Nothing heard — please try again.', true); done(); try { inp.focus(); } catch (x) {} };
    try { r.start(); } catch (e) { done(); say('Voice search stopped — please try again.', true); }
  }

  function wants(el) {
    if (!el || el.tagName !== 'INPUT' || el.__spv || el.hasAttribute('data-spv') || el.hasAttribute('data-novoice') || el.closest('[data-novoice]')) return false;
    var ty = (el.getAttribute('type') || 'text').toLowerCase();
    if (SKIP_TYPES.test(ty) || el.readOnly || el.disabled) return false;
    if (el.hasAttribute('data-voice') || ty === 'search') return true;
    var hay = [el.id, el.name, el.getAttribute('placeholder'), el.getAttribute('aria-label'), el.className, el.getAttribute('data-q') !== null ? 'q' : '', el.getAttribute('data-fq') !== null ? 'fq' : '', el.getAttribute('data-flt') !== null ? 'flt' : '', el.getAttribute('data-f')].join(' ');
    return NAME_RE.test(hay);
  }

  /* The mic is a sibling placed over the right end of the box (the box itself is never moved or wrapped, so each page's own layout / icons / handlers stay exactly as they are). */
  var RO = window.ResizeObserver ? new ResizeObserver(function (list) { list.forEach(function (en) { place(en.target.__spvIn || en.target); }); }) : null;
  function place(inp) {
    var b = inp.__spvBtn; if (!b) return;
    if (!inp.isConnected) { if (b.parentNode) b.parentNode.removeChild(b); if (RO) RO.unobserve(inp); return; }
    var w = inp.offsetWidth, h = inp.offsetHeight, vis = w > 0 && h > 0 && getComputedStyle(inp).visibility !== 'hidden';
    b.hidden = !vis; if (!vis) return;
    if (b.parentNode !== inp.parentNode) inp.parentNode.insertBefore(b, inp.nextSibling);
    var size = Math.max(26, Math.min(32, h - 6));
    b.style.width = b.style.height = size + 'px';
    b.style.left = (inp.offsetLeft + w - size - 5) + 'px'; b.style.top = (inp.offsetTop + (h - size) / 2) + 'px';
  }
  function attach(inp) {
    if (!inp || inp.__spv || !inp.parentNode) return;
    css(); inp.__spv = 1; inp.setAttribute('data-spv', '1'); inp.classList.add('spv-i');
    var b = document.createElement('button'); b.type = 'button'; b.className = 'spv-b'; b.setAttribute('aria-label', 'Voice search'); b.setAttribute('title', 'Voice search'); b.setAttribute('aria-pressed', 'false'); b.setAttribute('data-spv-btn', '1'); b.innerHTML = MIC;
    b.addEventListener('mousedown', function (e) { e.preventDefault(); });
    b.addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation(); listen(inp, b); });
    inp.__spvBtn = b; inp.parentNode.insertBefore(b, inp.nextSibling);
    place(inp);
    if (RO) { RO.observe(inp); if (inp.parentNode.nodeType === 1) { inp.parentNode.__spvIn = inp; RO.observe(inp.parentNode); } }
    inp.addEventListener('focus', function () { place(inp); });
    setTimeout(function () { place(inp); }, 300); setTimeout(function () { place(inp); }, 1500);
  }
  window.addEventListener('resize', function () { var l = document.querySelectorAll('input[data-spv]'); for (var i = 0; i < l.length; i++) place(l[i]); });

  var q = [], qt = 0;
  function scan(root) {
    if (!root || root.nodeType !== 1 && root.nodeType !== 9 && root.nodeType !== 11) return;
    var list = root.nodeType === 1 && root.tagName === 'INPUT' ? [root] : Array.prototype.slice.call(root.querySelectorAll ? root.querySelectorAll('input') : []);
    list.forEach(function (el) { if (wants(el)) q.push(el); });
    if (q.length && !qt) qt = setTimeout(flush, 30);
  }
  function flush() { qt = 0; var l = q; q = []; l.forEach(function (el) { if (el.isConnected && !el.__spv) { try { attach(el); } catch (e) { if (window.console) console.error('voice', e); } } }); }

  function start() {
    scan(document);
    new MutationObserver(function (list) { for (var i = 0; i < list.length; i++) for (var j = 0; j < list[i].addedNodes.length; j++) { var n = list[i].addedNodes[j]; if (n.nodeType === 1) scan(n); } }).observe(document.documentElement, { childList: true, subtree: true });
    document.addEventListener('focusin', function (e) { var t = e.target; if (t && t.tagName === 'INPUT' && wants(t)) scan(t); }, true);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();

  window.SPVOICE = { attach: attach, scan: scan, supported: !!SR, say: say };
})();
