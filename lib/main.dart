import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/swapcycle_app.dart';
import 'app/providers.dart';
import 'core/config/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const config = AppConfig.fromEnvironment();
  String? error;
  if (!config.demoMode && config.cloudConfigured) {
    try {
      await Supabase.initialize(
        url: config.supabaseUrl,
        publishableKey: config.publishableKey,
        debug: false,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );
    } catch (_) {
      error = 'Layanan cloud belum dapat dihubungkan. Periksa koneksi dan konfigurasi aplikasi.';
    }
  }
  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        bootstrapErrorProvider.overrideWithValue(error),
      ],
      child: const SwapCycleApp(),
    ),
  );
}
