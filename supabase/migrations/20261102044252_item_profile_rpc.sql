create function swapcycle_private.lock_members(members uuid[]) returns void
language plpgsql security definer set search_path='' as $$
begin
  perform 1 from swapcycle_private.account_settings where user_id=any(members) order by user_id for update;
  perform swapcycle_private.require_member();
end $$;
create function swapcycle_private.invalidate_item_pending(target uuid, reason text) returns void
language plpgsql security definer set search_path='' as $$
begin
  perform 1 from public.swap_offers where status='pending' and target in(offered_item_id,requested_item_id) order by id for update;
  with affected as (
    update public.swap_offers set status='invalidated',updated_at=now()
    where status='pending' and target in(offered_item_id,requested_item_id) returning id
  ) insert into public.offer_events(offer_id,actor_id,event_type,metadata)
    select id,auth.uid(),'invalidated',jsonb_build_object('reason',reason) from affected;
end $$;
create function swapcycle_private.save_item(
  p_id uuid,p_expected_revision integer,p_title text,p_description text,
  p_category_slug text,p_condition text,p_city text,p_preferences text
) returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=swapcycle_private.require_member(); current_item public.items;
begin
  perform swapcycle_private.lock_members(array[actor]);
  if not exists(select 1 from public.categories where slug=p_category_slug and enabled) then
    raise exception using errcode='P0001',message='INVALID_CATEGORY';
  end if;
  select * into current_item from public.items where id=p_id for update;
  if found then
    if current_item.owner_id<>actor then raise exception using errcode='P0001',message='NOT_OWNER'; end if;
    if current_item.status not in ('draft','available','archived') then raise exception using errcode='P0001',message='ITEM_LOCKED'; end if;
    if current_item.visibility<>'visible' then raise exception using errcode='P0001',message='ITEM_HIDDEN'; end if;
    if current_item.revision is distinct from p_expected_revision then raise exception using errcode='P0001',message='STALE_REVISION'; end if;
    update public.items set title=btrim(p_title),description=btrim(p_description),category_slug=p_category_slug,
      condition=p_condition,city=btrim(p_city),preferences=btrim(p_preferences),revision=revision+1,updated_at=now()
      where id=p_id;
    perform swapcycle_private.invalidate_item_pending(p_id,'item_updated');
  else
    if p_id is null or p_expected_revision is distinct from 0 then raise exception using errcode='P0001',message='INVALID_DRAFT'; end if;
    insert into public.items(id,owner_id,title,description,category_slug,condition,city,preferences)
      values(p_id,actor,btrim(p_title),btrim(p_description),p_category_slug,p_condition,btrim(p_city),btrim(p_preferences));
  end if;
  return p_id;
end $$;
create function public.save_item(p_id uuid,p_expected_revision integer,p_title text,p_description text,p_category_slug text,p_condition text,p_city text,p_preferences text)
returns uuid language sql security invoker set search_path='' as $$
  select swapcycle_private.save_item(p_id,p_expected_revision,p_title,p_description,p_category_slug,p_condition,p_city,p_preferences);
$$;

create function swapcycle_private.attach_item_photo(p_item_id uuid,p_expected_revision integer,p_path text,p_position smallint)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=swapcycle_private.require_member(); current_item public.items; photo_id uuid;
begin
  perform swapcycle_private.lock_members(array[actor]);
  select * into current_item from public.items where id=p_item_id for update;
  if not found or current_item.owner_id<>actor then raise exception using errcode='P0001',message='NOT_OWNER'; end if;
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
create function public.attach_item_photo(p_item_id uuid,p_expected_revision integer,p_path text,p_position smallint)
returns uuid language sql security invoker set search_path='' as $$
  select swapcycle_private.attach_item_photo(p_item_id,p_expected_revision,p_path,p_position);
$$;

create function swapcycle_private.detach_item_photo(p_photo_id uuid,p_expected_revision integer)
returns text language plpgsql security definer set search_path='' as $$
declare actor uuid:=swapcycle_private.require_member(); photo public.item_photos; current_item public.items;
begin
  perform swapcycle_private.lock_members(array[actor]);
  select * into photo from public.item_photos where id=p_photo_id;
  if not found then raise exception using errcode='P0001',message='NOT_FOUND'; end if;
  select * into current_item from public.items where id=photo.item_id for update;
  if current_item.owner_id<>actor then raise exception using errcode='P0001',message='NOT_OWNER'; end if;
  if current_item.status not in ('draft','available','archived') or current_item.visibility<>'visible' then
    raise exception using errcode='P0001',message='ITEM_LOCKED'; end if;
  if current_item.revision is distinct from p_expected_revision then raise exception using errcode='P0001',message='STALE_REVISION'; end if;
  if current_item.status='available' and (select count(*) from public.item_photos where item_id=photo.item_id)<=1 then
    raise exception using errcode='P0001',message='PHOTO_REQUIRED'; end if;
  delete from public.item_photos where id=p_photo_id;
  update public.items set revision=revision+1,updated_at=now() where id=photo.item_id;
  perform swapcycle_private.invalidate_item_pending(photo.item_id,'photos_updated');
  return photo.storage_path;
