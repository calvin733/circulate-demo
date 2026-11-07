import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../safety/presentation/safety_widgets.dart';
import '../application/item_providers.dart';
import '../domain/item.dart';
import 'item_widgets.dart';

class ItemDetailScreen extends ConsumerWidget {
  const ItemDetailScreen({super.key, required this.itemId});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: const Text('Detail barang'),
      leading: BackButton(
        onPressed: () =>
            context.canPop() ? context.pop() : context.go('/explore'),
      ),
    ),
    body: SafeArea(
      top: false,
      bottom: false,
      child: AsyncContent(
        value: ref.watch(itemProvider(itemId)),
        loadingLabel: 'Memuat detail barang',
        onRetry: () => ref.invalidate(itemProvider(itemId)),
        data: (item) {
          final isOwner = item.ownerId == ref.watch(viewerIdProvider);
          final canOffer = item.status == ItemStatus.available;
          final demo = ref.watch(isDemoModeProvider);
          return Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    ContentWidth(
                      maxWidth: 720,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: AppTokens.sm),
                          ItemGallery(item: item),
                          const SizedBox(height: AppTokens.lg),
                          SectionHeading(item.title, page: true),
                          const SizedBox(height: AppTokens.md),
                          Wrap(
                            spacing: AppTokens.sm,
                            runSpacing: AppTokens.sm,
                            children: [
                              StatusChip(
                                item.status.label,
                                tone: itemStatusTone(item.status),
                              ),
                              StatusChip(item.condition.label),
                            ],
                          ),
                          if (item.city.trim().isNotEmpty) ...[
                            const SizedBox(height: AppTokens.md),
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 20,
                                  color: AppTokens.muted,
                                ),
                                const SizedBox(width: AppTokens.sm),
                                Expanded(
                                  child: Text(
                                    item.city,
                                    style: const TextStyle(
                                      color: AppTokens.muted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: AppTokens.lg),
                          const Divider(),
                          const SizedBox(height: AppTokens.lg),
                          const SectionHeading('Tentang barang'),
                          const SizedBox(height: AppTokens.sm),
                          Text(item.description),
                          if (item.preferences.trim().isNotEmpty) ...[
                            const SizedBox(height: AppTokens.lg),
                            const SectionHeading('Ingin ditukar dengan'),
                            const SizedBox(height: AppTokens.sm),
                            Text(item.preferences),
                          ],
                          const SizedBox(height: AppTokens.lg),
                          const SectionHeading('Ditawarkan oleh'),
                          const SizedBox(height: AppTokens.sm),
                          Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: AppTokens.sage,
                                foregroundColor: AppTokens.primary,
                                child: Icon(Icons.person_outline),
                              ),
                              title: Text(item.ownerName),
                              subtitle: Text(
                                demo ? 'Anggota contoh' : 'Anggota Circulate',
                              ),
                            ),
                          ),
                          const SizedBox(height: AppTokens.gap),
                          const InfoPanel(
                            icon: Icons.shield_outlined,
                            text: 'Bertemu di tempat publik. Periksa kondisi barang sebelum mengonfirmasi penerimaan.',
                          ),
                          if (!isOwner && !canOffer) ...[
                            const SizedBox(height: AppTokens.md),
                            const InfoPanel(
                              text: 'Barang ini sedang tidak menerima penawaran baru.',
                              tone: NoticeTone.warning,
                            ),
                          ],
                          if (!isOwner) ...[
                            const SizedBox(height: AppTokens.gap),
                            SafetyActions(
                              memberId: item.ownerId,
                              memberName: item.ownerName,
                              itemId: item.id,
                            ),
                          ],
                          const SizedBox(height: AppTokens.lg),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (isOwner || canOffer)
                ActionBar(
                  child: FilledButton.icon(
                    onPressed: () => context.push(
                      isOwner ? '/items/$itemId/edit' : '/items/$itemId/offer',
                    ),
                    icon: Icon(
                      isOwner ? Icons.edit_outlined : Icons.swap_horiz_rounded,
                    ),
                    label: Text(
                      isOwner ? 'Kelola barang' : 'Ajukan pertukaran',
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
