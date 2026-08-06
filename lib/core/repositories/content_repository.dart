import 'dart:convert';

import '../database/app_database.dart';
import '../models/card_model.dart';
import '../models/document_model.dart';

class ContentRepository {
  ContentRepository(this.database);

  final AppDatabase database;

  Future<List<CardModel>> cards(String accountId) async {
    final values = await database.loadCards(accountId);
    if (values.isNotEmpty) return values;
    return const [];
  }

  Future<List<DocumentModel>> documents(String accountId) async {
    final values = await database.loadDocuments(accountId);
    if (values.isNotEmpty) return values;
    return const [];
  }

  Future<void> createCard(CardModel card) async {
    final now = DateTime.now();
    await database.transaction(() async {
      await database.saveCard(card);
      await database.enqueueSync(
        SyncQueueItemModel(
          id: 'card-upsert-${card.id}',
          accountId: card.accountId,
          objectType: 'CARD',
          objectId: card.id,
          objectVersion: 1,
          operation: SyncOperation.upsert,
          payload: jsonEncode(_cardSyncPayload(card)),
          status: SyncItemStatus.pending,
          attempts: 0,
          lastError: null,
          createdAt: now,
          updatedAt: now,
        ),
      );
    });
  }

  Future<void> saveReview({
    required CardModel card,
    required ReviewEventModel event,
  }) async {
    await database.transaction(() async {
      await database.saveCard(card);
      await database.saveReviewEvent(event);
      await database.enqueueSync(
        SyncQueueItemModel(
          id: 'review-${event.id}',
          accountId: event.accountId,
          objectType: 'CARD',
          objectId: card.id,
          objectVersion: card.reviews,
          operation: SyncOperation.upsert,
          payload: jsonEncode({
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
            'eventId': event.id,
            'lastRating': event.rating.name,
            'reviewedAt': event.reviewedAt.toIso8601String(),
            'nextDue': event.nextDue.toIso8601String(),
          }),
          status: SyncItemStatus.pending,
          attempts: 0,
          lastError: null,
          createdAt: event.reviewedAt,
          updatedAt: event.reviewedAt,
        ),
      );
    });
  }

  Future<void> deleteCard({
    required String accountId,
    required String cardId,
  }) async {
    final now = DateTime.now();
    await database.transaction(() async {
      await database.deleteCard(cardId, accountId);
      await database.deleteReviewEventsByCard(cardId, accountId);
      await database.enqueueSync(
        SyncQueueItemModel(
          id: 'delete-card-$cardId-${now.microsecondsSinceEpoch}',
          accountId: accountId,
          objectType: 'CARD',
          objectId: cardId,
          objectVersion: 1,
          operation: SyncOperation.delete,
          payload: '',
          status: SyncItemStatus.pending,
          attempts: 0,
          lastError: null,
          createdAt: now,
          updatedAt: now,
        ),
      );
    });
  }

  Future<int> deleteDeck({
    required String accountId,
    required String folder,
  }) async {
    final isUncategorized = folder.trim().isEmpty || folder == '未分类';
    final cards = (await database.loadCards(accountId))
        .where(
          (card) => isUncategorized
              ? card.folder.trim().isEmpty
              : card.folder == folder,
        )
        .toList();
    final now = DateTime.now();
    await database.transaction(() async {
      await database.deleteCardsByFolder(
        isUncategorized ? '' : folder,
        accountId,
      );
      for (final card in cards) {
        await database.deleteReviewEventsByCard(card.id, accountId);
        await database.enqueueSync(
          SyncQueueItemModel(
            id: 'delete-card-${card.id}-${now.microsecondsSinceEpoch}',
            accountId: accountId,
            objectType: 'CARD',
            objectId: card.id,
            objectVersion: 1,
            operation: SyncOperation.delete,
            payload: '',
            status: SyncItemStatus.pending,
            attempts: 0,
            lastError: null,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    });
    return cards.length;
  }

  Future<int> relearnDeck({
    required String accountId,
    required String folder,
  }) async {
    final cards = (await database.loadCards(
      accountId,
    )).where((card) => card.folder == folder).toList();
    if (cards.isEmpty) return 0;

    final now = DateTime.now();
    await database.transaction(() async {
      for (final card in cards) {
        final reset = card.copyWith(
          dueAt: now,
          updatedAt: now,
          reviews: 0,
          mastery: '',
          fsrs: FsrsSnapshot(
            state: FsrsState.newCard,
            dueAt: now,
            stability: 0,
            difficulty: 5,
            reps: 0,
            lapses: 0,
          ),
        );
        await database.saveCard(reset);
        await database.deleteReviewEventsByCard(card.id, accountId);
        await database.enqueueSync(
          SyncQueueItemModel(
            id: 'relearn-card-${card.id}-${now.microsecondsSinceEpoch}',
            accountId: accountId,
            objectType: 'CARD',
            objectId: card.id,
            objectVersion: now.millisecondsSinceEpoch,
            operation: SyncOperation.upsert,
            payload: jsonEncode(_cardSyncPayload(reset)),
            status: SyncItemStatus.pending,
            attempts: 0,
            lastError: null,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    });
    return cards.length;
  }

  Map<String, dynamic> _cardSyncPayload(CardModel card) => {
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
}
