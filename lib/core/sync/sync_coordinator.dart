import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../models/card_model.dart';
import '../models/document_model.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import 'sync_payload.dart';
import '../utils/rich_text.dart';

class SyncCoordinator {
  SyncCoordinator(this.database, {this.apiClient, this.preferences});

  static const _supportedObjectTypes = {'DECK', 'DOCUMENT', 'CARD', 'SETTINGS'};
  static const _lastSyncKey = 'sync.last_sync';
  static const _fullSyncVersionKey = 'sync.full_sync_version';
  // The saved value is a completed high-water timestamp, never an in-flight
  // pagination cursor. Version 2 stored the opaque cursor itself and must be
  // invalidated once so it cannot hide changes made after that cursor.
  static const _fullSyncVersion = '3';
  // Keep these in lockstep with the server's SYNC_BATCH_MAX. Only mutations
  // that are known to be progress-only are sent in the larger batch; a first
  // upload may still contain the complete card body and must stay smaller.
  static const _fullBatchSize = 50;
  static const _progressBatchSize = 200;
  // The server supports up to 500 objects per pull page. Keeping the page
  // size explicit avoids an unnecessary extra round trip on a first sync.
  static const _fullSyncPageSize = 500;
  static const _maxBatchAttempts = 3;
  static const _batchRetryBaseMs = 150;

  final AppDatabase database;
  final ApiClient? apiClient;
  final SharedPreferences? preferences;
  final Random _mutationRandom = Random.secure();
  // SharedPreferences is a platform bridge. Persisting one key per card made
  // a first pull of a large deck spend seconds in thousands of bridge calls.
  // Keep the hot path in memory and persist one compact JSON map per account.
  final Map<String, Map<String, int>> _serverVersionCache = {};

  Future<List<SyncQueueItemModel>> pending(String accountId) {
    return database.loadPendingSync(accountId);
  }

  Future<int> pendingCount(String accountId) {
    return database.countPendingSync(accountId);
  }

  bool needsInitialFullSync(String accountId) {
    final lastSync = preferences?.getString(_lastSyncKeyFor(accountId));
    return lastSync == null || lastSync.trim().isEmpty;
  }

  Future<void> retryPending(String accountId) async {
    final items = await database.loadPendingSync(accountId);
    final failedItems = items
        .where((value) => value.status == SyncItemStatus.failed)
        .map(
          (item) => SyncQueueItemModel(
            id: item.id,
            accountId: item.accountId,
            objectType: item.objectType,
            objectId: item.objectId,
            operation: item.operation,
            payload: item.payload,
            status: SyncItemStatus.pending,
            attempts: item.attempts,
            lastError: null,
            createdAt: item.createdAt,
            updatedAt: DateTime.now(),
          ),
        )
        .toList();
    if (failedItems.isEmpty) return;
    await database.enqueueSyncItems(failedItems);
  }

  Future<SyncReport> sync(String accountId, {CancelToken? cancelToken}) =>
      pushPending(accountId, cancelToken: cancelToken);

