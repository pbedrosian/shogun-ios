-- SHO-18: account data, library ownership and server-enforced access.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '' check (length(display_name) <= 120),
  created_at timestamptz not null default now()
);
create table public.libraries (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 120),
  is_shared boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index one_personal_library_per_user on public.libraries(owner_id) where not is_shared;
create table public.library_memberships (
  library_id uuid not null references public.libraries(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('owner', 'editor', 'viewer')),
  primary key (library_id, user_id)
);
create index memberships_by_user on public.library_memberships(user_id, library_id);
create table public.movies (
  id uuid primary key default gen_random_uuid(),
  source text not null default 'manual' check (source in ('manual', 'tmdb')),
  tmdb_id bigint unique check (tmdb_id > 0),
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  title text not null check (length(btrim(title)) between 1 and 500),
  release_year integer check (release_year between 1870 and 9999),
  synopsis text not null default '',
  director text,
  runtime_minutes integer check (runtime_minutes > 0),
  genres text[] not null default '{}',
  poster_path text,
  created_at timestamptz not null default now(),
  check ((source = 'tmdb' and tmdb_id is not null) or (source = 'manual' and tmdb_id is null))
);
create index movies_by_creator on public.movies(created_by);
create table public.owned_copies (
  id uuid primary key default gen_random_uuid(),
  library_id uuid not null references public.libraries(id) on delete cascade,
  movie_id uuid not null references public.movies(id),
  format text not null check (format in ('VHS', 'DVD', 'Blu-ray', '4K UHD', 'Digital')),
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index copies_by_library_movie on public.owned_copies(library_id, movie_id);
create index copies_by_movie on public.owned_copies(movie_id);
create table public.personal_movie_state (
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  movie_id uuid not null references public.movies(id),
  watched boolean not null default false,
  rating smallint check (rating between 1 and 5),
  primary key (user_id, movie_id)
);
create index personal_state_by_movie on public.personal_movie_state(movie_id);
create table public.user_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  default_library_id uuid references public.libraries(id) on delete set null
);
create index preferences_by_library on public.user_preferences(default_library_id);

