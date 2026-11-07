-- Disposable fixture IDs reserved exclusively for this automated test.
begin;
insert into auth.users(id,email,aud,role,email_confirmed_at,created_at,updated_at,raw_app_meta_data,raw_user_meta_data) values
('61000000-0000-4000-8000-000000000001','race-a@example.test','authenticated','authenticated',now(),now(),now(),'{}','{"display_name":"Race A"}'),
('61000000-0000-4000-8000-000000000002','race-b@example.test','authenticated','authenticated',now(),now(),now(),'{}','{"display_name":"Race B"}'),
('61000000-0000-4000-8000-000000000003','race-c@example.test','authenticated','authenticated',now(),now(),now(),'{}','{"display_name":"Race C"}');
insert into public.items(id,owner_id,category_slug,title,description,condition,city,status)
select id::uuid,owner::uuid,'books',label,'Deskripsi fixture khusus pengujian dua request bersamaan.','good','Tangerang','available'
from (values
('62000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','Race barang A'),
('62000000-0000-4000-8000-000000000002','61000000-0000-4000-8000-000000000002','Race barang B'),
('62000000-0000-4000-8000-000000000003','61000000-0000-4000-8000-000000000003','Race barang C')) as fixture(id,owner,label);
insert into public.swap_offers(id,requester_id,recipient_id,offered_item_id,requested_item_id,offered_revision,requested_revision) values
('63000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000002','62000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000002',1,1),
('63000000-0000-4000-8000-000000000002','61000000-0000-4000-8000-000000000003','61000000-0000-4000-8000-000000000002','62000000-0000-4000-8000-000000000003','62000000-0000-4000-8000-000000000002',1,1);
commit;
