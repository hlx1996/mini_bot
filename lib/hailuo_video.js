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
    await page.goto('https://hailuoai.video/zh-Intl/create/text-to-video', { waitUntil: 'domcontentloaded', timeout: 30000 });
    try { await page.waitForLoadState('networkidle', { timeout: 8000 }); } catch {}

    // Detect login wall
    const loggedIn = await page.evaluate(() => !document.body.innerText.match(/Sign in|Log in|^登录$/im) ||
                                          document.querySelector('#video-create-textarea, textarea, [contenteditable="true"]'));
    if (!loggedIn) {
      return JSON.stringify({ ok: false, error: '未登录 Hailuo。请在本机 Chrome 里先登录 hailuoai.video。' });
    }

    // Find the prompt input
    const inputSel = [
      '#video-create-textarea',
      '[contenteditable="true"]',
      'textarea',
    ];
    let input = null;
    for (const sel of inputSel) {
      input = await page.$(sel);
      if (input) { log('input selector:', sel); break; }
    }
    if (!input) return JSON.stringify({ ok: false, error: '找不到 prompt 输入框，页面布局可能变了' });
    await input.click();
    // Use keyboard type for contenteditable div
    await page.keyboard.type(prompt);
    await page.waitForTimeout(1500);

    // Click submit — Hailuo 2026-05 uses 创作视频 text
    const clicked = await page.evaluate(() => {
      // 1. try by text
      const all = [...document.querySelectorAll('button, div[role=button], [class*=cursor-pointer]')];
      const byText = all.find(el => /^(创作视频|生成视频|生成|Generate|Create Video)$/.test((el.innerText||'').trim()));
      if (byText) { byText.click(); return 'by-text:' + byText.innerText.trim(); }
      // 2. fallback: rightmost icon-only button at input row
      const ta = document.querySelector('#video-create-textarea, [contenteditable="true"], textarea');
      if (ta) {
        const tar = ta.getBoundingClientRect();
        const cands = [...document.querySelectorAll('button, [class*=cursor-pointer]')]
          .map(el => ({el, r: el.getBoundingClientRect()}))
          .filter(o => !o.el.innerText.trim() && o.r.width>=24 && o.r.width<=64
                       && o.r.top > tar.top - 20 && o.r.top < tar.bottom + 80)
          .sort((a,b) => b.r.right - a.r.right);
        if (cands[0]) { cands[0].el.click(); return 'by-pos'; }
      }
      return '';
    });
    if (!clicked) return JSON.stringify({ ok: false, error: '找不到生成按钮' });
    log('submitted via:', clicked, '— waiting for video...');

    // Poll for a <video src> in newly-rendered task list, up to timeoutMs
    const deadline = Date.now() + timeoutMs;
    let videoUrl = null;
    while (Date.now() < deadline) {
      videoUrl = await page.evaluate(() => {
        // pick the first video that has a real src (not blob preview of trending)
        const vids = [...document.querySelectorAll('video[src], video source[src]')];
        for (const v of vids) {
          const s = v.src || v.getAttribute('src');
          if (s && /\.(mp4|webm|m3u8)/i.test(s) && !s.startsWith('blob:')) return s;
        }
        // Accept blob: too as last resort (the user can download via the page)
        for (const v of vids) {
          const s = v.src || v.getAttribute('src');
          if (s) return s;
        }
        return null;
      });
      if (videoUrl) break;
      await page.waitForTimeout(5000);
    }
    if (!videoUrl) return JSON.stringify({ ok: false, error: '等待超时（' + (timeoutMs/1000) + 's），没有出现 video src' });
    return JSON.stringify({ ok: true, videoUrl });
  } catch (e) {
    return JSON.stringify({ ok: false, error: e.message });
  } finally {
    try { await page.close(); } catch {}
  }
};
