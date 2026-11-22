-- SHO-36: an explicit add-time cover and all copies commit together, with stable retry identity.
create or replace function private.add_movie(actor uuid, request_id uuid, target_library uuid,
  metadata jsonb, copy_formats jsonb, provider_id bigint) returns uuid
language plpgsql set search_path = '' as $$
declare
  film uuid;
  previous private.movie_add_requests%rowtype;
  intent jsonb;
  fmt text;
  cover_selection jsonb;
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
  -- Only provider imports can carry the trusted Edge Function's validated choice.
  cover_selection := case when provider_id is not null then metadata->'_cover' else null end;
  if cover_selection is not null then
    if jsonb_typeof(cover_selection) <> 'object' or not (cover_selection ? 'path')
      or cover_selection - 'path' <> '{}'::jsonb
      or jsonb_typeof(cover_selection->'path') not in ('string','null')
      or (cover_selection->>'path' is not null and cover_selection->>'path' !~ '^/[a-zA-Z0-9._-]+\.(jpg|png|webp)$') then
      raise exception 'Invalid cover' using errcode='22023';
    end if;
  end if;
  intent := jsonb_build_object('library',target_library,'formats',copy_formats,
    'provider',provider_id,'metadata',case when provider_id is null then metadata else null end);
  if cover_selection is not null then intent := intent || jsonb_build_object('cover',cover_selection); end if;
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
  -- This is in the same transaction as the copies. Completed retries return above,
  -- preserving a cover deliberately changed after the original addition.
  if cover_selection is not null then
    perform public.set_movie_cover(actor,provider_id,cover_selection->>'path');
  end if;
  insert into private.movie_add_requests(actor,request_id,payload,library_id,movie_id) values(actor,request_id,intent,target_library,film);
  return film;
end
$$;

-- Legacy import_catalog_movie keeps its exact signature and retry payload.
create function public.import_catalog_movie_with_cover(actor uuid,request_id uuid,target_library uuid,
  metadata jsonb,copy_formats jsonb,provider_id bigint,poster_path text) returns uuid
language sql security definer set search_path = '' as $$
  select private.add_movie(actor,request_id,target_library,
    metadata || jsonb_build_object('_cover',jsonb_build_object('path',poster_path)),copy_formats,provider_id)
$$;
revoke all on function public.import_catalog_movie_with_cover(uuid,uuid,uuid,jsonb,jsonb,bigint,text) from public,anon,authenticated;
grant execute on function public.import_catalog_movie_with_cover(uuid,uuid,uuid,jsonb,jsonb,bigint,text) to service_role;
notify pgrst, 'reload schema';
