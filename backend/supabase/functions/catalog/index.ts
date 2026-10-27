import { createCatalogHandler } from './handler.mjs';
Deno.serve(createCatalogHandler({
  url: Deno.env.get('SUPABASE_URL'),
  anon: Deno.env.get('SUPABASE_ANON_KEY'),
  tmdbToken: Deno.env.get('TMDB_READ_ACCESS_TOKEN'),
}));
