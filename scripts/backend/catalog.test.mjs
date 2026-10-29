import test from 'node:test';
import assert from 'node:assert/strict';
import { createCatalogHandler } from '../../backend/supabase/functions/catalog/handler.mjs';
import { createTMDBClient } from '../../backend/supabase/functions/catalog/tmdb.mjs';
const env = {url:'http://auth.local',anon:'public-key',tmdbToken:'provider-token'};
const user = {id:'10000000-0000-0000-0000-000000000001'};
const film = {id:329865,title:' Arrival ',release_date:'2016-11-10',overview:' First contact ',poster_path:'/arrival.jpg',runtime:116,genres:[{name:'Science Fiction'}],credits:{crew:[{job:'Director',name:'Denis Villeneuve'}]}};
function incoming(body,headers={Authorization:'Bearer user-token'},method='POST') {
  return new Request('http://app.local/catalog',{method,headers,body:method==='POST'?JSON.stringify(body):undefined});
}
function fake({auth=200,provider=200,data,network=false}={}) {
  const calls=[];
  const request=async (input,options)=>{
    const url=new URL(input); calls.push({url,options});
    if(url.host==='auth.local') return Response.json(auth===200?user:{error:'denied'},{status:auth});
    if(network) throw new Error('do not expose provider internals');
    return Response.json(data ?? (url.pathname.endsWith('/search/movie')?{page:Number(url.searchParams.get('page')),total_pages:2,results:[film]}:film),{status:provider,headers:{'Retry-After':'30'}});
  };
  return {request,calls};
}
test('catalog validates method, caller and body without permitting arbitrary upstream URLs',async()=>{
  const f=fake(),handler=createCatalogHandler(env,f.request);
  assert.equal((await handler(incoming(null,{},'GET'))).status,405);
  assert.equal((await handler(incoming({operation:'search',query:'Arrival',page:1},{}))).status,401);
  for(const body of [null,[],{operation:'other'},{operation:'search',query:'a',page:0},{operation:'search',query:'a',page:501},{operation:'search',query:'a'.repeat(201),page:1},{operation:'search',query:'a',page:1,url:'https://attacker.test'},{operation:'details',movieID:-1},{operation:'details',movieID:1.5},{operation:'details',movieID:1,user_id:user.id}]) {
    assert.equal((await handler(incoming(body))).status,400);
  }
  assert.equal((await handler(new Request('http://app.local',{method:'POST',headers:{Authorization:'Bearer user-token'},body:'bad json'}))).status,400);
  assert.equal((await handler(incoming({operation:'search',query:'a'.repeat(5000),page:1}))).status,400);
  assert.equal(f.calls.length,0);
});
test('search validates live identity, hides credentials and normalizes provider wire data',async()=>{
  const f=fake(),response=await createCatalogHandler(env,f.request)(incoming({operation:'search',query:' Arrival ',page:1}));
  assert.equal(response.status,200); assert.equal(response.headers.get('Cache-Control'),'no-store');
  const page=await response.json();
  assert.equal(page.results[0].id,329865); assert.equal(page.results[0].title,'Arrival');
  assert.equal(page.results[0].year,2016); assert.equal(page.results[0].posterURL,'https://image.tmdb.org/t/p/w342/arrival.jpg');
  assert.equal(page.results[0].director,'Denis Villeneuve'); assert.equal(page.results[0].runtimeMinutes,116);
  assert.deepEqual(page.results[0].genres,['Science Fiction']);
  assert.equal(f.calls[0].options.headers.Authorization,'Bearer user-token');
  assert.equal(f.calls[1].options.headers.Authorization,'Bearer provider-token');
  assert.equal(f.calls[1].url.origin,'https://api.themoviedb.org');
  assert.equal(f.calls[1].url.searchParams.get('query'),'Arrival');
  assert.equal(f.calls[1].url.searchParams.get('include_adult'),'false');
  assert.equal(f.calls[1].options.redirect,'error');
  assert.ok(!JSON.stringify(page).includes('provider-token'));
});
test('blank search never calls TMDB, and missing metadata has stable placeholders',async()=>{
  const f=fake(),handler=createCatalogHandler({...env,tmdbToken:''},f.request);
  const blank=await handler(incoming({operation:'search',query:' \n ',page:1}));
  assert.deepEqual(await blank.json(),{page:1,totalPages:0,results:[]}); assert.equal(f.calls.length,1);
  const data={page:1,total_pages:800,results:[{id:11,title:null,release_date:'',overview:'',poster_path:'https://evil.test/x.jpg',credits:{crew:[null,{job:'Director',name:''}]}},null,{id:-1}]};
  const sparse=fake({data});
  const page=await createTMDBClient('provider',sparse.request).search('a',1);
  assert.equal(page.totalPages,500); assert.equal(page.results.length,1);
  assert.equal(page.results[0].title,'Untitled movie'); assert.equal(page.results[0].year,null);
  assert.equal(page.results[0].synopsis,'No synopsis available.'); assert.equal(page.results[0].posterURL,null);
  assert.deepEqual(page.results[0].genres,[]); assert.equal(page.results[0].director,null);
});
test('details use fixed provider IDs and add credits without accepting arbitrary paths',async()=>{
  const f=fake(),response=await createCatalogHandler(env,f.request)(incoming({operation:'details',movieID:329865}));
  assert.equal(response.status,200); assert.equal((await response.json()).id,329865);
  assert.equal(f.calls[1].url.pathname,'/3/movie/329865');
  assert.equal(f.calls[1].url.searchParams.get('append_to_response'),'credits');
});
test('auth, provider configuration, rate limits and network failures fail safely',async()=>{
  for(const [options,status,code] of [[{auth:401},401,'unauthorized'],[{auth:503},503,'unavailable'],[{auth:429},503,'unavailable'],[{provider:401},503,'catalog_not_configured'],[{provider:403},503,'catalog_not_configured'],[{provider:429},429,'rate_limited'],[{provider:404},404,'movie_not_found'],[{provider:500},503,'provider_unavailable'],[{network:true},503,'provider_unavailable']]) {
    const f=fake(options),response=await createCatalogHandler(env,f.request)(incoming({operation:'search',query:'a',page:1}));
    assert.equal(response.status,status); assert.equal((await response.json()).error,code);
    if(status===429) assert.equal(response.headers.get('Retry-After'),'30');
  }
  const f=fake(),response=await createCatalogHandler({...env,tmdbToken:''},f.request)(incoming({operation:'details',movieID:11}));
  assert.equal(response.status,503); assert.equal(f.calls.length,1);
});
test('malformed and mismatched provider payloads cannot masquerade as successful results',async()=>{
  for(const data of [{},{page:2,total_pages:1,results:[]},{page:1,total_pages:-1,results:[]}]) {
    const f=fake({data}),response=await createCatalogHandler(env,f.request)(incoming({operation:'search',query:'a',page:1}));
    assert.equal(response.status,502);
  }
  const f=fake({data:{...film,id:11}});
  assert.equal((await createCatalogHandler(env,f.request)(incoming({operation:'details',movieID:329865}))).status,502);
});

