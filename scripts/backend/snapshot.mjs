import {readFileSync,writeFileSync,readdirSync,mkdirSync,existsSync,openSync,closeSync} from 'node:fs';
import {resolve,dirname,relative} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {execFileSync,spawnSync} from 'node:child_process';
import {root,synchronize} from '../release-version.mjs';
import {settings} from './local.mjs';

export function sourceManifest(directory){
 const release=synchronize(directory),files={};
 function collect(path){
  if(!existsSync(path))return;
  for(const entry of readdirSync(path,{withFileTypes:true})){
   const name=resolve(path,entry.name);
   if(entry.name.startsWith('.'))continue;
   if(entry.isDirectory())collect(name);
   else if(entry.isFile()&&/\.(mjs|ts|sql)$/.test(entry.name))files[relative(directory,name)]=createHash('sha256').update(readFileSync(name)).digest('hex');
  }
 }
 collect(resolve(directory,'backend/supabase/functions'));
 collect(resolve(directory,'backend/supabase/migrations'));
 collect(resolve(directory,'backend/supabase/tests'));
 collect(resolve(directory,'scripts/backend'));
 for(const name of ['release-version.json','apps/ios/Configuration/Version.xcconfig','scripts/release-version.mjs','package.json','package-lock.json','backend/supabase/config.toml','backend/supabase/fixtures/scenarios.json','backend/supabase/fixtures/demo-catalog.json']){
  if(existsSync(resolve(directory,name)))files[name]=createHash('sha256').update(readFileSync(resolve(directory,name))).digest('hex');
 }
 const ordered=Object.fromEntries(Object.entries(files).sort(([a],[b])=>a.localeCompare(b)));
 const migrations=Object.keys(ordered).filter(p=>/^backend\/supabase\/migrations\/\d{14}_.*\.sql$/.test(p)).map(p=>p.split('/').at(-1).slice(0,14)).sort();
 return {release,migrations,files:ordered,sourceSHA256:createHash('sha256').update(JSON.stringify(ordered)).digest('hex')};
}
export async function testSnapshot(output){
 settings(); // Refuses hosted/alternate endpoints before any fixture or test command.
 const manifest=sourceManifest(root);
 const cli=resolve(root,'node_modules/.bin/supabase');
 const result=JSON.parse(execFileSync(cli,['--workdir','backend','db','query','--local','select version from supabase_migrations.schema_migrations order by version','-o','json'],{cwd:root,encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout:20000}));
 if(JSON.stringify(result.rows.map(r=>r.version).sort())!==JSON.stringify(manifest.migrations))throw Error('Local database migrations differ from snapshot source. Apply local migrations before testing.');
 mkdirSync(output,{recursive:true});
 const path=resolve(output,'manifest.json');if(existsSync(path))throw Error('Choose a fresh snapshot output directory.');
 manifest.gitCommit=execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim();
 manifest.dirty=Boolean(execFileSync('git',['status','--porcelain'],{cwd:root,encoding:'utf8'}).trim());
 manifest.startedAt=new Date().toISOString();manifest.status='running';manifest.checks=[];
 const save=()=>writeFileSync(path,JSON.stringify(manifest,null,2)+'\n');save();
 const scripts=JSON.parse(readFileSync(resolve(root,'package.json'),'utf8')).scripts;
 const checks=['release:check','backend:test','backend:test:db','backend:fixtures','backend:test:api','backend:test:collection','backend:test:movie-add','backend:test:catalog'];
 if(scripts['backend:test:covers'])checks.push('backend:test:covers');
 checks.push('backend:test:deletion','backend:test:google-deletion','backend:test:apple-deletion');
 try{
  for(const name of checks){
   const file=name.replaceAll(':','-')+'.log',fd=openSync(resolve(output,file),'w');let run;
   try{run=spawnSync('npm',['run',name],{cwd:root,stdio:['ignore',fd,fd],timeout:120000});}finally{closeSync(fd);}
   manifest.checks.push({name,passed:run.status===0,log:file});save();
   if(run.status!==0)throw Error(name+' failed; inspect its snapshot log.');
   console.log(name+': passed');
  }
  if(sourceManifest(root).sourceSHA256!==manifest.sourceSHA256)throw Error('Backend source changed while snapshot checks ran. Retest the new source.');
  for(const [name,hash] of Object.entries(manifest.files)){
   const data=readFileSync(resolve(root,name));
   if(createHash('sha256').update(data).digest('hex')!==hash)throw Error('Source changed while capturing snapshot.');
   const destination=resolve(output,'source',name);mkdirSync(dirname(destination),{recursive:true});writeFileSync(destination,data);
  }
  manifest.status='passed';manifest.finishedAt=new Date().toISOString();save();
  console.log('Verified backend '+manifest.release.version+' snapshot: '+path);
 }catch(error){manifest.status='failed';manifest.finishedAt=new Date().toISOString();manifest.failure=error.message;save();throw error;}
 return manifest;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{
  const args=process.argv.slice(2);
  if(args.length!==2||args[0]!=='--output')throw Error('Usage: npm run backend:snapshot:test -- --output build/backend-snapshot-N');
  await testSnapshot(resolve(args[1]));
 }catch(error){console.error(error.message);process.exitCode=1;}
}
