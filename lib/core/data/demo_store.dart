import '../../features/items/domain/item.dart';
import '../../features/items/domain/item_draft.dart';

import 'dart:convert';
import 'dart:typed_data';

import '../../features/items/domain/item_repository.dart';
import '../../features/safety/domain/safety_repository.dart';
import '../../features/profile/domain/member_profile.dart';
import '../../features/swaps/domain/swap_offer.dart';
import '../../features/swaps/domain/swap_repository.dart';
import '../../features/swaps/domain/swap_rules.dart';
import '../errors/app_exception.dart';

/// An explicit, single-process preview. This never represents cloud security.
class DemoStore
    implements
        ItemRepository,
        SwapRepository,
        ProfileRepository,
        SafetyRepository {
  DemoStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    _seed();
  }

  static const viewerId = 'demo-ayu';
  final DateTime Function() _clock;
  final Map<String, Item> _items = {};
  final Set<String> _blocks = {};
  final Map<String, SwapOffer> _offers = {};
  final Map<String, ({String payload, String result})> _requests = {};
  MemberProfile _profile = const MemberProfile(
    id: viewerId,
    displayName: 'Ayu Pratiwi',
    city: 'Tangerang',
    bio: 'Senang membaca dan memberi kesempatan kedua untuk barang yang masih baik.',
  );

  void _seed() {
    const items = [
      Item(
        id: 'book',
        ownerId: 'demo-nadia',
        ownerName: 'Nadia',
        title: 'Atomic Habits',
        description: 'Buku pengembangan diri edisi Bahasa Indonesia. Halaman lengkap, bersih, dengan sedikit lipatan di sampul.',
        category: ItemCategory.books,
        condition: ItemCondition.good,
        city: 'Tangerang',
        preferences: 'Tanaman kecil atau buku nonfiksi lain.',
      ),
      Item(
        id: 'coffee',
        ownerId: 'demo-raka',
        ownerName: 'Raka',
        title: 'Coffee dripper V60',
        description: 'Dripper keramik ukuran 02. Jarang dipakai, tidak retak, sudah dicuci bersih. Cocok untuk mulai membuat kopi di rumah.',
        category: ItemCategory.home,
        condition: ItemCondition.likeNew,
        city: 'Jakarta Barat',
        preferences: 'Peralatan masak kecil atau tanaman hias.',
      ),
      Item(
        id: 'headphones',
        ownerId: 'demo-bima',
        ownerName: 'Bima',
        title: 'Headphone kabel',
        description: 'Headphone over-ear dengan kabel 3,5 mm. Kedua sisi berfungsi. Bantalan sedikit mengelupas, dapat diganti.',
        category: ItemCategory.electronics,
        condition: ItemCondition.fair,
        city: 'Tangerang Selatan',
        preferences: 'Buku, alat gambar, atau barang hobi.',
      ),
      Item(
        id: 'bag',
        ownerId: 'demo-dian',
        ownerName: 'Dian',
        title: 'Tas kanvas harian',
        description: 'Tas kanvas warna natural. Jahitan dan resleting baik, muat laptop kecil. Ada noda kecil di bagian dalam.',
        category: ItemCategory.fashion,
        condition: ItemCondition.good,
        city: 'Tangerang',
        preferences: 'Buku atau aksesori rumah.',
      ),
      Item(
        id: 'racket',
        ownerId: 'demo-laras',
        ownerName: 'Laras',
        title: 'Raket badminton',
        description: 'Raket latihan ringan, grip baru diganti. Senar masih utuh. Cocok untuk bermain santai di akhir pekan.',
        category: ItemCategory.sports,
        condition: ItemCondition.good,
        city: 'Jakarta Barat',
        preferences: 'Peralatan olahraga ringan atau buku.',
      ),
      Item(
        id: 'paint',
        ownerId: 'demo-surya',
        ownerName: 'Surya',
        title: 'Set cat air 12 warna',
        description: 'Set cat air untuk pemula. Beberapa warna sudah dipakai sedikit. Kotak masih baik, kuas tidak termasuk.',
        category: ItemCategory.hobbies,
        condition: ItemCondition.good,
        city: 'Tangerang',
        preferences: 'Alat tulis atau buku gambar.',
      ),
      Item(
        id: 'plant',
        ownerId: viewerId,
        ownerName: 'Ayu Pratiwi',
        title: 'Monstera mini',
        description: 'Tanaman sehat dengan pot terakota kecil. Sudah berakar dan mudah dirawat di area yang cukup cahaya.',
        category: ItemCategory.home,
        condition: ItemCondition.good,
        city: 'Tangerang',
        preferences: 'Buku bacaan atau alat kopi.',
      ),
      Item(
        id: 'lamp',
        ownerId: viewerId,
        ownerName: 'Ayu Pratiwi',
        title: 'Lampu meja belajar',
        description: 'Lampu meja dengan cahaya hangat. Sakelar dan kabel baik. Bohlam termasuk, ada goresan kecil di kaki lampu.',
        category: ItemCategory.home,
        condition: ItemCondition.good,
        city: 'Tangerang',
        preferences: 'Buku nonfiksi atau novel.',
      ),
      Item(
        id: 'yoga',
        ownerId: viewerId,
        ownerName: 'Ayu Pratiwi',
        title: 'Matras yoga',
        description: 'Matras yoga bersih dan tidak sobek. Sudah disepakati untuk pertukaran demo dengan buku memasak.',
        category: ItemCategory.sports,
        condition: ItemCondition.good,
        city: 'Tangerang',
        preferences: 'Buku memasak.',
        status: ItemStatus.reserved,
      ),
      Item(
        id: 'cookbook',
        ownerId: 'demo-sari',
        ownerName: 'Sari',
        title: 'Buku masakan rumahan',
        description: 'Kumpulan resep masakan sehari-hari, halaman lengkap dan bersih. Barang ini berada dalam transaksi demo aktif.',
        category: ItemCategory.books,
        condition: ItemCondition.good,
        city: 'Tangerang',
        preferences: 'Peralatan olahraga.',
        status: ItemStatus.reserved,
      ),
    ];
    _items.addEntries(items.map((item) => MapEntry(item.id, item)));
    final now = _clock();
    for (final offer in [
      SwapOffer(
        id: 'incoming',
        requesterId: 'demo-nadia',
        recipientId: viewerId,
        offeredItemId: 'book',
        requestedItemId: 'lamp',
        createdAt: now.subtract(const Duration(hours: 3)),
        expiresAt: now.add(const Duration(days: 6)),
        note: 'Tertarik menukar buku dengan lampu belajar Anda.',
        events: [
          SwapEvent(
            'Nadia mengajukan penawaran',
            now.subtract(const Duration(hours: 3)),
          ),
        ],
      ),
      SwapOffer(
        id: 'outgoing',
        requesterId: viewerId,
        recipientId: 'demo-raka',
        offeredItemId: 'plant',
        requestedItemId: 'coffee',
        createdAt: now.subtract(const Duration(hours: 1)),
        expiresAt: now.add(const Duration(days: 7)),
        events: [
          SwapEvent(
            'Anda mengajukan penawaran',
            now.subtract(const Duration(hours: 1)),
          ),
        ],
      ),
      SwapOffer(
        id: 'active',
        requesterId: viewerId,
        recipientId: 'demo-sari',
        offeredItemId: 'yoga',
        requestedItemId: 'cookbook',
        createdAt: now.subtract(const Duration(days: 2)),
        expiresAt: now.add(const Duration(days: 5)),
        status: SwapStatus.accepted,
        meetup: Meetup(
          location: 'Area duduk perpustakaan kota (data contoh)',
          scheduledAt: now.subtract(const Duration(hours: 1)),
          proposedBy: 'demo-sari',
          approvedBy: viewerId,
        ),
        events: [
          SwapEvent('Penawaran dikirim', now.subtract(const Duration(days: 2))),
          SwapEvent(
            'Sari menerima · kedua barang direservasi',
            now.subtract(const Duration(days: 1)),
          ),
          SwapEvent(
            'Pertemuan disepakati oleh kedua pihak',
            now.subtract(const Duration(hours: 2)),
          ),
        ],
      ),
    ]) {
      _offers[offer.id] = offer.copyWith(
        offeredSummary: SwapItemSummary.fromItem(_items[offer.offeredItemId]!),
        requestedSummary: SwapItemSummary.fromItem(
          _items[offer.requestedItemId]!,
        ),
      );
    }
  }

  @override
  Future<List<Item>> search(ItemFilter filter) async =>
      List.unmodifiable(_items.values.where(filter.matches));

  @override
  Future<List<Item>> ownedBy(String ownerId) async =>
      List.unmodifiable(_items.values.where((item) => item.ownerId == ownerId));

  @override
  Future<Item> find(String id) async => _item(id);

  Item _item(String id) =>
      _items[id] ??
      (throw const AppException('NOT_FOUND', 'Barang tidak tersedia.'));

  @override
  Future<List<SwapOffer>> listFor(String actorId) async => List.unmodifiable(
    _offers.values
        .where((offer) => offer.involves(actorId))
        .map((o) => o.forDisplay(_clock())),
  );

  @override
  Future<SwapOffer> findOffer(String id, String actorId) async {
    final offer = _offers[id];
    if (offer == null || !offer.involves(actorId)) {
      throw const AppException('NOT_FOUND', 'Pertukaran tidak tersedia.');
    }
    return offer;
  }

  @override
  Future<String> create({
    required String actorId,
    required String offeredItemId,
    required String requestedItemId,
    required String requestKey,
  }) async {
    if (requestKey.trim().isEmpty) {
      throw const AppException('REQUEST_KEY_REQUIRED', 'Coba ajukan kembali.');
    }
    final payload = '$offeredItemId|$requestedItemId';
    final requestId = '$actorId|$requestKey';
    final previous = _requests[requestId];
    if (previous != null) {
      if (previous.payload != payload) {
        throw const AppException(
          'IDEMPOTENCY_MISMATCH',
          'Permintaan ini telah digunakan untuk pilihan berbeda.',
        );
      }
      return previous.result;
    }
    final offered = _item(offeredItemId);
    final requested = _item(requestedItemId);
    if (_blocks.contains(requested.ownerId)) {
      throw const AppException(
        'USER_BLOCKED',
        'Penawaran ke anggota ini diblokir.',
      );
    }
    SwapRules.validateItems(
      actorId: actorId,
      offered: offered,
      requested: requested,
    );
    for (final offer in _offers.values) {
      final samePair =
          (offer.offeredItemId == offeredItemId &&
              offer.requestedItemId == requestedItemId) ||
          (offer.offeredItemId == requestedItemId &&
              offer.requestedItemId == offeredItemId);
      if (samePair &&
          offer.status == SwapStatus.pending &&
          _clock().isBefore(offer.expiresAt)) {
        throw const AppException(
          'DUPLICATE_OFFER',
          'Sudah ada penawaran untuk pasangan barang ini.',
        );
      }
    }
    final now = _clock();
    final id = 'local-${_offers.length + 1}';
    _offers[id] = SwapOffer(
      id: id,
      requesterId: actorId,
      recipientId: requested.ownerId,
      offeredItemId: offeredItemId,
      requestedItemId: requestedItemId,
      createdAt: now,
      expiresAt: now.add(const Duration(days: 7)),
      offeredSummary: SwapItemSummary.fromItem(offered),
      requestedSummary: SwapItemSummary.fromItem(requested),
      events: [SwapEvent('Penawaran diajukan (demo lokal)', now)],
    );
    _requests[requestId] = (payload: payload, result: id);
    return id;
  }

  @override
  Future<void> act(String id, SwapAction action, String actorId) async {
    final offer = await findOffer(id, actorId);
    final now = _clock();
    final next = SwapRules.transition(
      offer: offer,
      action: action,
      actorId: actorId,
      now: now,
    );
    if (action == SwapAction.accept) {
      SwapRules.validateItems(
        actorId: offer.requesterId,
        offered: _item(offer.offeredItemId),
        requested: _item(offer.requestedItemId),
      );
    }
    if (action == SwapAction.confirmReceipt && offer.confirmedBy(actorId)) {
      return;
    }
    final label = switch (action) {
      SwapAction.accept => 'Penawaran diterima · kedua barang direservasi',
      SwapAction.decline => 'Penawaran ditolak',
      SwapAction.withdraw => 'Penawaran ditarik pemohon',
      SwapAction.confirmReceipt =>
        next == SwapStatus.completed
            ? 'Kedua pihak mengonfirmasi · pertukaran selesai'
            : 'Satu pihak mengonfirmasi penerimaan',
      SwapAction.requestCancellation =>
        next == SwapStatus.disputed
            ? 'Masalah setelah konfirmasi · sengketa dibuka'
            : 'Pembatalan diminta',
      SwapAction.approveCancellation => 'Pembatalan disetujui kedua pihak',
      SwapAction.rejectCancellation => 'Permintaan pembatalan ditolak',
      SwapAction.dispute => 'Sengketa dibuka · barang tetap direservasi',
    };
    _offers[id] = offer.copyWith(
      status: next,
      offeredSnapshot: action == SwapAction.accept
          ? _item(offer.offeredItemId)
          : null,
      requestedSnapshot: action == SwapAction.accept
          ? _item(offer.requestedItemId)
          : null,
      clearCancellationRequest:
          action == SwapAction.approveCancellation ||
          action == SwapAction.rejectCancellation,
      events: List.unmodifiable([...offer.events, SwapEvent(label, now)]),
      requesterConfirmedAt:
          action == SwapAction.confirmReceipt && actorId == offer.requesterId
          ? now
          : null,
      recipientConfirmedAt:
          action == SwapAction.confirmReceipt && actorId == offer.recipientId
          ? now
          : null,
      cancellationRequestedBy: action == SwapAction.requestCancellation
          ? actorId
          : null,
    );
    final itemIds = {offer.offeredItemId, offer.requestedItemId};
    if (action == SwapAction.accept) {
      for (final itemId in itemIds) {
        _items[itemId] = _item(itemId).copyWith(status: ItemStatus.reserved);
      }
      for (final other in _offers.values.toList()) {
        if (other.id != id &&
            other.status == SwapStatus.pending &&
            (itemIds.contains(other.offeredItemId) ||
                itemIds.contains(other.requestedItemId))) {
          _offers[other.id] = other.copyWith(
            status: SwapStatus.invalidated,
            events: List.unmodifiable([
              ...other.events,
              SwapEvent('Barang terikat pertukaran lain', now),
            ]),
          );
        }
      }
    }
    if (next == SwapStatus.completed ||
        (next == SwapStatus.cancelled && offer.status.isActive)) {
      for (final itemId in itemIds) {
        _items[itemId] = _item(itemId).copyWith(
          status: next == SwapStatus.completed
              ? ItemStatus.exchanged
              : ItemStatus.available,
        );
      }
    }
  }

  @override
  Future<MemberProfile> current() async => _profile;

  @override
  Future<void> uploadAvatar(Uint8List jpeg, {String? requestKey}) async {
    _profile = MemberProfile(
      id: _profile.id,
      displayName: _profile.displayName,
      city: _profile.city,
      bio: _profile.bio,
      avatarUrl: 'data:image/jpeg;base64,${base64Encode(jpeg)}',
    );
  }

  @override
  Future<void> report({
    required ReportKind kind,
    required String target,
    required ReportReason reason,
    required String details,
  }) async {
    if (details.trim().length < 5 || details.trim().length > 2000) {
      throw const AppException(
        'REASON_REQUIRED',
        'Jelaskan laporan Anda dalam 5–2000 karakter.',
      );
    }
    // Preview only: no report is sent. The UI explicitly labels this mode.
  }

  @override
  Future<void> setBlocked(String target, {required bool blocked}) async {
    if (target == viewerId) {
      throw const AppException('INVALID_TARGET', 'Pilih anggota lain.');
    }
    if (!blocked) {
      _blocks.remove(target);
      return;
    }
    _blocks.add(target);
    for (final offer in _offers.values.toList()) {
      if (offer.involves(viewerId) &&
          offer.involves(target) &&
          !offer.status.isTerminal &&
          offer.status != SwapStatus.disputed) {
        _offers[offer.id] = offer.copyWith(
          status: offer.status == SwapStatus.pending
              ? SwapStatus.invalidated
              : SwapStatus.disputed,
          events: [...offer.events, SwapEvent('Anggota diblokir', _clock())],
        );
      }
    }
  }

  @override
  Future<List<BlockedMember>> blockedMembers() async => _blocks
      .map(
        (id) => BlockedMember(
          id,
          _items.values.where((i) => i.ownerId == id).firstOrNull?.ownerName ??
              'Anggota demo',
        ),
      )
      .toList();

  @override
  Future<void> proposeMeetup(
    String offerId,
    String actorId, {
    required String location,
    required DateTime scheduledAt,
  }) async {
    final offer = await findOffer(offerId, actorId);
    if (offer.status != SwapStatus.accepted || offer.hasConfirmation) {
      throw const AppException(
        'ITEM_LOCKED',
        'Pertemuan tidak dapat diubah pada status ini.',
      );
    }
    if (location.trim().length < 5 ||
        location.trim().length > 200 ||
        !scheduledAt.isAfter(_clock()) ||
        scheduledAt.isAfter(_clock().add(const Duration(days: 30)))) {
      throw const AppException(
        'INVALID_MEETUP',
        'Isi tempat publik dan waktu dalam 30 hari mendatang.',
      );
    }
    final version = (offer.meetup?.version ?? 0) + 1;
    _offers[offerId] = offer.copyWith(
      meetup: Meetup(
        id: '$offerId-$version',
        location: location.trim(),
        scheduledAt: scheduledAt,
        proposedBy: actorId,
        version: version,
      ),
      events: [...offer.events, SwapEvent('Pertemuan diusulkan', _clock())],
    );
  }

  @override
  Future<void> approveMeetup(
    String offerId,
    String actorId,
    Meetup proposal,
  ) async {
    final offer = await findOffer(offerId, actorId);
    final current = offer.meetup;
    if (current == null ||
        offer.status != SwapStatus.accepted ||
        offer.hasConfirmation ||
        current.version != proposal.version ||
        current.id != proposal.id ||
        current.proposedBy == actorId) {
      throw const AppException(
        'INVALID_MEETUP_APPROVAL',
        'Usulan berubah atau tidak tersedia untuk Anda. Muat ulang data.',
      );
    }
    if (current.approvedBy != null) return;
    _offers[offerId] = offer.copyWith(
      meetup: Meetup(
        id: current.id,
        location: current.location,
        scheduledAt: current.scheduledAt,
        proposedBy: current.proposedBy,
        approvedBy: actorId,
        version: current.version,
      ),
      events: [...offer.events, SwapEvent('Pertemuan disepakati', _clock())],
    );
  }

  Item _editable(Item item) {
    final current = _item(item.id);
    if (current.ownerId != viewerId ||
        current.status == ItemStatus.reserved ||
        current.status == ItemStatus.exchanged) {
      throw const AppException('ITEM_LOCKED', 'Barang ini tidak dapat diubah.');
    }
    if (current.revision != item.revision) {
      throw const AppException(
        'STALE_REVISION',
        'Muat ulang versi barang terbaru.',
      );
    }
    return current;
  }

  void _invalidatePending(String itemId) {
    for (final offer in _offers.values.toList()) {
      if (offer.status == SwapStatus.pending &&
          (offer.offeredItemId == itemId || offer.requestedItemId == itemId)) {
        _offers[offer.id] = offer.copyWith(
          status: SwapStatus.invalidated,
          events: [...offer.events, SwapEvent('Barang diperbarui', _clock())],
        );
      }
    }
  }

  @override
  Future<Item> saveDraft(ItemDraft draft) async {
    final previous = _items[draft.id];
    if (previous != null) {
      _editable(previous.copyWith(revision: draft.expectedRevision));
    }
    if (previous == null && draft.expectedRevision != 0) {
      throw const AppException('NOT_FOUND', 'Draft tidak ditemukan.');
    }
    if (draft.title.trim().length < 5 ||
        draft.title.trim().length > 80 ||
        draft.description.trim().length < 20 ||
        draft.description.trim().length > 2000 ||
        draft.city.trim().length < 2 ||
        draft.city.trim().length > 80 ||
        draft.preferences.length > 500) {
      throw const AppException('INVALID_ITEM', 'Periksa panjang isian barang.');
    }
    final item = Item(
      id: draft.id,
      ownerId: viewerId,
      ownerName: _profile.displayName,
      title: draft.title.trim(),
      description: draft.description.trim(),
      category: draft.category,
      condition: draft.condition,
      city: draft.city.trim(),
      preferences: draft.preferences.trim(),
      status: previous?.status ?? ItemStatus.draft,
      revision: (previous?.revision ?? 0) + 1,
      photoPaths: previous?.photoPaths ?? [],
      imageUrls: previous?.imageUrls ?? [],
      photos: previous?.photos ?? [],
    );
    _items[item.id] = item;
    _invalidatePending(item.id);
    return item;
  }

  Item _withPhotos(Item item, List<ItemPhoto> photos, List<String> urls) =>
      Item(
        id: item.id,
        ownerId: item.ownerId,
        ownerName: item.ownerName,
        title: item.title,
        description: item.description,
        category: item.category,
        condition: item.condition,
        city: item.city,
        preferences: item.preferences,
        status: item.status,
        revision: item.revision + 1,
        photos: photos,
        photoPaths: photos.map((p) => p.path).toList(),
        imageUrls: urls,
      );

  @override
  Future<Item> addPhoto(Item item, Uint8List jpeg, {String? requestKey}) async {
    final previous = requestKey == null
        ? null
        : _item(item.id).photos.where((p) => p.id == requestKey).firstOrNull;
    if (previous != null) return _item(item.id);
    _editable(item);
    final position = List.generate(
      5,
      (i) => i,
    ).where((i) => !item.photos.any((p) => p.position == i)).firstOrNull;
    if (position == null) {
      throw const AppException('PHOTO_LIMIT', 'Maksimal lima foto.');
    }
    final id = requestKey ?? 'photo-${_clock().microsecondsSinceEpoch}';
    final result = _withPhotos(
      item,
      [...item.photos, ItemPhoto(id: id, path: id, position: position)],
      [...item.imageUrls, 'data:image/jpeg;base64,${base64Encode(jpeg)}'],
    );
    _items[item.id] = result;
    _invalidatePending(item.id);
    return result;
  }

  @override
  Future<Item> removePhoto(Item item, ItemPhoto photo) async {
    _editable(item);
    if (item.status == ItemStatus.available && item.photos.length <= 1) {
      throw const AppException(
        'PHOTO_REQUIRED',
        'Barang tersedia memerlukan setidaknya satu foto.',
      );
    }
    final index = item.photos.indexWhere((p) => p.id == photo.id);
    if (index < 0) {
      throw const AppException('NOT_FOUND', 'Foto tidak ditemukan.');
    }
    final urls = [...item.imageUrls]..removeAt(index);
    final result = _withPhotos(
      item,
      item.photos.where((p) => p.id != photo.id).toList(),
      urls,
    );
    _items[item.id] = result;
    _invalidatePending(item.id);
    return result;
  }

  @override
  Future<Item> setListingState(Item item, {required bool publish}) async {
    _editable(item);
    if (publish && item.photos.isEmpty) {
      throw const AppException(
        'PHOTO_REQUIRED',
        'Tambahkan foto asli terlebih dahulu.',
      );
    }
    final result = item.copyWith(
      status: publish ? ItemStatus.available : ItemStatus.archived,
      revision: item.revision + 1,
    );
    _items[item.id] = result;
    if (!publish) _invalidatePending(item.id);
    return result;
  }

  @override
  Future<void> update({
    required String displayName,
    required String city,
    required String bio,
  }) async {
    if (displayName.trim().length < 2 ||
        displayName.trim().length > 50 ||
        city.trim().length < 2 ||
        city.trim().length > 80 ||
        bio.trim().length > 300) {
      throw const AppException(
        'INVALID_PROFILE',
        'Periksa panjang nama, kota, dan bio.',
      );
    }
    _profile = MemberProfile(
      id: viewerId,
      displayName: displayName.trim(),
      city: city.trim(),
      bio: bio.trim(),
      avatarUrl: _profile.avatarUrl,
    );
  }
}
