import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/circulate_brand.dart';
import '../core/widgets/shared_widgets.dart';
import '../features/items/presentation/explore_screen.dart';
import '../features/items/presentation/item_detail_screen.dart';
import '../features/items/presentation/my_items_screen.dart';
import '../features/items/presentation/item_editor_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/swaps/presentation/offer_composer_screen.dart';
import '../features/swaps/presentation/swap_detail_screen.dart';
import '../features/swaps/presentation/swaps_screen.dart';
import '../features/auth/presentation/auth_screen.dart';
import 'providers.dart';
import '../features/safety/presentation/safety_widgets.dart';

String safeDestination(String? value) {
  if (value == null || !value.startsWith('/') || value.startsWith('//')) {
    return '/explore';
  }
  return value.startsWith('/items/') ||
          value.startsWith('/swaps') ||
          value == '/my-items' ||
          value == '/profile' ||
          value == '/safety'
      ? value
      : '/explore';
}

final routerProvider = Provider<GoRouter>((ref) {
  final demo = ref.watch(isDemoModeProvider);
  final refresh = ValueNotifier<int>(0);
  if (!demo) ref.listen(authAccountProvider, (_, _) => refresh.value++);
  final router = GoRouter(
    initialLocation: '/explore',
    refreshListenable: refresh,
    redirect: (context, state) {
      if (demo) return null;
      final account = ref.read(authRepositoryProvider).current;
      final path = state.uri.path;
      if (account?.recoveringPassword == true && path != '/reset-password') {
        return '/reset-password';
      }
      final private =
          path == '/my-items' ||
          path.startsWith('/swaps') ||
          path.startsWith('/profile') ||
          path.endsWith('/offer');
      final needsLogin =
          private ||
          path == '/safety' ||
          path == '/items/new' ||
          path.endsWith('/edit');
      if (account == null && needsLogin) {
        return Uri(
          path: '/login',
          queryParameters: {'from': state.uri.toString()},
        ).toString();
      }
      if (account != null && (path == '/login' || path == '/register')) {
        return safeDestination(state.uri.queryParameters['from']);
      }
      if (path == '/reset-password' && account?.recoveringPassword != true) {
        return account == null ? '/login' : '/profile';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/safety', builder: (_, _) => const BlockedMembersScreen()),
      GoRoute(
        path: '/login',
        builder: (_, state) => AuthScreen(
          mode: AuthMode.login,
          destination: safeDestination(state.uri.queryParameters['from']),
        ),
      ),
      GoRoute(
        path: '/register',
        builder: (_, state) => AuthScreen(
          mode: AuthMode.register,
          destination: safeDestination(state.uri.queryParameters['from']),
        ),
      ),
      GoRoute(
        path: '/recover',
        builder: (_, state) => AuthScreen(
          mode: AuthMode.recover,
          destination: safeDestination(state.uri.queryParameters['from']),
        ),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, _) => const AuthScreen(mode: AuthMode.reset),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/explore',
                builder: (_, _) => const ExploreScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/my-items',
                builder: (_, _) => const MyItemsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/swaps', builder: (_, _) => const SwapsScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, _) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: '/items/new', builder: (_, _) => const ItemEditorScreen()),
      GoRoute(
        path: '/profile/edit',
        builder: (_, _) => const EditProfileScreen(),
      ),
      GoRoute(
        path: '/items/:id/edit',
        builder: (_, state) =>
            ItemEditorScreen(itemId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/items/:id',
        builder: (_, state) =>
            ItemDetailScreen(itemId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/items/:id/offer',
        builder: (_, state) =>
            OfferComposerScreen(requestedItemId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/swaps/:id',
        builder: (_, state) =>
            SwapDetailScreen(offerId: state.pathParameters['id']!),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Halaman tidak tersedia')),
      body: EmptyState(
        icon: Icons.explore_off_outlined,
        title: 'Halaman tidak ditemukan',
        message: 'Tautan mungkin sudah berubah. Kembali ke Jelajah untuk melanjutkan.',
        action: FilledButton(
          onPressed: () => context.go('/explore'),
          child: const Text('Kembali ke Jelajah'),
        ),
      ),
    ),
  );
  ref.onDispose(router.dispose);
  ref.onDispose(refresh.dispose);
  return router;
});

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demo = ref.watch(isDemoModeProvider);
    final scaled = MediaQuery.textScalerOf(context).scale(13);
    final stackDemo = scaled > 18;
    return Scaffold(
      appBar: AppBar(
        title: const CirculateWordmark(),
        automaticallyImplyLeading: false,
        toolbarHeight: stackDemo ? 76 : 60,
        actions: [
          if (demo && !stackDemo)
            const Padding(
              padding: EdgeInsets.only(right: AppTokens.gutter),
              child: Center(child: StatusChip('Demo lokal')),
            ),
        ],
        bottom: demo && stackDemo
            ? PreferredSize(
                preferredSize: Size.fromHeight(scaled * 1.4 + 20),
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: StatusChip('Demo lokal'),
                  ),
                ),
              )
            : null,
      ),
      body: SafeArea(top: false, child: shell),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTokens.line)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (index) => shell.goBranch(
            index,
            initialLocation: index == shell.currentIndex,
          ),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore),
              label: 'Jelajah',
            ),
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2),
              label: 'Barang',
            ),
            NavigationDestination(
              icon: Icon(Icons.swap_horiz_rounded),
              label: 'Tukar',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profil',
            ),
          ],
        ),
      ),
    );
  }
}
