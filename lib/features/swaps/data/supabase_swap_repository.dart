import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/cloud_support.dart';
import '../../../core/errors/app_exception.dart';
import '../../items/data/supabase_item_repository.dart';
import '../../items/domain/item.dart';
import '../domain/swap_offer.dart';
import '../domain/swap_repository.dart';

class SupabaseSwapRepository implements SwapRepository {
  SupabaseSwapRepository(this.client);
  final SupabaseClient client;
  final Map<String, String> _actionKeys = {};
  static const selection =
      '*,offer_events(*),meetup_proposals(*),offer_snapshots(*)';

  SwapStatus _status(String value) => switch (value) {
    'awaiting_confirmation' => SwapStatus.awaitingConfirmation,
    'cancellation_requested' => SwapStatus.cancellationRequested,
    _ => SwapStatus.values.byName(value),
  };

  Future<List<SwapOffer>> _decode(List<Map<String, dynamic>> rows) async {
    final paths = <String>[];
    for (final row in rows) {
      final snapshot = row['offer_snapshots'] as Map<String, dynamic>?;
      if (snapshot != null) {
        paths.addAll(
          ItemMapper.paths(
            snapshot['offered_snapshot'] as Map<String, dynamic>,
          ),
        );
        paths.addAll(
          ItemMapper.paths(
            snapshot['requested_snapshot'] as Map<String, dynamic>,
          ),
        );
      }
    }
    final urls = await signItemPhotos(client, paths);
    return rows.map((row) {
      final status = _status(row['status'] as String);
      final events =
          (row['offer_events'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>()
              .toList()
            ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
      final proposals =
          (row['meetup_proposals'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>()
              .toList()
            ..sort(
              (a, b) => (b['version'] as int).compareTo(a['version'] as int),
            );
      final snapshot = row['offer_snapshots'] as Map<String, dynamic>?;
      final proposal = proposals.firstOrNull;
      DateTime? date(Object? value) =>
          value == null ? null : DateTime.parse(value as String);
      SwapItemSummary? summary(Object? value) {
        if (value is! Map<String, dynamic>) return null;
        return SwapItemSummary(
          id: value['id'] as String,
          ownerId: value['owner_id'] as String,
          ownerName: value['owner_name'] as String? ?? 'Anggota komunitas',
          title: value['title'] as String? ?? 'Barang tidak tersedia',
        );
      }

      return SwapOffer(
        id: row['id'] as String,
        requesterId: row['requester_id'] as String,
        recipientId: row['recipient_id'] as String,
        offeredItemId: row['offered_item_id'] as String,
        requestedItemId: row['requested_item_id'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
        expiresAt: DateTime.parse(row['expires_at'] as String),
        status: status,
        note: row['note'] as String,
        requesterConfirmedAt: date(row['requester_confirmed_at']),
        recipientConfirmedAt: date(row['recipient_confirmed_at']),
        cancellationRequestedBy: row['cancellation_requested_by'] as String?,
        offeredSummary: summary(row['offered_summary']),
        requestedSummary: summary(row['requested_summary']),
        events: List.unmodifiable(
          events.map(
            (event) => SwapEvent(
              _eventLabel(event['event_type'] as String),
              DateTime.parse(event['created_at'] as String),
            ),
          ),
        ),
        meetup: proposal == null
            ? null
            : Meetup(
                id: proposal['id'] as String,
                location: proposal['public_location'] as String,
                scheduledAt: DateTime.parse(proposal['scheduled_at'] as String),
                proposedBy: proposal['proposed_by'] as String,
                approvedBy: proposal['approved_by'] as String?,
                version: proposal['version'] as int,
              ),
        offeredSnapshot: snapshot == null
            ? null
            : ItemMapper.read(
                snapshot['offered_snapshot'] as Map<String, dynamic>,
                urls,
                status: status == SwapStatus.completed
                    ? ItemStatus.exchanged
                    : ItemStatus.reserved,
              ),
        requestedSnapshot: snapshot == null
            ? null
            : ItemMapper.read(
                snapshot['requested_snapshot'] as Map<String, dynamic>,
                urls,
                status: status == SwapStatus.completed
                    ? ItemStatus.exchanged
                    : ItemStatus.reserved,
              ),
      );
    }).toList();
  }

  String _eventLabel(String event) => switch (event) {
    'created' => 'Penawaran diajukan',
    'accept' => 'Penawaran diterima · kedua barang direservasi',
    'decline' => 'Penawaran ditolak',
    'withdraw' => 'Penawaran ditarik',
    'confirm_receipt' => 'Konfirmasi penerimaan dicatat',
    'meetup_proposed' => 'Pertemuan diusulkan',
    'meetup_approved' => 'Pertemuan disepakati',
    'request_cancellation' => 'Pembatalan diminta',
    'approve_cancellation' => 'Pembatalan disetujui',
    'reject_cancellation' => 'Pertukaran dilanjutkan',
    'dispute' => 'Sengketa dibuka',
    'invalidated' => 'Penawaran tidak lagi berlaku',
    'expired' => 'Penawaran kedaluwarsa',
    _ => 'Status diperbarui',
  };
  @override
  Future<List<SwapOffer>> listFor(String actorId) => cloudCall(() async {
    requireCurrentUser(client, actorId);
    return _decode(
      await client
          .from('swap_offers')
          .select()
          .or('requester_id.eq.$actorId,recipient_id.eq.$actorId')
          .order('created_at', ascending: false)
          .limit(100),
    );
  });
  @override
  Future<SwapOffer> findOffer(String id, String actorId) => cloudCall(() async {
    requireCurrentUser(client, actorId);
    final row = await client
        .from('swap_offers')
        .select(selection)
        .eq('id', id)
        .maybeSingle();
    if (row == null) {
      throw const AppException('NOT_FOUND', 'Pertukaran tidak tersedia.');
    }
    return (await _decode([row])).single;
  });
  @override
  Future<String> create({
    required String actorId,
    required String offeredItemId,
    required String requestedItemId,
    required String requestKey,
  }) => cloudCall(() async {
    requireCurrentUser(client, actorId);
    return await client.rpc<String>(
      'create_offer',
      params: {
        'p_offered_item_id': offeredItemId,
        'p_requested_item_id': requestedItemId,
        'p_note': '',
        'p_request_key': requestKey,
      },
    );
  });
  @override
  Future<void> act(String id, SwapAction action, String actorId) =>
      cloudCall(() async {
        requireCurrentUser(client, actorId);
        final code = switch (action) {
          SwapAction.confirmReceipt => 'confirm_receipt',
          SwapAction.requestCancellation => 'request_cancellation',
          SwapAction.approveCancellation => 'approve_cancellation',
          SwapAction.rejectCancellation => 'reject_cancellation',
          _ => action.name,
        };
        final intent = '$id/$code';
        final requestKey = _actionKeys.putIfAbsent(
          intent,
          () => const Uuid().v4(),
        );
        await client.rpc<String>(
          'act_on_offer',
          params: {
            'p_offer_id': id,
            'p_action': code,
            'p_request_key': requestKey,
            'p_reason': action == SwapAction.dispute
                ? 'Peserta melaporkan masalah pertukaran.'
                : action == SwapAction.requestCancellation
                ? 'Peserta meminta pembatalan pertukaran.'
                : '',
          },
        );
        _actionKeys.remove(intent);
      });

  @override
  Future<void> proposeMeetup(
    String offerId,
    String actorId, {
    required String location,
    required DateTime scheduledAt,
  }) => cloudCall(() async {
    requireCurrentUser(client, actorId);
    await client.rpc<String>(
      'propose_meetup',
      params: {
        'p_offer_id': offerId, 'p_location': location.trim(),
        'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
        // An absolute UTC instant avoids a wrong inferred IANA device zone.
        'p_time_zone': 'UTC', 'p_note': '',
      },
    );
  });

  @override
  Future<void> approveMeetup(String offerId, String actorId, Meetup proposal) =>
      cloudCall(() async {
        requireCurrentUser(client, actorId);
        await client.rpc<String>(
          'approve_meetup',
          params: {
            'p_proposal_id': proposal.id,
            'p_expected_version': proposal.version,
          },
        );
      });
}
