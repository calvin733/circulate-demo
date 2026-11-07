-- Test-only identity. Replace HASH_FROM_DISPOSABLE_FIXTURE with a random bcrypt
-- hash generated for this test, never a real user's password or credential.
update auth.users set encrypted_password='HASH_FROM_DISPOSABLE_FIXTURE',
  instance_id='00000000-0000-0000-0000-000000000000',confirmation_token='',recovery_token='',email_change='',email_change_token_new='',
  raw_app_meta_data='{"provider":"email","providers":["email"]}'::jsonb
  where id='61000000-0000-4000-8000-000000000002';
insert into auth.identities(provider_id,user_id,identity_data,provider,created_at,updated_at)
values('61000000-0000-4000-8000-000000000002','61000000-0000-4000-8000-000000000002',
  '{"sub":"61000000-0000-4000-8000-000000000002","email":"race-b@example.test","email_verified":true,"phone_verified":false}'::jsonb,
  'email',now(),now());
-- This delay affects only the two disposable fixture offers, so a second real
-- HTTP request reaches the database before the first transaction commits.
create function swapcycle_private.race_test_delay() returns trigger
language plpgsql security definer set search_path='' as $$ begin perform pg_sleep(2); return new; end $$;
create trigger swapcycle_race_test_delay before update on public.swap_offers
for each row when (old.status='pending' and new.status='accepted' and new.id in(
'63000000-0000-4000-8000-000000000001'::uuid,'63000000-0000-4000-8000-000000000002'::uuid))
execute function swapcycle_private.race_test_delay();