  Future<SyncReport> pushPending(
    String accountId, {
    CancelToken? cancelToken,
  }) async {
    final client = apiClient;
    if (client == null) return const SyncReport();

    var synced = 0;
    var failed = 0;
    var conflicts = 0;
    var networkFailure = false;
    // A conflict can produce a merged local card that needs one more upload
    // with the server's current version. Allow that retry in the same sync so
    // a valid local review does not remain stuck as "waiting to upload".
    for (var pass = 0; pass < 3; pass++) {
      final items = await database.loadPendingSync(accountId);
      if (items.isEmpty) break;

      final groups = <String, List<SyncQueueItemModel>>{};
      final legacyItemIds = <String>[];
      for (final item in items) {
        if (!_supportedObjectTypes.contains(item.objectType)) {
          // Older builds queued review events separately. Review state is now
          // part of the CARD payload, so these legacy entries must not poison a
          // valid batch with an object type rejected by the server.
          legacyItemIds.add(item.id);
          continue;
        }
        groups
            .putIfAbsent(_objectKey(item.objectType, item.objectId), () => [])
            .add(item);
      }
      await database.markSyncItemsSynced(accountId, legacyItemIds);
      final latestItems = groups.values.map((items) => items.last).toList();
      if (latestItems.isEmpty) continue;
      final deviceId = await _deviceId();
      var queuedConflictRetry = false;

      final batchSize = _batchSizeFor(accountId, latestItems);
      for (var offset = 0; offset < latestItems.length; offset += batchSize) {
        final batch = latestItems.skip(offset).take(batchSize).toList();
        final batchGroups = <String, List<SyncQueueItemModel>>{
          for (final item in batch)
            _objectKey(item.objectType, item.objectId):
                groups[_objectKey(item.objectType, item.objectId)]!,
        };
        final batchTimer = Stopwatch()..start();
        try {
          final body = await _postBatchWithRetry(
            client,
            batch,
            accountId: accountId,
            deviceId: deviceId,
            cancelToken: cancelToken,
          );
          final responses = body['responses'] as List;
          final handled = <String>{};
          final syncedItemIds = <String>[];
          final retryItems = <SyncQueueItemModel>[];
          final batchServerVersions = <String, int>{};
          for (final raw in responses) {
            final result = _stringMap(raw);
            if (result == null) continue;
            final objectType = result['objectType']
                ?.toString()
                .trim()
                .toUpperCase();
            final objectId = result['objectId']?.toString().trim();
            if (objectType == null || objectType.isEmpty || objectId == null) {
              continue;
            }
            final key = _objectKey(objectType, objectId);
            final groupedItems = batchGroups[key];
            if (groupedItems == null) continue;
            handled.add(key);
            final serverVersion = _version(result['serverVersion']);
            if (serverVersion != null) {
              final versionKey = _serverVersionKey(
                accountId,
                objectType,
                objectId,
              );
              batchServerVersions[versionKey] = serverVersion;
              _serverVersionsFor(accountId)[versionKey] = serverVersion;
            }
            if (result['conflict'] == true) {
              conflicts++;
              if (_isRemoteDeletion(result)) {
                await _removeRemoteObject(
                  accountId,
                  objectType,
                  objectId,
                  result,
                );
              } else if (groupedItems.last.operation == SyncOperation.upsert) {
                final retry = await _mergeConflict(
                  accountId,
                  objectType,
                  objectId,
                  result,
                  localItem: groupedItems.last,
                  serverVersion: serverVersion,
                );
                if (retry != null) retryItems.add(retry);
              } else {
                await _applyRemotePayload(
                  accountId,
                  objectType,
                  result['data'],
                  fallbackId: objectId,
                );
              }
            } else if (groupedItems.last.operation == SyncOperation.upsert) {
              // A successful upload response normally contains only the
              // version. The local snapshot is already in SQLite, so writing
              // it again for every card turns a 200-card progress batch into
              // 200 redundant SQLite statements. Apply data only when the
              // server actually returned a payload.
              final acceptedData = result['data'];
              if (acceptedData != null) {
                await _applyRemotePayload(
                  accountId,
                  objectType,
                  acceptedData,
                  fallbackId: objectId,
                );
              }
            }
            for (final item in groupedItems) {
              synced++;
              syncedItemIds.add(item.id);
            }
          }
          await _saveServerVersions(accountId, batchServerVersions);
          await database.markSyncItemsSynced(accountId, syncedItemIds);
          if (retryItems.isNotEmpty) {
            await database.enqueueSyncItems(retryItems);
            queuedConflictRetry = true;
          }

          final failedByMessage = <String, List<SyncQueueItemModel>>{};
          final errors = body['errors'];
          if (errors is List) {
            for (final raw in errors) {
              final result = _stringMap(raw);
              if (result == null) continue;
              final objectType = result['objectType']
                  ?.toString()
                  .trim()
                  .toUpperCase();
              final objectId = result['objectId']?.toString().trim();
              if (objectType == null ||
                  objectType.isEmpty ||
                  objectId == null ||
                  objectId.isEmpty) {
                continue;
              }
              final key = _objectKey(objectType, objectId);
              final groupedItems = batchGroups[key];
              // A malformed/duplicate server entry must not cause the same
              // local mutation to be counted or updated twice.
              if (groupedItems == null || handled.contains(key)) continue;
              handled.add(key);
              final message = result['message']?.toString().trim();
              final errorMessage = message == null || message.isEmpty
                  ? 'Sync object could not be saved. Please retry.'
                  : message;
              failedByMessage
                  .putIfAbsent(errorMessage, () => [])
                  .addAll(groupedItems);
            }
          }
          for (final entry in failedByMessage.entries) {
            failed += entry.value.length;
            await database.markSyncFailedItems(
              accountId,
              entry.value,
              entry.key,
            );
          }

          final missingItems = <SyncQueueItemModel>[];
          for (final entry in batchGroups.entries) {
            if (handled.contains(entry.key)) continue;
            missingItems.addAll(entry.value);
          }
          failed += missingItems.length;
          await database.markSyncFailedItems(
            accountId,
            missingItems,
            'Server did not return a response for this item',
          );
        } on ApiException catch (error) {
          if (error.isNetworkFailure) {
            networkFailure = true;
            break;
          }
          final failedItems = batchGroups.values
              .expand((group) => group)
              .toList();
          failed += failedItems.length;
          await database.markSyncFailedItems(
            accountId,
            failedItems,
            error.message,
          );
        } finally {
          batchTimer.stop();
          developer.log(
            'pushPending batch account=$accountId offset=$offset '
            'items=${batch.length} batchSize=$batchSize '
            'durationMs=${batchTimer.elapsedMilliseconds}',
            name: 'SyncCoordinator',
          );
        }
      }
      if (networkFailure || !queuedConflictRetry) break;
    }
    developer.log(
      'pushPending complete account=$accountId synced=$synced failed=$failed '
      'conflicts=$conflicts networkFailure=$networkFailure',
      name: 'SyncCoordinator',
    );
    return SyncReport(
      synced: synced,
      failed: failed,
      conflicts: conflicts,
      networkFailure: networkFailure,
    );
  }

  Future<Map<String, dynamic>> _postBatchWithRetry(
    ApiClient client,
    List<SyncQueueItemModel> batch, {
    required String accountId,
    required String deviceId,
    CancelToken? cancelToken,
  }) async {
    final requestPayload = [
      for (final item in batch) _syncRequestPayload(accountId, item, deviceId),
    ];
    final canReplay = batch.every(
      (item) => item.id.trim().length >= 16 && item.id.trim().length <= 200,
    );

    for (var attempt = 0; ; attempt++) {
      try {
        final response = await client.post(
          '/api/v2/sync/batch',
          data: {'requests': requestPayload},
          cancelToken: cancelToken,
        );
        final body = _stringMap(response.data);
        final responses = body?['responses'];
        if (body == null || responses is! List) {
          throw const ApiException(
            statusCode: 502,
            message: 'Invalid sync response',
          );
        }
        if (canReplay &&
            attempt < _maxBatchAttempts - 1 &&
            _shouldRetryBatch(body)) {
          await _waitBeforeBatchRetry(attempt);
          continue;
        }
        return body;
      } on ApiException catch (error) {
        if (!canReplay ||
            attempt >= _maxBatchAttempts - 1 ||
            !_isRetryableBatchError(error)) {
          rethrow;
        }
        await _waitBeforeBatchRetry(attempt);
      }
    }
  }

