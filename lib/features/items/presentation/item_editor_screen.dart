import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../swaps/application/swap_providers.dart';
import '../application/photo_processor.dart';
import '../domain/item.dart';
import '../domain/item_draft.dart';
import 'item_widgets.dart';

class ItemEditorScreen extends ConsumerStatefulWidget {
  const ItemEditorScreen({super.key, this.itemId});
  final String? itemId;
  @override
  ConsumerState<ItemEditorScreen> createState() => _ItemEditorScreenState();
}

class _ItemEditorScreenState extends ConsumerState<ItemEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _feedback = GlobalKey();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _city = TextEditingController();
  final _preferences = TextEditingController();
  final _picker = ImagePicker();
  final List<({Uint8List bytes, String key})> _pending = [];
  final _newId = const Uuid().v4();
  ItemCategory _category = ItemCategory.books;
  ItemCondition _condition = ItemCondition.good;
  Item? _item;
  bool _loading = true;
  String? _progress;
  bool get _busy => _progress != null;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (widget.itemId != null) {
        final item = await ref
            .read(itemRepositoryProvider)
            .find(widget.itemId!);
        if (!mounted) return;
        if (item.ownerId != ref.read(viewerIdProvider)) {
          throw const AppException('NOT_OWNER', 'Barang ini bukan milik Anda.');
        }
        _item = item;
        _title.text = item.title;
        _description.text = item.description;
        _city.text = item.city;
        _preferences.text = item.preferences;
        _category = item.category;
        _condition = item.condition;
      }
      // Android can reclaim the activity while its photo picker is open.
      // Recovered files remain local until the user explicitly saves this form.
      final lost = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? await _picker.retrieveLostData()
          : null;
      if (lost?.files != null) {
        await _prepare(lost!.files!);
        _notice = 'Foto yang dipilih sebelumnya dipulihkan. Periksa barang tujuan sebelum menyimpan.';
      } else if (lost?.exception != null) {
        _error = 'Foto sebelumnya belum dapat dipulihkan. Silakan pilih ulang.';
      }
    } catch (error) {
      if (mounted) _error = friendlyError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _city.dispose();
    _preferences.dispose();
    super.dispose();
  }

  Future<void> _prepare(List<XFile> files) async {
    for (final file in files) {
      if ((_item?.photos.length ?? 0) + _pending.length >= 5) break;
      if (await file.length() > 20 * 1024 * 1024) {
        throw const AppException(
          'PHOTO_TOO_LARGE',
          'Pilih foto di bawah 20 MB.',
        );
      }
      final bytes = await prepareItemPhoto(await file.readAsBytes());
      if (!mounted) return;
      setState(() => _pending.add((bytes: bytes, key: const Uuid().v4())));
    }
  }

  Future<void> _run(
    Future<void> Function() operation, {
    String progress = 'Menyimpan…',
  }) async {
    if (_busy) return;
    setState(() {
      _progress = progress;
      _error = null;
      _notice = null;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) {
        refreshSwapViews(ref);
        setState(() => _progress = null);
        if (_error != null || _notice != null) {
          _reveal(() => _feedback.currentContext);
        }
      }
    }
  }

  Future<void> _save({bool publish = false}) async {
    final invalidFields = _form.currentState!.validateGranularly();
    if (invalidFields.isNotEmpty) {
      _reveal(() => invalidFields.first.context);
      return;
    }
    await _run(
      () async {
        final repository = ref.read(itemRepositoryProvider);
        final draft = ItemDraft(
          id: _item?.id ?? _newId,
          expectedRevision: _item?.revision ?? 0,
          title: _title.text.trim(),
          description: _description.text.trim(),
          category: _category,
          condition: _condition,
          city: _city.text.trim(),
          preferences: _preferences.text.trim(),
        );
        final saved = _item != null && draft.matches(_item!)
            ? await repository.find(_item!.id)
            : await repository.saveDraft(draft);
        if (!mounted) return;
        setState(() => _item = saved);
        while (_pending.isNotEmpty) {
          final photo = _pending.first;
          final updated = await repository.addPhoto(
            _item!,
            photo.bytes,
            requestKey: photo.key,
          );
          if (!mounted) return;
          setState(() {
            _item = updated;
            _pending.removeAt(0);
          });
        }
        if (publish) {
          final updated = await repository.setListingState(
            _item!,
            publish: true,
          );
          if (!mounted) return;
          setState(() => _item = updated);
        }
        if (mounted) {
          setState(
            () => _notice = publish
                ? 'Barang tersedia di Jelajah.'
                : 'Perubahan barang tersimpan.',
          );
        }
      },
      progress: _pending.isEmpty ? 'Menyimpan…' : 'Menyimpan barang dan foto…',
    );
  }

  void _reveal(BuildContext? Function() locate) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = locate();
      if (target != null && target.mounted) {
        Scrollable.ensureVisible(target, alignment: .1);
      }
    });
  }

  bool get _locked =>
      _item != null &&
      (!_item!.visible ||
          _item!.status == ItemStatus.reserved ||
          _item!.status == ItemStatus.exchanged);

  @override
  Widget build(BuildContext context) {
    final canEdit = !_locked && (_item != null || widget.itemId == null);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.itemId == null ? 'Tambah barang' : 'Kelola barang'),
        leading: BackButton(
          onPressed: _busy ? null : () => context.go('/my-items'),
        ),
      ),
      body: _loading
          ? const LoadingState(label: 'Memuat isian barang')
          : SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: AppTokens.lg),
                children: [
                  ContentWidth(
                    maxWidth: AppTokens.formWidth,
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_item case final item?) ...[
                            Align(
                              alignment: Alignment.centerLeft,
                              child: StatusChip(
                                item.status.label,
                                tone: itemStatusTone(item.status),
                              ),
                            ),
                            const SizedBox(height: AppTokens.gap),
                          ],
                          if (_error != null || _notice != null) ...[
                            InfoPanel(
                              key: _feedback,
                              text: _error ?? _notice!,
                              tone: _error == null
                                  ? NoticeTone.success
                                  : NoticeTone.error,
                              live: true,
                            ),
                            if (_error != null && _item != null)
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _run(() async {
                                        final current = await ref
                                            .read(itemRepositoryProvider)
                                            .find(_item!.id);
                                        if (mounted) {
                                          setState(() {
                                            _item = current;
                                            _notice = 'Status terbaru dimuat. Isian dan foto pilihan tetap tersimpan.';
                                          });
                                        }
                                      }, progress: 'Memuat status…'),
                                child: const Text(
                                  'Muat ulang status, pertahankan isian',
                                ),
                              ),
                            const SizedBox(height: AppTokens.gap),
                          ],
                          if (_locked)
                            const InfoPanel(
                              text: 'Barang yang direservasi, ditukar, atau disembunyikan tidak dapat diedit.',
                              tone: NoticeTone.warning,
                            ),
                          if (canEdit) ...[
                            _photos(context),
                            const SizedBox(height: AppTokens.lg),
                            const SectionHeading('Informasi barang'),
                            const SizedBox(height: AppTokens.md),
                            _field(_title, 'Nama barang', 5, 80),
                            DropdownButtonFormField<ItemCategory>(
                              initialValue: _category,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Kategori',
                              ),
                              items: [
                                for (final category in ItemCategory.values)
                                  DropdownMenuItem(
                                    value: category,
                                    child: Text(category.label),
                                  ),
                              ],
                              onChanged: _busy
                                  ? null
                                  : (value) =>
                                        setState(() => _category = value!),
                            ),
                            const SizedBox(height: AppTokens.gap),
                            _field(_city, 'Kota', 2, 80),
                            const SizedBox(height: AppTokens.sm),
                            const SectionHeading('Kondisi dan deskripsi'),
                            const SizedBox(height: AppTokens.md),
                            DropdownButtonFormField<ItemCondition>(
                              initialValue: _condition,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Kondisi',
                              ),
                              items: [
                                for (final condition in ItemCondition.values)
                                  DropdownMenuItem(
                                    value: condition,
                                    child: Text(condition.label),
                                  ),
                              ],
                              onChanged: _busy
                                  ? null
                                  : (value) =>
                                        setState(() => _condition = value!),
                            ),
                            const SizedBox(height: AppTokens.gap),
                            _field(
                              _description,
                              'Deskripsi dan kekurangan barang',
                              20,
                              2000,
                              lines: 4,
                            ),
                            _field(
                              _preferences,
                              'Ingin ditukar dengan (opsional)',
                              0,
                              500,
                              lines: 2,
                            ),
                            InfoPanel(
                              text: ref.watch(isDemoModeProvider)
                                  ? 'Barang dan foto demo tersimpan selama sesi ini.'
                                  : 'Mengubah barang yang tampil di Jelajah akan mengakhiri penawaran yang masih menunggu untuk barang tersebut.',
                            ),
                            const SizedBox(height: AppTokens.gap),
                            if (_item?.status != ItemStatus.available)
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => _save(publish: true),
                                child: const Text(
                                  'Simpan dan tampilkan di Jelajah',
                                ),
                              ),
                            if (_item != null &&
                                _item!.status != ItemStatus.archived)
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _run(() async {
                                        final updated = await ref
                                            .read(itemRepositoryProvider)
                                            .setListingState(
                                              _item!,
                                              publish: false,
                                            );
                                        if (mounted) {
                                          setState(() {
                                            _item = updated;
                                            _notice = 'Barang diarsipkan.';
                                          });
                                        }
                                      }),
                                child: const Text('Arsipkan barang'),
                              ),
                          ] else if (!_locked)
                            OutlinedButton(
                              onPressed: () {
                                setState(() => _loading = true);
                                _load();
                              },
                              child: const Text('Muat ulang barang'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: !_loading && canEdit && !keyboardOpen
          ? ActionBar(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_progress case final label?) ...[
                    LinearProgressIndicator(semanticsLabel: label),
                    const SizedBox(height: AppTokens.sm),
                  ],
                  FilledButton(
                    onPressed: _busy ? null : () => _save(),
                    child: Text(
                      _progress ??
                          (_item?.status == ItemStatus.available
                              ? 'Simpan perubahan'
                              : 'Simpan draft'),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget _photos(BuildContext context) {
    final item = _item;
    final photos = item?.photos ?? const <ItemPhoto>[];
    final count = photos.length + _pending.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading('Foto barang · $count/5'),
        const SizedBox(height: AppTokens.xs),
        Text(
          'Gunakan foto barang sendiri. Data lokasi dihapus sebelum unggah.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppTokens.md),
        if (count > 0) ...[
          Card(
            child: Column(
              children: [
                for (final photo in photos)
                  ListTile(
                    leading: _storedPhoto(item!, photo),
                    title: Text('Foto ${photo.position + 1} tersimpan'),
                    trailing: IconButton(
                      tooltip: 'Hapus foto ${photo.position + 1}',
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              final updated = await ref
                                  .read(itemRepositoryProvider)
                                  .removePhoto(_item!, photo);
                              if (mounted) setState(() => _item = updated);
                            }, progress: 'Menghapus foto…'),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                for (final (index, photo) in _pending.indexed)
                  ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(AppTokens.sm),
                      child: Image.memory(
                        photo.bytes,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        excludeFromSemantics: true,
                      ),
                    ),
                    title: const Text('Belum diunggah'),
                    trailing: IconButton(
                      tooltip: 'Hapus foto pilihan ${index + 1}',
                      onPressed: _busy
                          ? null
                          : () => setState(() => _pending.removeAt(index)),
                      icon: const Icon(Icons.close),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.md),
        ],
        if (count < 5)
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _run(() async {
                    final files = await _picker.pickMultiImage(
                      requestFullMetadata: false,
                    );
                    if (mounted) await _prepare(files);
                  }, progress: 'Menyiapkan foto…'),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Pilih foto dari galeri'),
          ),
      ],
    );
  }

  Widget _storedPhoto(Item item, ItemPhoto photo) {
    final index = item.photoPaths.indexOf(photo.path);
    if (index < 0 || index >= item.imageUrls.length) {
      return const Icon(Icons.photo_outlined);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.sm),
      child: SizedBox(
        width: 48,
        height: 48,
        child: ItemPhotoView(
          url: item.imageUrls[index],
          path: photo.path,
          height: 48,
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    int min,
    int max, {
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppTokens.gap),
    child: TextFormField(
      controller: controller,
      enabled: !_busy,
      minLines: lines,
      maxLines: lines,
      maxLength: max,
      decoration: InputDecoration(labelText: label),
      validator: (value) =>
          (value ?? '').trim().length < min || (value ?? '').trim().length > max
          ? 'Isi $min–$max karakter.'
          : null,
    ),
  );
}
