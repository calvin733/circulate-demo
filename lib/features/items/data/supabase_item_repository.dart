import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'dart:typed_data';

import '../../../core/data/cloud_support.dart';
import '../../../core/errors/app_exception.dart';
import '../domain/item.dart';
import '../domain/item_repository.dart';
import '../domain/item_draft.dart';

abstract final class ItemMapper {
  static List<String> paths(Map<String, dynamic> row) {
    if (row['photos'] case final List<dynamic> photos) {
      return photos.cast<String>();
    }
    final photos =
        (row['item_photos'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>()
            .toList()
          ..sort(
            (a, b) => (a['position'] as int).compareTo(b['position'] as int),
          );
    return photos.map((photo) => photo['storage_path'] as String).toList();
  }

  static Item read(
    Map<String, dynamic> row,
    Map<String, String> urls, {
    ItemStatus? status,
  }) {
    final photos = paths(row);
    final profile = row['profiles'] as Map<String, dynamic>?;
    return Item(
      id: row['id'] as String,
      ownerId: row['owner_id'] as String,
      ownerName:
          row['owner_name'] as String? ??
          profile?['display_name'] as String? ??
          'Anggota komunitas',
      title: row['title'] as String,
      description: row['description'] as String,
      category: ItemCategory.values.byName(row['category_slug'] as String),
      condition: switch (row['condition']) {
        'like_new' => ItemCondition.likeNew,
        'good' => ItemCondition.good,
        _ => ItemCondition.fair,
      },
      city: row['city'] as String,
      preferences: row['preferences'] as String? ?? '',
      status: status ?? ItemStatus.values.byName(row['status'] as String),
      visible: row['visibility'] != 'hidden',
      revision: row['revision'] as int,
      photoPaths: List.unmodifiable(photos),
      imageUrls: List.unmodifiable(photos.map((path) => urls[path] ?? '')),
      photos: List.unmodifiable(
        (row['item_photos'] as List<dynamic>? ?? []).map((value) {
          final photo = value as Map<String, dynamic>;
          return ItemPhoto(
            id: photo['id'] as String,
            path: photo['storage_path'] as String,
            position: photo['position'] as int,
          );
        }),
      ),
    );
  }
}

class SupabaseItemRepository implements ItemRepository {
  SupabaseItemRepository(this.client);
  final SupabaseClient client;
  static const selection =
      '*,profiles(display_name),item_photos(id,storage_path,position)';

  Future<List<Item>> _decode(List<Map<String, dynamic>> rows) async {
    final urls = await signItemPhotos(client, rows.expand(ItemMapper.paths));
    return List.unmodifiable(rows.map((row) => ItemMapper.read(row, urls)));
  }

  @override
  Future<List<Item>> search(ItemFilter filter) => cloudCall(() async {
    var query = client
        .from('items')
        .select(selection)
        .eq('status', 'available')
        .eq('visibility', 'visible');
    if (filter.category != null) {
      query = query.eq('category_slug', filter.category!.name);
    }
    if (filter.condition != null) {
      query = query.eq(
        'condition',
        filter.condition == ItemCondition.likeNew
            ? 'like_new'
            : filter.condition!.name,
      );
    }
    if (filter.query.trim().isNotEmpty) {
      query = query.textSearch(
        'search_vector',
        filter.query.trim(),
        config: 'simple',
        type: TextSearchType.websearch,
      );
    }
    final rows = await query
        .order('created_at', ascending: false)
        .order('id')
        .limit(20);
    return _decode(rows);
  });

  @override
  Future<List<Item>> ownedBy(String ownerId) => cloudCall(() async {
    if (ownerId.isEmpty) return <Item>[];
    requireCurrentUser(client, ownerId);
    return _decode(
      await client
          .from('items')
          .select(selection)
          .eq('owner_id', ownerId)
          .order('created_at', ascending: false)
          .limit(100),
    );
  });

  @override
  Future<Item> find(String id) => cloudCall(() async {
    final row = await client
        .from('items')
        .select(selection)
        .eq('id', id)
        .maybeSingle();
    if (row == null) {
      throw const AppException('NOT_FOUND', 'Barang tidak tersedia.');
    }
    return (await _decode([row])).single;
  });

  @override
  Future<Item> saveDraft(ItemDraft draft) => cloudCall(() async {
    requireCurrentUser(client, client.auth.currentUser?.id ?? '');
    try {
      await client.rpc<String>(
        'save_item',
        params: {
          'p_id': draft.id,
          'p_expected_revision': draft.expectedRevision,
          'p_title': draft.title,
          'p_description': draft.description,
          'p_category_slug': draft.category.name,
          'p_condition': draft.condition == ItemCondition.likeNew
              ? 'like_new'
              : draft.condition.name,
          'p_city': draft.city,
          'p_preferences': draft.preferences,
        },
      );
    } catch (_) {
      // A response can be lost after commit. Only accept the exact desired content.
      try {
        final saved = await find(draft.id);
        if (saved.ownerId == client.auth.currentUser?.id &&
            draft.matches(saved)) {
          return saved;
        }
      } catch (_) {
        /* preserve the original failure */
      }
      rethrow;
    }
    return find(draft.id);
  });

  @override
  Future<Item> addPhoto(
    Item item,
    Uint8List jpeg, {
    String? requestKey,
  }) => cloudCall(() async {
    final actor = client.auth.currentUser?.id ?? '';
    requireCurrentUser(client, item.ownerId);
    final path = '$actor/${item.id}/${requestKey ?? const Uuid().v4()}.jpg';
    final bucket = client.storage.from('item-photos');
    var current = await find(item.id);
    if (current.photos.any((p) => p.path == path)) return current;
    if (!current.visible ||
        current.status == ItemStatus.reserved ||
        current.status == ItemStatus.exchanged) {
      throw const AppException(
        'ITEM_LOCKED',
        'Barang ini sedang tidak dapat diubah.',
      );
    }
    if (current.photos.length >= 5) {
      throw const AppException('PHOTO_LIMIT', 'Maksimal lima foto per barang.');
    }
    if (!await bucket.exists(path)) {
      try {
        await bucket.uploadBinary(
          path,
          jpeg,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );
      } catch (_) {
        // An immutable, stable path lets a retry identify a completed upload.
        if (!await bucket.exists(path)) rethrow;
      }
    }
    current = await find(item.id);
    if (current.photos.any((p) => p.path == path)) return current;
    final occupied = current.photos.map((p) => p.position).toSet();
    final position = List.generate(
      5,
      (i) => i,
    ).where((i) => !occupied.contains(i)).firstOrNull;
    if (position == null) {
      throw const AppException('PHOTO_LIMIT', 'Maksimal lima foto per barang.');
    }
    try {
      await client.rpc<String>(
        'attach_item_photo',
        params: {
          'p_item_id': item.id,
          'p_expected_revision': current.revision,
          'p_path': path,
          'p_position': position,
        },
      );
    } catch (_) {
      try {
        final saved = await find(item.id);
        if (saved.photos.any((p) => p.path == path)) return saved;
      } catch (_) {
        /* retain the object and caller intent on ambiguous failure */
      }
      rethrow;
    }
    return find(item.id);
  });

  @override
  Future<Item> removePhoto(Item item, ItemPhoto photo) => cloudCall(() async {
    requireCurrentUser(client, item.ownerId);
    String path;
    try {
      path = await client.rpc<String>(
        'detach_item_photo',
        params: {'p_photo_id': photo.id, 'p_expected_revision': item.revision},
      );
    } catch (_) {
      final latest = await find(item.id);
      if (latest.photos.any((p) => p.id == photo.id)) rethrow;
      path = photo.path;
    }
    // The listing mutation is authoritative. Snapshot-referenced objects are
    // intentionally retained by Storage policy; cleanup must not undo this edit.
    try {
      await client.storage.from('item-photos').remove([path]);
    } on StorageException {
      /* retained for cleanup */
    }
    return find(item.id);
  });

  @override
  Future<Item> setListingState(Item item, {required bool publish}) =>
      cloudCall(() async {
        requireCurrentUser(client, item.ownerId);
        try {
          await client.rpc<String>(
            'set_listing_state',
            params: {
              'p_item_id': item.id,
              'p_expected_revision': item.revision,
              'p_action': publish ? 'publish' : 'archive',
            },
          );
        } catch (_) {
          final latest = await find(item.id);
          if (latest.ownerId == client.auth.currentUser?.id &&
              latest.status ==
                  (publish ? ItemStatus.available : ItemStatus.archived) &&
              (!publish || latest.visible)) {
            return latest;
          }
          rethrow;
        }
        return find(item.id);
      });
}
