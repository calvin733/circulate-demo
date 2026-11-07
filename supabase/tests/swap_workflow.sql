-- Complete workflow and failure cases; all fixtures roll back.
begin;
create temp table test_results(name text primary key,passed boolean not null);
create temp table ids(name text primary key,id uuid not null);
grant all on test_results,ids to authenticated;
create function pg_temp.expect_error(label text,command text,expected text) returns void
language plpgsql security invoker as $$ begin
  begin execute command; raise exception 'Expected error %, but statement succeeded',expected;
  exception when others then
    if sqlerrm<>expected then raise; end if;
    insert into test_results values(label,true);
  end;
end $$;
insert into auth.users(id,email,aud,role,email_confirmed_at,created_at,updated_at,raw_app_meta_data,raw_user_meta_data) values
('11000000-0000-4000-8000-000000000001','workflow-a@example.test','authenticated','authenticated',now(),now(),now(),'{}','{"display_name":"Workflow A"}'),
('11000000-0000-4000-8000-000000000002','workflow-b@example.test','authenticated','authenticated',now(),now(),now(),'{}','{"display_name":"Workflow B"}'),
('11000000-0000-4000-8000-000000000003','workflow-c@example.test','authenticated','authenticated',now(),now(),now(),'{}','{"display_name":"Workflow C"}');
insert into public.items(id,owner_id,category_slug,title,description,condition,city,status)
select id::uuid,owner::uuid,'books',label,'Deskripsi barang fixture untuk pengujian workflow.','good','Tangerang','available'
from (values
('21000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000001','Barang A satu'),
('21000000-0000-4000-8000-000000000002','11000000-0000-4000-8000-000000000001','Barang A dua'),
('21000000-0000-4000-8000-000000000003','11000000-0000-4000-8000-000000000002','Barang B satu'),
('21000000-0000-4000-8000-000000000004','11000000-0000-4000-8000-000000000002','Barang B dua'),
('21000000-0000-4000-8000-000000000005','11000000-0000-4000-8000-000000000003','Barang C satu'),
('21000000-0000-4000-8000-000000000006','11000000-0000-4000-8000-000000000001','Barang A tiga')) as fixture(id,owner,label);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
insert into ids values('main',public.create_offer('21000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000003','', '41000000-0000-4000-8000-000000000001'));
insert into test_results values('Create retry is idempotent',
  (select id from ids where name='main')=public.create_offer('21000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000003','', '41000000-0000-4000-8000-000000000001'));
select pg_temp.expect_error('Payload mismatch rejected',
  $$select public.create_offer('21000000-0000-4000-8000-000000000002','21000000-0000-4000-8000-000000000003','','41000000-0000-4000-8000-000000000001')$$,'IDEMPOTENCY_MISMATCH');
select pg_temp.expect_error('Self swap rejected',
  $$select public.create_offer('21000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000002','',gen_random_uuid())$$,'SELF_SWAP');
select pg_temp.expect_error('Forged offered owner rejected',
  $$select public.create_offer('21000000-0000-4000-8000-000000000003','21000000-0000-4000-8000-000000000002','',gen_random_uuid())$$,'NOT_OWNER');
select pg_temp.expect_error('Requester cannot accept',
  $$select public.act_on_offer((select id from ids where name='main'),'accept',gen_random_uuid())$$,'INVALID_TRANSITION');
select pg_temp.expect_error('Duplicate pending pair rejected',
  $$select public.create_offer('21000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000003','',gen_random_uuid())$$,'DUPLICATE_OFFER');
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
insert into ids values('competitor',public.create_offer('21000000-0000-4000-8000-000000000005','21000000-0000-4000-8000-000000000003','',gen_random_uuid()));
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.act_on_offer((select id from ids where name='main'),'accept',gen_random_uuid());
insert into test_results values('Conflicting offer invalidated',exists(select 1 from public.swap_offers where id=(select id from ids where name='competitor') and status='invalidated'));
insert into test_results values('Acceptance captured immutable snapshot',(select count(*)=1 from public.offer_snapshots where offer_id=(select id from ids where name='main')));
insert into test_results values('Acceptance still waits for explicit receipt',exists(select 1 from public.swap_offers where id=(select id from ids where name='main') and requester_confirmed_at is null and recipient_confirmed_at is null));
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
insert into ids values('meet1',public.propose_meetup((select id from ids where name='main'),'Perpustakaan kota',now()+interval '1 hour','Asia/Jakarta',''));
select pg_temp.expect_error('Cannot approve own proposal',
  $$select public.approve_meetup((select id from ids where name='meet1'),1)$$,'INVALID_MEETUP_APPROVAL');
insert into ids values('meet2',public.propose_meetup((select id from ids where name='main'),'Taman kota',now()+interval '2 hours','Asia/Jakarta',''));
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select pg_temp.expect_error('Stale meetup version rejected',
  $$select public.approve_meetup((select id from ids where name='meet1'),1)$$,'INVALID_MEETUP_APPROVAL');
