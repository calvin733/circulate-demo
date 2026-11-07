-- Portfolio MVP: additive summaries, optional scheduling, private unlinked media.
-- Existing statuses, rows, snapshots and applied migrations remain valid.
alter table public.swap_offers add column offered_summary jsonb;
alter table public.swap_offers add column requested_summary jsonb;

create function swapcycle_private.item_summary(target uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',i.id,'owner_id',i.owner_id,
    'owner_name',p.display_name,'title',i.title)
  from public.items i join public.profiles p on p.id=i.owner_id where i.id=target;
$$;
revoke all on function swapcycle_private.item_summary(uuid) from public,anon,authenticated;

-- Only previously agreed snapshots or currently public titles may populate legacy summaries.
-- A private archived listing must not become readable through a historical backfill.
update public.swap_offers o set
  offered_summary=coalesce(
    (select jsonb_build_object('id',o.offered_item_id,'owner_id',o.requester_id,
      'owner_name',s.offered_snapshot->>'owner_name','title',s.offered_snapshot->>'title')
      from public.offer_snapshots s where s.offer_id=o.id),
    (select swapcycle_private.item_summary(i.id) from public.items i
      join swapcycle_private.account_settings a on a.user_id=i.owner_id
      where i.id=o.offered_item_id and i.status='available' and i.visibility='visible' and a.status='active'),
    jsonb_build_object('id',o.offered_item_id,'owner_id',o.requester_id,
      'owner_name','Anggota komunitas','title','Barang yang ditawarkan')),
  requested_summary=coalesce(
    (select jsonb_build_object('id',o.requested_item_id,'owner_id',o.recipient_id,
      'owner_name',s.requested_snapshot->>'owner_name','title',s.requested_snapshot->>'title')
      from public.offer_snapshots s where s.offer_id=o.id),
    (select swapcycle_private.item_summary(i.id) from public.items i
      join swapcycle_private.account_settings a on a.user_id=i.owner_id
      where i.id=o.requested_item_id and i.status='available' and i.visibility='visible' and a.status='active'),
    jsonb_build_object('id',o.requested_item_id,'owner_id',o.recipient_id,
      'owner_name','Anggota komunitas','title','Barang tujuan'));

create or replace function swapcycle_private.create_offer(p_offered_item_id uuid,p_requested_item_id uuid,p_note text,p_request_key uuid)
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
  insert into public.swap_offers(requester_id,recipient_id,offered_item_id,requested_item_id,offered_revision,requested_revision,note,offered_summary,requested_summary)
    values(actor,requested.owner_id,p_offered_item_id,p_requested_item_id,offered.revision,requested.revision,coalesce(p_note,''),swapcycle_private.item_summary(offered.id),swapcycle_private.item_summary(requested.id)) returning id into new_id;
  insert into public.offer_events(offer_id,actor_id,event_type) values(new_id,actor,'created');
  insert into swapcycle_private.idempotency_requests(actor_id,request_key,operation,payload,result_id)
    values(actor,p_request_key,'create_offer',data,new_id);
  return new_id;
end $$;

create or replace function swapcycle_private.act_on_offer(p_offer_id uuid,p_action text,p_request_key uuid,p_reason text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=swapcycle_private.require_member(); offer public.swap_offers; offered public.items; requested public.items;
  previous swapcycle_private.idempotency_requests; data jsonb; operation_name text; next_status text;
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
      -- Receipt is a deliberate claim by each participant; scheduling is optional.
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

create or replace function swapcycle_private.attach_item_photo(p_item_id uuid,p_expected_revision integer,p_path text,p_position smallint)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=swapcycle_private.require_member(); current_item public.items; photo_id uuid;
begin
  perform swapcycle_private.lock_members(array[actor]);
  select * into current_item from public.items where id=p_item_id for update;
  if not found or current_item.owner_id<>actor then raise exception using errcode='P0001',message='NOT_OWNER'; end if;
  -- A retry after a lost response returns the original attachment, even if reserved later.
  select id into photo_id from public.item_photos where item_id=p_item_id and storage_path=p_path;
  if found then return photo_id; end if;
  if current_item.status not in ('draft','available','archived') or current_item.visibility<>'visible' then
    raise exception using errcode='P0001',message='ITEM_LOCKED'; end if;
  if current_item.revision is distinct from p_expected_revision then raise exception using errcode='P0001',message='STALE_REVISION'; end if;
  if split_part(p_path,'/',1)<>actor::text or split_part(p_path,'/',2)<>p_item_id::text
    or array_length(string_to_array(p_path,'/'),1)<>3
    or not exists(select 1 from storage.objects where bucket_id='item-photos' and name=p_path) then
    raise exception using errcode='P0001',message='INVALID_PHOTO'; end if;
  insert into public.item_photos(item_id,storage_path,position) values(p_item_id,p_path,p_position) returning id into photo_id;
  update public.items set revision=revision+1,updated_at=now() where id=p_item_id;
  perform swapcycle_private.invalidate_item_pending(p_item_id,'photos_updated');
  return photo_id;
end $$;

alter policy swapcycle_item_photos_read on storage.objects using (
  bucket_id='item-photos' and (
    (storage.foldername(name))[1]=(select auth.uid())::text
    or exists(select 1 from public.item_photos p join public.items i on i.id=p.item_id
      where p.storage_path=objects.name and i.id::text=(storage.foldername(objects.name))[2]
        and i.owner_id::text=(storage.foldername(objects.name))[1]
        and swapcycle_private.item_readable(i.id))
  )
);

-- Private implementations still need authenticated EXECUTE through invoker wrappers.
-- Anonymous catalog helpers keep their separate, explicitly granted read-only access.
revoke execute on function
  swapcycle_private.save_item(uuid,integer,text,text,text,text,text,text),
  swapcycle_private.attach_item_photo(uuid,integer,text,smallint),
  swapcycle_private.detach_item_photo(uuid,integer),
  swapcycle_private.set_listing_state(uuid,integer,text),
  swapcycle_private.update_profile(text,text,text,text),
  swapcycle_private.create_offer(uuid,uuid,text,uuid),
  swapcycle_private.act_on_offer(uuid,text,uuid,text),
  swapcycle_private.propose_meetup(uuid,text,timestamptz,text,text),
  swapcycle_private.approve_meetup(uuid,integer)
from public,anon;