test('import uses verified actor and canonical server metadata, with narrow service-role RPC',async()=>{
  const calls=[];
  const request=async(input,options)=>{
    const url=new URL(input); calls.push({url,options});
    if(url.pathname==='/auth/v1/user') return Response.json(user);
    if(url.host==='api.themoviedb.org') return Response.json(film);
    assert.equal(url.pathname,'/rest/v1/rpc/import_catalog_movie');
    assert.equal(options.headers.Authorization,'Bearer admin-key');
    const value=JSON.parse(options.body);
    assert.equal(value.actor,user.id);
    assert.equal(value.provider_id,329865);
    assert.equal(value.metadata.title,'Arrival');
    assert.deepEqual(value.copy_formats,['DVD','DVD','4K UHD']);
    return Response.json('30000000-0000-0000-0000-000000000001');
  };
  const body={operation:'import',movieID:329865,requestID:'40000000-0000-0000-0000-000000000001',libraryID:'20000000-0000-0000-0000-000000000001',formats:['DVD','DVD','4K UHD']};
  const handler=createCatalogHandler({...env,admin:'admin-key'},request);
  for(const extra of [{actor:user.id},{metadata:{title:'Spoof'}},{formats:[]},{formats:['Tape']},{formats:Array(100).fill('DVD')},{requestID:'bad'}]) {
    assert.equal((await handler(incoming({...body,...extra}))).status,400);
  }
  assert.equal(calls.length,0);
  const response=await handler(incoming(body));
  assert.equal(response.status,200);
  assert.deepEqual(await response.json(),{movieID:'30000000-0000-0000-0000-000000000001'});
  assert.equal(calls.length,3);
  assert.equal((await createCatalogHandler(env,request)(incoming(body))).status,503);
});
test('import maps denial and identity conflicts without exposing database internals',async()=>{
  const body={operation:'import',movieID:329865,requestID:'40000000-0000-0000-0000-000000000001',libraryID:'20000000-0000-0000-0000-000000000001',formats:['DVD']};
  for(const [code,status] of [['42501',403],['22023',400],['XX000',503]]) {
    const handler=createCatalogHandler({...env,admin:'admin-key'},async(input)=>{
      const url=new URL(input);
      if(url.pathname==='/auth/v1/user') return Response.json(user);
      if(url.host==='api.themoviedb.org') return Response.json(film);
      return Response.json({code,message:'private details'},{status:400});
    });
    const response=await handler(incoming(body));
    assert.equal(response.status,status);
    assert.deepEqual(await response.json(),{error:'import_failed'});
  }
});
