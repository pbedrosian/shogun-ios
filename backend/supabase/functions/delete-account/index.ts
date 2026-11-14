import { createDeleteHandler } from './handler.mjs';

Deno.serve(createDeleteHandler({
  url: Deno.env.get('SUPABASE_URL'),
  anon: Deno.env.get('SUPABASE_ANON_KEY'),
  admin: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),
  apple: {
    teamID: Deno.env.get('APPLE_TEAM_ID'),
    keyID: Deno.env.get('APPLE_KEY_ID'),
    privateKey: Deno.env.get('APPLE_PRIVATE_KEY'),
    clientIDs: (Deno.env.get('APPLE_CLIENT_IDS') ?? '').split(',').map(value => value.trim()).filter(Boolean),
  },
}));
