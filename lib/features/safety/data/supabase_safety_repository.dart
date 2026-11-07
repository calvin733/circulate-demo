import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/cloud_support.dart';
import '../domain/safety_repository.dart';

class SupabaseSafetyRepository implements SafetyRepository {
  SupabaseSafetyRepository(this.client);
  final SupabaseClient client;
  final Map<String, String> _keys = {};
  @override
  Future<void> report({
    required ReportKind kind,
    required String target,
    required ReportReason reason,
    required String details,
  }) => cloudCall(() async {
    final intent = '${kind.name}|$target|${reason.code}|${details.trim()}';
    final key = _keys.putIfAbsent(intent, () => const Uuid().v4());
    await client.rpc<String>(
      'submit_report',
      params: {
        'p_kind': kind.name,
        'p_target': target,
        'p_reason': reason.code,
        'p_details': details.trim(),
        'p_request_key': key,
      },
    );
    _keys.remove(intent);
  });
  @override
  Future<void> setBlocked(String target, {required bool blocked}) =>
      cloudCall(() async {
        await client.rpc<String>(
          'set_user_block',
          params: {'p_target': target, 'p_blocked': blocked},
        );
      });
  @override
  Future<List<BlockedMember>> blockedMembers() => cloudCall(() async {
    final actor = client.auth.currentUser?.id ?? '';
    requireCurrentUser(client, actor);
    final rows = await client
        .from('user_blocks')
        .select('blocked_id')
        .eq('blocker_id', actor)
        .order('created_at', ascending: false)
        .limit(200);
    if (rows.isEmpty) return [];
    final ids = rows.map((r) => r['blocked_id'] as String).toList();
    final profiles = await client
        .from('profiles')
        .select('id,display_name')
        .inFilter('id', ids);
    final names = {
      for (final row in profiles)
        row['id'] as String: row['display_name'] as String,
    };
    return ids
        .map((id) => BlockedMember(id, names[id] ?? 'Anggota komunitas'))
        .toList();
  });
}
