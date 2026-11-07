-- Run only on the SwapCycle development project. All fixtures roll back.
begin;
create temp table test_results(name text primary key,passed boolean not null);
grant select,insert on test_results to anon,authenticated;
insert into auth.users(id,email,aud,role,email_confirmed_at,created_at,updated_at,raw_app_meta_data,raw_user_meta_data) values
('10000000-0000-4000-8000-000000000001','swapcycle-fixture-a@example.test','authenticated','authenticated',now(),now(),now(),'{}','{"display_name":"Fixture A"}'),
('10000000-0000-4000-8000-000000000002','swapcycle-fixture-b@example.test','authenticated','authenticated',now(),now(),now(),'{}','{"display_name":"Fixture B"}'),
('10000000-0000-4000-8000-000000000003','swapcycle-fixture-c@example.test','authenticated','authenticated',now(),now(),now(),'{}','{"display_name":"Fixture C"}');
insert into public.items(id,owner_id,category_slug,title,description,condition,city,status) values
('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','books','Buku A tersedia','Deskripsi fixture barang A yang cukup panjang.','good','Tangerang','available'),
('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','books','Draft milik A','Deskripsi fixture draft A yang cukup panjang.','good','Tangerang','draft'),
('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000002','home','Barang B tersedia','Deskripsi fixture barang B yang cukup panjang.','good','Tangerang','available'),
('20000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000002','home','Draft milik B','Deskripsi fixture draft B yang cukup panjang.','good','Tangerang','draft');
insert into public.swap_offers(id,requester_id,recipient_id,offered_item_id,requested_item_id,offered_revision,requested_revision)
values('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002',
'20000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000003',1,1);
insert into public.offer_events(offer_id,actor_id,event_type) values('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','created');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
insert into test_results values('A sees public items plus own draft',(select count(*)=3 from public.items));
insert into test_results values('A cannot read B draft',not exists(select 1 from public.items where id='20000000-0000-4000-8000-000000000004'));
insert into test_results values('A can read participant offer',(select count(*)=1 from public.swap_offers));
insert into test_results values('A can read participant timeline',(select count(*)=1 from public.offer_events));
do $$ begin
  begin update public.items set owner_id='10000000-0000-4000-8000-000000000002' where id='20000000-0000-4000-8000-000000000001';
    raise exception 'Direct item UPDATE was permitted';
  exception when insufficient_privilege then insert into test_results values('Direct item mutation denied',true); end;
  begin perform * from swapcycle_private.moderator_roles;
    raise exception 'Private moderator table was readable';
  exception when insufficient_privilege then insert into test_results values('Moderator role table inaccessible',true); end;
  begin perform public.save_item('20000000-0000-4000-8000-000000000004',1,'Attempted takeover','Deskripsi pengambilalihan yang seharusnya ditolak.','home','good','Tangerang','');
    raise exception 'Ownership check failed';
  exception when sqlstate 'P0001' then
    if sqlerrm<>'NOT_OWNER' then raise; end if;
    insert into test_results values('RPC rejects forged ownership',true); end;
  begin perform public.save_item('20000000-0000-4000-8000-000000000002',null,'Draft diubah','Deskripsi fixture draft yang cukup panjang.','books','good','Tangerang','');
    raise exception 'Null revision was accepted';
  exception when sqlstate 'P0001' then
    if sqlerrm<>'STALE_REVISION' then raise; end if;
    insert into test_results values('Null expected revision rejected',true); end;
  begin perform public.set_listing_state('20000000-0000-4000-8000-000000000002',1,'publish');
    raise exception 'Draft without photos was published';
  exception when sqlstate 'P0001' then
    if sqlerrm<>'PHOTO_REQUIRED' then raise; end if;
    insert into test_results values('Publishing requires real photo objects',true); end;
end $$;
select public.save_item('20000000-0000-4000-8000-000000000002',1,'Draft A diperbarui','Deskripsi draft baru yang telah diperbarui dengan aman.','books','good','Tangerang','Buku lain');
insert into test_results values('Owner can update through RPC',exists(select 1 from public.items where id='20000000-0000-4000-8000-000000000002' and revision=2 and title='Draft A diperbarui'));
select public.update_profile('A diperbarui','Tangerang','Bio fixture',null);
insert into test_results values('Profile RPC changes only actor',
  exists(select 1 from public.profiles where id='10000000-0000-4000-8000-000000000001' and display_name='A diperbarui')
  and exists(select 1 from public.profiles where id='10000000-0000-4000-8000-000000000002' and display_name='Fixture B'));
do $$ begin
  begin perform public.update_profile('Fixture A','Tangerang','Bio fixture','other-user/avatar.jpg');
    raise exception 'Forged avatar was accepted';
  exception when sqlstate 'P0001' then
    if sqlerrm<>'INVALID_AVATAR' then raise; end if;
    insert into test_results values('Avatar path ownership validated',true); end;
end $$;

select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
insert into test_results values('C sees only available public listings',(select count(*)=2 from public.items));
insert into test_results values('C cannot read offer',(select count(*)=0 from public.swap_offers));
insert into test_results values('C cannot read timeline',(select count(*)=0 from public.offer_events));
do $$ begin
  begin perform * from swapcycle_private.account_settings;
    raise exception 'Private account table was readable';
  exception when insufficient_privilege then insert into test_results values('Private account state inaccessible',true); end;
end $$;

set local role anon;
select set_config('request.jwt.claims','{}',true);
insert into test_results values('Anon sees only available public listings',(select count(*)=2 from public.items));
do $$ begin
  begin perform * from public.swap_offers;
    raise exception 'Anon read offers';
  exception when insufficient_privilege then insert into test_results values('Anon has no offer table privilege',true); end;
  begin perform public.save_item(gen_random_uuid(),0,'Anon item','This anonymous creation must be rejected.','books','good','Tangerang','');
    raise exception 'Anon executed item mutation';
  exception when insufficient_privilege then insert into test_results values('Anon cannot execute item RPC',true); end;
end $$;

reset role;
insert into test_results values('Both media buckets are private and size limited',
  (select count(*)=2 from storage.buckets where id in ('avatars','item-photos') and not public and file_size_limit=5242880));
insert into test_results values('Every application table has RLS',not exists(
  select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','swapcycle_private') and c.relkind='r' and not c.relrowsecurity));
insert into test_results values('Public RPC wrappers use caller privilege',not exists(
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef));
update swapcycle_private.account_settings set status='suspended' where user_id='10000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ begin
  begin perform public.update_profile('Fixture A','Tangerang','Bio fixture',null);
    raise exception 'Suspended account mutated profile';
  exception when sqlstate 'P0001' then
    if sqlerrm<>'ACCOUNT_NOT_READY' then raise; end if;
    insert into test_results values('Suspended account mutations denied',true); end;
end $$;
reset role;
do $$ begin
  if (select count(*) from test_results)<>23 or exists(select 1 from test_results where not passed) then
    raise exception 'Foundation security assertions failed: %',(select jsonb_agg(to_jsonb(r)) from test_results r);
  end if;
end $$;
rollback;
select 'PASS' as result,23 as assertions,'All fixtures rolled back' as cleanup;