  bool _shouldRetryBatch(Map<String, dynamic> body) {
    final errors = body['errors'];
    if (errors is! List || errors.isEmpty) return false;
    return errors.every((raw) {
      final error = _stringMap(raw);
      final message = error?['message']?.toString() ?? '';
      return _isRetryableSyncMessage(message);
    });
  }

  bool _isRetryableBatchError(ApiException error) {
    final status = error.statusCode;
    return status == 429 ||
        status == 500 ||
        status == 502 ||
        status == 503 ||
        status == 504 ||
        _isRetryableSyncMessage(error.message);
  }

  bool _isRetryableSyncMessage(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('busy') ||
        normalized.contains('temporarily') ||
        normalized.contains('retry') ||
        normalized.contains('timeout');
  }

  Future<void> _waitBeforeBatchRetry(int attempt) {
    final backoff = _batchRetryBaseMs * (1 << attempt);
    final jitter = _mutationRandom.nextInt(_batchRetryBaseMs);
    return Future<void>.delayed(Duration(milliseconds: backoff + jitter));
  }

  Future<FullSyncReport> fullSync(
    String accountId, {
    bool force = false,
    CancelToken? cancelToken,
  }) async {
    final client = apiClient;
    if (client == null) return const FullSyncReport();
    var cards = 0;
    var documents = 0;
    var decks = 0;
    var settings = 0;
    var hasRemoteContent = false;
    var hasMore = true;
    var page = 0;
    var opaqueCursorSeen = false;
    final storedSync = preferences?.getString(_lastSyncKeyFor(accountId));
    final storedVersion = preferences?.getString(
      '$_fullSyncVersionKey.$accountId',
    );
    String? cursor;
    String? legacyLastSync;
    if (!force && storedSync != null && storedSync.trim().isNotEmpty) {
      // Version 2 persisted a pagination cursor. Treat it as invalid and run
      // one safe full pull instead of sending the base64 cursor as a timestamp.
      if (storedVersion != '2') legacyLastSync = storedSync;
    }
    final protectedObjectKeys = {
      for (final item in await database.loadPendingSync(accountId))
        _objectKey(item.objectType.trim().toUpperCase(), item.objectId),
    };
    final cardsToSave = <String, CardModel>{};
    final documentsToSave = <String, DocumentModel>{};
    Map<String, CardModel>? localCardsById;
    Map<String, DocumentModel>? localDocumentsById;
    final serverVersions = <String, int>{};
    String? completedHighWaterAt;
    String? completedSyncWatermark;
    while (hasMore) {
      page++;
      if (page > 1000) {
        throw const ApiException(
          statusCode: 502,
          message: 'Full sync returned too many pages',
        );
      }
      final pageTimer = Stopwatch()..start();
      final queryParameters = <String, dynamic>{};
      queryParameters['limit'] = _fullSyncPageSize;
      if (cursor != null && cursor.trim().isNotEmpty) {
        queryParameters['cursor'] = cursor;
      } else if (legacyLastSync != null && legacyLastSync.trim().isNotEmpty) {
        queryParameters['lastSyncAt'] = legacyLastSync;
      }
      final response = await client.get(
        '/api/v2/sync/full',
        queryParameters: queryParameters,
        cancelToken: cancelToken,
      );
      final fetchDurationMs = pageTimer.elapsedMilliseconds;
      final body = _stringMap(response.data);
      final objects = body?['objects'];
      if (body == null || (objects != null && objects is! List)) {
        throw const ApiException(
          statusCode: 502,
          message: 'Invalid full sync response',
        );
      }
      final explicitHighWaterAt = body['highWaterAt']?.toString().trim();
      final pageHighWaterAt = (explicitHighWaterAt ?? body['syncTime'])
          ?.toString()
          .trim();
      if (explicitHighWaterAt != null && explicitHighWaterAt.isNotEmpty) {
        completedHighWaterAt = explicitHighWaterAt;
      }
      if (pageHighWaterAt != null && pageHighWaterAt.isNotEmpty) {
        completedSyncWatermark = pageHighWaterAt;
      }
      final remoteObjects = [
        ...(objects as List? ?? const <Object?>[]),
        ..._deletionObjects(body),
      ];
      for (final raw in remoteObjects.whereType<Map>()) {
        final object = _stringMap(raw);
        if (object == null) continue;
        final objectId = _objectId(object);
        final objectUpdatedAt = object['updatedAt'];
        final objectType = _objectType(object);
        if (objectId == null || objectType == null) continue;
        final serverVersion = _version(object['objectVersion']);
        if (serverVersion != null) {
          serverVersions[_serverVersionKey(accountId, objectType, objectId)] =
              serverVersion;
        }
        // Never let a pull overwrite a local mutation which is still waiting
        // to be uploaded. A relearn reset is a deliberate local change even if
        // the server still has a higher review count.
        if (protectedObjectKeys.contains(_objectKey(objectType, objectId))) {
          continue;
        }
        if (_isRemoteDeletion(object)) {
          cardsToSave.remove(objectId);
          documentsToSave.remove(objectId);
          await _removeRemoteObject(accountId, objectType, objectId, object);
          continue;
        }
        final payload = _payloadMap(object['data']);
        if (payload == null) continue;
        switch (objectType) {
          case 'CARD':
            final card = _cardFromPayload(
              accountId,
              payload,
              fallbackId: objectId,
              fallbackUpdatedAt: objectUpdatedAt,
            );
            if (card.id.isEmpty) continue;
            if (localCardsById == null) {
              final localCards = await database.loadCards(accountId);
              localCardsById = {
                for (final value in localCards) value.id: value,
              };
            }
            final localCard = localCardsById[card.id];
            final value = localCard == null
                ? card
                : _mergeCardProgress(localCard, card);
            cardsToSave[value.id] = value;
            localCardsById[value.id] = value;
            cards++;
            hasRemoteContent = true;
          case 'DOCUMENT':
            final document = _documentFromPayload(
              accountId,
              payload,
              fallbackId: objectId,
              fallbackUpdatedAt: objectUpdatedAt,
            );
            if (document.id.isEmpty) continue;
            if (localDocumentsById == null) {
              final localDocuments = await database.loadDocuments(accountId);
              localDocumentsById = {
                for (final value in localDocuments) value.id: value,
              };
            }
            final localDocument = localDocumentsById[document.id];
            final value = document.body.trim().isEmpty && localDocument != null
                ? DocumentModel(
                    id: document.id,
                    accountId: document.accountId,
                    folder: document.folder.isEmpty
                        ? localDocument.folder
                        : document.folder,
                    title: document.title.isEmpty
                        ? localDocument.title
                        : document.title,
                    body: localDocument.body,
                    updatedAt: document.updatedAt,
                  )
                : document;
            documentsToSave[value.id] = value;
            localDocumentsById[value.id] = value;
            documents++;
            hasRemoteContent = true;
          case 'DECK':
            await _saveDeckMetadata(accountId, objectId, payload);
            decks++;
            hasRemoteContent = true;
          case 'SETTINGS':
            await _applyRemoteSettings(accountId, payload);
            settings++;
            hasRemoteContent = true;
        }
      }
      await database.saveCards(cardsToSave.values);
      await database.saveDocuments(documentsToSave.values);
      cardsToSave.clear();
      documentsToSave.clear();
      developer.log(
        'fullSync page=$page objects=${remoteObjects.length} '
        'fetchMs=$fetchDurationMs totalMs=${pageTimer.elapsedMilliseconds}',
        name: 'SyncCoordinator',
      );

      final responseCursor = body['nextCursor']?.toString().trim();
      final nextCursor = responseCursor == null || responseCursor.isEmpty
          ? _syncCursor(body)
          : responseCursor;
      final pageHasMore = body['hasMore'] == true;
      if (pageHasMore && (nextCursor.isEmpty || nextCursor == cursor)) {
        throw const ApiException(
          statusCode: 502,
          message: 'Full sync cursor did not advance',
        );
      }
      if (responseCursor == null || responseCursor.isEmpty) {
        // Older servers only return a wall-clock syncTime. Keep using the
        // legacy query until the server exposes an opaque high-water cursor.
        cursor = null;
        legacyLastSync = nextCursor;
      } else {
        opaqueCursorSeen = true;
        cursor = nextCursor;
        legacyLastSync = null;
      }
      hasMore = pageHasMore;
    }

    // Persist the complete pull's version map once. Writing after every page
    // is safe but needlessly repeats the same JSON serialization and platform
    // bridge call for large decks.
    await _saveServerVersions(accountId, serverVersions);

    if (force && hasRemoteContent) {
      await _removeSeedContent(
        accountId,
        cards: cards > 0,
        documents: documents > 0,
        protectedObjectKeys: protectedObjectKeys,
      );
    }
    if (completedHighWaterAt != null) {
      // The checkpoint is only a tombstone-retention hint. It must not add a
      // second blocking HTTP round trip to login/initial sync.
      unawaited(_checkpointDevice(client, completedHighWaterAt, cancelToken));
    }
    // Persist only the completed high-water timestamp. A pagination cursor is
    // valid only inside this pull; reusing the final cursor on the next pull
    // would permanently exclude objects created after its high-water time.
    await preferences?.setString(
      _lastSyncKeyFor(accountId),
      completedSyncWatermark ??
          legacyLastSync ??
          DateTime.now().toUtc().toIso8601String(),
    );
    await preferences?.setString(
      '$_fullSyncVersionKey.$accountId',
      opaqueCursorSeen ? _fullSyncVersion : '1',
    );
    return FullSyncReport(
      cards: cards,
      documents: documents,
      decks: decks,
      settings: settings,
    );
  }

