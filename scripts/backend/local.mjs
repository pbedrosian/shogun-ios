import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../../', import.meta.url));
const cli = path.join(root, 'node_modules/.bin/supabase');
const password = 'Shogun-local-only-25!';

// This script never accepts a URL/key from arguments or environment variables.
// Secrets come only from this project's running local CLI stack, and stay in memory.
export function localSettings(status) {
  const url = new URL(status.API_URL);
  if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1' ||
      url.port !== '54321' || url.pathname !== '/' || url.username || url.password ||
      url.search || url.hash) {
    throw new Error('Refusing fixtures/smoke checks outside http://127.0.0.1:54321.');
  }
  if (!status.SERVICE_ROLE_KEY || !status.ANON_KEY) {
    throw new Error('Local CLI status must include SERVICE_ROLE_KEY and ANON_KEY.');
  }
  return { url: url.origin, admin: status.SERVICE_ROLE_KEY, anon: status.ANON_KEY };
}

export function settings() {
  const status = execFileSync(cli, ['--workdir', path.join(root, 'backend'), 'status', '-o', 'json'],
    { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 20_000 });
  return localSettings(JSON.parse(status));
}

async function request(config, endpoint, { admin = false, method = 'GET', body, upsert = false } = {}) {
  const key = admin ? config.admin : config.anon;
  const response = await fetch(config.url + endpoint, {
    method, redirect: 'error', signal: AbortSignal.timeout(15_000),
    headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json',
      Prefer: upsert ? 'resolution=merge-duplicates,return=representation' : 'return=representation' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  // Do not print response bodies: Auth responses contain tokens and user information.
  if (!response.ok) throw new Error(`${method} ${endpoint.split('?')[0]} failed (${response.status}).`);
  return response.json();
}

async function fixtures(config) {
  const spec = JSON.parse(readFileSync(path.join(root, 'backend/supabase/fixtures/scenarios.json'), 'utf8'));
  const users = [];
  for (let page = 1; ; page++) {
    const result = await request(config, `/auth/v1/admin/users?page=${page}&per_page=100`, { admin: true });
    users.push(...result.users);
    if (result.users.length < 100) break;
  }
  const accounts = [];
  for (const account of spec.accounts) {
    const existing = users.find(user => user.email === account.email);
    const user = await request(config,
      existing ? `/auth/v1/admin/users/${existing.id}` : '/auth/v1/admin/users', {
        admin: true, method: existing ? 'PUT' : 'POST',
        body: { email: account.email, password, email_confirm: true },
      });
    const id = user.id ?? user.user?.id;
    if (!id) throw new Error(`Auth did not return an ID for fixture ${account.name}.`);
    accounts.push({ ...account, id });
  }
  const owner = accounts.find(account => account.name === 'owner');
  const family = spec.libraryScenario;
  await request(config, '/rest/v1/libraries?on_conflict=id', {
    admin: true, method: 'POST', upsert: true,
    body: { id: family.id, owner_id: owner.id, name: family.name, is_shared: true },
  });
  await request(config, '/rest/v1/library_memberships?on_conflict=library_id,user_id', {
    admin: true, method: 'POST', upsert: true,
    body: Object.entries(family.memberships).map(([name, role]) => ({
      library_id: family.id, user_id: accounts.find(account => account.name === name).id, role,
    })),
  });
  for (const name of family.excluded) {
    const account = accounts.find(account => account.name === name);
    await request(config, `/rest/v1/library_memberships?library_id=eq.${family.id}&user_id=eq.${account.id}`,
      { admin: true, method: 'DELETE' });
  }
  writeFileSync(path.join(root, 'backend/supabase/fixtures/accounts.local.json'),
    JSON.stringify({ accounts, libraryScenario: family }, null, 2) + '\n', { mode: 0o600 });
  console.log('Four local Auth fixtures and the owner/editor/viewer family library are ready.');
}

async function smoke(config) {
  await request(config, '/auth/v1/health');
  await request(config, '/rest/v1/');
  const { accounts } = JSON.parse(readFileSync(path.join(root, 'backend/supabase/fixtures/scenarios.json'), 'utf8'));
  const ids = new Set();
  for (const account of accounts) {
    const session = await request(config, '/auth/v1/token?grant_type=password', {
      method: 'POST', body: { email: account.email, password },
    });
    if (!session.access_token || !session.user?.id) throw new Error('Fixture sign-in did not return a session.');
    ids.add(session.user.id);
  }
  if (ids.size !== accounts.length) throw new Error('Fixture users must have distinct identities.');
  console.log('Auth health, REST, and four distinct fixture sign-ins passed. This does not test application RLS.');
}

function doctor() {
  const version = execFileSync(cli, ['--version'], { cwd: root, encoding: 'utf8', timeout: 20_000 }).trim();
  const expected = JSON.parse(readFileSync(path.join(root, 'package.json'), 'utf8')).devDependencies.supabase;
  if (version !== expected) throw new Error(`Expected Supabase ${expected}; found ${version}. Run npm ci.`);
  execFileSync('docker', ['info', '--format', '{{.ServerVersion}}'], { stdio: 'pipe', timeout: 20_000 });
  console.log(`Supabase ${version} and Docker engine are ready.`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const command = process.argv[2];
    if (process.argv.length !== 3) throw new Error('Usage: local.mjs doctor|fixtures|smoke (no additional arguments).');
    if (command === 'doctor') doctor();
    else if (command === 'fixtures') await fixtures(settings());
    else if (command === 'smoke') await smoke(settings());
    else throw new Error('Unknown local backend command.');
  } catch (error) {
    // Child-process errors can contain CLI status/keys: never dump them.
    console.error(error.status !== undefined || error.code ?
      'Local backend unavailable. Check Docker Desktop, run npm ci, then npm run backend:start.' : error.message);
    process.exitCode = 1;
  }
}
