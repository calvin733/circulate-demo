-- Isolated database policy/workflow fixtures, not working login credentials.
-- Positive/negative email-confirmation states are simulated only within this rollback.
begin;
create temp table mvp_results(name text primary key, passed boolean not null);
create temp table mvp_ids(name text primary key, id uuid not null);
grant select,insert on mvp_results,mvp_ids to anon,authenticated;
create function pg_temp.mvp_check(label text, ok boolean) returns void
language plpgsql security invoker as $$ begin
  if ok is distinct from true then raise exception 'MVP assertion failed: %',label; end if;
  insert into mvp_results values(label,true);
end $$;
create function pg_temp.mvp_error(label text,command text,expected text) returns void
language plpgsql security invoker as $$ begin
  begin execute command; raise exception 'Expected error %, but action succeeded',expected;
  exception when others then
    if sqlerrm<>expected then raise; end if;
    insert into mvp_results values(label,true);
  end;
end $$;

insert into auth.users(id,email,aud,role,email_confirmed_at,created_at,updated_at,raw_app_meta_data,raw_user_meta_data)
select id::uuid,mail,'authenticated','authenticated',confirmed,now(),now(),'{}'::jsonb,
  jsonb_build_object('display_name',label)
from (values
 ('12000000-0000-4000-8000-000000000001','mvp-a@example.test',now(),'MVP A'),
 ('12000000-0000-4000-8000-000000000002','mvp-b@example.test',now(),'MVP B'),
 ('12000000-0000-4000-8000-000000000003','mvp-c@example.test',now(),'MVP C'),
 ('12000000-0000-4000-8000-000000000004','mvp-unverified@example.test',null::timestamptz,'MVP unverified')
) as fixture(id,mail,confirmed,label);

insert into public.items(id,owner_id,category_slug,title,description,condition,city,status)
select id::uuid,owner::uuid,'books',label,'Deskripsi fixture MVP yang cukup panjang.','good','Tangerang',state
from (values
 ('22000000-0000-4000-8000-000000000001','12000000-0000-4000-8000-000000000001','Buku A publik','available'),
 ('22000000-0000-4000-8000-000000000002','12000000-0000-4000-8000-000000000002','Buku B publik','available'),
 ('22000000-0000-4000-8000-000000000003','12000000-0000-4000-8000-000000000001','Barang A pembatalan','available'),
 ('22000000-0000-4000-8000-000000000004','12000000-0000-4000-8000-000000000002','Barang B pembatalan','available'),
 ('22000000-0000-4000-8000-000000000005','12000000-0000-4000-8000-000000000003','Barang C pesaing','available'),
 ('22000000-0000-4000-8000-000000000006','12000000-0000-4000-8000-000000000001','Draft A privat','draft'),
 ('22000000-0000-4000-8000-000000000007','12000000-0000-4000-8000-000000000001','Barang A tenggat','available'),
 ('22000000-0000-4000-8000-000000000008','12000000-0000-4000-8000-000000000002','Barang B tenggat','available')
) as fixture(id,owner,label,state);

-- Metadata-only objects test Storage RLS; no blob or real upload is created.
insert into storage.objects(bucket_id,name,owner,metadata) values
 ('item-photos','12000000-0000-4000-8000-000000000001/22000000-0000-4000-8000-000000000001/linked.jpg','12000000-0000-4000-8000-000000000001','{"mimetype":"image/jpeg","size":128}'),
 ('item-photos','12000000-0000-4000-8000-000000000001/22000000-0000-4000-8000-000000000001/unlinked.jpg','12000000-0000-4000-8000-000000000001','{"mimetype":"image/jpeg","size":128}'),
 ('item-photos','12000000-0000-4000-8000-000000000002/22000000-0000-4000-8000-000000000002/linked.jpg','12000000-0000-4000-8000-000000000002','{"mimetype":"image/jpeg","size":128}'),
 ('item-photos','12000000-0000-4000-8000-000000000001/22000000-0000-4000-8000-000000000006/draft.jpg','12000000-0000-4000-8000-000000000001','{"mimetype":"image/jpeg","size":128}');
