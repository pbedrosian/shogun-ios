import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { settings } from './local.mjs';
import { createDeleteHandler } from '../../backend/supabase/functions/delete-account/handler.mjs';

// Fixed local stack only. Provider consent is emulated with disposable fixtures.
// GoTrue issues/verifies real JWTs; Apple exchange/revocation is mocked, never live.
const args = process.argv.slice(2);
if (args.length && (args.length !== 2 || args[0] !== '--provider' || !['google','apple'].includes(args[1]))) {
  throw new Error('Use --provider google or --provider apple.');
}
const provider = args[1] ?? 'google';
const config = settings();
let appleSubject, failAppleRevocation = false;
const appleEvents = [];
let appleHandler;
if (provider === 'apple') {
  const keys = await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
  const privateKey = '-----BEGIN PRIVATE KEY-----\n' + Buffer.from(await crypto.subtle.exportKey('pkcs8',keys.privateKey)).toString('base64') + '\n-----END PRIVATE KEY-----';
  const clientID = 'com.petebedrosian.shogun.dev';
  appleHandler = createDeleteHandler({...config,apple:{teamID:'TESTTEAM00',keyID:'TESTKEY000',privateKey,clientIDs:[clientID]}},async(url,options)=>{
    if (url === 'https://appleid.apple.com/auth/token') {
      appleEvents.push('exchange');
      const claims = {iss:'https://appleid.apple.com',aud:clientID,sub:appleSubject,exp:Math.floor(Date.now()/1000)+300};
      return Response.json({id_token:'header.'+Buffer.from(JSON.stringify(claims)).toString('base64url')+'.signature',refresh_token:'disposable-apple-fixture-token'});
    }
    if (url === 'https://appleid.apple.com/auth/revoke') {
      appleEvents.push('revoke');return new Response(null,{status:failAppleRevocation?503:200});
    }
    // The remaining requests must stay on the fixed local Auth service.
    assert.equal(new URL(url).origin,config.url);
    return fetch(url,options);
  });
}
async function appleRemove(token, payload, status) {
  const response=await appleHandler(new Request(config.url+endpoint,{method:'POST',headers:{Authorization:'Bearer '+token},body:JSON.stringify(payload)}));
  assert.equal(response.status,status,'Local Apple deletion status');
  return response.json();
}
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
    const password = randomUUID() + 'Aa1!', email = `${provider}-delete-${randomUUID()}@example.test`;
    const user = await call(config.admin, '/auth/v1/admin/users', { method: 'POST', body: { email, password, email_confirm: true } });
    created.push(user.id);
    assert.match(user.id, /^[0-9a-f-]{36}$/);
    const subject = randomUUID();
    sql(`INSERT INTO auth.identities (provider_id,user_id,identity_data,provider,created_at,updated_at)
      VALUES ('${subject}','${user.id}','${JSON.stringify({ sub: subject, email, email_verified: true })}'::jsonb,'${provider}',now(),now());`);
    const login = () => call(config.anon, '/auth/v1/token?grant_type=password', { method: 'POST', body: { email, password } });
    accounts.push({ id: user.id, subject, email, password, session: await login(), proof: await login() });
  }
  const [owner, other] = accounts;
  appleSubject = owner.subject;
  const library = await call(owner.session.access_token, '/rest/v1/rpc/bootstrap_account', { method: 'POST' });
  movie = randomUUID();
  await call(owner.session.access_token, '/rest/v1/movies', { method: 'POST', status: 201, body: { id: movie, title: `Disposable ${provider} deletion verification` } });
  await call(owner.session.access_token, '/rest/v1/owned_copies', { method: 'POST', status: 201, body: { library_id: library, movie_id: movie, format: 'DVD' } });
  const remove = (proof, status) => provider === 'google'
    ? call(owner.session.access_token, endpoint, { method: 'POST', status, body: { reauthentication_token: proof.access_token } })
    : appleRemove(owner.session.access_token,{apple:{reauthentication_token:proof.access_token,authorization_code:randomUUID(),client_id:'com.petebedrosian.shogun.dev'}},status);
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
  if (provider === 'apple') {
    await appleRemove(owner.session.access_token,{password:owner.password},403);
    await appleRemove(owner.session.access_token,{reauthentication_token:owner.proof.access_token},403);
    assert.deepEqual(appleEvents,[]); // Rejected proofs never contacted even the mock provider.
    appleSubject = other.subject;
    await remove(owner.proof,403); // A code for a different Apple subject must not revoke/delete it.
    assert.deepEqual(appleEvents,['exchange']);
    appleSubject = owner.subject;
    owner.proof = await call(config.anon, '/auth/v1/token?grant_type=password', {method:'POST',body:{email:owner.email,password:owner.password}});
    owner.proof = await oauthProof(owner.proof);
    failAppleRevocation = true;
    await remove(owner.proof,503);
    assert.equal((await call(config.admin, `/auth/v1/admin/users/${owner.id}`)).id,owner.id);
    assert.equal((await call(config.admin, `/rest/v1/owned_copies?library_id=eq.${library}`)).length,1);
    owner.proof = await call(config.anon, '/auth/v1/token?grant_type=password', {method:'POST',body:{email:owner.email,password:owner.password}});
    owner.proof = await oauthProof(owner.proof);
    failAppleRevocation = false;
  }
  const result = await remove(owner.proof, 200);
  assert.equal(result.deleted, true);
  for (const [table, filter] of [['profiles', `id=eq.${owner.id}`], ['libraries', `owner_id=eq.${owner.id}`], ['owned_copies', `library_id=eq.${library}`]]) {
    assert.deepEqual(await call(config.admin, `/rest/v1/${table}?${filter}`), [], `${table} cascades`);
  }
  await call(config.admin, `/auth/v1/admin/users/${owner.id}`, { status: 404 });
  assert.equal((await call(config.admin, `/auth/v1/admin/users/${other.id}`)).id, other.id);
  if (provider === 'apple') {
    const before = appleEvents.length;
    await appleRemove(other.session.access_token,{apple_fallback:{password:'intentionally-wrong'}},403);
    assert.equal((await call(config.admin, `/auth/v1/admin/users/${other.id}`)).id,other.id);
    const fallback = await appleRemove(other.session.access_token,{apple_fallback:{password:other.password}},200);
    assert.equal(fallback.apple_revocation_required,true);
    await call(config.admin, `/auth/v1/admin/users/${other.id}`, {status:404});
    assert.equal(appleEvents.length,before); // Explicit fallback does not claim Apple revocation.
  }
  console.log(`Local ${provider} OAuth-proof deletion passed: tampered/revoked/wrong-account/password/stale/same-session rejected, fresh independent proof accepted, owned data removed, other account preserved. Provider consent is a separate device check; Apple protocol calls are mocked.`);
} finally {
  for (const id of created) {
    const response = await fetch(config.url + '/auth/v1/admin/users/' + id, { method: 'DELETE', headers: { apikey: config.admin, Authorization: `Bearer ${config.admin}` } });
    if (!response.ok && response.status !== 404) throw new Error('Disposable OAuth deletion fixture cleanup failed.');
  }
  if (movie) await call(config.admin, `/rest/v1/movies?id=eq.${movie}`, { method: 'DELETE' });
}
