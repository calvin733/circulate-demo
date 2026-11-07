-- SwapCycle development foundation. No fixture users or service credentials.
create schema if not exists swapcycle_private;
revoke all on schema swapcycle_private from public, anon, authenticated;
grant usage on schema swapcycle_private to anon, authenticated;
alter default privileges in schema swapcycle_private revoke execute on functions from public, anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  display_name text not null check (char_length(btrim(display_name)) between 2 and 50),
  city text not null default 'Belum diisi' check (char_length(btrim(city)) between 2 and 80),
  bio text not null default '' check (char_length(bio) <= 300),
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table swapcycle_private.account_settings (
  user_id uuid primary key references public.profiles(id) on delete restrict,
  status text not null default 'active' check (status in ('active','suspended','deletion_pending')),
  terms_version text,
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);
create table public.categories (
  slug text primary key,
  name text not null,
  sort_order smallint not null,
  enabled boolean not null default true
);
insert into public.categories(slug,name,sort_order) values
('books','Buku',1),('electronics','Elektronik',2),('home','Rumah',3),
('hobbies','Hobi',4),('fashion','Fashion',5),('sports','Olahraga',6);
create table public.items (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete restrict,
  category_slug text not null references public.categories(slug),
  title text not null check (char_length(btrim(title)) between 5 and 80),
  description text not null check (char_length(btrim(description)) between 20 and 2000),
  condition text not null check (condition in ('like_new','good','fair')),
  preferences text not null default '' check (char_length(preferences) <= 500),
  city text not null check (char_length(btrim(city)) between 2 and 80),
  status text not null default 'draft' check (status in ('draft','available','reserved','exchanged','archived')),
  visibility text not null default 'visible' check (visibility in ('visible','hidden')),
  revision integer not null default 1 check (revision > 0),
  search_vector tsvector generated always as (to_tsvector('simple',title || ' ' || description)) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index items_owner_status_idx on public.items(owner_id,status);
create index items_category_idx on public.items(category_slug);
create index items_explore_idx on public.items(created_at desc,id) where status='available' and visibility='visible';
create index items_search_idx on public.items using gin(search_vector);
create table public.item_photos (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete restrict,
  storage_path text not null unique,
  position smallint not null check (position between 0 and 4),
  created_at timestamptz not null default now(),
  unique(item_id,position)
);
create table public.swap_offers (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete restrict,
  recipient_id uuid not null references public.profiles(id) on delete restrict,
  offered_item_id uuid not null references public.items(id) on delete restrict,
  requested_item_id uuid not null references public.items(id) on delete restrict,
  offered_revision integer not null,
  requested_revision integer not null,
  status text not null default 'pending' check (status in ('pending','accepted','awaiting_confirmation','cancellation_requested','disputed','completed','declined','cancelled','expired','invalidated')),
  note text not null default '' check (char_length(note) <= 500),
  expires_at timestamptz not null default (now()+interval '7 days'),
  accepted_at timestamptz,
  requester_confirmed_at timestamptz,
  recipient_confirmed_at timestamptz,
  cancellation_requested_by uuid references public.profiles(id),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (requester_id <> recipient_id),
  check (offered_item_id <> requested_item_id),
  check (cancellation_requested_by is null or cancellation_requested_by in (requester_id,recipient_id)),
  check (status <> 'completed' or completed_at is not null),
  check (status not in ('accepted','awaiting_confirmation','cancellation_requested','disputed','completed') or accepted_at is not null)
);
create unique index offers_pending_pair_idx on public.swap_offers(least(offered_item_id,requested_item_id),greatest(offered_item_id,requested_item_id)) where status='pending';
create index offers_incoming_idx on public.swap_offers(recipient_id,status,created_at desc);
create index offers_outgoing_idx on public.swap_offers(requester_id,status,created_at desc);
create index offers_offered_idx on public.swap_offers(offered_item_id);
create index offers_requested_idx on public.swap_offers(requested_item_id);
create index offers_cancellation_actor_idx on public.swap_offers(cancellation_requested_by);
create table swapcycle_private.item_reservations (
  item_id uuid primary key references public.items(id) on delete restrict,
  offer_id uuid not null references public.swap_offers(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index reservations_offer_idx on swapcycle_private.item_reservations(offer_id);
create table public.offer_snapshots (
  offer_id uuid primary key references public.swap_offers(id) on delete restrict,
  offered_snapshot jsonb not null,
  requested_snapshot jsonb not null,
  captured_at timestamptz not null default now()
);
create table public.offer_events (
  id bigint generated always as identity primary key,
  offer_id uuid not null references public.swap_offers(id) on delete restrict,
  actor_id uuid references public.profiles(id) on delete restrict,
  event_type text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index events_offer_idx on public.offer_events(offer_id,id);
create index events_actor_idx on public.offer_events(actor_id);
create table public.meetup_proposals (
  id uuid primary key default gen_random_uuid(),
  offer_id uuid not null references public.swap_offers(id) on delete restrict,
  version integer not null check (version>0),
  proposed_by uuid not null references public.profiles(id),
  public_location text not null check (char_length(btrim(public_location)) between 5 and 200),
  scheduled_at timestamptz not null,
  time_zone text not null default 'Asia/Jakarta',
  note text not null default '' check (char_length(note)<=300),
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  unique(offer_id,version),
  check (approved_by is null or approved_by <> proposed_by),
  check ((approved_by is null) = (approved_at is null))
);
create index meetup_proposer_idx on public.meetup_proposals(proposed_by);
create index meetup_approver_idx on public.meetup_proposals(approved_by);
create table public.user_blocks (
  blocker_id uuid not null references public.profiles(id),
  blocked_id uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  primary key(blocker_id,blocked_id),
  check(blocker_id<>blocked_id)
);
create index blocks_blocked_idx on public.user_blocks(blocked_id);
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id),
  item_id uuid references public.items(id),
  reported_user_id uuid references public.profiles(id),
  offer_id uuid references public.swap_offers(id),
  reason text not null check (reason in ('prohibited','misleading','harassment','no_show','condition_mismatch','other')),
  details text not null default '' check(char_length(details)<=2000),
  status text not null default 'open' check(status in ('open','reviewing','resolved','dismissed')),
  created_at timestamptz not null default now(),
  check(num_nonnulls(item_id,reported_user_id,offer_id)=1)
);
create index reports_reporter_idx on public.reports(reporter_id,created_at desc);
create index reports_queue_idx on public.reports(status,created_at);
create index reports_item_idx on public.reports(item_id);
create index reports_user_idx on public.reports(reported_user_id);
create index reports_offer_idx on public.reports(offer_id);
create table swapcycle_private.moderator_roles (
  user_id uuid primary key references public.profiles(id)
);
create table swapcycle_private.moderation_actions (
  id bigint generated always as identity primary key,
  report_id uuid references public.reports(id),
  moderator_id uuid not null references public.profiles(id),
  action text not null,
  target_id uuid not null,
  reason text not null check(char_length(btrim(reason)) between 5 and 2000),
  created_at timestamptz not null default now()
);
create index moderation_report_idx on swapcycle_private.moderation_actions(report_id);
create index moderation_actor_idx on swapcycle_private.moderation_actions(moderator_id);
create table public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  status text not null default 'requested' check(status in ('requested','reviewing','completed','withdrawn')),
  requested_at timestamptz not null default now(),
  processed_at timestamptz
);
create unique index deletion_active_idx on public.account_deletion_requests(user_id) where status in ('requested','reviewing');
create table swapcycle_private.idempotency_requests (
  actor_id uuid not null references public.profiles(id),
  request_key uuid not null,
  operation text not null,
  payload jsonb not null,
  result_id uuid not null,
  created_at timestamptz not null default now(),
  primary key(actor_id,request_key,operation)
);

-- Sensitive implementations live outside the exposed API schema.
create function swapcycle_private.require_member() returns uuid
language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid();
begin
  if actor is null or not exists (
    select 1 from auth.users u join swapcycle_private.account_settings a on a.user_id=u.id
    where u.id=actor and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false)
    and (u.banned_until is null or u.banned_until<now()) and a.status='active'
  ) then raise exception using errcode='P0001',message='ACCOUNT_NOT_READY'; end if;
  return actor;
