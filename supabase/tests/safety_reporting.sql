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
insert into ids values('report',public.submit_report('item','21000000-0000-4000-8000-000000000003','misleading','Foto dan deskripsi tidak sesuai.','51000000-0000-4000-8000-000000000001'));
insert into test_results values('Report retry is idempotent',(select id from ids where name='report')=public.submit_report('item','21000000-0000-4000-8000-000000000003','misleading','Foto dan deskripsi tidak sesuai.','51000000-0000-4000-8000-000000000001'));
select pg_temp.expect_error('Report retry payload is bound',$$select public.submit_report('user','11000000-0000-4000-8000-000000000002','other','Payload berubah.','51000000-0000-4000-8000-000000000001')$$,'IDEMPOTENCY_MISMATCH');
select pg_temp.expect_error('Self report rejected',$$select public.submit_report('user','11000000-0000-4000-8000-000000000001','other','Laporan diri sendiri.',gen_random_uuid())$$,'NOT_FOUND');
insert into ids values('active',public.create_offer('21000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000003','',gen_random_uuid()));
insert into ids values('pending',public.create_offer('21000000-0000-4000-8000-000000000002','21000000-0000-4000-8000-000000000004','',gen_random_uuid()));
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.act_on_offer((select id from ids where name='active'),'accept',gen_random_uuid());
insert into test_results values('B cannot read A report',not exists(select 1 from public.reports));
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.set_user_block('11000000-0000-4000-8000-000000000002',true);
select public.set_user_block('11000000-0000-4000-8000-000000000002',true);
insert into test_results values('Repeat block does not duplicate',(select count(*)=1 from public.user_blocks));
insert into test_results values('Block invalidates pending',exists(select 1 from public.swap_offers where id=(select id from ids where name='pending') and status='invalidated'));
insert into test_results values('Block holds active swap as disputed',exists(select 1 from public.swap_offers where id=(select id from ids where name='active') and status='disputed'));
select pg_temp.expect_error('Block prevents new offer',$$select public.create_offer('21000000-0000-4000-8000-000000000002','21000000-0000-4000-8000-000000000004','',gen_random_uuid())$$,'USER_BLOCKED');
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
insert into test_results values('C cannot read blocks or reports',(select count(*)=0 from public.user_blocks) and (select count(*)=0 from public.reports));
select pg_temp.expect_error('Third party cannot report private offer',$$select public.submit_report('offer',(select id from ids where name='active'),'other','Laporan bukan peserta.',gen_random_uuid())$$,'NOT_PARTICIPANT');
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.set_user_block('11000000-0000-4000-8000-000000000002',false);
insert into test_results values('Unblock removes own block',(select count(*)=0 from public.user_blocks));
insert into test_results values('Unblock never reopens disputed',exists(select 1 from public.swap_offers where id=(select id from ids where name='active') and status='disputed'));
do $$ begin
  for i in 1..9 loop perform public.submit_report('user','11000000-0000-4000-8000-000000000002','other','Fixture report for rate limit.',gen_random_uuid()); end loop;
end $$;
select pg_temp.expect_error('Daily report limit enforced',$$select public.submit_report('user','11000000-0000-4000-8000-000000000002','other','Too many reports fixture.',gen_random_uuid())$$,'RATE_LIMITED');
reset role;
insert into test_results values('Disputed reservation retained',(select count(*)=2 from swapcycle_private.item_reservations where offer_id=(select id from ids where name='active')));
do $$ begin if exists(select 1 from test_results where not passed) then raise exception 'Safety assertion failed'; end if; end $$;
select name,passed from test_results order by name;
rollback;
