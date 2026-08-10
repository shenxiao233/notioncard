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
  return compareCardOrder(left, right);
}

int compareCardOrder(CardModel left, CardModel right) {
  final leftOrder = left.sortOrder;
  final rightOrder = right.sortOrder;
  if (leftOrder != null && rightOrder != null) {
    final order = leftOrder.compareTo(rightOrder);
    if (order != 0) return order;
  } else if (leftOrder != null || rightOrder != null) {
    // Cards with an explicit source position belong before legacy cards that
    // have not been assigned one yet. The timestamp/id fallback keeps mixed
    // local and imported decks deterministic during migration.
    return leftOrder == null ? 1 : -1;
  }
  final created = left.createdAt.compareTo(right.createdAt);
  if (created != 0) return created;
  return left.id.compareTo(right.id);
}
