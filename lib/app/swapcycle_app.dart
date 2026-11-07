import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/circulate_brand.dart';
import '../core/widgets/shared_widgets.dart';
import 'app_router.dart';
import 'providers.dart';

class SwapCycleApp extends ConsumerStatefulWidget {
  const SwapCycleApp({super.key});
  @override
  ConsumerState<SwapCycleApp> createState() => _SwapCycleAppState();
}

class _SwapCycleAppState extends ConsumerState<SwapCycleApp> {
  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final bootstrapError = ref.watch(bootstrapErrorProvider);
    if (ref.watch(isDemoModeProvider) ||
        (config.cloudConfigured && bootstrapError == null)) {
      return const _RoutedApp();
    }
    return MaterialApp(
      title: circulateName,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        body: SafeArea(
          child: ListView(
            children: [
              ContentWidth(
                maxWidth: AppTokens.formWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppTokens.xxl),
                    const CirculateWordmark(size: 34),
                    const SizedBox(height: 16),
                    const SectionHeading(circulateTagline),
                    const SizedBox(height: 24),
                    InfoPanel(
                      text: bootstrapError ?? 'Buka demo lokal untuk mencoba pertukaran dengan barang contoh.',
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () =>
                          ref.read(previewModeProvider.notifier).enterDemo(),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Lihat demo lokal'),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Data demo akan direset ketika aplikasi dimulai ulang.',
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoutedApp extends ConsumerWidget {
  const _RoutedApp();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(viewerIdProvider, (previous, next) {
      if (previous != null && previous != next) {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      }
    });
    return MaterialApp.router(
      title: circulateName,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
