import 'package:flutter_test/flutter_test.dart';
import 'package:swapcycle/features/items/data/supabase_item_repository.dart';
import 'package:swapcycle/features/items/domain/item.dart';

void main() {
  test('Database item DTO and photo order match deployed schema', () {
    final row = <String, dynamic>{
      'id': 'item',
      'owner_id': 'owner',
      'profiles': <String, dynamic>{'display_name': 'Pemilik'},
      'title': 'Buku contoh',
      'description': 'Deskripsi buku contoh yang cukup lengkap.',
      'category_slug': 'books',
      'condition': 'like_new',
      'city': 'Tangerang',
      'preferences': 'Tanaman',
      'status': 'available',
      'visibility': 'visible',
      'revision': 2,
      'item_photos': <dynamic>[
        <String, dynamic>{
          'id': 'photo2',
          'storage_path': 'second',
          'position': 1,
        },
        <String, dynamic>{
          'id': 'photo1',
          'storage_path': 'first',
          'position': 0,
        },
      ],
    };
    final item = ItemMapper.read(row, {
      'first': 'https://example.test/first',
      'second': 'https://example.test/second',
    });
    expect(item.ownerName, 'Pemilik');
    expect(item.condition, ItemCondition.likeNew);
    expect(item.photoPaths, ['first', 'second']);
    expect(item.imageUrls.first, 'https://example.test/first');
  });
  test('Acceptance snapshot keeps original owner and photo identities', () {
    final row = <String, dynamic>{
      'id': 'item',
      'owner_id': 'owner',
      'owner_name': 'Nama saat diterima',
      'title': 'Buku contoh',
      'description': 'Deskripsi saat penawaran diterima.',
      'category_slug': 'books',
      'condition': 'good',
      'city': 'Tangerang',
      'preferences': 'Tanaman',
      'revision': 2,
      'photos': <dynamic>['original-path'],
    };
    final item = ItemMapper.read(row, {
      'original-path': 'https://example.test/photo',
    }, status: ItemStatus.exchanged);
    expect(item.ownerName, 'Nama saat diterima');
    expect(item.status, ItemStatus.exchanged);
    expect(item.photoPaths, ['original-path']);
  });
}
