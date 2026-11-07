class AppException implements Exception {
  const AppException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => message;
}

String friendlyError(Object error) => switch (error) {
  AppException(:final message) => message,
  _ => 'Belum bisa memuat data. Periksa koneksi lalu coba lagi.',
};
