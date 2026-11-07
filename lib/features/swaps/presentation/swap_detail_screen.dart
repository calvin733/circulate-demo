import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../application/swap_providers.dart';
import '../domain/swap_offer.dart';
import 'exchange_pair.dart';
import 'offer_time_boundary.dart';

class SwapDetailScreen extends ConsumerStatefulWidget {
  const SwapDetailScreen({super.key, required this.offerId});
  final String offerId;
  @override
  ConsumerState<SwapDetailScreen> createState() => _SwapDetailScreenState();
}

class _SwapDetailScreenState extends ConsumerState<SwapDetailScreen> {
  bool _busy = false;
  String? _error;

  Future<bool> _confirm(String title, String message, String label) async =>
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeading(title),
                  const SizedBox(height: AppTokens.md),
                  Text(message),
                  const SizedBox(height: AppTokens.lg),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(label),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Kembali'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ) ??
      false;

  Future<void> _act(SwapAction action, {bool simulatePartner = false}) async {
    if (_busy || (simulatePartner && !ref.read(isDemoModeProvider))) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final offer = await ref.read(offerProvider(widget.offerId).future);
      if (!mounted) return;
      if (!simulatePartner) {
        if (action == SwapAction.accept &&
            !await _confirm(
              'Terima penawaran ini?',
              'Kedua barang akan direservasi. Pertukaran selesai setelah Anda dan pasangan masing-masing mengonfirmasi penerimaan.',
              'Ya, terima penawaran',
            )) {
          return;
        }
        if (action == SwapAction.confirmReceipt &&
            !await _confirm(
              'Barang sudah Anda terima?',
              'Periksa kondisi barang. Pertukaran selesai setelah Anda dan pasangan mengonfirmasi penerimaan.',
              'Ya, saya sudah menerima barang',
            )) {
          return;
        }
        if ((action == SwapAction.dispute ||
                action == SwapAction.requestCancellation &&
                    offer.hasConfirmation) &&
            !await _confirm(
              'Catat masalah pertukaran?',
              'Barang tetap direservasi. Versi portfolio ini belum menyediakan layanan penyelesaian sengketa. Jangan gunakan aksi ini untuk membatalkan barang yang sudah berpindah.',
              'Catat masalah',
            )) {
          return;
        }
      }
      if (!mounted) return;
      final viewer = ref.read(viewerIdProvider);
      final actor = simulatePartner
          ? (offer.requesterId == viewer
                ? offer.recipientId
                : offer.requesterId)
          : viewer;
      await ref.read(swapRepositoryProvider).act(widget.offerId, action, actor);
      if (mounted) {
        showMessage(
          context,
          simulatePartner
              ? 'Konfirmasi pasangan disimulasikan pada demo lokal.'
              : 'Status pertukaran diperbarui.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) {
        refreshSwapViews(ref, offerId: widget.offerId);
        setState(() => _busy = false);
      }
    }
  }

  Widget _action(String label, SwapAction action, {bool primary = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppTokens.sm),
        child: SizedBox(
          width: double.infinity,
          child: primary
              ? FilledButton(
                  key: ValueKey('swap-${action.name}'),
                  onPressed: _busy ? null : () => _act(action),
                  child: Text(_busy ? 'Menyimpan…' : label),
                )
              : OutlinedButton(
                  onPressed: _busy ? null : () => _act(action),
                  child: Text(label),
                ),
        ),
      );

