import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

typedef MediaUrlSigner = Future<String> Function(String bucket, String path);
final mediaUrlSignerProvider = Provider<MediaUrlSigner>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return (bucket, path) =>
      client.storage.from(bucket).createSignedUrl(path, 600);
});

/// Expiry only schedules a UI refresh. Authorization remains in Storage RLS.
DateTime? signedUrlExpiry(String url) {
  try {
    final token = Uri.parse(url).queryParameters['token'];
    if (token == null) return null;
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
    );
    final exp = (payload as Map<String, dynamic>)['exp'];
    return exp is num
        ? DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true)
        : null;
  } catch (_) {
    return null;
  }
}
