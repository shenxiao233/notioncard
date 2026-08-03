import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../models/card_model.dart';
import '../models/document_model.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../utils/rich_text.dart';

class SyncCoordinator {
  SyncCoordinator(this.database, {this.apiClient, this.preferences});

  static const _supportedObjectTypes = {'DECK', 'DOCUMENT', 'CARD', 'SETTINGS'};
  static const _lastSyncKey = 'sync.last_sync';
  static const _fullSyncVersionKey = 'sync.full_sync_version';
  static const _fullSyncVersion = '1';

  final AppDatabase database;
  final ApiClient? apiClient;
  final SharedPreferences? preferences;

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
    for (final item in items.where(
      (value) => value.status == SyncItemStatus.failed,
    )) {
      await database.enqueueSync(
        SyncQueueItemModel(
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
      );
    }
  }

  Future<SyncReport> sync(String accountId) async {
    final client = apiClient;
    if (client == null) return const SyncReport();

    final items = await database.loadPendingSync(accountId);
    final groups = <String, List<SyncQueueItemModel>>{};
    for (final item in items) {
      if (!_supportedObjectTypes.contains(item.objectType)) {
        // Older builds queued review events separately. Review state is now
        // part of the CARD payload, so these legacy entries must not poison a
        // valid batch with an object type rejected by the server.
        await database.markSyncSynced(item.id, accountId);
        continue;
      }
      groups
          .putIfAbsent(_objectKey(item.objectType, item.objectId), () => [])
          .add(item);
    }
    final latestItems = groups.values.map((items) => items.last).toList();
    var synced = 0;
    var failed = 0;
    var conflicts = 0;
    var networkFailure = false;
    for (var offset = 0; offset < latestItems.length; offset += 100) {
      final batch = latestItems.skip(offset).take(100).toList();
      final batchGroups = <String, List<SyncQueueItemModel>>{
        for (final item in batch)
          _objectKey(item.objectType, item.objectId):
              groups[_objectKey(item.objectType, item.objectId)]!,
      };
      try {
        final response = await client.post(
          '/api/v2/sync/batch',
          data: {
            'requests': [
              for (final item in batch)
                {
                  'objectType': item.objectType,
                  'objectId': item.objectId,
                  'objectVersion': await _objectVersion(accountId, item),
                  if (item.operation == SyncOperation.upsert)
                    'data': _decodePayload(item.payload),
                  'deviceId': await _deviceId(),
                },
            ],
          },
        );
        final body = _stringMap(response.data);
        final responses = body?['responses'];
        if (body == null || responses is! List) {
          throw const ApiException(
            statusCode: 502,
            message: 'Invalid sync response',
          );
        }
        final handled = <String>{};
        for (final raw in responses) {
          final result = _stringMap(raw);
          if (result == null) continue;
          final objectType = result['objectType']?.toString();
          final objectId = result['objectId']?.toString();
          if (objectType == null || objectId == null) continue;
          final key = _objectKey(objectType, objectId);
          final groupedItems = batchGroups[key];
          if (groupedItems == null) continue;
          handled.add(key);
          await _saveServerVersion(
            accountId,
            objectType,
            objectId,
            _version(result['serverVersion']),
          );
          if (result['conflict'] == true) {
            conflicts++;
            await _applyRemotePayload(
              accountId,
              objectType,
              result['data'],
              fallbackId: objectId,
            );
            for (final item in groupedItems) {
              synced++;
              await database.markSyncSynced(item.id, accountId);
            }
          } else {
            for (final item in groupedItems) {
              synced++;
              await database.markSyncSynced(item.id, accountId);
            }
          }
        }
        for (final entry in batchGroups.entries) {
          if (handled.contains(entry.key)) continue;
          for (final item in entry.value) {
            failed++;
            await database.markSyncFailed(
              item.id,
              accountId,
              'Server did not return a response for this item',
            );
          }
        }
      } on ApiException catch (error) {
        if (error.isNetworkFailure) {
          networkFailure = true;
          break;
        }
        for (final group in batchGroups.values) {
          for (final item in group) {
            failed++;
            await database.markSyncFailed(item.id, accountId, error.message);
          }
        }
      }
    }
    return SyncReport(
      synced: synced,
      failed: failed,
      conflicts: conflicts,
      networkFailure: networkFailure,
    );
  }

