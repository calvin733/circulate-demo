import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:swapcycle/core/errors/app_exception.dart';
import 'package:swapcycle/features/items/data/supabase_item_repository.dart';
import 'package:swapcycle/features/items/domain/item.dart';
import 'package:swapcycle/features/items/domain/item_draft.dart';

import '../support/local_cloud.dart';

void main() {
  late LocalCloudFixture fixture;
  late SupabaseItemRepository repository;
  setUp(() async {
    fixture = LocalCloudFixture();
    await fixture.start();
    repository = SupabaseItemRepository(fixture.client);
  });
  tearDown(() => fixture.close());
  const draft = ItemDraft(
    id: LocalCloudFixture.itemId,
    expectedRevision: 0,
    title: 'Buku belajar Flutter',
    description: 'Buku lengkap yang masih bersih untuk belajar Flutter.',
    category: ItemCategory.books,
    condition: ItemCondition.good,
    city: 'Tangerang',
    preferences: '',
  );

  test(
    'Lost save response is reconciled from the exact committed draft',
    () async {
      fixture.loseSave = true;
      final saved = await repository.saveDraft(draft);
      expect(draft.matches(saved), isTrue);
      expect(saved.ownerId, LocalCloudFixture.actor);
    },
  );
  test('A failed save never passes off another revision with different content as success', () async {
    fixture.row = fixture.makeRow()
      ..['title'] = 'Different title from another edit';
    fixture.rejectSave = true;
    await expectLater(
      repository.saveDraft(draft),
      throwsA(isA<AppException>()),
    );
    expect(fixture.row!['title'], 'Different title from another edit');
  });
  test('Lost upload and attach responses keep one immutable object and one attachment', () async {
    fixture.row = fixture.makeRow();
    fixture.loseUpload = true;
    fixture.loseAttach = true;
    final item = await repository.find(LocalCloudFixture.itemId);
    final bytes = Uint8List.fromList([1, 2, 3]);
    const intent = '43000000-0000-4000-8000-000000000001';
    final saved = await repository.addPhoto(item, bytes, requestKey: intent);
    final again = await repository.addPhoto(item, bytes, requestKey: intent);
    expect(saved.photos.length, 1);
    expect(again.photos.single.path, saved.photos.single.path);
    expect(fixture.uploadedPaths.length, 1);
    expect(fixture.attaches, 1);
    // A signing service outage must not hide the successfully stored listing.
    expect(again.title, 'Buku belajar Flutter');
    expect(again.imageUrls, ['']);
    expect(again.photoPaths.length, 1);
  });
  test('Publication recovery requires an owned visible result', () async {
    fixture.row = fixture.makeRow();
    fixture.losePublish = true;
    final item = await repository.find(LocalCloudFixture.itemId);
    final published = await repository.setListingState(item, publish: true);
    expect(published.status, ItemStatus.available);
    expect(published.id, LocalCloudFixture.itemId);
    // A moderation rejection is not a lost-success response just because the
    // previous status still says available.
    fixture.row!['visibility'] = 'hidden';
    fixture.rejectPublish = true;
    await expectLater(
      repository.setListingState(published, publish: true),
      throwsA(isA<AppException>()),
    );
  });
}
