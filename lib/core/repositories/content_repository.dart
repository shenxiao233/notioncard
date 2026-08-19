import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../models/card_model.dart';
import '../models/card_highlight_model.dart';
import '../models/collection_model.dart';
import '../models/document_model.dart';
import '../sync/sync_payload.dart';

class ContentRepository {
  ContentRepository(this.database, {this.preferences});

  final AppDatabase database;
  final SharedPreferences? preferences;
  final Random _mutationRandom = Random.secure();
  final Map<String, String> _deckIds = {};
  final Map<String, int> _deckEpochs = {};

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

  Future<List<CollectionModel>> collections(String accountId) async {
    final stored = await database.loadCollections(accountId);
    final cards = await database.loadCards(accountId);
    final documents = await database.loadDocuments(accountId);
    final values = [...stored];
    final existing = {
      for (final value in values) '${value.type.name}:${value.name.trim()}',
    };
    final discovered = <CollectionModel>[];

    void discover(CollectionType type, String rawName, DateTime updatedAt) {
      final name = rawName.trim();
      if (name.isEmpty) return;
      final key = '${type.name}:$name';
      if (!existing.add(key)) return;
      discovered.add(
        CollectionModel(
          id: _collectionId(accountId, type, name),
          accountId: accountId,
          type: type,
          name: name,
          icon: type == CollectionType.deck ? 'style' : 'folder',
          color: type == CollectionType.deck ? 'blue' : 'green',
          archived: false,
          createdAt: updatedAt,
          updatedAt: updatedAt,
        ),
      );
    }

    for (final card in cards) {
      discover(CollectionType.deck, card.folder, card.updatedAt);
    }
    for (final document in documents) {
      discover(
        CollectionType.documentCategory,
        document.folder,
        document.updatedAt,
      );
    }
    if (discovered.isNotEmpty) {
      await database.saveCollections(discovered);
      values.addAll(discovered);
    }
    return values.where((value) => !value.archived).toList()
      ..sort((left, right) {
        final byType = left.type.index.compareTo(right.type.index);
        if (byType != 0) return byType;
        final byUpdated = right.updatedAt.compareTo(left.updatedAt);
        if (byUpdated != 0) return byUpdated;
        return left.name.compareTo(right.name);
      });
  }

  Future<CollectionModel> createCollection({
    required String accountId,
    required CollectionType type,
    required String name,
    String icon = 'folder',
    String color = 'green',
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', '名称不能为空');
    }
    final existing = await database.loadCollections(accountId);
    if (existing.any(
      (value) =>
          !value.archived &&
          value.type == type &&
          value.name.trim().toLowerCase() == normalizedName.toLowerCase(),
    )) {
      throw StateError(type == CollectionType.deck ? '已有同名牌组' : '已有同名文档类别');
    }

    final now = DateTime.now();
    final value = CollectionModel(
      id: _collectionId(accountId, type, normalizedName, unique: true),
      accountId: accountId,
      type: type,
      name: normalizedName,
      icon: icon,
      color: color,
      archived: false,
      createdAt: now,
      updatedAt: now,
    );
    await database.transaction(() async {
      await database.saveCollection(value);
      if (type == CollectionType.deck) {
        await _rememberDeckId(accountId, normalizedName, value.id);
      }
      await _enqueueCollectionMutation(value);
    });
    return value;
  }

  Future<CollectionModel> renameCollection({
    required CollectionModel collection,
    required String name,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', '名称不能为空');
    }
    if (normalizedName == collection.name.trim()) return collection;
    final existing = await database.loadCollections(collection.accountId);
    if (existing.any(
      (value) =>
          value.id != collection.id &&
          !value.archived &&
          value.type == collection.type &&
          value.name.trim().toLowerCase() == normalizedName.toLowerCase(),
    )) {
      throw StateError(
        collection.type == CollectionType.deck ? '已有同名牌组' : '已有同名文档类别',
      );
    }

    final now = DateTime.now();
    final renamed = collection.copyWith(name: normalizedName, updatedAt: now);
    await database.transaction(() async {
      if (collection.type == CollectionType.deck) {
        await database.updateCardsFolder(
          accountId: collection.accountId,
          fromFolder: collection.name,
          toFolder: normalizedName,
        );
        await database.updateReviewEventsFolder(
          accountId: collection.accountId,
          fromFolder: collection.name,
          toFolder: normalizedName,
        );
        await _rememberDeckId(
          collection.accountId,
          normalizedName,
          collection.id,
        );
      } else {
        final documents = await database.loadDocuments(collection.accountId);
        final movedDocuments = documents
            .where((document) => document.folder == collection.name)
            .map(
              (document) => DocumentModel(
                id: document.id,
                accountId: document.accountId,
                folder: normalizedName,
                title: document.title,
                body: document.body,
                updatedAt: now,
              ),
            )
            .toList();
        await database.saveDocuments(movedDocuments);
        for (final document in movedDocuments) {
          await _enqueueDocumentMutation(document);
        }
      }
      await database.saveCollection(renamed);
      await _enqueueCollectionMutation(renamed, renameFrom: collection.name);
    });
    return renamed;
  }

