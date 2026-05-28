// lib/hailuo_video.js — Drive https://hailuoai.video to generate a video from a prompt.
//
// Usage: invoked by browse.js --mode script --js lib/hailuo_video.js
// Env: HAILUO_PROMPT (required), HAILUO_TIMEOUT_SEC (default 600)
//
// NOTE: hailuoai.video changes its DOM often; selectors are best-effort and
// may need tweaking. Returns JSON {ok, videoUrl?, error?} on stdout.
//
// Requires user to be logged in via CDP-attached Chrome:
//   USE_LOCAL_CHROME=1, plus Chrome with --remote-debugging-port=9222 + valid Hailuo session.

module.exports = async ({ browser, ctx, log }) => {
  const prompt = process.env.HAILUO_PROMPT;
  if (!prompt) return JSON.stringify({ ok: false, error: 'HAILUO_PROMPT env required' });
  const timeoutMs = (parseInt(process.env.HAILUO_TIMEOUT_SEC || '600', 10)) * 1000;

  const page = await ctx.newPage();
  try {
    await page.goto('https://hailuoai.video/create', { waitUntil: 'domcontentloaded', timeout: 30000 });
    try { await page.waitForLoadState('networkidle', { timeout: 8000 }); } catch {}

    // Detect login wall
    const loggedIn = await page.evaluate(() => !document.body.innerText.match(/Sign in|Log in|登录/i) ||
                                          document.querySelector('textarea, [contenteditable="true"]'));
    if (!loggedIn) {
      return JSON.stringify({ ok: false, error: '未登录 Hailuo。请在本机 Chrome 里先登录 hailuoai.video。' });
    }

    // Find the prompt textarea (try a few selectors)
    const inputSel = [
      'textarea[placeholder*="describe" i]',
      'textarea[placeholder*="prompt" i]',
      'textarea[placeholder*="生成" i]',
      'textarea',
      '[contenteditable="true"]',
    ];
    let input = null;
    for (const sel of inputSel) {
      input = await page.$(sel);
      if (input) { log('input selector:', sel); break; }
    }
    if (!input) return JSON.stringify({ ok: false, error: '找不到 prompt 输入框，页面布局可能变了' });
    await input.click();
    await input.fill(prompt);

    // Find submit button
    const btnCandidates = [
      'button:has-text("Generate")',
      'button:has-text("生成")',
      'button:has-text("Create")',
      'button[type="submit"]',
    ];
    let btn = null;
    for (const sel of btnCandidates) {
      btn = await page.$(sel);
      if (btn && await btn.isEnabled()) { log('submit selector:', sel); break; }
      btn = null;
    }
    if (!btn) return JSON.stringify({ ok: false, error: '找不到生成按钮' });
    await btn.click();
    log('submitted, waiting for video...');

    // Poll for a <video> element with a src, up to timeoutMs
    const deadline = Date.now() + timeoutMs;
    let videoUrl = null;
    while (Date.now() < deadline) {
      videoUrl = await page.evaluate(() => {
        const v = document.querySelector('video[src]') || document.querySelector('video source[src]');
        return v ? (v.src || v.getAttribute('src')) : null;
      });
      if (videoUrl) break;
      await new Promise(r => setTimeout(r, 5000));
    }
    if (!videoUrl) return JSON.stringify({ ok: false, error: '等待超时（' + (timeoutMs/1000) + 's），没有出现 video src' });
    return JSON.stringify({ ok: true, videoUrl });
  } catch (e) {
    return JSON.stringify({ ok: false, error: e.message });
  } finally {
    try { await page.close(); } catch {}
  }
};
