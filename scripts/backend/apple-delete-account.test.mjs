import test from 'node:test';
import assert from 'node:assert/strict';
import { createDeleteHandler } from '../../backend/supabase/functions/delete-account/handler.mjs';

// Ephemeral test key only. No Apple credentials or external services are used.
const keys = await crypto.subtle.generateKey({ name:'ECDSA', namedCurve:'P-256' }, true, ['sign','verify']);
const privateKey = '-----BEGIN PRIVATE KEY-----\n' + Buffer.from(await crypto.subtle.exportKey('pkcs8',keys.privateKey)).toString('base64') + '\n-----END PRIVATE KEY-----';
const clientID = 'com.petebedrosian.shogun.dev';
const apple = {teamID:'TESTTEAM00',keyID:'TESTKEY000',privateKey,clientIDs:[clientID]};
const env = {url:'https://auth.test',anon:'public-key',admin:'server-key',apple};
const owner = {id:'10000000-0000-0000-0000-000000000001',email:'relay@example.test',
 identities:[{provider:'apple',identity_data:{sub:'owner-apple-subject'}},{provider:'google'}]};
const now = Math.floor(Date.now()/1000);
const jwt = claims => 'header.'+Buffer.from(JSON.stringify(claims)).toString('base64url')+'.signature';
const original = jwt({session_id:'20000000-0000-0000-0000-000000000001'});
const fresh = overrides => jwt({sub:owner.id,role:'authenticated',aud:'authenticated',exp:now+3600,
 session_id:'20000000-0000-0000-0000-000000000002',amr:[{method:'oauth',timestamp:now}],...overrides});
const appleJWT = overrides => jwt({iss:'https://appleid.apple.com',aud:clientID,sub:'owner-apple-subject',exp:now+3600,...overrides});
const body = (token=fresh({})) => ({apple:{reauthentication_token:token,authorization_code:'single-use-test-code',client_id:clientID}});
const incoming = value => new Request('https://function.test',{method:'POST',headers:{Authorization:'Bearer '+original},body:JSON.stringify(value)});
function fixture(options={}) {
 const events=[];
 const handler=createDeleteHandler(options.env??env,async(url,init)=>{
  if(url===env.url+'/auth/v1/user') {
   const isOriginal=init.headers.Authorization==='Bearer '+original;
   return Response.json(isOriginal?owner:(options.proofUser??owner),{status:!isOriginal&&options.rejectProof?401:200});
  }
  if(url===env.url+'/auth/v1/token?grant_type=password') {
   events.push('password');const credentials=JSON.parse(init.body);
   assert.equal(credentials.email,owner.email);
   if(credentials.password!=='valid-password') return Response.json({}, {status:400});
   return Response.json({access_token:'fallback-password-session',user:options.passwordUser??owner});
  }
  if(url===env.url+'/auth/v1/logout?scope=local') {events.push('cleanup');return new Response(null,{status:204});}
  if(url==='https://appleid.apple.com/auth/token') {
   events.push('exchange');
   const data=new URLSearchParams(init.body);
   assert.equal(init.redirect,'error');
   assert.equal(data.get('client_id'),clientID);
   assert.equal(data.get('grant_type'),'authorization_code');
   assert.equal(data.get('code'),'single-use-test-code');
   const secret=data.get('client_secret').split('.');
   const header=JSON.parse(Buffer.from(secret[0],'base64url'));
   const claims=JSON.parse(Buffer.from(secret[1],'base64url'));
   assert.equal(header.alg,'ES256');assert.equal(header.kid,apple.keyID);
   assert.equal(claims.iss,apple.teamID);assert.equal(claims.sub,clientID);
   assert.equal(claims.aud,'https://appleid.apple.com');assert.equal(claims.exp-claims.iat,300);
   assert.equal(await crypto.subtle.verify({name:'ECDSA',hash:'SHA-256'},keys.publicKey,
    Buffer.from(secret[2],'base64url'),new TextEncoder().encode(secret[0]+'.'+secret[1])),true);
   if(options.failExchange) return Response.json({error:'invalid_grant'},{status:400});
   return Response.json({id_token:appleJWT(options.appleClaims??{}),
    ...(options.noToken?{}:options.accessOnly?{access_token:'apple-access'}:{refresh_token:'apple-refresh'})});
  }
  if(url==='https://appleid.apple.com/auth/revoke') {
   events.push('revoke');const data=new URLSearchParams(init.body);
   assert.equal(data.get('token'),options.accessOnly?'apple-access':'apple-refresh');
   assert.equal(data.get('token_type_hint'),options.accessOnly?'access_token':'refresh_token');
   assert.equal(init.redirect,'error');
   return new Response(null,{status:options.failRevoke?503:200});
  }
  assert.equal(url,env.url+'/auth/v1/admin/users/'+owner.id);
  events.push('delete');assert.equal(init.method,'DELETE');
  assert.equal(init.headers.Authorization,'Bearer server-key');
  return Response.json({},{status:options.failDeletion?503:200});
 });
 return {handler,events};
}

