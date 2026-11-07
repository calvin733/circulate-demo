import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/swap_offer.dart';

/// A single foreground-view timer refreshes labels at the next offer deadline.
/// The server still decides whether an action is valid.
class OfferTimeBoundary extends StatefulWidget {
  const OfferTimeBoundary({
    super.key,
    required this.offers,
    required this.builder,
  });
  final List<SwapOffer> offers;
  final Widget Function(DateTime now) builder;
  @override
  State<OfferTimeBoundary> createState() => _OfferTimeBoundaryState();
}

class _OfferTimeBoundaryState extends State<OfferTimeBoundary> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant OfferTimeBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final now = DateTime.now();
    final deadlines =
        widget.offers
            .where(
              (o) => o.status == SwapStatus.pending && o.expiresAt.isAfter(now),
            )
            .map((o) => o.expiresAt)
            .toList()
          ..sort();
    if (deadlines.isNotEmpty) {
      _timer = Timer(
        deadlines.first.difference(now) + const Duration(milliseconds: 20),
        () {
          if (!mounted) return;
          setState(() {});
          _schedule();
        },
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(DateTime.now());
}
