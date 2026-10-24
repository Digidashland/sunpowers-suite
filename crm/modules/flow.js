/* Customer flow — ONE place that knows the 19 steps (names, icon, colour, which menu does the work, which details to note).
   Server rules (order, auto-steps, who may edit) live in MASTER-UPDATE.sql (Round 21); field keys below MUST match crm_wf_fields() there
   (tested by the JS<->SQL consistency check). Every other screen asks C.FLOW instead of keeping its own copy. */
(function () {
  'use strict';
  var C = window.CRM;

  var NAMES = { 1: 'Add Customer', 2: 'Conversation', 3: 'Quotation', 4: 'Site Visit', 5: 'Blueprint', 6: 'Confirmation', 7: 'Apply Process', 8: 'Hand Over Technician', 9: 'Start Installation', 10: 'Verification / Commissioning', 11: 'Net Metering', 12: 'Finish Work', 13: 'Subsidy Redeem', 14: 'Send Demo / Files', 15: 'Loan / Finance', 16: 'Suggest / Referral', 17: 'AMC / Maintenance', 18: 'Complaint Status', 19: 'Leads' };
  var IC = { 1: '👤', 2: '💬', 3: '📄', 4: '📍', 5: '📐', 6: '✅', 7: '📝', 8: '👷', 9: '🔧', 10: '⚡', 11: '🔌', 12: '🏁', 13: '💰', 14: '📤', 15: '🏦', 16: '🤝', 17: '🛠️', 18: '🎧', 19: '🎯' };
  var COL = { 1: '#2f6fdb', 2: '#0aa5a5', 3: '#7b4fd1', 4: '#e0742c', 5: '#d4a017', 6: '#1e8e3e', 7: '#c2417a', 8: '#3b7dd8', 9: '#e0742c', 10: '#12a5a5', 11: '#7b4fd1', 12: '#1e8e3e', 13: '#d4a017', 14: '#2f6fdb', 15: '#3b7dd8', 16: '#c2417a', 17: '#12a5a5', 18: '#d64545', 19: '#6b7280' };
  /* short plain-Hindi line: what happens in this step */
  var HELP = {
    19: 'Pehli enquiry — Leads me aati hai, path (kahan se aayi) apne aap darj. Mobile number zaroori.', 1: 'Customer list me jud gaya (kisi bhi platform se). Apne aap.', 2: 'Conversation: customer kya chahta hai + uski saari details yahin ek baar (baaki har form me apne aap aati hain). Pehla remark likhte hi apne aap.',
    14: 'Demo, datasheet, photo ya video bheji — Documents & Gallery se.', 3: 'Quotation banakar bheji. Apne aap (quotation se).', 4: 'Site par visit — Site Visit calendar se.', 5: 'Layout / blue print (zaroori nahi).',
    6: 'Customer ne quotation confirm ki. Apne aap.', 7: 'DISCOM / portal par application.', 15: 'Loan ya finance (Cash ho to "Lagu nahi").', 8: 'Technician ko kaam saupa.', 9: 'Installation shuru.',
    10: 'Verification, commissioning aur JCR.', 11: 'Net meter application aur meter.', 12: 'Kaam poora + bill. Apne aap (bill se).', 13: 'Subsidy claim (sirf Residential).', 16: 'Customer ne kisi ko refer kiya.',
    17: 'AMC / maintenance plan.', 18: 'Complaint / service ka status (warranty manufacturer ki).'
  };
  /* details a step can note — keys == crm_wf_fields() */
  var FIELDS = {
    4: [['roof_type', 'Chhat ka prakar'], ['roof_area', 'Chhat ka area (sq ft)'], ['shadow', 'Chhaya / shadow'], ['phase', 'Connection (1 / 3 phase)'], ['structure_ht', 'Structure ki height (ft)']],
    5: [['kw_final', 'Final plant size (kW)'], ['panels', 'Panels (sankhya)']],
    7: [['discom', 'DISCOM', 1], ['consumer_no', 'Consumer number', 1], ['sanctioned_load', 'Sanctioned load (kW)'], ['category', 'Category (LMV-1 etc.)'], ['portal_app_no', 'Portal application no.'], ['apply_date', 'Apply ki tareekh', 0, 'date']],
    8: [['tech_name', 'Technician ka naam', 1], ['tech_mobile', 'Technician ka mobile'], ['handover_date', 'Hand over ki tareekh', 0, 'date']],
    9: [['start_date', 'Installation shuru hui', 0, 'date'], ['team_size', 'Team (log)']],
    10: [['inverter_sn', 'Inverter serial no.'], ['panel_count', 'Panels (sankhya)'], ['jcr', 'Joint Commissioning Report'], ['comm_date', 'Commissioning ki tareekh', 0, 'date']],
    11: [['nm_app_no', 'Net metering application no.'], ['meter_no', 'Meter number'], ['meter_date', 'Meter lagne ki tareekh', 0, 'date'], ['discom_je', 'DISCOM JE / contact']],
    13: [['sub_app_no', 'Subsidy application no.'], ['sub_amount', 'Subsidy amount (Rs)'], ['sub_status', 'Subsidy status']],
    14: [['sent_what', 'Kya bheja (demo / datasheet / photo)'], ['sent_mode', 'Kaise bheja (WhatsApp / Email / Milkar)']],
    15: [['pay_mode', 'Payment tarika (Cash / Loan / Mixed)', 1], ['bank', 'Bank'], ['loan_amount', 'Loan amount (Rs)'], ['loan_status', 'Loan status'], ['loan_ref', 'Loan reference no.']],
    16: [['ref_name', 'Refer kiya (naam)'], ['ref_mobile', 'Refer kiya (mobile)']],
    17: [['amc_plan', 'AMC / maintenance plan'], ['amc_start', 'Shuru ki tareekh', 0, 'date']],
    18: [['c_status', 'Complaint status (None / Open / In progress / Resolved)'], ['c_issue', 'Samasya'], ['c_ticket', 'Ticket / complaint no.'], ['c_handler', 'Kisne sambhali (Installer / Dealer / Manufacturer)'], ['c_brand', 'Brand / product'], ['c_serial', 'Serial number'], ['c_date', 'Complaint ki tareekh', 0, 'date']]
  };
  /* the menu that does the work for a step. ctx = { party_id, quote_id } */
  function link(n, ctx) {
    ctx = ctx || {}; var p = ctx.party_id, q = ctx.quote_id;
    switch (+n) {
      case 19: return { href: '#/leads', label: 'Leads kholein', icon: 'lead' };
      case 1: case 2: return p ? { href: '#/customer/' + p, label: 'Customer page', icon: 'user' } : null;
      case 14: return { href: '#/docs', label: 'Documents & Gallery', icon: 'folder' };
      case 3: return q ? { href: '#/quote/' + q, label: 'Quotation kholein', icon: 'quote' } : { href: '#/quotes', label: 'Nayi quotation banayein', icon: 'quote' };
      case 4: return { href: '#/sitevisit' + (p ? '?party=' + p : ''), label: 'Site Visit lagayein', icon: 'plant' };
      case 5: return { href: '#/blueprint' + (p ? '?new=1&party=' + p : ''), label: 'Project blue print', icon: 'plant' };
      case 12: return { href: '#/billing', label: 'Billing', icon: 'bill' };
      case 16: return { href: '#/commission', label: 'Commission / Referral', icon: 'rupee' };
      case 17: case 18: return { href: '#/maintenance' + (p && +n === 17 ? '?party=' + p : ''), label: 'Maintenance & AMC', icon: 'settings' };
      default: return null; /* 6,7,8,9,10,11,13,15: noted right inside the step card */
    }
  }
  /* which customer kind a quotation customer-type means */
  var PROJECT_TYPES = ['Residential', 'Commercial', 'Industrial', 'VFD'];
  function kindOfCtype(t) { return PROJECT_TYPES.indexOf(t) >= 0 ? 'project' : (t === 'Items only' ? 'product' : (t === 'Service' || t === 'AMC only' || t === 'Site visit only' ? 'service' : '')); }

  /* Round 38: Conversation me jo chuna (customer kya chahta hai) -> kaam ka prakar (ctype). Ek hi jagah. */
  function ctypeOfParty(p) {
    var d = (p && p.data) || {};
    if (d.cust_kind === 'product') return 'Items only';
    if (d.cust_kind === 'service') return d.service_type === 'Maintenance / AMC' ? 'AMC only' : 'Service';
    return PROJECT_TYPES.indexOf(d.project_type) >= 0 ? d.project_type : 'Residential';
  }
  /* Save & Next: naya kaam usi customer par — details dobara nahi. Customer page "Naya Kaam" aur Lead ki Conversation dono yahi chalate hain. */
  async function startJob(pid, ctype) {
    if (ctype === 'AMC only' || ctype === 'Site visit only') {
      var r = await C.run('crm_job_new', { party_id: pid, ctype: ctype }, 'Naya kaam shuru ho gaya ✔');
      return C.go('#/' + (ctype === 'AMC only' ? 'maintenance' : 'sitevisit') + '?party=' + pid + '&cf=' + pid + '&cq=' + r.id);
    }
    C.go('#/quote/new?party=' + pid + '&ctype=' + encodeURIComponent(ctype) + '&cf=' + pid);
  }
  C.ctypeOfParty = ctypeOfParty; C.startJob = startJob;

  var ALL = [19, 2, 14, 3, 4, 5, 6, 7, 15, 8, 9, 10, 11, 12, 13, 16, 17, 18]; /* every step a Project customer can have, in order (Round 33 flow bar greys the ones a job does not use) */
  C.FLOW = { ALL: ALL, NAMES: NAMES, IC: IC, COL: COL, HELP: HELP, FIELDS: FIELDS, link: link, PROJECT_TYPES: PROJECT_TYPES, kindOfCtype: kindOfCtype };
  C.KINDS = { project: 'Project customer', product: 'Product customer', service: 'Service customer' };
  C.SEGMENTS = { b2c: 'Ghar / Individual (B2C)', b2b: 'Business / Dealer (B2B)' };
  C.kindPill = function (k) { return k === 'product' ? C.pill('Product', 'g') : k === 'service' ? C.pill('Service', 'b') : C.pill('Project', 'v'); };
})();
