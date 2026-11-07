import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/app_exception.dart';
import '../theme/app_theme.dart';

class ContentWidth extends StatelessWidget {
  const ContentWidth({
    super.key,
    required this.child,
    this.padding = true,
    this.maxWidth = AppTokens.maxWidth,
  });
  final Widget child;
  final bool padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: padding
              ? MediaQuery.sizeOf(context).width >= 600
                    ? AppTokens.lg
                    : AppTokens.gutter
              : 0,
        ),
        child: child,
      ),
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.page = false});
  final String title;
  final bool page;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      title,
      style: page
          ? Theme.of(context).textTheme.headlineMedium
          : Theme.of(context).textTheme.titleLarge,
    ),
  );
}

class ActionBar extends StatelessWidget {
  const ActionBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: AppTokens.surface,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTokens.line)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.symmetric(vertical: AppTokens.md),
        child: ContentWidth(
          maxWidth: AppTokens.formWidth,
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    ),
  );
}

class AsyncContent<T> extends StatelessWidget {
  const AsyncContent({
    super.key,
    required this.value,
    required this.data,
    required this.onRetry,
    this.loadingLabel = 'Memuat data',
    this.loading,
  });
  final AsyncValue<T> value;
  final Widget Function(T) data;
  final VoidCallback onRetry;
  final String loadingLabel;
  final Widget? loading;

  @override
  Widget build(BuildContext context) => value.when(
    data: data,
    loading: () => loading ?? LoadingState(label: loadingLabel),
    error: (error, stack) => EmptyState(
      icon: Icons.wifi_off_rounded,
      title: 'Belum bisa memuat data',
      message: friendlyError(error),
      action: OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('Coba lagi'),
      ),
    ),
  );
}

class LoadingState extends StatelessWidget {
  const LoadingState({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.all(AppTokens.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppTokens.md),
          LinearProgressIndicator(semanticsLabel: label),
        ],
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppTokens.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28, color: AppTokens.primary),
          const SizedBox(height: AppTokens.gap),
          SectionHeading(title),
          const SizedBox(height: AppTokens.sm),
          Text(message, style: const TextStyle(color: AppTokens.muted)),
          if (action != null) ...[
            const SizedBox(height: AppTokens.gap),
            action!,
          ],
        ],
      ),
    ),
  );
}

enum NoticeTone { neutral, info, success, warning, error }

(Color, Color) _toneColors(NoticeTone tone) => switch (tone) {
  NoticeTone.neutral => (AppTokens.quiet, AppTokens.ink),
  NoticeTone.info => (AppTokens.infoSurface, AppTokens.info),
  NoticeTone.success => (AppTokens.sage, AppTokens.primary),
  NoticeTone.warning => (AppTokens.warningSurface, AppTokens.warning),
  NoticeTone.error => (AppTokens.errorSurface, AppTokens.error),
};

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.tone = NoticeTone.neutral});
  final String label;
  final NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _toneColors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: foreground),
      ),
    );
  }
}

class InfoPanel extends StatelessWidget {
  const InfoPanel({
    super.key,
    required this.text,
    this.icon,
    this.tone = NoticeTone.info,
    this.live = false,
  });
  final String text;
  final IconData? icon;
  final NoticeTone tone;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _toneColors(tone);
    final symbol =
        icon ??
        switch (tone) {
          NoticeTone.error => Icons.error_outline,
          NoticeTone.warning => Icons.warning_amber_outlined,
          NoticeTone.success => Icons.check_circle_outline,
          _ => Icons.info_outline,
        };
    return Semantics(
      liveRegion: live,
      child: Container(
        padding: const EdgeInsets.all(AppTokens.gap),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppTokens.controlRadius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(symbol, size: 20, color: foreground),
            const SizedBox(width: AppTokens.md),
            Expanded(
              child: Text(text, style: TextStyle(color: foreground)),
            ),
          ],
        ),
      ),
    );
  }
}

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

String displayDate(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} · ${two(local.hour)}:${two(local.minute)}';
}
