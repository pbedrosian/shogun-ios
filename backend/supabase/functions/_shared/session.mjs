// Validate live Auth identity instead of trusting decoded JWT claims or caller-supplied IDs.
export function bearerHeader(value) { return /^Bearer \S{1,8192}$/.test(value ?? ''); }
export async function verifySession({ url, key }, authorization, request = fetch, signal) {
  if (!bearerHeader(authorization)) return { status: 401 };
  if (!url || !key) return { status: 503 };
  try {
    const response = await request(url.replace(/\/$/,'')+'/auth/v1/user', {
      headers: { apikey: key, Authorization: authorization }, redirect: 'error',
      signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(10000)]) : AbortSignal.timeout(10000),
    });
    if (!response.ok) return { status: response.status === 429 || response.status >= 500 ? 503 : 401 };
    const user = await response.json();
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(user.id ?? '')
      ? { user } : { status: 401 };
  } catch { return { status: 503 }; }
}
