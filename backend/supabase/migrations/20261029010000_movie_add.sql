-- SHO-3: metadata + all requested copies commit together. Request records are private.
create table private.movie_add_requests (
  actor uuid not null references public.profiles(id) on delete cascade,
  request_id uuid not null,
  payload jsonb not null,
  library_id uuid not null references public.libraries(id) on delete cascade,
  movie_id uuid not null references public.movies(id) on delete cascade,
  primary key(actor, request_id)
);
revoke all on private.movie_add_requests from public, anon, authenticated;

create function private.add_movie(actor uuid, request_id uuid, target_library uuid,
  metadata jsonb, copy_formats jsonb, provider_id bigint) returns uuid
language plpgsql set search_path = '' as $$
declare
  film uuid;
  previous private.movie_add_requests%rowtype;
  intent jsonb;
  fmt text;
begin
  if actor is null or request_id is null or target_library is null then
    raise exception 'Invalid request' using errcode = '22023';
  end if;
  -- Lock membership for the transaction: revocation cannot race an authorized write.
  perform 1 from public.library_memberships where library_id = target_library
    and user_id = actor and role in ('owner','editor') for share;
  if not found then raise exception 'Library write access required' using errcode = '42501'; end if;
  if jsonb_typeof(copy_formats) is distinct from 'array' then
    raise exception 'Invalid copies' using errcode = '22023';
  end if;
  if jsonb_array_length(copy_formats) not between 1 and 99 or exists (
    select 1 from jsonb_array_elements(copy_formats) f
    where jsonb_typeof(f) <> 'string' or f #>> '{}' not in ('VHS','DVD','Blu-ray','4K UHD','Digital')) then
    raise exception 'Invalid copies' using errcode = '22023';
  end if;
  intent := jsonb_build_object('library',target_library,'formats',copy_formats,
    'provider',provider_id,'metadata',case when provider_id is null then metadata else null end);
  perform pg_advisory_xact_lock(hashtextextended(actor::text || request_id::text, 3));
  select * into previous from private.movie_add_requests r where r.actor = add_movie.actor and r.request_id = add_movie.request_id;
  if found then
    if previous.payload is distinct from intent then
      raise exception 'Request identity conflict' using errcode = '22023';
    end if;
    return previous.movie_id;
  end if;
  if jsonb_typeof(metadata) is distinct from 'object'
    or length(btrim(coalesce(metadata->>'title',''))) not between 1 and 500
    or length(coalesce(metadata->>'synopsis','')) > 20000
    or length(coalesce(metadata->>'director','')) > 1000
    or length(coalesce(metadata->>'posterURL','')) > 2048
    or jsonb_typeof(coalesce(metadata->'genres','[]')) <> 'array' then
    raise exception 'Invalid metadata' using errcode = '22023';
  end if;
  if jsonb_array_length(coalesce(metadata->'genres','[]')) > 30 or exists (
    select 1 from jsonb_array_elements(coalesce(metadata->'genres','[]')) g
    where jsonb_typeof(g) <> 'string' or length(g #>> '{}') not between 1 and 100) then
    raise exception 'Invalid genres' using errcode = '22023';
  end if;
  if nullif(metadata->>'posterURL','') is not null and metadata->>'posterURL' !~ '^https://[^/@[:space:]]+(/|$)' then
    raise exception 'Invalid poster URL' using errcode = '22023';
  end if;
  if provider_id is not null then
    if provider_id not between 1 and 2147483647 then raise exception 'Invalid provider' using errcode = '22023'; end if;
    perform pg_advisory_xact_lock(hashtextextended('tmdb:' || provider_id::text, 3));
    select id into film from public.movies where tmdb_id = provider_id;
  end if;
  if film is null then
    insert into public.movies(source,tmdb_id,created_by,title,release_year,synopsis,director,runtime_minutes,genres,poster_path)
      values(case when provider_id is null then 'manual' else 'tmdb' end,provider_id,actor,
        btrim(metadata->>'title'),(metadata->>'year')::integer,coalesce(metadata->>'synopsis',''),
        nullif(btrim(metadata->>'director'),''),(metadata->>'runtimeMinutes')::integer,
        array(select jsonb_array_elements_text(coalesce(metadata->'genres','[]'))),nullif(metadata->>'posterURL',''))
      returning id into film;
  end if;
  for fmt in select jsonb_array_elements_text(copy_formats) loop
    insert into public.owned_copies(library_id,movie_id,format,created_by) values(target_library,film,fmt,actor);
  end loop;
  insert into private.movie_add_requests(actor,request_id,payload,library_id,movie_id) values(actor,request_id,intent,target_library,film);
  return film;
end
$$;
revoke all on function private.add_movie(uuid,uuid,uuid,jsonb,jsonb,bigint) from public,anon,authenticated;

create function public.add_manual_movie(request_id uuid,target_library uuid,metadata jsonb,copy_formats jsonb) returns uuid
language sql security definer set search_path = '' as $$
  select private.add_movie(auth.uid(),request_id,target_library,metadata,copy_formats,null)
$$;
revoke all on function public.add_manual_movie(uuid,uuid,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.add_manual_movie(uuid,uuid,jsonb,jsonb) to authenticated;

-- Only the trusted Edge Function may supply provider metadata and verified actor identity.
create function public.import_catalog_movie(actor uuid,request_id uuid,target_library uuid,metadata jsonb,copy_formats jsonb,provider_id bigint) returns uuid
language sql security definer set search_path = '' as $$
  select private.add_movie(actor,request_id,target_library,metadata,copy_formats,provider_id)
$$;
revoke all on function public.import_catalog_movie(uuid,uuid,uuid,jsonb,jsonb,bigint) from public,anon,authenticated;
grant execute on function public.import_catalog_movie(uuid,uuid,uuid,jsonb,jsonb,bigint) to service_role;
notify pgrst, 'reload schema';