  CardModel _cardFromPayload(
    String accountId,
    Map<String, dynamic> data, {
    String? fallbackId,
    Object? fallbackUpdatedAt,
  }) {
    final fsrs = data['fsrs'] is Map
        ? Map<String, dynamic>.from(data['fsrs'] as Map)
        : const <String, dynamic>{};
    return CardModel(
      id: _firstText(data, const ['id']).isNotEmpty
          ? _firstText(data, const ['id'])
          : fallbackId ?? '',
      accountId: accountId,
      type: CardType.values.firstWhere(
        (value) => value.name == data['type'],
        orElse: () => CardType.single,
      ),
      folder: data['folder']?.toString() ?? '',
      question: data['question']?.toString() ?? '',
      options: _stringStringMap(data['options']),
      answer: _stringList(data['answer']),
      noteContent: data['noteContent']?.toString() ?? '',
      explanation: data['explanation']?.toString() ?? '',
      tags: _stringList(data['tags']),
      dueAt: _date(data['dueAt']),
      createdAt: _date(data['createdAt']),
      updatedAt: _date(data['updatedAt'] ?? fallbackUpdatedAt),
      reviews: _intValue(data['reviews']),
      mastery: data['mastery']?.toString() ?? '',
      suspended: data['suspended'] == true,
      fsrs: FsrsSnapshot(
        state: FsrsState.values.firstWhere(
          (value) => value.name == fsrs['state'],
          orElse: () => FsrsState.newCard,
        ),
        dueAt: _date(fsrs['dueAt'] ?? data['dueAt']),
        stability: _doubleValue(fsrs['stability']),
        difficulty: _doubleValue(fsrs['difficulty']),
        reps: _intValue(fsrs['reps']),
        lapses: _intValue(fsrs['lapses']),
      ),
    );
  }

