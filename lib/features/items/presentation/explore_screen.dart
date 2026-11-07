import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../application/item_providers.dart';
import '../domain/item.dart';
import 'item_widgets.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});
  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(itemFilterProvider).query;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _reset() {
    _debounce?.cancel();
    _search.clear();
    ref.read(itemFilterProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(itemFilterProvider);
    final filtered =
        filter.query.trim().isNotEmpty ||
        filter.category != null ||
        filter.condition != null;
    final conditionPicker = DropdownButtonFormField<ItemCondition?>(
      key: ValueKey(filter.condition),
      initialValue: filter.condition,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Kondisi barang'),
      hint: const Text('Semua kondisi'),
      items: [
        const DropdownMenuItem<ItemCondition?>(
          value: null,
          child: Text('Semua kondisi'),
        ),
        for (final condition in ItemCondition.values)
          DropdownMenuItem(value: condition, child: Text(condition.label)),
      ],
      onChanged: (value) =>
          ref.read(itemFilterProvider.notifier).condition(value),
    );
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(exploreItemsProvider.future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppTokens.md),
                TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Cari barang…',
                    labelText: 'Cari barang',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: filtered
                        ? IconButton(
                            tooltip: 'Hapus pencarian dan filter',
                            onPressed: _reset,
                            icon: const Icon(Icons.close),
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () {
                      if (mounted) {
                        ref.read(itemFilterProvider.notifier).query(value);
                      }
                    });
                  },
                ),
                const SizedBox(height: AppTokens.md),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Semua'),
                        selected: filter.category == null,
                        onSelected: (_) => ref
                            .read(itemFilterProvider.notifier)
                            .category(null),
                      ),
                      for (final category in ItemCategory.values)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ChoiceChip(
                            label: Text(category.label),
                            selected: filter.category == category,
                            onSelected: (_) => ref
                                .read(itemFilterProvider.notifier)
                                .category(category),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTokens.lg),
                LayoutBuilder(
                  builder: (context, constraints) {
                    const heading = SectionHeading('Siap ditukar');
                    final largeText =
                        MediaQuery.textScalerOf(context).scale(15) > 18;
                    if (constraints.maxWidth >= 340 && !largeText) {
                      return Row(
                        children: [
                          const Expanded(child: heading),
                          const SizedBox(width: AppTokens.md),
                          SizedBox(width: 176, child: conditionPicker),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        heading,
                        const SizedBox(height: AppTokens.md),
                        conditionPicker,
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppTokens.gap),
                AsyncContent(
                  value: ref.watch(exploreItemsProvider),
                  onRetry: () => ref.invalidate(exploreItemsProvider),
                  loading: const ItemGridLoading(),
                  data: (items) => items.isEmpty
                      ? EmptyState(
                          icon: filtered
                              ? Icons.search_off_rounded
                              : Icons.inventory_2_outlined,
                          title: filtered
                              ? 'Belum ada yang cocok'
                              : 'Belum ada barang siap ditukar',
                          message: filtered
                              ? 'Coba kata kunci lain atau hapus filter.'
                              : 'Barang dari anggota akan muncul di sini setelah ditampilkan.',
                          action: filtered
                              ? OutlinedButton(
                                  onPressed: _reset,
                                  child: const Text('Reset filter'),
                                )
                              : FilledButton(
                                  onPressed: () => context.push('/items/new'),
                                  child: const Text('Tambah barang'),
                                ),
                        )
                      : ItemGrid(items: items),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
