import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../../core/data/cloud_support.dart';
import '../domain/member_profile.dart';

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this.client);
  final SupabaseClient client;
  @override
  Future<MemberProfile> current() => cloudCall(() async {
    final actor = client.auth.currentUser?.id ?? '';
    requireCurrentUser(client, actor);
    final row = await client
        .from('profiles')
        .select('id,display_name,city,bio,avatar_path')
        .eq('id', actor)
        .single();
    final avatarPath = row['avatar_path'] as String?;
    String? avatarUrl;
    if (avatarPath != null) {
      try {
        avatarUrl = await client.storage
            .from('avatars')
            .createSignedUrl(avatarPath, 600);
      } catch (_) {
        avatarUrl = '';
      }
    }
    return MemberProfile(
      id: row['id'] as String,
      displayName: row['display_name'] as String,
      city: row['city'] as String,
      bio: row['bio'] as String,
      avatarPath: row['avatar_path'] as String?,
      avatarUrl: avatarUrl,
    );
  });
  @override
  Future<void> update({
    required String displayName,
    required String city,
    required String bio,
  }) => cloudCall(() async {
    final actor = client.auth.currentUser?.id ?? '';
    requireCurrentUser(client, actor);
    final row = await client
        .from('profiles')
        .select('avatar_path')
        .eq('id', actor)
        .single();
    await client.rpc<void>(
      'update_profile',
      params: {
        'p_display_name': displayName.trim(),
        'p_city': city.trim(),
        'p_bio': bio.trim(),
        'p_avatar_path': row['avatar_path'],
      },
    );
  });
  @override
  Future<void> uploadAvatar(Uint8List jpeg, {String? requestKey}) =>
      cloudCall(() async {
        final actor = client.auth.currentUser?.id ?? '';
        requireCurrentUser(client, actor);
        final path = '$actor/${requestKey ?? const Uuid().v4()}.jpg';
        final bucket = client.storage.from('avatars');
        if (!await bucket.exists(path)) {
          try {
            await bucket.uploadBinary(
              path,
              jpeg,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: false,
              ),
            );
          } catch (_) {
            if (!await bucket.exists(path)) rethrow;
          }
        }
        final row = await client
            .from('profiles')
            .select('display_name,city,bio,avatar_path')
            .eq('id', actor)
            .single();
        if (row['avatar_path'] == path) return;
        try {
          await client.rpc<void>(
            'update_profile',
            params: {
              'p_display_name': row['display_name'],
              'p_city': row['city'],
              'p_bio': row['bio'],
              'p_avatar_path': path,
            },
          );
        } catch (_) {
          final saved = await client
              .from('profiles')
              .select('avatar_path')
              .eq('id', actor)
              .single();
          if (saved['avatar_path'] != path) rethrow;
        }
        if (row['avatar_path'] case final String previous) {
          try {
            await bucket.remove([previous]);
          } on StorageException {
            /* safe manual cleanup may retry later */
          }
        }
      });
}
