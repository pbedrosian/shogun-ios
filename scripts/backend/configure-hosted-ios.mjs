import { writeFileSync, chmodSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../../', import.meta.url));

export function hostedIOSConfiguration(rawURL, key) {
  if (typeof rawURL !== 'string' || typeof key !== 'string') throw new Error('Hosted URL and public key are required.');
  if (/\s/.test(key)) throw new Error('The public client key must contain no whitespace.');
  const url = new URL(rawURL);
  const project = /^([a-z0-9]{20})\.supabase\.co$/.exec(url.hostname);
  if (!project || url.protocol !== 'https:' || url.username || url.password || url.port ||
      url.search || url.hash || !['', '/'].includes(url.pathname) || /\s/.test(rawURL)) {
    throw new Error('Use the hosted project HTTPS URL from Supabase.');
  }
  let isPublic = /^sb_publishable_[A-Za-z0-9_-]+$/.test(key);
  if (!isPublic && /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(key)) {
    try {
      const payload = JSON.parse(Buffer.from(key.split('.')[1], 'base64url'));
      isPublic = payload.role === 'anon' && payload.ref === project[1];
    } catch { /* Reject malformed or privileged keys without printing their contents. */ }
  }
  if (!isPublic) throw new Error('Use a publishable key or this hosted project’s legacy anon key.');
  return '// Generated hosted configuration. Public client key only.\n' +
    `SUPABASE_URL = https:/$()/${url.hostname}\nSUPABASE_PUBLISHABLE_KEY = ${key}\n`;
}

export function configureHostedIOS({ configuration, url, key, replace = false, projectRoot = root }) {
  const filenames = { debug: 'Local.xcconfig', release: 'Release.local.xcconfig' };
  if (!Object.hasOwn(filenames, configuration)) throw new Error('Choose debug or release explicitly.');
  const contents = hostedIOSConfiguration(url, key);
  const target = path.join(projectRoot, 'apps/ios/Configuration', filenames[configuration]);
  try {
    writeFileSync(target, contents, { mode: 0o600, flag: replace ? 'w' : 'wx' });
    chmodSync(target, 0o600);
  } catch (error) {
    if (error.code === 'EEXIST') throw new Error('Configuration already exists. Use --replace only when ready to switch environments.');
    throw new Error('Could not write hosted iOS configuration.');
  }
  return target;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const args = process.argv.slice(2);
    if (args[0] !== '--configuration' || !['debug', 'release'].includes(args[1]) ||
        args.length > 3 || (args.length === 3 && args[2] !== '--replace')) {
      throw new Error('Usage: npm run ios:configure:hosted -- --configuration debug|release [--replace]');
    }
    configureHostedIOS({ configuration: args[1], replace: args[2] === '--replace',
      url: process.env.SHOGUN_HOSTED_SUPABASE_URL, key: process.env.SHOGUN_HOSTED_PUBLISHABLE_KEY });
    console.log('Hosted iOS configuration is ready. Rebuild the selected configuration in Xcode.');
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
