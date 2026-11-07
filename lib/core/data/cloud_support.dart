import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_exception.dart';

Future<T> cloudCall<T>(Future<T> Function() action) async {
  try {
    return await action();
  } catch (error) {
    throw mapCloudError(error);
  }
}

AppException mapCloudError(Object error) {
  if (error is AppException) return error;
  if (error is AuthException) {
    return const AppException(
      'AUTH_ERROR',
      'Akun belum dapat diakses. Periksa isian, koneksi, dan verifikasi email Anda.',
    );
  }
  if (error is PostgrestException) {
    final message = switch (error.message) {
      'NOT_OWNER' => 'Anda hanya dapat menggunakan barang milik sendiri.',
      'NOT_PARTICIPANT' => 'Pertukaran tidak tersedia untuk akun ini.',
      'SELF_SWAP' => 'Pilih barang milik anggota lain.',
      'ITEM_UNAVAILABLE' || 'ITEM_LOCKED' =>
        'Barang sudah tidak tersedia untuk aksi ini. Muat ulang data.',
      'STALE_REVISION' || 'STALE_OFFER' =>
        'Barang telah diperbarui. Muat ulang sebelum melanjutkan.',
      'DUPLICATE_OFFER' => 'Sudah ada penawaran untuk kedua barang ini.',
      'EXPIRED' => 'Penawaran sudah kedaluwarsa.',
      'ACCOUNT_NOT_READY' =>
        'Verifikasi email dan pastikan akun Anda aktif untuk melanjutkan.',
      'USER_BLOCKED' => 'Penawaran antarkedua akun ini tidak tersedia.',
      'MEETUP_REQUIRED' => 'Sepakati pertemuan terlebih dahulu.',
      'TOO_EARLY' => 'Konfirmasi tersedia setelah waktu pertemuan tiba.',
      'PHOTO_REQUIRED' =>
        'Tambahkan setidaknya satu foto sebelum mempublikasikan barang.',
      'RATE_LIMITED' => 'Terlalu banyak permintaan. Coba lagi nanti.',
      'REASON_REQUIRED' => 'Jelaskan alasan Anda dengan setidaknya 5 karakter.',
      _ => 'Aksi belum dapat dilakukan. Periksa isian dan muat ulang status terbaru.',
    };
    return AppException(error.message, message);
  }
  return const AppException(
    'NETWORK_ERROR',
    'Koneksi belum berhasil. Periksa internet lalu coba lagi.',
  );
}

Future<Map<String, String>> signItemPhotos(
  SupabaseClient client,
  Iterable<String> paths,
) async {
  final unique = paths.toSet().toList();
  if (unique.isEmpty) return {};
  try {
    final results = await client.storage
        .from('item-photos')
        .createSignedUrlsResult(unique, 600);
    return {
      for (final result in results)
        if (result is SignedUrlSuccess) result.path: result.signedUrl,
    };
  } catch (_) {
    // A failed image request must not hide listing text or private history.
    return {};
  }
}

void requireCurrentUser(SupabaseClient client, String actorId) {
  if (actorId.isEmpty || client.auth.currentUser?.id != actorId) {
    throw const AppException(
      'LOGIN_REQUIRED',
      'Masuk ke akun Anda untuk melanjutkan.',
    );
  }
}
