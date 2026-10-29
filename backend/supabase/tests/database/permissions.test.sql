begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select no_plan();

-- Disposable accounts exist only inside this transaction. Auth trigger bootstraps them.
insert into auth.users(id, email) values
 ('10000000-0000-0000-0000-000000000001','sql-owner@shogun.test'),
 ('10000000-0000-0000-0000-000000000002','sql-editor@shogun.test'),
 ('10000000-0000-0000-0000-000000000003','sql-viewer@shogun.test'),
 ('10000000-0000-0000-0000-000000000004','sql-outsider@shogun.test');
select is((select count(*) from public.libraries where owner_id::text like '10000000-%'),4::bigint,'one personal library bootstrapped per account');
select is((select count(*) from public.library_memberships where user_id::text like '10000000-%' and role='owner'),4::bigint,'personal owner memberships bootstrapped');
select is((select count(*) from public.user_preferences where user_id::text like '10000000-%' and default_library_id is not null),4::bigint,'default personal libraries set');
select is((select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relname in ('profiles','libraries','library_memberships','movies','owned_copies','personal_movie_state','user_preferences') and c.relrowsecurity),7::bigint,'all API tables have RLS');
select ok(not has_function_privilege('authenticated','private.bootstrap_account(uuid)','execute'),'cannot bootstrap another identity');
select ok(not has_function_privilege('anon','public.bootstrap_account()','execute'),'anonymous cannot invoke bootstrap');

select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where ((n.nspname='private' and p.proname in ('library_role','bootstrap_account','can_read_movie','on_user_created','clear_revoked_default'))
 or (n.nspname='public' and p.proname in ('bootstrap_account','create_shared_library')))
 and p.prosecdef and p.proconfig @> array['search_path=""']),7::bigint,'definer helpers pin empty search paths');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select lives_ok('select public.bootstrap_account()', 'bootstrap retry works');
select is((select count(*) from public.libraries),1::bigint,'bootstrap retry does not duplicate personal library');
select is((select count(*) from public.profiles),1::bigint,'profiles private to current user');
select public.create_shared_library('SQL Family') as family_id \gset
select is((select private.library_role(:'family_id')),'owner','RPC establishes shared owner');
select throws_ok($$insert into public.libraries(owner_id,name) values(auth.uid(),'Bypass')$$,'42501',null,'direct library insert denied');
select throws_ok(format('update public.libraries set owner_id=%L where id=%L','10000000-0000-0000-0000-000000000002',:'family_id'),'42501',null,'ownership cannot be reassigned through table API');
insert into public.library_memberships values
 (:'family_id','10000000-0000-0000-0000-000000000002','editor'),
 (:'family_id','10000000-0000-0000-0000-000000000003','viewer');
select is((select count(*) from public.library_memberships where library_id=:'family_id'),3::bigint,'owner adds editor and viewer');
select throws_ok(format('insert into public.library_memberships values(%L,%L,%L)',:'family_id','10000000-0000-0000-0000-000000000004','owner'),'42501',null,'cannot fabricate second owner');
select throws_ok($$insert into public.library_memberships select id,'10000000-0000-0000-0000-000000000002','editor' from public.libraries where not is_shared$$,'42501',null,'personal library cannot be shared');
insert into public.movies(id,title,release_year) values('20000000-0000-0000-0000-000000000001','Manual film',2026);
insert into public.movies(id,title) values('20000000-0000-0000-0000-000000000002','Unshared manual film');
insert into public.owned_copies(id,library_id,movie_id,format) values
 ('30000000-0000-0000-0000-000000000001',:'family_id','20000000-0000-0000-0000-000000000001','VHS'),
 ('30000000-0000-0000-0000-000000000002',:'family_id','20000000-0000-0000-0000-000000000001','VHS');
