// The default smoke checks need no provider credential; --live explicitly calls TMDB.
import assert from 'node:assert/strict';
import { settings } from './local.mjs';
const config=settings();
const args=process.argv.slice(2);
if(args.some(a=>a!=='--live')) throw new Error('Usage: catalog-api.mjs [--live]');
async function call(token,body,status=200) {
  const response=await fetch(config.url+'/functions/v1/catalog',{method:'POST',redirect:'error',signal:AbortSignal.timeout(20000),
    headers:{apikey:config.anon,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(body)});
  assert.equal(response.status,status,'catalog endpoint status');
  return response.json();
}
const response=await fetch(config.url+'/auth/v1/token?grant_type=password',{method:'POST',redirect:'error',signal:AbortSignal.timeout(15000),
 headers:{apikey:config.anon,'Content-Type':'application/json'},body:JSON.stringify({email:'owner@shogun.test',password:'Shogun-local-only-25!'})});
assert.equal(response.status,200,'fixture sign-in');
const session=await response.json();
await call('invalid',{operation:'search',query:'Arrival',page:1},401);
await call(session.access_token,{operation:'search',query:'Arrival',page:1,url:'https://attacker.test'},400);
await call(session.access_token,{operation:'details',movieID:-1},400);
assert.deepEqual(await call(session.access_token,{operation:'search',query:' \n ',page:1}),{page:1,totalPages:0,results:[]});
if(args.includes('--live')) {
  const page=await call(session.access_token,{operation:'search',query:'Arrival',page:1});
  assert.ok(page.results.some(m=>m.id===329865),'provider search contains stable Arrival ID');
  const movie=await call(session.access_token,{operation:'details',movieID:329865});
  assert.equal(movie.id,329865); assert.equal(movie.year,2016);
  assert.ok(movie.runtimeMinutes>0); assert.ok(movie.director);
  assert.ok(movie.posterURL?.startsWith('https://image.tmdb.org/t/p/'));
  if(page.totalPages>1) assert.equal((await call(session.access_token,{operation:'search',query:'Arrival',page:2})).page,2);
  console.log('Live catalog search, details, artwork mapping and pagination passed through the authenticated local Edge Function.');
} else console.log('Catalog gateway passed: real JWT validation, narrow request contract, and blank-query suppression.');
