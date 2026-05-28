#!/usr/bin/env node
// lib/browse.js — Playwright helper. Modes:
//
//   --mode fetch  --url <u> [--screenshot <p>] [--text <p>]
//                 Headless fresh-profile fetch. Writes PNG + text file.
//
//   --mode cdp    --url <u> [--screenshot <p>] [--text <p>] [--cdp <ws>]
//                 Attach to local Chrome via DevTools Protocol (default
//                 endpoint http://localhost:9222). Opens a new tab so we
//                 don't disturb the user's foreground tab.
//
//   --mode script --js <file>
//                 Custom browser automation (used by /video Hailuo).
//                 The JS file should `module.exports = async ({ browser, log }) => { ... }`.
//
// All modes background-only: never raises window, never steals focus.

const path = require('path');
const fs   = require('fs');

function parseArgs(argv) {
  const o = {};
  for (let i=2; i<argv.length; i++) {
    const k = argv[i];
    if (k.startsWith('--')) o[k.slice(2)] = (argv[i+1] && !argv[i+1].startsWith('--')) ? argv[++i] : true;
  }
  return o;
}

async function getBrowser(args) {
  const { chromium } = require('playwright');
  if (args.mode === 'cdp') {
    const endpoint = args.cdp || 'http://localhost:9222';
    // connectOverCDP works with http or ws URLs; chrome --remote-debugging-port=9222 exposes http
    const b = await chromium.connectOverCDP(endpoint);
    return { browser: b, isCDP: true };
  }
  // Fresh-profile headless. macOS: don't bring app to front.
  const b = await chromium.launch({ headless: true });
  return { browser: b, isCDP: false };
}

async function newContext(browser, isCDP) {
  if (isCDP) {
    // Reuse the user's default context (cookies, login, etc), but open NEW tab.
    const contexts = browser.contexts();
    return contexts[0] || (await browser.newContext());
  }
  return await browser.newContext({
    viewport: { width: 1280, height: 1024 },
    userAgent: 'Mozilla/5.0 (mini_bot/browse)',
  });
}

(async () => {
  const args = parseArgs(process.argv);
  const log  = (...m) => console.error('[browse]', ...m);

  let r;
  try { r = await getBrowser(args); }
  catch (e) {
    console.error('FATAL browser-launch:', e.message);
    if (args.mode === 'cdp') console.error('提示：请先用  chrome --remote-debugging-port=9222 --user-data-dir=/tmp/chrome-debug  启动 Chrome');
    process.exit(2);
  }
  const { browser, isCDP } = r;
  let ctx, page;
  try {
    ctx = await newContext(browser, isCDP);

    if (args.mode === 'script') {
      const mod = require(path.resolve(args.js));
      const result = await mod({ browser, ctx, log });
      if (result) process.stdout.write(typeof result === 'string' ? result : JSON.stringify(result));
      return;
    }

    page = await ctx.newPage();
    if (!args.url) throw new Error('--url required');
    await page.goto(args.url, { waitUntil: 'domcontentloaded', timeout: 30000 });
    // small idle wait so JS apps can render
    try { await page.waitForLoadState('networkidle', { timeout: 8000 }); } catch {}

    if (args.screenshot) {
      await page.screenshot({ path: args.screenshot, fullPage: false });
      log('screenshot ->', args.screenshot);
    }
    if (args.text) {
      // strip script/style, take body innerText
      const text = await page.evaluate(() => {
        document.querySelectorAll('script,style,noscript').forEach(n => n.remove());
        return document.body ? document.body.innerText : '';
      });
      fs.writeFileSync(args.text, text.slice(0, 30000));
      log('text bytes ->', text.length);
    }
  } catch (e) {
    console.error('ERROR:', e.message);
    process.exit(1);
  } finally {
    try { if (page) await page.close(); } catch {}
    // Don't close shared contexts in CDP mode
    if (!isCDP) { try { await ctx?.close(); } catch {} try { await browser.close(); } catch {} }
    else { try { await browser.close(); } catch {} }
  }
})();
