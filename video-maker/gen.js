const { chromium } = require('playwright'); const { spawn } = require('child_process'); const fs = require('fs'); const V = require('./videos.js');
const FPS = 15, OUT = '/home/claude/vidgen/out/';
(async () => {
  const keys = process.argv.slice(2).filter(k => V[k]); const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  await p.goto('file:///home/claude/vidgen/scene.html'); p.on('pageerror', e => console.log('PAGEERR', e.message));
  for (const k of keys) {
    const tot = await p.evaluate(v => window.load(v), V[k]); const n = Math.round(tot * FPS);
    const ff = spawn('ffmpeg', ['-v', 'error', '-y', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-', '-c:v', 'libx264', '-preset', 'slow', '-crf', '28', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-metadata', 'title=' + V[k].title, OUT + k + '.mp4'], { stdio: ['pipe', 'inherit', 'inherit'] });
    for (let f = 0; f < n; f++) {
      await p.evaluate(t => window.setT(t), f / FPS); const buf = await p.screenshot({ type: 'jpeg', quality: 86 });
      if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
      if (f === Math.round(FPS * 1.6)) fs.writeFileSync(OUT + k + '.jpg', await p.screenshot({ type: 'jpeg', quality: 72 }));
    }
    ff.stdin.end(); await new Promise(r => ff.on('close', r)); console.log(k, tot.toFixed(1) + 's', (fs.statSync(OUT + k + '.mp4').size / 1024).toFixed(0) + 'KB');
  }
  await b.close();
})();
