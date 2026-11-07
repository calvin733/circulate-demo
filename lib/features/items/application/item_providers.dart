import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/item.dart';

class ItemFilterController extends Notifier<ItemFilter> {
  @override
  ItemFilter build() => const ItemFilter();

  void query(String query) => state = ItemFilter(
    query: query,
    category: state.category,
    condition: state.condition,
  );
  void category(ItemCategory? category) => state = ItemFilter(
    query: state.query,
    category: category,
    condition: state.condition,
  );
  void condition(ItemCondition? condition) => state = ItemFilter(
    query: state.query,
    category: state.category,
    condition: condition,
  );
  void reset() => state = const ItemFilter();
}

final itemFilterProvider = NotifierProvider<ItemFilterController, ItemFilter>(
  ItemFilterController.new,
);
final exploreItemsProvider = FutureProvider<List<Item>>(
  (ref) =>
      ref.watch(itemRepositoryProvider).search(ref.watch(itemFilterProvider)),
);
final myItemsProvider = FutureProvider<List<Item>>(
  (ref) =>
      ref.watch(itemRepositoryProvider).ownedBy(ref.watch(viewerIdProvider)),
);
final itemProvider = FutureProvider.autoDispose.family<Item, String>(
  (ref, id) => ref.watch(itemRepositoryProvider).find(id),
);
