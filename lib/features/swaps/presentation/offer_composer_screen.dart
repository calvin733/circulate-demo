import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../items/application/item_providers.dart';
import '../../items/domain/item.dart';
import '../application/swap_providers.dart';
import 'exchange_pair.dart';

class OfferComposerScreen extends ConsumerStatefulWidget {
  const OfferComposerScreen({super.key, required this.requestedItemId});
  final String requestedItemId;
  @override
  ConsumerState<OfferComposerScreen> createState() =>
      _OfferComposerScreenState();
}

class _OfferComposerScreenState extends ConsumerState<OfferComposerScreen> {
  String? _selected;
  late String _requestKey;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _requestKey = _newKey();
  }

  String _newKey() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Future<void> _submit() async {
    final selected = _selected;
    if (selected == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(swapRepositoryProvider)
          .create(
            actorId: ref.read(viewerIdProvider),
            offeredItemId: selected,
            requestedItemId: widget.requestedItemId,
            requestKey: _requestKey,
          );
      if (!mounted) return;
      refreshSwapViews(ref);
      context.replace('/swaps/$id');
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requested = ref.watch(itemProvider(widget.requestedItemId));
    final items = ref.watch(myItemsProvider);
    final eligible = items.asData?.value
        .where((item) => item.status == ItemStatus.available && item.visible)
        .toList();
    final selected = eligible
        ?.where((item) => item.id == _selected)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajukan pertukaran')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppTokens.lg),
          children: [
            ContentWidth(
              maxWidth: AppTokens.formWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AsyncContent(
                    value: requested,
                    onRetry: () =>
                        ref.invalidate(itemProvider(widget.requestedItemId)),
                    loadingLabel: 'Memuat barang tujuan',
                    data: (item) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeading('Pasangan barang'),
                        const SizedBox(height: AppTokens.sm),
                        ExchangePair(
                          given: selected?.title,
                          received: item.title,
                        ),
                        const SizedBox(height: AppTokens.sm),
                        Text(
                          'Pemilik barang tujuan · ${item.ownerName}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTokens.lg),
                  const SectionHeading('Barang yang Anda tawarkan'),
                  const SizedBox(height: AppTokens.sm),
                  AsyncContent(
                    value: items,
                    onRetry: () => ref.invalidate(myItemsProvider),
                    loadingLabel: 'Memuat barang Anda',
                    data: (_) {
                      final choices = eligible ?? const <Item>[];
                      if (choices.isEmpty) {
                        return EmptyState(
                          icon: Icons.inventory_2_outlined,
                          title: 'Belum ada barang tersedia',
                          message:
                              'Tampilkan barang Anda untuk mengirim penawaran.',
                          action: FilledButton.icon(
                            onPressed: () => context.push('/items/new'),
                            icon: const Icon(Icons.add),
                            label: const Text('Tambah barang'),
                          ),
                        );
                      }
                      return Card(
                        child: Column(
                          children: [
                            for (final (index, item) in choices.indexed) ...[
                              if (index > 0) const Divider(indent: 52),
                              ListTile(
                                key: ValueKey('offer-item-${item.id}'),
                                selected: _selected == item.id,
                                selectedTileColor: AppTokens.sage,
                                leading: Icon(
                                  _selected == item.id
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                ),
                                title: Text(item.title),
                                subtitle: Text(item.condition.label),
                                onTap: _busy
                                    ? null
                                    : () => setState(() {
                                        if (_selected != item.id) {
                                          _requestKey = _newKey();
                                        }
                                        _selected = item.id;
                                        _error = null;
                                      }),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppTokens.gap),
                    InfoPanel(
                      text: _error!,
                      tone: NoticeTone.error,
                      live: true,
                    ),
                  ],
                  if (eligible?.isNotEmpty ?? false) ...[
                    const SizedBox(height: AppTokens.gap),
                    const InfoPanel(
                      text: 'Barang direservasi setelah pemilik menerima penawaran.',
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: (eligible?.isNotEmpty ?? false) && requested.hasValue
          ? ActionBar(
              child: FilledButton(
                onPressed: selected == null || _busy ? null : _submit,
                child: Text(
                  _busy
                      ? 'Mengirim…'
                      : ref.watch(isDemoModeProvider)
                      ? 'Ajukan penawaran demo'
                      : 'Kirim penawaran',
                ),
              ),
            )
          : null,
    );
  }
}
