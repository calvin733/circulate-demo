import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swapcycle/app/providers.dart';
import 'package:swapcycle/core/config/app_config.dart';
import 'package:swapcycle/core/data/demo_store.dart';
import 'package:swapcycle/features/items/presentation/item_editor_screen.dart';

void main() {
  testWidgets('Item editor validates, preserves input and saves a draft', (
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
        child: const MaterialApp(home: ItemEditorScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Simpan draft'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan draft'));
    await tester.pumpAndSettle();
    expect(find.text('Isi 5–80 karakter.'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nama barang'),
      'Buku belajar Flutter',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Deskripsi dan kekurangan barang'),
      'Buku lengkap dan masih bersih, semua halaman tersedia.',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Kota'),
      'Tangerang',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Simpan draft'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan draft'));
    await tester.pumpAndSettle();
    expect(
      (await store.ownedBy(DemoStore.viewerId))
          .any((item) => item.title == 'Buku belajar Flutter'),
      isTrue,
    );
    expect(find.text('Perubahan barang tersimpan.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.linux}));
}
