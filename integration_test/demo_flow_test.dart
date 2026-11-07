import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:swapcycle/app/providers.dart';
import 'package:swapcycle/app/app_router.dart';
import 'package:swapcycle/app/swapcycle_app.dart';
import 'package:swapcycle/core/config/app_config.dart';
import 'package:swapcycle/core/data/demo_store.dart';
import 'package:swapcycle/features/items/domain/item.dart';
import 'package:swapcycle/features/swaps/domain/swap_offer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('demo browse → offer → withdraw', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(const AppConfig(demoMode: true)),
        ],
        child: const SwapCycleApp(),
      ),
    );
    await tester.pumpAndSettle();
    debugPrint('SMOKE: catalog ready');
    await Scrollable.ensureVisible(
      tester.element(find.text('Atomic Habits')),
      alignment: 0.35,
    );
    await tester.pumpAndSettle();
    expect(find.text('Atomic Habits').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Atomic Habits'));
    await tester.pumpAndSettle();
    debugPrint('SMOKE: item detail ready');
    expect(find.text('Ajukan pertukaran').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Ajukan pertukaran'));
    await tester.pumpAndSettle();
    expect(find.text('Barang yang Anda tawarkan'), findsOneWidget);
    expect(find.text('Monstera mini'), findsOneWidget);
    debugPrint('SMOKE: offer composer ready');
    await tester.ensureVisible(find.text('Monstera mini'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monstera mini'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ajukan penawaran demo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajukan penawaran demo'));
    await tester.pumpAndSettle();
    expect(find.text('Menunggu jawaban'), findsOneWidget);
    await tester.ensureVisible(find.text('Tarik penawaran'));
    await tester.tap(find.text('Tarik penawaran'));
    await tester.pumpAndSettle();
    expect(find.text('Dibatalkan'), findsOneWidget);
    debugPrint('SMOKE: offer submitted and withdrawn');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('demo accept → two receipts → completed history, no meetup', (
    tester,
  ) async {
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
    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      expect(finder.hitTestable(), findsOneWidget);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await tap(find.byKey(const ValueKey('swap-accept')));
    await tap(find.text('Ya, terima penawaran'));
    expect((await store.find('lamp')).status, ItemStatus.reserved);
    await tap(find.byKey(const ValueKey('swap-confirmReceipt')));
    await tap(find.text('Ya, saya sudah menerima barang'));
    expect(
      (await store.findOffer('incoming', DemoStore.viewerId)).status,
      SwapStatus.awaitingConfirmation,
    );
    await tap(find.text('Simulasikan konfirmasi pasangan (demo)'));
    expect(find.text('Selesai'), findsOneWidget);
    expect((await store.find('lamp')).status, ItemStatus.exchanged);
    container.read(routerProvider).go('/swaps');
    await tester.pumpAndSettle();
    await tap(find.text('Riwayat'));
    expect(find.text('Selesai'), findsOneWidget);
    debugPrint(
      'SMOKE: accepted, two simulated participants confirmed, history ready',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
