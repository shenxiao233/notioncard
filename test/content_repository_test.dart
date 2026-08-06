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

  test('createCard saves the card and queues a card upsert', () async {
    final now = DateTime(2026, 8, 1);
    final card = CardModel(
      id: 'local-card-1',
      accountId: 'account-1',
      type: CardType.note,
      folder: 'deck',
      question: 'What is spaced repetition?',
      options: const {},
      answer: const [],
      noteContent: 'Review information at increasing intervals.',
      explanation: '',
      tags: const ['study'],
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
        difficulty: 5,
        reps: 0,
        lapses: 0,
      ),
    );

    await ContentRepository(database).createCard(card);

    expect((await database.loadCards(card.accountId)).single.question,
        card.question);
    final queued = (await database.loadPendingSync(card.accountId)).single;
    final payload = jsonDecode(queued.payload) as Map<String, dynamic>;
    expect(queued.objectType, 'CARD');
    expect(queued.objectId, card.id);
    expect(queued.operation, SyncOperation.upsert);
    expect(payload['question'], card.question);
    expect(payload['folder'], card.folder);
  });

  test('updateCard replaces editable fields and queues a card upsert', () async {
    final now = DateTime(2026, 8, 1);
    final card = CardModel(
      id: 'local-card-2',
      accountId: 'account-1',
      type: CardType.note,
      folder: 'deck',
      question: 'Original question',
      options: const {},
      answer: const [],
      noteContent: 'Original note',
      explanation: '',
      tags: const [],
      dueAt: now,
      createdAt: now,
      updatedAt: now,
      reviews: 3,
      mastery: 'familiar',
      suspended: false,
      fsrs: FsrsSnapshot(
        state: FsrsState.review,
        dueAt: now,
        stability: 4,
        difficulty: 4,
        reps: 3,
        lapses: 0,
      ),
    );
    await database.saveCard(card);

    final updated = card.copyWith(
      question: 'Updated question',
      noteContent: 'Updated note',
      updatedAt: now.add(const Duration(minutes: 1)),
    );
    await ContentRepository(database).updateCard(updated);

    final saved = (await database.loadCards(card.accountId)).single;
    final queued = (await database.loadPendingSync(card.accountId)).single;
    final payload = jsonDecode(queued.payload) as Map<String, dynamic>;

    expect(saved.question, 'Updated question');
    expect(saved.noteContent, 'Updated note');
    expect(saved.reviews, card.reviews);
    expect(payload['question'], 'Updated question');
    expect(payload['noteContent'], 'Updated note');
    expect(queued.objectType, 'CARD');
    expect(queued.objectId, card.id);
    expect(queued.operation, SyncOperation.upsert);
  });
}
