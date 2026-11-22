// Provider wire types and credentials stay at this boundary, out of the app and handlers.
export class CatalogError extends Error {
  constructor(status, code, retryAfter) { super(code); this.status = status; this.code = code; this.retryAfter = retryAfter; }
}
const validID = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
export { validID };
const text = (value, fallback = '') => typeof value === 'string' && value.trim() ? value.trim() : fallback;
function artwork(path) {
  return typeof path === 'string' && /^\/[a-zA-Z0-9._-]+\.(jpg|png|webp)$/i.test(path)
    ? 'https://image.tmdb.org/t/p/w342'+path : null;
}
export const validPosterPath = path => typeof path === 'string' && /^\/[a-zA-Z0-9._-]+\.(jpg|png|webp)$/i.test(path);
function movie(value) {
  if (!value || !validID(value.id)) throw new CatalogError(502,'provider_unavailable');
  const match = typeof value.release_date === 'string' && value.release_date.match(/^(\d{4})-\d{2}-\d{2}$/);
  const year = match ? Number(match[1]) : null;
  return { id: value.id, title: text(value.title,'Untitled movie'), year: year >= 1870 && year <= 9999 ? year : null,
    synopsis: text(value.overview,'No synopsis available.'), posterURL: artwork(value.poster_path),
    runtimeMinutes: Number.isSafeInteger(value.runtime) && value.runtime > 0 ? value.runtime : null,
    genres: Array.isArray(value.genres) ? value.genres.map(g=>text(g?.name)).filter(Boolean) : [],
    director: Array.isArray(value.credits?.crew) ? value.credits.crew.filter(p=>p?.job==='Director').map(p=>text(p.name)).filter(Boolean).join(', ') || null : null };
}
export function createTMDBClient(token, request = fetch) {
  async function get(path, params, signal) {
    if (!token?.trim()) throw new CatalogError(503,'catalog_not_configured');
    const url = new URL('https://api.themoviedb.org/3/'+path);
    for (const [key,value] of Object.entries(params)) url.searchParams.set(key,String(value));
    let response;
    try {
      response = await request(url, { headers:{ Authorization:'Bearer '+token.trim(),accept:'application/json' },
        redirect:'error', signal: signal ? AbortSignal.any([signal,AbortSignal.timeout(10000)]) : AbortSignal.timeout(10000) });
    } catch { throw new CatalogError(503,'provider_unavailable'); }
    if (!response.ok) {
      const wait = Number(response.headers.get('Retry-After'));
      if (response.status===429) throw new CatalogError(429,'rate_limited',Number.isInteger(wait) && wait>0 ? Math.min(wait,120) : 5);
      if (response.status===404) throw new CatalogError(404,'movie_not_found');
      throw new CatalogError(503, response.status===401 || response.status===403 ? 'catalog_not_configured' : 'provider_unavailable');
    }
    try { return await response.json(); } catch { throw new CatalogError(502,'provider_unavailable'); }
  }
  return {
    async posters(id,signal) {
      const data = await get('movie/'+id+'/images',{},signal);
      if (data?.id!==id || !Array.isArray(data.posters)) throw new CatalogError(502,'provider_unavailable');
      const seen = new Set();
      return data.posters.filter(p=>validPosterPath(p?.file_path) && Number.isInteger(p.width) && p.width>0
        && Number.isInteger(p.height) && p.height>0 && !seen.has(p.file_path) && seen.add(p.file_path))
        .sort((a,b)=> {
          const rank=p=>p.iso_639_1==='en'?0:p.iso_639_1==null?1:2;
          return rank(a)-rank(b) || (Number(b.vote_average)||0)-(Number(a.vote_average)||0);
        }).map(p=>({path:p.file_path,url:artwork(p.file_path),language:typeof p.iso_639_1==='string'?p.iso_639_1:null,width:p.width,height:p.height}));
    },
    async search(query,page,signal) {
      const data = await get('search/movie',{query,page,include_adult:false,language:'en-US'},signal);
      if (!data || data.page!==page || !Array.isArray(data.results) || !Number.isInteger(data.total_pages) || data.total_pages<0) throw new CatalogError(502,'provider_unavailable');
      const results = data.results.filter(m=>validID(m?.id)).map(movie);
      return { page, totalPages:Math.min(data.total_pages,500), results };
    },
    async details(id,signal) {
      const data = await get('movie/'+id,{language:'en-US',append_to_response:'credits'},signal);
      if (data?.id!==id) throw new CatalogError(502,'provider_unavailable');
      return movie(data);
    },
  };
}