end $$;
create function swapcycle_private.bootstrap_profile() returns trigger
language plpgsql security definer set search_path='' as $$
declare label text := btrim(coalesce(new.raw_user_meta_data->>'display_name','Anggota SwapCycle'));
begin
  if char_length(label) not between 2 and 50 then label:='Anggota SwapCycle'; end if;
  insert into public.profiles(id,display_name) values(new.id,label);
  insert into swapcycle_private.account_settings(user_id) values(new.id);
  return new;
end $$;
create trigger on_swapcycle_user_created after insert on auth.users
for each row execute function swapcycle_private.bootstrap_profile();

create function swapcycle_private.item_readable(target uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.items i where i.id=target and (
    i.owner_id=(select auth.uid()) or
    (i.status='available' and i.visibility='visible' and exists(select 1 from swapcycle_private.account_settings a where a.user_id=i.owner_id and a.status='active')) or
    exists(select 1 from public.swap_offers o where target in (o.offered_item_id,o.requested_item_id)
      and o.status in ('accepted','awaiting_confirmation','cancellation_requested','disputed')
      and (select auth.uid()) in (o.requester_id,o.recipient_id))
  ));
$$;
create function swapcycle_private.snapshot_photo_readable(path text) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.offer_snapshots s join public.swap_offers o on o.id=s.offer_id
    where (select auth.uid()) in (o.requester_id,o.recipient_id)
      and ((s.offered_snapshot->'photos') ? path or (s.requested_snapshot->'photos') ? path));
$$;

