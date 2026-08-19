import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kncard_app/core/database/app_database.dart';
import 'package:kncard_app/core/models/card_model.dart';
import 'package:kncard_app/core/models/collection_model.dart';
import 'package:kncard_app/core/repositories/content_repository.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('createDocument stores the document and queues one mutation', () async {
    final document = await ContentRepository(database).createDocument(
      accountId: 'account-1',
      title: '学习笔记',
      body: '# 间隔重复',
      folder: '学习',
    );

    expect(document.id, startsWith('local-document-'));
    expect((await database.loadDocuments('account-1')).single.title, '学习笔记');
    final queued = (await database.loadPendingSync('account-1')).single;
    expect(queued.objectType, 'DOCUMENT');
    expect(queued.objectId, document.id);
    expect(jsonDecode(queued.payload)['body'], '# 间隔重复');
  });

  test(
    'creates empty collections and renames document categories safely',
    () async {
      final repository = ContentRepository(database);
      final category = await repository.createCollection(
        accountId: 'account-1',
        type: CollectionType.documentCategory,
        name: '项目笔记',
      );

      expect((await database.loadCollections('account-1')).single.name, '项目笔记');

      final document = await repository.createDocument(
        accountId: 'account-1',
        title: '第一次记录',
        body: '正文',
        folder: category.name,
      );
      final renamed = await repository.renameCollection(
        collection: category,
        name: '工作笔记',
      );

      expect(renamed.name, '工作笔记');
      expect((await database.loadDocuments('account-1')).single.folder, '工作笔记');

      await repository.archiveCollection(renamed);
      expect(
        (await database.loadCollections('account-1')).single.archived,
        isTrue,
      );
      final pending = await database.loadPendingSync('account-1');
      final collectionMutation = pending.firstWhere(
        (item) => item.objectId == category.id,
      );
      expect(jsonDecode(collectionMutation.payload)['archived'], isTrue);
      expect(document.id, startsWith('local-document-'));
    },
  );

  test(
    'relearnDeck resets cards, clears events, and queues one deck mutation',
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
        content: 'Note',
        noteContent: '',
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
      expect(sync.objectType, 'DECK');
      expect(sync.objectVersion, 1);
      expect(payload['syncAction'], 'DECK_RELEARN');
      expect(payload['cardCount'], 1);
      expect(payload['resetEpoch'], 1);
    },
  );

  test(
    'relearnDeck removes card snapshots and queues one deck mutation',
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
      expect(pending, hasLength(1));
      expect(pending.single.objectType, 'DECK');
      final payload =
          jsonDecode(pending.single.payload) as Map<String, dynamic>;
      expect(payload['syncAction'], 'DECK_RELEARN');
      expect(payload['cardCount'], 1210);
    },
  );

  test(
    'renaming a large deck updates cards locally but queues one deck mutation',
    () async {
      final now = DateTime(2026, 8, 1);
      final cards = List.generate(
        1210,
        (index) => _buildLargeDeckCard(index, now),
      );
      await database.saveCards(cards);
      final persistedUpdatedAt = {
        for (final card in await database.loadCards('account-1'))
          card.id: card.updatedAt,
      };
      await database.saveReviewEvent(
        _reviewEvent(cards.first, now, 'rename-event-1'),
      );

      final renamed = await ContentRepository(database).renameDeck(
        accountId: 'account-1',
        folder: 'large-deck',
        name: 'renamed-deck',
      );

      expect(renamed, 1210);
      final savedCards = await database.loadCards('account-1');
      final savedEvents = await database.loadReviewEvents('account-1');
      final pending = await database.loadPendingSync('account-1');
      final payload =
          jsonDecode(pending.single.payload) as Map<String, dynamic>;

      expect(savedCards, hasLength(1210));
      expect(savedCards.every((card) => card.folder == 'renamed-deck'), isTrue);
      expect(
        savedCards.every(
          (card) => card.updatedAt == persistedUpdatedAt[card.id],
        ),
        isTrue,
      );
      expect(savedEvents.single.folder, 'renamed-deck');
      expect(pending, hasLength(1));
      expect(pending.single.objectType, 'DECK');
      expect(pending.single.objectId, startsWith('local-deck-'));
      expect(payload['id'], pending.single.objectId);
      expect(payload['title'], 'renamed-deck');
      expect(payload['folder'], 'renamed-deck');
      expect(payload['renameFrom'], 'large-deck');
      expect(payload['cardCount'], 1210);
    },
  );

  test(
    'repeated offline deck renames keep one mutation and the original source',
    () async {
      final now = DateTime(2026, 8, 1);
      await database.saveCards([
        _buildLargeDeckCard(0, now),
        _buildLargeDeckCard(1, now.add(const Duration(microseconds: 1))),
      ]);
      final repository = ContentRepository(database);

      await repository.renameDeck(
        accountId: 'account-1',
        folder: 'large-deck',
        name: 'middle-deck',
      );
      await repository.renameDeck(
        accountId: 'account-1',
        folder: 'middle-deck',
        name: 'final-deck',
      );

      final pending = await database.loadPendingSync('account-1');
      final payload =
          jsonDecode(pending.single.payload) as Map<String, dynamic>;

      expect(pending, hasLength(1));
      expect(pending.single.objectType, 'DECK');
      expect(payload['title'], 'final-deck');
      expect(payload['folder'], 'final-deck');
      expect(payload['renameFrom'], 'large-deck');
      expect(payload['cardCount'], 2);
      expect(
        (await database.loadCards(
          'account-1',
        )).every((card) => card.folder == 'final-deck'),
        isTrue,
      );
    },
  );

  test(
    'deleting a deck discards card mutations and queues one deck tombstone',
    () async {
      final now = DateTime(2026, 8, 1);
      final cards = List.generate(
        3,
        (index) => _buildLargeDeckCard(index, now),
      );
      await database.saveCards(cards);
      await database.saveReviewEvent(
        _reviewEvent(cards.first, now, 'delete-event-1'),
      );
      await database.enqueueSyncItems(
        cards.map(
          (card) => SyncQueueItemModel(
            id: 'card-mutation-${card.id}',
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
      ).deleteDeck(accountId: 'account-1', folder: 'large-deck');

      final pending = await database.loadPendingSync('account-1');
      final payload =
          jsonDecode(pending.single.payload) as Map<String, dynamic>;
      expect(count, 3);
      expect(await database.loadCards('account-1'), isEmpty);
      expect(await database.loadReviewEvents('account-1'), isEmpty);
      expect(pending, hasLength(1));
      expect(pending.single.objectType, 'DECK');
      expect(pending.single.operation, SyncOperation.delete);
      expect(payload['folder'], 'large-deck');
      expect(payload['cardCount'], 3);
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

  test('concurrent queue replacements leave one snapshot per object', () async {
    final now = DateTime(2026, 8, 1);
    await Future.wait(
      List.generate(
        20,
        (index) => database.enqueueSync(
          SyncQueueItemModel(
            id: 'settings-mutation-$index-00000000',
            accountId: 'account-1',
            objectType: 'SETTINGS',
            objectId: 'review',
            operation: SyncOperation.upsert,
            payload: '{"value":$index}',
            status: SyncItemStatus.pending,
            attempts: 0,
            lastError: null,
            createdAt: now.add(Duration(microseconds: index)),
            updatedAt: now.add(Duration(microseconds: index)),
          ),
        ),
      ),
    );

    expect(await database.loadPendingSync('account-1'), hasLength(1));
  });

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

    final pending = await database.loadPendingSync(card.accountId);
    final cardMutation = pending.singleWhere(
      (item) => item.objectType == 'CARD',
    );
    final deckMutation = pending.singleWhere(
      (item) => item.objectType == 'DECK',
    );
    final payload = jsonDecode(cardMutation.payload) as Map<String, dynamic>;
    final deckPayload =
        jsonDecode(deckMutation.payload) as Map<String, dynamic>;
    expect(pending, hasLength(2));
    expect(payload['reviews'], 1);
    expect(payload['deckEpoch'], 1);
    expect(payload['syncMode'], 'progress');
    expect(payload.containsKey('progressReset'), isFalse);
    expect(deckPayload['syncAction'], 'DECK_RELEARN');
    expect(deckPayload['resetEpoch'], 1);
  });

  test('review status maps legacy values to the two visible states', () {
    final card = _buildReviewCard(DateTime(2026, 8, 1));

    expect(card.copyWith(mastery: masteredCardMastery).isMastered, isTrue);
    expect(card.copyWith(mastery: 'familiar').isMastered, isTrue);
    expect(card.copyWith(mastery: 'tooEasy').isMastered, isTrue);
    expect(card.copyWith(mastery: 'forgot').isMastered, isFalse);
    expect(card.copyWith(mastery: 'fuzzy').isMastered, isFalse);
    expect(card.copyWith(mastery: '').reviewStatusLabel, '复习中');
  });

  test(
    'manual mastery toggles due time and coalesces its card mutation',
    () async {
      final card = _buildReviewCard(DateTime(2026, 8, 1));
      final repository = ContentRepository(database);

      final mastered = await repository.setCardReviewStatus(
        card: card,
        mastered: true,
      );
      expect(mastered.mastery, masteredCardMastery);
      expect(mastered.dueAt, DateTime(9999, 12, 31, 23, 59, 59));
      expect(mastered.isDue, isFalse);

      final reviewing = await repository.setCardReviewStatus(
        card: mastered,
        mastered: false,
      );
      expect(reviewing.mastery, reviewingCardMastery);
      expect(reviewing.isDue, isTrue);

      final pending = await database.loadPendingSync(card.accountId);
      expect(pending, hasLength(1));
      final payload =
          jsonDecode(pending.single.payload) as Map<String, dynamic>;
      expect(payload['mastery'], reviewingCardMastery);
      expect(payload['dueAt'], reviewing.dueAt.toIso8601String());
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
      content: 'Review information at increasing intervals.',
      noteContent: '',
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
    expect(payload['content'], card.content);
    expect(payload['noteContent'], card.noteContent);
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
    'market re-download replaces a deck tombstone with an explicit restore',
    () async {
      final repository = ContentRepository(database);
      final first = _buildImportCard('market-deck-restore-1', 'first');
      final second = _buildImportCard('market-deck-restore-2', 'second');

      await repository.importCards(
        'account-1',
        [first, second],
        deckId: 'market-deck-restore',
        deckTitle: first.folder,
        deckVersion: 1,
        restoreDeleted: true,
      );
      await repository.deleteDeck(accountId: 'account-1', folder: first.folder);
      expect(
        (await database.loadPendingSync('account-1')).single.operation,
        SyncOperation.delete,
      );

      await repository.importCards(
        'account-1',
        [first, second],
        deckId: 'market-deck-restore',
        deckTitle: first.folder,
        deckVersion: 1,
        restoreDeleted: true,
      );

      final pending = await database.loadPendingSync('account-1');
      expect(pending, hasLength(3));
      expect(pending.first.objectType, 'DECK');
      expect(pending.first.operation, SyncOperation.upsert);
      final deckPayload =
          jsonDecode(pending.first.payload) as Map<String, dynamic>;
      expect(deckPayload['restoreDeleted'], true);
      expect(deckPayload['resetEpoch'], 0);
      expect(
        pending.skip(1).every((item) {
          final payload = jsonDecode(item.payload) as Map<String, dynamic>;
          return item.objectType == 'CARD' &&
              item.operation == SyncOperation.upsert &&
              payload['restoreDeleted'] == true;
        }),
        isTrue,
      );
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
        content: 'Original content',
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
      expect(saved.content, 'Original content');
      expect(saved.noteContent, 'Updated note');
      expect(saved.reviews, card.reviews);
      expect(payload['question'], 'Updated question');
      expect(payload['content'], 'Original content');
      expect(payload['noteContent'], 'Updated note');
      expect(queued.objectType, 'CARD');
      expect(queued.objectId, card.id);
      expect(queued.operation, SyncOperation.upsert);
    },
  );

  test(
    'reimporting a deck repairs legacy card positions without progress loss',
    () async {
      final repository = ContentRepository(database);
      final first = _buildImportCard(
        'market-deck-2-1',
        'first',
      ).copyWith(reviews: 4, mastery: 'familiar');
      final second = _buildImportCard('market-deck-2-2', 'second');
      await database.saveCards([first, second]);

      final result = await repository.importCards('account-1', [
        first.copyWith(sortOrder: 2),
        second.copyWith(sortOrder: 1),
      ]);

      final saved = await database.loadCards('account-1');
      final pending = await database.loadPendingSync('account-1');
      expect(result.imported, 0);
      expect(result.updated, 2);
      expect(result.skipped, 0);
      expect(saved.firstWhere((card) => card.id == first.id).sortOrder, 2);
      expect(saved.firstWhere((card) => card.id == first.id).reviews, 4);
      expect(
        saved.firstWhere((card) => card.id == first.id).mastery,
        'familiar',
      );
      // Order is derived from the downloaded package and is repaired locally;
      // it must not create one CARD mutation per existing card.
      expect(pending, isEmpty);
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
    content: '',
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
    content: '',
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
  content: 'Note',
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
