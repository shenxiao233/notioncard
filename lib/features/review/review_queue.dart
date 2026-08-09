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
        (folder == null || card.folder.trim() == folder.trim());
  }).toList()..sort(compareReviewCardOrder);

  final queue = <CardModel>[];
  var newCards = 0;
  var scheduledCards = 0;
  for (final card in due) {
    if (!settings.autonomousLearning) {
      if (card.fsrs.state == FsrsState.newCard) {
        if (newCards >= settings.newCardsPerDay) continue;
        newCards++;
      } else {
        if (scheduledCards >= settings.reviewsPerDay) continue;
        scheduledCards++;
      }
    }
    queue.add(card);
  }

  return queue;
}

int compareReviewCardOrder(CardModel left, CardModel right) {
  final created = left.createdAt.compareTo(right.createdAt);
  if (created != 0) return created;
  return left.id.compareTo(right.id);
}
