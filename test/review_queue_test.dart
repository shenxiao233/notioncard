import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kncard_app/core/models/card_model.dart';
import 'package:kncard_app/features/review/review_queue.dart';
import 'package:kncard_app/features/review/review_settings.dart';

void main() {
  test('review queue limits new and scheduled cards independently', () {
    final cards = [
      _card('new-1', FsrsState.newCard),
      _card('new-2', FsrsState.newCard),
      _card('new-3', FsrsState.newCard),
      _card('review-1', FsrsState.review),
      _card('review-2', FsrsState.relearning),
    ];

    final queue = buildReviewQueue(
      cards: cards,
      settings: const ReviewSettings(newCardsPerDay: 2, reviewsPerDay: 1),
      folder: '默认牌组',
      now: DateTime(2026, 1, 2),
    );

    expect(queue.map((card) => card.id), ['new-1', 'new-2', 'review-1']);
  });

  test('review queue follows card creation order while applying limits', () {
    final oldReview = _card(
      'old-review',
      FsrsState.review,
      createdAt: DateTime(2026, 1, 1),
    );
    final newCard = _card(
      'new-card',
      FsrsState.newCard,
      createdAt: DateTime(2026, 1, 2),
    );
    final recentReview = _card(
      'recent-review',
      FsrsState.review,
      createdAt: DateTime(2026, 1, 3),
    );

    final queue = buildReviewQueue(
      cards: [recentReview, newCard, oldReview],
      settings: const ReviewSettings(newCardsPerDay: 1, reviewsPerDay: 2),
      folder: '默认牌组',
      now: DateTime(2026, 1, 4),
    );

    expect(queue.map((card) => card.id), [
      'old-review',
      'new-card',
      'recent-review',
    ]);
  });
  test('review settings are persisted per account', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final first = ReviewSettingsController(preferences, 'account-a');

    await first.setNewCardsPerDay(7);
    await first.setReviewsPerDay(42);

    final second = ReviewSettingsController(preferences, 'account-a');
    final other = ReviewSettingsController(preferences, 'account-b');

    expect(second.state.newCardsPerDay, 7);
    expect(second.state.reviewsPerDay, 42);
    expect(other.state.newCardsPerDay, 20);
    expect(other.state.reviewsPerDay, 100);
  });

  test('review settings tolerate legacy preference values', () async {
    SharedPreferences.setMockInitialValues({
      'review.new_cards_per_day.account-a': '7',
      'review.reviews_per_day.account-a': 12000,
    });
    final preferences = await SharedPreferences.getInstance();
    final settings = ReviewSettingsController(preferences, 'account-a');

    expect(settings.state.newCardsPerDay, 7);
    expect(settings.state.reviewsPerDay, 9999);
  });

  test('selected review folder is persisted per account', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await saveSelectedReviewFolder(preferences, 'account-a', '英语');

    expect(loadSelectedReviewFolder(preferences, 'account-a'), '英语');
    expect(loadSelectedReviewFolder(preferences, 'account-b'), isNull);

    await saveSelectedReviewFolder(preferences, 'account-a', null);
    expect(loadSelectedReviewFolder(preferences, 'account-a'), isNull);
  });
}

CardModel _card(String id, FsrsState state, {DateTime? createdAt}) {
  final due = createdAt ?? DateTime(2026, 1, 1);
  return CardModel(
    id: id,
    accountId: 'account-a',
    type: CardType.note,
    folder: '默认牌组',
    question: id,
    options: const {},
    answer: const [],
    noteContent: '内容',
    explanation: '',
    tags: const [],
    dueAt: due,
    createdAt: due,
    updatedAt: due,
    reviews: state == FsrsState.newCard ? 0 : 1,
    mastery: '',
    suspended: false,
    fsrs: FsrsSnapshot(
      state: state,
      dueAt: due,
      stability: 1,
      difficulty: 5,
      reps: state == FsrsState.newCard ? 0 : 1,
      lapses: 0,
    ),
  );
}
