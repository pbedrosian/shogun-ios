-- SHO-36: validated TMDB covers are private account preferences, never catalog edits.
create table public.movie_cover_preferences (
  user_id uuid not null references public.profiles(id) on delete cascade,
  movie_id uuid not null references public.movies(id) on delete cascade,
  poster_path text not null check (poster_path ~ '^/[a-zA-Z0-9._-]+\.(jpg|png|webp)$'),
  primary key(user_id, movie_id)
);
alter table public.movie_cover_preferences enable row level security;
revoke all on public.movie_cover_preferences from anon, authenticated;
grant select on public.movie_cover_preferences to authenticated;
grant all on public.movie_cover_preferences to service_role;
create policy covers_read on public.movie_cover_preferences for select to authenticated
  using (user_id = (select auth.uid()));

-- Only the authenticated catalog Edge Function may supply a verified actor and TMDB path.
create function public.set_movie_cover(actor uuid, provider_id bigint, poster_path text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare target uuid;
begin
  if actor is null or not exists(select 1 from public.profiles where id=actor) then
    raise exception 'Account required' using errcode='42501';
  end if;
  select id into target from public.movies where source='tmdb' and tmdb_id=provider_id;
  if target is null then raise exception 'Catalog movie required' using errcode='22023'; end if;
  if poster_path is null then
    delete from public.movie_cover_preferences where user_id=actor and movie_id=target;
  else
    insert into public.movie_cover_preferences(user_id,movie_id,poster_path)
      values(actor,target,poster_path)
      on conflict(user_id,movie_id) do update set poster_path=excluded.poster_path;
  end if;
  return true;
end
$$;
revoke all on function public.set_movie_cover(uuid,bigint,text) from public, anon, authenticated;
grant execute on function public.set_movie_cover(uuid,bigint,text) to service_role;

-- Additive field: older clients continue to receive the unchanged default poster_path.
create or replace function public.collection_snapshot() returns jsonb
language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object(
    'libraries', coalesce((select jsonb_agg(l order by l.created_at, l.id) from public.libraries l), '[]'::jsonb),
    'memberships', coalesce((select jsonb_agg(m) from public.library_memberships m where user_id = auth.uid()), '[]'::jsonb),
    'movies', coalesce((select jsonb_agg(to_jsonb(m) || jsonb_build_object('cover_poster_path',
      case when c.poster_path is not null then 'https://image.tmdb.org/t/p/w342' || c.poster_path else null end)
      order by m.title,m.id) from public.movies m left join public.movie_cover_preferences c
      on c.movie_id=m.id and c.user_id=auth.uid()), '[]'::jsonb),
    'copies', coalesce((select jsonb_agg(c order by c.created_at, c.id) from public.owned_copies c), '[]'::jsonb),
    'states', coalesce((select jsonb_agg(s) from public.personal_movie_state s), '[]'::jsonb),
    'default_library_id', (select default_library_id from public.user_preferences where user_id = auth.uid())
  )
$$;