  Widget _actions(SwapOffer offer, String viewer) {
    if (offer.status == SwapStatus.pending) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Berlaku hingga ${displayDate(offer.expiresAt)}'),
          const SizedBox(height: 12),
          if (viewer == offer.recipientId) ...[
            _action('Terima penawaran', SwapAction.accept, primary: true),
            _action('Tolak penawaran', SwapAction.decline),
          ] else
            _action('Tarik penawaran', SwapAction.withdraw),
        ],
      );
    }
    if (offer.status == SwapStatus.accepted ||
        offer.status == SwapStatus.awaitingConfirmation) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (offer.confirmedBy(viewer)) ...[
            const InfoPanel(
              text: 'Konfirmasi Anda tersimpan. Barang tetap direservasi sambil menunggu konfirmasi pasangan.',
            ),
            if (ref.watch(isDemoModeProvider))
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _act(
                        SwapAction.confirmReceipt,
                        simulatePartner: true,
                      ),
                child: const Text('Simulasikan konfirmasi pasangan (demo)'),
              ),
          ] else
            _action(
              'Saya sudah menerima barang',
              SwapAction.confirmReceipt,
              primary: true,
            ),
          const SizedBox(height: 8),
          _action(
            offer.hasConfirmation
                ? 'Ada masalah setelah penerimaan'
                : 'Minta pembatalan',
            SwapAction.requestCancellation,
          ),
          TextButton(
            onPressed: _busy ? null : () => _act(SwapAction.dispute),
            child: const Text('Laporkan masalah pertukaran'),
          ),
        ],
      );
    }
    if (offer.status == SwapStatus.cancellationRequested) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (offer.cancellationRequestedBy == viewer)
            const InfoPanel(
              text: 'Menunggu persetujuan pembatalan dari pasangan. Barang tetap direservasi.',
            )
          else ...[
            _action(
              'Setujui pembatalan',
              SwapAction.approveCancellation,
              primary: true,
            ),
            _action('Lanjutkan pertukaran', SwapAction.rejectCancellation),
          ],
          TextButton(
            onPressed: _busy ? null : () => _act(SwapAction.dispute),
            child: const Text('Catat masalah pertukaran'),
          ),
        ],
      );
    }
    return InfoPanel(
      tone: offer.statusTone,
      icon: offer.status == SwapStatus.completed
          ? Icons.task_alt
          : Icons.info_outline,
      text: switch (offer.status) {
        SwapStatus.completed => 'Kedua peserta sudah mengonfirmasi penerimaan. Kedua barang tercatat sebagai sudah ditukar.',
        SwapStatus.expired => 'Penawaran sudah melewati batas waktu. Buat penawaran baru bila kedua barang masih tersedia.',
        SwapStatus.invalidated => 'Penawaran berakhir karena barang berubah, tidak tersedia, atau hubungan akun diblokir.',
        SwapStatus.declined => 'Penawaran ini ditolak oleh penerima.',
        SwapStatus.cancelled =>
          'Penawaran dibatalkan. Riwayat kesepakatan tetap tersimpan.',
        _ =>
          ref.watch(isDemoModeProvider)
              ? 'Demo terbatas: barang tetap direservasi dan tidak ada laporan yang dikirim.'
              : 'Masalah dicatat dan barang tetap direservasi. Versi portfolio belum mempunyai layanan penyelesaian sengketa.',
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Detail pertukaran'),
      leading: BackButton(
        onPressed: () =>
            context.canPop() ? context.pop() : context.go('/swaps'),
      ),
    ),
    body: AsyncContent(
      value: ref.watch(swapDetailProvider(widget.offerId)),
      onRetry: () => ref.invalidate(offerProvider(widget.offerId)),
      loadingLabel: 'Memuat detail pertukaran',
      data: (detail) => OfferTimeBoundary(
        offers: [detail.offer],
        builder: (now) {
          final offer = detail.offer.forDisplay(now);
          final viewer = ref.watch(viewerIdProvider);
          final partnerConfirmed = viewer == offer.requesterId
              ? offer.recipientConfirmedAt != null
              : offer.requesterConfirmedAt != null;
          return SafeArea(
            top: false,
            child: ListView(
              children: [
                ContentWidth(
                  maxWidth: AppTokens.formWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppTokens.gap),
                      Wrap(
                        spacing: AppTokens.md,
                        runSpacing: AppTokens.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatusChip(offer.statusLabel, tone: offer.statusTone),
                          Text(
                            displayDate(offer.createdAt),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.gap),
                      Text(
                        'Dengan ${offer.partnerName(viewer)}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppTokens.md),
                      ExchangePair.forOffer(offer: offer, viewer: viewer),
                      if (offer.status.isActive ||
                          offer.status == SwapStatus.completed) ...[
                        const SizedBox(height: AppTokens.gap),
                        _ReceiptProgress(
                          viewerConfirmed: offer.confirmedBy(viewer),
                          partnerConfirmed: partnerConfirmed,
                        ),
                      ],
                      const SizedBox(height: AppTokens.gap),
                      if (_error != null) ...[
                        InfoPanel(
                          text: _error!,
                          tone: NoticeTone.error,
                          live: true,
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  ref.invalidate(offerProvider(widget.offerId));
                                  setState(() => _error = null);
                                },
                          child: const Text('Muat ulang status'),
                        ),
                      ],
                      _actions(offer, viewer),
                      if (offer.note.isNotEmpty) ...[
                        const SizedBox(height: AppTokens.gap),
                        const SectionHeading('Catatan penawaran'),
                        const SizedBox(height: AppTokens.sm),
                        InfoPanel(icon: Icons.notes_outlined, text: offer.note),
                      ],
                      if (offer.meetup case final meetup?) ...[
                        const SizedBox(height: AppTokens.gap),
                        InfoPanel(
                          icon: Icons.location_on_outlined,
                          text:
                              'Catatan pertemuan (opsional)\n${meetup.location}\n${displayDate(meetup.scheduledAt)}',
                        ),
                      ],
                      if (offer.events.isNotEmpty) ...[
                        const SizedBox(height: AppTokens.lg),
                        const SectionHeading('Riwayat pertukaran'),
                        const SizedBox(height: AppTokens.sm),
                        Card(
                          child: Column(
                            children: [
                              for (final (index, event)
                                  in offer.events.indexed) ...[
                                if (index > 0) const Divider(indent: 52),
                                ListTile(
                                  leading: const Icon(
                                    Icons.check_circle_outline,
                                  ),
                                  title: Text(event.label),
                                  subtitle: Text(displayDate(event.at)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: AppTokens.lg),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _ReceiptProgress extends StatelessWidget {
  const _ReceiptProgress({
    required this.viewerConfirmed,
    required this.partnerConfirmed,
  });
  final bool viewerConfirmed;
  final bool partnerConfirmed;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppTokens.gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeading('Konfirmasi'),
          const SizedBox(height: AppTokens.xs),
          if (!(viewerConfirmed && partnerConfirmed))
            const Text('Kedua peserta perlu mengonfirmasi penerimaan.'),
          const SizedBox(height: AppTokens.md),
          Wrap(
            spacing: AppTokens.sm,
            runSpacing: AppTokens.sm,
            children: [
              StatusChip(
                viewerConfirmed
                    ? 'Anda sudah konfirmasi'
                    : 'Anda belum konfirmasi',
                tone: viewerConfirmed ? NoticeTone.success : NoticeTone.neutral,
              ),
              StatusChip(
                partnerConfirmed
                    ? 'Pasangan sudah konfirmasi'
                    : 'Pasangan belum konfirmasi',
                tone: partnerConfirmed
                    ? NoticeTone.success
                    : NoticeTone.neutral,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
