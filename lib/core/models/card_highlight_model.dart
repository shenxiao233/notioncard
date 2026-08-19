import 'card_model.dart';

class CardHighlightModel {
  const CardHighlightModel({
    required this.id,
    required this.accountId,
    required this.cardId,
    required this.section,
    required this.selectedText,
    required this.color,
    required this.createdAt,
  });

  final String id;
  final String accountId;
  final String cardId;
  final CardHighlightSection section;
  final String selectedText;
  final String color;
  final DateTime createdAt;

  CardHighlightModel copyWith({
    String? selectedText,
    String? color,
    DateTime? createdAt,
  }) {
    return CardHighlightModel(
      id: id,
      accountId: accountId,
      cardId: cardId,
      section: section,
      selectedText: selectedText ?? this.selectedText,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
