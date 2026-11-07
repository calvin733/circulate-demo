import 'item_draft.dart';

enum ItemCategory {
  books('Buku'),
  electronics('Elektronik'),
  home('Rumah'),
  hobbies('Hobi'),
  fashion('Fashion'),
  sports('Olahraga');

  const ItemCategory(this.label);
  final String label;
}

enum ItemCondition {
  likeNew('Seperti baru'),
  good('Baik'),
  fair('Cukup baik');

  const ItemCondition(this.label);
  final String label;
}

enum ItemStatus {
  draft('Draft'),
  available('Tersedia'),
  reserved('Direservasi'),
  exchanged('Sudah ditukar'),
  archived('Diarsipkan');

  const ItemStatus(this.label);
  final String label;
}

class Item {
  const Item({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.title,
    required this.description,
    required this.category,
    required this.condition,
    required this.city,
    required this.preferences,
    this.status = ItemStatus.available,
    this.visible = true,
    this.revision = 1,
    this.photoPaths = const [],
    this.imageUrls = const [],
    this.photos = const [],
  });
  final String id;
  final String ownerId;
  final String ownerName;
  final String title;
  final String description;
  final ItemCategory category;
  final ItemCondition condition;
  final String city;
  final String preferences;
  final ItemStatus status;
  final bool visible;
  final int revision;
  final List<String> photoPaths;
  final List<String> imageUrls;
  final List<ItemPhoto> photos;

  Item copyWith({ItemStatus? status, bool? visible, int? revision}) => Item(
    id: id,
    ownerId: ownerId,
    ownerName: ownerName,
    title: title,
    description: description,
    category: category,
    condition: condition,
    city: city,
    preferences: preferences,
    status: status ?? this.status,
    visible: visible ?? this.visible,
    revision: revision ?? this.revision,
    photoPaths: photoPaths,
    imageUrls: imageUrls,
    photos: photos,
  );
}

class ItemFilter {
  const ItemFilter({this.query = '', this.category, this.condition});
  final String query;
  final ItemCategory? category;
  final ItemCondition? condition;

  bool matches(Item item) {
    final needle = query.trim().toLowerCase();
    return item.status == ItemStatus.available &&
        item.visible &&
        (category == null || item.category == category) &&
        (condition == null || item.condition == condition) &&
        (needle.isEmpty ||
            '${item.title} ${item.description}'.toLowerCase().contains(needle));
  }
}
