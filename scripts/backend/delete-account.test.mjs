import test from 'node:test';
import assert from 'node:assert/strict';
import { createDeleteHandler } from '../../backend/supabase/functions/delete-account/handler.mjs';
const env = { url: 'https://auth.test', anon: 'public-key', admin: 'server-key' };
const user = { id: '10000000-0000-0000-0000-000000000001', email: 'test@example.test' };
const incoming = (body = { password: 'password' }, token = 'session-token') => new Request('https://function.test', { method: 'POST', headers: token ? { Authorization: `Bearer ${token}` } : {}, body: JSON.stringify(body) });
test('rejects missing/invalid sessions and untrusted target IDs before deletion', async () => {
 let calls=0;const handler=createDeleteHandler(env,async()=>{calls++;return Response.json({}, {status:401});});
 assert.equal((await handler(incoming({},null))).status,401);
 assert.equal((await handler(incoming({password:'password',user_id:user.id}))).status,400);
 assert.equal((await handler(incoming())).status,401); assert.equal(calls,1);
 assert.equal((await handler(new Request('https://function.test'))).status,405);
});
test('requires current password for the verified user and never deletes on failed verification', async () => {
 let calls=0;const handler=createDeleteHandler(env,async(url,options)=>{calls++;
  if(url.endsWith('/user')) return Response.json(user);
  assert.equal(JSON.parse(options.body).email,user.email);
  return Response.json({}, {status:400});
 });
 assert.equal((await handler(incoming())).status,403);assert.equal(calls,2);
});
test('hard-deletes only the authenticated user using server-side credentials', async () => {
 const handler=createDeleteHandler(env,async(url,options)=>{
  if(url.endsWith('/user')) {assert.equal(options.headers.Authorization,'Bearer session-token');return Response.json(user);}
  if(url.includes('/token?')) return Response.json({user});
  assert.equal(url,env.url+'/auth/v1/admin/users/'+user.id);assert.equal(options.method,'DELETE');
  assert.equal(options.headers.Authorization,'Bearer server-key');assert.deepEqual(JSON.parse(options.body),{should_soft_delete:false});
  return Response.json({});
 });
 const r=await handler(incoming());assert.equal(r.status,200);assert.deepEqual(await r.json(),{deleted:true});
});
test('fails closed for mismatched reauthentication, upstream failure, malformed input and missing configuration', async () => {
 const mismatch=createDeleteHandler(env,async url=>Response.json(url.endsWith('/user')?user:{user:{id:'different-user'}}));
 assert.equal((await mismatch(incoming())).status,403);
 const broken=createDeleteHandler(env,async()=>{throw new Error('private server details');});
 const response=await broken(incoming());assert.equal(response.status,503);assert.equal((await response.text()).includes('private'),false);
 assert.equal((await broken(incoming({password:''}))).status,400);
 assert.equal((await broken(incoming({password:'x'.repeat(5000)}))).status,400);
 assert.equal((await createDeleteHandler({})(incoming())).status,503);
});
test('revokes temporary reauthentication session if administrative deletion fails', async () => {
 let revoked=false;
 const handler=createDeleteHandler(env,async(url,options)=>{
  if(url.endsWith('/user')) return Response.json(user);
  if(url.includes('/token?')) return Response.json({user,access_token:'temporary-verification-token'});
  if(url.includes('/admin/users/')) return Response.json({}, {status:503});
  assert.equal(url,env.url+'/auth/v1/logout?scope=local');
  assert.equal(options.headers.Authorization,'Bearer temporary-verification-token');revoked=true;
  return new Response(null,{status:204});
 });
 assert.equal((await handler(incoming())).status,503);assert.equal(revoked,true);
});

const now = Math.floor(Date.now()/1000);
const originalSession = '20000000-0000-0000-0000-000000000001';
const freshSession = '20000000-0000-0000-0000-000000000002';
const jwt = claims => 'header.'+Buffer.from(JSON.stringify(claims)).toString('base64url')+'.signature';
const original = jwt({session_id:originalSession});
const googleUser = {...user,identities:[{provider:'google'}]};
const googleProof = overrides => jwt({sub:user.id,iss:env.url+'/auth/v1',aud:'authenticated',role:'authenticated',
 exp:now+3600,session_id:freshSession,amr:[{method:'oauth',timestamp:now}],...overrides});
