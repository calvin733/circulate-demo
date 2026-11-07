import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swapcycle/app/providers.dart';
import 'package:swapcycle/core/config/app_config.dart';
import 'package:swapcycle/features/auth/domain/auth_repository.dart';
import 'package:swapcycle/features/safety/domain/safety_repository.dart';
import 'package:swapcycle/features/safety/presentation/safety_widgets.dart';

class SessionFixture implements AuthRepository {
  final events = StreamController<AuthAccount?>.broadcast();
  @override
  AuthAccount? current = const AuthAccount(id: 'A');
  void change(String? id) {
    current = id == null ? null : AuthAccount(id: id);
    events.add(current);
  }

  @override
  Stream<AuthAccount?> watch() async* {
    yield current;
    yield* events.stream;
  }

  @override
  Future<void> logout() async => change(null);
  @override
  Future<void> login(String email, String password) async => change(email);
  @override
  Future<void> register(String name, String email, String password) async {}
  @override
  Future<void> recover(String email) async {}
  @override
  Future<void> resetPassword(String password) async {}
}

class SafetyFixture implements SafetyRepository {
  SafetyFixture(this.auth);
  final SessionFixture auth;
  Completer<List<BlockedMember>>? accountB;
  int reads = 0;
  @override
  Future<List<BlockedMember>> blockedMembers() async {
    reads++;
    if (auth.current?.id == 'B' && accountB != null) return accountB!.future;
    return [BlockedMember('target', 'Private list of ${auth.current?.id}')];
  }

  @override
  Future<void> setBlocked(String target, {required bool blocked}) async {}
  @override
  Future<void> report({
    required ReportKind kind,
    required String target,
    required ReportReason reason,
    required String details,
  }) async {}
}

void main() {
  testWidgets(
    'A logout B never displays the previous blocked list, including while loading',
    (tester) async {
      final auth = SessionFixture();
      final safety = SafetyFixture(auth);
      addTearDown(auth.events.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(
              const AppConfig(demoMode: false),
            ),
            authRepositoryProvider.overrideWithValue(auth),
            safetyRepositoryProvider.overrideWithValue(safety),
          ],
          child: const MaterialApp(home: BlockedMembersScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private list of A'), findsOneWidget);
      await auth.logout();
      await tester.pumpAndSettle();
      expect(find.text('Private list of A'), findsNothing);
      expect(find.text('Belum ada blokir'), findsOneWidget);
      safety.accountB = Completer<List<BlockedMember>>();
      auth.change('B');
      await tester.pump();
      await tester.pump();
      expect(find.text('Private list of A'), findsNothing);
      expect(find.text('Memuat anggota yang diblokir'), findsOneWidget);
      safety.accountB!.complete([
        BlockedMember('b-target', 'Private list of B'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Private list of B'), findsOneWidget);
      expect(safety.reads, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'User-bound repository instances reset together when the account changes',
    () async {
      final auth = SessionFixture();
      final client = SupabaseClient(
        'https://fixture.invalid',
        'sb_publishable_fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(const AppConfig(demoMode: false)),
          authRepositoryProvider.overrideWithValue(auth),
          supabaseClientProvider.overrideWithValue(client),
        ],
      );
      final subscription = container.listen(
        viewerIdProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() async {
        subscription.close();
        container.dispose();
        await auth.events.close();
        await client.dispose();
      });
      await container.read(authAccountProvider.future);
      // The fixture's async* installs its upstream listener after the initial yield.
      await Future<void>.delayed(Duration.zero);
      final first = [
        container.read(itemRepositoryProvider),
        container.read(swapRepositoryProvider),
        container.read(profileRepositoryProvider),
        container.read(safetyRepositoryProvider),
      ];
      auth.change('B');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(viewerIdProvider), 'B');
      final second = [
        container.read(itemRepositoryProvider),
        container.read(swapRepositoryProvider),
        container.read(profileRepositoryProvider),
        container.read(safetyRepositoryProvider),
      ];
      for (var i = 0; i < first.length; i++) {
        expect(identical(first[i], second[i]), isFalse);
      }
    },
  );
}
