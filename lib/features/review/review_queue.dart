import '../../core/models/card_model.dart';
import 'review_settings.dart';

List<CardModel> buildReviewQueue({
  required List<CardModel> cards,
  required ReviewSettings settings,
  String? folder,
  DateTime? now,
}) {
  final currentTime = now ?? DateTime.now();
  final due = cards.where((card) {
    return !card.suspended &&
        !card.dueAt.isAfter(currentTime) &&
        (folder == null || card.folder == folder);
  });

  final newCards = <CardModel>[];
  final scheduledCards = <CardModel>[];
  for (final card in due) {
    if (card.fsrs.state == FsrsState.newCard) {
      newCards.add(card);
    } else {
      scheduledCards.add(card);
    }
  }

  return [
    ...newCards.take(settings.newCardsPerDay),
    ...scheduledCards.take(settings.reviewsPerDay),
  ];
}
