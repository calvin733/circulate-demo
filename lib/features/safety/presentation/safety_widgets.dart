import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../swaps/application/swap_providers.dart';
import '../domain/safety_repository.dart';

class SafetyActions extends ConsumerWidget {
  const SafetyActions({
    super.key,
    required this.memberId,
    required this.memberName,
    this.itemId,
  });
  final String memberId;
  final String memberName;
  final String? itemId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Wrap(
    spacing: AppTokens.sm,
    runSpacing: AppTokens.xs,
    children: [
      if (itemId != null)
        TextButton.icon(
          onPressed: () => _report(context, ref, ReportKind.item, itemId!),
          icon: const Icon(Icons.flag_outlined),
          label: const Text('Laporkan barang'),
        ),
      TextButton(
        onPressed: () => _report(context, ref, ReportKind.user, memberId),
        child: const Text('Laporkan anggota'),
      ),
      TextButton(
        onPressed: () => _block(context, ref),
        child: const Text('Blokir anggota'),
      ),
    ],
  );
  bool _signedIn(BuildContext context, WidgetRef ref) {
    if (ref.read(viewerIdProvider).isNotEmpty) return true;
    context.push(
      Uri(
        path: '/login',
        queryParameters: {'from': GoRouterState.of(context).uri.toString()},
      ).toString(),
    );
    return false;
  }

  void _report(
    BuildContext context,
    WidgetRef ref,
    ReportKind kind,
    String target,
  ) {
    if (!_signedIn(context, ref)) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ReportForm(kind: kind, target: target),
    );
  }

  Future<void> _block(BuildContext context, WidgetRef ref) async {
    if (!_signedIn(context, ref)) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text('Blokir $memberName?'),
        content: const Text(
          'Penawaran baru antarkedua akun akan dicegah dan penawaran menunggu diakhiri. Jika ada pertukaran aktif, barang tetap direservasi dan masalah dicatat. Blokir dapat dibuka melalui Profil.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Blokir anggota'),
          ),
        ],
      ),
    );
    if (approved != true || !context.mounted) return;
    try {
      await ref
          .read(safetyRepositoryProvider)
          .setBlocked(memberId, blocked: true);
      if (!context.mounted) return;
      ref.invalidate(blockedMembersProvider);
      refreshSwapViews(ref);
      showMessage(context, 'Anggota diblokir.');
    } catch (error) {
      if (context.mounted) showMessage(context, friendlyError(error));
    }
  }
}

class _ReportForm extends ConsumerStatefulWidget {
  const _ReportForm({required this.kind, required this.target});
  final ReportKind kind;
  final String target;
  @override
  ConsumerState<_ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends ConsumerState<_ReportForm> {
  final _form = GlobalKey<FormState>();
  final _details = TextEditingController();
  ReportReason _reason = ReportReason.other;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(safetyRepositoryProvider)
          .report(
            kind: widget.kind,
            target: widget.target,
            reason: _reason,
            details: _details.text,
          );
      if (!mounted) return;
      final demo = ref.read(isDemoModeProvider);
      showMessage(
        context,
        demo ? 'Simulasi laporan selesai.' : 'Laporan dicatat. Layanan penanganan belum tersedia pada versi ini.',
      );
      Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppTokens.lg,
          AppTokens.lg,
          AppTokens.lg,
          MediaQuery.viewInsetsOf(context).bottom + AppTokens.lg,
        ),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeading(
                widget.kind == ReportKind.item
                    ? 'Laporkan barang'
                    : 'Laporkan anggota',
              ),
              const SizedBox(height: AppTokens.md),
              InfoPanel(
                text: ref.watch(isDemoModeProvider)
                    ? 'Laporan demo hanya berupa simulasi.'
                    : 'Laporan disimpan untuk peninjauan. Layanan penanganan belum tersedia pada versi ini.',
              ),
              const SizedBox(height: AppTokens.gap),
              DropdownButtonFormField<ReportReason>(
                initialValue: _reason,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Alasan'),
                items: ReportReason.values
                    .map(
                      (v) => DropdownMenuItem(value: v, child: Text(v.label)),
                    )
                    .toList(),
                onChanged: _busy ? null : (v) => setState(() => _reason = v!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _details,
                enabled: !_busy,
                minLines: 3,
                maxLines: 5,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Rincian laporan',
                  helperText:
                      'Jelaskan masalah tanpa menyertakan data pribadi.',
                ),
                validator: (v) => (v ?? '').trim().length < 5
                    ? 'Jelaskan dengan setidaknya 5 karakter.'
                    : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppTokens.sm),
                InfoPanel(text: _error!, tone: NoticeTone.error, live: true),
              ],
              const SizedBox(height: AppTokens.gap),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? 'Menyimpan…' : 'Kirim laporan'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

final blockedMembersProvider = FutureProvider<List<BlockedMember>>((ref) {
  final viewer = ref.watch(viewerIdProvider);
  return viewer.isEmpty
      ? Future.value(<BlockedMember>[])
      : ref.watch(safetyRepositoryProvider).blockedMembers();
});

class BlockedMembersScreen extends ConsumerWidget {
  const BlockedMembersScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Anggota diblokir')),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.lg),
        children: [
          ContentWidth(
            maxWidth: AppTokens.formWidth,
            child: AsyncContent(
              value: ref.watch(blockedMembersProvider),
              onRetry: () => ref.invalidate(blockedMembersProvider),
              loadingLabel: 'Memuat anggota yang diblokir',
              data: (members) => members.isEmpty
                  ? const EmptyState(
                      icon: Icons.block,
                      title: 'Belum ada blokir',
                      message: 'Anggota yang Anda blokir akan muncul di sini.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final member in members) ...[
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AppTokens.gap),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    member.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: AppTokens.xs),
                                  TextButton(
                                    onPressed: () async {
                                      try {
                                        await ref
                                            .read(safetyRepositoryProvider)
                                            .setBlocked(
                                              member.id,
                                              blocked: false,
                                            );
                                        ref.invalidate(blockedMembersProvider);
                                      } catch (error) {
                                        if (context.mounted) {
                                          showMessage(
                                            context,
                                            friendlyError(error),
                                          );
                                        }
                                      }
                                    },
                                    child: const Text('Buka blokir'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: AppTokens.sm),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}
