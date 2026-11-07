-- Reports do not automatically punish a user or release disputed reservations.
create function swapcycle_private.submit_report(p_kind text,p_target uuid,p_reason text,p_details text,p_request_key uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=swapcycle_private.require_member(); payload jsonb; prior swapcycle_private.idempotency_requests; result uuid;
begin
  perform swapcycle_private.lock_members(array[actor]);
  payload:=jsonb_build_object('kind',p_kind,'target',p_target,'reason',p_reason,'details',btrim(p_details));
  select * into prior from swapcycle_private.idempotency_requests where actor_id=actor and request_key=p_request_key and operation='submit_report';
  if found then
    if prior.payload<>payload then raise exception using errcode='P0001',message='IDEMPOTENCY_MISMATCH'; end if;
    return prior.result_id;
  end if;
  if p_request_key is null or p_reason is null or p_reason not in ('prohibited','misleading','harassment','no_show','condition_mismatch','other')
    or p_details is null or char_length(btrim(p_details)) not between 5 and 2000 then raise exception using errcode='P0001',message='REASON_REQUIRED'; end if;
  if (select count(*) from public.reports where reporter_id=actor and created_at>now()-interval '1 day')>=10 then
    raise exception using errcode='P0001',message='RATE_LIMITED'; end if;
  if p_kind='item' then
    if not swapcycle_private.item_readable(p_target) or not exists(select 1 from public.items where id=p_target and owner_id<>actor) then
      raise exception using errcode='P0001',message='NOT_FOUND'; end if;
  elsif p_kind='user' then
    if p_target=actor or not exists(select 1 from public.profiles where id=p_target) then raise exception using errcode='P0001',message='NOT_FOUND'; end if;
  elsif p_kind='offer' then
    if not exists(select 1 from public.swap_offers where id=p_target and actor in(requester_id,recipient_id)) then raise exception using errcode='P0001',message='NOT_PARTICIPANT'; end if;
  else raise exception using errcode='P0001',message='INVALID_ACTION'; end if;
  insert into public.reports(reporter_id,item_id,reported_user_id,offer_id,reason,details)
    values(actor,case when p_kind='item' then p_target end,case when p_kind='user' then p_target end,case when p_kind='offer' then p_target end,p_reason,btrim(p_details)) returning id into result;
  insert into swapcycle_private.idempotency_requests(actor_id,request_key,operation,payload,result_id) values(actor,p_request_key,'submit_report',payload,result);
  return result;
end $$;
create function public.submit_report(p_kind text,p_target uuid,p_reason text,p_details text,p_request_key uuid)
returns uuid language sql security invoker set search_path='' as $$ select swapcycle_private.submit_report(p_kind,p_target,p_reason,p_details,p_request_key); $$;

create function swapcycle_private.set_user_block(p_target uuid,p_blocked boolean)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=swapcycle_private.require_member(); affected uuid[];
begin
  if p_target is null or p_target=actor or p_blocked is null or not exists(select 1 from public.profiles where id=p_target) then
    raise exception using errcode='P0001',message='NOT_FOUND'; end if;
  perform swapcycle_private.lock_members(array[actor,p_target]);
  if p_blocked then
    insert into public.user_blocks(blocker_id,blocked_id) values(actor,p_target) on conflict do nothing;
    select array_agg(id) into affected from public.swap_offers where requester_id in(actor,p_target) and recipient_id in(actor,p_target)
      and status in('pending','accepted','awaiting_confirmation','cancellation_requested');
    perform 1 from public.items where id in(select offered_item_id from public.swap_offers where id=any(affected)
      union select requested_item_id from public.swap_offers where id=any(affected)) order by id for update;
    perform 1 from public.swap_offers where id=any(affected) order by id for update;
    with changed as (
      update public.swap_offers set status=case when status='pending' then 'invalidated' else 'disputed' end,updated_at=now()
      where id=any(affected) returning id,status
    ) insert into public.offer_events(offer_id,actor_id,event_type,metadata)
      select id,actor,case when status='invalidated' then 'invalidated' else 'dispute' end,jsonb_build_object('reason','user_block') from changed;
  else delete from public.user_blocks where blocker_id=actor and blocked_id=p_target;
  end if;
  return p_target;
end $$;
create function public.set_user_block(p_target uuid,p_blocked boolean)
returns uuid language sql security invoker set search_path='' as $$ select swapcycle_private.set_user_block(p_target,p_blocked); $$;

revoke all on function public.submit_report(text,uuid,text,text,uuid),public.set_user_block(uuid,boolean),
  swapcycle_private.submit_report(text,uuid,text,text,uuid),swapcycle_private.set_user_block(uuid,boolean) from public,anon,authenticated;
grant execute on function public.submit_report(text,uuid,text,text,uuid),public.set_user_block(uuid,boolean),
  swapcycle_private.submit_report(text,uuid,text,text,uuid),swapcycle_private.set_user_block(uuid,boolean) to authenticated;
