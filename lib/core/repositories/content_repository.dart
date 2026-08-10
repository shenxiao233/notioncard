import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../models/card_model.dart';
import '../models/document_model.dart';
import '../sync/sync_payload.dart';

class ContentRepository {
  ContentRepository(this.database, {this.preferences});

  final AppDatabase database;
  final SharedPreferences? preferences;
  final Random _mutationRandom = Random.secure();
  final Map<String, String> _deckIds = {};

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
          id: _mutationId('card-upsert', card.id, now),
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
    Iterable<CardModel> values, {
    String? deckId,
    String? deckTitle,
    int? deckVersion,
  }) async {
    final incoming = <CardModel>[];
    final incomingIds = <String>{};
    for (final card in values) {
      if (card.accountId == accountId && incomingIds.add(card.id)) {
        incoming.add(card);
      }
    }
    if (incoming.isEmpty) return const CardImportResult();
    if (deckId != null && deckId.trim().isNotEmpty) {
      await _rememberDeckId(accountId, deckTitle ?? '', deckId);
    }

    final existingCards = await database.loadCards(accountId);
    final existingById = {for (final card in existingCards) card.id: card};
    final cards = <CardModel>[];
    final reordered = <CardModel>[];
    for (final card in incoming) {
      final existing = existingById[card.id];
      if (existing == null) {
        cards.add(card);
      } else if (card.sortOrder != null &&
          card.sortOrder != existing.sortOrder) {
        // Re-downloading a deck also repairs cards imported by an older app
        // version that had no durable source-order field. Keep all content
        // and FSRS progress from the local card; only update its position.
        reordered.add(existing.copyWith(sortOrder: card.sortOrder));
      }
    }
    final changedCards = [...cards, ...reordered];
    if (changedCards.isEmpty) {
      return CardImportResult(skipped: incoming.length);
    }

    final now = DateTime.now();
    await database.transaction(() async {
      await database.saveCards(changedCards);
      // Sort order is derived from the downloaded deck package. Repairing a
      // legacy local order must not turn into one CARD mutation per card.
      // New cards still need their content uploaded, while order-only repairs
      // stay local and are picked up by the next normal card edit if needed.
      if (cards.isNotEmpty) {
        await database.enqueueSyncItems(
          cards.map(
            (card) => SyncQueueItemModel(
              id: _mutationId('card-upsert', card.id, now),
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
      }
      if (cards.isNotEmpty && deckId != null && deckId.trim().isNotEmpty) {
        await database.enqueueSync(
          SyncQueueItemModel(
            id: _mutationId('deck-upsert', deckId, now),
            accountId: accountId,
            objectType: 'DECK',
            objectId: deckId,
            objectVersion: 1,
            operation: SyncOperation.upsert,
            payload: jsonEncode({
              'id': deckId,
              'title': deckTitle ?? '',
              'folder': deckTitle ?? '',
              'version': deckVersion,
              'cardCount': incoming.length,
              'updatedAt': now.toIso8601String(),
            }),
            status: SyncItemStatus.pending,
            attempts: 0,
            lastError: null,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    });
    return CardImportResult(
      imported: cards.length,
      skipped: incoming.length - cards.length - reordered.length,
      updated: reordered.length,
    );
  }

  Future<void> updateCard(CardModel card) async {
    final now = DateTime.now();
    final progressReset = await _pendingProgressReset(card.accountId, card.id);
    await database.transaction(() async {
      await database.saveCard(card);
      await database.enqueueSync(
        SyncQueueItemModel(
          id: _mutationId('card-upsert', card.id, now),
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
    final now = event.reviewedAt;
    final progressReset = await _pendingProgressReset(card.accountId, card.id);
    await database.transaction(() async {
      await database.saveCard(card);
      await database.saveReviewEvent(event);
      await database.enqueueSync(
        SyncQueueItemModel(
          // One pending snapshot per card is enough. The latest local FSRS
          // state supersedes older review snapshots until the next upload.
          id: _mutationId('card-upsert', card.id, now),
          accountId: event.accountId,
          objectType: 'CARD',
          objectId: card.id,
          // objectVersion is the last known server version. The coordinator
          // falls back to version 1 when this card has not been pulled yet.
          objectVersion: 1,
          operation: SyncOperation.upsert,
          payload: jsonEncode({
            ...cardSyncPayload(
              card,
              progressReset: progressReset,
              progressOnly: true,
            ),
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
          id: _mutationId('card-delete', cardId, now),
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

  Future<void> renameDocument({
    required DocumentModel document,
    required String title,
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', '文档名称不能为空');
    }
    if (normalizedTitle == document.title.trim()) return;

    final now = DateTime.now();
    final renamed = DocumentModel(
      id: document.id,
      accountId: document.accountId,
      folder: document.folder,
      title: normalizedTitle,
      body: document.body,
      updatedAt: now,
    );
    await database.transaction(() async {
      await database.saveDocument(renamed);
      await database.enqueueSync(
        SyncQueueItemModel(
          id: _mutationId('document-upsert', document.id, now),
          accountId: document.accountId,
          objectType: 'DOCUMENT',
          objectId: document.id,
          objectVersion: 1,
          operation: SyncOperation.upsert,
          payload: jsonEncode(_documentSyncPayload(renamed)),
          status: SyncItemStatus.pending,
          attempts: 0,
          lastError: null,
          createdAt: now,
          updatedAt: now,
        ),
      );
    });
  }

  Future<void> deleteDocument({
    required String accountId,
    required String documentId,
  }) async {
    final now = DateTime.now();
    await database.transaction(() async {
      await database.deleteDocument(documentId, accountId);
      await database.enqueueSync(
        SyncQueueItemModel(
          id: _mutationId('document-delete', documentId, now),
          accountId: accountId,
          objectType: 'DOCUMENT',
          objectId: documentId,
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

  Future<int> renameDeck({
    required String accountId,
    required String folder,
    required String name,
  }) async {
    final oldFolder = _deckFolderValue(folder);
    final newFolder = name.trim();
    if (newFolder == folder.trim()) return 0;
    if (newFolder.isEmpty) {
      throw ArgumentError.value(name, 'name', '牌组名称不能为空');
    }
    if (newFolder == '未分类') {
      throw ArgumentError.value(name, 'name', '未分类是系统默认牌组名称');
    }
    if (oldFolder == newFolder) return 0;

    final cardCount = await database.countCardsByFolder(accountId, oldFolder);
    if (cardCount == 0) return 0;
    if (await database.countCardsByFolder(accountId, newFolder) > 0) {
      throw StateError('已有同名牌组');
    }

    final now = DateTime.now();
    final deckId = await _deckIdFor(accountId, oldFolder);
    final renameFrom =
        await _pendingDeckRenameFrom(accountId, deckId) ?? oldFolder;
    await _rememberDeckId(accountId, newFolder, deckId);
    await database.transaction(() async {
      await database.updateCardsFolder(
        accountId: accountId,
        fromFolder: oldFolder,
        toFolder: newFolder,
      );
      await database.updateReviewEventsFolder(
        accountId: accountId,
        fromFolder: oldFolder,
        toFolder: newFolder,
      );
      await database.enqueueSync(
        SyncQueueItemModel(
          id: _mutationId('deck-rename', deckId, now),
          accountId: accountId,
          objectType: 'DECK',
          objectId: deckId,
          objectVersion: 1,
          operation: SyncOperation.upsert,
          payload: jsonEncode({
            'id': deckId,
            'title': newFolder,
            'folder': newFolder,
            'renameFrom': renameFrom,
            'cardCount': cardCount,
            'updatedAt': now.toIso8601String(),
          }),
          status: SyncItemStatus.pending,
          attempts: 0,
          lastError: null,
          createdAt: now,
          updatedAt: now,
        ),
      );
    });
    return cardCount;
  }

  Future<int> deleteDeck({
    required String accountId,
    required String folder,
  }) async {
    final normalizedFolder = folder.trim();
    final isUncategorized =
        normalizedFolder.isEmpty || normalizedFolder == '未分类';
    final storedFolder = isUncategorized ? '' : normalizedFolder;
    final cards = (await database.loadCards(accountId))
        .where(
          (card) => isUncategorized
              ? card.folder.trim().isEmpty
              : card.folder == storedFolder,
        )
        .toList();
    if (cards.isEmpty) return 0;

    final now = DateTime.now();
    final deckId = await _deckIdFor(accountId, storedFolder);
    final cardIds = cards.map((card) => card.id).toSet();
    await database.transaction(() async {
      await database.deleteCardsByIds(accountId, cardIds);
      await database.deleteReviewEventsByCards(accountId, cardIds);
      // A deck delete supersedes every queued card mutation in that deck.
      // Leaving those rows behind would upload the cards after the deck
      // tombstone and recreate content that the user just removed.
      await database.discardPendingSyncItems(
        accountId,
        objectType: 'CARD',
        objectIds: cardIds,
      );
      await database.enqueueSync(
        SyncQueueItemModel(
          id: _mutationId('deck-delete', deckId, now),
          accountId: accountId,
          objectType: 'DECK',
          objectId: deckId,
          objectVersion: 1,
          operation: SyncOperation.delete,
          payload: jsonEncode({
            'id': deckId,
            'folder': storedFolder,
            'title': storedFolder,
            'cardCount': cards.length,
            'deletedAt': now.toIso8601String(),
          }),
          status: SyncItemStatus.pending,
          attempts: 0,
          lastError: null,
          createdAt: now,
          updatedAt: now,
        ),
      );
    });
    return cards.length;
  }

  Future<int> relearnDeck({
    required String accountId,
    required String folder,
  }) async {
    final totalTimer = Stopwatch()..start();
    final loadTimer = Stopwatch()..start();
    final normalizedFolder = folder.trim();
    final cards = (await database.loadCards(
      accountId,
    )).where((card) => card.folder.trim() == normalizedFolder).toList();
    loadTimer.stop();
    if (cards.isEmpty) return 0;

    final now = DateTime.now();
    final resetTimer = Stopwatch()..start();
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
    resetTimer.stop();
    final transactionTimer = Stopwatch()..start();
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
            id: _mutationId('card-upsert', reset.id, now),
            accountId: accountId,
            objectType: 'CARD',
            objectId: reset.id,
            objectVersion: 1,
            operation: SyncOperation.upsert,
            payload: jsonEncode(
              cardSyncPayload(reset, progressReset: true, progressOnly: true),
            ),
            status: SyncItemStatus.pending,
            attempts: 0,
            lastError: null,
            createdAt: now,
            updatedAt: now,
          ),
        ),
      );
    });
    transactionTimer.stop();
    totalTimer.stop();
    developer.log(
      'relearnDeck complete account=$accountId folder=$normalizedFolder '
      'cards=${cards.length} loadMs=${loadTimer.elapsedMilliseconds} '
      'resetMs=${resetTimer.elapsedMilliseconds} '
      'transactionMs=${transactionTimer.elapsedMilliseconds} '
      'totalMs=${totalTimer.elapsedMilliseconds}',
      name: 'ContentRepository.relearnDeck',
    );
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

  String _mutationId(String prefix, String objectId, DateTime at) =>
      '$prefix-$objectId-${at.microsecondsSinceEpoch}-${_mutationRandom.nextInt(1 << 32)}';
  Future<String> _deckIdFor(String accountId, String folder) async {
    final normalizedFolder = folder.trim();
    final key = _deckNameKey(accountId, normalizedFolder);
    final cached = _deckIds[key] ?? preferences?.getString(key);
    if (cached != null && cached.trim().isNotEmpty) {
      _deckIds[key] = cached;
      return cached;
    }
    final generated =
        'local-deck-' +
        base64UrlEncode(utf8.encode(accountId + '|' + normalizedFolder));
    _deckIds[key] = generated;
    await preferences?.setString(key, generated);
    return generated;
  }

  Future<void> _rememberDeckId(
    String accountId,
    String folder,
    String deckId,
  ) async {
    final normalizedDeckId = deckId.trim();
    if (normalizedDeckId.isEmpty) return;
    final key = _deckNameKey(accountId, folder);
    _deckIds[key] = normalizedDeckId;
    await preferences?.setString(key, normalizedDeckId);
  }

  Future<String?> _pendingDeckRenameFrom(
    String accountId,
    String deckId,
  ) async {
    final item = await database.loadPendingSyncItem(
      accountId,
      objectType: 'DECK',
      objectId: deckId,
    );
    if (item == null || item.operation != SyncOperation.upsert) return null;
    try {
      final payload = jsonDecode(item.payload);
      if (payload is Map && payload.containsKey('renameFrom')) {
        return payload['renameFrom']?.toString();
      }
    } catch (_) {
      // A malformed older queue item is safely replaced by the new snapshot.
    }
    return null;
  }

  String _deckNameKey(String accountId, String folder) =>
      'sync.deck.local.name.' +
      accountId +
      '.' +
      base64UrlEncode(utf8.encode(folder.trim()));

  String _deckFolderValue(String folder) {
    final value = folder.trim();
    return value == '未分类' ? '' : value;
  }

  Map<String, dynamic> _documentSyncPayload(DocumentModel document) => {
    'id': document.id,
    'folder': document.folder,
    'title': document.title,
    'body': document.body,
    'updatedAt': document.updatedAt.toIso8601String(),
  };
}

class CardImportResult {
  const CardImportResult({
    this.imported = 0,
    this.skipped = 0,
    this.updated = 0,
  });

  final int imported;
  final int skipped;
  final int updated;
}