-- Enable RLS on every application table, including private defense in depth.
alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.items enable row level security;
alter table public.item_photos enable row level security;
alter table public.swap_offers enable row level security;
alter table public.offer_snapshots enable row level security;
alter table public.offer_events enable row level security;
alter table public.meetup_proposals enable row level security;
alter table public.user_blocks enable row level security;
alter table public.reports enable row level security;
alter table public.account_deletion_requests enable row level security;
alter table swapcycle_private.account_settings enable row level security;
alter table swapcycle_private.item_reservations enable row level security;
alter table swapcycle_private.moderator_roles enable row level security;
alter table swapcycle_private.moderation_actions enable row level security;
alter table swapcycle_private.idempotency_requests enable row level security;
revoke all on all tables in schema swapcycle_private from public,anon,authenticated;
revoke all on public.profiles,public.categories,public.items,public.item_photos,public.swap_offers,public.offer_snapshots,public.offer_events,public.meetup_proposals,public.user_blocks,public.reports,public.account_deletion_requests from anon,authenticated;
grant select on public.profiles,public.categories,public.items,public.item_photos to anon,authenticated;
grant select on public.swap_offers,public.offer_snapshots,public.offer_events,public.meetup_proposals,public.user_blocks,public.reports,public.account_deletion_requests to authenticated;
create policy profiles_public_read on public.profiles for select to anon,authenticated using(true);
create policy categories_public_read on public.categories for select to anon,authenticated using(enabled);
create policy items_read on public.items for select to anon,authenticated using(swapcycle_private.item_readable(id));
create policy photos_read on public.item_photos for select to anon,authenticated using(swapcycle_private.item_readable(item_id));
create policy offers_participant_read on public.swap_offers for select to authenticated using((select auth.uid()) in (requester_id,recipient_id));
create policy snapshots_participant_read on public.offer_snapshots for select to authenticated using(exists(select 1 from public.swap_offers o where o.id=offer_id));
create policy events_participant_read on public.offer_events for select to authenticated using(exists(select 1 from public.swap_offers o where o.id=offer_id));
create policy meetups_participant_read on public.meetup_proposals for select to authenticated using(exists(select 1 from public.swap_offers o where o.id=offer_id));
create policy blocks_own_read on public.user_blocks for select to authenticated using(blocker_id=(select auth.uid()));
create policy reports_own_read on public.reports for select to authenticated using(reporter_id=(select auth.uid()));
create policy deletion_own_read on public.account_deletion_requests for select to authenticated using(user_id=(select auth.uid()));
revoke all on function swapcycle_private.require_member(),swapcycle_private.bootstrap_profile(),swapcycle_private.item_readable(uuid),swapcycle_private.snapshot_photo_readable(text) from public,anon,authenticated;
grant execute on function swapcycle_private.item_readable(uuid) to anon,authenticated;
grant execute on function swapcycle_private.require_member(),swapcycle_private.snapshot_photo_readable(text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
('item-photos','item-photos',false,5242880,array['image/jpeg','image/png','image/webp']),
('avatars','avatars',false,5242880,array['image/jpeg','image/png','image/webp']);
create policy swapcycle_item_photos_insert on storage.objects for insert to authenticated with check(
  bucket_id='item-photos' and (storage.foldername(name))[1]=(select swapcycle_private.require_member())::text
  and exists(select 1 from public.items i where i.id::text=(storage.foldername(name))[2]
    and i.owner_id=(select auth.uid()) and i.status in ('draft','available','archived'))
);
create policy swapcycle_item_photos_read on storage.objects for select to anon,authenticated using(
  bucket_id='item-photos' and exists(select 1 from public.items i where i.id::text=(storage.foldername(name))[2]
    and i.owner_id::text=(storage.foldername(name))[1] and swapcycle_private.item_readable(i.id))
);
create policy swapcycle_snapshot_photos_read on storage.objects for select to authenticated using(
  bucket_id='item-photos' and swapcycle_private.snapshot_photo_readable(name)
);
-- Immutable object paths: no UPDATE/upsert grant is introduced.
create policy swapcycle_item_photos_delete on storage.objects for delete to authenticated using(
  bucket_id='item-photos' and (storage.foldername(name))[1]=(select auth.uid())::text
  and exists(select 1 from public.items i where i.id::text=(storage.foldername(name))[2]
    and i.owner_id=(select auth.uid()) and i.status in ('draft','available','archived')
    and not exists(select 1 from public.item_photos p where p.storage_path=name)
    and not swapcycle_private.snapshot_photo_readable(name))
);
create policy swapcycle_avatars_insert on storage.objects for insert to authenticated with check(
  bucket_id='avatars' and (storage.foldername(name))[1]=(select swapcycle_private.require_member())::text
);
create policy swapcycle_avatars_read on storage.objects for select to anon,authenticated using(
  bucket_id='avatars' and ((storage.foldername(name))[1]=(select auth.uid())::text
  or exists(select 1 from public.profiles p where p.avatar_path=name))
);
create policy swapcycle_avatars_delete on storage.objects for delete to authenticated using(
  bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text
  and not exists(select 1 from public.profiles p where p.avatar_path=name)
);
