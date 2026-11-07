import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../core/data/demo_store.dart';
import '../features/items/domain/item_repository.dart';
import '../features/items/data/supabase_item_repository.dart';
import '../features/swaps/data/supabase_swap_repository.dart';
import '../features/profile/data/supabase_profile_repository.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/auth/data/supabase_auth_repository.dart';
import '../features/profile/domain/member_profile.dart';
import '../features/swaps/domain/swap_repository.dart';
import '../features/safety/domain/safety_repository.dart';
import '../features/safety/data/supabase_safety_repository.dart';

final appConfigProvider = Provider<AppConfig>(
  (ref) => const AppConfig.fromEnvironment(),
);
final bootstrapErrorProvider = Provider<String?>((ref) => null);

class PreviewModeController extends Notifier<bool> {
  @override
  bool build() => false;
  void enterDemo() => state = true;
}

final previewModeProvider = NotifierProvider<PreviewModeController, bool>(
  PreviewModeController.new,
);
final isDemoModeProvider = Provider<bool>(
  (ref) =>
      ref.watch(appConfigProvider).demoMode || ref.watch(previewModeProvider),
);
final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(ref.watch(supabaseClientProvider)),
);
final authAccountProvider = StreamProvider<AuthAccount?>(
  (ref) => ref.watch(isDemoModeProvider)
      ? Stream.value(null)
      : ref.watch(authRepositoryProvider).watch(),
);
// Demo is selected explicitly and never used as a fallback for cloud errors.
final demoStoreProvider = Provider<DemoStore>((ref) => DemoStore());
final viewerIdProvider = Provider<String>(
  (ref) => ref.watch(isDemoModeProvider)
      ? DemoStore.viewerId
      : ref.watch(authAccountProvider).value?.id ??
            ref.watch(authRepositoryProvider).current?.id ??
            '',
);
final itemRepositoryProvider = Provider<ItemRepository>((ref) {
  ref.watch(viewerIdProvider);
  return ref.watch(isDemoModeProvider)
      ? ref.watch(demoStoreProvider)
      : SupabaseItemRepository(ref.watch(supabaseClientProvider));
});
final swapRepositoryProvider = Provider<SwapRepository>((ref) {
  ref.watch(viewerIdProvider);
  return ref.watch(isDemoModeProvider)
      ? ref.watch(demoStoreProvider)
      : SupabaseSwapRepository(ref.watch(supabaseClientProvider));
});
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  ref.watch(viewerIdProvider);
  return ref.watch(isDemoModeProvider)
      ? ref.watch(demoStoreProvider)
      : SupabaseProfileRepository(ref.watch(supabaseClientProvider));
});
final safetyRepositoryProvider = Provider<SafetyRepository>((ref) {
  ref.watch(viewerIdProvider);
  return ref.watch(isDemoModeProvider)
      ? ref.watch(demoStoreProvider)
      : SupabaseSafetyRepository(ref.watch(supabaseClientProvider));
});