select public.approve_meetup((select id from ids where name='meet2'),2);
insert into test_results values('Optional meetup does not imply completion',exists(select 1 from public.swap_offers where id=(select id from ids where name='main') and status='accepted'));
reset role;
insert into test_results values('Both items reserved atomically',(select count(*)=2 from swapcycle_private.item_reservations where offer_id=(select id from ids where name='main')));
-- Advance only fixture time to represent a real completed meetup.
update public.meetup_proposals set scheduled_at=now()-interval '1 minute' where id=(select id from ids where name='meet2');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.act_on_offer((select id from ids where name='main'),'confirm_receipt','41000000-0000-4000-8000-000000000002');
insert into test_results values('First confirmation does not finish',exists(select 1 from public.swap_offers where id=(select id from ids where name='main') and status='awaiting_confirmation' and requester_confirmed_at is not null and recipient_confirmed_at is null));
select public.act_on_offer((select id from ids where name='main'),'confirm_receipt','41000000-0000-4000-8000-000000000002');
insert into test_results values('Same actor retry counted once',(select count(*)=1 from public.offer_events where offer_id=(select id from ids where name='main') and event_type='confirm_receipt'));
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.act_on_offer((select id from ids where name='main'),'confirm_receipt',gen_random_uuid());
insert into test_results values('Second actor completes',exists(select 1 from public.swap_offers where id=(select id from ids where name='main') and status='completed' and requester_confirmed_at is not null and recipient_confirmed_at is not null));
reset role;
insert into test_results values('Both items exchanged',(select count(*)=2 from public.items where id in('21000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000003') and status='exchanged'));
insert into test_results values('Completion clears reservations',not exists(select 1 from swapcycle_private.item_reservations where offer_id=(select id from ids where name='main')));
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select pg_temp.expect_error('Exchanged listing cannot be offered again',
  $$select public.create_offer('21000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000004','',gen_random_uuid())$$,'ITEM_UNAVAILABLE');
insert into ids values('cancel',public.create_offer('21000000-0000-4000-8000-000000000002','21000000-0000-4000-8000-000000000004','',gen_random_uuid()));
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.act_on_offer((select id from ids where name='cancel'),'accept',gen_random_uuid());
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.act_on_offer((select id from ids where name='cancel'),'request_cancellation',gen_random_uuid(),'Jadwal pertemuan tidak cocok');
select pg_temp.expect_error('Cannot approve own cancellation',
  $$select public.act_on_offer((select id from ids where name='cancel'),'approve_cancellation',gen_random_uuid())$$,'INVALID_TRANSITION');
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.act_on_offer((select id from ids where name='cancel'),'approve_cancellation',gen_random_uuid());
insert into test_results values('Mutual cancellation ends offer',exists(select 1 from public.swap_offers where id=(select id from ids where name='cancel') and status='cancelled'));
insert into test_results values('Mutual cancellation releases items',(select count(*)=2 from public.items where id in('21000000-0000-4000-8000-000000000002','21000000-0000-4000-8000-000000000004') and status='available'));
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
insert into ids values('dispute',public.create_offer('21000000-0000-4000-8000-000000000002','21000000-0000-4000-8000-000000000004','',gen_random_uuid()));
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.act_on_offer((select id from ids where name='dispute'),'accept',gen_random_uuid());
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.act_on_offer((select id from ids where name='dispute'),'dispute',gen_random_uuid(),'Barang tidak sesuai deskripsi');
insert into test_results values('Dispute recorded and report created',exists(select 1 from public.swap_offers where id=(select id from ids where name='dispute') and status='disputed') and exists(select 1 from public.reports where offer_id=(select id from ids where name='dispute')));
select pg_temp.expect_error('No normal confirmation during dispute',
  $$select public.act_on_offer((select id from ids where name='dispute'),'confirm_receipt',gen_random_uuid())$$,'INVALID_TRANSITION');
reset role;
insert into test_results values('Dispute holds both reservations',(select count(*)=2 from swapcycle_private.item_reservations where offer_id=(select id from ids where name='dispute')));
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
insert into test_results values('Third party cannot read snapshots',(select count(*)=0 from public.offer_snapshots));
select pg_temp.expect_error('Third party cannot act on active offer',
  $$select public.act_on_offer((select id from ids where name='dispute'),'dispute',gen_random_uuid(),'Palsu dari pihak ketiga')$$,'NOT_PARTICIPANT');
insert into ids values('expiry',public.create_offer('21000000-0000-4000-8000-000000000005','21000000-0000-4000-8000-000000000006','',gen_random_uuid()));
reset role;
update public.swap_offers set expires_at=now()-interval '1 second' where id=(select id from ids where name='expiry');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select pg_temp.expect_error('Expiry checked without scheduler',
  $$select public.act_on_offer((select id from ids where name='expiry'),'accept',gen_random_uuid())$$,'EXPIRED');
reset role;
do $$ begin
  if (select count(*) from test_results)<25 or exists(select 1 from test_results where not passed) then
    raise exception 'Workflow assertions failed: %',(select jsonb_agg(to_jsonb(r)) from test_results r);
  end if;
end $$;
rollback;
select 'PASS' as result,'All workflow fixtures rolled back' as cleanup;
