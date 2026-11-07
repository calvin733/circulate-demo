// Optional native-cloud verification. Requires two existing, email-verified test accounts.
// This test never creates/auto-confirms accounts and leaves its labeled exchange history intact.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as image;
import 'package:swapcycle/app/app_router.dart';
import 'package:swapcycle/app/providers.dart';
import 'package:swapcycle/app/swapcycle_app.dart';
import 'package:swapcycle/core/config/app_config.dart';
import 'package:swapcycle/features/items/application/photo_processor.dart';
import 'package:swapcycle/features/items/data/supabase_item_repository.dart';
import 'package:swapcycle/features/items/domain/item.dart';
import 'package:swapcycle/features/items/domain/item_draft.dart';
import 'package:swapcycle/features/swaps/application/swap_providers.dart';
import 'package:swapcycle/features/swaps/data/supabase_swap_repository.dart';
import 'package:swapcycle/features/swaps/domain/swap_offer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const config = AppConfig.fromEnvironment();
  const emailA = String.fromEnvironment('QA_EMAIL_A');
  const passwordA = String.fromEnvironment('QA_PASSWORD_A');
  const emailB = String.fromEnvironment('QA_EMAIL_B');
  const passwordB = String.fromEnvironment('QA_PASSWORD_B');
  final available =
      config.cloudConfigured &&
      !config.demoMode &&
      [emailA, passwordA, emailB, passwordB].every((v) => v.isNotEmpty);
  testWidgets(
    'verified A/B cloud: publish photos, swap, accept, two receipts and history',
    (tester) async {
      await Supabase.initialize(
        url: config.supabaseUrl,
        publishableKey: config.publishableKey,
        debug: false,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          persistSession: false,
        ),
      );
      final client = Supabase.instance.client;
      final container = ProviderContainer(
        overrides: [appConfigProvider.overrideWithValue(config)],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await client.auth.signOut(scope: SignOutScope.local);
        await Supabase.instance.dispose();
      });
      Future<String> login(String email, String password) async {
        await client.auth.signOut(scope: SignOutScope.local);
        final response = await client.auth.signInWithPassword(
          email: email,
          password: password,
        );
        expect(
          response.user?.emailConfirmedAt,
          isNotNull,
          reason: 'Use an email-verified account',
        );
        return response.user!.id;
      }

      final items = SupabaseItemRepository(client);
      final swaps = SupabaseSwapRepository(client);
      final run = const Uuid().v4().substring(0, 8);
      final photo = normalizeItemPhoto(
        image.encodeJpg(image.Image(width: 4, height: 4)),
      );
      Future<Item> publish(String label) async {
        var item = await items.saveDraft(
          ItemDraft(
            id: const Uuid().v4(),
            expectedRevision: 0,
            title: 'QA $run $label',
            description:
                'Barang khusus demonstrasi cloud SwapCycle dengan foto uji.',
            category: ItemCategory.books,
            condition: ItemCondition.good,
            city: 'Tangerang',
            preferences: 'Pertukaran demonstrasi',
          ),
        );
        item = await items.addPhoto(item, photo, requestKey: const Uuid().v4());
        return items.setListingState(item, publish: true);
      }

      final a = await login(emailA, passwordA);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SwapCycleApp(),
        ),
      );
      await tester.pumpAndSettle();
      final itemA = await publish('Buku A');
      debugPrint('CLOUD_QA: A published a photo listing');
      final b = await login(emailB, passwordB);
      expect(b, isNot(a), reason: 'Two distinct test accounts are required');
      final itemB = await publish('Buku B');
      final id = await swaps.create(
        actorId: b,
        offeredItemId: itemB.id,
        requestedItemId: itemA.id,
        requestKey: const Uuid().v4(),
      );
      debugPrint('CLOUD_QA: B published and submitted an offer');
      await login(emailA, passwordA);
      await swaps.act(id, SwapAction.accept, a);
      expect((await items.find(itemA.id)).status, ItemStatus.reserved);
      expect((await items.find(itemB.id)).status, ItemStatus.reserved);
      expect((await swaps.findOffer(id, a)).meetup, isNull);
      await swaps.act(id, SwapAction.confirmReceipt, a);
      expect(
        (await swaps.findOffer(id, a)).status,
        SwapStatus.awaitingConfirmation,
      );
      await login(emailB, passwordB);
      await swaps.act(id, SwapAction.confirmReceipt, b);
      expect((await swaps.findOffer(id, b)).status, SwapStatus.completed);
      expect((await items.find(itemB.id)).status, ItemStatus.exchanged);
      expect(
        (await swaps.listFor(b))
            .any((o) => o.id == id && o.status == SwapStatus.completed),
        isTrue,
      );
      await login(emailA, passwordA);
      expect(
        (await swaps.listFor(a))
            .any((o) => o.id == id && o.status == SwapStatus.completed),
        isTrue,
      );
      container.invalidate(offersProvider);
      container.invalidate(offerProvider(id));
      await tester.pumpAndSettle();
      container.read(routerProvider).go('/swaps/$id');
      await tester.pumpAndSettle();
      expect(find.text('Selesai'), findsOneWidget);
      debugPrint('CLOUD_QA: two receipts and both histories verified');
    },
    skip: !available,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
