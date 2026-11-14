// Real Auth/RLS/database, deterministic TMDB images. Refuses non-local stacks.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {settings} from './local.mjs';
import {createCatalogHandler} from '../../backend/supabase/functions/catalog/handler.mjs';
const c=settings(),movie=randomUUID(),provider=2147000081;
async function call(token,path,body,method='POST',status=200){
 const r=await fetch(c.url+path,{method,redirect:'error',signal:AbortSignal.timeout(15000),headers:{apikey:c.anon,Authorization:'Bearer '+token,'Content-Type':'application/json',Prefer:'return=representation'},body:body===undefined?undefined:JSON.stringify(body)});
 assert.equal(r.status,status,path.split('?')[0]);const text=await r.text();return text?JSON.parse(text):null;
}
const sessions={};
const handler=createCatalogHandler({url:c.url,anon:c.anon,admin:c.admin,tmdbToken:'fixture'},async(input,options)=>{
 const url=new URL(input);
 if(url.host==='api.themoviedb.org')return Response.json(url.pathname.endsWith('/images')
  ? {id:provider,posters:[{file_path:'/alternate.jpg',width:1000,height:1500,iso_639_1:'en'}]}
  : {id:provider,title:'Cover integration',release_date:'2026-01-01'});
 return fetch(input,options);
});
async function choose(user,path,status=200){
 const r=await handler(new Request(c.url+'/functions/v1/catalog',{method:'POST',headers:{Authorization:'Bearer '+sessions[user].access_token},body:JSON.stringify({operation:'set_cover',movieID:provider,path})}));
 assert.equal(r.status,status);
}
const snapshot=token=>call(token,'/rest/v1/rpc/collection_snapshot',{});
const film=s=>s.movies.find(m=>m.id===movie);
try{
 for(const name of ['owner','viewer'])sessions[name]=await call(c.anon,'/auth/v1/token?grant_type=password',{email:name+'@shogun.test',password:'Shogun-local-only-25!'});
 await call(c.admin,'/rest/v1/movies',{id:movie,source:'tmdb',tmdb_id:provider,title:'Cover integration',poster_path:'https://image.tmdb.org/t/p/w342/default.jpg'},'POST',201);
 await call(sessions.owner.access_token,'/rest/v1/rpc/save_movie_diary',{target_movie:movie,is_watched:true,personal_rating:5});
 const before=await snapshot(sessions.owner.access_token);
 await choose('owner','/foreign.jpg',400);
 await choose('owner','/alternate.jpg');await choose('owner','/alternate.jpg');
 const owner=await snapshot(sessions.owner.access_token),viewer=await snapshot(sessions.viewer.access_token);
 assert.equal(film(owner).cover_poster_path,'https://image.tmdb.org/t/p/w342/alternate.jpg');
 assert.equal(film(viewer).cover_poster_path,null);
 assert.equal(film(owner).poster_path,'https://image.tmdb.org/t/p/w342/default.jpg');
 assert.deepEqual(owner.states,before.states);assert.deepEqual(owner.copies,before.copies);
 const prefs=await call(sessions.owner.access_token,'/rest/v1/movie_cover_preferences?movie_id=eq.'+movie,undefined,'GET');
 assert.equal(prefs.length,1);
 assert.deepEqual(await call(sessions.viewer.access_token,'/rest/v1/movie_cover_preferences?movie_id=eq.'+movie,undefined,'GET'),[]);
 await call(sessions.viewer.access_token,'/rest/v1/movie_cover_preferences',{user_id:sessions.owner.user.id,movie_id:movie,poster_path:'/hijack.jpg'},'POST',403);
 await call(sessions.viewer.access_token,'/rest/v1/rpc/set_movie_cover',{actor:sessions.owner.user.id,provider_id:provider,poster_path:null},'POST',403);
 const fresh=await call(c.anon,'/auth/v1/token?grant_type=password',{email:'owner@shogun.test',password:'Shogun-local-only-25!'});
 assert.equal(film(await snapshot(fresh.access_token)).cover_poster_path,film(owner).cover_poster_path);
 await choose('viewer','/alternate.jpg');await choose('owner',null);await choose('owner',null);
 assert.equal(film(await snapshot(sessions.owner.access_token)).cover_poster_path,null);
 assert.equal(film(await snapshot(sessions.viewer.access_token)).cover_poster_path,'https://image.tmdb.org/t/p/w342/alternate.jpg');
 const library=before.libraries.find(l=>!l.is_shared).id;
 const intent={operation:'import',movieID:provider,requestID:randomUUID(),libraryID:library,formats:['4K UHD'],coverPath:'/alternate.jpg'};
 async function add(body,status=200){
  const r=await handler(new Request(c.url+'/functions/v1/catalog',{method:'POST',headers:{Authorization:'Bearer '+sessions.owner.access_token},body:JSON.stringify(body)}));
  assert.equal(r.status,status);return r.json();
 }
 await add({...intent,coverPath:'/foreign.jpg'},400);
 assert.equal((await snapshot(sessions.owner.access_token)).copies.filter(x=>x.movie_id===movie).length,0);
 await Promise.all([add(intent),add(intent)]);
 let added=await snapshot(sessions.owner.access_token);
 assert.equal(added.copies.filter(x=>x.movie_id===movie).length,1);
 assert.equal(film(added).cover_poster_path,'https://image.tmdb.org/t/p/w342/alternate.jpg');
 await choose('owner',null);
 await add(intent);
 assert.equal(film(await snapshot(sessions.owner.access_token)).cover_poster_path,null);
 await choose('owner','/alternate.jpg');
 await add({...intent,requestID:randomUUID(),coverPath:null});
 assert.equal(film(await snapshot(sessions.owner.access_token)).cover_poster_path,null);
 await choose('owner','/alternate.jpg');
 const legacy={...intent,requestID:randomUUID()};delete legacy.coverPath;
 await add(legacy);
 added=await snapshot(sessions.owner.access_token);
 assert.equal(film(added).cover_poster_path,'https://image.tmdb.org/t/p/w342/alternate.jpg');
 assert.equal(added.copies.filter(x=>x.movie_id===movie).length,3);
 assert.deepEqual(added.states,before.states);
 console.log('Cover integration passed: real JWT isolation, atomic add-time cover, concurrent retry deduplication, completed retry preserves later cover, legacy omission/default reset and durable relogin.');
}finally{
 await call(c.admin,'/rest/v1/owned_copies?movie_id=eq.'+movie,undefined,'DELETE');
 await call(c.admin,'/rest/v1/personal_movie_state?movie_id=eq.'+movie,undefined,'DELETE');
 await call(c.admin,'/rest/v1/movies?id=eq.'+movie,undefined,'DELETE');
}
