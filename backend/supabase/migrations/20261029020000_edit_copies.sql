-- Edit owned copies without changing movie metadata or private diary state.
create function public.edit_collection_copies(target_library uuid, target_movie uuid,
  expected_copies jsonb, copy_formats jsonb) returns boolean
language plpgsql security definer set search_path = '' as $$
declare current_copies jsonb; current_formats jsonb; fmt text; wanted integer;
begin
  perform 1 from public.library_memberships where library_id=target_library
    and user_id=auth.uid() and role in ('owner','editor') for share;
  if not found then raise exception 'Library write access required' using errcode='42501'; end if;
  -- Parent lock blocks concurrent inserts through the copy FK; row locks block updates/deletes.
  perform 1 from public.libraries where id=target_library for update;
  perform 1 from public.owned_copies where library_id=target_library and movie_id=target_movie order by id for update;
  if jsonb_typeof(copy_formats) is distinct from 'array' or jsonb_typeof(expected_copies) is distinct from 'array' then
    raise exception 'Invalid copies' using errcode='22023';
  end if;
  if jsonb_array_length(copy_formats)>99 or exists(select 1 from jsonb_array_elements(copy_formats) f
    where jsonb_typeof(f)<>'string' or f #>> '{}' not in ('VHS','DVD','Blu-ray','4K UHD','Digital')) then
    raise exception 'Invalid copies' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'format',format) order by id),'[]') into current_copies
    from public.owned_copies where library_id=target_library and movie_id=target_movie;
  select coalesce(jsonb_agg(format order by format),'[]') into current_formats
    from public.owned_copies where library_id=target_library and movie_id=target_movie;
  -- An uncertain successful response can be retried without inserting extra rows.
  if current_formats=(select coalesce(jsonb_agg(f order by f),'[]') from jsonb_array_elements(copy_formats) f) then return true; end if;
  if jsonb_array_length(current_copies)=0 or current_copies is distinct from expected_copies then
    raise exception 'Copies changed. Refresh and reopen the editor.' using errcode='PT409';
  end if;
  -- Insert deficits first so shared manual metadata remains readable throughout the transaction.
  for fmt in select distinct jsonb_array_elements_text(copy_formats) loop
    select count(*)::integer into wanted from jsonb_array_elements_text(copy_formats) f where f=fmt;
    insert into public.owned_copies(library_id,movie_id,format)
      select target_library,target_movie,fmt from generate_series(1,greatest(0,wanted-(select count(*)::integer
        from public.owned_copies where library_id=target_library and movie_id=target_movie and format=fmt)));
  end loop;
  delete from public.owned_copies where id in (
    select id from (select id,format,row_number() over(partition by format order by created_at,id) n
      from public.owned_copies where library_id=target_library and movie_id=target_movie) c
    where n>(select count(*) from jsonb_array_elements_text(copy_formats) f where f=c.format));
  return true;
end
$$;
revoke all on function public.edit_collection_copies(uuid,uuid,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.edit_collection_copies(uuid,uuid,jsonb,jsonb) to authenticated;
notify pgrst, 'reload schema';
