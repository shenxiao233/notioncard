import '../models/card_model.dart';

Map<String, dynamic> cardSyncPayload(
  CardModel card, {
  bool progressReset = false,
  bool progressOnly = false,
  bool restoreDeleted = false,
  String? deckId,
  int? deckEpoch,
}) {
  final payload = <String, dynamic>{
    'id': card.id,
    'type': card.type.name,
    'folder': card.folder,
    'source': card.source,
    'question': card.question,
    'options': card.options,
    'answer': card.answer,
    'content': card.content,
    'noteContent': card.noteContent,
    'explanation': card.explanation,
    'tags': card.tags,
    'dueAt': card.dueAt.toIso8601String(),
    'createdAt': card.createdAt.toIso8601String(),
    'updatedAt': card.updatedAt.toIso8601String(),
    'reviews': card.reviews,
    'mastery': card.mastery,
    'suspended': card.suspended,
    'fsrs': {
      'state': card.fsrs.state.name,
      'dueAt': card.fsrs.dueAt.toIso8601String(),
      'stability': card.fsrs.stability,
      'difficulty': card.fsrs.difficulty,
      'reps': card.fsrs.reps,
      'lapses': card.fsrs.lapses,
    },
  };
  if (card.sortOrder != null) {
    // `order` is the field used by the desktop client. Keep the Flutter
    // spelling too so newer clients can be explicit without breaking older
    // desktop clients.
    payload['sortOrder'] = card.sortOrder;
    payload['order'] = card.sortOrder;
  }
  if (progressReset) payload['progressReset'] = true;
  // A market re-download is an explicit user action that is allowed to
  // resurrect a previously deleted deck/card tombstone. This is deliberately
  // opt-in; ordinary offline mutations must remain unable to resurrect data.
  if (restoreDeleted) payload['restoreDeleted'] = true;
  if (deckId != null && deckId.trim().isNotEmpty) {
    payload['deckId'] = deckId.trim();
  }
  if (deckEpoch != null && deckEpoch >= 0) {
    payload['deckEpoch'] = deckEpoch;
  }
  if (progressOnly) payload['syncMode'] = 'progress';
  return payload;
}
