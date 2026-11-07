import 'dart:typed_data';

class MemberProfile {
  const MemberProfile({
    required this.id,
    required this.displayName,
    required this.city,
    required this.bio,
    this.avatarUrl,
    this.avatarPath,
  });
  final String id;
  final String displayName;
  final String city;
  final String bio;
  final String? avatarUrl;
  final String? avatarPath;
}

abstract interface class ProfileRepository {
  Future<MemberProfile> current();
  Future<void> uploadAvatar(Uint8List jpeg, {String? requestKey});
  Future<void> update({
    required String displayName,
    required String city,
    required String bio,
  });
}
