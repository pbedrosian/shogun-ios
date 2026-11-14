import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,readFileSync,rmSync,mkdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {releaseInfo,synchronize} from '../release-version.mjs';
import {createCatalogHandler} from '../../backend/supabase/functions/catalog/handler.mjs';
import {sourceManifest} from './snapshot.mjs';

test('one release source generates matching numeric app and semantic backend labels',()=>{
 const directory=mkdtempSync(join(tmpdir(),'shogun-version-'));
 try{
  for(const [version,channel] of [['1.1.0-SNAPSHOT','snapshot'],['1.1.0-rc.2','candidate'],['1.1.0','release']]){
   writeFileSync(join(directory,'release-version.json'),JSON.stringify({version}));
   assert.equal(synchronize(directory,{write:true}).channel,channel);
   assert.equal(synchronize(directory).version,version);
   const app=readFileSync(join(directory,'apps/ios/Configuration/Version.xcconfig'),'utf8');
   assert.ok(app.includes('SHOGUN_BASE_VERSION = 1.1.0\n'));
   assert.ok(app.includes('SHOGUN_DISPLAY_VERSION = '+version+'\n'));
   assert.ok(readFileSync(join(directory,'backend/supabase/functions/_shared/release.mjs'),'utf8').includes('"version":"'+version+'"'));
  }
  writeFileSync(join(directory,'apps/ios/Configuration/Version.xcconfig'),'stale');
  assert.throws(()=>synchronize(directory),/drift/);
 }finally{rmSync(directory,{recursive:true,force:true});}
});
test('release metadata rejects malformed, injected and ambiguous version labels',()=>{
 for(const version of ['01.1.0','1.1','1.1.0-rc.0','1.1.0-snapshot','1.1.0\n','1.1.0\nSECRET=x','1.1.0+build',null])assert.throws(()=>releaseInfo(version));
});
test('snapshot fingerprints bind tested code and migration IDs while excluding local secrets',()=>{
 const directory=mkdtempSync(join(tmpdir(),'shogun-snapshot-'));
 try{
  writeFileSync(join(directory,'release-version.json'),JSON.stringify({version:'1.1.0-SNAPSHOT'}));
  synchronize(directory,{write:true});
  const functions=join(directory,'backend/supabase/functions');
  writeFileSync(join(functions,'example.mjs'),'export const example=1;');
  writeFileSync(join(functions,'.env'),'SECRET=never-include');
  const migrations=join(directory,'backend/supabase/migrations');mkdirSync(migrations,{recursive:true});
  writeFileSync(join(migrations,'20261114010000_example.sql'),'select 1;');
  const first=sourceManifest(directory);
  assert.deepEqual(first.migrations,['20261114010000']);
  assert.ok(!JSON.stringify(first).includes('SECRET'));
  assert.ok(!Object.keys(first.files).some(p=>p.endsWith('.env')));
  writeFileSync(join(functions,'.env'),'SECRET=changed');
  assert.equal(sourceManifest(directory).sourceSHA256,first.sourceSHA256);
  writeFileSync(join(functions,'example.mjs'),'export const example=2;');
  assert.notEqual(sourceManifest(directory).sourceSHA256,first.sourceSHA256);
 }finally{rmSync(directory,{recursive:true,force:true});}
});
test('backend version discovery requires live Auth and no TMDB credential or provider call',async()=>{
 const handler=createCatalogHandler({url:'http://auth.local',anon:'anon'},async(input)=>{
  assert.equal(new URL(input).pathname,'/auth/v1/user');
  return Response.json({id:'10000000-0000-0000-0000-000000000001'});
 });
 const incoming=body=>new Request('http://app.local',{method:'POST',headers:{Authorization:'Bearer user'},body:JSON.stringify(body)});
 const r=await handler(incoming({operation:'version'}));
 assert.equal(r.status,200);assert.equal(r.headers.get('Cache-Control'),'no-store');
 const source=JSON.parse(readFileSync(new URL('../../release-version.json',import.meta.url),'utf8'));
 assert.equal((await r.json()).version,source.version);
 assert.equal((await handler(incoming({operation:'version',version:'spoof'}))).status,400);
 const denied=createCatalogHandler({url:'http://auth.local',anon:'anon'},async()=>Response.json({}, {status:401}));
 assert.equal((await denied(incoming({operation:'version'}))).status,401);
});