function googleHandler(proof,{freshUser=googleUser,rejectFresh=false,failDeletion=false}={}) {
 const state={deleted:false,revoked:false};
 const handler=createDeleteHandler(env,async(url,options)=>{
  if(url.endsWith('/user')) {
   if(options.headers.Authorization==='Bearer '+original) return Response.json(user);
   assert.equal(options.headers.Authorization,'Bearer '+proof);
   return Response.json(freshUser,{status:rejectFresh?401:200});
  }
  if(url.includes('/logout?')) {state.revoked=true;return new Response(null,{status:204});}
  assert.equal(url,env.url+'/auth/v1/admin/users/'+user.id);
  assert.equal(options.method,'DELETE');state.deleted=true;
  return Response.json({}, {status:failDeletion?503:200});
 });
 return {state,handler};
}
test('Google deletion validates a fresh independent OAuth session for exactly the current user',async()=>{
 const proof=googleProof({});const {state,handler}=googleHandler(proof);
 assert.equal((await handler(incoming({reauthentication_token:proof},original))).status,200);
 assert.equal(state.deleted,true);assert.equal(state.revoked,true);
});
test('Google deletion rejects stale, refreshed-old, same-session, wrong-method and invalid claims',async()=>{
 for(const overrides of [
  {amr:[{method:'oauth',timestamp:now-301}]},
  {iat:now,amr:[{method:'oauth',timestamp:now-3600}]},
  {amr:[{method:'oauth',timestamp:now+60}]},
  {amr:[{method:'password',timestamp:now}]}, {amr:[]}, {amr:null},
  {session_id:originalSession}, {session_id:'invalid'}, {sub:'other-user'},
  {role:'service_role'}, {aud:'anon'}, {exp:now-1},
 ]) {
  const proof=googleProof(overrides);const {state,handler}=googleHandler(proof);
  assert.equal((await handler(incoming({reauthentication_token:proof},original))).status,403);
  assert.equal(state.deleted,false);
  assert.equal(state.revoked,false); // Invalid proof must not revoke the main or an unrelated session.
 }
});
test('Google deletion rejects wrong accounts, unsigned/rejected proof and missing Google identity',async()=>{
 for(const options of [{freshUser:{...googleUser,id:'10000000-0000-0000-0000-000000000002'}},
  {rejectFresh:true},{freshUser:user}]) {
  const proof=googleProof({});const {state,handler}=googleHandler(proof,options);
  assert.equal((await handler(incoming({reauthentication_token:proof},original))).status,403);
  assert.equal(state.deleted,false);
 }
 const {state,handler}=googleHandler('malformed');
 assert.equal((await handler(incoming({reauthentication_token:'malformed'},original))).status,403);
 assert.equal(state.deleted,false);
});
test('Google deletion rejects ambiguous or oversized bodies and cleans proof after upstream failure',async()=>{
 const proof=googleProof({});const {state,handler}=googleHandler(proof,{failDeletion:true});
 assert.equal((await handler(incoming({reauthentication_token:proof,password:'password'},original))).status,400);
 assert.equal((await handler(incoming({reauthentication_token:proof,user_id:user.id},original))).status,400);
 assert.equal((await handler(incoming({reauthentication_token:'x'.repeat(8193)},original))).status,400);
 assert.equal((await handler(incoming({reauthentication_token:proof},original))).status,503);
 assert.equal(state.revoked,true);
});

test('rejects oversized streaming bodies before buffering or contacting Auth', async()=>{
 let cancelled=false,called=false;
 const body=new ReadableStream({
  start(controller){controller.enqueue(new Uint8Array(12289).fill(32));},
  cancel(){cancelled=true;},
 });
 const handler=createDeleteHandler(env,async()=>{called=true;throw new Error('must not contact Auth');});
 const request=new Request('https://function.test',{method:'POST',duplex:'half',headers:{Authorization:'Bearer session-token','Content-Length':'1'},body});
 assert.equal((await handler(request)).status,400);
 assert.equal(cancelled,true);assert.equal(called,false);
});
