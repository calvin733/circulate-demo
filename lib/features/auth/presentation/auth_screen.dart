import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/circulate_brand.dart';
import '../../../core/widgets/shared_widgets.dart';

enum AuthMode { login, register, recover, reset }

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({
    super.key,
    required this.mode,
    this.destination = '/explore',
  });
  final AuthMode mode;
  final String destination;
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  bool _obscured = true;
  String? _error;
  String? _message;
  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  String get _title => switch (widget.mode) {
    AuthMode.login => 'Masuk untuk bertukar',
    AuthMode.register => 'Buat akun Circulate',
    AuthMode.recover => 'Pulihkan akun Anda',
    AuthMode.reset => 'Buat password baru',
  };
  String get _intro => switch (widget.mode) {
    AuthMode.login => 'Kelola barang dan penawaran dengan akun Anda.',
    AuthMode.register => 'Gunakan email yang bisa Anda akses untuk verifikasi.',
    AuthMode.recover => 'Masukkan email yang Anda gunakan saat mendaftar.',
    AuthMode.reset => 'Password ini akan dipakai saat Anda masuk kembali.',
  };
  String get _label => switch (widget.mode) {
    AuthMode.login => 'Masuk',
    AuthMode.register => 'Buat akun',
    AuthMode.recover => 'Kirim tautan pemulihan',
    AuthMode.reset => 'Simpan password baru',
  };
  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final auth = ref.read(authRepositoryProvider);
      switch (widget.mode) {
        case AuthMode.login:
          await auth.login(_email.text, _password.text);
        case AuthMode.register:
          await auth.register(_name.text, _email.text, _password.text);
        case AuthMode.recover:
          await auth.recover(_email.text);
        case AuthMode.reset:
          await auth.resetPassword(_password.text);
      }
      if (!mounted) return;
      _password.clear();
      _confirmation.clear();
      if (widget.mode == AuthMode.login) {
        context.go(widget.destination);
      } else if (widget.mode == AuthMode.reset) {
        context.go('/profile');
      } else {
        setState(
          () => _message = widget.mode == AuthMode.register
              ? 'Jika pendaftaran dapat diproses, periksa email Anda untuk verifikasi sebelum masuk.'
              : 'Jika alamat ini dapat diproses, instruksi pemulihan akan dikirim. Periksa inbox dan folder spam.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsEmail = widget.mode != AuthMode.reset;
    final needsPassword = widget.mode != AuthMode.recover;
    final newPassword =
        widget.mode == AuthMode.register || widget.mode == AuthMode.reset;
    return Scaffold(
      appBar: AppBar(
        title: const CirculateWordmark(size: 22),
        leading: BackButton(onPressed: () => context.go('/explore')),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          children: [
            ContentWidth(
              maxWidth: AppTokens.formWidth,
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppTokens.lg),
                      DecoratedBox(
                        decoration: const BoxDecoration(
                          border: Border(
                            left: BorderSide(color: AppTokens.clay, width: 3),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(left: AppTokens.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                circulateTagline,
                                style: TextStyle(color: AppTokens.muted),
                              ),
                              const SizedBox(height: AppTokens.sm),
                              SectionHeading(_title, page: true),
                              const SizedBox(height: AppTokens.sm),
                              Text(_intro),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTokens.lg),
                      if (widget.mode == AuthMode.register) ...[
                        TextFormField(
                          controller: _name,
                          enabled: !_busy,
                          autofillHints: const [AutofillHints.name],
                          textInputAction: TextInputAction.next,
                          maxLength: 50,
                          decoration: const InputDecoration(
                            labelText: 'Nama tampilan',
                          ),
                          validator: (value) => (value?.trim().length ?? 0) < 2
                              ? 'Nama minimal 2 karakter.'
                              : null,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (needsEmail) ...[
                        TextFormField(
                          controller: _email,
                          enabled: !_busy,
                          textInputAction: needsPassword
                              ? TextInputAction.next
                              : TextInputAction.done,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(labelText: 'Email'),
                          validator: (value) =>
                              RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                  .hasMatch(value?.trim() ?? '')
                              ? null
                              : 'Masukkan email yang valid.',
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (needsPassword) ...[
                        TextFormField(
                          controller: _password,
                          enabled: !_busy,
                          obscureText: _obscured,
                          autofillHints: [
                            newPassword
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          decoration: InputDecoration(
                            labelText: newPassword
                                ? 'Password baru'
                                : 'Password',
                            helperText: newPassword
                                ? 'Gunakan setidaknya 10 karakter.'
                                : null,
                            suffixIcon: IconButton(
                              tooltip: _obscured
                                  ? 'Tampilkan password'
                                  : 'Sembunyikan password',
                              onPressed: () =>
                                  setState(() => _obscured = !_obscured),
                              icon: Icon(
                                _obscured
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) =>
                              (value?.length ?? 0) < (newPassword ? 10 : 1)
                              ? newPassword
                                    ? 'Password minimal 10 karakter.'
                                    : 'Isi password Anda.'
                              : null,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (newPassword) ...[
                        TextFormField(
                          controller: _confirmation,
                          enabled: !_busy,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Ulangi password baru',
                          ),
                          validator: (value) => value != _password.text
                              ? 'Kedua password belum sama.'
                              : null,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_error != null) ...[
                        InfoPanel(
                          text: _error!,
                          tone: NoticeTone.error,
                          live: true,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_message != null) ...[
                        InfoPanel(text: _message!, live: true),
                        const SizedBox(height: 16),
                      ],
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: Text(_busy ? 'Memproses…' : _label),
                      ),
                      const SizedBox(height: 12),
                      if (widget.mode == AuthMode.login) ...[
                        TextButton(
                          onPressed: () => context.go(
                            Uri(
                              path: '/recover',
                              queryParameters: {'from': widget.destination},
                            ).toString(),
                          ),
                          child: const Text('Lupa password?'),
                        ),
                        TextButton(
                          onPressed: () => context.go(
                            Uri(
                              path: '/register',
                              queryParameters: {'from': widget.destination},
                            ).toString(),
                          ),
                          child: const Text('Belum punya akun? Daftar'),
                        ),
                      ] else
                        TextButton(
                          onPressed: () => context.go(
                            Uri(
                              path: '/login',
                              queryParameters: {'from': widget.destination},
                            ).toString(),
                          ),
                          child: const Text('Kembali ke halaman masuk'),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
