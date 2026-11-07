import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/member_profile.dart';

final currentProfileProvider = FutureProvider<MemberProfile>((ref) {
  ref.watch(viewerIdProvider);
  return ref.watch(profileRepositoryProvider).current();
});
