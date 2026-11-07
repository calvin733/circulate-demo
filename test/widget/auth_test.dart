import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swapcycle/app/app_router.dart';
import 'package:swapcycle/app/providers.dart';
import 'package:swapcycle/app/swapcycle_app.dart';
import 'package:swapcycle/core/config/app_config.dart';
import 'package:swapcycle/core/data/demo_store.dart';
import 'package:swapcycle/features/auth/domain/auth_repository.dart';

class FakeAuth implements AuthRepository {
  final changes = StreamController<AuthAccount?>.broadcast();
  @override
  AuthAccount? current;
  @override
  Stream<AuthAccount?> watch() async* {
    yield current;
    yield* changes.stream;
  }

  @override
  Future<void> login(String email, String password) async {
    current = const AuthAccount(id: DemoStore.viewerId);
    changes.add(current);
  }

  @override
  Future<void> logout() async {
    current = null;
    changes.add(null);
  }

  @override
  Future<void> register(String name, String email, String password) async {}
  @override
  Future<void> recover(String email) async {}
  @override
  Future<void> resetPassword(String password) async {}
}

void main() {
  test('Return destinations never open an external URL', () {
    expect(safeDestination('https://untrusted.example'), '/explore');
    expect(safeDestination('//untrusted.example'), '/explore');
    expect(safeDestination('/profile'), '/profile');
    expect(safeDestination('/items/book/offer'), '/items/book/offer');
  });
  test('Cloud configuration rejects secret and service keys', () {
    expect(
      const AppConfig(
        demoMode: false,
        supabaseUrl: 'https://fixture.supabase.co',
        publishableKey: 'sb_secret_fixture',
      ).cloudConfigured,
      false,
    );
    expect(
      const AppConfig(
        demoMode: false,
        supabaseUrl: 'http://fixture.supabase.co',
        publishableKey: 'sb_publishable_fixture',
      ).cloudConfigured,
      false,
    );
    expect(
      const AppConfig(
        demoMode: false,
        supabaseUrl: 'https://fixture.supabase.co',
        publishableKey: 'sb_publishable_fixture',
      ).cloudConfigured,
      true,
    );
  });
  testWidgets('Cloud mode guards private pages and returns after login', (
    tester,
  ) async {
    final auth = FakeAuth();
    final store = DemoStore();
    addTearDown(auth.changes.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              demoMode: false,
              supabaseUrl: 'https://fixture.supabase.co',
              publishableKey: 'sb_publishable_fixture',
            ),
          ),
          authRepositoryProvider.overrideWithValue(auth),
          itemRepositoryProvider.overrideWithValue(store),
          swapRepositoryProvider.overrideWithValue(store),
          profileRepositoryProvider.overrideWithValue(store),
        ],
        child: const SwapCycleApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person_outline).last);
    await tester.pumpAndSettle();
    expect(find.text('Masuk untuk bertukar'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Masuk'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Masuk'));
    await tester.pumpAndSettle();
    expect(find.text('Masukkan email yang valid.'), findsOneWidget);
    expect(find.text('Isi password Anda.'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Tampilkan password'));
    await tester.tap(find.byTooltip('Tampilkan password'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
      isFalse,
    );
    await tester.enterText(
      find.byType(TextFormField).first,
      'fixture@example.test',
    );
    await tester.enterText(find.byType(TextFormField).last, 'fixture-password');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Masuk'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Masuk'));
    await tester.pumpAndSettle();
    expect(find.text('Ayu Pratiwi'), findsOneWidget);
    expect(find.text('Demo lokal'), findsNothing);
    final logout = find.text('Keluar akun');
    await tester.ensureVisible(logout);
    await tester.tap(logout);
    await tester.pumpAndSettle();
    expect(auth.current, isNull);
    expect(find.text('Siap ditukar'), findsOneWidget);
  });
}
