import test from 'node:test';
import assert from 'node:assert/strict';
import { iosConfiguration } from './configure-ios.mjs';
const status = { API_URL: 'http://127.0.0.1:54321', PUBLISHABLE_KEY: 'sb_publishable_test' };
test('generates simulator and private device configuration without xcconfig comments', () => {
  assert.match(iosConfiguration(status), /http:\/\$\(\)\/127.0.0.1:54321/);
  assert.match(iosConfiguration(status, '192.168.1.5'), /192.168.1.5/);
  assert.match(iosConfiguration(status, 'mac.local'), /mac.local/);
});
test('rejects remote stacks, unsafe hosts, and server keys', () => {
  assert.throws(() => iosConfiguration({ ...status, API_URL: 'https://example.com' }));
  for (const host of ['example.com', '8.8.8.8', '127.0.0.1\nBAD=1', '192.168.1.999']) assert.throws(() => iosConfiguration(status, host));
  for (const key of ['sb_secret_bad', 'bad', 'sb_publishable_abc\nBAD=1']) assert.throws(() => iosConfiguration({ ...status, PUBLISHABLE_KEY: key }));
});
test('legacy anon keys are accepted and service-role keys are rejected', () => {
  const key = role => `header.${Buffer.from(JSON.stringify({role})).toString('base64url')}.signature`;
  assert.match(iosConfiguration({ API_URL: status.API_URL, ANON_KEY: key('anon') }), /SUPABASE_PUBLISHABLE_KEY/);
  assert.throws(() => iosConfiguration({ API_URL: status.API_URL, ANON_KEY: key('service_role') }));
});
