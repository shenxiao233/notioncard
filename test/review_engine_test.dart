import 'package:flutter_test/flutter_test.dart';
import 'package:kncard_app/core/models/card_model.dart';
import 'package:kncard_app/features/review/review_engine.dart';

void main() {
  final now = DateTime(2026, 8, 1, 9);

  CardModel card() => CardModel(
    id: 'card-1',
    accountId: 'account-1',
    type: CardType.single,
    folder: 'Test',
    question: 'Question',
    options: const {'A': 'Answer'},
    answer: const ['A'],
    noteContent: '',
    explanation: '',
    tags: const [],
    dueAt: now,
    createdAt: now,
    updatedAt: now,
    reviews: 0,
    mastery: '',
    suspended: false,
    fsrs: FsrsSnapshot(
      state: FsrsState.newCard,
      dueAt: now,
      stability: 0,
      difficulty: 0,
      reps: 0,
      lapses: 0,
    ),
  );

  test('again creates a relearning card with a short interval', () {
    final result = ReviewEngine().review(card(), ReviewRating.again, now);

    expect(result.fsrs.state, FsrsState.relearning);
    expect(result.fsrs.reps, 1);
    expect(result.fsrs.lapses, 1);
    expect(result.dueAt, now.add(const Duration(minutes: 58)));
    expect(result.mastery, 'forgot');
  });

  test('easy schedules a new card later than good', () {
    final engine = ReviewEngine();
    final good = engine.review(card(), ReviewRating.good, now);
    final easy = engine.review(card(), ReviewRating.easy, now);

    expect(easy.dueAt.isAfter(good.dueAt), isTrue);
    expect(easy.fsrs.stability, 4);
    expect(easy.mastery, 'tooEasy');
  });
}
