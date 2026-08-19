import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kncard_app/core/models/card_model.dart';
import 'package:kncard_app/app/app_providers.dart';
import 'package:kncard_app/features/statistics/statistics_page.dart';
import 'package:kncard_app/features/statistics/study_statistics.dart';

void main() {
  final now = DateTime(2026, 8, 19, 12);

  test('aggregates current card state and the selected date range', () {
    final statistics = buildStudyStatistics(
      cards: [
        _card(
          id: 'mastered',
          folder: 'deck-a',
          mastery: 'familiar',
          reviews: 4,
          state: FsrsState.review,
          dueAt: now.add(const Duration(days: 2)),
        ),
        _card(
          id: 'fuzzy',
          folder: 'deck-a',
          mastery: 'fuzzy',
          reviews: 2,
          state: FsrsState.review,
          dueAt: now.subtract(const Duration(days: 1)),
        ),
        _card(
          id: 'forgotten',
          folder: 'deck-a',
          mastery: 'forgot',
          reviews: 1,
          state: FsrsState.relearning,
          dueAt: now.subtract(const Duration(days: 1)),
        ),
        _card(
          id: 'new',
          folder: 'deck-b',
          state: FsrsState.newCard,
          dueAt: now,
        ),
      ],
      events: [
        _event('e1', 'mastered', 'deck-a', ReviewRating.good, now),
        _event(
          'e2',
          'mastered',
          'deck-a',
          ReviewRating.easy,
          now.subtract(const Duration(days: 1)),
        ),
        _event(
          'e3',
          'fuzzy',
          'deck-a',
          ReviewRating.hard,
          now.subtract(const Duration(days: 2)),
        ),
        _event(
          'e4',
          'forgotten',
          'deck-a',
          ReviewRating.again,
          now.subtract(const Duration(days: 2)),
        ),
        _event(
          'old',
          'mastered',
          'deck-a',
          ReviewRating.good,
          DateTime(2026, 7, 31),
        ),
      ],
      range: StudyStatsRange.week,
      folder: 'deck-a',
      now: now,
    );

    expect(statistics.totalCards, 3);
    expect(statistics.learnedCards, 3);
    expect(statistics.masteredCards, 1);
    expect(statistics.fuzzyCards, 1);
    expect(statistics.forgottenCards, 1);
    expect(statistics.dueCards, 2);
    expect(statistics.newCards, 0);
    expect(statistics.reviewCount, 4);
    expect(statistics.reviewedCardCount, 3);
    expect(statistics.streakDays, 3);
    expect(statistics.trend, hasLength(7));
    expect(statistics.trend[4].reviewed, 2);
    expect(statistics.trend[4].fuzzy, 1);
    expect(statistics.trend[4].forgotten, 1);
    expect(statistics.decks.single.name, 'deck-a');
    expect(statistics.decks.single.progress, 1);
  });

  test('keeps new-card and folder counts independent from event range', () {
    final statistics = buildStudyStatistics(
      cards: [
        _card(
          id: 'new',
          folder: 'deck-b',
          state: FsrsState.newCard,
          dueAt: now,
        ),
      ],
      events: [
        _event(
          'old',
          'removed-card',
          'deck-b',
          ReviewRating.good,
          DateTime(2026, 7, 1),
        ),
      ],
      range: StudyStatsRange.month,
      folder: 'deck-b',
      now: now,
    );

    expect(statistics.totalCards, 1);
    expect(statistics.newCards, 1);
    expect(statistics.learnedCards, 0);
    expect(statistics.reviewCount, 0);
    expect(statistics.trend, hasLength(19));
    expect(statistics.decks.single.due, 1);
  });

  test('counts manually mastered new cards as learned, not as new cards', () {
    final statistics = buildStudyStatistics(
      cards: [
        _card(
          id: 'manually-mastered',
          folder: 'deck-a',
          mastery: masteredCardMastery,
          state: FsrsState.newCard,
          dueAt: DateTime(9999, 12, 31, 23, 59, 59),
        ),
        _card(
          id: 'new',
          folder: 'deck-a',
          state: FsrsState.newCard,
          dueAt: now,
        ),
      ],
      events: const [],
      range: StudyStatsRange.all,
      folder: 'deck-a',
      now: now,
    );

    expect(statistics.learnedCards, 1);
    expect(statistics.masteredCards, 1);
    expect(statistics.masteryRate, 1);
    expect(statistics.newCards, 1);
    expect(statistics.decks.single.learned, 1);
    expect(statistics.decks.single.mastered, 1);
    expect(statistics.decks.single.newCards, 1);
  });

  testWidgets('renders the statistics page at phone width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardsProvider.overrideWith(
            (ref) async => [
              _card(
                id: 'card',
                folder: 'deck-a',
                mastery: 'familiar',
                reviews: 2,
                state: FsrsState.review,
                dueAt: now,
              ),
            ],
          ),
          reviewEventsProvider.overrideWith(
            (ref) async => [
              _event('event', 'card', 'deck-a', ReviewRating.good, now),
            ],
          ),
        ],
        child: const MaterialApp(home: StatisticsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('学习统计'), findsOneWidget);
    expect(find.text('题库维度'), findsOneWidget);
    expect(find.text('学习反馈趋势'), findsOneWidget);
    expect(find.text('deck-a'), findsOneWidget);
  });
}

CardModel _card({
  required String id,
  required String folder,
  String mastery = '',
  int reviews = 0,
  FsrsState state = FsrsState.newCard,
  required DateTime dueAt,
}) {
  return CardModel(
    id: id,
    accountId: 'account-a',
    type: CardType.single,
    folder: folder,
    question: id,
    options: const {},
    answer: const [],
    content: '',
    noteContent: '',
    explanation: '',
    tags: const [],
    dueAt: dueAt,
    createdAt: dueAt,
    updatedAt: dueAt,
    reviews: reviews,
    mastery: mastery,
    suspended: false,
    fsrs: FsrsSnapshot(
      state: state,
      dueAt: dueAt,
      stability: reviews == 0 ? 0 : 2,
      difficulty: reviews == 0 ? 0 : 5,
      reps: reviews,
      lapses: mastery == 'forgot' ? 1 : 0,
    ),
  );
}

ReviewEventModel _event(
  String id,
  String cardId,
  String folder,
  ReviewRating rating,
  DateTime reviewedAt,
) => ReviewEventModel(
  id: id,
  accountId: 'account-a',
  cardId: cardId,
  question: cardId,
  folder: folder,
  rating: rating,
  reviewedAt: reviewedAt,
  nextDue: reviewedAt.add(const Duration(days: 1)),
);
