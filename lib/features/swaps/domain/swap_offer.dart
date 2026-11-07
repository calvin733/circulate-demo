import '../../items/domain/item.dart';

enum SwapStatus {
  pending('Menunggu jawaban'),
  accepted('Diterima'),
  awaitingConfirmation('Menunggu konfirmasi'),
  cancellationRequested('Pembatalan diminta'),
  disputed('Perlu penyelesaian'),
  completed('Selesai'),
  declined('Ditolak'),
  cancelled('Dibatalkan'),
  expired('Kedaluwarsa'),
  invalidated('Barang tidak tersedia');

  const SwapStatus(this.label);
  final String label;
  bool get isActive => switch (this) {
    accepted ||
    awaitingConfirmation ||
    cancellationRequested ||
    disputed => true,
    _ => false,
  };
  bool get isTerminal => !isActive && this != pending;
}

enum SwapAction {
  accept,
  decline,
  withdraw,
  confirmReceipt,
  requestCancellation,
  approveCancellation,
  rejectCancellation,
  dispute,
}

class SwapEvent {
  const SwapEvent(this.label, this.at);
  final String label;
  final DateTime at;
}

class Meetup {
  const Meetup({
    this.id = '',
    required this.location,
    required this.scheduledAt,
    required this.proposedBy,
    this.approvedBy,
    this.version = 1,
  });
  final String location;
  final String id;
  final DateTime scheduledAt;
  final String proposedBy;
  final String? approvedBy;
  final int version;
  bool get isApproved => approvedBy != null && approvedBy != proposedBy;
}

/// Minimal participant-only history, independent from access to a live listing.
class SwapItemSummary {
  const SwapItemSummary({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.title,
  });
  factory SwapItemSummary.fromItem(Item item) => SwapItemSummary(
    id: item.id,
    ownerId: item.ownerId,
    ownerName: item.ownerName,
    title: item.title,
  );
  final String id;
  final String ownerId;
  final String ownerName;
  final String title;
}

class SwapOffer {
  const SwapOffer({
    required this.id,
    required this.requesterId,
    required this.recipientId,
    required this.offeredItemId,
    required this.requestedItemId,
    required this.createdAt,
    required this.expiresAt,
    required this.events,
    this.status = SwapStatus.pending,
    this.note = '',
    this.requesterConfirmedAt,
    this.recipientConfirmedAt,
    this.cancellationRequestedBy,
    this.meetup,
    this.offeredSnapshot,
    this.requestedSnapshot,
    this.offeredSummary,
    this.requestedSummary,
  });
  final String id;
  final String requesterId;
  final String recipientId;
  final String offeredItemId;
  final String requestedItemId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<SwapEvent> events;
  final SwapStatus status;
  final String note;
  final DateTime? requesterConfirmedAt;
  final DateTime? recipientConfirmedAt;
  final String? cancellationRequestedBy;
  final Meetup? meetup;
  final Item? offeredSnapshot;
  final Item? requestedSnapshot;
  final SwapItemSummary? offeredSummary;
  final SwapItemSummary? requestedSummary;

  String get statusLabel => status.label;
  SwapStatus statusAt(DateTime now) =>
      status == SwapStatus.pending && !now.isBefore(expiresAt)
      ? SwapStatus.expired
      : status;
  SwapOffer forDisplay(DateTime now) =>
      statusAt(now) == status ? this : copyWith(status: statusAt(now));
  SwapItemSummary get offeredHistory => offeredSnapshot != null
      ? SwapItemSummary.fromItem(offeredSnapshot!)
      : offeredSummary ??
            SwapItemSummary(
              id: offeredItemId,
              ownerId: requesterId,
              ownerName: 'Anggota komunitas',
              title: 'Barang yang ditawarkan',
            );
  SwapItemSummary get requestedHistory => requestedSnapshot != null
      ? SwapItemSummary.fromItem(requestedSnapshot!)
      : requestedSummary ??
            SwapItemSummary(
              id: requestedItemId,
              ownerId: recipientId,
              ownerName: 'Anggota komunitas',
              title: 'Barang tujuan',
            );

  bool involves(String userId) =>
      requesterId == userId || recipientId == userId;
  bool confirmedBy(String userId) => userId == requesterId
      ? requesterConfirmedAt != null
      : userId == recipientId && recipientConfirmedAt != null;
  bool get hasConfirmation =>
      requesterConfirmedAt != null || recipientConfirmedAt != null;

  SwapOffer copyWith({
    SwapStatus? status,
    List<SwapEvent>? events,
    DateTime? requesterConfirmedAt,
    DateTime? recipientConfirmedAt,
    String? cancellationRequestedBy,
    Meetup? meetup,
    SwapItemSummary? offeredSummary,
    SwapItemSummary? requestedSummary,
    Item? offeredSnapshot,
    Item? requestedSnapshot,
    bool clearCancellationRequest = false,
  }) => SwapOffer(
    id: id,
    requesterId: requesterId,
    recipientId: recipientId,
    offeredItemId: offeredItemId,
    requestedItemId: requestedItemId,
    createdAt: createdAt,
    expiresAt: expiresAt,
    events: events ?? this.events,
    status: status ?? this.status,
    note: note,
    requesterConfirmedAt: requesterConfirmedAt ?? this.requesterConfirmedAt,
    recipientConfirmedAt: recipientConfirmedAt ?? this.recipientConfirmedAt,
    cancellationRequestedBy: clearCancellationRequest
        ? null
        : cancellationRequestedBy ?? this.cancellationRequestedBy,
    meetup: meetup ?? this.meetup,
    offeredSnapshot: offeredSnapshot ?? this.offeredSnapshot,
    requestedSnapshot: requestedSnapshot ?? this.requestedSnapshot,
    offeredSummary: offeredSummary ?? this.offeredSummary,
    requestedSummary: requestedSummary ?? this.requestedSummary,
  );
}
