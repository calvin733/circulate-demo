import 'dart:typed_data';

import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../items/application/photo_processor.dart';
import '../../items/presentation/item_widgets.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../application/profile_providers.dart';
import '../domain/member_profile.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demo = ref.watch(isDemoModeProvider);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.lg),
      children: [
        ContentWidth(
          maxWidth: AppTokens.formWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeading('Profil', page: true),
              const SizedBox(height: AppTokens.gap),
              AsyncContent(
                value: ref.watch(currentProfileProvider),
                onRetry: () => ref.invalidate(currentProfileProvider),
                loadingLabel: 'Memuat profil',
                data: (profile) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.gap),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _ProfileAvatar(profile: profile),
                            const SizedBox(width: AppTokens.gap),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    profile.displayName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  if (profile.city.isNotEmpty) ...[
                                    const SizedBox(height: AppTokens.xs),
                                    Text(
                                      profile.city,
                                      style: const TextStyle(
                                        color: AppTokens.muted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (profile.bio.isNotEmpty) ...[
                          const SizedBox(height: AppTokens.gap),
                          Text(profile.bio),
                        ],
                        const SizedBox(height: AppTokens.gap),
                        OutlinedButton.icon(
                          onPressed: () => context.push('/profile/edit'),
                          icon: const Icon(Icons.edit_outlined),
                          label: Text(
                            demo ? 'Edit profil demo' : 'Edit profil',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.lg),
              const SectionHeading('Akun dan privasi'),
              const SizedBox(height: AppTokens.sm),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.block_outlined),
                      title: const Text('Anggota diblokir'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/safety'),
                    ),
                    if (!demo) ...[
                      const Divider(indent: 52),
                      ListTile(
                        leading: const Icon(Icons.logout),
                        title: const Text('Keluar akun'),
                        onTap: () async {
                          try {
                            await ref.read(authRepositoryProvider).logout();
                            if (context.mounted) context.go('/explore');
                          } catch (error) {
                            if (context.mounted) {
                              showMessage(context, friendlyError(error));
                            }
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppTokens.gap),
              InfoPanel(
                icon: demo
                    ? Icons.science_outlined
                    : Icons.privacy_tip_outlined,
                text: demo
                    ? 'Profil dan pertukaran demo tersimpan selama sesi ini.'
                    : 'Komunitas dapat melihat nama, kota, dan bio Anda. Email akun bersifat pribadi.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.profile});
  final MemberProfile profile;

  @override
  Widget build(BuildContext context) {
    const size = 64.0;
    final url = profile.avatarUrl;
    return url == null
        ? const CircleAvatar(
            radius: size / 2,
            backgroundColor: AppTokens.sage,
            foregroundColor: AppTokens.primary,
            child: Icon(Icons.person_outline_rounded, size: 30),
          )
        : ClipOval(
            child: SizedBox.square(
              dimension: size,
              child: ItemPhotoView(
                url: url,
                path: profile.avatarPath,
                bucket: 'avatars',
                height: size,
              ),
            ),
          );
  }
}

class EditProfileScreen extends ConsumerWidget {
  const EditProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Edit profil')),
    body: AsyncContent(
      value: ref.watch(currentProfileProvider),
      onRetry: () => ref.invalidate(currentProfileProvider),
      loadingLabel: 'Memuat profil',
      data: (profile) =>
          _EditProfileForm(key: ValueKey(profile.id), profile: profile),
    ),
  );
}

class _EditProfileForm extends ConsumerStatefulWidget {
  const _EditProfileForm({super.key, required this.profile});
  final MemberProfile profile;
  @override
  ConsumerState<_EditProfileForm> createState() => _EditProfileFormState();
}

class _EditProfileFormState extends ConsumerState<_EditProfileForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _city;
  late final TextEditingController _bio;
  bool _busy = false;
  String? _error;
  Uint8List? _pendingAvatar;
  String? _avatarKey;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.displayName);
    _city = TextEditingController(text: widget.profile.city);
    _bio = TextEditingController(text: widget.profile.bio);
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(profileRepositoryProvider)
          .update(displayName: _name.text, city: _city.text, bio: _bio.text);
      if (!mounted) return;
      ref.invalidate(currentProfileProvider);
      Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _photo({bool chooseAgain = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_pendingAvatar == null || chooseAgain) {
        final file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          requestFullMetadata: false,
        );
        if (file == null) return;
        if (await file.length() > 20 * 1024 * 1024) {
          throw const AppException(
            'PHOTO_TOO_LARGE',
            'Pilih foto di bawah 20 MB.',
          );
        }
        _pendingAvatar = await prepareItemPhoto(await file.readAsBytes());
        _avatarKey = const Uuid().v4();
      }
      if (!mounted) return;
      await ref
          .read(profileRepositoryProvider)
          .uploadAvatar(_pendingAvatar!, requestKey: _avatarKey);
      if (mounted) {
        _pendingAvatar = null;
        _avatarKey = null;
        ref.invalidate(currentProfileProvider);
        showMessage(context, 'Foto profil tersimpan.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: ListView(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.lg),
      children: [
        ContentWidth(
          maxWidth: AppTokens.formWidth,
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeading('Foto profil'),
                const SizedBox(height: AppTokens.md),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.gap),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProfileAvatar(profile: widget.profile),
                        const SizedBox(height: AppTokens.md),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _photo,
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: Text(
                            _pendingAvatar == null
                                ? 'Ganti foto profil'
                                : 'Coba lagi unggah foto',
                          ),
                        ),
                        if (_pendingAvatar != null)
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _photo(chooseAgain: true),
                            child: const Text('Pilih foto lain'),
                          ),
                        if (_busy) ...[
                          const SizedBox(height: AppTokens.sm),
                          const LinearProgressIndicator(
                            semanticsLabel: 'Memproses profil',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppTokens.gap),
                  InfoPanel(text: _error!, tone: NoticeTone.error, live: true),
                ],
                const SizedBox(height: AppTokens.lg),
                const SectionHeading('Informasi profil'),
                const SizedBox(height: AppTokens.md),
                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  maxLength: 50,
                  decoration: const InputDecoration(labelText: 'Nama tampilan'),
                  validator: (value) => (value?.trim().length ?? 0) < 2
                      ? 'Nama minimal 2 karakter.'
                      : null,
                ),
                const SizedBox(height: AppTokens.gap),
                TextFormField(
                  controller: _city,
                  enabled: !_busy,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Kota / kabupaten',
                  ),
                  validator: (value) => (value?.trim().length ?? 0) < 2
                      ? 'Isi nama kota / kabupaten.'
                      : null,
                ),
                const SizedBox(height: AppTokens.gap),
                TextFormField(
                  controller: _bio,
                  enabled: !_busy,
                  maxLength: 300,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Tentang Anda'),
                ),
                const SizedBox(height: AppTokens.gap),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(
                    _busy
                        ? 'Menyimpan…'
                        : ref.watch(isDemoModeProvider)
                        ? 'Simpan profil demo'
                        : 'Simpan profil',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
