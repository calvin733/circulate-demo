import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:swapcycle/core/data/demo_store.dart';
import 'package:swapcycle/core/errors/app_exception.dart';
import 'package:swapcycle/features/items/application/photo_processor.dart';
import 'package:swapcycle/features/items/domain/item.dart';
import 'package:swapcycle/features/items/domain/item_draft.dart';
import 'package:swapcycle/features/swaps/domain/swap_offer.dart';

void main() {
  test('New photo is JPEG with baked orientation and no source metadata', () {
    final pixels = image.Image(width: 6, height: 4);
    pixels.exif.imageIfd.orientation = 6;
    pixels.exif.imageIfd.make = 'PRIVATE CAMERA';
    final normalized = normalizeItemPhoto(
      Uint8List.fromList(image.encodeJpg(pixels)),
    );
    final decoded = image.decodeJpg(normalized)!;
    expect(decoded.width, 4);
    expect(decoded.height, 6);
    expect(decoded.exif.imageIfd.make, isNull);
    expect(decoded.exif.imageIfd.orientation, anyOf(isNull, 1));
  });
  test('Invalid photo produces a user-facing error', () {
    expect(
      () => normalizeItemPhoto(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<AppException>()),
    );
  });
  test(
    'Draft requires real photo before publish; stale edits are rejected',
    () async {
      final store = DemoStore();
      final draft = ItemDraft(
        id: 'new',
        expectedRevision: 0,
        title: 'Buku pelajaran',
        description: 'Buku pelajaran lengkap dan masih bersih.',
        category: ItemCategory.books,
        condition: ItemCondition.good,
        city: 'Tangerang',
        preferences: 'Tanaman',
      );
      final item = await store.saveDraft(draft);
      expect(item.status, ItemStatus.draft);
      await expectLater(
        store.setListingState(item, publish: true),
        throwsA(isA<AppException>()),
      );
      final withPhoto = await store.addPhoto(
        item,
        Uint8List.fromList(image.encodeJpg(image.Image(width: 3, height: 3))),
      );
      await expectLater(
        store.setListingState(item, publish: true),
        throwsA(isA<AppException>()),
      );
      final published = await store.setListingState(withPhoto, publish: true);
      expect(published.status, ItemStatus.available);
      await expectLater(
        store.removePhoto(published, published.photos.single),
        throwsA(isA<AppException>()),
      );
      final archived = await store.setListingState(published, publish: false);
      expect(
        (await store.search(const ItemFilter()))
            .any((i) => i.id == archived.id),
        isFalse,
      );
    },
  );
  test(
    'Meetup needs counterpart approval and stale proposal cannot approve',
    () async {
      final now = DateTime(2026, 11, 2);
      final store = DemoStore(clock: () => now);
      await store.act('incoming', SwapAction.accept, DemoStore.viewerId);
      await store.proposeMeetup(
        'incoming',
        DemoStore.viewerId,
        location: 'Lobi perpustakaan kota',
        scheduledAt: now.add(const Duration(days: 1)),
      );
      final first = (await store.findOffer(
        'incoming',
        DemoStore.viewerId,
      )).meetup!;
      await expectLater(
        store.approveMeetup('incoming', DemoStore.viewerId, first),
        throwsA(isA<AppException>()),
      );
      await store.proposeMeetup(
        'incoming',
        'demo-nadia',
        location: 'Lobi museum kota',
        scheduledAt: now.add(const Duration(days: 2)),
      );
      await expectLater(
        store.approveMeetup('incoming', DemoStore.viewerId, first),
        throwsA(isA<AppException>()),
      );
      final latest = (await store.findOffer(
        'incoming',
        DemoStore.viewerId,
      )).meetup!;
      await store.approveMeetup('incoming', DemoStore.viewerId, latest);
      expect(
        (await store.findOffer(
          'incoming',
          DemoStore.viewerId,
        )).meetup!.isApproved,
        isTrue,
      );
    },
  );
}
