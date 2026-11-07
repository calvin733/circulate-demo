import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swapcycle/app/app_router.dart';
import 'package:swapcycle/app/providers.dart';
import 'package:swapcycle/app/swapcycle_app.dart';
import 'package:swapcycle/core/config/app_config.dart';
import 'package:swapcycle/core/data/demo_store.dart';
import 'package:swapcycle/features/items/domain/item.dart';
import 'package:swapcycle/features/swaps/domain/swap_offer.dart';
import 'package:swapcycle/features/swaps/presentation/exchange_pair.dart';

void main() {
  testWidgets(
    'Accept then two different receipt confirmations completes without a meetup',
    (tester) async {
      final store = DemoStore();
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(const AppConfig(demoMode: true)),
          demoStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SwapCycleApp(),
        ),
      );
      await tester.pumpAndSettle();
      container.read(routerProvider).go('/swaps/incoming');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('swap-accept')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ya, terima penawaran'));
      await tester.pumpAndSettle();
      expect((await store.find('lamp')).status, ItemStatus.reserved);
      expect((await store.find('book')).status, ItemStatus.reserved);
      expect(find.text('Usulkan pertemuan'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('swap-confirmReceipt')),
      );
      await tester.tap(find.byKey(const ValueKey('swap-confirmReceipt')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ya, saya sudah menerima barang'));
      await tester.pumpAndSettle();
      expect(
        (await store.findOffer('incoming', DemoStore.viewerId)).status,
        SwapStatus.awaitingConfirmation,
      );
      expect((await store.find('lamp')).status, ItemStatus.reserved);
      await tester.ensureVisible(
        find.text('Simulasikan konfirmasi pasangan (demo)'),
      );
      await tester.tap(find.text('Simulasikan konfirmasi pasangan (demo)'));
      await tester.pumpAndSettle();
      expect(find.text('Selesai'), findsOneWidget);
      expect((await store.find('lamp')).status, ItemStatus.exchanged);
      expect((await store.find('book')).status, ItemStatus.exchanged);
      container.read(routerProvider).go('/swaps');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Riwayat'));
      await tester.pumpAndSettle();
      final pair = tester.widget<ExchangePair>(find.byType(ExchangePair));
      expect(pair.given, 'Lampu meja belajar');
      expect(pair.received, 'Atomic Habits');
      expect(find.text('Selesai'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('An empty offer composer provides a working Add Item route', (
    tester,
  ) async {
    final store = DemoStore();
    await store.setListingState(await store.find('plant'), publish: false);
    await store.setListingState(await store.find('lamp'), publish: false);
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(const AppConfig(demoMode: true)),
        demoStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SwapCycleApp(),
      ),
    );
    await tester.pumpAndSettle();
    container.read(routerProvider).go('/items/book/offer');
    await tester.pumpAndSettle();
    expect(find.text('Belum ada barang tersedia'), findsOneWidget);
    await tester.ensureVisible(find.text('Tambah barang'));
    await tester.tap(find.text('Tambah barang'));
    await tester.pumpAndSettle();
    expect(find.text('Nama barang'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant({TargetPlatform.linux}));
}
