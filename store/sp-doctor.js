/* =====================================================================
   sp-doctor.js — Solar Problem Detector (Website + Online Store)
   - Inverter error: brand + code / display text, ya display ki PHOTO (OCR, phone ke andar hi)
   - Panel photo check (beta) + checklist
   - Doosri problem (symptoms)
   Photo kahin upload / save NAHI hoti — check ke baad turant memory se hata di jaati hai.
   Result ke baad sirf Sunpowers ka number: window.SP_DOCTOR_PHONE (default 9621050636)
   Use:  <button data-doctor>…</button>   ya   SPDoctor.open('inverter' | 'panel' | 'other')
   ===================================================================== */
(function () {
  'use strict';
  if (window.SPDoctor) return;
  var PHONE = String(window.SP_DOCTOR_PHONE || '9621050636').replace(/\D/g, '').slice(-10);
  var OCR_URL = 'https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js';

  /* ---------------- language ---------------- */
  function L() { var l = (window.SPI18N && SPI18N.lang) || ''; if (!l) { var h = document.documentElement.lang || ''; l = /^hi(-IN)?$/i.test(h) ? 'hi' : ''; } if (!l) { try { l = String(localStorage.getItem('sp_lang') || '').replace(/"/g, ''); } catch (e) {} } return l === 'hi' || l === 'hg' ? 'hi' : 'en'; }
  var TX = {
    title: ['Solar Problem Detector', 'सोलर समस्या जाँच'],
    sub: ['Find what is wrong in 1 minute — then talk to our engineer.', '1 मिनट में पता करें क्या गड़बड़ है — फिर हमारे इंजीनियर से बात करें।'],
    close: ['Close', 'बंद करें'],
    back: ['Back', 'वापस'],
    t_inv: ['Inverter shows an error', 'इन्वर्टर पर एरर दिख रहा है'],
    t_inv_s: ['Type the code or take a photo of the display', 'कोड लिखें या डिस्प्ले की फ़ोटो लें'],
    t_pan: ['Panel / low generation', 'पैनल / कम बिजली बन रही है'],
    t_pan_s: ['Photo check (beta) + quick checklist', 'फ़ोटो जाँच (बीटा) + आसान चेकलिस्ट'],
    t_oth: ['Other problem', 'दूसरी समस्या'],
    t_oth_s: ['Display off, tripping, bill, battery, app', 'डिस्प्ले बंद, ट्रिपिंग, बिल, बैटरी, ऐप'],
    brand: ['Inverter brand', 'इन्वर्टर ब्रांड'],
    unver: ['unverified list — model / firmware may differ; check your manual', 'अपुष्ट सूची — मॉडल / फ़र्मवेयर से अलग हो सकता है; अपना मैनुअल देखें'],
    brand_other: ['Other / not sure', 'दूसरा / पता नहीं'],
    code: ['Error code or message on the display', 'डिस्प्ले पर लिखा एरर कोड या मैसेज'],
    code_ph: ['e.g. F35, Error 117, NO-Grid, PV Isolation Low', 'जैसे F35, Error 117, NO-Grid, PV Isolation Low'],
    photo: ['Take / upload photo of display', 'डिस्प्ले की फ़ोटो लें / अपलोड करें'],
    photo_p: ['Take / upload panel photo', 'पैनल की फ़ोटो लें / अपलोड करें'],
    reading: ['Reading the photo…', 'फ़ोटो पढ़ी जा रही है…'],
    read_ok: ['Text found in photo — check and correct it if needed:', 'फ़ोटो में ये लिखा मिला — ज़रूरत हो तो ठीक करें:'],
    read_fail: ['Could not read the photo clearly. Please type the code shown on the display.', 'फ़ोटो साफ़ नहीं पढ़ी गई। डिस्प्ले पर लिखा कोड खुद लिखें।'],
    check: ['Check problem', 'समस्या जाँचें'],
    need_code: ['Type the code / message or add a photo first.', 'पहले कोड / मैसेज लिखें या फ़ोटो लगाएँ।'],
    privacy: ['🔒 Your photo is checked only on your phone. It is never uploaded or saved, and is deleted right after the check.', '🔒 फ़ोटो सिर्फ़ आपके फ़ोन में जाँची जाती है — कहीं अपलोड या सेव नहीं होती, जाँच के तुरंत बाद हटा दी जाती है।'],
    found: ['What it means', 'इसका मतलब'],
    safe: ['What you can safely check', 'आप सुरक्षित रूप से ये देख सकते हैं'],
    never: ['Do not open the inverter or touch the DC (panel) cables. Leave repairs to a trained technician.', 'इन्वर्टर न खोलें और DC (पैनल) केबल न छुएँ। रिपेयर सिर्फ़ ट्रेंड टेक्नीशियन से कराएँ।'],
    sev_high: ['Serious — call us now', 'गंभीर — अभी कॉल करें'],
    sev_medium: ['Needs attention', 'ध्यान देना ज़रूरी'],
    sev_low: ['Usually clears by itself', 'अक्सर अपने-आप ठीक हो जाता है'],
    nomatch: ['This code is not in our list yet', 'ये कोड अभी हमारी सूची में नहीं है'],
    nomatch_p: ['No problem — our engineer will tell you exactly what it means. Call or WhatsApp us with the code.', 'कोई बात नहीं — हमारे इंजीनियर सही मतलब बताएँगे। कोड के साथ कॉल या WhatsApp करें।'],
    pick_brand: ['Several brands use this code. Choose your brand for the exact meaning.', 'ये कोड कई ब्रांड में आता है। सही मतलब के लिए अपना ब्रांड चुनें।'],
    call: ['Call now', 'अभी कॉल करें'],
    wa: ['WhatsApp', 'WhatsApp'],
    help: ['Talk to a Sunpowers engineer', 'Sunpowers इंजीनियर से बात करें'],
    help_s: ['Free advice on call — service visit if needed.', 'कॉल पर मुफ़्त सलाह — ज़रूरत हो तो सर्विस विज़िट।'],
    again: ['Check another problem', 'दूसरी समस्या जाँचें'],
    see: ['What do you see? (tick all that apply)', 'आपको क्या दिख रहा है? (जो-जो सही हो, टिक करें)'],
    beta: ['Beta', 'बीटा'],
    beta_note: ['Photo check is a rough estimate (light and haze only) — the checklist below matters more.', 'फ़ोटो जाँच सिर्फ़ अंदाज़ा है (रोशनी और धुंधलापन) — नीचे की चेकलिस्ट ज़्यादा ज़रूरी है।'],
    photo_dark: ['Photo looks dark — take it in daylight for a better check.', 'फ़ोटो अंधेरी है — दिन की रोशनी में फ़ोटो लें।'],
    photo_hazy: ['Panel surface looks hazy / dusty in the photo — cleaning may help.', 'फ़ोटो में पैनल धुंधला / धूल भरा दिख रहा है — सफ़ाई से फ़ायदा हो सकता है।'],
    photo_ok: ['Photo looks clear. No heavy dust visible.', 'फ़ोटो साफ़ है। ज़्यादा धूल नहीं दिख रही।'],
    pick_one: ['Tick at least one option.', 'कम से कम एक विकल्प टिक करें।'],
    result: ['Result', 'नतीजा'],
    wa_msg: ['Hello Sunpowers, I need help with my solar system.', 'नमस्ते Sunpowers, मुझे सोलर सिस्टम में मदद चाहिए।']
  };
  function t(k) { var v = TX[k]; return v ? v[L() === 'hi' ? 1 : 0] : k; }
  function pick(o, k) { return o[k + '_' + L()] || o[k + '_en']; }

  /* ---------------- knowledge ---------------- */
  var C = {
    no_grid: { sev: 'low', title_en: 'Grid power not available', title_hi: 'ग्रिड (बिजली विभाग) की बिजली नहीं मिल रही',
      m_en: 'The inverter cannot see grid power. An on-grid inverter switches off for safety when the grid supply is off, and starts again by itself when power returns.',
      m_hi: 'इन्वर्टर को ग्रिड की बिजली नहीं मिल रही। बिजली जाने पर ऑन-ग्रिड इन्वर्टर सुरक्षा के लिए बंद हो जाता है और बिजली आने पर अपने-आप चालू हो जाता है।',
      s_en: ['Check if there is electricity in the house / area right now.', 'Check that the AC MCB / isolator near the inverter and in the meter box is ON.', 'After power returns, wait 5–10 minutes — the inverter restarts by itself.', 'If grid power is ON and the error stays, call us.'],
      s_hi: ['देखें कि अभी घर / इलाके में बिजली है या नहीं।', 'इन्वर्टर के पास और मीटर बॉक्स में AC MCB / आइसोलेटर ON है या नहीं, देखें।', 'बिजली आने के बाद 5–10 मिनट रुकें — इन्वर्टर अपने-आप चालू होता है।', 'बिजली होने पर भी एरर रहे तो हमें कॉल करें।'] },
    grid_voltage: { sev: 'medium', title_en: 'Grid voltage too high or too low', title_hi: 'ग्रिड वोल्टेज बहुत ज़्यादा या कम',
      m_en: 'The electricity line voltage went outside the safe range, so the inverter stopped for a while. It is common in the afternoon when line voltage rises.',
      m_hi: 'बिजली लाइन का वोल्टेज सुरक्षित सीमा से बाहर गया, इसलिए इन्वर्टर कुछ देर के लिए रुका। दोपहर में लाइन वोल्टेज बढ़ने पर ऐसा अक्सर होता है।',
      s_en: ['Wait 5–10 minutes — it usually restarts by itself.', 'Note the time when it happens (e.g. every afternoon).', 'If it repeats daily, call us — we check the settings and cable size, and help you get the line voltage checked by the electricity department.'],
      s_hi: ['5–10 मिनट रुकें — अक्सर अपने-आप चालू हो जाता है।', 'ये किस समय होता है, नोट करें (जैसे रोज़ दोपहर)।', 'रोज़ हो तो कॉल करें — हम सेटिंग और केबल जाँचेंगे और बिजली विभाग से लाइन वोल्टेज चेक कराने में मदद करेंगे।'] },
    grid_freq: { sev: 'low', title_en: 'Grid frequency out of range', title_hi: 'ग्रिड फ़्रीक्वेंसी सीमा से बाहर',
      m_en: 'The grid frequency was unstable for a moment, so the inverter paused for safety.',
      m_hi: 'ग्रिड की फ़्रीक्वेंसी कुछ देर अस्थिर रही, इसलिए इन्वर्टर सुरक्षा के लिए रुका।',
      s_en: ['Wait 5–10 minutes — it normally clears by itself.', 'If you run a generator / DG, the inverter will not run on it — this is normal.', 'If it repeats many times a day, call us.'],
      s_hi: ['5–10 मिनट रुकें — आमतौर पर अपने-आप ठीक हो जाता है।', 'जनरेटर / DG चल रहा हो तो इन्वर्टर उस पर नहीं चलता — ये सामान्य है।', 'दिन में कई बार हो तो कॉल करें।'] },
    isolation: { sev: 'high', title_en: 'Insulation (earth) fault on panel side', title_hi: 'पैनल साइड पर इंसुलेशन (अर्थ) फ़ॉल्ट',
      m_en: 'There is a leakage path from the panel (DC) wiring to earth — often a damaged cable, water in a connector, or a damaged panel. Often seen after rain.',
      m_hi: 'पैनल (DC) वायरिंग से अर्थ की ओर लीकेज है — अक्सर कटी केबल, कनेक्टर में पानी या खराब पैनल। बारिश के बाद ज़्यादा दिखता है।',
      s_en: ['Do not touch panels, cables or the inverter. Keep children away.', 'If it started after rain, it may clear once things dry — but still call us.', 'Look (from a distance) for cut / burnt cables or broken panel glass and tell us.'],
      s_hi: ['पैनल, केबल या इन्वर्टर को न छुएँ। बच्चों को दूर रखें।', 'बारिश के बाद शुरू हुआ हो तो सूखने पर ठीक हो सकता है — फिर भी कॉल करें।', 'दूर से देखें कि कोई केबल कटी / जली या पैनल का शीशा टूटा तो नहीं — हमें बताएँ।'] },
    leakage: { sev: 'high', title_en: 'Leakage (residual) current too high', title_hi: 'लीकेज (रेज़िडुअल) करंट ज़्यादा',
      m_en: 'The inverter detected current leaking to earth and stopped for safety. It needs a technician check of earthing and wiring.',
      m_hi: 'इन्वर्टर ने अर्थ में करंट लीक होता पाया और सुरक्षा के लिए बंद हुआ। अर्थिंग और वायरिंग की टेक्नीशियन से जाँच ज़रूरी है।',
      s_en: ['Do not touch the inverter, panels or cables.', 'Note if it started after rain or after any work on the roof.', 'Call us — an engineer must check earthing and wiring.'],
      s_hi: ['इन्वर्टर, पैनल या केबल न छुएँ।', 'नोट करें कि ये बारिश या छत पर किसी काम के बाद शुरू हुआ या नहीं।', 'कॉल करें — इंजीनियर को अर्थिंग और वायरिंग जाँचनी होगी।'] },
    over_temp: { sev: 'medium', title_en: 'Inverter too hot', title_hi: 'इन्वर्टर ज़्यादा गरम',
      m_en: 'The inverter is overheating and reduces or stops power to protect itself.',
      m_hi: 'इन्वर्टर ज़्यादा गरम हो रहा है, इसलिए खुद को बचाने के लिए बिजली कम या बंद कर रहा है।',
      s_en: ['Make sure the vents / fan grille are not blocked and nothing is kept against the inverter.', 'Check if it gets direct afternoon sun — a small shade helps.', 'Wipe dust off the outer grille with a dry cloth (do not open the inverter).', 'If it repeats, call us — the fan may need service.'],
      s_hi: ['देखें कि वेंट / पंखे की जाली बंद न हो और इन्वर्टर से सटाकर कुछ न रखा हो।', 'देखें कि दोपहर की सीधी धूप तो नहीं पड़ती — छोटी छाया से फ़ायदा होता है।', 'बाहर की जाली की धूल सूखे कपड़े से साफ़ करें (इन्वर्टर न खोलें)।', 'बार-बार हो तो कॉल करें — पंखे की सर्विस लग सकती है।'] },
    pv_over_voltage: { sev: 'high', title_en: 'Panel (DC) voltage too high', title_hi: 'पैनल (DC) वोल्टेज बहुत ज़्यादा',
      m_en: 'The voltage coming from the panels is above what the inverter allows. This is a design / wiring issue and must be checked by an engineer.',
      m_hi: 'पैनल से आ रहा वोल्टेज इन्वर्टर की सीमा से ज़्यादा है। ये डिज़ाइन / वायरिंग की समस्या है, इंजीनियर से जाँच ज़रूरी है।',
      s_en: ['Do not switch the DC isolator on and off repeatedly.', 'Do not touch panel cables.', 'Call us — note if any panels were added or changed recently.'],
      s_hi: ['DC आइसोलेटर को बार-बार ON-OFF न करें।', 'पैनल की केबल न छुएँ।', 'कॉल करें — बताएँ कि हाल में कोई पैनल जोड़ा या बदला गया हो।'] },
    pv_fault: { sev: 'high', title_en: 'Panel (DC) input fault', title_hi: 'पैनल (DC) इनपुट फ़ॉल्ट',
      m_en: 'Something is wrong on the panel input side — for example a reversed or loose string, or abnormal DC current.',
      m_hi: 'पैनल इनपुट साइड में गड़बड़ है — जैसे स्ट्रिंग उलटी या ढीली, या DC करंट असामान्य।',
      s_en: ['Do not touch panel cables or connectors.', 'Look from a distance for loose or hanging wires on the roof.', 'Call us — a technician must check the strings.'],
      s_hi: ['पैनल केबल या कनेक्टर न छुएँ।', 'छत पर दूर से देखें कि कोई तार ढीला या लटका तो नहीं।', 'कॉल करें — टेक्नीशियन को स्ट्रिंग जाँचनी होगी।'] },
    pv_low: { sev: 'low', title_en: 'Low sunlight / waiting for panels', title_hi: 'धूप कम / पैनल का इंतज़ार',
      m_en: 'Panel power is too low to start. This is normal early morning, evening or on very cloudy days.',
      m_hi: 'पैनल की बिजली शुरू होने के लिए कम है। सुबह, शाम या बहुत बादल होने पर ये सामान्य है।',
      s_en: ['Check again in good sunlight (10 AM – 3 PM).', 'Clean dust from panels if they are safely reachable — water only, early morning or evening.', 'If it shows this in full sun, call us.'],
      s_hi: ['अच्छी धूप में (सुबह 10 – दोपहर 3) फिर देखें।', 'पैनल सुरक्षित पहुँच में हों तो धूल साफ़ करें — सिर्फ़ पानी से, सुबह या शाम।', 'तेज़ धूप में भी ये दिखे तो कॉल करें।'] },
    dc_injection: { sev: 'medium', title_en: 'DC injection to grid too high', title_hi: 'ग्रिड में DC इंजेक्शन ज़्यादा',
      m_en: 'The inverter detected a DC component in its AC output — an internal check. It may clear after a restart; if it repeats, the inverter needs service.',
      m_hi: 'इन्वर्टर ने अपने AC आउटपुट में DC हिस्सा पाया — ये अंदरूनी जाँच है। रीस्टार्ट से ठीक हो सकता है; बार-बार हो तो सर्विस चाहिए।',
      s_en: ['Wait 10 minutes and see if it clears.', 'Note how often it appears.', 'If it repeats, call us.'],
      s_hi: ['10 मिनट रुककर देखें कि ठीक हुआ या नहीं।', 'नोट करें कि कितनी बार आता है।', 'बार-बार आए तो कॉल करें।'] },
    fan: { sev: 'medium', title_en: 'Fan fault', title_hi: 'पंखे में खराबी',
      m_en: 'The inverter cooling fan is not working properly. The inverter may reduce power when hot.',
      m_hi: 'इन्वर्टर का कूलिंग पंखा ठीक से नहीं चल रहा। गरम होने पर इन्वर्टर बिजली कम कर सकता है।',
      s_en: ['Check that the fan grille is not blocked by dust or objects (from outside).', 'Call us for fan service.'],
      s_hi: ['बाहर से देखें कि पंखे की जाली धूल या किसी चीज़ से बंद तो नहीं।', 'पंखे की सर्विस के लिए कॉल करें।'] },
    relay: { sev: 'medium', title_en: 'Relay self-check failed', title_hi: 'रिले सेल्फ़-चेक फ़ेल',
      m_en: 'The inverter could not pass its relay safety check before connecting to the grid. It may be a grid issue or an internal fault.',
      m_hi: 'ग्रिड से जुड़ने से पहले इन्वर्टर रिले सुरक्षा जाँच पास नहीं कर पाया। ये ग्रिड की समस्या या अंदरूनी खराबी हो सकती है।',
      s_en: ['Wait 10–15 minutes — it retries by itself.', 'If it keeps showing, call us.'],
      s_hi: ['10–15 मिनट रुकें — ये खुद दोबारा कोशिश करता है।', 'लगातार दिखे तो कॉल करें।'] },
    comm: { sev: 'low', title_en: 'Communication / monitoring problem', title_hi: 'कम्युनिकेशन / मॉनिटरिंग समस्या',
      m_en: 'The inverter cannot talk to the WiFi stick, meter or monitoring app. Power generation may still be normal.',
      m_hi: 'इन्वर्टर WiFi स्टिक, मीटर या मॉनिटरिंग ऐप से बात नहीं कर पा रहा। बिजली बनना शायद सामान्य हो।',
      s_en: ['Check that the house WiFi router is ON and the WiFi password was not changed.', 'Check the light on the WiFi / data stick.', 'If you changed the router or password, call us to reconnect it.'],
      s_hi: ['देखें कि घर का WiFi राउटर ON है और WiFi पासवर्ड बदला तो नहीं।', 'WiFi / डेटा स्टिक की लाइट देखें।', 'राउटर या पासवर्ड बदला हो तो दोबारा जोड़ने के लिए कॉल करें।'] },
    arc: { sev: 'high', title_en: 'Arc fault detected — stop', title_hi: 'आर्क फ़ॉल्ट — रुकें',
      m_en: 'The inverter detected sparking (arcing) in the panel wiring. This can be a fire risk.',
      m_hi: 'इन्वर्टर ने पैनल वायरिंग में स्पार्किंग (आर्क) पकड़ी है। इससे आग का ख़तरा हो सकता है।',
      s_en: ['Do not touch the panels, cables or inverter.', 'If you see smoke or smell burning, switch OFF the main AC MCB from a safe distance and keep away.', 'Call us immediately.'],
      s_hi: ['पैनल, केबल या इन्वर्टर न छुएँ।', 'धुआँ या जलने की गंध हो तो सुरक्षित दूरी से मेन AC MCB बंद करें और दूर रहें।', 'तुरंत कॉल करें।'] },
    battery: { sev: 'medium', title_en: 'Battery problem', title_hi: 'बैटरी की समस्या',
      m_en: 'The battery is low, not connected, or its BMS is not communicating with the inverter.',
      m_hi: 'बैटरी कम है, जुड़ी नहीं है, या उसका BMS इन्वर्टर से बात नहीं कर रहा।',
      s_en: ['Check (from outside) that the battery switch / breaker is ON.', 'During a power cut, switch off heavy loads so the battery lasts longer.', 'If it does not charge in sunlight, call us.'],
      s_hi: ['बाहर से देखें कि बैटरी स्विच / ब्रेकर ON है।', 'बिजली कटौती में भारी लोड बंद करें ताकि बैटरी ज़्यादा चले।', 'धूप में भी चार्ज न हो तो कॉल करें।'] },
    overload: { sev: 'medium', title_en: 'Overload', title_hi: 'ओवरलोड',
      m_en: 'More load is connected than the inverter can supply (often on backup during a power cut).',
      m_hi: 'इन्वर्टर की क्षमता से ज़्यादा लोड लगा है (अक्सर बिजली कटौती में बैकअप पर)।',
      s_en: ['Switch off heavy appliances — AC, geyser, motor, iron, heater.', 'Wait a minute and restart the loads one by one.', 'If it repeats with normal load, call us.'],
      s_hi: ['भारी उपकरण बंद करें — AC, गीज़र, मोटर, प्रेस, हीटर।', 'एक मिनट रुककर उपकरण एक-एक करके चलाएँ।', 'सामान्य लोड पर भी बार-बार हो तो कॉल करें।'] },
    internal: { sev: 'high', title_en: 'Internal inverter fault', title_hi: 'इन्वर्टर की अंदरूनी खराबी',
      m_en: 'The inverter found a problem in its own hardware or self-test. It needs a technician (often a warranty case).',
      m_hi: 'इन्वर्टर ने अपने हार्डवेयर या सेल्फ़-टेस्ट में खराबी पाई। टेक्नीशियन चाहिए (अक्सर वारंटी केस)।',
      s_en: ['Wait 10–15 minutes — some faults clear after an automatic restart.', 'Take a clear photo of the display and keep the warranty card ready.', 'Call us — we handle the warranty claim with the company.'],
      s_hi: ['10–15 मिनट रुकें — कुछ खराबी अपने-आप रीस्टार्ट से ठीक होती है।', 'डिस्प्ले की साफ़ फ़ोटो लें और वारंटी कार्ड तैयार रखें।', 'कॉल करें — कंपनी से वारंटी क्लेम हम कराते हैं।'] },
    info: { sev: 'low', title_en: 'Status message (not an error)', title_hi: 'स्टेटस मैसेज (एरर नहीं)',
      m_en: 'This is a normal status / information message from the inverter.',
      m_hi: 'ये इन्वर्टर का सामान्य स्टेटस / जानकारी वाला मैसेज है।',
      s_en: ['No action needed if power generation is normal.', 'If generation is low, check again in full sun or call us.'],
      s_hi: ['बिजली सामान्य बन रही हो तो कुछ करने की ज़रूरत नहीं।', 'बिजली कम बने तो तेज़ धूप में फिर देखें या कॉल करें।'] }
  ,
    vfd_oc: { sev: 'high', title_en: 'Drive / motor over-current', title_hi: 'ड्राइव / मोटर में ओवर-करंट',
      m_en: 'The drive (VFD) stopped because the motor drew more current than allowed. Common causes: jammed or heavy pump, very fast ramp-up, short circuit in the motor or cable.',
      m_hi: 'मोटर ने ज़रूरत से ज़्यादा करंट खींचा, इसलिए ड्राइव (VFD) बंद हो गया। आम कारण: पंप फँसा या भारी, बहुत तेज़ स्टार्ट, मोटर या केबल में शॉर्ट।',
      s_en: ['Switch OFF the drive and wait 5 minutes before trying again.', 'Check (from outside) that the pump or load is not jammed or choked.', 'If it trips again right after start, do not keep resetting — call us.'],
      s_hi: ['ड्राइव बंद करें और दोबारा चलाने से पहले 5 मिनट रुकें।', 'बाहर से देखें कि पंप या लोड फँसा या जाम तो नहीं।', 'चालू करते ही फिर ट्रिप करे तो बार-बार रीसेट न करें — हमें कॉल करें।'] },
    vfd_ov: { sev: 'medium', title_en: 'Drive DC-bus over-voltage', title_hi: 'ड्राइव में DC-बस ओवर-वोल्टेज',
      m_en: 'The voltage inside the drive went too high. This can come from a high supply voltage, or from the motor feeding energy back while stopping.',
      m_hi: 'ड्राइव के अंदर वोल्टेज बहुत बढ़ गया। ये सप्लाई वोल्टेज ज़्यादा होने से, या रुकते समय मोटर से ऊर्जा वापस आने से हो सकता है।',
      s_en: ['Switch OFF and restart after a few minutes.', 'If it repeats at the same time of day, the supply voltage may be high — call us.'],
      s_hi: ['बंद करें और कुछ मिनट बाद चालू करें।', 'रोज़ एक ही समय पर दोहराए तो सप्लाई वोल्टेज ज़्यादा हो सकता है — हमें कॉल करें।'] },
    vfd_uv: { sev: 'medium', title_en: 'Drive under-voltage', title_hi: 'ड्राइव में अंडर-वोल्टेज',
      m_en: 'The supply or solar (DC) voltage to the drive is too low. For a solar pump this usually means weak sunlight, or a loose / undersized cable.',
      m_hi: 'ड्राइव को मिलने वाली सप्लाई या सोलर (DC) वोल्टेज कम है। सोलर पंप में ये अक्सर कम धूप, या ढीले / पतले केबल की वजह से होता है।',
      s_en: ['Wait for stronger sunlight — it usually restarts by itself.', 'Check from outside that panels are clean and not shaded.', 'If it happens in full sun, call us to check the cables and connections.'],
      s_hi: ['तेज़ धूप का इंतज़ार करें — ये अक्सर खुद चालू हो जाता है।', 'बाहर से देखें कि पैनल साफ़ हैं और छाया में नहीं।', 'पूरी धूप में भी हो तो केबल और कनेक्शन जाँचने के लिए कॉल करें।'] },
    vfd_gf: { sev: 'high', title_en: 'Motor / cable earth (ground) fault', title_hi: 'मोटर / केबल में अर्थ (ग्राउंड) फ़ॉल्ट',
      m_en: 'Current is leaking to earth from the motor or its cable — often damaged insulation or water entering a joint. This can give an electric shock.',
      m_hi: 'मोटर या उसके केबल से करंट अर्थ में लीक हो रहा है — अक्सर इन्सुलेशन खराब या जोड़ में पानी जाने से। इससे बिजली का झटका लग सकता है।',
      s_en: ['Do not touch the pump, pipe or cable with wet hands.', 'Switch OFF the drive and the main supply.', 'Call us — the motor and cable need an insulation test.'],
      s_hi: ['गीले हाथों से पंप, पाइप या केबल न छुएँ।', 'ड्राइव और मेन सप्लाई बंद करें।', 'हमें कॉल करें — मोटर और केबल की इन्सुलेशन जाँच चाहिए।'] },
    vfd_oh: { sev: 'medium', title_en: 'Drive over-heating', title_hi: 'ड्राइव ज़्यादा गरम',
      m_en: 'The drive is too hot. Common causes: direct sun on the box, blocked vents, a dead cooling fan or very hot weather.',
      m_hi: 'ड्राइव बहुत गरम है। आम कारण: डिब्बे पर सीधी धूप, वेंट बंद, कूलिंग पंखा बंद या बहुत गर्मी।',
      s_en: ['Let it cool for 20–30 minutes in shade.', 'Check from outside that vents are free of dust and the fan turns.', 'If it repeats, call us for service.'],
      s_hi: ['छाया में 20–30 मिनट ठंडा होने दें।', 'बाहर से देखें कि वेंट में धूल नहीं और पंखा घूम रहा है।', 'बार-बार हो तो सर्विस के लिए कॉल करें।'] },
    vfd_phase: { sev: 'medium', title_en: 'Phase loss / supply problem', title_hi: 'फ़ेज़ गायब / सप्लाई की समस्या',
      m_en: 'One phase of the supply or the motor is missing or unbalanced. A running motor on a missing phase can burn.',
      m_hi: 'सप्लाई या मोटर की कोई एक फ़ेज़ गायब या असंतुलित है। फ़ेज़ गायब होने पर मोटर चलती रहे तो जल सकती है।',
      s_en: ['Switch OFF the drive.', 'Check that the main breaker and fuses are ON (from outside).', 'Call us before restarting.'],
      s_hi: ['ड्राइव बंद करें।', 'बाहर से देखें कि मेन ब्रेकर और फ़्यूज़ ON हैं।', 'दोबारा चालू करने से पहले हमें कॉल करें।'] },
    vfd_dry: { sev: 'medium', title_en: 'Dry run / no water / low load', title_hi: 'ड्राई रन / पानी नहीं / कम लोड',
      m_en: 'The pump is running with little or no water (or the load is unusually low). Running dry damages the pump seal and motor.',
      m_hi: 'पंप बहुत कम या बिना पानी के चल रहा है (या लोड असामान्य रूप से कम है)। बिना पानी चलाने से पंप की सील और मोटर खराब होती है।',
      s_en: ['Check the water level in the well / tank and that the suction side is not choked.', 'Wait for the water level to recover, then restart.', 'If water is fine and it still shows, call us.'],
      s_hi: ['कुएँ / टंकी में पानी का स्तर और सक्शन साइड बंद तो नहीं — देखें।', 'पानी का स्तर वापस आने दें, फिर चालू करें।', 'पानी ठीक है फिर भी दिखे तो हमें कॉल करें।'] }
};

  // Brand code tables (+ Round 20 EXTRA block neeche) — sirf manufacturer / installer documents se mile codes (Sources: Solis service portal "Alarm codes (complete list)", GoodWe FAQ, Growatt error list, Deye hybrid fault list, Sungrow fault list, Huawei SUN2000 manuals)
  function R(code, msg, cat, alias, u) { return { code: code, msg: msg, cat: cat, alias: alias || [], u: !!u }; }
  function U(code, msg, cat, alias) { return R(code, msg, cat, alias, true); } // third-party / unverified list — shown with a 'confirm with manual' note
  var BRANDS = [
    { id: 'growatt', name: 'Growatt', codes: [
      R('No AC Connection', 'No grid connection / grid power failure', 'no_grid'), R('AC V Outrange', 'Grid voltage out of range', 'grid_voltage'), R('AC F Outrange', 'Grid frequency out of range', 'grid_freq'),
      R('Over Temperature', 'Temperature out of range', 'over_temp'), R('PV Isolation Low', 'Insulation problem', 'isolation'), R('Output High DCI', 'Output DC current too high', 'dc_injection'),
      R('Residual I High', 'Leakage current too high', 'leakage'), R('PV Voltage High', 'DC input voltage above maximum', 'pv_over_voltage'), R('Auto Test Failed', 'Self-test failed', 'internal'),
      R('Error 100', '2.5 V reference voltage fault', 'internal'), R('Error 101', 'Communication fault', 'internal'), R('Error 102', 'Master/slave processor data mismatch', 'internal'),
      R('Error 116', 'EEPROM fault', 'internal'), R('Error 117', 'Relay fault', 'relay'), R('Error 118', 'Init model fault', 'internal'), R('Error 119', 'GFCI device damage', 'internal'),
      R('Error 120', 'HCT fault', 'internal'), R('Error 121', 'Master cannot receive data from slave processor', 'internal'), R('Error 122', 'Bus voltage fault', 'internal')] },
    { id: 'sungrow', name: 'Sungrow', codes: [
      R('002', 'Grid over-voltage', 'grid_voltage'), R('003', 'Transient grid fault', 'grid_voltage'), R('004', 'Grid under-voltage', 'grid_voltage'), R('005', 'Transient grid fault', 'grid_voltage'),
      R('006', 'AC over-current', 'internal'), R('007', 'Transient grid fault', 'grid_voltage'), R('010', 'Grid failure (islanding) — grid not detected', 'no_grid'),
      R('012', 'Insulation / leakage current fault', 'leakage'), R('014', 'Grid voltage fault', 'grid_voltage'), R('015', 'Grid voltage fault', 'grid_voltage'), R('019', 'Transient grid fault', 'grid_voltage'),
      R('021', 'PV input fault', 'pv_fault'), R('022', 'PV input fault', 'pv_fault'), R('036', 'Temperature fault', 'over_temp'), R('037', 'Temperature fault', 'over_temp'),
      R('039', 'Insulation / leakage fault', 'isolation'), R('041', 'Insulation / leakage fault', 'isolation'), R('056', 'Insulation / leakage fault', 'isolation'), R('059', 'Communication / sensor error', 'internal')] },
    { id: 'solis', name: 'Solis (Ginlong)', codes: [
      R('NO-Grid', 'No grid detected', 'no_grid', ['1015']), R('OV-G-V', 'Grid voltage above limit', 'grid_voltage', ['1010']), R('UN-G-V', 'Grid voltage below limit', 'grid_voltage', ['1011']),
      R('OV-G-F', 'Grid frequency above limit', 'grid_freq', ['1012']), R('UN-G-F', 'Grid frequency below limit', 'grid_freq', ['1013']), R('G-F-FLU', 'Grid frequency abnormal', 'grid_freq', ['1017']),
      R('G-PHASE', 'Unbalanced three-phase grid', 'grid_voltage', ['1016']), R('GRID-INTF', 'Grid interference / loose AC connection', 'grid_voltage', ['1030']),
      R('OV-G-I', 'Grid output overcurrent', 'internal', ['1018']), R('OV-DC', 'DC overvoltage', 'pv_over_voltage', ['1020']), R('OV-BUS', 'DC bus overvoltage', 'internal', ['1021']),
      R('UN-BUS', 'DC bus voltage too low', 'internal', ['1023']), R('DC-INTF', 'Abnormal DC input current', 'pv_fault', ['1027']), R('Reve-DC', 'DC input reversed', 'pv_fault', ['1028']),
      R('OV-TEM', 'Internal temperature too high', 'over_temp', ['1032']), R('PV ISO-PRO', 'Low PV insulation', 'isolation', ['1033', 'PV ISO-PRO 01', 'PV ISO-PRO 02']),
      R('ILeak-PRO', 'Leakage current protection', 'leakage', ['1034', 'ILeak-PRO 01', 'ILeak-PRO 02', 'ILeak-PRO 03', 'ILeak-PRO 04']), R('RelayChk-FAIL', 'Relay self-check fault', 'relay', ['1035']),
      R('DCInj-FAULT', 'DC injection too large', 'dc_injection', ['1037']), R('12Power-FAULT', '12V power supply fault', 'internal', ['1038']), R('ILeak-Check', 'Leakage sensor self-check fault', 'internal', ['1039']),
      R('INI-FAULT', 'DSP initialization fault', 'internal', ['1031']), R('DSP-B-FAULT', 'Master/slave DSP fault', 'internal', ['1036']), R('AFCI-Check', 'AFCI self-check fault', 'internal', ['1040']),
      R('ARC-FAULT', 'DC arc detected', 'arc', ['1041']), R('IGBT-OV-I', 'IGBT overcurrent', 'internal', ['1048']), R('Fan Alarm', 'Fan fault', 'fan'), R('Over-Load', 'Backup load overloaded', 'overload', ['1057']),
      R('NO-Battery', 'Battery not connected', 'battery', ['1055']), R('OV-Vbatt', 'Battery overvoltage', 'battery', ['1053']), R('UN-Vbatt', 'Battery undervoltage', 'battery', ['1054']),
      R('Alarm1-BMS', 'Battery BMS alarm', 'battery', ['2015']), R('CAN_Comm_FAIL', 'Battery communication failure', 'battery', ['2012']), R('MET_Comm_FAIL', 'Meter communication failure', 'comm', ['2011']),
      R('Failsafe', 'Export manager communication failure', 'comm', ['2010']), R('Waiting', 'Waiting — DC input below start voltage', 'pv_low'), R('Grid Off', 'Inverter set to Grid OFF', 'info')] },
    { id: 'goodwe', name: 'GoodWe', codes: [
      R('Utility Loss', 'No AC voltage at the inverter', 'no_grid'), R('Vac Failure', 'Grid voltage out of range', 'grid_voltage'), R('Fac Failure', 'Grid frequency out of range', 'grid_freq'),
      R('ISO Failure', 'PV insulation resistance too low', 'isolation', ['Isolation Failure']), R('Ground I Failure', 'Leakage current too high', 'leakage'), R('PV Overvoltage', 'PV input voltage too high', 'pv_over_voltage')] },
    { id: 'deye', name: 'Deye', codes: [
      R('F08', 'GFDI relay failure', 'internal'), R('F13', 'Working mode changed', 'info'), R('F18', 'Hardware AC overcurrent', 'internal'), R('F20', 'Hardware DC overcurrent', 'internal'),
      R('F22', 'Emergency stop fault', 'internal'), R('F23', 'AC leakage current transient overcurrent', 'leakage'), R('F24', 'DC insulation impedance failure', 'isolation'), R('F26', 'DC busbar unbalanced', 'internal'),
      R('F29', 'Parallel CAN bus fault', 'comm'), R('F34', 'AC overcurrent', 'overload'), R('F35', 'No AC grid', 'no_grid'), R('F41', 'Parallel system stop', 'internal'),
      R('F42', 'AC line low voltage', 'grid_voltage'), R('F47', 'AC over frequency', 'grid_freq'), R('F48', 'AC under frequency', 'grid_freq'), R('F56', 'DC busbar voltage too low (often battery low)', 'battery'),
      R('F58', 'BMS communication fault', 'battery'), R('F63', 'Arc fault', 'arc'), R('F64', 'Heat sink high temperature', 'over_temp')] },
    { id: 'huawei', name: 'Huawei', codes: [
      R('2033', 'Grid Undervoltage', 'grid_voltage'), R('2062', 'Low Insulation Resistance', 'isolation'), R('103', 'High DC Input Voltage', 'pv_over_voltage'),
      R('301', 'Abnormal Grid Voltage', 'grid_voltage'), R('305', 'Abnormal Grid Frequency', 'grid_freq'), R('313', 'Low Insulation Resistance', 'isolation'), R('318', 'Abnormal Residual Current', 'leakage'),
      R('321', 'Cabinet Overtemperature', 'over_temp'), R('326', 'Abnormal Grounding', 'leakage'), R('400', 'System Fault', 'internal')] },
    { id: 'solax', name: 'SolaX', codes: [
      R('IE 01', 'TZ protect fault — overcurrent protection', 'internal', ['TZ Protect Fault']), R('IE 02', 'Grid lost — no grid connection', 'no_grid', ['Grid Lost Fault']), R('IE 03', 'Grid voltage out of range', 'grid_voltage', ['Grid Volt Fault']),
      R('IE 04', 'Grid frequency out of range', 'grid_freq', ['Grid Freq Fault']), R('IE 05', 'PV voltage above the allowed input range', 'pv_over_voltage', ['PV Volt Fault']), R('IE 07', 'Battery voltage out of range', 'battery', ['Bat Volt Fault']),
      R('IE 13', 'Isolation (earth) fault', 'isolation', ['Isolation Fault']), R('IE 15', 'Battery connected in the wrong direction', 'battery', ['Bat Con Dir Fault']), R('IE 16', 'EPS (backup) overload', 'overload', ['EPS Overload Fault']), R('IE 17', 'Overload in on-grid mode', 'overload', ['Overload Fault'])] },
    { id: 'fronius', name: 'Fronius', codes: [
      U('102', 'AC voltage too high', 'grid_voltage'), U('103', 'AC voltage too low', 'grid_voltage'), U('105', 'AC frequency too high', 'grid_freq'), U('106', 'AC frequency too low', 'grid_freq'),
      U('107', 'AC grid not available / outside limits', 'no_grid'), U('108', 'Stand-alone (islanding) operation detected', 'no_grid'), U('112', 'RCMU (residual current) error', 'leakage'),
      U('301', 'AC overcurrent', 'internal'), U('302', 'DC overcurrent / current peak on PV side', 'pv_fault'), U('303', 'Power stage over-temperature', 'over_temp'), U('304', 'Internal temperature too high', 'over_temp'),
      U('305', 'No power fed in despite closed relay', 'relay'), U('306', 'Low PV output', 'pv_low'), U('307', 'Low PV voltage', 'pv_low'), U('308', 'Intermediate-circuit voltage too high', 'pv_over_voltage'),
      U('309', 'DC input (MPPT 1) too high', 'pv_over_voltage'), U('311', 'DC string polarity reversed', 'pv_fault'), U('313', 'DC input (MPPT 2) too high', 'pv_over_voltage'),
      U('326', 'Fan 1 error', 'fan'), U('327', 'Fan 2 error', 'fan'), U('401', 'No communication with power stage set', 'comm'), U('408', 'DC component fed into grid', 'dc_injection'),
      U('447', 'Insulation fault', 'isolation'), U('475', 'Solar panel ground insulation fault', 'isolation'), U('502', 'Insulation error on solar panels', 'isolation'), U('509', 'No energy fed in for 24 hours', 'no_grid'),
      U('517', 'Power derating due to high temperature', 'over_temp'), U('566', 'Arc detector switched off', 'arc'), U('567', 'Grid-voltage dependent power reduction active', 'info')] },
    { id: 'abb', name: 'ABB / Fimer / Power-One', codes: [
      U('E018', 'Leakage current fault', 'leakage'), U('E021', 'Internal error', 'internal'), U('E025', 'Riso low — insulation fault on the solar array', 'isolation'), U('E031', 'Wrong voltage measurement', 'internal'),
      U('E034', 'Internal fatal error', 'internal'), U('W003', 'Grid voltage error (often a grid issue)', 'grid_voltage'), U('W010', 'Fan fault', 'fan')] },
    { id: 'sma', name: 'SMA', codes: [
      U('3501', 'Insulation resistance fault', 'isolation'), U('1302', 'Grid fault', 'grid_voltage'), U('101', 'Grid incident — grid voltage out of limits', 'grid_voltage')] },
    { id: 'vfd', name: 'Solar Pump VFD / Drive (Delta, ABB, Danfoss, Shakti, Lubi, Kirloskar…)', short: true, codes: [
      U('OC', 'Over-current (motor drew too much current)', 'vfd_oc', ['Overcurrent', 'Over current', 'OCA', 'OCD', 'OCN', 'OC-A', 'OC-D', 'OC-N', 'Over-current']),
      U('OV', 'DC-bus over-voltage', 'vfd_ov', ['Overvoltage', 'Over voltage', 'OVA', 'OVD', 'OVN', 'Over-voltage']),
      U('UV', 'DC-bus under-voltage / low voltage', 'vfd_uv', ['Undervoltage', 'Under voltage', 'LV', 'LVA', 'LVD', 'LVN', 'Low voltage', 'Under-voltage']),
      U('GF', 'Ground (earth) fault', 'vfd_gf', ['GND', 'GFF', 'Ground fault', 'Earth fault']),
      U('OH', 'Drive over-temperature', 'vfd_oh', ['OT', 'THM', 'OH1', 'Overheat', 'Over heat', 'Over temperature', 'Over-temperature']),
      U('PL', 'Phase loss / imbalance', 'vfd_phase', ['PH', 'PHL', 'IPF', 'Phase loss', 'Phase failure']),
      U('CE', 'Communication fault', 'comm', ['COM', 'NET', 'Comm error']),
      U('Dry Run', 'Dry run / under-load (no water)', 'vfd_dry', ['Dry-run', 'Underload', 'Under load', 'No water', 'Low water', 'DRY'])] },
    { id: 'polycab', name: 'Polycab', codes: [] }, { id: 'luminous', name: 'Luminous', codes: [
      U('E-01', 'Low battery (Zelio 1100 series)', 'battery', ['E01', 'Low Batt']), U('E-02', 'Overload (above ~110% of rating)', 'overload', ['E02', 'Overload']), U('E-03', 'Short circuit at output', 'internal', ['E03', 'Short-cir']),
      U('E-04', 'Over-charge — charger voltage too high', 'battery', ['E04', 'Over-chg']), U('E-05', 'High grid voltage', 'grid_voltage', ['E05', 'Hi Volt']), U('E-06', 'Heat-sink temperature too high', 'over_temp', ['E06', 'Heat Hi']),
      U('E-07', 'Main relay error', 'relay', ['E07', 'Relay Err']), U('E-08', 'Charger fuse blown', 'internal', ['E08', 'Chg Fuse']), U('E-09', 'Grid frequency error', 'grid_freq', ['E09', 'Freq Err']), U('E-10', 'Display / control communication failure', 'comm', ['E10', 'Com Fail'])] }, { id: 'havells', name: 'Havells', codes: [] },
    { id: 'utl', name: 'UTL', codes: [] }, { id: 'microtek', name: 'Microtek', codes: [] }, { id: 'waaree', name: 'Waaree', codes: [] }, { id: 'tata', name: 'Tata Power Solar', codes: [] },
    { id: 'other', name: '', codes: [] }
  ];
  // ---- Round 20: extra codes (researched Oct 2026) — Huawei/SMA/Victron = manufacturer manuals (R), baaki third-party lists (U = 'confirm with manual') ----
  var EXTRA = [{"id": "huawei", "name": "Huawei", "rows": [["103", "High DC Input Voltage — DC input voltage above inverter maximum — too many modules in series", "pv_over_voltage", [], 0], ["106", "Abnormal String 1 — String 1 shaded for long time or modules degraded/damaged", "pv_fault", [], 0], ["107", "Abnormal String 2 — String 2 shaded for long time or modules degraded/damaged", "pv_fault", [], 0], ["108", "Abnormal String 3 — String 3 shaded for long time or modules degraded/damaged", "pv_fault", [], 0], ["109", "Abnormal String 4 — String 4 shaded for long time or modules degraded/damaged", "pv_fault", [], 0], ["110", "Abnormal String 5 — String 5 shaded for long time or modules degraded/damaged", "pv_fault", [], 0], ["111", "Abnormal String 6 — String 6 shaded for long time or modules degraded/damaged", "pv_fault", [], 0], ["120", "String 1 Reversed — String 1 polarity reversed or too few modules in series", "pv_fault", [], 0], ["121", "String 2 Reversed — String 2 polarity reversed or too few modules in series", "pv_fault", [], 0], ["122", "String 3 Reversed — String 3 polarity reversed or too few modules in series", "pv_fault", [], 0], ["123", "String 4 Reversed — String 4 polarity reversed or too few modules in series", "pv_fault", [], 0], ["124", "String 5 Reversed — String 5 polarity reversed or too few modules in series", "pv_fault", [], 0], ["125", "String 6 Reversed — String 6 polarity reversed or too few modules in series", "pv_fault", [], 0], ["200", "Abnormal DC Circuit — Input suddenly disconnected/shaded, grid phase imbalance, voltage swings or internal fault", "internal", [], 0], ["202", "Abnormal Invert Circuit — Grid voltage dip/short circuit, excess output or DC current in grid", "internal", [], 0], ["322", "Abnormal SPI Communication — Unrecoverable internal circuit fault", "internal", [], 0], ["410", "Abnormal Auxiliary Power — Abnormal voltage on control board (power chip/detection circuit)", "internal", [], 0], ["504", "Software Version Unmatch — Wrong software version after an upgrade", "internal", [], 0], ["505", "Upgrade Failed — Firmware upgrade did not complete", "internal", [], 0], ["61440", "Flash Fault — Flash memory insufficient or bad sector", "internal", [], 0]]}, {"id": "sma", "name": "SMA", "rows": [["102", "Grid overvoltage fast — Grid voltage/impedance too high; inverter disconnected", "grid_voltage", [], 0], ["202", "Grid undervoltage fast — Grid disconnected, AC cable damaged or grid voltage too low", "grid_voltage", [], 0], ["301", "Voltage increase protection — Grid voltage/impedance too high; inverter disconnects to protect power quality", "grid_voltage", [], 0], ["401", "Island grid detected — Inverter no longer grid-parallel and stopped feed-in for safety", "no_grid", ["Island grid"], 0], ["501", "Grid frequency disturbance — Grid frequency outside permitted range; inverter disconnected", "grid_freq", [], 0], ["1001", "L/N swapped — Conductors L and N swapped or PE not connected (installation fault)", "internal", [], 0], ["3401", "DC overvoltage input A — DC input voltage too high; can damage inverter", "pv_over_voltage", [], 0], ["3902", "Generator voltage too low (waiting for DC start) — PV voltage too low — low sunlight, dirt/snow on modules", "pv_low", [], 0], ["3903", "Generator voltage too high (waiting for DC start) — PV voltage too high; inverter waits for start conditions", "pv_over_voltage", [], 0], ["6002", "Device interference (self-diagnosis) — Internal self-diagnosis fault — cause needs SMA service", "internal", [], 0], ["6003", "Device interference (self-diagnosis) — Internal self-diagnosis fault — cause needs SMA service", "internal", [], 0], ["6004", "Device interference (self-diagnosis) — Internal self-diagnosis fault — cause needs SMA service", "internal", [], 0], ["6005", "Device interference (self-diagnosis) — Internal self-diagnosis fault — cause needs SMA service", "internal", [], 0], ["6006", "Device interference (self-diagnosis) — Internal self-diagnosis fault — cause needs SMA service", "internal", [], 0], ["6305", "Device interference (self-diagnosis) — Internal self-diagnosis fault — cause needs SMA service", "internal", [], 0], ["6415", "Device interference (self-diagnosis) — Internal self-diagnosis fault — cause needs SMA service", "internal", [], 0], ["6402", "Overtemperature (self-diagnosis) — Internal over-temperature — needs SMA service to confirm cause", "over_temp", [], 0], ["6406", "DC overcurrent input A — Module input current too high; feed-in interrupted, often with grid voltage jumps", "pv_fault", [], 0], ["6450", "Energy transfer not possible — Cannot feed in: high grid voltage, faulty/dirty/shaded module or bad weather", "pv_low", [], 0], ["7001", "Internal temperature sensor fault — Temperature sensor defective; feed-in interrupted", "internal", [], 0], ["7702", "Device interference (relay error) — A relay fault occurred", "relay", [], 0], ["8101", "Communication disturbed — Internal communication error; feed-in continues", "comm", ["8102"], 0], ["9014", "Invalid device combination — Multigate and inverters cannot work together in this combination; firmware update may be needed", "comm", [], 0], ["10265", "PLC communication impaired — Powerline communication impaired — may relate to AC cables routed together", "comm", [], 0]]}, {"id": "victron", "name": "Victron Energy", "rows": [["2", "Battery voltage too high — Battery voltage above allowed", "battery", [], 0], ["11", "Battery high ripple voltage — High ripple on battery voltage", "battery", [], 0], ["17", "Controller overheated — Overheated despite reduced output current", "over_temp", [], 0], ["27", "Charger short circuit — Short circuit on charger output", "internal", [], 0], ["29", "Overcharge protection — Overcharge protection triggered", "battery", [], 0], ["33", "PV overvoltage — PV voltage too high", "pv_over_voltage", [], 0], ["34", "PV overcurrent — PV current too high", "pv_fault", [], 0], ["35", "PV over power — PV power above limit", "pv_fault", [], 0], ["41", "Inverter shutdown: panel isolation too low — Panel isolation resistance too low", "isolation", [], 0], ["42", "Inverter shutdown: ground current above 30 mA — Earth leakage current above 30 mA", "leakage", [], 0], ["43", "Inverter shutdown: ground fault — Ground fault detected", "isolation", [], 0], ["50", "Inverter overload — Load above inverter rating", "overload", [], 0], ["51", "Inverter temperature too high — Inverter overheated", "over_temp", [], 0], ["52", "Inverter peak current — Peak current limit hit", "overload", [], 0], ["53", "Inverter output voltage low — Output voltage low", "overload", ["54"], 0], ["55", "Inverter self-test failed — Self-test did not pass", "internal", ["56", "58"], 0], ["67", "BMS connection lost — Battery management communication lost", "battery", [], 0], ["116", "Calibration data lost — Calibration data missing", "internal", [], 0], ["117", "Incompatible firmware — Incomplete firmware update", "internal", [], 0], ["200", "Internal DC voltage error — DC-DC converter fault", "internal", [], 0], ["202", "Internal GFCI sensor error — Residual-current sensor fault", "leakage", [], 0]]}, {"id": "solax", "name": "SolaX", "rows": [["SPI Fault", "SPI bus failure — Internal SPI communication failure", "internal", [], 1], ["SCI Fault", "SCI bus failure — Internal SCI communication failure", "internal", [], 1], ["CAN1 Fault", "CAN bus failure — CAN communication failure", "comm", [], 1], ["PV Config Fault", "PV connection setting error — PV connection settings are faulty", "pv_fault", [], 1], ["Inv EEPROM Fault", "Inverter memory fault — Inverter EEPROM fault", "internal", [], 1], ["Relay Fault", "Relay failure — Internal relay fault", "relay", [], 1], ["Sample Fault", "Detection circuit fault — Sensing / detection circuit fault", "internal", [], 1], ["RCD Fault", "Residual current device fault — RCD fault", "leakage", [], 1], ["Fan1 Fault", "Fan 1 failure — Fan 1 device fault", "fan", [], 1], ["Fan2 Fault", "Fan 2 failure — Fan 2 device fault", "fan", [], 1], ["AC HCT Fault", "AC current sensor fault", "internal", [], 1], ["EPS OCP Fault", "EPS overcurrent — Current exceeds limit in EPS (backup) mode", "overload", [], 1], ["DCI Device Fault", "DCI device fault — DC injection device fault", "dc_injection", [], 1], ["EPS Relay Fault", "EPS relay failure — EPS relay fault", "relay", [], 1], ["PLL Lost Fault", "Grid sync lost — Poor grid quality prevents synchronisation", "grid_voltage", [], 1], ["Bus Volt Fault", "DC bus voltage out of range — Bus voltage outside normal range", "internal", [], 1], ["AC5M Volt Fault", "5-minute grid voltage fault — Grid voltage out of range for 5 minutes", "grid_voltage", [], 1], ["AC10M Volt Fault", "10-minute grid voltage fault — Grid voltage out of range for 10 minutes", "grid_voltage", [], 1], ["Inv OCP Fault", "Inverter overcurrent — Inverter overcurrent protection", "internal", [], 1], ["Temp Over Fault", "Over-temperature — Temperature above limit", "over_temp", [], 1], ["Fan1 Speed Fault", "Fan 1 speed fault — Fan speed outside normal range", "fan", [], 1], ["C1 Can Fault", "Battery CAN communication fault", "battery", [], 1], ["C1 Bat OVP", "Battery overvoltage — Battery voltage above limit", "battery", [], 1], ["CT Fault", "CT or meter fault — CT / meter poorly connected", "comm", [], 1], ["SW OCP Fault", "Software overcurrent — Overcurrent detected by software", "internal", [], 1], ["RTC Fault", "Real-time clock fault", "internal", [], 1]]}, {"id": "growatt", "name": "Growatt", "rows": [["Fault 01", "Off-grid SPF: fan not working", "fan", [], 1], ["Fault 02", "Off-grid SPF: over temperature", "over_temp", [], 1], ["Fault 03", "Off-grid SPF: battery voltage too high", "battery", [], 1], ["Fault 04", "Off-grid SPF: battery voltage too low", "battery", [], 1], ["Fault 05", "Off-grid SPF: output short circuited", "internal", [], 1], ["Fault 06", "Off-grid SPF: output voltage abnormal (too high)", "overload", [], 1], ["Fault 07", "Off-grid SPF: overload time-out", "overload", [], 1], ["Fault 20", "Off-grid SPF: BMS communication loss", "battery", [], 1], ["Fault 51", "Off-grid SPF: over current or surge", "overload", [], 1], ["Fault 58", "Off-grid SPF: output abnormal (below 180 V or above 290 V AC)", "overload", [], 1], ["Warning 01", "Off-grid SPF: MPPT PCB fan abnormal", "fan", [], 1], ["Warning 03", "Off-grid SPF: battery voltage high", "battery", [], 1], ["Warning 04", "Off-grid SPF: battery low voltage / SOC low", "battery", [], 1], ["Warning 07", "Off-grid SPF: overload in inverter mode", "overload", [], 1], ["Warning 12", "Off-grid SPF: solar controller over temperature", "over_temp", [], 1], ["Warning 51", "Off-grid SPF: solar charger over current", "pv_fault", [], 1], ["Warning 54", "Off-grid SPF: PV input over voltage", "pv_over_voltage", [], 1], ["Warning 58", "Off-grid SPF: AC output low voltage", "overload", [], 1], ["Warning 61", "Off-grid SPF: battery voltage sampling error", "battery", [], 1]]}, {"id": "sungrow", "name": "Sungrow", "rows": [["088", "AC or PV input fault — AC / PV input issue (grouped by source)", "pv_fault", [], 1], ["320", "Communication or sensor error — Internal communication problem or sensor malfunction", "internal", [], 1], ["503", "Communication or sensor error — Internal communication problem or sensor malfunction", "internal", [], 1], ["504", "Communication or sensor error — Internal communication problem or sensor malfunction", "internal", [], 1], ["505", "Communication or sensor error — Internal communication problem or sensor malfunction", "internal", [], 1], ["506", "Communication or sensor error — Internal communication problem or sensor malfunction", "internal", [], 1]]}, {"id": "microtek", "name": "Microtek", "rows": [["E01", "Battery disconnected or depleted", "battery", [], 1], ["E02", "Load exceeds rated capacity", "overload", [], 1], ["E03", "Battery charge is low", "battery", [], 1], ["E04", "Short circuit at output", "internal", [], 1], ["E05", "Mains fuse blown", "internal", [], 1], ["E06", "Internal fault in inverter circuitry", "internal", [], 1], ["E07", "Charging problem", "battery", [], 1], ["E08", "Input voltage too low or too high", "grid_voltage", [], 1], ["E09", "Temperature too high", "over_temp", [], 1], ["E10", "Fan malfunction", "fan", [], 1]]}, {"id": "goodwe", "name": "GoodWe", "rows": [["DC Bus High", "DC bus voltage too high", "internal", [], 1], ["Over Temperature", "Inverter temperature too high", "over_temp", [], 1], ["Relay Check Failure", "Relay self-check failed", "relay", [], 1], ["DCI High", "DC injection into grid too high", "dc_injection", [], 1], ["Fan Failure", "Fan failure", "fan", [], 1], ["EEPROM R/W Failure", "Memory read/write failure", "internal", [], 1], ["SPI Failure", "Internal SPI communication failure", "internal", [], 1]]}, {"id": "solis", "name": "Solis (Ginlong)", "rows": [["Backfeed_Iac", "Backfeed current abnormal", "internal", ["1014"], 1], ["IGFOL-F", "Grid current tracking fault", "internal", ["1019"], 1], ["PHASE-FAULT", "Phase fault", "grid_voltage", ["101A"], 1], ["BoostFal", "Boost circuit fault", "internal", [], 1], ["UNB-BUS", "DC bus unbalanced", "internal", ["1022"], 1], ["PvMidIso", "PV mid-point insulation fault", "isolation", [], 1], ["PVGndRun", "PV ground fault", "isolation", [], 1], ["Vbus-Sam", "DC bus sampling fault", "internal", ["102A"], 1], ["UN-TEM", "Temperature too low", "over_temp", ["103A"], 1], ["IG-AD", "Grid current sampling fault", "internal", ["1047"], 1], ["L&PE FAULT", "Live/Earth wiring fault", "leakage", ["F017"], 1], ["DSP-SelfCheck", "DSP self-check fault", "internal", ["1058"], 1], ["Vg-Sample", "Grid voltage sampling fault", "internal", ["1059"], 1], ["DcSpdFail", "DC surge protector failed", "internal", [], 1], ["Fan_H Alarm", "Fan alarm", "fan", [], 1], ["FuseFail", "Fuse failed", "internal", [], 1], ["Surge Alarm", "Surge protector alarm", "internal", [], 1], ["VgSpdFail", "AC surge protector failed", "internal", [], 1], ["OV-DCA-I", "DC input A overcurrent", "pv_fault", ["1025"], 1], ["OV-DCB-I", "DC input B overcurrent", "pv_fault", ["1026"], 1], ["OV-Vbatt-H", "Battery / bus overvoltage (hardware)", "battery", ["1051"], 1], ["OV-ILLC", "LLC overcurrent", "internal", ["1052"], 1], ["OV-Vbackup", "Backup output overvoltage", "overload", ["1056"], 1], ["DSP_Comm_FAIL", "DSP communication failure", "comm", ["2014"], 1], ["BatName-FAIL", "Battery name / type mismatch", "battery", ["2016"], 1], ["Alarm2-BMS", "Battery BMS alarm 2", "battery", ["2017"], 1], ["DRM_LINK_FAIL", "DRM link failure", "comm", ["2018"], 1]]}];
  (function () {
    function nk(s) { return String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, ''); }
    EXTRA.forEach(function (e) {
      var b = BRANDS.filter(function (x) { return x.id === e.id; })[0];
      if (!b) { b = { id: e.id, name: e.name, codes: [] }; var oi = BRANDS.map(function (x) { return x.id; }).indexOf('other'); BRANDS.splice(oi < 0 ? BRANDS.length : oi, 0, b); }
      var have = {}; b.codes.forEach(function (r) { have[nk(r.code)] = 1; });
      e.rows.forEach(function (r) { if (have[nk(r[0])]) return; have[nk(r[0])] = 1; b.codes.push(R(r[0], r[1], r[2], r[3], !!r[4])); });
    });
  })();
  // Brand se alag — display par aane wale aam shabd (har brand par kaam karte hain)
  var KEYS = [
    ['no ac connection', 'no_grid'], ['no utility', 'no_grid'], ['utility loss', 'no_grid'], ['grid loss', 'no_grid'], ['grid lost', 'no_grid'], ['no grid', 'no_grid'], ['nogrid', 'no_grid'], ['mains lost', 'no_grid'], ['grid fail', 'no_grid'], ['grid off', 'no_grid'], ['islanding', 'no_grid'],
    ['ac v outrange', 'grid_voltage'], ['vac failure', 'grid_voltage'], ['grid over voltage', 'grid_voltage'], ['grid overvoltage', 'grid_voltage'], ['grid under voltage', 'grid_voltage'], ['grid undervoltage', 'grid_voltage'], ['ov-g-v', 'grid_voltage'], ['un-g-v', 'grid_voltage'], ['grid volt', 'grid_voltage'], ['ac volt', 'grid_voltage'], ['grid-intf', 'grid_voltage'],
    ['ac f outrange', 'grid_freq'], ['fac failure', 'grid_freq'], ['grid freq', 'grid_freq'], ['frequency', 'grid_freq'], ['ov-g-f', 'grid_freq'], ['un-g-f', 'grid_freq'],
    ['pv isolation', 'isolation'], ['isolation', 'isolation'], ['iso failure', 'isolation'], ['iso-pro', 'isolation'], ['insulation', 'isolation'], ['riso', 'isolation'], ['earth fault', 'isolation'], ['ground fault', 'isolation'],
    ['residual', 'leakage'], ['gfci', 'leakage'], ['leakage', 'leakage'], ['ileak', 'leakage'], ['ground i', 'leakage'], ['rcd', 'leakage'],
    ['over temp', 'over_temp'], ['overtemp', 'over_temp'], ['ov-tem', 'over_temp'], ['high temp', 'over_temp'], ['temperature', 'over_temp'],
    ['pv voltage high', 'pv_over_voltage'], ['pv over voltage', 'pv_over_voltage'], ['pv overvoltage', 'pv_over_voltage'], ['ov-dc', 'pv_over_voltage'], ['dc over voltage', 'pv_over_voltage'],
    ['reverse', 'pv_fault'], ['reve-dc', 'pv_fault'], ['string', 'pv_fault'],
    ['pv low', 'pv_low'], ['pv voltage low', 'pv_low'], ['waiting', 'pv_low'], ['no pv', 'pv_low'],
    ['dci', 'dc_injection'], ['dc injection', 'dc_injection'], ['dcinj', 'dc_injection'],
    ['fan', 'fan'], ['relay', 'relay'],
    ['wifi', 'comm'], ['comm', 'comm'], ['communication', 'comm'], ['meter', 'comm'], ['offline', 'comm'], ['rs485', 'comm'],
    ['arc', 'arc'], ['afci', 'arc'],
    ['battery', 'battery'], ['batt', 'battery'], ['bms', 'battery'], ['bat low', 'battery'], ['soc', 'battery'],
    ['overload', 'overload'], ['over load', 'overload'], ['over-load', 'overload'], ['eps', 'overload'],
    ['dry run', 'vfd_dry'], ['dry-run', 'vfd_dry'], ['underload', 'vfd_dry'], ['no water', 'vfd_dry'], ['phase loss', 'vfd_phase'], ['phase fail', 'vfd_phase'], ['overcurrent', 'vfd_oc'], ['over current', 'vfd_oc'], ['motor overload', 'vfd_oc'],
    ['normal', 'info'], ['generating', 'info'], ['standby', 'pv_low'],
    ['bus volt', 'internal'], ['eeprom', 'internal'], ['self test', 'internal'], ['auto test', 'internal'], ['dsp', 'internal'], ['hardware', 'internal'], ['system fault', 'internal'], ['inverter fault', 'internal']
  ];

  /* ---------------- matching ---------------- */
  function norm(s) { return String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, ''); }
  function codeKey(s) { var n = norm(s).replace(/^(error|err|fault|alarm|code|warning|e)(?=\d)/, ''); return /^\d+$/.test(n) ? String(+n) : n; }
  function tokens(text) {
    var out = [], raw = String(text || '').toLowerCase();
    raw.split(/[\s,;|/]+/).forEach(function (w) { if (/\d[:.]\d/.test(w)) return; w = w.replace(/^[^a-z0-9]+|[^a-z0-9]+$/g, ''); var k = codeKey(w); if (k) out.push(k); });
    raw.replace(/\b([a-z])\s+(\d{1,4})\b/g, function (x, a, n) { out.push(a === 'e' ? String(+n) : a + n); });
    var re = /(?:error|err|fault|alarm|code|warning)\s*(?:code)?\s*[:#-]?\s*([a-z]{0,2}-?\d{1,5})/g, m;
    while ((m = re.exec(raw))) out.push(codeKey(m[1]));
    return out;
  }
  function find(brandId, text) {
    var nt = norm(text), tk = tokens(text), hits = [], seen = {};
    function add(b, r, how) { var k = b.id + '|' + r.code; if (seen[k]) return; seen[k] = 1; hits.push({ brand: b, row: r, how: how }); }
    BRANDS.forEach(function (b) {
      b.codes.forEach(function (r) {
        var names = [r.code].concat(r.alias), ok = false, how = 'code';
        names.forEach(function (n) {
          var nk = codeKey(n), nn = norm(n);
          if (/^\d+$/.test(nk) || /^[a-z]\d+$/.test(nk)) { if (tk.indexOf(nk) >= 0) ok = true; }
          else if (b.short && brandId === b.id && /^[a-z]{2,4}\d?$/.test(nk)) { if (tk.indexOf(nk) >= 0) ok = true; }
          else if (nn.length >= 4 && nt.indexOf(nn) >= 0) { ok = true; how = 'text'; }
        });
        if (ok) add(b, r, how);
      });
    });
    var mine = hits.filter(function (h) { return h.brand.id === brandId; });
    var textHits = hits.filter(function (h) { return h.how === 'text'; });
    var res = { exact: mine, others: [], cats: [], ambiguous: false };
    if (!mine.length) {
      if (textHits.length) res.others = textHits;
      else if (hits.length) { res.others = hits; res.ambiguous = brandId === 'other' || !brandId || BRANDS.some(function (b) { return b.id === brandId && !b.codes.length; }); }
    }
    if (!res.exact.length && !res.others.length) {
      var low = ' ' + String(text || '').toLowerCase().replace(/[^a-z0-9-]+/g, ' ') + ' ', cs = {};
      KEYS.forEach(function (k) { var w = k[0]; var pat = w.length <= 4 ? new RegExp('(^|[^a-z])' + w.replace(/-/g, '\\-') + '([^a-z]|$)') : null; if ((pat ? pat.test(low) : low.indexOf(w) >= 0 || nt.indexOf(norm(w)) >= 0) && !cs[k[1]]) { cs[k[1]] = 1; res.cats.push(k[1]); } });
    }
    return res;
  }

  /* ---------------- photo helpers (no upload, no storage) ---------------- */
  function loadScript(src) { return new Promise(function (ok, no) { if (window.Tesseract) return ok(); var s = document.createElement('script'); s.src = src; s.async = true; s.onload = function () { ok(); }; s.onerror = function () { s.remove(); no(new Error('load')); }; document.head.appendChild(s); }); }
  function fileToCanvas(file, max) {
    return new Promise(function (ok, no) {
      var url = URL.createObjectURL(file), img = new Image();
      img.onload = function () {
        var w = img.naturalWidth, h = img.naturalHeight, k = Math.min(1, (max || 1600) / Math.max(w, h)), c = document.createElement('canvas');
        c.width = Math.max(1, Math.round(w * k)); c.height = Math.max(1, Math.round(h * k)); c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
        URL.revokeObjectURL(url); img.src = ''; ok(c);
      };
      img.onerror = function () { URL.revokeObjectURL(url); no(new Error('img')); };
      img.src = url;
    });
  }
  function wipe(c) { if (!c) return; try { var x = c.getContext('2d'); x.clearRect(0, 0, c.width, c.height); } catch (e) {} c.width = c.height = 0; }
  function prepForOcr(c) { // grayscale + contrast stretch (LCD text padhne me madad)
    var x = c.getContext('2d'), d = x.getImageData(0, 0, c.width, c.height), p = d.data, lo = 255, hi = 0, i, g;
    for (i = 0; i < p.length; i += 4) { g = (p[i] * 0.299 + p[i + 1] * 0.587 + p[i + 2] * 0.114) | 0; p[i] = g; if (g < lo) lo = g; if (g > hi) hi = g; }
    var r = Math.max(1, hi - lo);
    for (i = 0; i < p.length; i += 4) { g = Math.round((p[i] - lo) * 255 / r); p[i] = p[i + 1] = p[i + 2] = g; }
    x.putImageData(d, 0, 0); return c;
  }
  var api = { ocr: null };
  function ocr(file) { // returns text ('' if not possible)
    var c = null;
    return fileToCanvas(file, 1600).then(function (cv) { c = prepForOcr(cv); return (api.ocr ? Promise.resolve() : loadScript(OCR_URL)); })
      .then(function () {
        if (api.ocr) return api.ocr(c);
        return window.Tesseract.createWorker('eng').then(function (w) { return w.recognize(c).then(function (r) { return w.terminate().then(function () { return (r && r.data && r.data.text) || ''; }); }, function (e) { w.terminate(); throw e; }); });
      })
      .then(function (txt) { wipe(c); return String(txt || '').replace(/[^\x20-\x7E\n]/g, ' ').replace(/[ \t]+/g, ' ').trim(); }, function () { wipe(c); return ''; });
  }
  function panelStats(file) {
    return fileToCanvas(file, 320).then(function (c) {
      var d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data, n = 0, sum = 0, sq = 0, sat = 0;
      for (var i = 0; i < d.length; i += 16) { var r = d[i], g = d[i + 1], b = d[i + 2], y = 0.299 * r + 0.587 * g + 0.114 * b, mx = Math.max(r, g, b), mn = Math.min(r, g, b); sum += y; sq += y * y; sat += mx ? (mx - mn) / mx : 0; n++; }
      wipe(c); var mean = sum / n, sd = Math.sqrt(Math.max(0, sq / n - mean * mean));
      return { mean: mean, sd: sd, sat: sat / n };
    });
  }

  /* ---------------- UI ---------------- */
  var CSS = '.spd::after{content:"Powered by Digidashland.in";position:sticky;bottom:42%;display:block;height:0;text-align:center;font-size:clamp(18px,5.5vw,40px);font-weight:800;color:rgba(11,46,31,.06);transform:rotate(-22deg);pointer-events:none;white-space:nowrap;z-index:3}.spd-links{display:flex;gap:8px;flex-wrap:wrap;margin:0 0 10px}.spd-links a{font-size:13px;font-weight:700;padding:6px 12px;border-radius:99px;border:1px solid #cfe0d2;color:#0b6e4f;text-decoration:none;background:#fff}' +
    '.spd-ov{position:fixed;inset:0;z-index:2147483000;background:rgba(6,24,16,.62);display:flex;align-items:flex-end;justify-content:center;font-family:inherit}' +
    '@media(min-width:720px){.spd-ov{align-items:center;padding:24px}}' +
    '.spd{background:#fff;color:#10241a;width:100%;max-width:560px;max-height:92vh;overflow:auto;border-radius:22px 22px 0 0;box-shadow:0 -10px 50px rgba(0,0,0,.35);-webkit-overflow-scrolling:touch}' +
    '@media(min-width:720px){.spd{border-radius:22px}}' +
    '.spd *{box-sizing:border-box}.spd-hd{position:sticky;top:0;z-index:2;background:linear-gradient(120deg,#0b2e1f,#1d5a3e);color:#fff;padding:18px 54px 16px 20px}' +
    '.spd-hd h2{margin:0;font-size:20px;font-weight:800;line-height:1.2;color:#fff}.spd-hd p{margin:4px 0 0;font-size:13.5px;opacity:.85}' +
    '.spd-x{position:absolute;right:12px;top:12px;width:36px;height:36px;border-radius:50%;border:0;background:rgba(255,255,255,.14);color:#fff;font-size:22px;line-height:1;cursor:pointer}' +
    '.spd-bd{padding:18px 20px 22px}.spd-opt{display:flex;gap:14px;align-items:center;width:100%;text-align:left;border:1.5px solid #dfe8e2;background:#f7faf8;border-radius:16px;padding:14px;margin-bottom:10px;cursor:pointer;font:inherit;color:inherit}' +
    '.spd-opt:hover,.spd-opt:focus-visible{border-color:#1e8e3e;background:#eef7f0;outline:none}.spd-opt .e{font-size:28px;width:48px;height:48px;border-radius:14px;background:#fff3d6;display:flex;align-items:center;justify-content:center;flex:none}' +
    '.spd-opt b{display:block;font-size:16px}.spd-opt small{display:block;color:#5b6b63;font-size:13px;margin-top:2px}' +
    '.spd label.l{display:block;font-weight:700;font-size:13.5px;margin:12px 0 6px}.spd select,.spd input[type=text]{width:100%;min-height:46px;border:1.5px solid #dfe8e2;border-radius:12px;padding:10px 12px;font:inherit;font-size:16px;background:#fff;color:#10241a}' +
    '.spd select:focus,.spd input[type=text]:focus{outline:none;border-color:#1e8e3e;box-shadow:0 0 0 3px rgba(30,142,62,.15)}' +
    '.spd-btn{display:inline-flex;align-items:center;justify-content:center;gap:8px;min-height:46px;padding:10px 18px;border-radius:999px;border:0;font:inherit;font-weight:800;font-size:15px;cursor:pointer;text-decoration:none}' +
    '.spd-btn.p{background:#1e8e3e;color:#fff}.spd-btn.s{background:#f4b740;color:#0b2e1f}.spd-btn.g{background:#1fae54;color:#fff}.spd-btn.o{background:#fff;color:#0b2e1f;border:1.5px solid #dfe8e2}.spd-btn.w{width:100%}' +
    '.spd-cam{display:flex;align-items:center;justify-content:center;gap:10px;width:100%;min-height:52px;border:2px dashed #9fcfac;border-radius:14px;background:#f2faf4;color:#14562b;font-weight:800;cursor:pointer;margin-top:10px;font-size:15px}' +
    '.spd-cam input{position:absolute;opacity:0;width:1px;height:1px;pointer-events:none}.spd-note{font-size:12.5px;color:#5b6b63;margin-top:8px}.spd-err{color:#b3261e;font-weight:700;font-size:13.5px;margin-top:8px}' +
    '.spd-busy{display:flex;align-items:center;gap:10px;margin-top:10px;font-weight:700;color:#14562b}.spd-busy i{width:18px;height:18px;border-radius:50%;border:3px solid #cfe7d5;border-top-color:#1e8e3e;animation:spdspin 1s linear infinite}@keyframes spdspin{to{transform:rotate(1turn)}}' +
    '.spd-res{border-radius:16px;border:1.5px solid #dfe8e2;padding:14px;margin-bottom:12px;background:#fff}.spd-res h3{margin:6px 0 4px;font-size:17px;color:#0b2e1f}.spd-res p{margin:0;color:#33463c;font-size:14.5px}' +
    '.spd-res ul{margin:8px 0 0;padding-left:20px;font-size:14px;color:#33463c}.spd-res li{margin:4px 0}.spd-res .h{font-size:12.5px;font-weight:800;text-transform:uppercase;letter-spacing:.06em;color:#5b6b63;margin-top:10px}' +
    '.spd-tag{display:inline-block;font-size:12px;font-weight:800;padding:3px 10px;border-radius:999px}.spd-tag.high{background:#fde8e6;color:#b3261e}.spd-tag.medium{background:#fff3d6;color:#8a5a00}.spd-tag.low{background:#e6f4ea;color:#14562b}' +
    '.spd-code{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:13px;background:#f1f5f2;border-radius:6px;padding:2px 6px}' +
    '.spd-warn{background:#fff7e6;border:1px solid #f0c36d;color:#6b4500;border-radius:12px;padding:10px 12px;font-size:13.5px;margin:10px 0}' +
    '.spd-cta{background:linear-gradient(120deg,#0b2e1f,#1d5a3e);color:#fff;border-radius:18px;padding:16px;margin-top:6px}.spd-cta b{display:block;font-size:17px}.spd-cta small{display:block;opacity:.85;margin:2px 0 12px}' +
    '.spd-cta .r{display:grid;grid-template-columns:1fr 1fr;gap:8px}.spd-chk{display:flex;gap:10px;align-items:flex-start;padding:10px 12px;border:1.5px solid #dfe8e2;border-radius:12px;margin-bottom:8px;cursor:pointer;font-size:14.5px}' +
    '.spd-chk input{width:20px;height:20px;accent-color:#1e8e3e;flex:none;margin-top:1px}.spd-chk:has(input:checked){border-color:#1e8e3e;background:#eef7f0}.spd-row{display:flex;gap:8px;flex-wrap:wrap;margin-top:12px}' +
    '.spd-beta{font-size:11px;font-weight:800;background:#e8eefc;color:#1d3f9a;border-radius:999px;padding:2px 8px;margin-left:6px;vertical-align:2px}';

  var PANEL = [
    { id: 'dust', e: '🌫️', en: 'Dust / dirt / bird droppings on panels', hi: 'पैनल पर धूल / गंदगी / पक्षियों की बीट', a_en: 'Clean panels with plain water and a soft mop, early morning or evening, only if safely reachable. Never use detergent or hard brushes, never stand on panels. Dust can cut generation by 10–25%.', a_hi: 'सिर्फ़ सादे पानी और नरम पोछे से सुबह या शाम सफ़ाई करें, तभी जब सुरक्षित पहुँच हो। डिटर्जेंट या सख़्त ब्रश न लगाएँ, पैनल पर खड़े न हों। धूल से 10–25% बिजली कम हो सकती है।', sev: 'low' },
    { id: 'shade', e: '🌳', en: 'Shadow on panels (tree, tank, wall, new building)', hi: 'पैनल पर छाया (पेड़, टंकी, दीवार, नई बिल्डिंग)', a_en: 'Even a small shadow can reduce the whole string. Trim branches if possible; for a fixed shadow, call us — we can re-arrange panels.', a_hi: 'छोटी-सी छाया भी पूरी स्ट्रिंग की बिजली घटा देती है। हो सके तो डालियाँ कटवाएँ; पक्की छाया हो तो कॉल करें — हम पैनल की जगह बदल सकते हैं।', sev: 'medium' },
    { id: 'crack', e: '💥', en: 'Cracked / broken glass on a panel', hi: 'पैनल का शीशा टूटा / दरार', a_en: 'Do not touch the panel — broken glass can carry voltage. Call us; panel damage is often covered by warranty or insurance.', a_hi: 'पैनल न छुएँ — टूटे शीशे में करंट हो सकता है। कॉल करें; अक्सर वारंटी या बीमा में कवर होता है।', sev: 'high' },
    { id: 'burn', e: '🔥', en: 'Brown / burnt spots or melted junction box', hi: 'भूरे / जले निशान या पिघला जंक्शन बॉक्स', a_en: 'This can be a hotspot — a fire risk. Keep away and call us immediately.', a_hi: 'ये हॉटस्पॉट हो सकता है — आग का ख़तरा। दूर रहें और तुरंत कॉल करें।', sev: 'high' },
    { id: 'wire', e: '🔌', en: 'Loose, hanging or chewed wires', hi: 'ढीले, लटके या कुतरे हुए तार', a_en: 'Do not touch. Rats / monkeys often damage cables. Call us for safe re-wiring with conduit.', a_hi: 'न छुएँ। चूहे / बंदर अक्सर तार काटते हैं। कंड्यूट के साथ सुरक्षित वायरिंग के लिए कॉल करें।', sev: 'high' },
    { id: 'struct', e: '🏗️', en: 'Structure loose / rust / water collecting', hi: 'स्ट्रक्चर ढीला / ज़ंग / पानी भरना', a_en: 'Tell us before the monsoon or strong winds — we tighten bolts and treat rust.', a_hi: 'बारिश या तेज़ हवा से पहले बताएँ — हम बोल्ट कसते हैं और ज़ंग का इलाज करते हैं।', sev: 'medium' },
    { id: 'low', e: '📉', en: 'Units lower than before (same season)', hi: 'पहले से कम यूनिट बन रहे (उसी मौसम में)', a_en: 'Compare units on a sunny day. If still 20% lower after cleaning, call us for a string-wise check.', a_hi: 'धूप वाले दिन यूनिट मिलाएँ। सफ़ाई के बाद भी 20% कम हों तो स्ट्रिंग-वार जाँच के लिए कॉल करें।', sev: 'medium' }
  ];
  var OTHER = [
    { id: 'off', e: '⚫', en: 'Inverter display is off / blank', hi: 'इन्वर्टर डिस्प्ले बंद / खाली', a_en: 'At night the display turns off — normal. In daytime: check that the AC MCB and DC isolator are ON (do not open the box). Still off in sun → call us.', a_hi: 'रात में डिस्प्ले बंद रहता है — सामान्य है। दिन में: AC MCB और DC आइसोलेटर ON हैं या नहीं देखें (बॉक्स न खोलें)। धूप में भी बंद → कॉल करें।', sev: 'medium' },
    { id: 'trip', e: '⚡', en: 'MCB / RCCB keeps tripping', hi: 'MCB / RCCB बार-बार ट्रिप', a_en: 'Do not force it ON again and again. Note when it trips (rain, afternoon). Call us — it may be leakage or overload.', a_hi: 'बार-बार ज़बरदस्ती ON न करें। नोट करें कब ट्रिप होता है (बारिश, दोपहर)। कॉल करें — लीकेज या ओवरलोड हो सकता है।', sev: 'high' },
    { id: 'bill', e: '🧾', en: 'Electricity bill has not reduced', hi: 'बिजली का बिल कम नहीं हुआ', a_en: 'Check that the net meter is installed and export (kWh E) reading is increasing. Bills sometimes lag 1–2 months. Send us your last 2 bills on WhatsApp — we check for free.', a_hi: 'देखें कि नेट मीटर लगा है और एक्सपोर्ट (kWh E) रीडिंग बढ़ रही है। बिल में 1–2 महीने की देरी हो सकती है। पिछले 2 बिल WhatsApp करें — हम मुफ़्त जाँचते हैं।', sev: 'medium' },
    { id: 'net', e: '📟', en: 'Net meter not installed / showing error', hi: 'नेट मीटर नहीं लगा / एरर दिखा रहा', a_en: 'Net metering is done by the electricity department after the application. Call us with your application number — we follow up.', a_hi: 'नेट मीटरिंग आवेदन के बाद बिजली विभाग लगाता है। आवेदन नंबर के साथ कॉल करें — हम फ़ॉलो-अप करते हैं।', sev: 'low' },
    { id: 'bat', e: '🔋', en: 'Battery not charging / backup too short', hi: 'बैटरी चार्ज नहीं हो रही / बैकअप कम', a_en: 'Reduce heavy loads during power cuts. Check the battery switch is ON. If backup dropped suddenly, call us — battery health check.', a_hi: 'बिजली कटौती में भारी लोड कम करें। बैटरी स्विच ON देखें। बैकअप अचानक घटा हो तो कॉल करें — बैटरी हेल्थ जाँच।', sev: 'medium' },
    { id: 'app', e: '📱', en: 'Monitoring app shows no data', hi: 'मॉनिटरिंग ऐप में डेटा नहीं', a_en: 'Usually WiFi: check the router is ON and the password was not changed. Generation is often still normal. Call us to reconnect.', a_hi: 'अक्सर WiFi की वजह से: राउटर ON है और पासवर्ड बदला नहीं, देखें। बिजली शायद ठीक बन रही हो। दोबारा जोड़ने के लिए कॉल करें।', sev: 'low' },
    { id: 'noise', e: '🔊', en: 'Humming noise / burning smell', hi: 'तेज़ आवाज़ / जलने की गंध', a_en: 'A light hum in daytime is normal. Burning smell or smoke: switch OFF the main AC MCB from a safe distance, keep away and call us immediately.', a_hi: 'दिन में हल्की भनभनाहट सामान्य है। जलने की गंध या धुआँ: सुरक्षित दूरी से मेन AC MCB बंद करें, दूर रहें और तुरंत कॉल करें।', sev: 'high' }
  ];

  var ov = null, box = null, state = {}, lastFocus = null;
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return '&#' + c.charCodeAt(0) + ';'; }); }
  function tel() { return 'tel:+91' + PHONE; }
  function waUrl(extra) { return 'https://wa.me/91' + PHONE + '?text=' + encodeURIComponent(t('wa_msg') + (extra ? '\n' + extra : '')); }
  function cta(extra) {
    return '<div class="spd-cta"><b>📞 ' + esc(t('help')) + '</b><small>' + esc(t('help_s')) + ' • 0' + PHONE + '</small><div class="r">' +
      '<a class="spd-btn s" data-spd-call href="' + tel() + '">📞 ' + esc(t('call')) + '</a><a class="spd-btn g" data-spd-wa target="_blank" rel="noopener" href="' + esc(waUrl(extra)) + '">' + esc(t('wa')) + '</a></div></div>' +
      '<div class="spd-row"><button type="button" class="spd-btn o w" data-spd="home">↺ ' + esc(t('again')) + '</button></div>';
  }
  function sevTag(s) { return '<span class="spd-tag ' + s + '">' + esc(t('sev_' + s)) + '</span>'; }
  function catCard(id, label) {
    var c = C[id] || C.internal;
    return '<div class="spd-res">' + sevTag(c.sev) + (label ? ' <span class="spd-code">' + esc(label) + '</span>' : '') + '<h3>' + esc(pick({ title_en: c.title_en, title_hi: c.title_hi }, 'title')) + '</h3><p>' + esc(L() === 'hi' ? c.m_hi : c.m_en) + '</p>' +
      '<div class="h">' + esc(t('safe')) + '</div><ul>' + (L() === 'hi' ? c.s_hi : c.s_en).map(function (x) { return '<li>' + esc(x) + '</li>'; }).join('') + '</ul></div>';
  }
  function linksHtml() { var l = (window.SPGate && SPGate.cfg && SPGate.cfg.links) || {}; return (l.site || l.store) ? '<div class="spd-links">' + (l.site ? '<a href="' + esc(l.site) + '" target="_blank" rel="noopener">🌐 ' + esc(L() === 'hi' ? 'वेबसाइट' : 'Website') + '</a>' : '') + (l.store ? '<a href="' + esc(l.store) + '" target="_blank" rel="noopener">🛒 ' + esc(L() === 'hi' ? 'स्टोर' : 'Store') + '</a>' : '') + '</div>' : ''; }
  function frame(inner, back) {
    box.innerHTML = '<div class="spd-hd"><h2 id="spdT">🔎 ' + esc(t('title')) + '</h2><p>' + esc(t('sub')) + '</p><button type="button" class="spd-x" data-spd="close" aria-label="' + esc(t('close')) + '">×</button></div><div class="spd-bd">' +
      linksHtml() + (back ? '<button type="button" class="spd-btn o" data-spd="home" style="min-height:36px;padding:6px 14px;margin-bottom:10px">← ' + esc(t('back')) + '</button>' : '') + inner + '</div>';
  }
  function home() {
    state = { view: 'home' };
    frame('<button type="button" class="spd-opt" data-spd="inverter"><span class="e">📟</span><span><b>' + esc(t('t_inv')) + '</b><small>' + esc(t('t_inv_s')) + '</small></span></button>' +
      '<button type="button" class="spd-opt" data-spd="panel"><span class="e">☀️</span><span><b>' + esc(t('t_pan')) + '</b><small>' + esc(t('t_pan_s')) + '</small></span></button>' +
      '<button type="button" class="spd-opt" data-spd="other"><span class="e">🛠️</span><span><b>' + esc(t('t_oth')) + '</b><small>' + esc(t('t_oth_s')) + '</small></span></button>' +
      '<p class="spd-note">' + esc(t('privacy')) + '</p>' + cta().replace(/<div class="spd-row">[\s\S]*$/, ''));
  }
  function inverter(prev) {
    state = { view: 'inverter' }; prev = prev || {};
    var opts = BRANDS.map(function (b) { return '<option value="' + b.id + '"' + (prev.brand === b.id ? ' selected' : '') + '>' + esc(b.name || t('brand_other')) + '</option>'; }).join('');
    frame('<label class="l" for="spdBrand">' + esc(t('brand')) + '</label><select id="spdBrand">' + opts + '</select>' +
      '<label class="l" for="spdCode">' + esc(t('code')) + '</label><input type="text" id="spdCode" autocomplete="off" autocapitalize="characters" spellcheck="false" placeholder="' + esc(t('code_ph')) + '" value="' + esc(prev.code || '') + '">' +
      '<label class="spd-cam">📷 ' + esc(t('photo')) + '<input type="file" accept="image/*" capture="environment" id="spdFile"></label><div id="spdMsg"></div>' +
      '<p class="spd-note">' + esc(t('privacy')) + '</p><div class="spd-row"><button type="button" class="spd-btn p w" data-spd="find">🔎 ' + esc(t('check')) + '</button></div>', true);
    var f = box.querySelector('#spdFile');
    f.addEventListener('change', function () {
      var file = f.files && f.files[0]; f.value = ''; if (!file) return;
      var msg = box.querySelector('#spdMsg'); msg.innerHTML = '<div class="spd-busy"><i></i>' + esc(t('reading')) + '</div>';
      ocr(file).then(function (txt) {
        file = null; if (!box || state.view !== 'inverter') return;
        if (txt && /[a-z0-9]{2,}/i.test(txt)) { var inp = box.querySelector('#spdCode'); inp.value = txt.replace(/\s*\n\s*/g, ' ').slice(0, 160); msg.innerHTML = '<p class="spd-note">' + esc(t('read_ok')) + '</p>'; inp.focus(); }
        else msg.innerHTML = '<p class="spd-err">' + esc(t('read_fail')) + '</p>';
      });
    });
  }
  function result() {
    var brand = box.querySelector('#spdBrand').value, code = box.querySelector('#spdCode').value.trim(), msg = box.querySelector('#spdMsg');
    if (!code) { msg.innerHTML = '<p class="spd-err">' + esc(t('need_code')) + '</p>'; box.querySelector('#spdCode').focus(); return; }
    var r = find(brand, code), bname = (BRANDS.filter(function (b) { return b.id === brand; })[0] || {}).name || t('brand_other'), html = '';
    if (r.exact.length) html = r.exact.slice(0, 3).map(function (h) { return catCard(h.row.cat, h.brand.name + ' • ' + h.row.code + ' — ' + h.row.msg + (h.row.u ? ' (' + t('unver') + ')' : '')); }).join('');
    else if (r.others.length) {
      var seenC = {}, list = r.others.filter(function (h) { if (r.ambiguous) return true; if (seenC[h.row.cat]) return false; seenC[h.row.cat] = 1; return true; });
      html = (r.ambiguous ? '<div class="spd-warn">' + esc(t('pick_brand')) + '</div>' : '') + list.slice(0, 4).map(function (h) { return catCard(h.row.cat, (r.ambiguous ? h.brand.name + ' • ' : '') + h.row.code + ' — ' + h.row.msg + (h.row.u ? ' (' + t('unver') + ')' : '')); }).join('');
    }
    else if (r.cats.length) html = r.cats.slice(0, 2).map(function (c) { return catCard(c, code.slice(0, 40)); }).join('');
    else html = '<div class="spd-res"><span class="spd-tag medium">?</span><h3>' + esc(t('nomatch')) + '</h3><p>' + esc(t('nomatch_p')) + '</p></div>';
    state = { view: 'result', prev: { brand: brand, code: code } };
    if (window.SPGate) SPGate.log('detector', 'Inverter: ' + bname + ' | Error: ' + code.slice(0, 100));
    frame('<div class="h" style="font-weight:800;margin-bottom:8px">' + esc(t('result')) + ': <span class="spd-code">' + esc(bname) + ' — ' + esc(code.slice(0, 60)) + '</span></div>' + html +
      '<div class="spd-warn">⚠️ ' + esc(t('never')) + '</div>' + cta('Inverter: ' + bname + '\nError: ' + code.slice(0, 120)), true);
  }
  function checklist(list, kind) {
    state = { view: kind };
    var items = list.map(function (x) { return '<label class="spd-chk"><input type="checkbox" value="' + x.id + '"><span>' + x.e + ' ' + esc(L() === 'hi' ? x.hi : x.en) + '</span></label>'; }).join('');
    var cam = kind === 'panel' ? '<label class="spd-cam">📷 ' + esc(t('photo_p')) + ' <span class="spd-beta">' + esc(t('beta')) + '</span><input type="file" accept="image/*" capture="environment" id="spdFile"></label><div id="spdPh"></div><p class="spd-note">' + esc(t('beta_note')) + '</p><p class="spd-note">' + esc(t('privacy')) + '</p>' : '';
    frame(cam + '<label class="l">' + esc(t('see')) + '</label>' + items + '<div id="spdMsg"></div><div class="spd-row"><button type="button" class="spd-btn p w" data-spd="advice">🔎 ' + esc(t('check')) + '</button></div>', true);
    var f = box.querySelector('#spdFile');
    if (f) f.addEventListener('change', function () {
      var file = f.files && f.files[0]; f.value = ''; if (!file) return;
      var ph = box.querySelector('#spdPh'); ph.innerHTML = '<div class="spd-busy"><i></i>' + esc(t('reading')) + '</div>';
      panelStats(file).then(function (s) {
        file = null; if (!box) return; var m;
        if (s.mean < 60) m = t('photo_dark');
        else if (s.sd < 38 || (s.sat < 0.12 && s.mean > 150)) { m = t('photo_hazy'); var d = box.querySelector('input[value=dust]'); if (d) d.checked = true; }
        else m = t('photo_ok');
        state.photo = m; ph.innerHTML = '<div class="spd-warn" style="background:#eef7f0;border-color:#9fcfac;color:#14562b">📷 ' + esc(m) + '</div>';
      }, function () { if (box) box.querySelector('#spdPh').innerHTML = '<p class="spd-err">' + esc(t('read_fail').split('.')[0]) + '.</p>'; });
    });
  }
  function advice() {
    var kind = state.view, list = kind === 'panel' ? PANEL : OTHER, sel = [].slice.call(box.querySelectorAll('.spd-chk input:checked')).map(function (i) { return i.value; });
    if (!sel.length) { box.querySelector('#spdMsg').innerHTML = '<p class="spd-err">' + esc(t('pick_one')) + '</p>'; return; }
    var rows = list.filter(function (x) { return sel.indexOf(x.id) >= 0; }), photo = state.photo;
    var order = { high: 0, medium: 1, low: 2 }; rows.sort(function (a, b) { return order[a.sev] - order[b.sev]; });
    var html = (photo ? '<div class="spd-warn" style="background:#eef7f0;border-color:#9fcfac;color:#14562b">📷 ' + esc(photo) + '</div>' : '') + rows.map(function (x) { return '<div class="spd-res">' + sevTag(x.sev) + '<h3>' + x.e + ' ' + esc(L() === 'hi' ? x.hi : x.en) + '</h3><p>' + esc(L() === 'hi' ? x.a_hi : x.a_en) + '</p></div>'; }).join('');
    state = { view: 'result' };
    if (window.SPGate) SPGate.log('detector', 'Problems selected: ' + rows.map(function (x) { return x.en; }).join(', ').slice(0, 300));
    frame(html + '<div class="spd-warn">⚠️ ' + esc(t('never')) + '</div>' + cta('Problem: ' + rows.map(function (x) { return x.en; }).join(', ')), true);
  }
  function onClick(e) {
    var b = e.target.closest('[data-spd]'); if (!b) { if (e.target === ov) close(); return; }
    var a = b.getAttribute('data-spd');
    if (a === 'close') close(); else if (a === 'home') home(); else if (a === 'inverter') inverter(); else if (a === 'panel') checklist(PANEL, 'panel'); else if (a === 'other') checklist(OTHER, 'other');
    else if (a === 'find') result(); else if (a === 'advice') advice();
    var bd = box && box.querySelector('.spd-bd'); if (bd && a !== 'find' && a !== 'advice') box.scrollTop = 0; else if (box) box.scrollTop = 0;
  }
  function onKey(e) { if (!ov) return; if (e.key === 'Escape') return close(); if (e.key === 'Enter' && e.target && e.target.id === 'spdCode') { e.preventDefault(); result(); } if (e.key === 'Tab' && box) { var f = box.querySelectorAll('button,a[href],input,select'); if (!f.length) return; var first = f[0], last = f[f.length - 1]; if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); } else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); } } }
  var gated = false;
  function open(view) {
    if (!gated && window.SPGate && SPGate.active()) { SPGate.require('detector', function () { gated = true; try { open(view); } finally { gated = false; } }); return; }
    if (!document.getElementById('spdCss')) { var s = document.createElement('style'); s.id = 'spdCss'; s.textContent = CSS; document.head.appendChild(s); }
    lastFocus = document.activeElement;
    if (!ov) {
      ov = document.createElement('div'); ov.className = 'spd-ov'; ov.setAttribute('data-noi18n', '');
      box = document.createElement('div'); box.className = 'spd'; box.setAttribute('role', 'dialog'); box.setAttribute('aria-modal', 'true'); box.setAttribute('aria-labelledby', 'spdT');
      // Hinglish: texts are written in Hindi, so they are transliterated to Roman here (the overlay is data-noi18n)
      (function (bx) { function fix() { if (!(window.SPI18N && SPI18N.lang === 'hg' && SPI18N.xlit)) return; var w = document.createTreeWalker(bx, NodeFilter.SHOW_TEXT), n, list = []; while ((n = w.nextNode())) if (/[\u0900-\u097F]/.test(n.nodeValue)) list.push(n); list.forEach(function (x) { x.nodeValue = SPI18N.xlit(x.nodeValue); }); }
        if (window.MutationObserver) new MutationObserver(fix).observe(bx, { childList: true, subtree: true, characterData: true }); })(box);
      ov.appendChild(box); ov.addEventListener('click', onClick); document.addEventListener('keydown', onKey); document.body.appendChild(ov);
      document.documentElement.style.overflow = 'hidden';
    }
    if (view === 'inverter') inverter(); else if (view === 'panel') checklist(PANEL, 'panel'); else if (view === 'other') checklist(OTHER, 'other'); else home();
    var x = box.querySelector('.spd-x'); if (x) x.focus();
  }
  function close() {
    if (!ov) return; document.removeEventListener('keydown', onKey); ov.remove(); ov = box = null; state = {}; document.documentElement.style.overflow = '';
    if (lastFocus && lastFocus.focus) try { lastFocus.focus(); } catch (e) {}
  }
  document.addEventListener('click', function (e) { var b = e.target.closest && e.target.closest('[data-doctor]'); if (b) { e.preventDefault(); open(b.getAttribute('data-doctor') || ''); } });
  document.addEventListener('sp-lang', function () { if (!box) return; if (state.view === 'inverter') inverter({ brand: box.querySelector('#spdBrand').value, code: box.querySelector('#spdCode').value }); else if (state.view === 'home') home(); else if (state.view === 'panel' || state.view === 'other') checklist(state.view === 'panel' ? PANEL : OTHER, state.view); });
  window.SPDoctor = { open: open, close: close, find: find, brands: BRANDS, cats: C, _api: api, phone: PHONE };
})();
