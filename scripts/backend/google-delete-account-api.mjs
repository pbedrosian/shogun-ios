import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { settings } from './local.mjs';

// Fixed local stack only. Google itself is not contacted: disposable Auth fixtures
// model a completed OAuth login, while GoTrue issues and validates real JWTs.
const config = settings();
const created = [];
let movie;
const endpoint = '/functions/v1/delete-account';
async function call(token, path, { method = 'GET', body, status = 200 } = {}) {
  const response = await fetch(config.url + path, {
    method, redirect: 'error', signal: AbortSignal.timeout(20000),
    headers: { apikey: config.anon, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', Prefer: 'return=representation' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  assert.equal(response.status, status, `${method} ${path.split('?')[0]}`);
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}
function sql(statement) {
  try {
    execFileSync('docker', ['exec', 'supabase_db_shogun-local', 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', statement],
      { stdio: ['ignore', 'pipe', 'pipe'] });
  } catch { throw new Error('Disposable local OAuth fixture setup failed.'); }
}
function sessionID(session) {
  const id = JSON.parse(Buffer.from(session.access_token.split('.')[1], 'base64url')).session_id;
  assert.match(id, /^[0-9a-f-]{36}$/);
  return id;
}
async function oauthProof(session, age = 0) {
  const id = sessionID(session);
  sql(`DELETE FROM auth.mfa_amr_claims WHERE session_id='${id}';
    INSERT INTO auth.mfa_amr_claims (id,session_id,authentication_method,created_at,updated_at)
    VALUES (gen_random_uuid(),'${id}','oauth',now()-interval '${age} seconds',now()-interval '${age} seconds');`);
  return call(config.anon, '/auth/v1/token?grant_type=refresh_token', { method: 'POST', body: { refresh_token: session.refresh_token } });
}
try {
  const accounts = [];
  for (let i = 0; i < 2; i++) {
    const password = randomUUID() + 'Aa1!', email = `google-delete-${randomUUID()}@example.test`;
    const user = await call(config.admin, '/auth/v1/admin/users', { method: 'POST', body: { email, password, email_confirm: true } });
    created.push(user.id);
    assert.match(user.id, /^[0-9a-f-]{36}$/);
    const subject = randomUUID();
    sql(`INSERT INTO auth.identities (provider_id,user_id,identity_data,provider,created_at,updated_at)
      VALUES ('${subject}','${user.id}','${JSON.stringify({ sub: subject, email, email_verified: true })}'::jsonb,'google',now(),now());`);
    const login = () => call(config.anon, '/auth/v1/token?grant_type=password', { method: 'POST', body: { email, password } });
    accounts.push({ id: user.id, email, password, session: await login(), proof: await login() });
  }
  const [owner, other] = accounts;
  const library = await call(owner.session.access_token, '/rest/v1/rpc/bootstrap_account', { method: 'POST' });
  movie = randomUUID();
  await call(owner.session.access_token, '/rest/v1/movies', { method: 'POST', status: 201, body: { id: movie, title: 'Disposable Google deletion verification' } });
  await call(owner.session.access_token, '/rest/v1/owned_copies', { method: 'POST', status: 201, body: { library_id: library, movie_id: movie, format: 'DVD' } });
  const remove = (proof, status) => call(owner.session.access_token, endpoint, { method: 'POST', status, body: { reauthentication_token: proof.access_token } });
  const parts = owner.proof.access_token.split('.');
  parts[2] = (parts[2][0] === 'A' ? 'B' : 'A') + parts[2].slice(1);
  await remove({access_token:parts.join('.')}, 403); // Tampered signatures cannot authorize deletion.
  await remove(other.proof, 403);
  await remove(owner.proof, 403); // Password proof cannot substitute for OAuth.
  const same = await oauthProof(owner.session);
  await remove(same, 403); // Even a fresh proof cannot reuse the main session.
  owner.proof = await oauthProof(owner.proof, 600);
  await remove(owner.proof, 403); // Refreshing does not make an old authentication recent.
  owner.proof = await oauthProof(owner.proof);
  await call(owner.proof.access_token, '/auth/v1/logout?scope=local', {method:'POST',status:204});
  await remove(owner.proof, 403); // A signed-out proof must not authorize a destructive action.
  owner.proof = await call(config.anon, '/auth/v1/token?grant_type=password', {method:'POST',body:{email:owner.email,password:owner.password}});
  owner.proof = await oauthProof(owner.proof);
  const result = await remove(owner.proof, 200);
  assert.equal(result.deleted, true);
  for (const [table, filter] of [['profiles', `id=eq.${owner.id}`], ['libraries', `owner_id=eq.${owner.id}`], ['owned_copies', `library_id=eq.${library}`]]) {
    assert.deepEqual(await call(config.admin, `/rest/v1/${table}?${filter}`), [], `${table} cascades`);
  }
  await call(config.admin, `/auth/v1/admin/users/${owner.id}`, { status: 404 });
  assert.equal((await call(config.admin, `/auth/v1/admin/users/${other.id}`)).id, other.id);
  console.log('Local OAuth-proof deletion passed: tampered/revoked/wrong-account/password/stale/same-session rejected, fresh independent proof accepted, owned data removed, other account preserved. Google browser consent is a separate device check.');
} finally {
  for (const id of created) {
    const response = await fetch(config.url + '/auth/v1/admin/users/' + id, { method: 'DELETE', headers: { apikey: config.admin, Authorization: `Bearer ${config.admin}` } });
    if (!response.ok && response.status !== 404) throw new Error('Disposable Google deletion fixture cleanup failed.');
  }
  if (movie) await call(config.admin, `/rest/v1/movies?id=eq.${movie}`, { method: 'DELETE' });
}
