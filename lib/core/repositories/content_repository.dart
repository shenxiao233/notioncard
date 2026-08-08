import 'dart:convert';

import '../database/app_database.dart';
import '../models/card_model.dart';
import '../models/document_model.dart';
import '../sync/sync_payload.dart';

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
          payload: jsonEncode(cardSyncPayload(card)),
          status: SyncItemStatus.pending,
          attempts: 0,
          lastError: null,
          createdAt: now,
          updatedAt: now,
        ),
      );
    });
  }

  Future<CardImportResult> importCards(
    String accountId,
    Iterable<CardModel> values,
  ) async {
    final incoming = <CardModel>[];
    final incomingIds = <String>{};
    for (final card in values) {
      if (card.accountId == accountId && incomingIds.add(card.id)) {
        incoming.add(card);
      }
    }
    if (incoming.isEmpty) return const CardImportResult();

    final existingIds = (await database.loadCards(
      accountId,
    )).map((card) => card.id).toSet();
    final cards = incoming
        .where((card) => !existingIds.contains(card.id))
        .toList();
    if (cards.isEmpty) {
      return CardImportResult(skipped: incoming.length);
    }

    final now = DateTime.now();
    await database.transaction(() async {
      await database.saveCards(cards);
      await database.enqueueSyncItems(
        cards.map(
          (card) => SyncQueueItemModel(
            id: 'card-upsert-${card.id}',
            accountId: card.accountId,
            objectType: 'CARD',
            objectId: card.id,
            objectVersion: 1,
            operation: SyncOperation.upsert,
            payload: jsonEncode(cardSyncPayload(card)),
            status: SyncItemStatus.pending,
            attempts: 0,
            lastError: null,
            createdAt: now,
            updatedAt: now,
          ),
        ),
      );
    });
    return CardImportResult(
      imported: cards.length,
      skipped: incoming.length - cards.length,
    );
  }

  Future<void> updateCard(CardModel card) async {
    final now = DateTime.now();
    final progressReset = await _pendingProgressReset(card.accountId, card.id);
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
          payload: jsonEncode(
            cardSyncPayload(card, progressReset: progressReset),
          ),
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
    final progressReset = await _pendingProgressReset(card.accountId, card.id);
    await database.transaction(() async {
      await database.saveCard(card);
      await database.saveReviewEvent(event);
      await database.enqueueSync(
        SyncQueueItemModel(
          // One pending snapshot per card is enough. The latest local FSRS
          // state supersedes older review snapshots until the next upload.
          id: 'card-upsert-${card.id}',
          accountId: event.accountId,
          objectType: 'CARD',
          objectId: card.id,
          // objectVersion is the last known server version. The coordinator
          // falls back to version 1 when this card has not been pulled yet.
          objectVersion: 1,
          operation: SyncOperation.upsert,
          payload: jsonEncode({
            ...cardSyncPayload(card, progressReset: progressReset),
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
    final normalizedFolder = folder.trim();
    final cards = (await database.loadCards(
      accountId,
    )).where((card) => card.folder.trim() == normalizedFolder).toList();
    if (cards.isEmpty) return 0;

    final now = DateTime.now();
    final resets = cards
        .map(
          (card) => card.copyWith(
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
          ),
        )
        .toList();
    await database.transaction(() async {
      await database.saveCards(resets);
      await database.deleteReviewEventsByCards(
        accountId,
        resets.map((card) => card.id),
      );
      await database.enqueueSyncItems(
        resets.map(
          (reset) => SyncQueueItemModel(
            // Relearn replaces any previous review/update snapshot for this
            // card instead of adding another upload task.
            id: 'card-upsert-${reset.id}',
            accountId: accountId,
            objectType: 'CARD',
            objectId: reset.id,
            objectVersion: 1,
            operation: SyncOperation.upsert,
            payload: jsonEncode(cardSyncPayload(reset, progressReset: true)),
            status: SyncItemStatus.pending,
            attempts: 0,
            lastError: null,
            createdAt: now,
            updatedAt: now,
          ),
        ),
      );
    });
    return cards.length;
  }

  Future<bool> _pendingProgressReset(String accountId, String cardId) async {
    final item = await database.loadPendingSyncItem(
      accountId,
      objectType: 'CARD',
      objectId: cardId,
    );
    if (item == null || item.operation != SyncOperation.upsert) return false;
    try {
      final payload = jsonDecode(item.payload);
      return payload is Map && payload['progressReset'] == true;
    } catch (_) {
      return false;
    }
  }
}

class CardImportResult {
  const CardImportResult({this.imported = 0, this.skipped = 0});

  final int imported;
  final int skipped;
}
