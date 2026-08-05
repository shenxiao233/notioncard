import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kncard_app/core/database/app_database.dart';
import 'package:kncard_app/core/models/card_model.dart';
import 'package:kncard_app/core/repositories/content_repository.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'relearnDeck resets cards, clears events, and queues sync updates',
    () async {
      final now = DateTime(2026, 8, 1);
      final card = CardModel(
        id: 'card-1',
        accountId: 'account-1',
        type: CardType.note,
        folder: 'deck',
        question: 'Question',
        options: const {},
        answer: const [],
        noteContent: 'Note',
        explanation: '',
        tags: const [],
        dueAt: now.add(const Duration(days: 3)),
        createdAt: now,
        updatedAt: now,
        reviews: 8,
        mastery: 'familiar',
        suspended: false,
        fsrs: FsrsSnapshot(
          state: FsrsState.review,
          dueAt: now.add(const Duration(days: 3)),
          stability: 12,
          difficulty: 4,
          reps: 8,
          lapses: 1,
        ),
      );
      await database.saveCard(card);
      await database.saveReviewEvent(
        ReviewEventModel(
          id: 'event-1',
          accountId: card.accountId,
          cardId: card.id,
          question: card.question,
          folder: card.folder,
          rating: ReviewRating.good,
          reviewedAt: now,
          nextDue: card.dueAt,
        ),
      );

      final count = await ContentRepository(
        database,
      ).relearnDeck(accountId: card.accountId, folder: card.folder);

      final reset = (await database.loadCards(card.accountId)).single;
      final events = await database.loadReviewEvents(card.accountId);
      final sync = (await database.loadPendingSync(card.accountId)).single;
      final payload = jsonDecode(sync.payload) as Map<String, dynamic>;

      expect(count, 1);
      expect(reset.fsrs.state, FsrsState.newCard);
      expect(reset.fsrs.reps, 0);
      expect(reset.fsrs.lapses, 0);
      expect(reset.reviews, 0);
      expect(reset.mastery, isEmpty);
      expect(reset.dueAt.isAfter(now), isTrue);
      expect(events, isEmpty);
      expect(payload['reviews'], 0);
      expect((payload['fsrs'] as Map)['state'], 'newCard');
    },
  );
}
