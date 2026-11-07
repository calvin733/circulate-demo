import 'item.dart';
import 'item_draft.dart';

import 'dart:typed_data';

abstract interface class ItemRepository {
  Future<List<Item>> search(ItemFilter filter);
  Future<List<Item>> ownedBy(String ownerId);
  Future<Item> find(String id);
  Future<Item> saveDraft(ItemDraft draft);
  Future<Item> addPhoto(Item item, Uint8List jpeg, {String? requestKey});
  Future<Item> removePhoto(Item item, ItemPhoto photo);
  Future<Item> setListingState(Item item, {required bool publish});
}
