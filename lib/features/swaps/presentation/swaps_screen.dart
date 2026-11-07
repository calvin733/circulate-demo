import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../application/swap_providers.dart';
import '../domain/swap_offer.dart';
import 'exchange_pair.dart';
import 'offer_time_boundary.dart';

class SwapsScreen extends ConsumerStatefulWidget {
  const SwapsScreen({super.key});
  @override
  ConsumerState<SwapsScreen> createState() => _SwapsScreenState();
}

class _SwapsScreenState extends ConsumerState<SwapsScreen> {
  int _tab = 0;
  static const _labels = ['Masuk', 'Keluar', 'Aktif', 'Riwayat'];

  bool _matches(SwapOffer offer, String viewer, DateTime now) {
    final status = offer.statusAt(now);
    return switch (_tab) {
      0 => offer.recipientId == viewer && status == SwapStatus.pending,
      1 => offer.requesterId == viewer && status == SwapStatus.pending,
      2 => status.isActive,
      _ => status.isTerminal,
    };
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () async => ref.refresh(offersProvider.future),
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppTokens.lg),
              const SectionHeading('Pertukaran', page: true),
              const SizedBox(height: AppTokens.gap),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var index = 0; index < _labels.length; index++)
                    ChoiceChip(
                      label: Text(_labels[index]),
                      selected: _tab == index,
                      onSelected: (_) => setState(() => _tab = index),
                    ),
                ],
              ),
              const SizedBox(height: AppTokens.gap),
              AsyncContent(
                value: ref.watch(offersProvider),
                onRetry: () => ref.invalidate(offersProvider),
                loadingLabel: 'Memuat pertukaran',
                data: (all) => OfferTimeBoundary(
                  offers: all,
                  builder: (now) {
                    final viewer = ref.watch(viewerIdProvider);
                    final offers = all
                        .where((offer) => _matches(offer, viewer, now))
                        .toList();
                    if (offers.isEmpty) {
                      return EmptyState(
                        icon: Icons.swap_horiz_rounded,
                        title: 'Belum ada pertukaran di sini',
                        message: switch (_tab) {
                          0 =>
                            'Penawaran untuk barang Anda akan muncul di sini.',
                          1 => 'Pantau penawaran yang Anda kirim di sini.',
                          2 => 'Pertukaran yang sedang berlangsung akan muncul di sini.',
                          _ => 'Lihat pertukaran dan penawaran yang telah berakhir di sini.',
                        },
                        action: OutlinedButton(
                          onPressed: () => context.go('/explore'),
                          child: const Text('Jelajahi barang'),
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final offer in offers)
                          _OfferTile(
                            offer: offer.forDisplay(now),
                            viewer: viewer,
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    ),
  );
}

class _OfferTile extends StatelessWidget {
  const _OfferTile({required this.offer, required this.viewer});
  final SwapOffer offer;
  final String viewer;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppTokens.md),
    child: Card(
      child: InkWell(
        onTap: () => context.push('/swaps/${offer.id}'),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.gap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppTokens.md,
                runSpacing: AppTokens.xs,
                children: [
                  StatusChip(offer.statusLabel, tone: offer.statusTone),
                  Text(
                    displayDate(offer.createdAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.md),
              ExchangePair.forOffer(offer: offer, viewer: viewer),
              const SizedBox(height: AppTokens.md),
              Text(
                'Dengan ${offer.partnerName(viewer)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (offer.status == SwapStatus.pending) ...[
                const SizedBox(height: AppTokens.xs),
                Text(
                  'Berlaku hingga ${displayDate(offer.expiresAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: AppTokens.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      switch (offer.status) {
                        SwapStatus.pending when viewer == offer.recipientId =>
                          'Tinjau penawaran',
                        SwapStatus.pending => 'Lihat penawaran',
                        _ => 'Lihat pertukaran',
                      },
                      style: const TextStyle(
                        color: AppTokens.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppTokens.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
