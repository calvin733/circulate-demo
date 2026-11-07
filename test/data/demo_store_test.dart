import 'package:flutter_test/flutter_test.dart';
import 'package:swapcycle/core/data/demo_store.dart';
import 'package:swapcycle/core/errors/app_exception.dart';
import 'package:swapcycle/features/items/domain/item.dart';
import 'package:swapcycle/features/swaps/domain/swap_offer.dart';

void main() {
  final now = DateTime.utc(2026, 11, 2, 8);
  late DemoStore store;
  setUp(() => store = DemoStore(clock: () => now));
  const viewer = DemoStore.viewerId;

  test(
    'accept reserves both items and invalidates competing pending offers',
    () async {
      final competing = await store.create(
        actorId: viewer,
        offeredItemId: 'lamp',
        requestedItemId: 'coffee',
        requestKey: 'competitor',
      );
      await store.act('incoming', SwapAction.accept, viewer);
      expect((await store.find('lamp')).status, ItemStatus.reserved);
      expect((await store.find('book')).status, ItemStatus.reserved);
      expect(
        (await store.findOffer(competing, viewer)).status,
        SwapStatus.invalidated,
      );
      expect((await store.find('coffee')).status, ItemStatus.available);
    },
  );
  test(
    'idempotent create returns same result; changed payload rejected',
    () async {
      final first = await store.create(
        actorId: viewer,
        offeredItemId: 'plant',
        requestedItemId: 'paint',
        requestKey: 'same',
      );
      final again = await store.create(
        actorId: viewer,
        offeredItemId: 'plant',
        requestedItemId: 'paint',
        requestKey: 'same',
      );
      expect(again, first);
      expect(
        () => store.create(
          actorId: viewer,
          offeredItemId: 'lamp',
          requestedItemId: 'paint',
          requestKey: 'same',
        ),
        throwsA(
          isA<AppException>().having(
            (error) => error.code,
            'code',
            'IDEMPOTENCY_MISMATCH',
          ),
        ),
      );
    },
  );
  test('duplicate reverse pair rejected', () async {
    expect(
      () => store.create(
        actorId: viewer,
        offeredItemId: 'lamp',
        requestedItemId: 'book',
        requestKey: 'reverse',
      ),
      throwsA(
        isA<AppException>().having(
          (error) => error.code,
          'code',
          'DUPLICATE_OFFER',
        ),
      ),
    );
  });
  test('both confirmations exchange both items; repeated confirmation does not duplicate event', () async {
    await store.act('active', SwapAction.confirmReceipt, viewer);
    expect((await store.find('yoga')).status, ItemStatus.reserved);
    await store.act('active', SwapAction.confirmReceipt, 'demo-sari');
    expect(
      (await store.findOffer('active', viewer)).status,
      SwapStatus.completed,
    );
    expect((await store.find('yoga')).status, ItemStatus.exchanged);
    expect((await store.find('cookbook')).status, ItemStatus.exchanged);
    final count = (await store.findOffer('active', viewer)).events.length;
    await store.act('active', SwapAction.confirmReceipt, viewer);
    expect((await store.findOffer('active', viewer)).events.length, count);
  });
  test(
    'one participant cannot release reservation after first confirmation',
    () async {
      await store.act('active', SwapAction.confirmReceipt, viewer);
      await store.act('active', SwapAction.requestCancellation, 'demo-sari');
      expect(
        (await store.findOffer('active', viewer)).status,
        SwapStatus.disputed,
      );
      expect((await store.find('yoga')).status, ItemStatus.reserved);
      expect((await store.find('cookbook')).status, ItemStatus.reserved);
    },
  );
  test('mutual cancellation releases both items', () async {
    await store.act('active', SwapAction.requestCancellation, viewer);
    await store.act('active', SwapAction.approveCancellation, 'demo-sari');
    expect(
      (await store.findOffer('active', viewer)).status,
      SwapStatus.cancelled,
    );
    expect((await store.find('yoga')).status, ItemStatus.available);
    expect((await store.find('cookbook')).status, ItemStatus.available);
  });
  test('third party cannot read private offer or change it', () async {
    expect(
      () => store.findOffer('active', 'third-party'),
      throwsA(isA<AppException>()),
    );
    expect(
      () => store.act('incoming', SwapAction.accept, 'third-party'),
      throwsA(isA<AppException>()),
    );
    expect((await store.find('lamp')).status, ItemStatus.available);
  });
  test(
    'profile validation trims safe fields and rejects excessive lengths',
    () async {
      await store.update(
        displayName: '  Ayu  ',
        city: ' Tangerang ',
        bio: ' Membaca ',
      );
      expect((await store.current()).displayName, 'Ayu');
      expect(
        () => store.update(displayName: 'A', city: 'Tangerang', bio: ''),
        throwsA(isA<AppException>()),
      );
      expect(
        () =>
            store.update(displayName: 'Ayu', city: 'Tangerang', bio: 'x' * 301),
        throwsA(isA<AppException>()),
      );
    },
  );
}
