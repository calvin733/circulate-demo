import 'item.dart';

class ItemDraft {
  const ItemDraft({
    required this.id,
    required this.expectedRevision,
    required this.title,
    required this.description,
    required this.category,
    required this.condition,
    required this.city,
    required this.preferences,
  });
  final String id;
  final int expectedRevision;
  final String title;
  final String description;
  final ItemCategory category;
  final ItemCondition condition;
  final String city;
  final String preferences;
  bool matches(Item item) =>
      item.id == id &&
      item.title == title.trim() &&
      item.description == description.trim() &&
      item.category == category &&
      item.condition == condition &&
      item.city == city.trim() &&
      item.preferences == preferences.trim();
}

class ItemPhoto {
  const ItemPhoto({
    required this.id,
    required this.path,
    required this.position,
  });
  final String id;
  final String path;
  final int position;
}
