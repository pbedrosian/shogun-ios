import { createDeleteHandler } from './handler.mjs';

Deno.serve(createDeleteHandler({
  url: Deno.env.get('SUPABASE_URL'),
  anon: Deno.env.get('SUPABASE_ANON_KEY'),
  admin: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),
}));
