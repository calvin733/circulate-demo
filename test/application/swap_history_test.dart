import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swapcycle/app/providers.dart';
import 'package:swapcycle/core/errors/app_exception.dart';
import 'package:swapcycle/features/items/domain/item.dart';
import 'package:swapcycle/features/items/domain/item_repository.dart';
import 'package:swapcycle/features/swaps/application/swap_providers.dart';
import 'package:swapcycle/features/swaps/domain/swap_offer.dart';
import 'package:swapcycle/features/swaps/domain/swap_repository.dart';
import 'package:swapcycle/features/swaps/presentation/swaps_screen.dart';
import 'package:swapcycle/features/swaps/presentation/swap_detail_screen.dart';

SwapOffer historicalOffer({
  String id = 'historical',
  SwapStatus status = SwapStatus.invalidated,
  bool summary = true,
  DateTime? expires,
}) => SwapOffer(
  id: id,
  requesterId: 'other',
  recipientId: 'viewer',
  offeredItemId: 'archived-other',
  requestedItemId: 'own-item',
  createdAt: DateTime.now().subtract(const Duration(days: 1)),
  expiresAt: expires ?? DateTime.now().add(const Duration(days: 5)),
  status: status,
  events: const [],
  offeredSummary: summary
      ? const SwapItemSummary(
          id: 'archived-other',
          ownerId: 'other',
          ownerName: 'Pemilik lama',
          title: 'Judul saat penawaran',
        )
      : null,
  requestedSummary: summary
      ? const SwapItemSummary(
          id: 'own-item',
          ownerId: 'viewer',
          ownerName: 'Saya',
          title: 'Barang saya',
        )
      : null,
);

class HistoryFixture implements SwapRepository {
  HistoryFixture(this.offers);
  final List<SwapOffer> offers;
  int detailReads = 0;
  int listReads = 0;
  @override
  Future<List<SwapOffer>> listFor(String actorId) async {
    listReads++;
    return offers;
  }

  @override
  Future<SwapOffer> findOffer(String id, String actorId) async {
    detailReads++;
    return offers.firstWhere((offer) => offer.id == id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class InaccessibleListings implements ItemRepository {
  int reads = 0;
  @override
  Future<Item> find(String id) async {
    reads++;
    throw const AppException('NOT_FOUND', 'Private archived listing');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Historical detail uses a captured summary without fetching a private archived item', () async {
    final listings = InaccessibleListings();
    final repository = HistoryFixture([historicalOffer()]);
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        viewerIdProvider.overrideWithValue('viewer'),
        swapRepositoryProvider.overrideWithValue(repository),
        itemRepositoryProvider.overrideWithValue(listings),
      ],
    );
    addTearDown(container.dispose);
    final listener = container.listen(
      swapDetailProvider('historical'),
      (_, _) {},
    );
    addTearDown(listener.close);
    final detail = await container.read(
      swapDetailProvider('historical').future,
    );
    expect(detail.offered.title, 'Judul saat penawaran');
    expect(detail.offer.status, SwapStatus.invalidated);
    expect(listings.reads, 0);
  });

  test('Legacy history without summaries remains readable through safe generic labels', () {
    final old = historicalOffer(summary: false);
    expect(old.offeredHistory.title, 'Barang yang ditawarkan');
    expect(old.requestedHistory.title, 'Barang tujuan');
    expect(old.offeredHistory.id, 'archived-other');
  });

  testWidgets(
    'An offer list does not issue a detail or listing query for every tile',
    (tester) async {
      final repository = HistoryFixture(
        List.generate(
          3,
          (i) => historicalOffer(id: 'offer-$i', status: SwapStatus.pending),
        ),
      );
      final listings = InaccessibleListings();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            viewerIdProvider.overrideWithValue('viewer'),
            swapRepositoryProvider.overrideWithValue(repository),
            itemRepositoryProvider.overrideWithValue(listings),
          ],
          child: const MaterialApp(home: Scaffold(body: SwapsScreen())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Judul saat penawaran'), findsNWidgets(3));
      expect(find.text('Barang saya'), findsNWidgets(3));
      expect(repository.listReads, 1);
      expect(repository.detailReads, 0);
      expect(listings.reads, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Expired pending offers move to history and cannot be accepted in detail',
    (tester) async {
      final old = historicalOffer(
        status: SwapStatus.pending,
        expires: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      final repository = HistoryFixture([old]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            viewerIdProvider.overrideWithValue('viewer'),
            swapRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: Scaffold(body: SwapsScreen())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Belum ada pertukaran di sini'), findsOneWidget);
      await tester.tap(find.text('Riwayat'));
      await tester.pumpAndSettle();
      expect(find.text('Kedaluwarsa'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            viewerIdProvider.overrideWithValue('viewer'),
            swapRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(home: SwapDetailScreen(offerId: old.id)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Kedaluwarsa'), findsOneWidget);
      expect(find.text('Terima penawaran'), findsNothing);
      expect(find.text('Tolak penawaran'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('Expiry boundary is exact and never changes an already accepted transaction', () {
    final at = DateTime.utc(2026, 11, 3);
    final pending = historicalOffer(status: SwapStatus.pending, expires: at);
    expect(
      pending.statusAt(at.subtract(const Duration(microseconds: 1))),
      SwapStatus.pending,
    );
    expect(pending.statusAt(at), SwapStatus.expired);
    expect(
      pending.copyWith(status: SwapStatus.accepted).statusAt(at),
      SwapStatus.accepted,
    );
  });
}
