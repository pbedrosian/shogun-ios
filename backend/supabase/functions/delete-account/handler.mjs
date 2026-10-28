import { bearerHeader, verifySession } from '../_shared/session.mjs';
// Auth validates both the session and current password. Never accept a target user ID.
export function createDeleteHandler(env, request = fetch) {
  const reply = (status, error) => Response.json(error ? { error } : { deleted: true }, { status, headers: { 'Cache-Control': 'no-store' } });
  return async incoming => {
    if (incoming.method !== 'POST') return reply(405, 'method_not_allowed');
    const authorization = incoming.headers.get('Authorization') ?? '';
    if (!bearerHeader(authorization)) return reply(401, 'unauthorized');
    if (!env.url || !env.admin || !env.anon) return reply(503, 'unavailable');
    let body;
    try {
      const raw = await incoming.text();
      if (new TextEncoder().encode(raw).length > 4096) return reply(400, 'invalid_request');
      body = JSON.parse(raw);
      if (!body || typeof body.password !== 'string' || !body.password || Object.keys(body).some(k => k !== 'password')) return reply(400, 'invalid_request');
    } catch { return reply(400, 'invalid_request'); }
    const authURL = env.url.replace(/\/$/, '') + '/auth/v1';
    const headers = { apikey: env.admin, Authorization: authorization };
    const options = { redirect: 'error', signal: AbortSignal.timeout(15000) };
    let reauthenticationToken;
    try {
      const sessionCheck = await verifySession({url:env.url,key:env.admin},authorization,request);
      if (!sessionCheck.user) return reply(sessionCheck.status,'unauthorized');
      const user = sessionCheck.user;
      if (!user.email) return reply(401,'unauthorized');
      const verified = await request(authURL + '/token?grant_type=password', { ...options, method: 'POST',
        headers: { apikey: env.anon, 'Content-Type': 'application/json' }, body: JSON.stringify({ email: user.email, password: body.password }) });
      if (!verified.ok) return reply(verified.status === 429 ? 429 : verified.status >= 500 ? 503 : 403, 'reauthentication_failed');
      const session = await verified.json();
      reauthenticationToken = session.access_token;
      if (session.user?.id !== user.id) return reply(403, 'reauthentication_failed');
      const result = await request(authURL + '/admin/users/' + user.id, { ...options, method: 'DELETE',
        headers: { apikey: env.admin, Authorization: 'Bearer ' + env.admin, 'Content-Type': 'application/json' },
        body: JSON.stringify({ should_soft_delete: false }) });
      return result.ok ? reply(200) : reply(503, 'unavailable');
    } catch { return reply(503, 'unavailable'); }
    finally {
      // Do not leave the temporary password-verification session active on failure.
      if (reauthenticationToken) {
        try { await request(authURL + '/logout?scope=local', { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(5000),
          headers: { apikey: env.anon, Authorization: 'Bearer ' + reauthenticationToken } }); } catch {}
      }
    }
  };
}
