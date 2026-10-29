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
      } else if (body.operation==='import') {
        if (Object.keys(body).some(k=>!['operation','movieID','requestID','libraryID','formats'].includes(k)) || !validID(body.movieID)
          || ![body.requestID,body.libraryID].every(v=>typeof v==='string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v))
          || !Array.isArray(body.formats) || body.formats.length<1 || body.formats.length>99
          || body.formats.some(v=>!['VHS','DVD','Blu-ray','4K UHD','Digital'].includes(v))) throw new Error();
      } else throw new Error();
    } catch { return reply(400,{error:'invalid_request'}); }
    const session = await verifySession({url:env.url,key:env.anon},authorization,request,incoming.signal);
    if (!session.user) return reply(session.status,{error: session.status===401 ? 'unauthorized' : 'unavailable'});
    try {
      if (body.operation==='search') {
        const query = body.query.trim();
        return reply(200, query ? await client.search(query,body.page,incoming.signal) : {page:1,totalPages:0,results:[]});
      }
      if (body.operation==='import') {
        if (!env.admin) return reply(503,{error:'unavailable'});
        // Fetch canonical details here. Client metadata is never trusted for a provider ID.
        const metadata = await client.details(body.movieID,incoming.signal);
        const response = await request(env.url.replace(/\/$/,'')+'/rest/v1/rpc/import_catalog_movie', {
          method:'POST', redirect:'error', signal:AbortSignal.any([incoming.signal,AbortSignal.timeout(15000)]),
          headers:{apikey:env.admin,Authorization:'Bearer '+env.admin,'Content-Type':'application/json'},
          body:JSON.stringify({actor:session.user.id,request_id:body.requestID,target_library:body.libraryID,
            metadata,copy_formats:body.formats,provider_id:body.movieID}),
        });
        if (!response.ok) {
          const error = await response.json().catch(()=>({}));
          return reply(error.code==='42501' ? 403 : error.code==='22023' ? 400 : 503,{error:'import_failed'});
        }
        return reply(200,{movieID:await response.json()});
      }
      return reply(200,await client.details(body.movieID,incoming.signal));
    } catch (error) {
      return error instanceof CatalogError ? reply(error.status,{error:error.code},error.retryAfter) : reply(503,{error:'provider_unavailable'});
    }
  };
}