select is((select count(*) from public.owned_copies where library_id=:'family_id'),2::bigint,'repeated copies retain separate IDs');
select is((select count(*) from public.movies where id='20000000-0000-0000-0000-000000000001'),1::bigint,'copies share one movie identity');
select throws_ok(format('insert into public.owned_copies(library_id,movie_id,format) values(%L,%L,%L)',:'family_id','20000000-0000-0000-0000-000000000001','Laserdisc'),'23514',null,'format constrained');
select throws_ok($$insert into public.movies(title,source,tmdb_id) values('Spoof','tmdb',123)$$,'42501',null,'TMDB ingestion is server-only');
select throws_ok($$insert into public.movies(title,created_by) values('Spoof','10000000-0000-0000-0000-000000000002')$$,'42501',null,'cannot spoof manual creator');
select throws_ok($$insert into public.movies(title,tmdb_id) values('Invalid manual',123)$$,'42501',null,'manual records cannot claim provider IDs');
insert into public.personal_movie_state(movie_id,watched,rating) values('20000000-0000-0000-0000-000000000001',true,5);
select throws_ok($$update public.personal_movie_state set rating=0$$,'23514',null,'rating lower bound enforced');
select throws_ok($$update public.personal_movie_state set rating=6$$,'23514',null,'rating upper bound enforced');
select lives_ok($$update public.personal_movie_state set rating=null$$,'rating can be cleared');
select throws_ok($$update public.personal_movie_state set user_id='10000000-0000-0000-0000-000000000002'$$,'42501',null,'cannot transfer personal state identity');

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
select is((select count(*) from public.libraries),2::bigint,'editor sees own personal and family library');
select is((select count(*) from public.owned_copies),2::bigint,'editor reads family copies');
select is((select count(*) from public.movies where id::text like '20000000-%'),1::bigint,'editor sees shared manual metadata only');
select is((select count(*) from public.personal_movie_state),0::bigint,'owner diary hidden from editor');
select lives_ok(format('insert into public.owned_copies(library_id,movie_id,format) values(%L,%L,%L)',:'family_id','20000000-0000-0000-0000-000000000001','DVD'),'editor adds copies');
select lives_ok($$update public.owned_copies set format='Blu-ray' where id='30000000-0000-0000-0000-000000000001'$$,'editor changes format');
select is((select format from public.owned_copies where id='30000000-0000-0000-0000-000000000001'),'Blu-ray','editor write actually applied');
with changed as (update public.libraries set name='Hijack' where id=:'family_id' returning id) select is(count(*),0::bigint,'editor cannot rename library') from changed;
with changed as (update public.library_memberships set role='owner' where library_id=:'family_id' returning user_id) select is(count(*),0::bigint,'editor cannot elevate membership') from changed;
select throws_ok(format('insert into public.library_memberships values(%L,%L,%L)',:'family_id','10000000-0000-0000-0000-000000000004','editor'),'42501',null,'editor cannot invite members');
select throws_ok($$update public.owned_copies set library_id=gen_random_uuid()$$,'42501',null,'copies cannot be moved by rewriting identity');
with changed as (update public.movies set title='Hijack' where id='20000000-0000-0000-0000-000000000001' returning id) select is(count(*),0::bigint,'editor cannot overwrite another creator metadata') from changed;
insert into public.personal_movie_state(movie_id,rating) values('20000000-0000-0000-0000-000000000001',3);
select throws_ok($$insert into public.personal_movie_state(user_id,movie_id) values('10000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001')$$,'42501',null,'cannot write someone else diary');
update public.user_preferences set default_library_id=:'family_id';
select is((select default_library_id from public.user_preferences),:'family_id'::uuid,'editor may choose writable shared default');
select throws_ok($$insert into public.owned_copies(library_id,movie_id,format) select id,'ffffffff-ffff-ffff-ffff-ffffffffffff','DVD' from public.libraries where not is_shared$$,'42501',null,'invalid/invisible movie references rejected');
select throws_ok($$insert into public.owned_copies(library_id,movie_id,format) select id,'20000000-0000-0000-0000-000000000002','DVD' from public.libraries where not is_shared$$,'42501',null,'cannot attach guessed private manual movie');

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
select is((select count(*) from public.owned_copies),3::bigint,'viewer reads family copies');
select throws_ok(format('insert into public.owned_copies(library_id,movie_id,format) values(%L,%L,%L)',:'family_id','20000000-0000-0000-0000-000000000001','DVD'),'42501',null,'viewer insert denied');
with changed as (update public.owned_copies set format='Digital' returning id) select is(count(*),0::bigint,'viewer update denied') from changed;
with changed as (delete from public.owned_copies returning id) select is(count(*),0::bigint,'viewer delete denied') from changed;
select throws_ok(format('update public.user_preferences set default_library_id=%L',:'family_id'),'42501',null,'read-only library cannot be default write target');
select is((select count(*) from public.personal_movie_state),0::bigint,'other diaries hidden from viewer');
select lives_ok($$insert into public.personal_movie_state(movie_id,watched,rating) values('20000000-0000-0000-0000-000000000001',true,4)$$,'viewer may keep own personal diary');

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
select is((select count(*) from public.libraries where id=:'family_id'),0::bigint,'outsider cannot read family library');
select is((select count(*) from public.library_memberships where library_id=:'family_id'),0::bigint,'outsider cannot enumerate memberships');
select is((select count(*) from public.owned_copies),0::bigint,'outsider cannot read copies');
select is((select count(*) from public.movies where id::text like '20000000-%'),0::bigint,'outsider cannot read manual metadata');
select throws_ok(format('insert into public.owned_copies(library_id,movie_id,format) values(%L,%L,%L)',:'family_id','20000000-0000-0000-0000-000000000001','DVD'),'42501',null,'outsider cannot write family library');
select throws_ok(format('insert into public.library_memberships values(%L,auth.uid(),%L)',:'family_id','editor'),'42501',null,'outsider cannot enroll themselves');
select throws_ok($$insert into public.personal_movie_state(movie_id) values('20000000-0000-0000-0000-000000000001')$$,'42501',null,'outsider cannot create diary for guessed manual movie');

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
update public.library_memberships set role='viewer' where library_id=:'family_id' and user_id='10000000-0000-0000-0000-000000000002';
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
select is((select default_library_id from public.user_preferences),null::uuid,'downgrade clears unwritable default');
select throws_ok(format('insert into public.owned_copies(library_id,movie_id,format) values(%L,%L,%L)',:'family_id','20000000-0000-0000-0000-000000000001','DVD'),'42501',null,'revoked editor permission effective at next write');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
delete from public.library_memberships where library_id=:'family_id' and user_id='10000000-0000-0000-0000-000000000002';
with changed as (delete from public.library_memberships where library_id=:'family_id' and role='owner' returning user_id) select is(count(*),0::bigint,'owner membership cannot be removed') from changed;
with changed as (delete from public.libraries where not is_shared returning id) select is(count(*),0::bigint,'personal library cannot be deleted by client') from changed;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
select is((select count(*) from public.owned_copies),0::bigint,'membership deletion hides library copies');
select is((select count(*) from public.personal_movie_state),1::bigint,'personal diary survives loss of library membership');

