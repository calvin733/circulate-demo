class AuthAccount {
  const AuthAccount({required this.id, this.recoveringPassword = false});
  final String id;
  final bool recoveringPassword;
}

abstract interface class AuthRepository {
  AuthAccount? get current;
  Stream<AuthAccount?> watch();
  Future<void> login(String email, String password);
  Future<void> register(String name, String email, String password);
  Future<void> recover(String email);
  Future<void> resetPassword(String password);
  Future<void> logout();
}
