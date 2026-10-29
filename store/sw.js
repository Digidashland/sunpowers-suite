/* Sunpowers App — minimal service worker (Round 31).
   Only job: make the app installable ("Install app" on Android Chrome) and show a polite page when offline.
   It never keeps a copy of the app, it always uses the network, so customers always get the latest prices and products. */
self.addEventListener('install', function () { self.skipWaiting(); });
self.addEventListener('activate', function (e) { e.waitUntil(self.clients.claim()); });
self.addEventListener('fetch', function (e) {
  var r = e.request;
  if (r.method !== 'GET' || r.mode !== 'navigate') return;   /* everything else goes straight to the network */
  e.respondWith(fetch(r).catch(function () {
    return new Response('<meta charset="utf-8"><meta name="viewport" content="width=device-width"><body style="font-family:sans-serif;text-align:center;padding:48px 20px"><h2>📴 इंटरनेट नहीं है / You are offline</h2><p>कनेक्शन आने पर फिर से खोलें · Open again when you are online.</p>', { status: 200, headers: { 'Content-Type': 'text/html; charset=utf-8' } });
  }));
});