  DocumentModel _documentFromPayload(
    String accountId,
    Map<String, dynamic> data, {
    String? fallbackId,
    Object? fallbackUpdatedAt,
  }) => DocumentModel(
    id: _firstText(data, const ['id']).isNotEmpty
        ? _firstText(data, const ['id'])
        : fallbackId ?? '',
    accountId: accountId,
    folder: _firstText(data, const ['folder', 'folderId']),
    title: _firstText(data, const ['title', 'name']),
    body: _documentText(data),
    updatedAt: _date(data['updatedAt'] ?? fallbackUpdatedAt),
  );

  String _firstText(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  String _documentText(Map<String, dynamic> data) {
    const keys = ['html', 'body', 'content', 'markdown', 'contentMarkdown'];
    for (final key in keys) {
      final raw = data[key]?.toString() ?? '';
      if (raw.trim().isEmpty) continue;
      final converted = htmlToMarkdown(raw);
      if (converted.trim().isNotEmpty) return converted;
    }
    return '';
  }

  Future<void> _saveDocumentPreservingContent(
    String accountId,
    DocumentModel document, {
    Map<String, DocumentModel>? localDocumentsById,
  }) async {
    final localDocument =
        localDocumentsById?[document.id] ??
        (localDocumentsById == null
            ? (await database.loadDocuments(
                accountId,
              )).where((value) => value.id == document.id).firstOrNull
            : null);
    final value = document.body.trim().isEmpty && localDocument != null
        ? DocumentModel(
            id: document.id,
            accountId: document.accountId,
            folder: document.folder.isEmpty
                ? localDocument.folder
                : document.folder,
            title: document.title.isEmpty
                ? localDocument.title
                : document.title,
            body: localDocument.body,
            updatedAt: document.updatedAt,
          )
        : document;
    await database.saveDocument(value);
    localDocumentsById?[value.id] = value;
  }

  Future<void> _removeSeedContent(
    String accountId, {
    required bool cards,
    required bool documents,
    Set<String> protectedObjectKeys = const {},
  }) async {
    if (cards) {
      final localCards = await database.loadCards(accountId);
      final seedIds = localCards
          .where(
            (card) =>
                !protectedObjectKeys.contains(_objectKey('CARD', card.id)) &&
                (card.id.startsWith('card-flutter-') ||
                    card.id.startsWith('card-sync-') ||
                    card.id.startsWith('card-fsrs-') ||
                    card.id.startsWith('card-note-') ||
                    card.id.startsWith('card-drift-')),
          )
          .map((card) => card.id)
          .toSet();
      for (final id in seedIds) {
        await database.deleteCard(id, accountId);
      }
    }
    if (documents) {
      final localDocuments = await database.loadDocuments(accountId);
      final seedIds = localDocuments
          .where(
            (document) =>
                !protectedObjectKeys.contains(
                  _objectKey('DOCUMENT', document.id),
                ) &&
                (document.id == 'doc-first-phase' ||
                    document.id == 'doc-offline'),
          )
          .map((document) => document.id)
          .toSet();
      for (final id in seedIds) {
        await database.deleteDocument(id, accountId);
      }
    }
  }

  String _objectKey(String objectType, String objectId) =>
      '$objectType\u0000$objectId';

  String? _objectType(Map<String, dynamic> object) {
    for (final key in const ['objectType', 'type', 'kind']) {
      final value = object[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value.toUpperCase();
    }
    return null;
  }

  String? _objectId(Map<String, dynamic> object) {
    for (final key in const ['objectId', 'id']) {
      final value = object[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    final data = _stringMap(object['data']);
    for (final key in const ['objectId', 'id']) {
      final value = data?[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  List<Map<String, dynamic>> _deletionObjects(Map<String, dynamic> body) {
    final result = <Map<String, dynamic>>[];
    for (final key in const [
      'deletedObjects',
      'deletions',
      'tombstones',
      'removedObjects',
    ]) {
      final values = body[key];
      if (values is! List) continue;
      for (final value in values) {
        final item = _stringMap(value);
        if (item != null) {
          result.add({...item, 'deleted': true});
        }
      }
    }
    return result;
  }

  bool _isRemoteDeletion(Map<String, dynamic> object) {
    // A full-sync tombstone may only contain the object identity and a null
    // data field. It must not be treated as an empty upsert.
    if (object.containsKey('data') && object['data'] == null) return true;
    for (final key in const [
      'deleted',
      'isDeleted',
      'is_deleted',
      'removed',
      'deletedAt',
      'deleted_at',
    ]) {
      if (object[key] == true) return true;
      if (key == 'deletedAt' || key == 'deleted_at') {
        final value = object[key]?.toString().trim();
        if (value != null && value.isNotEmpty && value != 'null') return true;
      }
    }
    final metadata = _stringMap(object['metadata']);
    if (metadata != null && metadata['deleted'] == true) return true;
    for (final key in const ['operation', 'action', 'status']) {
      final value = object[key]?.toString().toLowerCase().trim();
      if (value == 'delete' || value == 'deleted' || value == 'remove') {
        return true;
      }
    }
    final data = _stringMap(object['data']);
    if (data != null && !identical(data, object)) {
      return _isRemoteDeletion(data);
    }
    return false;
  }

  Future<void> _removeRemoteObject(
    String accountId,
    String objectType,
    String objectId,
    Map<String, dynamic> object,
  ) async {
    final idsToClear = <String>{objectId};
    switch (objectType) {
      case 'CARD':
        await database.deleteCard(objectId, accountId);
      case 'DOCUMENT':
        await database.deleteDocument(objectId, accountId);
      case 'DECK':
        final folders = _deckFolderCandidates(object, objectId);
        if (folders.isNotEmpty) {
          final localCards = await database.loadCards(accountId);
          final localDocuments = await database.loadDocuments(accountId);
          final cards = localCards.where(
            (card) => folders.contains(card.folder),
          );
          final documents = localDocuments.where(
            (document) => folders.contains(document.folder),
          );
          final cardIds = cards.map((card) => card.id).toSet();
          final documentIds = documents.map((document) => document.id).toSet();
          idsToClear.addAll(cardIds);
          idsToClear.addAll(documentIds);
          await database.deleteCardsByIds(accountId, cardIds);
          await database.deleteDocumentsByIds(accountId, documentIds);
        }
        await preferences?.remove('sync.deck.$accountId.$objectId');
      case 'SETTINGS':
        final prefs = preferences;
        if (prefs != null) {
          await prefs.remove('review.new_cards_per_day.$accountId');
          await prefs.remove('review.reviews_per_day.$accountId');
          await prefs.remove('review.autonomous_learning.$accountId');
          await prefs.remove('review.selected_folder.$accountId');
        }
    }
    await database.markPendingSyncObjectsSynced(accountId, idsToClear);
  }

  Set<String> _deckFolderCandidates(
    Map<String, dynamic> object,
    String objectId,
  ) {
    final candidates = <String>{objectId};
    final data = _payloadMap(object['data']) ?? _stringMap(object['data']);
    for (final source in [object, ?data]) {
      for (final key in const [
        'folder',
        'folderId',
        'deckId',
        'name',
        'title',
      ]) {
        final value = source[key]?.toString().trim();
        if (value != null && value.isNotEmpty) candidates.add(value);
      }
    }
    return candidates;
  }

  Map<String, dynamic>? _stringMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Map<String, dynamic>? _payloadMap(Object? value) {
    Object? current = value;
    for (var depth = 0; depth < 4; depth++) {
      final map = _stringMap(current);
      if (map == null) return null;
      final nested = map['data'];
      final hasObjectFields = map.keys.any(
        (key) => const {
          'objectType',
          'objectId',
          'objectVersion',
          'updatedAt',
          'metadata',
        }.contains(key),
      );
      final looksLikePayload = map.keys.any(
        (key) => const {
          'id',
          'title',
          'html',
          'body',
          'question',
          'folder',
          'type',
        }.contains(key),
      );
      if (nested != null && (hasObjectFields || !looksLikePayload)) {
        current = nested;
        continue;
      }
      return map;
    }
    return null;
  }

  Future<SyncQueueItemModel?> _mergeConflict(
    String accountId,
    String objectType,
    String objectId,
    Map<String, dynamic> result, {
    required SyncQueueItemModel localItem,
    required int? serverVersion,
  }) async {
    if (objectType != 'CARD') {
      await _applyRemotePayload(
        accountId,
        objectType,
        result['data'],
        fallbackId: objectId,
      );
      return null;
    }

    final payload = _payloadMap(result['data']);
    if (payload == null) return null;
    final remote = _cardFromPayload(
      accountId,
      payload,
      fallbackId: objectId,
      fallbackUpdatedAt: result['updatedAt'],
    );
    if (remote.id.isEmpty) return null;

    // The full pull may have already refreshed the local row. The queued
    // payload is the authoritative snapshot of the user's local mutation.
    final localPayload = _payloadMap(_decodePayload(localItem.payload));
    final queuedLocal = localPayload == null
        ? null
        : _cardFromPayload(accountId, localPayload, fallbackId: objectId);
    final local = queuedLocal?.id.isNotEmpty == true
        ? queuedLocal
        : await database.loadCard(objectId, accountId);
    if (local == null) {
      await database.saveCard(remote);
      return null;
    }

    final progressReset = localPayload?['progressReset'] == true;
    final progressOnly = localPayload?['syncMode'] == 'progress';
    final merged = _mergeCardProgress(
      local,
      remote,
      preferLocalProgress: progressReset,
    );
    await database.saveCard(merged);
    if (!progressReset && local.reviews < remote.reviews) return null;

    final now = DateTime.now();
    return SyncQueueItemModel(
      id: _mutationId('conflict-card', objectId, now),
      accountId: accountId,
      objectType: 'CARD',
      objectId: objectId,
      objectVersion: serverVersion ?? 1,
      operation: SyncOperation.upsert,
      payload: jsonEncode(
        cardSyncPayload(
          merged,
          progressReset: progressReset,
          progressOnly: progressOnly,
        ),
      ),
      status: SyncItemStatus.pending,
      attempts: 0,
      lastError: null,
      createdAt: now,
      updatedAt: now,
    );
  }

  CardModel _mergeCardProgress(
    CardModel local,
    CardModel remote, {
    bool preferLocalProgress = false,
  }) {
    if (!preferLocalProgress && local.reviews < remote.reviews) return remote;
    return remote.copyWith(
      dueAt: local.dueAt,
      updatedAt: local.updatedAt,
      reviews: local.reviews,
      mastery: local.mastery,
      suspended: local.suspended,
      fsrs: local.fsrs,
    );
  }

  Future<void> _applyRemotePayload(
    String accountId,
    String objectType,
    Object? value, {
    String? fallbackId,
    Object? fallbackUpdatedAt,
  }) async {
    final payload = _payloadMap(value);
    if (payload == null) return;
    switch (objectType) {
      case 'CARD':
        final card = _cardFromPayload(
          accountId,
          payload,
          fallbackId: fallbackId,
          fallbackUpdatedAt: fallbackUpdatedAt,
        );
        if (card.id.isNotEmpty) await database.saveCard(card);
      case 'DOCUMENT':
        final document = _documentFromPayload(
          accountId,
          payload,
          fallbackId: fallbackId,
          fallbackUpdatedAt: fallbackUpdatedAt,
        );
        if (document.id.isNotEmpty) {
          await _saveDocumentPreservingContent(accountId, document);
        }
      case 'DECK':
        final id = fallbackId?.trim();
        if (id != null && id.isNotEmpty) {
          await _saveDeckMetadata(accountId, id, payload);
        }
      case 'SETTINGS':
        await _applyRemoteSettings(accountId, payload);
    }
  }

  Future<void> _saveDeckMetadata(
    String accountId,
    String objectId,
    Map<String, dynamic> payload,
  ) async {
    final prefs = preferences;
    if (prefs == null || objectId.trim().isEmpty) return;
    await prefs.setString(
      'sync.deck.$accountId.$objectId',
      jsonEncode(payload),
    );
  }

  Future<void> _applyRemoteSettings(
    String accountId,
    Map<String, dynamic> payload,
  ) async {
    final prefs = preferences;
    if (prefs == null) return;
    final nested =
        _stringMap(payload['reviewSettings']) ??
        _stringMap(payload['settings']);
    final source = nested ?? payload;
    final newCards = source['newCardsPerDay'];
    final reviews = source['reviewsPerDay'];
    final autonomous = source['autonomousLearning'];
    if (newCards != null) {
      await prefs.setInt(
        'review.new_cards_per_day.$accountId',
        _intValue(newCards).clamp(0, 9999).toInt(),
      );
    }
    if (reviews != null) {
      await prefs.setInt(
        'review.reviews_per_day.$accountId',
        _intValue(reviews).clamp(0, 9999).toInt(),
      );
    }
    if (autonomous != null) {
      await prefs.setBool(
        'review.autonomous_learning.$accountId',
        autonomous == true || autonomous.toString().toLowerCase() == 'true',
      );
    }
    if (source.containsKey('selectedFolder')) {
      final selectedFolder = source['selectedFolder']?.toString().trim();
      if (selectedFolder == null || selectedFolder.isEmpty) {
        await prefs.remove('review.selected_folder.$accountId');
      } else {
        await prefs.setString(
          'review.selected_folder.$accountId',
          selectedFolder,
        );
      }
    }
  }

  int? _version(Object? value) {
    if (value is num) return value.toInt() > 0 ? value.toInt() : null;
    final parsed = int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed > 0 ? parsed : null;
  }

  String _lastSyncKeyFor(String accountId) => '$_lastSyncKey.$accountId';

  String _syncCursor(Map<String, dynamic>? body) {
    for (final key in const [
      'nextCursor',
      'syncTime',
      'nextSyncAt',
      'lastSyncAt',
    ]) {
      final value = body?[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return DateTime.now().toUtc().toIso8601String();
  }

  String _serverVersionKey(
    String accountId,
    String objectType,
    String objectId,
  ) => 'sync.object_version.$accountId.$objectType.$objectId';

  String _serverVersionCacheKey(String accountId) =>
      'sync.object_versions.$accountId';

  Map<String, int> _serverVersionsFor(String accountId) {
    return _serverVersionCache.putIfAbsent(accountId, () {
      final result = <String, int>{};
      final prefs = preferences;
      if (prefs == null) return result;

      final packed = prefs.getString(_serverVersionCacheKey(accountId));
      if (packed != null && packed.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(packed);
          if (decoded is Map) {
            for (final entry in decoded.entries) {
              final version = _version(entry.value);
              if (version != null) result[entry.key.toString()] = version;
            }
          }
        } catch (_) {
          // A corrupt compact cache is recoverable from legacy keys below.
        }
      }

      // Migrate old per-object keys without writing them one by one. Keeping
      // the old keys is intentional: it makes downgrade/recovery harmless.
      final legacyPrefix = 'sync.object_version.$accountId.';
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(legacyPrefix) || result.containsKey(key)) continue;
        final version = _version(prefs.getString(key));
        if (version != null) result[key] = version;
      }
      return result;
    });
  }

  int _batchSizeFor(String accountId, List<SyncQueueItemModel> items) {
    final canUseProgressBatch =
        items.isNotEmpty &&
        items.every((item) {
          if (item.objectType != 'CARD' ||
              item.operation != SyncOperation.upsert) {
            return false;
          }
          final decoded = _stringMap(_decodePayload(item.payload));
          if (decoded?['syncMode'] != 'progress') return false;
          return _serverVersionsFor(accountId)[_serverVersionKey(
                accountId,
                item.objectType,
                item.objectId,
              )] !=
              null;
        });
    return canUseProgressBatch ? _progressBatchSize : _fullBatchSize;
  }

  int _objectVersion(String accountId, SyncQueueItemModel item) {
    final cached = _serverVersionsFor(
      accountId,
    )[_serverVersionKey(accountId, item.objectType, item.objectId)];
    // The fallback must represent the initial server version. Local review
    // counts and timestamps are not server versions and can make an update
    // look newer than it really is.
    return cached ?? 1;
  }

  Future<void> _saveServerVersions(
    String accountId,
    Map<String, int> versions,
  ) async {
    final prefs = preferences;
    if (prefs == null || versions.isEmpty) return;
    final cached = _serverVersionsFor(accountId);
    cached.addAll(versions);
    await prefs.setString(
      _serverVersionCacheKey(accountId),
      jsonEncode(cached),
    );
    // Preserve the old key for single-object writes so existing installations
    // and downgrade paths continue to observe their last acknowledged value.
    if (versions.length == 1) {
      final entry = versions.entries.single;
      await prefs.setString(entry.key, entry.value.toString());
    }
  }

  Future<void> _checkpointDevice(
    ApiClient client,
    String highWaterAt,
    CancelToken? cancelToken,
  ) async {
    try {
      await client.post(
        '/api/v2/sync/device',
        data: {'deviceId': await _deviceId(), 'highWaterAt': highWaterAt},
        cancelToken: cancelToken,
      );
    } catch (_) {
      // Checkpointing is best effort. If it fails, the server keeps the
      // tombstones, which is safer than deleting them too early.
    }
  }

  Map<String, String> _stringStringMap(Object? value) {
    final map = _stringMap(value);
    if (map == null) return const {};
    return map.map((key, value) => MapEntry(key, value.toString()));
  }

  List<String> _stringList(Object? value) {
    if (value is List) return value.map((item) => item.toString()).toList();
    if (value is String && value.trim().isNotEmpty) {
      final decoded = _stringMap(value) ?? _stringListValue(value);
      if (decoded is List) {
        return decoded.map((item) => item.toString()).toList();
      }
      return value
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  Object? _stringListValue(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  int _intValue(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _doubleValue(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  DateTime _date(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();

  Map<String, dynamic> _syncRequestPayload(
    String accountId,
    SyncQueueItemModel item,
    String deviceId,
  ) {
    final mutationId = item.id.trim();
    final decoded = _stringMap(_decodePayload(item.payload));
    final hasProgressMarker =
        item.objectType == 'CARD' && decoded?['syncMode'] == 'progress';
    final hasKnownServerVersion =
        _serverVersionsFor(accountId)[_serverVersionKey(
          accountId,
          item.objectType,
          item.objectId,
        )] !=
        null;
    final sendProgress = hasProgressMarker && hasKnownServerVersion;

    return {
      'objectType': item.objectType,
      'objectId': item.objectId,
      'objectVersion': _objectVersion(accountId, item),
      'operation': item.operation.name,
      'deviceId': deviceId,
      // The queue row is the durable mutation identity. It remains unchanged
      // across network retries, while a new local snapshot receives a new
      // queue ID and therefore a new server-side idempotency key.
      if (mutationId.length >= 16 && mutationId.length <= 200)
        'mutationId': mutationId,
      if (item.operation == SyncOperation.upsert)
        'data': sendProgress
            ? _progressPayload(decoded ?? const <String, dynamic>{})
            : _withoutSyncControlFields(decoded ?? const <String, dynamic>{}),
      if (sendProgress) 'metadata': const {'syncMode': 'progress'},
    };
  }

  Map<String, dynamic> _progressPayload(Map<String, dynamic> payload) {
    final result = <String, dynamic>{};
    for (final key in const [
      'id',
      'dueAt',
      'updatedAt',
      'reviews',
      'mastery',
      'suspended',
      'fsrs',
      'progressReset',
    ]) {
      if (payload.containsKey(key)) result[key] = payload[key];
    }
    return result;
  }

  Map<String, dynamic> _withoutSyncControlFields(Map<String, dynamic> payload) {
    final result = Map<String, dynamic>.from(payload);
    result.remove('syncMode');
    return result;
  }

  dynamic _decodePayload(String payload) {
    try {
      return jsonDecode(payload);
    } catch (_) {
      return {'raw': payload};
    }
  }

  Future<String> _deviceId() async {
    const key = 'sync.device_id';
    final existing = preferences?.getString(key);
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random();
    final value =
        'flutter-${DateTime.now().microsecondsSinceEpoch}-${random.nextInt(1 << 32)}';
    await preferences?.setString(key, value);
    return value;
  }

  String _mutationId(String prefix, String objectId, DateTime at) =>
      '$prefix-$objectId-${at.microsecondsSinceEpoch}-${_mutationRandom.nextInt(1 << 32)}';
}

class SyncReport {
  const SyncReport({
    this.synced = 0,
    this.failed = 0,
    this.conflicts = 0,
    this.networkFailure = false,
  });

  final int synced;
  final int failed;
  final int conflicts;
  final bool networkFailure;
}

class FullSyncReport {
  const FullSyncReport({
    this.cards = 0,
    this.documents = 0,
    this.decks = 0,
    this.settings = 0,
  });

  final int cards;
  final int documents;
  final int decks;
  final int settings;
}
