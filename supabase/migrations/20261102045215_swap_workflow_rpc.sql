create function swapcycle_private.check_swap_items(actor uuid,offered public.items,requested public.items) returns void
language plpgsql security definer set search_path='' as $$
begin
  if offered.id is null or requested.id is null then raise exception using errcode='P0001',message='NOT_FOUND'; end if;
  if offered.owner_id<>actor then raise exception using errcode='P0001',message='NOT_OWNER'; end if;
  if offered.owner_id=requested.owner_id or offered.id=requested.id then raise exception using errcode='P0001',message='SELF_SWAP'; end if;
  if offered.status<>'available' or requested.status<>'available' or offered.visibility<>'visible' or requested.visibility<>'visible' then
    raise exception using errcode='P0001',message='ITEM_UNAVAILABLE'; end if;
  if exists(select 1 from swapcycle_private.account_settings a where a.user_id in (offered.owner_id,requested.owner_id) and a.status<>'active') then
    raise exception using errcode='P0001',message='ACCOUNT_NOT_READY'; end if;
  if exists(select 1 from public.user_blocks b where
    (b.blocker_id=offered.owner_id and b.blocked_id=requested.owner_id) or
    (b.blocker_id=requested.owner_id and b.blocked_id=offered.owner_id)) then
    raise exception using errcode='P0001',message='USER_BLOCKED'; end if;
end $$;
create function swapcycle_private.item_snapshot(target uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',i.id,'owner_id',i.owner_id,'owner_name',p.display_name,
    'title',i.title,'description',i.description,'category_slug',i.category_slug,'condition',i.condition,
    'city',i.city,'preferences',i.preferences,'revision',i.revision,
    'photos',coalesce((select jsonb_agg(f.storage_path order by f.position) from public.item_photos f where f.item_id=i.id),'[]'::jsonb))
  from public.items i join public.profiles p on p.id=i.owner_id where i.id=target;
