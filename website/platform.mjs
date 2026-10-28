// Use only browser-provided hints; no network request or persistent identifier.
export function detectPlatform(browser = {}) {
  const hint = browser.userAgentData?.platform || '';
  const ua = browser.userAgent || '';
  const platform = browser.platform || '';
  if (/Windows Phone|CrOS/i.test(ua) || /Chrome OS|Chromium OS/i.test(hint)) return null;
  if (/Android/i.test(hint + ' ' + ua)) return 'android';
  if (/iOS|iPhone|iPad|iPod/i.test(hint + ' ' + ua)) return 'ios';
  // iPadOS can request desktop pages and identify itself as a Mac.
  if (/Mac/i.test(platform + ' ' + ua) && browser.maxTouchPoints > 1) return 'ios';
  if (/Windows/i.test(hint)) return 'windows';
  if (/macOS|Mac OS/i.test(hint)) return 'macos';
  if (/Linux/i.test(hint)) return 'linux';
  if (/Win/i.test(platform) || /Windows/i.test(ua)) return 'windows';
  if (/Mac/i.test(platform) || /Macintosh|Mac OS X/i.test(ua)) return 'macos';
  if (/Linux|X11/i.test(platform + ' ' + ua)) return 'linux';
  return null;
}
