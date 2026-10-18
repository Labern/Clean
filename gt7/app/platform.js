// The one place that knows whether we're the web app or a native shell
// (Capacitor, for the iOS/Android builds). Native shells can call PSN and
// GT-Gridstats directly because native HTTP has no CORS; the web app relays
// through the Mac bridge instead.
export const isNative = () => !!window.Capacitor?.isNativePlatform?.();
export const platform = () => (isNative() ? window.Capacitor.getPlatform() : 'web');

// fetch-shaped wrapper over CapacitorHttp, so shared code (psn-core.js) runs unchanged.
export async function nativeFetch(url, opt = {}) {
  const H = window.Capacitor.Plugins.CapacitorHttp;
  const r = await H.request({ url, method: opt.method || 'GET', headers: opt.headers || {}, data: opt.body, disableRedirects: opt.redirect === 'manual' });
  const headers = new Map(Object.entries(r.headers || {}).map(([k, v]) => [k.toLowerCase(), v]));
  return { status: r.status, headers: { get: (k) => headers.get(k.toLowerCase()) }, json: async () => (typeof r.data === 'string' ? JSON.parse(r.data) : r.data), text: async () => (typeof r.data === 'string' ? r.data : JSON.stringify(r.data)) };
}