$$;
create function swapcycle_private.create_offer(p_offered_item_id uuid,p_requested_item_id uuid,p_note text,p_request_key uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=swapcycle_private.require_member(); offered public.items; requested public.items;
  previous swapcycle_private.idempotency_requests; new_id uuid; data jsonb;
begin
  if p_request_key is null then raise exception using errcode='P0001',message='REQUEST_KEY_REQUIRED'; end if;
  select * into offered from public.items where id=p_offered_item_id;
  select * into requested from public.items where id=p_requested_item_id;
  if offered.owner_id is distinct from actor or requested.id is null then raise exception using errcode='P0001',message='NOT_OWNER'; end if;
  perform swapcycle_private.lock_members(array[actor,requested.owner_id]);
  data:=jsonb_build_object('offered',p_offered_item_id,'requested',p_requested_item_id,'note',coalesce(p_note,''));
  select * into previous from swapcycle_private.idempotency_requests where actor_id=actor and request_key=p_request_key and operation='create_offer';
  if found then
    if previous.payload is distinct from data then raise exception using errcode='P0001',message='IDEMPOTENCY_MISMATCH'; end if;
    return previous.result_id;
  end if;
  perform 1 from public.items where id in (p_offered_item_id,p_requested_item_id) order by id for update;
  select * into offered from public.items where id=p_offered_item_id;
  select * into requested from public.items where id=p_requested_item_id;
  perform swapcycle_private.check_swap_items(actor,offered,requested);
  if (select count(*) from public.swap_offers where requester_id=actor and created_at>now()-interval '1 hour')>=20 then
    raise exception using errcode='P0001',message='RATE_LIMITED'; end if;
  perform 1 from public.swap_offers where status='pending' and
    ((offered_item_id=p_offered_item_id and requested_item_id=p_requested_item_id) or
    (offered_item_id=p_requested_item_id and requested_item_id=p_offered_item_id)) order by id for update;
  with expired as (
    update public.swap_offers set status='expired',updated_at=now() where status='pending' and expires_at<=now()
      and ((offered_item_id=p_offered_item_id and requested_item_id=p_requested_item_id) or
      (offered_item_id=p_requested_item_id and requested_item_id=p_offered_item_id)) returning id
  ) insert into public.offer_events(offer_id,event_type) select id,'expired' from expired;
  if exists(select 1 from public.swap_offers where status='pending' and
    ((offered_item_id=p_offered_item_id and requested_item_id=p_requested_item_id) or
    (offered_item_id=p_requested_item_id and requested_item_id=p_offered_item_id))) then
    raise exception using errcode='P0001',message='DUPLICATE_OFFER'; end if;
  insert into public.swap_offers(requester_id,recipient_id,offered_item_id,requested_item_id,offered_revision,requested_revision,note)
    values(actor,requested.owner_id,p_offered_item_id,p_requested_item_id,offered.revision,requested.revision,coalesce(p_note,'')) returning id into new_id;
  insert into public.offer_events(offer_id,actor_id,event_type) values(new_id,actor,'created');
  insert into swapcycle_private.idempotency_requests(actor_id,request_key,operation,payload,result_id)
    values(actor,p_request_key,'create_offer',data,new_id);
  return new_id;
end $$;
create function public.create_offer(p_offered_item_id uuid,p_requested_item_id uuid,p_note text,p_request_key uuid)
returns uuid language sql security invoker set search_path='' as $$
  select swapcycle_private.create_offer(p_offered_item_id,p_requested_item_id,p_note,p_request_key);
$$;

create function swapcycle_private.act_on_offer(p_offer_id uuid,p_action text,p_request_key uuid,p_reason text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=swapcycle_private.require_member(); offer public.swap_offers; offered public.items; requested public.items;
  previous swapcycle_private.idempotency_requests; data jsonb; operation_name text; next_status text; meetup public.meetup_proposals;
  did_change boolean:=true; other_id uuid;
begin
  if p_request_key is null then raise exception using errcode='P0001',message='REQUEST_KEY_REQUIRED'; end if;
  if p_action is null or p_action not in ('accept','decline','withdraw','confirm_receipt','request_cancellation','approve_cancellation','reject_cancellation','dispute') then
    raise exception using errcode='P0001',message='INVALID_ACTION'; end if;
  select * into offer from public.swap_offers where id=p_offer_id;
  if not found or actor not in(offer.requester_id,offer.recipient_id) then raise exception using errcode='P0001',message='NOT_PARTICIPANT'; end if;
  perform swapcycle_private.lock_members(array[offer.requester_id,offer.recipient_id]);
  operation_name:='offer_'||p_action;
  data:=jsonb_build_object('offer',p_offer_id,'reason',coalesce(p_reason,''));
  select * into previous from swapcycle_private.idempotency_requests where actor_id=actor and request_key=p_request_key and operation=operation_name;
  if found then
    if previous.payload is distinct from data then raise exception using errcode='P0001',message='IDEMPOTENCY_MISMATCH'; end if;
    return previous.result_id;
  end if;
  perform 1 from public.items where id in(offer.offered_item_id,offer.requested_item_id) order by id for update;
  perform 1 from public.swap_offers where id=p_offer_id or (status='pending' and
    (offered_item_id in(offer.offered_item_id,offer.requested_item_id) or requested_item_id in(offer.offered_item_id,offer.requested_item_id))) order by id for update;
  select * into offer from public.swap_offers where id=p_offer_id;
  next_status:=offer.status;
  if offer.status='pending' then
    if offer.expires_at<=now() then raise exception using errcode='P0001',message='EXPIRED'; end if;
    if p_action='accept' and actor=offer.recipient_id then
      select * into offered from public.items where id=offer.offered_item_id;
      select * into requested from public.items where id=offer.requested_item_id;
      perform swapcycle_private.check_swap_items(offer.requester_id,offered,requested);
      if offered.revision<>offer.offered_revision or requested.revision<>offer.requested_revision then
        raise exception using errcode='P0001',message='STALE_OFFER'; end if;
      insert into swapcycle_private.item_reservations(item_id,offer_id)
        values(offered.id,p_offer_id),(requested.id,p_offer_id);
      insert into public.offer_snapshots(offer_id,offered_snapshot,requested_snapshot)
        values(p_offer_id,swapcycle_private.item_snapshot(offered.id),swapcycle_private.item_snapshot(requested.id));
      update public.items set status='reserved',updated_at=now() where id in(offered.id,requested.id);
      update public.swap_offers set accepted_at=now() where id=p_offer_id;
      with conflicts as (
        update public.swap_offers set status='invalidated',updated_at=now() where id<>p_offer_id and status='pending'
          and (offered_item_id in(offered.id,requested.id) or requested_item_id in(offered.id,requested.id)) returning id
      ) insert into public.offer_events(offer_id,actor_id,event_type,metadata)
        select id,actor,'invalidated','{"reason":"item_reserved_elsewhere"}'::jsonb from conflicts;
      next_status:='accepted';
    elsif p_action='decline' and actor=offer.recipient_id then next_status:='declined';
    elsif p_action='withdraw' and actor=offer.requester_id then next_status:='cancelled';
    else raise exception using errcode='P0001',message='INVALID_TRANSITION'; end if;
  elsif p_action='accept' and actor=offer.recipient_id and offer.status in('accepted','awaiting_confirmation') then
    did_change:=false;
  elsif p_action='decline' and actor=offer.recipient_id and offer.status='declined' then
    did_change:=false;
  elsif p_action='withdraw' and actor=offer.requester_id and offer.status='cancelled' and offer.accepted_at is null then
    did_change:=false;
  elsif p_action='confirm_receipt' and offer.status in('accepted','awaiting_confirmation','completed') then
    if (actor=offer.requester_id and offer.requester_confirmed_at is not null) or
      (actor=offer.recipient_id and offer.recipient_confirmed_at is not null) then did_change:=false;
    elsif offer.status='completed' then raise exception using errcode='P0001',message='INVALID_TRANSITION';
    else
      select * into meetup from public.meetup_proposals where offer_id=p_offer_id order by version desc limit 1;
      if meetup.approved_at is null then raise exception using errcode='P0001',message='MEETUP_REQUIRED'; end if;
      if meetup.scheduled_at>now() then raise exception using errcode='P0001',message='TOO_EARLY'; end if;
      if actor=offer.requester_id then
        update public.swap_offers set requester_confirmed_at=now() where id=p_offer_id;
        next_status:=case when offer.recipient_confirmed_at is null then 'awaiting_confirmation' else 'completed' end;
      else
        update public.swap_offers set recipient_confirmed_at=now() where id=p_offer_id;
        next_status:=case when offer.requester_confirmed_at is null then 'awaiting_confirmation' else 'completed' end;
      end if;
    end if;
  elsif p_action='request_cancellation' and offer.status in('accepted','awaiting_confirmation') then
    if char_length(btrim(coalesce(p_reason,''))) not between 5 and 2000 then raise exception using errcode='P0001',message='REASON_REQUIRED'; end if;
    next_status:=case when offer.requester_confirmed_at is not null or offer.recipient_confirmed_at is not null then 'disputed' else 'cancellation_requested' end;
    update public.swap_offers set cancellation_requested_by=actor where id=p_offer_id;
  elsif p_action='request_cancellation' and offer.status='cancellation_requested' and offer.cancellation_requested_by=actor then
    did_change:=false;
  elsif p_action in('approve_cancellation','reject_cancellation') and offer.status='cancellation_requested'
    and actor<>offer.cancellation_requested_by then
    if offer.requester_confirmed_at is not null or offer.recipient_confirmed_at is not null then
      raise exception using errcode='P0001',message='DISPUTE_REQUIRED'; end if;
    next_status:=case when p_action='approve_cancellation' then 'cancelled' else 'accepted' end;
    update public.swap_offers set cancellation_requested_by=null where id=p_offer_id;
  elsif p_action='dispute' and offer.status in('accepted','awaiting_confirmation','cancellation_requested','disputed') then
    if char_length(btrim(coalesce(p_reason,''))) not between 5 and 2000 then raise exception using errcode='P0001',message='REASON_REQUIRED'; end if;
    if offer.status='disputed' then did_change:=false; end if;
    next_status:='disputed';
  else raise exception using errcode='P0001',message='INVALID_TRANSITION'; end if;

  if did_change then
    update public.swap_offers set status=next_status,updated_at=now(),
      completed_at=case when next_status='completed' then now() else completed_at end where id=p_offer_id;
    if next_status in('completed','cancelled') and offer.accepted_at is not null then
      update public.items set status=case when next_status='completed' then 'exchanged' else 'available' end,updated_at=now()
        where id in(select item_id from swapcycle_private.item_reservations where offer_id=p_offer_id);
      delete from swapcycle_private.item_reservations where offer_id=p_offer_id;
    end if;
    insert into public.offer_events(offer_id,actor_id,event_type,metadata)
      values(p_offer_id,actor,p_action,jsonb_build_object('status',next_status));
    if next_status='disputed' then
      insert into public.reports(reporter_id,offer_id,reason,details)
        select actor,p_offer_id,'other',p_reason where not exists(
          select 1 from public.reports where reporter_id=actor and offer_id=p_offer_id and status in('open','reviewing'));
    end if;
  end if;
  insert into swapcycle_private.idempotency_requests(actor_id,request_key,operation,payload,result_id)
    values(actor,p_request_key,operation_name,data,p_offer_id);
  return p_offer_id;
end $$;
create function public.act_on_offer(p_offer_id uuid,p_action text,p_request_key uuid,p_reason text default '')
returns uuid language sql security invoker set search_path='' as $$
  select swapcycle_private.act_on_offer(p_offer_id,p_action,p_request_key,p_reason);
$$;

create function swapcycle_private.propose_meetup(p_offer_id uuid,p_location text,p_scheduled_at timestamptz,p_time_zone text,p_note text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=swapcycle_private.require_member(); offer public.swap_offers; new_id uuid; next_version integer;
begin
  select * into offer from public.swap_offers where id=p_offer_id;
  if not found or actor not in(offer.requester_id,offer.recipient_id) then raise exception using errcode='P0001',message='NOT_PARTICIPANT'; end if;
  perform swapcycle_private.lock_members(array[offer.requester_id,offer.recipient_id]);
  select * into offer from public.swap_offers where id=p_offer_id for update;
  if offer.status<>'accepted' or offer.requester_confirmed_at is not null or offer.recipient_confirmed_at is not null then
    raise exception using errcode='P0001',message='INVALID_TRANSITION'; end if;
  if p_scheduled_at is null or p_scheduled_at<now() or p_scheduled_at>offer.accepted_at+interval '30 days'
    or not exists(select 1 from pg_catalog.pg_timezone_names where name=p_time_zone) then
    raise exception using errcode='P0001',message='INVALID_MEETUP_TIME'; end if;
  select coalesce(max(version),0)+1 into next_version from public.meetup_proposals where offer_id=p_offer_id;
  insert into public.meetup_proposals(offer_id,version,proposed_by,public_location,scheduled_at,time_zone,note)
    values(p_offer_id,next_version,actor,btrim(p_location),p_scheduled_at,p_time_zone,coalesce(p_note,'')) returning id into new_id;
  insert into public.offer_events(offer_id,actor_id,event_type,metadata) values(p_offer_id,actor,'meetup_proposed',jsonb_build_object('version',next_version));
  return new_id;
end $$;
create function public.propose_meetup(p_offer_id uuid,p_location text,p_scheduled_at timestamptz,p_time_zone text,p_note text default '')
returns uuid language sql security invoker set search_path='' as $$
  select swapcycle_private.propose_meetup(p_offer_id,p_location,p_scheduled_at,p_time_zone,p_note);
$$;
create function swapcycle_private.approve_meetup(p_proposal_id uuid,p_expected_version integer)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=swapcycle_private.require_member(); offer public.swap_offers; proposal public.meetup_proposals;
begin
  select * into proposal from public.meetup_proposals where id=p_proposal_id;
  if not found then raise exception using errcode='P0001',message='NOT_FOUND'; end if;
  select * into offer from public.swap_offers where id=proposal.offer_id;
  if actor not in(offer.requester_id,offer.recipient_id) then raise exception using errcode='P0001',message='NOT_PARTICIPANT'; end if;
  perform swapcycle_private.lock_members(array[offer.requester_id,offer.recipient_id]);
  select * into offer from public.swap_offers where id=proposal.offer_id for update;
  select * into proposal from public.meetup_proposals where id=p_proposal_id for update;
  if offer.status<>'accepted' or offer.requester_confirmed_at is not null or offer.recipient_confirmed_at is not null
    or proposal.version is distinct from p_expected_version
    or proposal.version<>(select max(version) from public.meetup_proposals where offer_id=offer.id)
    or proposal.proposed_by=actor then raise exception using errcode='P0001',message='INVALID_MEETUP_APPROVAL'; end if;
  if proposal.approved_by is null then
    update public.meetup_proposals set approved_by=actor,approved_at=now() where id=p_proposal_id;
    insert into public.offer_events(offer_id,actor_id,event_type,metadata) values(offer.id,actor,'meetup_approved',jsonb_build_object('version',proposal.version));
  end if;
  return p_proposal_id;
end $$;
create function public.approve_meetup(p_proposal_id uuid,p_expected_version integer)
returns uuid language sql security invoker set search_path='' as $$
  select swapcycle_private.approve_meetup(p_proposal_id,p_expected_version);
$$;

revoke all on function swapcycle_private.check_swap_items(uuid,public.items,public.items),swapcycle_private.item_snapshot(uuid) from public,anon,authenticated;
revoke all on function public.create_offer(uuid,uuid,text,uuid),public.act_on_offer(uuid,text,uuid,text),
  public.propose_meetup(uuid,text,timestamptz,text,text),public.approve_meetup(uuid,integer) from public,anon,authenticated;
grant execute on function public.create_offer(uuid,uuid,text,uuid),public.act_on_offer(uuid,text,uuid,text),
  public.propose_meetup(uuid,text,timestamptz,text,text),public.approve_meetup(uuid,integer),
  swapcycle_private.create_offer(uuid,uuid,text,uuid),swapcycle_private.act_on_offer(uuid,text,uuid,text),
  swapcycle_private.propose_meetup(uuid,text,timestamptz,text,text),swapcycle_private.approve_meetup(uuid,integer) to authenticated;
