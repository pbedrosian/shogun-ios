// Real-JWT SHO-3 checks; preserves existing data and cleans only UUID-scoped test rows.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {settings} from './local.mjs';
const config=settings();
const library=randomUUID(), importedLibrary=randomUUID(), films=new Set(), sessions={};
async function request(token,path,body,{method='POST',status=200}={}) {
  const response=await fetch(config.url+path,{method,redirect:'error',signal:AbortSignal.timeout(20000),
    headers:{apikey:config.anon,Authorization:'Bearer '+token,'Content-Type':'application/json',Prefer:'return=representation'},
    body:body===undefined?undefined:JSON.stringify(body)});
  assert.equal(response.status,status,`${method} ${path.split('?')[0]} status`);
  const text=await response.text(); return text?JSON.parse(text):null;
}
const rpc=(who,name,body,status=200)=>request(sessions[who].access_token,'/rest/v1/rpc/'+name,body,{status});
try {
  for(const who of ['owner','editor','viewer','outsider']) {
    sessions[who]=await request(config.anon,'/auth/v1/token?grant_type=password',{email:who+'@shogun.test',password:'Shogun-local-only-25!'});
  }
  await rpc('owner','create_collection_library',{request_id:library,library_name:'SHO-3 integration'});
  await request(sessions.owner.access_token,'/rest/v1/library_memberships',[
    {library_id:library,user_id:sessions.editor.user.id,role:'editor'},
    {library_id:library,user_id:sessions.viewer.user.id,role:'viewer'},
  ],{status:201});
  const body={request_id:randomUUID(),target_library:library,metadata:{title:'SHO-3 '+randomUUID(),year:2026,director:'Manual director',synopsis:'Manual story',runtimeMinutes:117,genres:['Drama','Mystery'],posterURL:'https://example.com/poster.jpg'},copy_formats:['DVD','DVD','Blu-ray']};
  await request(config.anon,'/rest/v1/rpc/add_manual_movie',body,{status:401});
  const saved=await Promise.all([rpc('owner','add_manual_movie',body),rpc('owner','add_manual_movie',body)]);
  assert.equal(saved[0],saved[1]);films.add(saved[0]);
  await rpc('owner','add_manual_movie',{...body,copy_formats:['VHS']},400);
  for(const who of ['viewer','outsider']) await rpc(who,'add_manual_movie',{...body,request_id:randomUUID()},403);
  const snapshot=await rpc('owner','collection_snapshot',{});
  assert.equal(snapshot.copies.filter(c=>c.library_id===library).length,3);
  const film=snapshot.movies.find(m=>m.id===saved[0]);
  assert.equal(film.director,'Manual director');assert.equal(film.runtime_minutes,117);
  assert.deepEqual(film.genres,['Drama','Mystery']);assert.equal(film.poster_path,'https://example.com/poster.jpg');
  const expected=snapshot.copies.filter(c=>c.library_id===library && c.movie_id===saved[0])
    .map(c=>({id:c.id,format:c.format})).sort((a,b)=>a.id.localeCompare(b.id));
  const edit={target_library:library,target_movie:saved[0],expected_copies:expected,copy_formats:['DVD','4K UHD']};
  await rpc('owner','edit_collection_copies',edit);
  await rpc('owner','edit_collection_copies',edit);
  await rpc('owner','edit_collection_copies',{...edit,copy_formats:['VHS']},409);
  await rpc('viewer','edit_collection_copies',edit,403);
  await rpc('outsider','edit_collection_copies',edit,403);
  const edited=await rpc('owner','collection_snapshot',{});
  assert.equal(edited.copies.filter(c=>c.library_id===library && c.movie_id===saved[0]).length,2);
  assert.deepEqual(edited.movies.find(m=>m.id===saved[0]),film,'copy edits preserve movie metadata');
  const editorBody={...body,request_id:randomUUID()};
  const editorFilm=await rpc('editor','add_manual_movie',editorBody); films.add(editorFilm);
  assert.notEqual(editorFilm,saved[0],'manual titles never silently deduplicate');
  await request(sessions.owner.access_token,`/rest/v1/library_memberships?library_id=eq.${library}&user_id=eq.${sessions.editor.user.id}`,undefined,{method:'DELETE'});
  await rpc('editor','add_manual_movie',editorBody,403);
  const failedTitle='invalid '+randomUUID();
  await rpc('owner','add_manual_movie',{...body,request_id:randomUUID(),metadata:{title:failedTitle,year:1}},400);
  assert.ok(!(await rpc('owner','collection_snapshot',{})).movies.some(m=>m.title===failedTitle));
  await rpc('owner','import_catalog_movie',{actor:sessions.owner.user.id,request_id:randomUUID(),target_library:library,metadata:body.metadata,copy_formats:['DVD'],provider_id:2147000001},403);
  // A trusted provider import is checked separately through live Auth + the Edge boundary.
  if(process.argv.includes('--live')) {
    await rpc('owner','create_collection_library',{request_id:importedLibrary,library_name:'SHO-3 provider integration'});
    const before=(await rpc('owner','collection_snapshot',{})).movies.find(m=>m.tmdb_id===329865);
    const importBody={operation:'import',movieID:329865,requestID:randomUUID(),libraryID:importedLibrary,formats:['4K UHD','4K UHD']};
    const imported=await request(sessions.owner.access_token,'/functions/v1/catalog',importBody);
    if(!before) films.add(imported.movieID);
    assert.equal((await request(sessions.owner.access_token,'/functions/v1/catalog',importBody)).movieID,imported.movieID);
    if(before) assert.equal(imported.movieID,before.id);
    const after=await rpc('owner','collection_snapshot',{});
    assert.equal(after.movies.find(m=>m.id===imported.movieID).tmdb_id,329865);
    assert.equal(after.copies.filter(c=>c.library_id===importedLibrary).length,2);
    await request(sessions.outsider.access_token,'/functions/v1/catalog',{...importBody,requestID:randomUUID()}, {status:403});
    console.log('Live TMDB import passed: server metadata, stable UUID, multiple copies, retries and denied writes.');
  }
  console.log('Movie add RPC checks passed: atomic metadata/copies, concurrent retries, quantity, manual identity, writable roles and revocation.');
} finally {
  for(const path of [`libraries?id=in.(${library},${importedLibrary})`,...Array.from(films,id=>'movies?id=eq.'+id)]) {
    const response=await fetch(config.url+'/rest/v1/'+path,{method:'DELETE',redirect:'error',signal:AbortSignal.timeout(15000),headers:{apikey:config.admin,Authorization:'Bearer '+config.admin}});
    assert.ok(response.ok,'cleanup test rows');
  }
}
