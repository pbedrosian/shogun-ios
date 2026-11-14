import { bearerHeader, verifySession } from '../_shared/session.mjs';
import { createTMDBClient, CatalogError, validID, validPosterPath } from './tmdb.mjs';

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
      } else if (body.operation==='details' || body.operation==='posters') {
        if (Object.keys(body).some(k=>!['operation','movieID'].includes(k)) || !validID(body.movieID)) throw new Error();
      } else if (body.operation==='set_cover') {
        if (Object.keys(body).some(k=>!['operation','movieID','path'].includes(k)) || !validID(body.movieID)
          || (body.path!==null && !validPosterPath(body.path))) throw new Error();
      } else if (body.operation==='import') {
        if (Object.keys(body).some(k=>!['operation','movieID','requestID','libraryID','formats','coverPath'].includes(k)) || !validID(body.movieID)
          || (Object.hasOwn(body,'coverPath') && body.coverPath!==null && !validPosterPath(body.coverPath))
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
      if (body.operation==='posters') return reply(200,{posters:await client.posters(body.movieID,incoming.signal)});
      if (body.operation==='set_cover') {
        if (!env.admin) return reply(503,{error:'unavailable'});
        // A syntactically valid filename is insufficient: it must belong to this movie.
        // Reset remains available even when TMDB is offline.
        if (body.path!==null && !(await client.posters(body.movieID,incoming.signal)).some(p=>p.path===body.path)) {
          return reply(400,{error:'invalid_cover'});
        }
        const response=await request(env.url.replace(/\/$/,'')+'/rest/v1/rpc/set_movie_cover',{
          method:'POST',redirect:'error',signal:AbortSignal.any([incoming.signal,AbortSignal.timeout(15000)]),
          headers:{apikey:env.admin,Authorization:'Bearer '+env.admin,'Content-Type':'application/json'},
          body:JSON.stringify({actor:session.user.id,provider_id:body.movieID,poster_path:body.path}),
        });
        if (!response.ok) {
          const error=await response.json().catch(()=>({}));
          return reply(error.code==='42501'?403:error.code==='22023'?400:503,{error:'cover_save_failed'});
        }
        return reply(200,{saved:true});
      }
      if (body.operation==='import') {
        if (!env.admin) return reply(503,{error:'unavailable'});
        // Fetch canonical details here. Client metadata is never trusted for a provider ID.
        const metadata = await client.details(body.movieID,incoming.signal);
        const withCover = Object.hasOwn(body,'coverPath');
        if (withCover && body.coverPath!==null && !(await client.posters(body.movieID,incoming.signal)).some(p=>p.path===body.coverPath)) {
          return reply(400,{error:'invalid_cover'});
        }
        const response = await request(env.url.replace(/\/$/,'')+'/rest/v1/rpc/'+(withCover?'import_catalog_movie_with_cover':'import_catalog_movie'), {
          method:'POST', redirect:'error', signal:AbortSignal.any([incoming.signal,AbortSignal.timeout(15000)]),
          headers:{apikey:env.admin,Authorization:'Bearer '+env.admin,'Content-Type':'application/json'},
          body:JSON.stringify({actor:session.user.id,request_id:body.requestID,target_library:body.libraryID,
            metadata,copy_formats:body.formats,provider_id:body.movieID,...(withCover?{poster_path:body.coverPath}:{})}),
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
