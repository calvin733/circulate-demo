import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../items/application/item_providers.dart';
import '../domain/swap_offer.dart';

final offersProvider = FutureProvider<List<SwapOffer>>((ref) {
  final viewer = ref.watch(viewerIdProvider);
  return viewer.isEmpty
      ? Future.value(<SwapOffer>[])
      : ref.watch(swapRepositoryProvider).listFor(viewer);
});
final offerProvider = FutureProvider.autoDispose.family<SwapOffer, String>(
  (ref, id) => ref
      .watch(swapRepositoryProvider)
      .findOffer(id, ref.watch(viewerIdProvider)),
);

typedef SwapDetail = ({
  SwapOffer offer,
  SwapItemSummary offered,
  SwapItemSummary requested,
});
final swapDetailProvider = FutureProvider.autoDispose
    .family<SwapDetail, String>((ref, id) async {
      final offer = await ref.watch(offerProvider(id).future);
      return (
        offer: offer,
        offered: offer.offeredHistory,
        requested: offer.requestedHistory,
      );
    });

/// Refresh all views of the aggregate after a successful mutation.
void refreshSwapViews(WidgetRef ref, {String? offerId}) {
  ref.invalidate(offersProvider);
  ref.invalidate(myItemsProvider);
  ref.invalidate(exploreItemsProvider);
  ref.invalidate(itemProvider);
  if (offerId != null) {
    ref.invalidate(offerProvider(offerId));
    ref.invalidate(swapDetailProvider(offerId));
  }
}
