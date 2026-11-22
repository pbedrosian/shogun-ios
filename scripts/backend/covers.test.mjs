import test from 'node:test';
import assert from 'node:assert/strict';
import {createCatalogHandler} from '../../backend/supabase/functions/catalog/handler.mjs';
import {createTMDBClient} from '../../backend/supabase/functions/catalog/tmdb.mjs';
const user={id:'10000000-0000-0000-0000-000000000001'};
const env={url:'http://auth.local',anon:'anon',admin:'admin',tmdbToken:'tmdb'};
const poster=(path,language='en')=>({file_path:path,iso_639_1:language,width:1000,height:1500});
const incoming=body=>new Request('http://app.local/catalog',{method:'POST',headers:{Authorization:'Bearer user'},body:JSON.stringify(body)});
test('poster discovery normalizes paths, deduplicates and orders English/textless choices first',async()=>{
 const client=createTMDBClient('tmdb',async(input,options)=>{
  const url=new URL(input);assert.equal(url.href,'https://api.themoviedb.org/3/movie/106/images');
  assert.equal(options.redirect,'error');
  return Response.json({id:106,posters:[poster('/fr.jpg','fr'),poster('/none.jpg',null),poster('/en.jpg'),poster('/en.jpg'),poster('https://evil.test/a.jpg'),{...poster('/bad.jpg'),height:0}]});
 });
 const covers=await client.posters(106);
 assert.deepEqual(covers.map(p=>p.path),['/en.jpg','/none.jpg','/fr.jpg']);
 assert.equal(covers[0].url,'https://image.tmdb.org/t/p/w342/en.jpg');
 for(const data of [{id:107,posters:[]},{id:106,posters:null}]){
  await assert.rejects(createTMDBClient('token',async()=>Response.json(data)).posters(106),{status:502});
 }
});
test('cover writes accept only a poster for that movie and derive the actor from live Auth',async()=>{
 const writes=[];
 const handler=createCatalogHandler(env,async(input,options)=>{
  const url=new URL(input);
  if(url.pathname==='/auth/v1/user')return Response.json(user);
  if(url.host==='api.themoviedb.org')return Response.json({id:106,posters:[poster('/valid.jpg')]});
  assert.equal(url.pathname,'/rest/v1/rpc/set_movie_cover');
  assert.equal(options.headers.Authorization,'Bearer admin');writes.push(JSON.parse(options.body));return Response.json(true);
 });
 for(const extra of [{actor:'spoof'},{path:'https://evil.test/a.jpg'},{path:'/../a.jpg'},{path:'/x.JPG'},{path:undefined},{movieID:0}]){
  assert.equal((await handler(incoming({operation:'set_cover',movieID:106,path:'/valid.jpg',...extra}))).status,400);
 }
 assert.equal((await handler(incoming({operation:'set_cover',movieID:106,path:'/other.jpg'}))).status,400);
 assert.equal(writes.length,0);
 const r=await handler(incoming({operation:'set_cover',movieID:106,path:'/valid.jpg'}));
 assert.equal(r.status,200);assert.deepEqual(writes,[{actor:user.id,provider_id:106,poster_path:'/valid.jpg'}]);
 assert.equal((await handler(incoming({operation:'posters',movieID:106}))).status,200);
});
test('reset requires no provider access; denied/missing Auth and backend errors fail closed',async()=>{
 for(const [code,status] of [['42501',403],['22023',400],['XX000',503],[null,200]]){
  const handler=createCatalogHandler({...env,tmdbToken:''},async(input,options)=>{
   const url=new URL(input);if(url.pathname==='/auth/v1/user')return Response.json(user);
   assert.equal(url.host,'auth.local');assert.equal(JSON.parse(options.body).poster_path,null);
   return code?Response.json({code,message:'private error'},{status:400}):Response.json(true);
  });
  const r=await handler(incoming({operation:'set_cover',movieID:106,path:null}));assert.equal(r.status,status);
  assert.ok(!JSON.stringify(await r.json()).includes('private error'));
 }
 const denied=createCatalogHandler(env,async()=>Response.json({}, {status:401}));
 assert.equal((await denied(incoming({operation:'set_cover',movieID:106,path:null}))).status,401);
 const missing=createCatalogHandler({...env,admin:''},async()=>Response.json(user));
 assert.equal((await missing(incoming({operation:'set_cover',movieID:106,path:null}))).status,503);
});
test('add-time artwork is validated before a single atomic import RPC; omission preserves legacy requests',async()=>{
 const writes=[];
 const handler=createCatalogHandler(env,async(input,options)=>{
  const url=new URL(input);
  if(url.pathname==='/auth/v1/user')return Response.json(user);
  if(url.host==='api.themoviedb.org')return Response.json(url.pathname.endsWith('/images')
   ? {id:106,posters:[poster('/valid.jpg')]}
   : {id:106,title:'Predator',release_date:'1987-06-12'});
  writes.push({rpc:url.pathname,body:JSON.parse(options.body)});return Response.json('movie-uuid');
 });
 const base={operation:'import',movieID:106,requestID:'40000000-0000-0000-0000-000000000001',libraryID:'20000000-0000-0000-0000-000000000001',formats:['4K UHD']};
 for(const coverPath of ['/foreign.jpg','https://evil.test/a.jpg',{},false]) {
  assert.equal((await handler(incoming({...base,coverPath}))).status,400);
 }
 assert.equal(writes.length,0);
 for(const coverPath of ['/valid.jpg',null]){
  assert.equal((await handler(incoming({...base,coverPath}))).status,200);
  assert.equal(writes.at(-1).rpc,'/rest/v1/rpc/import_catalog_movie_with_cover');
  assert.equal(writes.at(-1).body.poster_path,coverPath);
  assert.equal(writes.at(-1).body.actor,user.id);
 }
 assert.equal((await handler(incoming(base))).status,200);
 assert.equal(writes.at(-1).rpc,'/rest/v1/rpc/import_catalog_movie');
 assert.equal(Object.hasOwn(writes.at(-1).body,'poster_path'),false);
});
