begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,email) values('10000000-0000-0000-0000-000000000091','add-cover@shogun.test');
select id as lib from public.libraries where owner_id='10000000-0000-0000-0000-000000000091' and not is_shared \gset
select public.import_catalog_movie_with_cover('10000000-0000-0000-0000-000000000091','40000000-0000-0000-0000-000000000091',:'lib','{"title":"Atomic cover","posterURL":"https://image.tmdb.org/t/p/w342/default.jpg"}','["DVD","4K UHD"]',2147000091,'/one.jpg') as film \gset
select is((select count(*) from public.owned_copies where movie_id=:'film'),2::bigint,'selected cover and both copies saved');
select is((select poster_path from public.movie_cover_preferences where movie_id=:'film'),'/one.jpg','add-time cover saved privately');
select is((select poster_path from public.movies where id=:'film'),'https://image.tmdb.org/t/p/w342/default.jpg','add-time choice does not replace default metadata');
select public.import_catalog_movie_with_cover('10000000-0000-0000-0000-000000000091','40000000-0000-0000-0000-000000000091',:'lib','{"title":"Atomic cover"}','["DVD","4K UHD"]',2147000091,'/one.jpg');
select is((select count(*) from public.owned_copies where movie_id=:'film'),2::bigint,'unchanged add retry does not duplicate copies');
select public.set_movie_cover('10000000-0000-0000-0000-000000000091',2147000091,'/later.jpg');
select public.import_catalog_movie_with_cover('10000000-0000-0000-0000-000000000091','40000000-0000-0000-0000-000000000091',:'lib','{"title":"Atomic cover"}','["DVD","4K UHD"]',2147000091,'/one.jpg');
select is((select poster_path from public.movie_cover_preferences where movie_id=:'film'),'/later.jpg','completed add retry preserves a subsequently changed cover');
select throws_ok(format('select public.import_catalog_movie_with_cover(%L,%L,%L,%L,%L,2147000091,%L)','10000000-0000-0000-0000-000000000091','40000000-0000-0000-0000-000000000091',:'lib','{"title":"Atomic cover"}','["DVD","4K UHD"]','/different.jpg'),'22023',null,'reused request ID with different cover rejected');
select public.import_catalog_movie('10000000-0000-0000-0000-000000000091','40000000-0000-0000-0000-000000000092',:'lib','{"title":"Atomic cover"}','["DVD"]',2147000091);
select is((select poster_path from public.movie_cover_preferences where movie_id=:'film'),'/later.jpg','legacy add without cover preserves current override');
select public.import_catalog_movie_with_cover('10000000-0000-0000-0000-000000000091','40000000-0000-0000-0000-000000000093',:'lib','{"title":"Atomic cover"}','["DVD"]',2147000091,null);
select is((select count(*) from public.movie_cover_preferences where movie_id=:'film'),0::bigint,'explicit default resets cover as part of add');
create function pg_temp.reject_test_cover() returns trigger language plpgsql as $$
begin
 if new.poster_path='/reject.jpg' then raise exception 'Test cover failure' using errcode='22023'; end if;
 return new;
end $$;
create trigger reject_test_cover before insert or update on public.movie_cover_preferences for each row execute function pg_temp.reject_test_cover();
select throws_ok(format('select public.import_catalog_movie_with_cover(%L,%L,%L,%L,%L,2147000092,%L)','10000000-0000-0000-0000-000000000091','40000000-0000-0000-0000-000000000094',:'lib','{"title":"Must roll back"}','["DVD"]','/reject.jpg'),'22023',null,'cover failure rolls back the whole addition');
select is((select count(*) from public.movies where tmdb_id=2147000092),0::bigint,'no orphan metadata after cover failure');
select is((select count(*) from public.owned_copies where library_id=:'lib'),4::bigint,'no extra copy after cover failure');
select is((select count(*) from private.movie_add_requests where request_id='40000000-0000-0000-0000-000000000094'),0::bigint,'failed save leaves retry identity reusable');
select ok(not has_function_privilege('authenticated','public.import_catalog_movie_with_cover(uuid,uuid,uuid,jsonb,jsonb,bigint,text)','execute'),'new trusted import cannot be called by a client');
select ok(not has_function_privilege('anon','public.import_catalog_movie_with_cover(uuid,uuid,uuid,jsonb,jsonb,bigint,text)','execute'),'anonymous cannot use trusted import');
select * from finish();
rollback;
