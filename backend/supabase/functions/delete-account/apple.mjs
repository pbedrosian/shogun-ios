const appleURL = 'https://appleid.apple.com/auth/';
const encoder = new TextEncoder();
const base64URL = bytes => btoa(String.fromCharCode(...new Uint8Array(bytes)))
  .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
const encodedJSON = value => base64URL(encoder.encode(JSON.stringify(value)));

async function clientSecret(config, clientID) {
  const raw = config.privateKey.replace(/\\n/g, '\n')
    .replace('-----BEGIN PRIVATE KEY-----', '').replace('-----END PRIVATE KEY-----', '').replace(/\s/g, '');
  const key = await crypto.subtle.importKey('pkcs8', Uint8Array.from(atob(raw), c => c.charCodeAt(0)),
    { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const now = Math.floor(Date.now() / 1000);
  const input = encodedJSON({ alg: 'ES256', kid: config.keyID }) + '.' +
    encodedJSON({ iss: config.teamID, sub: clientID, aud: 'https://appleid.apple.com', iat: now, exp: now + 300 });
  const signature = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, encoder.encode(input));
  return input + '.' + base64URL(signature);
}

// Only inspect the ID token returned directly by Apple's HTTPS token endpoint,
// never an ID token supplied by the caller. The authenticated Supabase identity
// supplies the expected Apple subject; email is never an identity binding.
function matchesAppleIdentity(token, clientID, user) {
  if (typeof token !== 'string' || token.length > 16384) return false;
  const parts = token.split('.');
  if (parts.length !== 3) return false;
  const payload = parts[1].replace(/-/g, '+').replace(/_/g, '/');
  const claims = JSON.parse(atob(payload.padEnd(Math.ceil(payload.length / 4) * 4, '=')));
  return claims.iss === 'https://appleid.apple.com' && claims.aud === clientID &&
    Number.isFinite(claims.exp) && claims.exp > Date.now() / 1000 &&
    typeof claims.sub === 'string' && claims.sub.length > 0 &&
    user.identities?.some(identity => identity.provider === 'apple' &&
      identity.identity_data?.sub === claims.sub) === true;
}

export async function revokeAppleAuthorization(config, proof, user, request = fetch) {
  if (!config || !/^[A-Z0-9]{10}$/.test(config.teamID ?? '') ||
      !/^[A-Z0-9]{10}$/.test(config.keyID ?? '') || !config.privateKey ||
      !Array.isArray(config.clientIDs) || config.clientIDs.length === 0) return 503;
  if (!config.clientIDs.includes(proof.client_id)) return 403;
  try {
    const secret = await clientSecret(config, proof.client_id);
    const options = { method: 'POST', redirect: 'error',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' } };
    const result = await request(appleURL + 'token', { ...options, signal: AbortSignal.timeout(10000),
      body: new URLSearchParams({ grant_type: 'authorization_code', code: proof.authorization_code,
        client_id: proof.client_id, client_secret: secret }).toString() });
    if (!result.ok) return result.status === 429 || result.status >= 500 ? 503 : 403;
    const tokens = await result.json();
    if (!matchesAppleIdentity(tokens.id_token, proof.client_id, user)) return 403;
    const refresh = typeof tokens.refresh_token === 'string' && tokens.refresh_token.length > 0;
    const token = refresh ? tokens.refresh_token : tokens.access_token;
    if (typeof token !== 'string' || !token || token.length > 8192) return 503;
    const revoked = await request(appleURL + 'revoke', { ...options, signal: AbortSignal.timeout(10000),
      body: new URLSearchParams({ client_id: proof.client_id, client_secret: secret, token,
        token_type_hint: refresh ? 'refresh_token' : 'access_token' }).toString() });
    return revoked.ok ? 200 : 503;
  } catch { return 503; }
}