  Future<FullSyncReport> fullSync(
    String accountId, {
    bool force = false,
  }) async {
    final client = apiClient;
    if (client == null) return const FullSyncReport();
    final lastSync = force
        ? null
        : preferences?.getString(_lastSyncKeyFor(accountId));
    final queryParameters = <String, dynamic>{};
    if (lastSync != null && lastSync.trim().isNotEmpty) {
      queryParameters['lastSyncAt'] = lastSync;
    }
    final response = await client.get(
      '/api/v2/sync/full',
      queryParameters: queryParameters,
    );
    final body = _stringMap(response.data);
    final objects = body?['objects'];
    if (body == null || (objects != null && objects is! List)) {
      throw const ApiException(
        statusCode: 502,
        message: 'Invalid full sync response',
      );
    }
    var cards = 0;
    var documents = 0;
    var hasRemoteContent = false;
    for (final raw
        in (objects as List? ?? const <Object?>[]).whereType<Map>()) {
      final object = _stringMap(raw);
      if (object == null) continue;
      final payload = _payloadMap(object['data']);
      if (payload == null) continue;
      final objectId = object['objectId']?.toString();
      final objectUpdatedAt = object['updatedAt'];
      final objectType = object['objectType']?.toString();
      if (objectId == null || objectType == null) continue;
      await _saveServerVersion(
        accountId,
        objectType,
        objectId,
        _version(object['objectVersion']),
      );
      switch (objectType) {
        case 'CARD':
          await database.saveCard(
            _cardFromPayload(
              accountId,
              payload,
              fallbackId: objectId,
              fallbackUpdatedAt: objectUpdatedAt,
            ),
          );
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
          await _saveDocumentPreservingContent(accountId, document);
          documents++;
          hasRemoteContent = true;
      }
    }
    if (force && hasRemoteContent) {
      await _removeSeedContent(
        accountId,
        cards: cards > 0,
        documents: documents > 0,
      );
    }
    final nextSync = _syncCursor(body);
    await preferences?.setString(_lastSyncKeyFor(accountId), nextSync);
    await preferences?.setString(
      '$_fullSyncVersionKey.$accountId',
      _fullSyncVersion,
    );
    return FullSyncReport(cards: cards, documents: documents);
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
    DocumentModel document,
  ) async {
    final localDocument = (await database.loadDocuments(
      accountId,
    )).where((value) => value.id == document.id).firstOrNull;
    if (document.body.trim().isEmpty && localDocument != null) {
      await database.saveDocument(
        DocumentModel(
          id: document.id,
          accountId: document.accountId,
          folder: document.folder.isEmpty
              ? localDocument.folder
              : document.folder,
          title: document.title.isEmpty ? localDocument.title : document.title,
          body: localDocument.body,
          updatedAt: document.updatedAt,
        ),
      );
      return;
    }
    await database.saveDocument(document);
  }

  Future<void> _removeSeedContent(
    String accountId, {
    required bool cards,
    required bool documents,
  }) async {
    if (cards) {
      final localCards = await database.loadCards(accountId);
      final seedIds = localCards
          .where(
            (card) =>
                card.id.startsWith('card-flutter-') ||
                card.id.startsWith('card-sync-') ||
                card.id.startsWith('card-fsrs-') ||
                card.id.startsWith('card-note-') ||
                card.id.startsWith('card-drift-'),
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
                document.id == 'doc-first-phase' ||
                document.id == 'doc-offline',
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
    }
  }

  int? _version(Object? value) {
    if (value is num) return value.toInt() > 0 ? value.toInt() : null;
    final parsed = int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed > 0 ? parsed : null;
  }

  String _lastSyncKeyFor(String accountId) => '$_lastSyncKey.$accountId';

  String _syncCursor(Map<String, dynamic>? body) {
    for (final key in const ['syncTime', 'nextSyncAt', 'lastSyncAt']) {
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

  Future<int> _objectVersion(String accountId, SyncQueueItemModel item) async {
    final cached = _version(
      preferences?.getString(
        _serverVersionKey(accountId, item.objectType, item.objectId),
      ),
    );
    return cached ?? max(1, item.objectVersion);
  }

  Future<void> _saveServerVersion(
    String accountId,
    String objectType,
    String objectId,
    int? version,
  ) async {
    if (version == null) return;
    await preferences?.setString(
      _serverVersionKey(accountId, objectType, objectId),
      version.toString(),
    );
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
  const FullSyncReport({this.cards = 0, this.documents = 0});

  final int cards;
  final int documents;
}
