import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

export const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
export function releaseInfo(value){
 const match=typeof value==='string'&&value.match(/^((?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))(?:-(SNAPSHOT|rc\.[1-9]\d*))?$/);
 if(!match||match[0]!==value)throw Error('Use a numeric version, optionally suffixed -SNAPSHOT or -rc.N.');
 return {version:value,baseVersion:match[1],channel:match[2]==='SNAPSHOT'?'snapshot':match[2]?'candidate':'release'};
}
export function generatedFiles(version){
 const r=releaseInfo(version);
 return new Map([
  ['apps/ios/Configuration/Version.xcconfig',`// Generated from release-version.json by npm run release:generate.\nSHOGUN_BASE_VERSION = ${r.baseVersion}\nSHOGUN_DISPLAY_VERSION = ${r.version}\n`],
  ['backend/supabase/functions/_shared/release.mjs',`// Generated from release-version.json by npm run release:generate.\nexport const backendRelease = Object.freeze(${JSON.stringify({version:r.version,channel:r.channel})});\n`],
 ]);
}
export function synchronize(directory,{write=false}={}){
 const source=JSON.parse(readFileSync(resolve(directory,'release-version.json'),'utf8'));
 if(Object.keys(source).some(k=>k!=='version'))throw Error('Unexpected release-version property.');
 const info=releaseInfo(source.version);
 for(const [name,content] of generatedFiles(source.version)){
  const path=resolve(directory,name);
  if(write){mkdirSync(dirname(path),{recursive:true});writeFileSync(path,content);}
  else if(readFileSync(path,'utf8')!==content)throw Error(`Release version drift in ${name}. Run npm run release:generate.`);
 }
 return info;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{
  const args=process.argv.slice(2);
  if(args.length!==1||!['--check','--write'].includes(args[0]))throw Error('Usage: node scripts/release-version.mjs --check|--write');
  const r=synchronize(root,{write:args[0]==='--write'});
  console.log(`App and backend release: ${r.version} (${r.channel})`);
 }catch(e){console.error(e.message);process.exitCode=1;}
}
