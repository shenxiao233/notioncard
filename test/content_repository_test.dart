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
      expect(sync.objectVersion, 1);
      expect(payload['reviews'], 0);
      expect((payload['fsrs'] as Map)['state'], 'newCard');
      expect(payload['progressReset'], true);
    },
  );

  test(
    'relearnDeck coalesces a large deck without duplicating queue rows',
    () async {
      final now = DateTime(2026, 8, 1);
      final cards = List.generate(
        1210,
        (index) => _buildLargeDeckCard(index, now),
      );
      await database.saveCards(cards);
      await database.enqueueSyncItems(
        cards.map(
          (card) => SyncQueueItemModel(
            id: 'old-${card.id}',
            accountId: card.accountId,
            objectType: 'CARD',
            objectId: card.id,
            operation: SyncOperation.upsert,
            payload: '{}',
            status: SyncItemStatus.pending,
            attempts: 0,
            lastError: null,
            createdAt: now,
            updatedAt: now,
          ),
        ),
      );

      final count = await ContentRepository(
        database,
      ).relearnDeck(accountId: 'account-1', folder: 'large-deck');

      expect(count, 1210);
      final pending = await database.loadPendingSync('account-1');
      expect(pending, hasLength(1210));
      expect(
        pending.every((item) => item.id.startsWith('card-upsert-')),
        isTrue,
      );
    },
  );

  test(
    'coalesces multiple reviews of one card into one pending snapshot',
    () async {
      final now = DateTime(2026, 8, 1);
      final card = _buildReviewCard(now);
      final repository = ContentRepository(database);

      await repository.saveReview(
        card: card.copyWith(reviews: 1),
        event: _reviewEvent(card, now, 'event-1'),
      );
      await repository.saveReview(
        card: card.copyWith(reviews: 2),
        event: _reviewEvent(
          card,
          now.add(const Duration(minutes: 1)),
          'event-2',
        ),
      );

      final pending = await database.loadPendingSync(card.accountId);
      final payload =
          jsonDecode(pending.single.payload) as Map<String, dynamic>;
      expect(pending, hasLength(1));
      expect(pending.single.id, startsWith('card-upsert-${card.id}-'));
      expect(payload['reviews'], 2);
      expect(payload['eventId'], 'event-2');
    },
  );

  test('keeps relearn intent when a card is reviewed before upload', () async {
    final now = DateTime(2026, 8, 1);
    final card = _buildReviewCard(now).copyWith(reviews: 4);
    final repository = ContentRepository(database);
    await database.saveCard(card);

    await repository.relearnDeck(
      accountId: card.accountId,
      folder: card.folder,
    );
    final reset = (await database.loadCards(card.accountId)).single;
    await repository.saveReview(
      card: reset.copyWith(reviews: 1),
      event: _reviewEvent(card, now.add(const Duration(minutes: 1)), 'event-1'),
    );

    final pending = (await database.loadPendingSync(card.accountId)).single;
    final payload = jsonDecode(pending.payload) as Map<String, dynamic>;
    expect(payload['reviews'], 1);
    expect(payload['progressReset'], true);
  });

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

    expect(
      (await database.loadCards(card.accountId)).single.question,
      card.question,
    );
    final queued = (await database.loadPendingSync(card.accountId)).single;
    final payload = jsonDecode(queued.payload) as Map<String, dynamic>;
    expect(queued.objectType, 'CARD');
    expect(queued.objectId, card.id);
    expect(queued.operation, SyncOperation.upsert);
    expect(payload['question'], card.question);
    expect(payload['folder'], card.folder);
  });

  test(
    'importCards writes cards and sync items, then skips duplicates',
    () async {
      final repository = ContentRepository(database);
      final first = _buildImportCard('market-deck-1-1', '第一张卡');
      final second = _buildImportCard('market-deck-1-2', '第二张卡');

      final imported = await repository.importCards('account-1', [
        first,
        second,
        _buildImportCard('other-account-card', '忽略的卡片'),
      ]);

      expect(imported.imported, 2);
      expect(imported.skipped, 0);
      expect(await database.loadCards('account-1'), hasLength(2));
      expect(await database.loadCards('other-account'), isEmpty);
      expect(await database.loadPendingSync('account-1'), hasLength(2));

      final repeated = await repository.importCards('account-1', [
        first,
        second,
      ]);

      expect(repeated.imported, 0);
      expect(repeated.skipped, 2);
      expect(await database.loadCards('account-1'), hasLength(2));
      expect(await database.loadPendingSync('account-1'), hasLength(2));
    },
  );

  test(
    'updateCard replaces editable fields and queues a card upsert',
    () async {
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
    },
  );
}

CardModel _buildImportCard(String id, String question) {
  final now = DateTime(2026, 8, 1);
  return CardModel(
    id: id,
    accountId: id == 'other-account-card' ? 'other-account' : 'account-1',
    type: CardType.note,
    folder: '测试牌组',
    question: question,
    options: const {},
    answer: const ['答案'],
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
      difficulty: 5,
      reps: 0,
      lapses: 0,
    ),
  );
}

CardModel _buildLargeDeckCard(int index, DateTime now) {
  final timestamp = now.add(Duration(microseconds: index));
  return CardModel(
    id: 'large-card-$index',
    accountId: 'account-1',
    type: CardType.note,
    folder: 'large-deck',
    question: 'Question $index',
    options: const {},
    answer: const [],
    noteContent: '',
    explanation: '',
    tags: const [],
    dueAt: timestamp,
    createdAt: timestamp,
    updatedAt: timestamp,
    reviews: 2,
    mastery: 'familiar',
    suspended: false,
    fsrs: FsrsSnapshot(
      state: FsrsState.review,
      dueAt: timestamp,
      stability: 2,
      difficulty: 5,
      reps: 2,
      lapses: 0,
    ),
  );
}

CardModel _buildReviewCard(DateTime now) => CardModel(
  id: 'review-card',
  accountId: 'account-1',
  type: CardType.note,
  folder: 'deck',
  question: 'Question',
  options: const {},
  answer: const [],
  noteContent: 'Note',
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
    difficulty: 5,
    reps: 0,
    lapses: 0,
  ),
);

ReviewEventModel _reviewEvent(CardModel card, DateTime reviewedAt, String id) =>
    ReviewEventModel(
      id: id,
      accountId: card.accountId,
      cardId: card.id,
      question: card.question,
      folder: card.folder,
      rating: ReviewRating.good,
      reviewedAt: reviewedAt,
      nextDue: reviewedAt.add(const Duration(days: 1)),
    );
