import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { settings } from './local.mjs';
let config;
try { config=settings(); } catch { console.error("Start the local Supabase stack before running deletion checks."); process.exit(1); }
const created=[]; let movie;
async function call(token,path,{method='GET',body,status=200}={}) {
 const response=await fetch(config.url+path,{method,redirect:'error',signal:AbortSignal.timeout(20000),headers:{apikey:config.anon,Authorization:`Bearer ${token}`,'Content-Type':'application/json',Prefer:'return=representation'},body:body===undefined?undefined:JSON.stringify(body)});
 assert.equal(response.status,status,`${method} ${path.split('?')[0]}`);
 const text=await response.text(); return text?JSON.parse(text):null;
}
try {
 const accounts=[];
 for(let i=0;i<2;i++) {
  const password=randomUUID()+'Aa1!', email=`delete-check-${randomUUID()}@example.test`;
  const user=await call(config.admin,'/auth/v1/admin/users',{method:'POST',body:{email,password,email_confirm:true}});created.push(user.id);
  const session=await call(config.anon,'/auth/v1/token?grant_type=password',{method:'POST',body:{email,password}});
  accounts.push({id:user.id,email,password,token:session.access_token});
 }
 const [owner,other]=accounts;
 const shared=await call(owner.token,'/rest/v1/rpc/create_shared_library',{method:'POST',body:{library_name:'Deletion verification shared library'}});
 await call(owner.token,'/rest/v1/library_memberships',{method:'POST',status:201,body:{library_id:shared,user_id:other.id,role:'viewer'}});
 movie=randomUUID();
 await call(owner.token,'/rest/v1/movies',{method:'POST',status:201,body:{id:movie,title:'Deletion verification shared metadata'}});
 await call(owner.token,'/rest/v1/owned_copies',{method:'POST',status:201,body:{library_id:shared,movie_id:movie,format:'DVD'}});
 await call(owner.token,'/rest/v1/personal_movie_state',{method:'POST',status:201,body:{movie_id:movie,watched:true,rating:5}});
 const endpoint='/functions/v1/delete-account';
 await call(config.anon,endpoint,{method:'POST',status:401,body:{password:owner.password}});
 await call(owner.token,endpoint,{method:'POST',status:403,body:{password:'intentionally-incorrect'}});
 await call(owner.token,endpoint,{method:'POST',status:400,body:{password:owner.password,user_id:other.id}});
 const result=await call(owner.token,endpoint,{method:'POST',body:{password:owner.password}});assert.equal(result.deleted,true);
 for(const [table,filter] of [['profiles',`id=eq.${owner.id}`],['libraries',`owner_id=eq.${owner.id}`],['library_memberships',`user_id=eq.${owner.id}`],['personal_movie_state',`user_id=eq.${owner.id}`],['user_preferences',`user_id=eq.${owner.id}`],['owned_copies',`library_id=eq.${shared}`]]) {
  assert.deepEqual(await call(config.admin,`/rest/v1/${table}?${filter}`),[],`Deletion cascades ${table}`);
 }
 assert.equal((await call(config.admin,`/rest/v1/profiles?id=eq.${other.id}`)).length,1);
 await call(owner.token,endpoint,{method:'POST',status:401,body:{password:owner.password}});
 await call(config.anon,'/auth/v1/token?grant_type=password',{method:'POST',status:400,body:{email:owner.email,password:owner.password}});
 console.log('Account deletion passed: auth required, password required, target-ID injection rejected, owned/shared data cascades, other account preserved, deleted login rejected.');
} finally {
 for(const id of created) {
  const r=await fetch(config.url+'/auth/v1/admin/users/'+id,{method:'DELETE',headers:{apikey:config.admin,Authorization:`Bearer ${config.admin}`}});
  if(!r.ok && r.status!==404) throw new Error('Temporary deletion-test account cleanup failed.');
 }
 if(movie) await call(config.admin,`/rest/v1/movies?id=eq.${movie}`,{method:'DELETE'});
}
