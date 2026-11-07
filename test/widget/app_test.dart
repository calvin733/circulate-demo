import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swapcycle/app/providers.dart';
import 'package:swapcycle/app/swapcycle_app.dart';
import 'package:swapcycle/core/config/app_config.dart';
import 'package:swapcycle/core/errors/app_exception.dart';
import 'package:swapcycle/core/theme/app_theme.dart';
import 'package:swapcycle/core/widgets/shared_widgets.dart';

Widget app({bool demo = true}) => ProviderScope(
  overrides: [appConfigProvider.overrideWithValue(AppConfig(demoMode: demo))],
  child: const SwapCycleApp(),
);

void main() {
  testWidgets('unconfigured build requires explicit entry to local demo', (
    tester,
  ) async {
    await tester.pumpWidget(app(demo: false));
    await tester.pumpAndSettle();
    expect(find.text('Lihat demo lokal'), findsOneWidget);
    expect(find.text('Siap ditukar'), findsNothing);
    await tester.tap(find.text('Lihat demo lokal'));
    await tester.pumpAndSettle();
    expect(find.text('Demo lokal'), findsOneWidget);
    expect(find.text('Atomic Habits'), findsOneWidget);
  });
  testWidgets('search and reset show meaningful empty state', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'tidak-ada-123');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Belum ada yang cocok'), findsOneWidget);
    await tester.ensureVisible(find.text('Reset filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset filter'));
    await tester.pumpAndSettle();
    expect(find.text('Atomic Habits'), findsOneWidget);
  });
  testWidgets('bottom navigation opens own items, offers and profile', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.inventory_2_outlined).last);
    await tester.pumpAndSettle();
    expect(find.text('Monstera mini'), findsOneWidget);
    await tester.tap(find.text('Tukar'));
    await tester.pumpAndSettle();
    expect(find.text('Masuk'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.person_outline).last);
    await tester.pumpAndSettle();
    expect(find.text('Ayu Pratiwi'), findsOneWidget);
  });
  for (final size in [
    const Size(320, 740),
    const Size(390, 844),
    const Size(768, 1024),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('explore fits ${size.width} dp at text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('async error displays safe message and retry', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: AsyncContent<int>(
            value: AsyncValue.error(
              const AppException('TEST', 'Data contoh belum tersedia.'),
              StackTrace.empty,
            ),
            data: (value) => Text('$value'),
            onRetry: () => retried = true,
          ),
        ),
      ),
    );
    expect(find.text('Data contoh belum tersedia.'), findsOneWidget);
    await tester.tap(find.text('Coba lagi'));
    expect(retried, isTrue);
  });
}