end $$;
create function public.detach_item_photo(p_photo_id uuid,p_expected_revision integer)
returns text language sql security invoker set search_path='' as $$
  select swapcycle_private.detach_item_photo(p_photo_id,p_expected_revision);
$$;

create function swapcycle_private.set_listing_state(p_item_id uuid,p_expected_revision integer,p_action text)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=swapcycle_private.require_member(); current_item public.items;
begin
  perform swapcycle_private.lock_members(array[actor]);
  select * into current_item from public.items where id=p_item_id for update;
  if not found or current_item.owner_id<>actor then raise exception using errcode='P0001',message='NOT_OWNER'; end if;
  if current_item.status in ('reserved','exchanged') then raise exception using errcode='P0001',message='ITEM_LOCKED'; end if;
  if current_item.revision is distinct from p_expected_revision then raise exception using errcode='P0001',message='STALE_REVISION'; end if;
  if p_action='publish' then
    if current_item.visibility<>'visible' then raise exception using errcode='P0001',message='ITEM_HIDDEN'; end if;
    if (select count(*) from public.item_photos where item_id=p_item_id) not between 1 and 5
      or exists(select 1 from public.item_photos p where p.item_id=p_item_id and not exists(
        select 1 from storage.objects s where s.bucket_id='item-photos' and s.name=p.storage_path)) then
      raise exception using errcode='P0001',message='PHOTO_REQUIRED'; end if;
    if not exists(select 1 from public.categories where slug=current_item.category_slug and enabled) then
      raise exception using errcode='P0001',message='INVALID_CATEGORY'; end if;
    update public.items set status='available',revision=revision+1,updated_at=now() where id=p_item_id;
  elsif p_action='archive' then
    update public.items set status='archived',revision=revision+1,updated_at=now() where id=p_item_id;
    perform swapcycle_private.invalidate_item_pending(p_item_id,'item_archived');
  else raise exception using errcode='P0001',message='INVALID_ACTION'; end if;
  return p_item_id;
end $$;
create function public.set_listing_state(p_item_id uuid,p_expected_revision integer,p_action text)
returns uuid language sql security invoker set search_path='' as $$
  select swapcycle_private.set_listing_state(p_item_id,p_expected_revision,p_action);
$$;

create function swapcycle_private.update_profile(p_display_name text,p_city text,p_bio text,p_avatar_path text default null)
returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=swapcycle_private.require_member();
begin
  perform swapcycle_private.lock_members(array[actor]);
  if p_avatar_path is not null and (split_part(p_avatar_path,'/',1)<>actor::text or
    not exists(select 1 from storage.objects where bucket_id='avatars' and name=p_avatar_path)) then
    raise exception using errcode='P0001',message='INVALID_AVATAR'; end if;
  update public.profiles set display_name=btrim(p_display_name),city=btrim(p_city),bio=btrim(p_bio),
    avatar_path=p_avatar_path,updated_at=now() where id=actor;
end $$;
create function public.update_profile(p_display_name text,p_city text,p_bio text,p_avatar_path text default null)
returns void language sql security invoker set search_path='' as $$
  select swapcycle_private.update_profile(p_display_name,p_city,p_bio,p_avatar_path);
$$;

-- Explicit deny policies document the intended closed private tables.
create policy no_client_access on swapcycle_private.account_settings for all to anon,authenticated using(false) with check(false);
create policy no_client_access on swapcycle_private.item_reservations for all to anon,authenticated using(false) with check(false);
create policy no_client_access on swapcycle_private.idempotency_requests for all to anon,authenticated using(false) with check(false);
create policy no_client_access on swapcycle_private.moderator_roles for all to anon,authenticated using(false) with check(false);
create policy no_client_access on swapcycle_private.moderation_actions for all to anon,authenticated using(false) with check(false);
revoke all on function swapcycle_private.lock_members(uuid[]),swapcycle_private.invalidate_item_pending(uuid,text) from public,anon,authenticated;
revoke all on function public.save_item(uuid,integer,text,text,text,text,text,text),public.attach_item_photo(uuid,integer,text,smallint),
  public.detach_item_photo(uuid,integer),public.set_listing_state(uuid,integer,text),public.update_profile(text,text,text,text) from public,anon,authenticated;
grant execute on function public.save_item(uuid,integer,text,text,text,text,text,text),public.attach_item_photo(uuid,integer,text,smallint),
  public.detach_item_photo(uuid,integer),public.set_listing_state(uuid,integer,text),public.update_profile(text,text,text,text),
  swapcycle_private.save_item(uuid,integer,text,text,text,text,text,text),swapcycle_private.attach_item_photo(uuid,integer,text,smallint),
  swapcycle_private.detach_item_photo(uuid,integer),swapcycle_private.set_listing_state(uuid,integer,text),swapcycle_private.update_profile(text,text,text,text)
  to authenticated;