insert into public.item_photos(item_id,storage_path,position)
select split_part(name,'/',2)::uuid,name,0 from storage.objects
where bucket_id='item-photos' and name in (
 '12000000-0000-4000-8000-000000000001/22000000-0000-4000-8000-000000000001/linked.jpg',
 '12000000-0000-4000-8000-000000000002/22000000-0000-4000-8000-000000000002/linked.jpg',
 '12000000-0000-4000-8000-000000000001/22000000-0000-4000-8000-000000000006/draft.jpg');

set local role anon;
select set_config('request.jwt.claims','{}',true);
select pg_temp.mvp_check('Anon sees linked public photo',exists(select 1 from storage.objects where name='12000000-0000-4000-8000-000000000001/22000000-0000-4000-8000-000000000001/linked.jpg'));
select pg_temp.mvp_check('Anon cannot see unlinked public-folder photo',not exists(select 1 from storage.objects where name='12000000-0000-4000-8000-000000000001/22000000-0000-4000-8000-000000000001/unlinked.jpg'));
select pg_temp.mvp_check('Anon cannot see draft photo',not exists(select 1 from storage.objects where name='12000000-0000-4000-8000-000000000001/22000000-0000-4000-8000-000000000006/draft.jpg'));

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"12000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select pg_temp.mvp_check('Owner sees unlinked object for recovery',exists(select 1 from storage.objects where name='12000000-0000-4000-8000-000000000001/22000000-0000-4000-8000-000000000001/unlinked.jpg'));
select pg_temp.mvp_check('Owner sees own draft object',exists(select 1 from storage.objects where name='12000000-0000-4000-8000-000000000001/22000000-0000-4000-8000-000000000006/draft.jpg'));
select public.attach_item_photo('22000000-0000-4000-8000-000000000006',0,
 '12000000-0000-4000-8000-000000000001/22000000-0000-4000-8000-000000000006/draft.jpg',0::smallint);
select pg_temp.mvp_check('Attach retry keeps one photo and its revision',
 (select count(*)=1 from public.item_photos where item_id='22000000-0000-4000-8000-000000000006') and
 (select revision=1 from public.items where id='22000000-0000-4000-8000-000000000006'));

