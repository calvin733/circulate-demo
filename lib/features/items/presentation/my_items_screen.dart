import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../application/item_providers.dart';
import 'item_widgets.dart';

class MyItemsScreen extends ConsumerWidget {
  const MyItemsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    children: [
      ContentWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppTokens.gap),
            const SectionHeading('Barang saya', page: true),
            const SizedBox(height: AppTokens.sm),
            const Text(
              'Kelola draf dan barang yang Anda tawarkan untuk ditukar.',
              style: TextStyle(color: AppTokens.muted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.push('/items/new'),
              icon: const Icon(Icons.add),
              label: const Text('Tambah barang'),
            ),
            const SizedBox(height: 20),
            AsyncContent(
              value: ref.watch(myItemsProvider),
              loadingLabel: 'Memuat barang Anda',
              onRetry: () => ref.invalidate(myItemsProvider),
              data: (items) => items.isEmpty
                  ? const EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: 'Belum ada barang',
                      message: 'Pilih Tambah barang untuk menyimpan draf pertama Anda.',
                    )
                  : ItemGrid(items: items, showStatus: true),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ],
  );
}
