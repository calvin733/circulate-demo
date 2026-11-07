import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../domain/swap_offer.dart';

class ExchangePair extends StatelessWidget {
  const ExchangePair({super.key, this.given, required this.received});

  factory ExchangePair.forOffer({
    Key? key,
    required SwapOffer offer,
    required String viewer,
  }) {
    final isRequester = viewer == offer.requesterId;
    final offered = offer.offeredHistory.title;
    final requested = offer.requestedHistory.title;
    return ExchangePair(
      key: key,
      given: isRequester ? offered : requested,
      received: isRequester ? requested : offered,
    );
  }

  final String? given;
  final String received;

  @override
  Widget build(BuildContext context) {
    final give = _PairSide(label: 'Anda memberi', title: given);
    final receive = _PairSide(
      label: 'Anda menerima',
      title: received,
      incoming: true,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
        if (constraints.maxWidth < 320 * textScale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              give,
              const SizedBox(height: AppTokens.sm),
              receive,
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: give),
              const SizedBox(width: AppTokens.sm),
              Expanded(child: receive),
            ],
          ),
        );
      },
    );
  }
}

class _PairSide extends StatelessWidget {
  const _PairSide({
    required this.label,
    required this.title,
    this.incoming = false,
  });
  final String label;
  final String? title;
  final bool incoming;

  @override
  Widget build(BuildContext context) {
    final styles = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTokens.md),
        decoration: BoxDecoration(
          color: incoming ? AppTokens.sage : AppTokens.paper,
          border: Border.all(color: incoming ? AppTokens.sage : AppTokens.line),
          borderRadius: BorderRadius.circular(AppTokens.controlRadius),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: styles.labelMedium?.copyWith(color: AppTokens.primary),
            ),
            const SizedBox(height: AppTokens.xs),
            Text(
              title ?? 'Pilih barang Anda',
              style: styles.titleMedium?.copyWith(
                color: title == null ? AppTokens.muted : AppTokens.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension SwapPresentation on SwapOffer {
  String partnerName(String viewer) => viewer == requesterId
      ? requestedHistory.ownerName
      : offeredHistory.ownerName;

  NoticeTone get statusTone => switch (status) {
    SwapStatus.pending || SwapStatus.awaitingConfirmation => NoticeTone.info,
    SwapStatus.accepted || SwapStatus.completed => NoticeTone.success,
    SwapStatus.disputed ||
    SwapStatus.cancellationRequested => NoticeTone.warning,
    _ => NoticeTone.neutral,
  };
}
