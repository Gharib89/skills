// PROTOTYPE helper: node contact.mjs <KEY> <out.png> [t1 t2 ...]
// Rebuild first (python3 build.py <KEY>). Seeks one direction to each time and writes one contact sheet,
// plus prints console errors. Uses headless Chrome, its own instance, so sessions do not collide.
import puppeteer from 'puppeteer-core';
import { fileURLToPath } from 'url';
import path from 'path';
const here = path.dirname(fileURLToPath(import.meta.url));
const [key, out, ...ts] = process.argv.slice(2);
const times = ts.length ? ts.map(Number) : [1, 5, 9, 13, 17, 21, 24, 26.5, 28, 33, 38, 43, 47, 50, 51.5, 56, 61, 66, 70, 72.4];
const browser = await puppeteer.launch({ executablePath: '/home/ribo/.cache/ms-playwright/chromium_headless_shell-1243/chrome-headless-shell-linux64/chrome-headless-shell', headless: 'shell', args: ['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--allow-file-access-from-files'] });
const page = await browser.newPage();
const errs = [];
page.on('pageerror', e => errs.push('pageerror: ' + e.message));
page.on('console', m => { if (m.type() === 'error') errs.push('console: ' + m.text()); });
await page.setViewport({ width: 1600, height: 1000 });
await page.goto('file://' + path.join(here, 'preview-' + key + '.html') + '#' + key.toLowerCase(), { waitUntil: 'load', timeout: 60000 });
await page.evaluate(async (key, times) => {
  document.querySelector('.switcher').hidden = true;
  const g = document.createElement('div');
  g.style.cssText = 'position:fixed;inset:0;z-index:99;background:#777;display:grid;grid-template-columns:repeat(5,1fr);gap:4px;padding:4px;align-content:start';
  document.body.appendChild(g);
  const d = DIRECTIONS.find(x => x.key === key);
  for (const t of times) {
    const w = document.createElement('div'); w.style.position = 'relative';
    const st = document.createElement('div'); st.className = 'stage'; w.appendChild(st);
    const lab = document.createElement('span'); lab.textContent = t; lab.style.cssText = 'position:absolute;left:2px;top:2px;background:#000;color:#fff;font:12px monospace;padding:1px 4px;z-index:5';
    w.appendChild(lab); g.appendChild(w);
    __mount(st, d).seek(t);
  }
  await new Promise(r => setTimeout(r, 500));
}, key, times);
await page.screenshot({ path: out });
await browser.close();
console.log(errs.length ? errs.join('\n') : 'no errors');
