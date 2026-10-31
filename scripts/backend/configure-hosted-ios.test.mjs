import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, statSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { configureHostedIOS, hostedIOSConfiguration } from './configure-hosted-ios.mjs';

const ref = 'abcdefghijklmnopqrst';
const url = `https://${ref}.supabase.co`;
const key = 'sb_publishable_example';
const jwt = payload => `header.${Buffer.from(JSON.stringify(payload)).toString('base64url')}.signature`;

test('hosted config escapes xcconfig URL comments and permits matching legacy anon keys', () => {
  assert.match(hostedIOSConfiguration(url, key), /https:\/\$\(\)\/abcdefghijklmnopqrst\.supabase\.co\n/);
  assert.ok(hostedIOSConfiguration(url + '/', jwt({ role: 'anon', ref })).includes('SUPABASE_PUBLISHABLE_KEY'));
});

test('hosted config rejects local, alternate, credential-bearing and injected URLs', () => {
  for (const value of [undefined, 'http://' + ref + '.supabase.co', 'https://localhost',
    'https://example.com', url + '/auth/v1', url + '?key=bad', url + '#bad',
    'https://user:password@' + ref + '.supabase.co', url + '\nOTHER=1']) {
    assert.throws(() => hostedIOSConfiguration(value, key));
  }
});

test('hosted config rejects privileged, mismatched, malformed and injected keys without revealing them', () => {
  for (const value of [undefined, 'sb_secret_private', jwt({ role: 'service_role', ref }),
    jwt({ role: 'anon', ref: 'different' }), jwt({ role: 'anon' }), 'bad', 'a.b.c', key + '\n', key + '\nOTHER=1']) {
    assert.throws(() => hostedIOSConfiguration(url, value));
  }
});

test('hosted config preserves existing files and separates debug from release', () => {
  const projectRoot = mkdtempSync(path.join(tmpdir(), 'shogun-hosted-config-'));
  mkdirSync(path.join(projectRoot, 'apps/ios/Configuration'), { recursive: true });
  try {
    const options = { projectRoot, url, key, configuration: 'debug' };
    const debug = configureHostedIOS(options);
    const original = readFileSync(debug, 'utf8');
    assert.throws(() => configureHostedIOS({ ...options, key: 'sb_publishable_other' }), /already exists/);
    assert.equal(readFileSync(debug, 'utf8'), original);
    const release = configureHostedIOS({ ...options, configuration: 'release' });
    assert.notEqual(debug, release);
    configureHostedIOS({ ...options, key: 'sb_publishable_other', replace: true });
    assert.ok(readFileSync(debug, 'utf8').includes('sb_publishable_other'));
    assert.equal(readFileSync(release, 'utf8'), original);
    assert.equal(statSync(debug).mode & 0o777, 0o600);
    assert.throws(() => configureHostedIOS({ ...options, configuration: '../../outside' }));
  } finally { rmSync(projectRoot, { recursive: true, force: true }); }
});