insert into mvp_ids values('historical',public.create_offer('22000000-0000-4000-8000-000000000001','22000000-0000-4000-8000-000000000002','',gen_random_uuid()));
select pg_temp.mvp_check('Offer stores minimal safe historical title',exists(select 1 from public.swap_offers where id=(select id from mvp_ids where name='historical') and requested_summary->>'title'='Buku B publik' and not(requested_summary ? 'description') and not(requested_summary ? 'photos')));
select set_config('request.jwt.claims','{"sub":"12000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.set_listing_state('22000000-0000-4000-8000-000000000002',1,'archive');
select public.save_item('22000000-0000-4000-8000-000000000002',2,'Judul privat setelah arsip','Deskripsi privat setelah arsip yang tidak boleh terbuka.','books','good','Tangerang','');
select set_config('request.jwt.claims','{"sub":"12000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select pg_temp.mvp_check('History survives archive without exposing live item',
 exists(select 1 from public.swap_offers where id=(select id from mvp_ids where name='historical') and status='invalidated' and requested_summary->>'title'='Buku B publik')
 and not exists(select 1 from public.items where id='22000000-0000-4000-8000-000000000002'));
select set_config('request.jwt.claims','{"sub":"12000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select pg_temp.mvp_check('Third party cannot read historical summary',not exists(select 1 from public.swap_offers where id=(select id from mvp_ids where name='historical')));
select pg_temp.mvp_check('Third party cannot read unlinked photo',not exists(select 1 from storage.objects where name='12000000-0000-4000-8000-000000000001/22000000-0000-4000-8000-000000000001/unlinked.jpg'));

select set_config('request.jwt.claims','{"sub":"12000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.set_listing_state('22000000-0000-4000-8000-000000000002',3,'publish');
select set_config('request.jwt.claims','{"sub":"12000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
insert into mvp_ids values('main',public.create_offer('22000000-0000-4000-8000-000000000001','22000000-0000-4000-8000-000000000002','',gen_random_uuid()));
select set_config('request.jwt.claims','{"sub":"12000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
insert into mvp_ids values('competitor',public.create_offer('22000000-0000-4000-8000-000000000005','22000000-0000-4000-8000-000000000002','',gen_random_uuid()));
select set_config('request.jwt.claims','{"sub":"12000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.act_on_offer((select id from mvp_ids where name='main'),'accept',gen_random_uuid());
select pg_temp.mvp_check('Acceptance keeps snapshot',exists(select 1 from public.offer_snapshots where offer_id=(select id from mvp_ids where name='main')));
select pg_temp.mvp_check('Acceptance invalidates competing pending offer',exists(select 1 from public.swap_offers where id=(select id from mvp_ids where name='competitor') and status='invalidated'));
select pg_temp.mvp_error('Competing accept cannot reserve same item',
 $$select public.act_on_offer((select id from mvp_ids where name='competitor'),'accept',gen_random_uuid())$$,'INVALID_TRANSITION');
reset role;
select pg_temp.mvp_check('Acceptance reserves exactly two items',(select count(*)=2 from swapcycle_private.item_reservations where offer_id=(select id from mvp_ids where name='main')));
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"12000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
insert into mvp_ids values('receipt_key',gen_random_uuid());
select public.act_on_offer((select id from mvp_ids where name='main'),'confirm_receipt',(select id from mvp_ids where name='receipt_key'));
select pg_temp.mvp_check('First receipt succeeds without meetup and is not completion',exists(select 1 from public.swap_offers where id=(select id from mvp_ids where name='main') and status='awaiting_confirmation' and requester_confirmed_at is not null and recipient_confirmed_at is null));
select public.act_on_offer((select id from mvp_ids where name='main'),'confirm_receipt',(select id from mvp_ids where name='receipt_key'));
select public.act_on_offer((select id from mvp_ids where name='main'),'confirm_receipt',gen_random_uuid());
select pg_temp.mvp_check('Same participant retries count only once',(select count(*)=1 from public.offer_events where offer_id=(select id from mvp_ids where name='main') and event_type='confirm_receipt'));
select set_config('request.jwt.claims','{"sub":"12000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select pg_temp.mvp_error('Third party cannot confirm',
 $$select public.act_on_offer((select id from mvp_ids where name='main'),'confirm_receipt',gen_random_uuid())$$,'NOT_PARTICIPANT');
select set_config('request.jwt.claims','{"sub":"12000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.act_on_offer((select id from mvp_ids where name='main'),'confirm_receipt',gen_random_uuid());
select pg_temp.mvp_check('Two different participants complete',exists(select 1 from public.swap_offers where id=(select id from mvp_ids where name='main') and status='completed' and completed_at is not null and requester_confirmed_at is not null and recipient_confirmed_at is not null));
select pg_temp.mvp_check('Both participants keep completed history',exists(select 1 from public.offer_snapshots where offer_id=(select id from mvp_ids where name='main')));
select pg_temp.mvp_check('Snapshot participant keeps old photo after completion',exists(select 1 from storage.objects where name='12000000-0000-4000-8000-000000000001/22000000-0000-4000-8000-000000000001/linked.jpg'));
select pg_temp.mvp_check('Snapshot access does not expose owner unlinked photo',not exists(select 1 from storage.objects where name='12000000-0000-4000-8000-000000000001/22000000-0000-4000-8000-000000000001/unlinked.jpg'));
reset role;
select pg_temp.mvp_check('Completed items are exchanged',(select count(*)=2 from public.items where id in('22000000-0000-4000-8000-000000000001','22000000-0000-4000-8000-000000000002') and status='exchanged'));
select pg_temp.mvp_check('Completion releases reservations',not exists(select 1 from swapcycle_private.item_reservations where offer_id=(select id from mvp_ids where name='main')));
set local role anon;
select set_config('request.jwt.claims','{}',true);
select pg_temp.mvp_check('Completed photo is not public',not exists(select 1 from storage.objects where name='12000000-0000-4000-8000-000000000001/22000000-0000-4000-8000-000000000001/linked.jpg'));

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"12000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
insert into mvp_ids values('cancel',public.create_offer('22000000-0000-4000-8000-000000000003','22000000-0000-4000-8000-000000000004','',gen_random_uuid()));
select set_config('request.jwt.claims','{"sub":"12000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.act_on_offer((select id from mvp_ids where name='cancel'),'accept',gen_random_uuid());
select set_config('request.jwt.claims','{"sub":"12000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.act_on_offer((select id from mvp_ids where name='cancel'),'request_cancellation',gen_random_uuid(),'Jadwal tidak cocok');
select set_config('request.jwt.claims','{"sub":"12000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.act_on_offer((select id from mvp_ids where name='cancel'),'approve_cancellation',gen_random_uuid());
select pg_temp.mvp_check('Mutual cancellation remains safe',exists(select 1 from public.swap_offers where id=(select id from mvp_ids where name='cancel') and status='cancelled'));
reset role;
select pg_temp.mvp_check('Cancellation releases both items',(select count(*)=2 from public.items where id in('22000000-0000-4000-8000-000000000003','22000000-0000-4000-8000-000000000004') and status='available'));

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"12000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
insert into mvp_ids values('dispute',public.create_offer('22000000-0000-4000-8000-000000000003','22000000-0000-4000-8000-000000000004','',gen_random_uuid()));
select set_config('request.jwt.claims','{"sub":"12000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.act_on_offer((select id from mvp_ids where name='dispute'),'accept',gen_random_uuid());
select set_config('request.jwt.claims','{"sub":"12000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
insert into mvp_ids values('optional_meetup',public.propose_meetup((select id from mvp_ids where name='dispute'),'Perpustakaan kota',now()+interval '1 day','Asia/Jakarta',''));
select public.act_on_offer((select id from mvp_ids where name='dispute'),'confirm_receipt',gen_random_uuid());
select pg_temp.mvp_check('Future unapproved meetup never blocks receipt',exists(select 1 from public.swap_offers where id=(select id from mvp_ids where name='dispute') and status='awaiting_confirmation'));
select set_config('request.jwt.claims','{"sub":"12000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.act_on_offer((select id from mvp_ids where name='dispute'),'request_cancellation',gen_random_uuid(),'Klaim penerimaan perlu ditinjau');
select pg_temp.mvp_check('Conflicting receipt claim stays disputed',exists(select 1 from public.swap_offers where id=(select id from mvp_ids where name='dispute') and status='disputed'));
select pg_temp.mvp_error('Dispute cannot release through normal cancel',
 $$select public.act_on_offer((select id from mvp_ids where name='dispute'),'approve_cancellation',gen_random_uuid())$$,'INVALID_TRANSITION');
reset role;
select pg_temp.mvp_check('Dispute keeps both reservations',(select count(*)=2 from swapcycle_private.item_reservations where offer_id=(select id from mvp_ids where name='dispute')));

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"12000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
insert into mvp_ids values('expiry',public.create_offer('22000000-0000-4000-8000-000000000007','22000000-0000-4000-8000-000000000008','',gen_random_uuid()));
reset role;
update public.swap_offers set expires_at=now()-interval '1 second' where id=(select id from mvp_ids where name='expiry');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"12000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select pg_temp.mvp_error('Server still rejects expired accept',
 $$select public.act_on_offer((select id from mvp_ids where name='expiry'),'accept',gen_random_uuid())$$,'EXPIRED');
select set_config('request.jwt.claims','{"sub":"12000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
select pg_temp.mvp_error('Unverified account still rejected',
 $$select public.update_profile('MVP unverified','Tangerang','',null)$$,'ACCOUNT_NOT_READY');

reset role;
select pg_temp.mvp_check('Anonymous mutator privileges are explicitly closed',not exists(
 select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='swapcycle_private' and p.proname in('save_item','attach_item_photo','detach_item_photo','set_listing_state','update_profile','create_offer','act_on_offer','propose_meetup','approve_meetup')
 and has_function_privilege('anon',p.oid,'EXECUTE')));
select pg_temp.mvp_check('Anonymous catalog helper remains callable',has_function_privilege('anon','swapcycle_private.item_readable(uuid)','EXECUTE'));
select pg_temp.mvp_check('All application tables retain RLS',not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in('public','swapcycle_private') and c.relkind='r' and not c.relrowsecurity));
select 'PASS' as result,count(*) as assertions,'Fixture rows and metadata roll back; not a real email/Auth test' as scope from mvp_results;
rollback;
