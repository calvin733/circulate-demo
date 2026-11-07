class AppConfig {
  const AppConfig({
    required this.demoMode,
    this.supabaseUrl = '',
    this.publishableKey = '',
  });

  const AppConfig.fromEnvironment()
    : demoMode = const bool.fromEnvironment('DEMO_MODE'),
      supabaseUrl = const String.fromEnvironment('SUPABASE_URL'),
      publishableKey = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  final bool demoMode;
  final String supabaseUrl;
  final String publishableKey;
  bool get cloudConfigured =>
      Uri.tryParse(supabaseUrl)?.scheme == 'https' &&
      publishableKey.startsWith('sb_publishable_');
}
