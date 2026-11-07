import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/cloud_support.dart';
import '../domain/auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this.client);
  final SupabaseClient client;
  bool _recovering = false;
  static const redirect = 'dev.swapcycle.app://auth-callback';
  @override
  AuthAccount? get current {
    final user = client.auth.currentUser;
    return user == null
        ? null
        : AuthAccount(id: user.id, recoveringPassword: _recovering);
  }

  @override
  Stream<AuthAccount?> watch() async* {
    yield current;
    await for (final state in client.auth.onAuthStateChange) {
      if (state.event == AuthChangeEvent.passwordRecovery) _recovering = true;
      if (state.event == AuthChangeEvent.signedOut) _recovering = false;
      yield current;
    }
  }

  @override
  Future<void> login(String email, String password) => cloudCall(() async {
    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  });
  @override
  Future<void> register(String name, String email, String password) =>
      cloudCall(() async {
        await client.auth.signUp(
          email: email.trim(),
          password: password,
          data: {'display_name': name.trim()},
          emailRedirectTo: redirect,
        );
      });
  @override
  Future<void> recover(String email) => cloudCall(
    () => client.auth.resetPasswordForEmail(email.trim(), redirectTo: redirect),
  );
  @override
  Future<void> resetPassword(String password) => cloudCall(() async {
    await client.auth.updateUser(UserAttributes(password: password));
    _recovering = false;
  });
  @override
  Future<void> logout() =>
      cloudCall(() => client.auth.signOut(scope: SignOutScope.local));
}
