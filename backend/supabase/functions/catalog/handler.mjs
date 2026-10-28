import { bearerHeader, verifySession } from '../_shared/session.mjs';
import { createTMDBClient, CatalogError, validID } from './tmdb.mjs';

export function createCatalogHandler(env, request = fetch) {
  const client = createTMDBClient(env.tmdbToken,request);
  const reply = (status,body,retryAfter) => Response.json(body,{status,headers:{'Cache-Control':'no-store',...(retryAfter ? {'Retry-After':String(retryAfter)} : {})}});
  return async incoming => {
    if (incoming.method!=='POST') return reply(405,{error:'method_not_allowed'});
    const authorization = incoming.headers.get('Authorization') ?? '';
    if (!bearerHeader(authorization)) return reply(401,{error:'unauthorized'});
    let body;
    try {
      const raw = await incoming.text();
      if (new TextEncoder().encode(raw).length>4096) throw new Error();
      body = JSON.parse(raw);
      if (!body || typeof body!=='object' || Array.isArray(body)) throw new Error();
      if (body.operation==='search') {
        if (Object.keys(body).some(k=>!['operation','query','page'].includes(k)) || typeof body.query!=='string' || body.query.length>200 || !Number.isInteger(body.page) || body.page<1 || body.page>500) throw new Error();
      } else if (body.operation==='details') {
        if (Object.keys(body).some(k=>!['operation','movieID'].includes(k)) || !validID(body.movieID)) throw new Error();
      } else throw new Error();
    } catch { return reply(400,{error:'invalid_request'}); }
    const session = await verifySession({url:env.url,key:env.anon},authorization,request,incoming.signal);
    if (!session.user) return reply(session.status,{error: session.status===401 ? 'unauthorized' : 'unavailable'});
    try {
      if (body.operation==='search') {
        const query = body.query.trim();
        return reply(200, query ? await client.search(query,body.page,incoming.signal) : {page:1,totalPages:0,results:[]});
      }
      return reply(200,await client.details(body.movieID,incoming.signal));
    } catch (error) {
      return error instanceof CatalogError ? reply(error.status,{error:error.code},error.retryAfter) : reply(503,{error:'provider_unavailable'});
    }
  };
}
