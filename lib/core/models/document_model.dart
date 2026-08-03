class DocumentModel {
  const DocumentModel({
    required this.id,
    required this.accountId,
    required this.folder,
    required this.title,
    required this.body,
    required this.updatedAt,
  });

  final String id;
  final String accountId;
  final String folder;
  final String title;
  final String body;
  final DateTime updatedAt;
}
