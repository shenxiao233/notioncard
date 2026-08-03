class MarketDeckModel {
  const MarketDeckModel({
    required this.id,
    required this.title,
    required this.author,
    required this.description,
    required this.category,
    required this.tags,
    required this.cardCount,
    required this.downloads,
    required this.version,
    required this.updatedAt,
    required this.subscribed,
  });

  final String id;
  final String title;
  final String author;
  final String description;
  final String category;
  final List<String> tags;
  final int cardCount;
  final int downloads;
  final String version;
  final DateTime updatedAt;
  final bool subscribed;
}
