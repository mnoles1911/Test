// ===========================================================================
// browse_shot.mjs — headless-browser screenshot + console/error capture
// ===========================================================================
// The browser self-verification primitive: open a URL (a studio, a local page,
// a built artifact), wait for it to settle, screenshot it, and report any
// console errors / page errors / failed requests. Exit code 1 if errors — so it
// drives a fix-rerun loop.
//
//   node tools/devtools/browse_shot.mjs <url> [out.png] [options]
//     --wait <ms>        extra settle time after networkidle (default 2500)
//     --full             full-page screenshot
//     --width/-height N  viewport (default 1280x900)
//     --click "<sel>"    click a selector before shooting (repeatable)
//     --eval "<js>"      run JS in the page before shooting (e.g. set a slider)
//     --selector "<sel>" wait for this selector to appear
//
// Prints a JSON report: { url, httpStatus, errors[], warnings[], out }.
import { chromium } from 'playwright';

const argv = process.argv.slice(2);
const url = argv[0];
const out = (argv[1] && !argv[1].startsWith('-')) ? argv[1] : '/tmp/shot.png';
const getAll = (name) => argv.reduce((a, v, i) => (v === name ? [...a, argv[i + 1]] : a), []);
const get = (name, def) => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : def; };

if (!url) { console.error('usage: browse_shot.mjs <url> [out.png] [--wait ms] [--full] [--click sel] [--eval js] [--selector sel]'); process.exit(2); }

const waitMs = +get('--wait', 2500);
const full = argv.includes('--full');
const W = +get('--width', 1280), H = +get('--height', 900);
const selector = get('--selector', null);

const errors = [], warnings = [];
const browser = await chromium.launch({ args: ['--no-sandbox', '--use-gl=swiftshader', '--enable-webgl', '--ignore-gpu-blocklist'] });
const context = await browser.newContext({ viewport: { width: W, height: H }, deviceScaleFactor: 1, ignoreHTTPSErrors: true });
const page = await context.newPage();

page.on('console', (m) => { const t = m.type(); if (t === 'error') errors.push(m.text()); else if (t === 'warning') warnings.push(m.text()); });
page.on('pageerror', (e) => errors.push('PAGEERROR: ' + e.message));
page.on('requestfailed', (r) => errors.push('REQ FAIL: ' + r.url() + ' — ' + (r.failure()?.errorText || '')));
let httpStatus = null;
page.on('response', (r) => { if (r.url().replace(/[#?].*$/, '') === url.replace(/[#?].*$/, '')) httpStatus = r.status(); });

try {
  await page.goto(url, { waitUntil: 'networkidle', timeout: 45000 });
} catch (e) { errors.push('GOTO: ' + e.message); }

if (selector) { try { await page.waitForSelector(selector, { timeout: 15000 }); } catch (e) { errors.push('SELECTOR: ' + e.message); } }
for (const sel of getAll('--click')) { try { await page.click(sel, { timeout: 8000 }); await page.waitForTimeout(400); } catch (e) { errors.push('CLICK ' + sel + ': ' + e.message); } }
for (const js of getAll('--eval')) { try { await page.evaluate(js); } catch (e) { errors.push('EVAL: ' + e.message); } }

await page.waitForTimeout(waitMs);
try { await page.screenshot({ path: out, fullPage: full }); } catch (e) { errors.push('SHOT: ' + e.message); }
await browser.close();

console.log(JSON.stringify({ url, out, httpStatus, errorCount: errors.length, errors, warningCount: warnings.length }, null, 2));
process.exit(errors.length ? 1 : 0);
