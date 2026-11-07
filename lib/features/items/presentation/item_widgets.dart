import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../../core/widgets/storage_photo.dart';
import '../domain/item.dart';

IconData categoryIcon(ItemCategory category) => switch (category) {
  ItemCategory.books => Icons.menu_book_rounded,
  ItemCategory.electronics => Icons.headphones_rounded,
  ItemCategory.home => Icons.chair_alt_rounded,
  ItemCategory.hobbies => Icons.palette_outlined,
  ItemCategory.fashion => Icons.shopping_bag_outlined,
  ItemCategory.sports => Icons.sports_tennis_rounded,
};

class ItemPhotoView extends StatelessWidget {
  const ItemPhotoView({
    super.key,
    required this.url,
    required this.height,
    this.path,
    this.bucket = 'item-photos',
  });
  final String url;
  final double height;
  final String? path;
  final String bucket;
  @override
  Widget build(BuildContext context) {
    return StoragePhoto(url: url, height: height, path: path, bucket: bucket);
  }
}

class ItemGallery extends StatefulWidget {
  const ItemGallery({super.key, required this.item});
  final Item item;
  @override
  State<ItemGallery> createState() => _ItemGalleryState();
}

class _ItemGalleryState extends State<ItemGallery> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(
        page,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = (constraints.maxWidth * .78).clamp(200.0, 404.0);
      final count = widget.item.imageUrls.length;
      final current = count == 0 ? 0 : _index.clamp(0, count - 1);
      return Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTokens.cardRadius),
            child: SizedBox(
              height: height,
              child: count == 0
                  ? ItemArtwork(item: widget.item, height: height)
                  : PageView(
                      controller: _pages,
                      onPageChanged: (v) => setState(() => _index = v),
                      children: widget.item.imageUrls.indexed
                          .map(
                            (entry) => Semantics(
                              image: true,
                              label: 'Foto ${widget.item.title}',
                              child: ItemPhotoView(
                                url: entry.$2,
                                height: height,
                                path: entry.$1 < widget.item.photoPaths.length
                                    ? widget.item.photoPaths[entry.$1]
                                    : null,
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
          ),
          if (count > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Foto sebelumnya',
                  onPressed: current > 0 ? () => _goTo(current - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Flexible(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      'Foto ${current + 1} dari $count',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Foto berikutnya',
                  onPressed: current < count - 1
                      ? () => _goTo(current + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
        ],
      );
    },
  );
}

class ItemArtwork extends ConsumerWidget {
  const ItemArtwork({super.key, required this.item, this.height = 154});
  final Item item;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (item.imageUrls.isNotEmpty) {
      return Semantics(
        label: 'Foto ${item.title}',
        image: true,
        child: ItemPhotoView(
          url: item.imageUrls.first,
          height: height,
          path: item.photoPaths.firstOrNull,
        ),
      );
    }
    final demo = ref.watch(isDemoModeProvider);
    return Semantics(
      label: demo
          ? 'Ilustrasi demo ${item.title}'
          : 'Belum ada foto ${item.title}',
      image: true,
      child: Container(
        height: height,
        width: double.infinity,
        color: AppTokens.quiet,
        child: ExcludeSemantics(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    categoryIcon(item.category),
                    size: (height * .3).clamp(18.0, 58.0),
                    color: AppTokens.primary,
                  ),
                  if (height >= 112) ...[
                    const SizedBox(height: AppTokens.sm),
                    Text(
                      demo ? 'Ilustrasi demo' : 'Belum ada foto',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AppTokens.muted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

NoticeTone itemStatusTone(ItemStatus status) => switch (status) {
  ItemStatus.available => NoticeTone.success,
  ItemStatus.reserved => NoticeTone.warning,
  ItemStatus.exchanged => NoticeTone.info,
  _ => NoticeTone.neutral,
};

class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.item, this.showStatus = false});
  final Item item;
  final bool showStatus;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: () => context.push('/items/${item.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) =>
                ItemArtwork(item: item, height: constraints.maxWidth * .75),
          ),
          Padding(
            padding: const EdgeInsets.all(AppTokens.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppTokens.xs),
                Text(
                  item.condition.label,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: AppTokens.primary),
                ),
                if (item.city.trim().isNotEmpty) ...[
                  const SizedBox(height: AppTokens.xs),
                  Text(
                    item.city,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AppTokens.muted),
                  ),
                ],
                if (showStatus || item.status != ItemStatus.available) ...[
                  const SizedBox(height: AppTokens.sm),
                  StatusChip(
                    item.visible ? item.status.label : 'Disembunyikan',
                    tone: item.visible
                        ? itemStatusTone(item.status)
                        : NoticeTone.warning,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Wrap instead of fixed-height grid tiles so large system text never clips.
class ItemGrid extends StatelessWidget {
  const ItemGrid({super.key, required this.items, this.showStatus = false});
  final List<Item> items;
  final bool showStatus;

  @override
  Widget build(BuildContext context) => _CatalogGrid(
    children: [
      for (final item in items) ItemCard(item: item, showStatus: showStatus),
    ],
  );
}

class ItemGridLoading extends StatelessWidget {
  const ItemGridLoading({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const LoadingState(label: 'Memuat barang'),
      ExcludeSemantics(
        child: _CatalogGrid(
          children: [
            for (var i = 0; i < 4; i++)
              const Card(
                child: Column(
                  children: [
                    AspectRatio(
                      aspectRatio: 4 / 3,
                      child: ColoredBox(color: AppTokens.quiet),
                    ),
                    SizedBox(height: 76),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _CatalogGrid extends StatelessWidget {
  const _CatalogGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final minWidth = scale > 1.4 ? 270.0 : 148.0;
      final columns =
          ((constraints.maxWidth + AppTokens.md) / (minWidth + AppTokens.md))
              .floor()
              .clamp(1, 4);
      final width =
          (constraints.maxWidth - (columns - 1) * AppTokens.md) / columns;
      return Wrap(
        spacing: AppTokens.md,
        runSpacing: AppTokens.gap,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}
