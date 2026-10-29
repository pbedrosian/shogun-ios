// Exercise the real REST gateway with signed JWTs, not the service role.
// The service role is used only to remove resources created by this test.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { settings } from './local.mjs';

const config = settings();
const movie = randomUUID();
let library;
async function call(token, endpoint, { method = 'GET', body, status = 200 } = {}) {
  const response = await fetch(config.url + endpoint, {
    method, redirect:'error', signal:AbortSignal.timeout(15_000),
    headers:{apikey:config.anon, Authorization:`Bearer ${token}`, 'Content-Type':'application/json', Prefer:'return=representation'},
    body:body === undefined ? undefined : JSON.stringify(body),
  });
  assert.equal(response.status,status,`${method} ${endpoint.split('?')[0]} status`);
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

try {
  const sessions = {};
  for (const name of ['owner','editor','viewer','outsider']) {
    const session = await call(config.anon,'/auth/v1/token?grant_type=password', {
      method:'POST',body:{email:`${name}@shogun.test`,password:'Shogun-local-only-25!'},
    });
    sessions[name] = {token:session.access_token,id:session.user.id};
  }
  const {owner,editor,viewer,outsider} = sessions;
  library = await call(owner.token,'/rest/v1/rpc/create_shared_library', {method:'POST',body:{library_name:'REST permission test'}});
  assert.equal(typeof library,'string');
  await call(owner.token,'/rest/v1/library_memberships', {method:'POST',status:201,body:[
    {library_id:library,user_id:editor.id,role:'editor'},
    {library_id:library,user_id:viewer.id,role:'viewer'},
  ]});
  await call(owner.token,'/rest/v1/movies',{method:'POST',status:201,body:{id:movie,title:'REST test manual movie'}});
  const copy = {library_id:library,movie_id:movie,format:'DVD'};
  const firstCopy = randomUUID();
  await call(owner.token,'/rest/v1/owned_copies',{method:'POST',status:201,body:[{...copy,id:firstCopy},{...copy,id:randomUUID()}]});
  await call(owner.token,'/rest/v1/owned_copies',{method:'POST',status:409,body:{...copy,id:firstCopy}});
  assert.equal((await call(viewer.token,`/rest/v1/owned_copies?library_id=eq.${library}`)).length,2);
  assert.equal((await call(outsider.token,`/rest/v1/owned_copies?library_id=eq.${library}`)).length,0);
  await call(config.anon,'/rest/v1/libraries',{status:401});
  await call(viewer.token,'/rest/v1/owned_copies',{method:'POST',status:403,body:copy});
  await call(editor.token,'/rest/v1/owned_copies',{method:'POST',status:201,body:copy});
  assert.deepEqual(await call(viewer.token,`/rest/v1/owned_copies?library_id=eq.${library}`,{method:'DELETE'}),[]);
  assert.equal((await call(owner.token,`/rest/v1/owned_copies?library_id=eq.${library}`)).length,3);
  assert.deepEqual(await call(editor.token,`/rest/v1/libraries?id=eq.${library}`,{method:'PATCH',body:{name:'Hijack'}}),[]);
  await call(owner.token,'/rest/v1/library_memberships',{method:'POST',status:403,body:{library_id:library,user_id:outsider.id,role:'owner'}});
  await call(owner.token,'/rest/v1/personal_movie_state',{method:'POST',status:201,body:{movie_id:movie,watched:true,rating:5}});
  assert.deepEqual(await call(editor.token,`/rest/v1/personal_movie_state?movie_id=eq.${movie}`),[]);
  await call(editor.token,'/rest/v1/personal_movie_state',{method:'POST',status:201,body:{movie_id:movie,rating:3}});
  await call(editor.token,`/rest/v1/personal_movie_state?movie_id=eq.${movie}`,{method:'PATCH',status:400,body:{rating:6}});
  await call(editor.token,`/rest/v1/personal_movie_state?movie_id=eq.${movie}`,{method:'PATCH',body:{rating:null}});
  await call(editor.token,`/rest/v1/owned_copies?library_id=eq.${library}`,{method:'PATCH',status:403,body:{movie_id:randomUUID()}});
  await call(owner.token,`/rest/v1/library_memberships?library_id=eq.${library}&user_id=eq.${editor.id}`,{method:'DELETE'});
  assert.equal((await call(editor.token,`/rest/v1/owned_copies?library_id=eq.${library}`)).length,0);
  await call(editor.token,'/rest/v1/owned_copies',{method:'POST',status:403,body:copy});
  assert.equal((await call(editor.token,`/rest/v1/personal_movie_state?movie_id=eq.${movie}`)).length,1);
  console.log('REST permission tests passed: real owner/editor/viewer/outsider JWTs, repeated copies, denied writes, private diary, bounds and revocation.');
} finally {
  // UUID filters ensure cleanup cannot remove unrelated local data.
  for (const endpoint of [
    ...(library ? [`libraries?id=eq.${library}`] : []),
    `personal_movie_state?movie_id=eq.${movie}`, `movies?id=eq.${movie}`,
  ]) {
    const response = await fetch(config.url+'/rest/v1/'+endpoint, {method:'DELETE',redirect:'error',
      signal:AbortSignal.timeout(15_000), headers:{apikey:config.admin,Authorization:`Bearer ${config.admin}`}});
    if (!response.ok) throw new Error('Could not clean up a local permission-test resource.');
  }
}
