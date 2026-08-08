import '../models/card_model.dart';

Map<String, dynamic> cardSyncPayload(
  CardModel card, {
  bool progressReset = false,
}) {
  final payload = <String, dynamic>{
    'id': card.id,
    'type': card.type.name,
    'folder': card.folder,
    'question': card.question,
    'options': card.options,
    'answer': card.answer,
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
  if (progressReset) payload['progressReset'] = true;
  return payload;
}
