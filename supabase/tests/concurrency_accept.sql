-- Execute on TWO independent connections, substituting OFFER_ID for each fixture.
-- The caller role is administrative only to set test JWT context; the operation
-- still validates auth.uid(), participant role, ownership, locks, and item state.
do $$ begin
  perform set_config('request.jwt.claims','{"sub":"61000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
  perform set_config('swapcycle.test_started',clock_timestamp()::text,true);
  perform pg_sleep(1);
  begin
    perform public.act_on_offer('OFFER_ID'::uuid,'accept',gen_random_uuid());
    perform set_config('swapcycle.test_result','accepted',true);
  exception when sqlstate 'P0001' then
    perform set_config('swapcycle.test_result',sqlerrm,true);
  end;
  perform set_config('swapcycle.test_finished',clock_timestamp()::text,true);
end $$;
select current_setting('swapcycle.test_started') as started,
  current_setting('swapcycle.test_finished') as finished,
  current_setting('swapcycle.test_result') as result;
