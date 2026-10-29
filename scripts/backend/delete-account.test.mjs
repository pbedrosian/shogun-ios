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
