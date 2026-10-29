import assert from 'node:assert/strict';
import test from 'node:test';
import { localSettings } from './local.mjs';

const status = { API_URL: 'http://127.0.0.1:54321', SERVICE_ROLE_KEY: 'local-admin', ANON_KEY: 'local-client' };
test('accepts the fixed local API endpoint', () => {
  assert.equal(localSettings(status).url, status.API_URL);
});
test('refuses hosted, alternate, and credential-bearing endpoints before any request', () => {
  for (const API_URL of ['https://example.supabase.co', 'http://localhost:54321',
    'http://127.0.0.1:54322', 'http://127.0.0.1:54321/path',
    'http://user@127.0.0.1:54321', 'http://127.0.0.1:54321?remote=true']) {
    assert.throws(() => localSettings({ ...status, API_URL }));
  }
});
test('requires local Auth keys', () => {
  assert.throws(() => localSettings({ ...status, SERVICE_ROLE_KEY: '' }));
  assert.throws(() => localSettings({ ...status, ANON_KEY: '' }));
});