-- This helper bypasses membership RLS to avoid recursive policies. It can only
-- report the caller's own role; callers cannot supply another user's identity.
create function private.library_role(target uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case when l.owner_id = auth.uid() then 'owner' else m.role end
  from public.libraries l left join public.library_memberships m
    on m.library_id = l.id and m.user_id = auth.uid()
  where l.id = target
$$;

-- Library creation is atomic. Clients cannot insert libraries/membership owners
-- directly or modify owner_id/is_shared after creation.
create function private.bootstrap_account(target uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare personal uuid;
begin
  insert into public.profiles(id) values(target) on conflict do nothing;
  insert into public.libraries(owner_id, name) values(target, 'My Library')
    on conflict (owner_id) where not is_shared do nothing;
  select id into personal from public.libraries where owner_id = target and not is_shared;
  insert into public.library_memberships(library_id, user_id, role)
    values(personal, target, 'owner') on conflict do nothing;
  insert into public.user_preferences(user_id, default_library_id)
    values(target, personal) on conflict do nothing;
  return personal;
end
$$;
create function public.bootstrap_account() returns uuid
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  return private.bootstrap_account(auth.uid());
end
$$;
create function public.create_shared_library(library_name text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare result uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  perform private.bootstrap_account(auth.uid());
  insert into public.libraries(owner_id, name, is_shared)
    values(auth.uid(), library_name, true) returning id into result;
  insert into public.library_memberships(library_id, user_id, role) values(result, auth.uid(), 'owner');
  return result;
end
$$;
create function private.on_user_created() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform private.bootstrap_account(new.id);
  return new;
end
$$;
create trigger shogun_user_created after insert on auth.users
  for each row execute function private.on_user_created();
-- Preserve existing Auth accounts from SHO-25 without importing demo movie data.
do $$ declare account record; begin
  for account in select id from auth.users loop perform private.bootstrap_account(account.id); end loop;
end $$;

create function private.clear_revoked_default() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' or new.role = 'viewer' then
    update public.user_preferences set default_library_id = null
    where user_id = old.user_id and default_library_id = old.library_id
      and not exists (select 1 from public.libraries where id = old.library_id and owner_id = old.user_id);
  end if;
  return null;
end
$$;
create trigger clear_revoked_default after delete or update on public.library_memberships
  for each row execute function private.clear_revoked_default();

-- Explicit privileges: RLS is mandatory for every table exposed through REST.
alter table public.profiles enable row level security;
alter table public.libraries enable row level security;
alter table public.library_memberships enable row level security;
alter table public.movies enable row level security;
alter table public.owned_copies enable row level security;
alter table public.personal_movie_state enable row level security;
alter table public.user_preferences enable row level security;
revoke all on public.profiles, public.libraries, public.library_memberships,
  public.movies, public.owned_copies, public.personal_movie_state, public.user_preferences from anon, authenticated;
grant select on public.profiles, public.libraries, public.library_memberships,
  public.movies, public.owned_copies, public.personal_movie_state, public.user_preferences to authenticated;
grant update(display_name) on public.profiles to authenticated;
grant update(name) on public.libraries to authenticated;
grant delete on public.libraries to authenticated;
grant insert, delete on public.library_memberships to authenticated;
grant update(role) on public.library_memberships to authenticated;
grant insert on public.movies to authenticated;
grant update(title, release_year, synopsis, director, runtime_minutes, genres, poster_path) on public.movies to authenticated;
grant insert, delete on public.owned_copies to authenticated;
grant update(format) on public.owned_copies to authenticated;
grant insert, delete on public.personal_movie_state to authenticated;
grant update(watched, rating) on public.personal_movie_state to authenticated;
grant update(default_library_id) on public.user_preferences to authenticated;
grant all on public.profiles, public.libraries, public.library_memberships,
  public.movies, public.owned_copies, public.personal_movie_state, public.user_preferences to service_role;

create policy profiles_read on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy profiles_update on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy libraries_read on public.libraries for select to authenticated using (private.library_role(id) is not null);
create policy libraries_update on public.libraries for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy libraries_delete on public.libraries for delete to authenticated using (owner_id = (select auth.uid()) and is_shared);
create policy memberships_read on public.library_memberships for select to authenticated using (private.library_role(library_id) is not null);
create policy memberships_insert on public.library_memberships for insert to authenticated with check (
  private.library_role(library_id) = 'owner' and role in ('editor','viewer')
  and exists (select 1 from public.libraries where id = library_id and is_shared and owner_id <> user_id));
create policy memberships_update on public.library_memberships for update to authenticated
  using (private.library_role(library_id) = 'owner' and role <> 'owner')
  with check (private.library_role(library_id) = 'owner' and role in ('editor','viewer'));
create policy memberships_delete on public.library_memberships for delete to authenticated
  using (private.library_role(library_id) = 'owner' and role <> 'owner');

-- Definer reads prevent policy recursion between movies, copies, and diary rows.
create function private.can_read_movie(target uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.movies m where m.id = target and (
    m.source = 'tmdb' or m.created_by = auth.uid()
    or exists (select 1 from public.owned_copies c where c.movie_id = m.id and private.library_role(c.library_id) is not null)
    or exists (select 1 from public.personal_movie_state s where s.movie_id = m.id and s.user_id = auth.uid())
  ))
$$;
create policy movies_read on public.movies for select to authenticated using (
  source = 'tmdb' or created_by = (select auth.uid()) or private.can_read_movie(id));
create policy movies_insert on public.movies for insert to authenticated with check (
  source = 'manual' and tmdb_id is null and created_by = (select auth.uid()));
create policy movies_update on public.movies for update to authenticated
  using (source = 'manual' and created_by = (select auth.uid()))
  with check (source = 'manual' and created_by = (select auth.uid()));

create policy copies_read on public.owned_copies for select to authenticated using (private.library_role(library_id) is not null);
create policy copies_insert on public.owned_copies for insert to authenticated with check (
  private.library_role(library_id) in ('owner','editor') and created_by = (select auth.uid())
  and exists (select 1 from public.movies m where m.id = movie_id));
create policy copies_update on public.owned_copies for update to authenticated
  using (private.library_role(library_id) in ('owner','editor'))
  with check (private.library_role(library_id) in ('owner','editor'));
create policy copies_delete on public.owned_copies for delete to authenticated using (private.library_role(library_id) in ('owner','editor'));
create policy state_read on public.personal_movie_state for select to authenticated using (user_id = (select auth.uid()));
create policy state_insert on public.personal_movie_state for insert to authenticated with check (
  user_id = (select auth.uid()) and exists (select 1 from public.movies m where m.id = movie_id));
create policy state_update on public.personal_movie_state for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy state_delete on public.personal_movie_state for delete to authenticated using (user_id = (select auth.uid()));
create policy preferences_read on public.user_preferences for select to authenticated using (user_id = (select auth.uid()));
create policy preferences_update on public.user_preferences for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()) and
    (default_library_id is null or private.library_role(default_library_id) in ('owner','editor')));

revoke all on function private.can_read_movie(uuid), private.library_role(uuid), private.bootstrap_account(uuid), private.on_user_created(),
  private.clear_revoked_default(), public.bootstrap_account(), public.create_shared_library(text) from public, anon, authenticated;
grant execute on function private.can_read_movie(uuid), private.library_role(uuid), public.bootstrap_account(), public.create_shared_library(text) to authenticated;
comment on table public.movies is 'Stable metadata identity. TMDB ingestion is server-only; manual records are visible to their creator, accessible collections, and personal diary references.';
comment on table public.owned_copies is 'One physical/digital copy per row. Supply a stable UUID when retrying a create; repeated formats are allowed.';
comment on table public.personal_movie_state is 'Private per-user movie diary, independent of library ownership. Rating is null or 1–5.';
notify pgrst, 'reload schema';
