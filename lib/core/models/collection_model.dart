enum CollectionType { deck, documentCategory }

class CollectionModel {
  const CollectionModel({
    required this.id,
    required this.accountId,
    required this.type,
    required this.name,
    required this.icon,
    required this.color,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String accountId;
  final CollectionType type;
  final String name;
  final String icon;
  final String color;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  CollectionModel copyWith({
    String? id,
    String? accountId,
    CollectionType? type,
    String? name,
    String? icon,
    String? color,
    bool? archived,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => CollectionModel(
    id: id ?? this.id,
    accountId: accountId ?? this.accountId,
    type: type ?? this.type,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    color: color ?? this.color,
    archived: archived ?? this.archived,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  String get typeName =>
      type == CollectionType.deck ? 'deck' : 'documentCategory';
}
