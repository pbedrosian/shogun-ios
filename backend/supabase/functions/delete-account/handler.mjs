import { revokeAppleAuthorization } from './apple.mjs';
import { bearerHeader, verifySession } from '../_shared/session.mjs';
// Auth validates every token before its claims are inspected. Never accept a target user ID.
function validatedClaims(token) {
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('invalid_token');
  return JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
}
function freshOAuthReauthentication(original, fresh, user, provider) {
  // Auth already verified both JWTs with this project's signing keys. Its public
  // issuer URL can differ from the internal service URL used by local functions.
  const current = validatedClaims(original), proof = validatedClaims(fresh);
  const now = Date.now() / 1000;
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  return proof.sub === user.id && proof.role === 'authenticated' &&
    (proof.aud === 'authenticated' || (Array.isArray(proof.aud) && proof.aud.includes('authenticated'))) &&
    Number.isFinite(proof.exp) && proof.exp > now &&
    uuid.test(current.session_id ?? '') && uuid.test(proof.session_id ?? '') &&
    current.session_id !== proof.session_id &&
    user.identities?.some(identity => identity.provider === provider) === true &&
    Array.isArray(proof.amr) && proof.amr.some(method => method.method === 'oauth' &&
      Number.isFinite(method.timestamp) && method.timestamp >= now - 300 && method.timestamp <= now + 30);
}
async function readDeletionBody(incoming) {
  const reader = incoming.body?.getReader();
  if (!reader) throw new Error('invalid_request');
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let raw = '', bytes = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > 12288) {
        await reader.cancel();
        throw new Error('invalid_request');
      }
      raw += decoder.decode(value, { stream: true });
    }
    return { body: JSON.parse(raw + decoder.decode()), bytes };
  } finally { reader.releaseLock(); }
}
export function createDeleteHandler(env, request = fetch) {
  const reply = (status, error, appleRevocationRequired = false) => Response.json(error ? { error } : { deleted: true, ...(appleRevocationRequired ? { apple_revocation_required: true } : {}) }, { status, headers: { 'Cache-Control': 'no-store' } });
  return async incoming => {
    if (incoming.method !== 'POST') return reply(405, 'method_not_allowed');
    const authorization = incoming.headers.get('Authorization') ?? '';
    if (!bearerHeader(authorization)) return reply(401, 'unauthorized');
    if (!env.url || !env.admin || !env.anon) return reply(503, 'unavailable');
    let body;
    try {
      const parsed = await readDeletionBody(incoming);
      body = parsed.body;
      if (!body || Array.isArray(body) || Object.keys(body).length !== 1) return reply(400, 'invalid_request');
      const password = typeof body.password === 'string' && body.password.length > 0 &&
        parsed.bytes <= 4096;
      const appleFallback = body.apple_fallback && typeof body.apple_fallback === 'object' && !Array.isArray(body.apple_fallback) &&
        Object.keys(body.apple_fallback).length === 1 && typeof body.apple_fallback.password === 'string' &&
        body.apple_fallback.password.length > 0 && parsed.bytes <= 4096;
      const google = typeof body.reauthentication_token === 'string' &&
        bearerHeader('Bearer ' + body.reauthentication_token);
      const apple = body.apple && typeof body.apple === 'object' && !Array.isArray(body.apple) &&
        Object.keys(body.apple).length === 3 &&
        Object.keys(body.apple).every(key => ['reauthentication_token','authorization_code','client_id'].includes(key)) &&
        typeof body.apple.reauthentication_token === 'string' && bearerHeader('Bearer ' + body.apple.reauthentication_token) &&
        typeof body.apple.authorization_code === 'string' && body.apple.authorization_code.length > 0 && body.apple.authorization_code.length <= 2048 &&
        typeof body.apple.client_id === 'string' && /^[a-zA-Z0-9][a-zA-Z0-9.-]{1,254}$/.test(body.apple.client_id);
      if (!password && !google && !apple && !appleFallback) return reply(400, 'invalid_request');
    } catch { return reply(400, 'invalid_request'); }
    const authURL = env.url.replace(/\/$/, '') + '/auth/v1';
    const options = { redirect: 'error', signal: AbortSignal.timeout(15000) };
    let reauthenticationToken;
    let manualAppleRevocation = false;
    try {
      const sessionCheck = await verifySession({url:env.url,key:env.admin},authorization,request);
      if (!sessionCheck.user) return reply(sessionCheck.status,'unauthorized');
      const user = sessionCheck.user;
      if (!user.email) return reply(401,'unauthorized');
      // Prefer Apple revocation before deletion. The explicit password-confirmed
      // fallback lets an owner delete when Apple authorization is unavailable;
      // the response tells the app that Apple access still needs manual removal.
      const hasApple = user.identities?.some(identity => identity.provider === 'apple') === true;
      if (hasApple && !body.apple && !body.apple_fallback) return reply(403, 'reauthentication_failed');
      if (body.apple_fallback && !hasApple) return reply(403, 'reauthentication_failed');
      manualAppleRevocation = !!body.apple_fallback;
      if (body.apple) {
        if (!hasApple) return reply(403, 'reauthentication_failed');
        const proof = body.apple;
        const fresh = await verifySession({url:env.url,key:env.admin},
          'Bearer ' + proof.reauthentication_token, request);
        if (!fresh.user) return reply(fresh.status === 503 ? 503 : 403, 'reauthentication_failed');
        if (fresh.user.id !== user.id) return reply(403, 'reauthentication_failed');
        try {
          if (!freshOAuthReauthentication(authorization.slice(7), proof.reauthentication_token, fresh.user, 'apple')) {
            return reply(403, 'reauthentication_failed');
          }
        } catch { return reply(403, 'reauthentication_failed'); }
        reauthenticationToken = proof.reauthentication_token;
        const revoked = await revokeAppleAuthorization(env.apple, proof, user, request);
        if (revoked !== 200) return reply(revoked, 'reauthentication_failed');
      } else if (body.reauthentication_token) {
        const fresh = await verifySession({url:env.url,key:env.admin},
          'Bearer ' + body.reauthentication_token,request);
        if (!fresh.user) return reply(fresh.status === 503 ? 503 : 403, 'reauthentication_failed');
        if (fresh.user.id !== user.id) return reply(403, 'reauthentication_failed');
        try {
          if (!freshOAuthReauthentication(authorization.slice(7),body.reauthentication_token,fresh.user,'google')) {
            return reply(403, 'reauthentication_failed');
          }
        } catch { return reply(403, 'reauthentication_failed'); }
        reauthenticationToken = body.reauthentication_token;
      } else {
        const verified = await request(authURL + '/token?grant_type=password', { ...options, method: 'POST',
          headers: { apikey: env.anon, 'Content-Type': 'application/json' }, body: JSON.stringify({ email: user.email, password: body.apple_fallback?.password ?? body.password }) });
        if (!verified.ok) return reply(verified.status === 429 ? 429 : verified.status >= 500 ? 503 : 403, 'reauthentication_failed');
        const session = await verified.json();
        reauthenticationToken = session.access_token;
        if (session.user?.id !== user.id) return reply(403, 'reauthentication_failed');
      }
      const result = await request(authURL + '/admin/users/' + user.id, { ...options, method: 'DELETE',
        headers: { apikey: env.admin, Authorization: 'Bearer ' + env.admin, 'Content-Type': 'application/json' },
        body: JSON.stringify({ should_soft_delete: false }) });
      return result.ok ? reply(200, undefined, manualAppleRevocation) : reply(503, 'unavailable');
    } catch { return reply(503, 'unavailable'); }
    finally {
      // Do not leave the temporary reauthentication session active on failure.
      if (reauthenticationToken) {
        try { await request(authURL + '/logout?scope=local', { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(5000),
          headers: { apikey: env.anon, Authorization: 'Bearer ' + reauthenticationToken } }); } catch {}
      }
    }
  };
}
