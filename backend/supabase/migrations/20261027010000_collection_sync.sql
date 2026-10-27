-- SHO-20: transactional RLS-scoped reads and retry-safe writes.
create function public.collection_snapshot() returns jsonb
language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object(
    'libraries', coalesce((select jsonb_agg(l order by l.created_at, l.id) from public.libraries l), '[]'::jsonb),
    'memberships', coalesce((select jsonb_agg(m) from public.library_memberships m where user_id = auth.uid()), '[]'::jsonb),
    'movies', coalesce((select jsonb_agg(m order by m.title, m.id) from public.movies m), '[]'::jsonb),
    'copies', coalesce((select jsonb_agg(c order by c.created_at, c.id) from public.owned_copies c), '[]'::jsonb),
    'states', coalesce((select jsonb_agg(s) from public.personal_movie_state s), '[]'::jsonb),
    'default_library_id', (select default_library_id from public.user_preferences where user_id = auth.uid())
  )
$$;

create function public.save_collection_copy(copy_id uuid, target_library uuid, target_movie uuid, copy_format text) returns uuid
language plpgsql security invoker set search_path = '' as $$
begin
  -- Recheck on every retry, even if this UUID already exists.
  if auth.uid() is null or private.library_role(target_library) not in ('owner','editor')
    or private.library_role(target_library) is null then
    raise exception 'Library write access required' using errcode = '42501';
  end if;
  insert into public.owned_copies(id, library_id, movie_id, format)
    values(copy_id, target_library, target_movie, copy_format) on conflict (id) do nothing;
  if not exists(select 1 from public.owned_copies where id = copy_id and library_id = target_library
    and movie_id = target_movie and format = copy_format) then
    raise exception 'Copy identity conflict' using errcode = '42501';
  end if;
  return copy_id;
end
$$;

create function public.save_movie_diary(target_movie uuid, is_watched boolean, personal_rating smallint) returns boolean
language plpgsql security invoker set search_path = '' as $$
begin
  insert into public.personal_movie_state(user_id, movie_id, watched, rating)
    values(auth.uid(), target_movie, is_watched, personal_rating)
    on conflict (user_id, movie_id) do update set watched = excluded.watched, rating = excluded.rating;
  return true;
end
$$;

create function public.set_default_library(target_library uuid) returns boolean
language plpgsql security invoker set search_path = '' as $$
begin
  update public.user_preferences set default_library_id = target_library where user_id = auth.uid();
  if not found then raise exception 'Account required' using errcode = '42501'; end if;
  return true;
end
$$;

-- Stable request identity prevents duplicate shared libraries after a lost response.
create function public.create_collection_library(request_id uuid, library_name text) returns uuid
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  perform private.bootstrap_account(auth.uid());
  insert into public.libraries(id, owner_id, name, is_shared)
    values(request_id, auth.uid(), library_name, true) on conflict (id) do nothing;
  if not exists(select 1 from public.libraries where id = request_id and owner_id = auth.uid()
    and is_shared and name = library_name) then
    raise exception 'Library identity conflict' using errcode = '42501';
  end if;
  insert into public.library_memberships(library_id, user_id, role)
    values(request_id, auth.uid(), 'owner') on conflict do nothing;
  return request_id;
end
$$;
revoke all on function public.collection_snapshot(), public.save_collection_copy(uuid,uuid,uuid,text),
  public.save_movie_diary(uuid,boolean,smallint), public.set_default_library(uuid),
  public.create_collection_library(uuid,text) from public, anon, authenticated;
grant execute on function public.collection_snapshot(), public.save_collection_copy(uuid,uuid,uuid,text),
  public.save_movie_diary(uuid,boolean,smallint), public.set_default_library(uuid),
  public.create_collection_library(uuid,text) to authenticated;
notify pgrst, 'reload schema';
