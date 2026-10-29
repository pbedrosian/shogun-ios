// Real JWT integration checks for the exact RPCs consumed by iOS. Local stack only.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { settings } from './local.mjs';
const config = settings();
const library = randomUUID(), movie = randomUUID(), copy = randomUUID();
const sessions = {};
let previousDefault;
async function request(token, path, { method = 'POST', body, status = 200 } = {}) {
  const response = await fetch(config.url + path, {
    method, redirect: 'error', signal: AbortSignal.timeout(15000),
    headers: { apikey: config.anon, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', Prefer: 'return=representation' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  assert.equal(response.status, status, `${method} ${path.split('?')[0]} status`);
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}
const rpc = (user, name, body = {}, status = 200) => request(sessions[user].access_token, '/rest/v1/rpc/' + name, { body, status });
try {
  for (const name of ['owner','editor','viewer','outsider']) {
    sessions[name] = await request(config.anon, '/auth/v1/token?grant_type=password', {
      body: { email: `${name}@shogun.test`, password: 'Shogun-local-only-25!' },
    });
  }
  previousDefault = (await rpc('editor','collection_snapshot')).default_library_id;
  await request(config.anon, '/rest/v1/rpc/collection_snapshot', { body: {}, status: 401 });
  for (let i = 0; i < 2; i++) {
    assert.equal(await rpc('owner','create_collection_library',{request_id: library, library_name: 'Collection sync integration'}), library);
  }
  await rpc('outsider','create_collection_library',{request_id: library, library_name: 'Collection sync integration'},403);
  await request(sessions.owner.access_token, '/rest/v1/library_memberships', { status: 201, body: [
    {library_id:library,user_id:sessions.editor.user.id,role:'editor'},
    {library_id:library,user_id:sessions.viewer.user.id,role:'viewer'},
  ] });
  await request(sessions.owner.access_token, '/rest/v1/movies', { status:201, body:{id:movie,title:'Collection sync film',release_year:2026} });
  const body = { copy_id:copy,target_library:library,target_movie:movie,copy_format:'Blu-ray' };
  // Concurrent retries resolve to one row; intentionally new UUIDs remain separate copies.
  await Promise.all([rpc('owner','save_collection_copy',body), rpc('owner','save_collection_copy',body)]);
  await rpc('editor','save_collection_copy',{...body,copy_id:randomUUID()});
  await rpc('viewer','save_collection_copy',{...body,copy_id:randomUUID()},403);
  await rpc('outsider','save_collection_copy',body,403);
  let snapshot = await rpc('editor','collection_snapshot');
  assert.equal(snapshot.copies.filter(c=>c.library_id===library).length,2);
  assert.equal(snapshot.movies.find(m=>m.id===movie).title,'Collection sync film');
  assert.ok(!snapshot.states.some(s=>s.user_id!==sessions.editor.user.id));
  assert.ok(!(await rpc('outsider','collection_snapshot')).libraries.some(l=>l.id===library));
  await rpc('owner','save_movie_diary',{target_movie:movie,is_watched:true,personal_rating:5});
  assert.ok(!(await rpc('editor','collection_snapshot')).states.some(s=>s.movie_id===movie));
  await rpc('editor','save_movie_diary',{target_movie:movie,is_watched:true,personal_rating:3});
  await rpc('editor','save_movie_diary',{target_movie:movie,is_watched:false,personal_rating:null});
  snapshot = await rpc('editor','collection_snapshot');
  assert.equal(snapshot.states.find(s=>s.movie_id===movie).rating,null);
  assert.equal(snapshot.states.find(s=>s.movie_id===movie).watched,false);
  await rpc('editor','save_movie_diary',{target_movie:movie,is_watched:true,personal_rating:6},400);
  await rpc('editor','set_default_library',{target_library:library});
  assert.equal((await rpc('editor','collection_snapshot')).default_library_id,library);
  await rpc('viewer','set_default_library',{target_library:library},403);
  // Fresh sign-in represents another device/relaunch reading the same durable rows.
  const fresh = await request(config.anon,'/auth/v1/token?grant_type=password',{body:{email:'editor@shogun.test',password:'Shogun-local-only-25!'}});
  const second = await request(fresh.access_token,'/rest/v1/rpc/collection_snapshot',{body:{}});
  assert.equal(second.default_library_id,library);
  assert.equal(second.copies.filter(c=>c.library_id===library).length,2);
  await request(sessions.owner.access_token,`/rest/v1/library_memberships?library_id=eq.${library}&user_id=eq.${sessions.editor.user.id}`,{method:'DELETE'});
  snapshot = await rpc('editor','collection_snapshot');
  assert.equal(snapshot.default_library_id,null);
  assert.ok(!snapshot.libraries.some(l=>l.id===library));
  assert.ok(!snapshot.copies.some(c=>c.library_id===library));
  assert.ok(snapshot.states.some(s=>s.movie_id===movie));
  await rpc('editor','save_collection_copy',body,403);
  await rpc('editor','set_default_library',{target_library:library},403);
  console.log('Collection RPC checks passed: durable reload, real JWT isolation, concurrent retry deduplication, private diary, defaults and revocation.');
} finally {
  if (sessions.editor && previousDefault !== undefined) {
    await rpc('editor','set_default_library',{target_library:previousDefault});
  }
  for (const path of [`libraries?id=eq.${library}`,`personal_movie_state?movie_id=eq.${movie}`,`movies?id=eq.${movie}`]) {
    const response = await fetch(config.url+'/rest/v1/'+path,{method:'DELETE',redirect:'error',signal:AbortSignal.timeout(15000),
      headers:{apikey:config.admin,Authorization:`Bearer ${config.admin}`}});
    if (!response.ok) throw new Error('Could not clean up collection test resources.');
  }
}
