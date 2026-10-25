import { createServer } from 'node:http';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../../', import.meta.url));
const require = createRequire(import.meta.url);
const assets = path.dirname(require.resolve('swagger-ui-dist/package.json'));
const api = 'http://127.0.0.1:54321';
const page = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Shogun API</title><link rel="stylesheet" href="/swagger-ui.css">
<style>body{margin:0;background:#faf9f6}header{padding:20px;font:16px system-ui}input{width:min(600px,80%);padding:8px}button{padding:8px}#error{color:#b42318}</style></head>
<body><header><h1>Shogun local API</h1><p>Live database REST documentation. Movie and library endpoints arrive with SHO-18. Auth endpoints are not included.</p>
<label for="token">Optional user access token (JWT, without “Bearer”)</label><br>
<input id="token" type="password" autocomplete="off" placeholder="Leave empty for anonymous access">
<button id="reload">Load API</button><p>Token stays in this page's memory. Try it out sends real requests to your local database.</p><p id="error" role="alert"></p></header>
<div id="swagger-ui"></div><script src="/swagger-ui-bundle.js"></script><script src="/docs.js"></script></body></html>`;

const browserScript = `let token = '';
async function load() {
  token = document.getElementById('token').value.trim();
  const error = document.getElementById('error'); error.textContent = '';
  try {
    const headers = token ? {Authorization: 'Bearer ' + token} : {};
    const response = await fetch('/openapi.json', {headers});
    if (!response.ok) throw new Error('Cannot load the API. Check Supabase is running and the token is valid.');
    const spec = await response.json();
    const config = await fetch('/config.json').then(r => r.json());
    SwaggerUIBundle({spec, dom_id:'#swagger-ui', validatorUrl:null, persistAuthorization:false,
      requestInterceptor(request) {
        const target = new URL(request.url, location.origin);
        if (target.origin !== config.api || !target.pathname.startsWith('/rest/v1')) throw new Error('Only the local REST API is supported.');
        request.headers.apikey = config.key;
        request.headers.Authorization = 'Bearer ' + (token || config.key);
        return request;
      }
    });
  } catch (e) { error.textContent = e.message; }
}
document.getElementById('reload').addEventListener('click', load); load();`;

export function restSpec(spec) {
  // PostgREST advertises its internal container address. Use the local gateway.
  const result = { ...spec, host: '127.0.0.1:54321', basePath: '/rest/v1', schemes: ['http'],
    info: { ...spec.info, title: 'Shogun database REST API' },
    security: [] };
  // The token field above controls both schema discovery and request identity.
  // Avoid a second, conflicting Swagger authorization control.
  delete result.securityDefinitions;
  return result;
}

export function docsServer(key) {
  return createServer(async (request, response) => {
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    const send = (status, type, body) => { response.writeHead(status, {'Content-Type':type}); response.end(body); };
    if (request.headers.host !== '127.0.0.1:54328') return send(403, 'text/plain', 'Local access only');
    if (request.method !== 'GET') return send(405, 'text/plain', 'GET only');
    try {
      switch (request.url) {
        case '/': return send(200, 'text/html; charset=utf-8', page);
        case '/docs.js': return send(200, 'text/javascript', browserScript);
        case '/config.json': return send(200, 'application/json', JSON.stringify({api,key}));
        case '/swagger-ui.css': return send(200, 'text/css', readFileSync(path.join(assets,'swagger-ui.css')));
        case '/swagger-ui-bundle.js': return send(200, 'text/javascript', readFileSync(path.join(assets,'swagger-ui-bundle.js')));
        case '/openapi.json': {
          const upstream = await fetch(api + '/rest/v1/', {
            headers: {apikey:key, Authorization:request.headers.authorization || 'Bearer ' + key, Accept:'application/openapi+json'},
            redirect:'error', signal:AbortSignal.timeout(10_000),
          });
          if (!upstream.ok) return send(upstream.status, 'application/json', JSON.stringify({error:'Local API unavailable or token rejected'}));
          return send(200,'application/json',JSON.stringify(restSpec(await upstream.json())));
        }
        default: return send(404,'text/plain','Not found');
      }
    } catch { send(502,'application/json',JSON.stringify({error:'Start Supabase with npm run backend:start, then reload.'})); }
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const status = JSON.parse(execFileSync(path.join(root,'node_modules/.bin/supabase'),
      ['--workdir',path.join(root,'backend'),'status','-o','json'], {encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout:20_000}));
    if (status.API_URL !== api || !status.ANON_KEY) throw new Error();
    const server = docsServer(status.ANON_KEY);
    server.on('error', () => { console.error('Cannot bind 127.0.0.1:54328. Check whether backend:docs is already running.'); process.exitCode = 1; });
    server.listen(54328,'127.0.0.1',()=>console.log('Swagger UI: http://127.0.0.1:54328 (Ctrl-C to stop)'));
  } catch { console.error('Start local Supabase with npm run backend:start first.'); process.exitCode = 1; }
}
