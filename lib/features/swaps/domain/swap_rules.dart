import '../../../core/errors/app_exception.dart';
import '../../items/domain/item.dart';
import 'swap_offer.dart';

abstract final class SwapRules {
  static void validateItems({
    required String actorId,
    required Item offered,
    required Item requested,
  }) {
    if (offered.ownerId != actorId) {
      throw const AppException('NOT_OWNER', 'Pilih barang milik Anda sendiri.');
    }
    if (offered.ownerId == requested.ownerId || offered.id == requested.id) {
      throw const AppException('SELF_SWAP', 'Pilih barang milik anggota lain.');
    }
    if (offered.status != ItemStatus.available ||
        requested.status != ItemStatus.available ||
        !offered.visible ||
        !requested.visible) {
      throw const AppException(
        'ITEM_UNAVAILABLE',
        'Salah satu barang sudah tidak tersedia. Muat ulang pilihan Anda.',
      );
    }
  }

  static SwapStatus transition({
    required SwapOffer offer,
    required SwapAction action,
    required String actorId,
    required DateTime now,
  }) {
    if (!offer.involves(actorId)) {
      throw const AppException('NOT_PARTICIPANT', 'Pertukaran tidak tersedia.');
    }
    final status = offer.status;
    if (status == SwapStatus.completed &&
        action == SwapAction.confirmReceipt &&
        offer.confirmedBy(actorId)) {
      return status;
    }
    if (status == SwapStatus.pending) {
      if (!now.isBefore(offer.expiresAt)) {
        throw const AppException('EXPIRED', 'Penawaran ini sudah kedaluwarsa.');
      }
      if (actorId == offer.recipientId) {
        if (action == SwapAction.accept) return SwapStatus.accepted;
        if (action == SwapAction.decline) return SwapStatus.declined;
      }
      if (actorId == offer.requesterId && action == SwapAction.withdraw) {
        return SwapStatus.cancelled;
      }
    }
    if (status.isActive && status != SwapStatus.disputed) {
      if (action == SwapAction.dispute) return SwapStatus.disputed;
      if (action == SwapAction.requestCancellation &&
          status != SwapStatus.cancellationRequested) {
        return offer.hasConfirmation
            ? SwapStatus.disputed
            : SwapStatus.cancellationRequested;
      }
    }
    if (status == SwapStatus.cancellationRequested &&
        actorId != offer.cancellationRequestedBy) {
      if (action == SwapAction.approveCancellation && !offer.hasConfirmation) {
        return SwapStatus.cancelled;
      }
      if (action == SwapAction.rejectCancellation) return SwapStatus.accepted;
    }
    if ((status == SwapStatus.accepted ||
            status == SwapStatus.awaitingConfirmation) &&
        action == SwapAction.confirmReceipt) {
      if (offer.confirmedBy(actorId)) return status;
      final otherConfirmed = actorId == offer.requesterId
          ? offer.recipientConfirmedAt != null
          : offer.requesterConfirmedAt != null;
      return otherConfirmed
          ? SwapStatus.completed
          : SwapStatus.awaitingConfirmation;
    }
    throw const AppException(
      'INVALID_TRANSITION',
      'Aksi ini tidak tersedia pada status atau peran Anda saat ini.',
    );
  }
}