reset role;
insert into public.movies(id,source,tmdb_id,title) values('20000000-0000-0000-0000-000000000003','tmdb',123,'Provider film');
select throws_ok($$insert into public.movies(source,tmdb_id,title) values('tmdb',123,'Duplicate')$$,'23505',null,'provider identity unique');
select throws_ok($$insert into public.library_memberships values('ffffffff-ffff-ffff-ffff-ffffffffffff','10000000-0000-0000-0000-000000000001','viewer')$$,'23503',null,'invalid library reference constrained');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
select is((select count(*) from public.movies where id::text like '20000000-%'),1::bigint,'provider catalog readable by authenticated users');
with changed as (update public.movies set title='Corrupt provider' where source='tmdb' returning id) select is(count(*),0::bigint,'client cannot modify provider metadata') from changed;
select lives_ok($$insert into public.personal_movie_state(movie_id,rating) values('20000000-0000-0000-0000-000000000003',2)$$,'diary does not require owning a movie');
-- Cross-library diary state and membership transitions use the same movie identity.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
insert into public.owned_copies(id,library_id,movie_id,format)
 select '30000000-0000-0000-0000-000000000009',id,'20000000-0000-0000-0000-000000000001','Digital'
 from public.libraries where not is_shared;
select is((select count(*) from public.personal_movie_state),1::bigint,'same movie across libraries keeps one personal state');
select lives_ok($$delete from public.owned_copies where id='30000000-0000-0000-0000-000000000009'$$,'owner can remove copy');
select is((select count(*) from public.owned_copies where id='30000000-0000-0000-0000-000000000009'),0::bigint,'owner deletion applied');
select throws_ok(format('update public.library_memberships set role=%L where library_id=%L and user_id=%L','owner',:'family_id','10000000-0000-0000-0000-000000000003'),'42501',null,'owner cannot promote second owner');
select throws_ok(format('update public.user_preferences set default_library_id=%L',gen_random_uuid()),'42501',null,'invalid default library rejected');
select throws_ok($$insert into public.movies(title,runtime_minutes) values('Bad runtime',0)$$,'23514',null,'runtime must be positive');
select throws_ok($$insert into public.movies(title,release_year) values('Bad year',0)$$,'23514',null,'release year bounded');
select lives_ok(format('update public.libraries set name=%L where id=%L','Renamed family',:'family_id'),'owner renames shared library');
select is((select name from public.libraries where id=:'family_id'),'Renamed family','rename applied');
update public.library_memberships set role='editor' where library_id=:'family_id' and user_id='10000000-0000-0000-0000-000000000003';
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
insert into public.owned_copies(id,library_id,movie_id,format) values('30000000-0000-0000-0000-000000000010',:'family_id','20000000-0000-0000-0000-000000000001','4K UHD');
delete from public.owned_copies where id='30000000-0000-0000-0000-000000000010';
select is((select count(*) from public.owned_copies where id='30000000-0000-0000-0000-000000000010'),0::bigint,'editor may delete a copy');
update public.user_preferences set default_library_id=:'family_id';
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
delete from public.libraries where id=:'family_id';
select is((select count(*) from public.owned_copies where library_id=:'family_id'),0::bigint,'deleting shared library cascades its copies');
select is((select count(*) from public.library_memberships where library_id=:'family_id'),0::bigint,'deleting shared library cascades its memberships');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
select is((select default_library_id from public.user_preferences),null::uuid,'deleted library clears default');
select is((select count(*) from public.personal_movie_state),1::bigint,'library deletion preserves user diary');
-- Authenticated role with no identity must not become an owner through a definer RPC.
select set_config('request.jwt.claim.sub','',true);
select throws_ok('select public.bootstrap_account()','42501',null,'missing identity rejected by bootstrap');
select throws_ok('select public.create_shared_library(''No identity'')','42501',null,'missing identity rejected by library RPC');
-- Account deletion must not remove copies created in another user's library.
reset role;
insert into public.owned_copies(id,library_id,movie_id,format,created_by)
 select '30000000-0000-0000-0000-000000000011',id,'20000000-0000-0000-0000-000000000001','DVD','10000000-0000-0000-0000-000000000002'
 from public.libraries where owner_id='10000000-0000-0000-0000-000000000001' and not is_shared;
delete from auth.users where id='10000000-0000-0000-0000-000000000002';
select is((select count(*) from public.owned_copies where id='30000000-0000-0000-0000-000000000011'),1::bigint,'account deletion preserves copies owned by another library');
select is((select created_by from public.owned_copies where id='30000000-0000-0000-0000-000000000011'),null::uuid,'deleted creator audit reference cleared');
select is((select count(*) from public.personal_movie_state where user_id='10000000-0000-0000-0000-000000000002'),0::bigint,'account deletion removes its private diary');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select throws_ok('select * from public.libraries','42501',null,'anonymous table access denied');
select throws_ok('select public.create_shared_library(''Anonymous'')','42501',null,'anonymous RPC access denied');
reset role;
select * from finish();
rollback;