test('Apple deletion binds fresh same-user proof, revokes authorization, then deletes only that account',async()=>{
 for(const accessOnly of [false,true]) {
  const {handler,events}=fixture({accessOnly});const result=await handler(incoming(body()));
  assert.equal(result.status,200);assert.deepEqual(await result.json(),{deleted:true});
  assert.deepEqual(events,['exchange','revoke','delete','cleanup']);
 }
});
test('Apple-linked accounts reject implicit password or Google deletion without an explicit fallback choice',async()=>{
 for(const value of [{password:'password'},{reauthentication_token:fresh({})}]) {
  const {handler,events}=fixture();assert.equal((await handler(incoming(value))).status,403);
  assert.deepEqual(events,[]);
 }
});
test('Apple deletion rejects stale/same-session/wrong-user/unverified proof before contacting Apple',async()=>{
 for(const claims of [{amr:[{method:'oauth',timestamp:now-301}]},{role:'service_role'},
  {session_id:'20000000-0000-0000-0000-000000000001'},{sub:'another-user'},{exp:now-1},
  {amr:[{method:'password',timestamp:now}]}]) {
  const {handler,events}=fixture();assert.equal((await handler(incoming(body(fresh(claims))))).status,403);
  assert.deepEqual(events,[]);
 }
 for(const options of [{rejectProof:true},{proofUser:{...owner,id:'10000000-0000-0000-0000-000000000099'}},
  {proofUser:{...owner,identities:[]}}]) {
  const {handler,events}=fixture(options);assert.equal((await handler(incoming(body()))).status,403);
  assert.deepEqual(events,[]);
 }
});
test('Apple token exchange rejects wrong Apple subject, audience, issuer or expired token without revoking another identity',async()=>{
 for(const appleClaims of [{sub:'different-apple-subject'},{aud:'other.client'},{iss:'https://evil.test'},{exp:now-1}]) {
  const {handler,events}=fixture({appleClaims});assert.equal((await handler(incoming(body()))).status,403);
  assert.deepEqual(events,['exchange','cleanup']);
 }
});
test('Apple missing configuration, disallowed client and provider failures preserve the account and clean temporary proof',async()=>{
 for(const [options,status,expected] of [
  [{env:{...env,apple:undefined}},503,['cleanup']],
  [{env:{...env,apple:{...apple,clientIDs:['other.client']}}},403,['cleanup']],
  [{env:{...env,apple:{...apple,privateKey:'invalid'}}},503,['cleanup']],
  [{failExchange:true},403,['exchange','cleanup']],
  [{noToken:true},503,['exchange','cleanup']],
  [{failRevoke:true},503,['exchange','revoke','cleanup']],
  [{failDeletion:true},503,['exchange','revoke','delete','cleanup']],
 ]) {
  const {handler,events}=fixture(options);const result=await handler(incoming(body()));
  assert.equal(result.status,status);assert.deepEqual(events,expected);
  const response=await result.text();assert.equal(response.includes('apple-refresh'),false);
  assert.equal(response.includes('PRIVATE KEY'),false);
 }
});
test('Apple deletion rejects malformed and ambiguous proof bodies before any privileged operation',async()=>{
 for(const value of [
  {apple:{...body().apple,authorization_code:''}}, {apple:{...body().apple,authorization_code:'x'.repeat(2049)}},
  {apple:{...body().apple,client_id:'https://evil.test'}}, {apple:{...body().apple,user_id:owner.id}},
  {apple:body().apple,password:'password'}, {apple:'invalid'}, {apple:[]},
 ]) {
  const {handler,events}=fixture();assert.equal((await handler(incoming(value))).status,400);
  assert.deepEqual(events,[]);
 }
});

test('Explicit Apple-unavailable fallback requires current password and reports manual Apple removal',async()=>{
 const {handler,events}=fixture();const result=await handler(incoming({apple_fallback:{password:'valid-password'}}));
 assert.equal(result.status,200);assert.deepEqual(await result.json(),{deleted:true,apple_revocation_required:true});
 assert.deepEqual(events,['password','delete','cleanup']);
 for(const [options,password] of [[{},'wrong-password'],[{passwordUser:{...owner,id:'another-user'}},'valid-password']]) {
  const {handler,events}=fixture(options);
  assert.equal((await handler(incoming({apple_fallback:{password}}))).status,403);
  assert.equal(events.includes('delete'),false);assert.equal(events.includes('exchange'),false);
 }
 for(const value of [{apple_fallback:{password:''}},{apple_fallback:{password:'x'.repeat(4097)}},
  {apple_fallback:{password:'valid-password',user_id:owner.id}}]) {
  const {handler,events}=fixture();assert.equal((await handler(incoming(value))).status,400);assert.deepEqual(events,[]);
 }
});
