-- Destructive rollback of SHO-18 only. NOT an automatically applied migration.
-- Back up application data first. Existing Auth accounts are retained.
-- No CASCADE: unrelated dependencies must cause an explicit failure/review.
drop trigger if exists shogun_user_created on auth.users;
drop function if exists public.bootstrap_account();
drop function if exists public.create_shared_library(text);
drop table if exists public.user_preferences;
drop table if exists public.personal_movie_state;
drop table if exists public.owned_copies;
drop table if exists public.library_memberships;
drop table if exists public.movies;
drop table if exists public.libraries;
drop table if exists public.profiles;
drop function if exists private.on_user_created();
drop function if exists private.clear_revoked_default();
drop function if exists private.can_read_movie(uuid);
drop function if exists private.bootstrap_account(uuid);
drop function if exists private.library_role(uuid);
notify pgrst, 'reload schema';
