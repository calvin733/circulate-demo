enum ReportKind { item, user, offer }

enum ReportReason {
  prohibited('Barang terlarang'),
  misleading('Informasi menyesatkan'),
  harassment('Pelecehan / perilaku mengganggu'),
  noShow('Tidak hadir'),
  conditionMismatch('Kondisi barang tidak sesuai'),
  other('Lainnya');

  const ReportReason(this.label);
  final String label;
  String get code => switch (this) {
    noShow => 'no_show',
    conditionMismatch => 'condition_mismatch',
    _ => name,
  };
}

class BlockedMember {
  const BlockedMember(this.id, this.name);
  final String id;
  final String name;
}

abstract interface class SafetyRepository {
  Future<void> report({
    required ReportKind kind,
    required String target,
    required ReportReason reason,
    required String details,
  });
  Future<void> setBlocked(String target, {required bool blocked});
  Future<List<BlockedMember>> blockedMembers();
}
