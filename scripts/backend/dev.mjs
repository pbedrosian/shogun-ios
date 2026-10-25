import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { docsServer } from './docs.mjs';

const exec = promisify(execFile);
const root = fileURLToPath(new URL('../../', import.meta.url));
const cli = path.join(root, 'node_modules/.bin/supabase');
const docsURL = 'http://127.0.0.1:54328';
const noOpen = process.argv.includes('--no-open');
let server;
let child;

function run(command, args) {
  return new Promise((resolve, reject) => {
    // Supabase prints keys to stdout on success; keep those out of launcher logs.
    child = spawn(command, args, { cwd: root, stdio: ['inherit', 'ignore', 'inherit'] });
    child.once('error', reject);
    child.once('exit', code => {
      child = undefined;
      code === 0 ? resolve() : reject(new Error(`${command} failed (${code}).`));
    });
  });
}

async function dockerReady() {
  try {
    await exec('docker', ['info'], { timeout: 5_000 });
    return true;
  } catch { return false; }
}

async function existingDocs() {
  try {
    const response = await fetch(docsURL + '/config.json', {signal:AbortSignal.timeout(2_000),redirect:'error'});
    const config = await response.json();
    return response.ok && config.api === 'http://127.0.0.1:54321';
  } catch { return false; }
}

function shutdown() {
  child?.kill('SIGINT');
  server?.close();
  console.log('\nStopped this launcher. Supabase remains running; use npm run backend:stop to stop it.');
  process.exit(0);
}
process.once('SIGINT', shutdown);
process.once('SIGTERM', shutdown);

try {
  if (process.argv.slice(2).some(arg => arg !== '--no-open')) throw new Error('Usage: npm run dev [-- --no-open]');
  if (!await dockerReady()) {
    if (process.platform !== 'darwin') throw new Error('Start your Docker engine, then run npm run dev again.');
    console.log('Starting Docker Desktop…');
    await exec('open', ['-a', 'Docker']);
    const deadline = Date.now() + 120_000;
    while (!await dockerReady()) {
      if (Date.now() >= deadline) throw new Error('Docker did not become ready within two minutes. Check Docker Desktop and retry.');
      await new Promise(resolve => setTimeout(resolve, 2_000));
    }
  }
  console.log('Starting local Supabase…');
  await run(cli, ['--workdir', path.join(root, 'backend'), 'start']);
  if (!await existingDocs()) {
    const {stdout} = await exec(cli, ['--workdir',path.join(root,'backend'),'status','-o','json'], {cwd:root,timeout:20_000});
    const status = JSON.parse(stdout);
    if (status.API_URL !== 'http://127.0.0.1:54321' || !status.ANON_KEY) throw new Error('Expected the local Supabase project.');
    server = docsServer(status.ANON_KEY);
    await new Promise((resolve,reject) => {
      server.once('error',reject);
      server.listen(54328,'127.0.0.1',resolve);
    });
  } else console.log('Reusing the running Swagger UI server.');

  if (!noOpen && process.platform === 'darwin') {
    await exec('open', [docsURL]);
    await exec('open', [path.join(root,'apps/ios/Shogun.xcodeproj')]);
  }
  console.log(`Ready. Swagger UI: ${docsURL}\nStudio: http://127.0.0.1:54323\nPress Run (⌘R) in Xcode to launch the iPhone app.`);
  console.log('The iOS app still uses offline demo data until SHO-19/20.');
  if (server) console.log('Keep this Terminal open for Swagger UI. Ctrl-C stops the docs server only.');
} catch (error) {
  server?.close();
  // Do not dump child-process output, which can contain local API keys.
  console.error(error.code === 'EADDRINUSE' ? 'Port 54328 is occupied by another service.' :
    error.stdout || error.stderr ? 'Startup failed. Check Docker Desktop and local Supabase, then retry.' : error.message);
  process.exitCode = 1;
}