  Future<CollectionModel> archiveCollection(CollectionModel collection) async {
    if (collection.archived) return collection;
    final archived = collection.copyWith(
      archived: true,
      updatedAt: DateTime.now(),
    );
    await database.transaction(() async {
      await database.saveCollection(archived);
      await _enqueueCollectionMutation(archived);
    });
    return archived;
  }

  Future<void> createCard(CardModel card) async {
    final now = DateTime.now();
    final cardToSave = card.sortOrder == null
        ? card.copyWith(
            sortOrder: await database.nextCardSortOrder(
              card.accountId,
              card.folder,
            ),
          )
        : card;
    final deckId = await _deckIdFor(card.accountId, card.folder);
    final deckEpoch = _deckEpochFor(card.accountId, deckId);
    await database.transaction(() async {
      await database.saveCard(cardToSave);
      await database.enqueueSync(
        SyncQueueItemModel(
          id: _mutationId('card-upsert', cardToSave.id, now),
          accountId: cardToSave.accountId,
          objectType: 'CARD',
          objectId: cardToSave.id,
          objectVersion: 1,
          operation: SyncOperation.upsert,
          payload: jsonEncode(
            cardSyncPayload(cardToSave, deckId: deckId, deckEpoch: deckEpoch),
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

  Future<DocumentModel> createDocument({
    required String accountId,
    required String title,
    required String body,
    String folder = '',
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', '鏂囨。鍚嶇О涓嶈兘涓虹┖');
    }

    final normalizedFolder = folder.trim();
    final now = DateTime.now();
    final id = 'local-document-${now.microsecondsSinceEpoch}';
    final document = DocumentModel(
      id: id,
      accountId: accountId,
      folder: normalizedFolder,
      title: normalizedTitle,
      body: body.trim(),
      updatedAt: now,
    );
    await database.transaction(() async {
      await database.saveDocument(document);
      await database.enqueueSync(
        SyncQueueItemModel(
          id: _mutationId('document-upsert', id, now),
          accountId: accountId,
          objectType: 'DOCUMENT',
          objectId: id,
          objectVersion: 1,
          operation: SyncOperation.upsert,
          payload: jsonEncode(_documentSyncPayload(document)),
          status: SyncItemStatus.pending,
          attempts: 0,
          lastError: null,
          createdAt: now,
          updatedAt: now,
        ),
      );
    });
    return document;
  }

  Future<CardImportResult> importCards(
    String accountId,
    Iterable<CardModel> values, {
    String? deckId,
    String? deckTitle,
    int? deckVersion,
    bool restoreDeleted = false,
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
    final nextSortOrderByFolder = <String, int>{};
    final preparedCards = <CardModel>[];
    for (final card in cards) {
      final folder = card.folder;
      final nextSortOrder =
          nextSortOrderByFolder[folder] ??= await database.nextCardSortOrder(
            accountId,
            folder,
          );
      nextSortOrderByFolder[folder] = nextSortOrder + 1;
      preparedCards.add(card.copyWith(sortOrder: nextSortOrder));
    }
    final changedCards = [...preparedCards, ...reordered];
    if (changedCards.isEmpty) {
      return CardImportResult(skipped: incoming.length);
    }

    final now = DateTime.now();
    final importDeckId = deckId?.trim().isNotEmpty == true
        ? deckId!.trim()
        : await _deckIdFor(accountId, deckTitle ?? '');
    final importEpoch = _deckEpochFor(accountId, importDeckId);
    final deckMutationAt = now;
    final cardMutationAt = now.add(const Duration(microseconds: 1));
    await database.transaction(() async {
      await database.saveCards(changedCards);
      // Queue the deck snapshot before its cards. A re-download may be
      // restoring a server tombstone; restoring the deck first recreates the
      // deck epoch before card progress is accepted by the server.
      if (preparedCards.isNotEmpty && deckId != null && deckId.trim().isNotEmpty) {
        await database.enqueueSync(
          SyncQueueItemModel(
            id: _mutationId('deck-upsert', deckId, deckMutationAt),
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
              'updatedAt': deckMutationAt.toIso8601String(),
              if (restoreDeleted) 'restoreDeleted': true,
              if (restoreDeleted) 'resetEpoch': importEpoch,
            }),
            status: SyncItemStatus.pending,
            attempts: 0,
            lastError: null,
            createdAt: deckMutationAt,
            updatedAt: deckMutationAt,
          ),
        );
      }
      // Sort order is derived from the downloaded deck package. Repairing a
      // legacy local order must not turn into one CARD mutation per card.
      // New cards still need their content uploaded, while order-only repairs
      // stay local and are picked up by the next normal card edit if needed.
      if (preparedCards.isNotEmpty) {
        await database.enqueueSyncItems(
          preparedCards.map(
            (card) => SyncQueueItemModel(
              id: _mutationId('card-upsert', card.id, cardMutationAt),
              accountId: card.accountId,
              objectType: 'CARD',
              objectId: card.id,
              objectVersion: 1,
              operation: SyncOperation.upsert,
              payload: jsonEncode(
                cardSyncPayload(
                  card,
                  deckId: importDeckId,
                  deckEpoch: importEpoch,
                  restoreDeleted: restoreDeleted,
                ),
              ),
              status: SyncItemStatus.pending,
              attempts: 0,
              lastError: null,
              createdAt: cardMutationAt,
              updatedAt: cardMutationAt,
            ),
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
    final deckId = await _deckIdFor(card.accountId, card.folder);
    final deckEpoch = _deckEpochFor(card.accountId, deckId);
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
            cardSyncPayload(
              card,
              progressReset: progressReset,
              deckId: deckId,
              deckEpoch: deckEpoch,
            ),
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

  Future<CardModel> setCardReviewStatus({
    required CardModel card,
    required bool mastered,
  }) async {
    final now = DateTime.now();
    // A manual mastery mark is a deliberate opt-out from the active review
    // queue. Keep it as a normal card snapshot so it is synced to other
    // devices, but place it far enough in the future to avoid an immediate
    // reappearance as an overdue card.
    final dueAt = mastered ? DateTime(9999, 12, 31, 23, 59, 59) : now;
    final updated = card.copyWith(
      dueAt: dueAt,
      updatedAt: now,
      mastery: mastered ? masteredCardMastery : reviewingCardMastery,
      fsrs: FsrsSnapshot(
        state: card.fsrs.state,
        dueAt: dueAt,
        stability: card.fsrs.stability,
        difficulty: card.fsrs.difficulty,
        reps: card.fsrs.reps,
        lapses: card.fsrs.lapses,
      ),
    );
    await updateCard(updated);
    return updated;
  }

  Future<void> saveReview({
    required CardModel card,
    required ReviewEventModel event,
  }) async {
    final now = event.reviewedAt;
    final progressReset = await _pendingProgressReset(card.accountId, card.id);
    final deckId = await _deckIdFor(card.accountId, card.folder);
    final deckEpoch = _deckEpochFor(card.accountId, deckId);
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
              deckId: deckId,
              deckEpoch: deckEpoch,
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
      await database.deleteHighlightsByCard(accountId, cardId);
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
    final pendingDeckPayload = await _pendingDeckPayload(accountId, deckId);
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
            ...?pendingDeckPayload,
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
      for (final cardId in cardIds) {
        await database.deleteHighlightsByCard(accountId, cardId);
      }
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

  Future<List<CardHighlightModel>> loadCardHighlights(
    String accountId,
    String cardId,
  ) =>
      database.loadCardHighlights(accountId, cardId: cardId);

  Future<CardHighlightModel> addCardHighlight(CardHighlightModel highlight) async {
    await database.saveCardHighlight(highlight);
    return highlight;
  }

  Future<void> removeCardHighlight({
    required String accountId,
    required String highlightId,
  }) =>
      database.deleteCardHighlight(accountId, highlightId);

  Future<int> relearnDeck({
    required String accountId,
    required String folder,
  }) async {
    final totalTimer = Stopwatch()..start();
    final normalizedFolder = folder.trim();
    final deckId = await _deckIdFor(accountId, normalizedFolder);
    final previousPayload = await _pendingDeckPayload(accountId, deckId);
    final existingEpoch = _deckEpochFor(accountId, deckId);
    final queuedEpoch = previousPayload?['resetEpoch'] is num
        ? (previousPayload!['resetEpoch'] as num).toInt()
        : int.tryParse(previousPayload?['resetEpoch']?.toString() ?? '') ?? 0;
    final nextEpoch = [
      existingEpoch + 1,
      queuedEpoch + 1,
    ].reduce((left, right) => left > right ? left : right);
    final epochKey = _deckEpochKey(accountId, deckId);
    _deckEpochs[epochKey] = nextEpoch;
    await preferences?.setInt(epochKey, nextEpoch);
    final now = DateTime.now();
    final transactionTimer = Stopwatch()..start();
    var cardCount = 0;
    await database.transaction(() async {
      cardCount = await database.resetDeckProgress(
        accountId: accountId,
        folder: normalizedFolder,
        dueAt: now,
      );
      await database.discardPendingCardSyncByFolder(
        accountId: accountId,
        folder: normalizedFolder,
      );
      if (cardCount == 0) return;
      await database.enqueueSync(
        SyncQueueItemModel(
          id: _mutationId('deck-relearn', deckId, now),
          accountId: accountId,
          objectType: 'DECK',
          objectId: deckId,
          objectVersion: 1,
          operation: SyncOperation.upsert,
          payload: jsonEncode({
            ...?previousPayload,
            'id': deckId,
            'title': normalizedFolder,
            'folder': normalizedFolder,
            'cardCount': cardCount,
            'syncAction': 'DECK_RELEARN',
            'resetEpoch': nextEpoch,
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
    transactionTimer.stop();
    totalTimer.stop();
    developer.log(
      'relearnDeck complete account=$accountId folder=$normalizedFolder '
      'cards=$cardCount epoch=$nextEpoch '
      'transactionMs=${transactionTimer.elapsedMilliseconds} '
      'totalMs=${totalTimer.elapsedMilliseconds}',
      name: 'ContentRepository.relearnDeck',
    );
    return cardCount;
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

  String _collectionId(
    String accountId,
    CollectionType type,
    String name, {
    bool unique = false,
  }) {
    if (unique) {
      return 'local-collection-${type == CollectionType.deck ? 'deck' : 'doc'}-'
          '${DateTime.now().microsecondsSinceEpoch}-'
          '${_mutationRandom.nextInt(1 << 32)}';
    }
    final encoded = base64UrlEncode(
      utf8.encode('$accountId|${type.name}|${name.trim()}'),
    );
    return 'local-collection-${encoded.substring(0, encoded.length > 48 ? 48 : encoded.length)}';
  }

  Future<void> _enqueueCollectionMutation(
    CollectionModel value, {
    String? renameFrom,
  }) async {
    final payload = <String, dynamic>{
      'id': value.id,
      'name': value.name,
      'title': value.name,
      'folder': value.name,
      'collectionType': value.typeName,
      'icon': value.icon,
      'color': value.color,
      'archived': value.archived,
      'createdAt': value.createdAt.toIso8601String(),
      'updatedAt': value.updatedAt.toIso8601String(),
    };
    if (renameFrom != null) payload['renameFrom'] = renameFrom;
    await database.enqueueSync(
      SyncQueueItemModel(
        id: _mutationId('collection-upsert', value.id, value.updatedAt),
        accountId: value.accountId,
        objectType: 'DECK',
        objectId: value.id,
        objectVersion: 1,
        operation: SyncOperation.upsert,
        payload: jsonEncode(payload),
        status: SyncItemStatus.pending,
        attempts: 0,
        lastError: null,
        createdAt: value.updatedAt,
        updatedAt: value.updatedAt,
      ),
    );
  }

  Future<void> _enqueueDocumentMutation(DocumentModel document) async {
    await database.enqueueSync(
      SyncQueueItemModel(
        id: _mutationId('document-upsert', document.id, document.updatedAt),
        accountId: document.accountId,
        objectType: 'DOCUMENT',
        objectId: document.id,
        objectVersion: 1,
        operation: SyncOperation.upsert,
        payload: jsonEncode(_documentSyncPayload(document)),
        status: SyncItemStatus.pending,
        attempts: 0,
        lastError: null,
        createdAt: document.updatedAt,
        updatedAt: document.updatedAt,
      ),
    );
  }

  Future<String> _deckIdFor(String accountId, String folder) async {
    final normalizedFolder = folder.trim();
    final key = _deckNameKey(accountId, normalizedFolder);
    final cached = _deckIds[key] ?? preferences?.getString(key);
    if (cached != null && cached.trim().isNotEmpty) {
      _deckIds[key] = cached;
      return cached;
    }
    final generated =
        'local-deck-${base64UrlEncode(utf8.encode('$accountId|$normalizedFolder'))}';
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

  Future<Map<String, dynamic>?> _pendingDeckPayload(
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
      return payload is Map ? Map<String, dynamic>.from(payload) : null;
    } catch (_) {
      return null;
    }
  }

  String _deckNameKey(String accountId, String folder) =>
      'sync.deck.local.name.$accountId.${base64UrlEncode(utf8.encode(folder.trim()))}';

  String _deckEpochKey(String accountId, String deckId) =>
      'sync.deck.epoch.$accountId.$deckId';

  int _deckEpochFor(String accountId, String deckId) {
    final key = _deckEpochKey(accountId, deckId);
    return _deckEpochs[key] ??= preferences?.getInt(key) ?? 0;
  }

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
