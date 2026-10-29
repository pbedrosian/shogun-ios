// Local-only seed. Credentials are supplied by the caller, never accepted for a hosted URL.
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { settings } from './local.mjs';
const email=process.env.SHOGUN_DEMO_EMAIL;
const password=process.env.SHOGUN_DEMO_PASSWORD;
if(!email || !password) { console.error('Set SHOGUN_DEMO_EMAIL and SHOGUN_DEMO_PASSWORD for the local testing account.'); process.exit(1); }
let config;
try { config=settings(); } catch { console.error('Start local Supabase before seeding the demo account.'); process.exit(1); }
const fixture=JSON.parse(readFileSync(new URL('../../backend/supabase/fixtures/demo-catalog.json',import.meta.url),'utf8'));
function id(value) { const h=createHash('sha256').update('shogun-local-demo:'+value).digest('hex'); return `${h.slice(0,8)}-${h.slice(8,12)}-4${h.slice(13,16)}-a${h.slice(17,20)}-${h.slice(20,32)}`; }
async function call(path,{method='GET',body,token=config.admin,upsert=false}={}) {
 const r=await fetch(config.url+path,{method,redirect:'error',signal:AbortSignal.timeout(15000),headers:{apikey:config.anon,Authorization:`Bearer ${token}`,'Content-Type':'application/json',Prefer:upsert?'resolution=merge-duplicates,return=representation':'return=representation'},body:body===undefined?undefined:JSON.stringify(body)});
 if(!r.ok) throw new Error(`${method} ${path.split('?')[0]} failed (${r.status}).`);
 const text=await r.text();return text?JSON.parse(text):null;
}
try {
 let existing;
 for(let page=1;;page++) { const result=await call(`/auth/v1/admin/users?page=${page}&per_page=100`);existing=result.users.find(u=>u.email?.toLowerCase()===email.toLowerCase());if(existing || result.users.length<100) break; }
 const user=await call(existing?`/auth/v1/admin/users/${existing.id}`:'/auth/v1/admin/users',{method:existing?'PUT':'POST',body:{email,password,email_confirm:true}});
 const userID=user.id;
 const session=await call('/auth/v1/token?grant_type=password',{method:'POST',token:config.anon,body:{email,password}});
 if(session.user?.id!==userID) throw new Error('Login did not return the seeded account.');
 const personal=await call('/rest/v1/rpc/bootstrap_account',{method:'POST',token:session.access_token,body:{}});
 await call(`/rest/v1/profiles?id=eq.${userID}`,{method:'PATCH',body:{display_name:'Alex Morgan'}});
 const ownerSpec=JSON.parse(readFileSync(new URL('../../backend/supabase/fixtures/scenarios.json',import.meta.url),'utf8')).accounts.find(a=>a.name==='owner');
 let fixtureOwner;
 for(let page=1;;page++) { const result=await call(`/auth/v1/admin/users?page=${page}&per_page=100`);fixtureOwner=result.users.find(u=>u.email===ownerSpec.email);if(fixtureOwner || result.users.length<100) break; }
 if(!fixtureOwner) throw new Error('Run npm run backend:fixtures first (shared-library owner is missing).');
 const libraryIDs=Object.fromEntries(fixture.libraries.map(l=>[l.id,l.is_shared?id(`${userID}:library:${l.id}`):personal]));
 for(const library of fixture.libraries) {
  const libraryID=libraryIDs[library.id];
  await call('/rest/v1/libraries?on_conflict=id',{method:'POST',upsert:true,body:{id:libraryID,name:library.name.length>120?library.name.slice(0,119)+"…":library.name,is_shared:library.is_shared,owner_id:library.is_shared?fixtureOwner.id:userID}});
  await call('/rest/v1/library_memberships?on_conflict=library_id,user_id',{method:'POST',upsert:true,body:{library_id:libraryID,user_id:userID,role:library.is_shared?'editor':'owner'}});
  if(library.is_shared) await call('/rest/v1/library_memberships?on_conflict=library_id,user_id',{method:'POST',upsert:true,body:{library_id:libraryID,user_id:fixtureOwner.id,role:'owner'}});
 }
 const movieIDs=Object.fromEntries(fixture.movies.map(m=>[m.id,id(`${userID}:movie:${m.id}`)]));
 await call('/rest/v1/movies?on_conflict=id',{method:'POST',upsert:true,body:fixture.movies.map(({id:local,...m})=>({...m,id:movieIDs[local],source:'manual',created_by:userID}))});
 await call('/rest/v1/owned_copies?on_conflict=id',{method:'POST',upsert:true,body:fixture.copies.map(c=>({id:id(`${userID}:copy:${c.id}`),library_id:libraryIDs[c.library_id],movie_id:movieIDs[c.movie_id],format:c.format,created_by:userID}))});
 await call('/rest/v1/personal_movie_state?on_conflict=user_id,movie_id',{method:'POST',upsert:true,body:fixture.personal_state.map(({movie_id,...state})=>({...state,user_id:userID,movie_id:movieIDs[movie_id]}))});
 await call('/rest/v1/user_preferences?on_conflict=user_id',{method:'POST',upsert:true,body:{user_id:userID,default_library_id:personal}});
 const asUser={token:session.access_token};
 const libraries=await call(`/rest/v1/libraries?id=in.(${Object.values(libraryIDs).join(',')})`,asUser);
 const movies=await call(`/rest/v1/movies?id=in.(${Object.values(movieIDs).join(',')})`,asUser);
 const copies=await call(`/rest/v1/owned_copies?library_id=in.(${Object.values(libraryIDs).join(',')})`,asUser);
 const state=await call(`/rest/v1/personal_movie_state?user_id=eq.${userID}&movie_id=eq.${movieIDs['arrival-2016']}`,asUser);
 if(libraries.length!==3 || movies.length!==8 || copies.length!==15 || state[0]?.rating!==5 || state[0]?.watched!==true) throw new Error('Seed verification failed.');
 console.log('Local demo login verified: 3 libraries, 8 movies, 15 copies; Arrival watched and rated 5/5.');
 console.log('Shared-library editor permissions match the original demo. Existing non-demo data was preserved.');
} catch(error) { console.error(error.message);process.exitCode=1; }
