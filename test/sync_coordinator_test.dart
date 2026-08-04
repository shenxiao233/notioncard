import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kncard_app/core/database/app_database.dart';
import 'package:kncard_app/core/models/card_model.dart';
import 'package:kncard_app/core/models/document_model.dart';
import 'package:kncard_app/core/network/api_client.dart';
import 'package:kncard_app/core/network/api_config.dart';
import 'package:kncard_app/core/sync/sync_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase database;
  late SharedPreferences preferences;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'accepts a batch response without data and caches server version',
    () async {
      final adapter = _QueueAdapter([
        _FakeResponse.json({
          'responses': [
            {
              'objectType': 'CARD',
              'objectId': 'card-1',
              'serverVersion': 7,
              'conflict': false,
            },
          ],
        }),
        _FakeResponse.json({
          'responses': [
            {
              'objectType': 'CARD',
              'objectId': 'card-1',
              'serverVersion': 8,
              'conflict': false,
            },
          ],
        }),
      ]);
      final coordinator = _buildCoordinator(database, preferences, adapter);
      final now = DateTime(2026, 8, 2);

      await database.enqueueSync(_buildQueueItem('queue-1', now));
      final first = await coordinator.sync('account-1');

      expect(first.synced, 1);
      expect(first.failed, 0);
      expect(
        preferences.getString('sync.object_version.account-1.CARD.card-1'),
        '7',
      );

      await database.enqueueSync(
        _buildQueueItem('queue-2', now.add(const Duration(minutes: 1))),
      );
      await coordinator.sync('account-1');

      final secondRequest = adapter.requests[1];
      final requestData = secondRequest.data as Map<String, dynamic>;
      final request = (requestData['requests'] as List).single as Map;
      expect(request['objectVersion'], 7);
    },
  );

  test('accepts a JSON string batch response', () async {
    final adapter = _QueueAdapter([
      _FakeResponse.text(
        jsonEncode({
          'responses': [
            {
              'objectType': 'CARD',
              'objectId': 'card-1',
              'serverVersion': 2,
              'conflict': false,
            },
          ],
        }),
      ),
    ]);
    final coordinator = _buildCoordinator(database, preferences, adapter);
    await database.enqueueSync(
      _buildQueueItem('queue-1', DateTime(2026, 8, 2)),
    );

    final report = await coordinator.sync('account-1');

    expect(report.synced, 1);
    expect(report.failed, 0);
  });

  test('uses the saved cursor for subsequent incremental pulls', () async {
    final adapter = _QueueAdapter([
      _FakeResponse.json({
        'syncTime': '2026-08-02T00:00:00.000Z',
        'objects': [],
      }),
      _FakeResponse.json({
        'syncTime': '2026-08-03T00:00:00.000Z',
        'objects': [],
      }),
    ]);
    final coordinator = _buildCoordinator(database, preferences, adapter);

    expect(coordinator.needsInitialFullSync('account-1'), isTrue);
    await coordinator.fullSync('account-1');
    expect(coordinator.needsInitialFullSync('account-1'), isFalse);
    expect(adapter.requests.single.queryParameters, isEmpty);

    await coordinator.fullSync('account-1');
    expect(
      adapter.requests[1].queryParameters['lastSyncAt'],
      '2026-08-02T00:00:00.000Z',
    );
  });
  test(
    'unwraps nested document data and preserves local body when remote body is empty',
    () async {
      await database.saveDocument(
        DocumentModel(
          id: 'doc-1',
          accountId: 'account-1',
          folder: 'local',
          title: 'local title',
          body: '# local body',
          updatedAt: DateTime(2026, 8, 1),
        ),
      );
      final adapter = _QueueAdapter([
        _FakeResponse.json({
          'syncTime': '2026-08-02T00:00:00.000Z',
          'objects': [
            {
              'objectType': 'DOCUMENT',
              'objectId': 'doc-1',
              'objectVersion': 3,
              'data': jsonEncode({
                'data': {
                  'id': 'doc-1',
                  'folder': 'remote',
                  'title': 'remote title',
                  'html': '<p></p>',
                },
              }),
            },
          ],
        }),
      ]);
      final coordinator = _buildCoordinator(database, preferences, adapter);

      final report = await coordinator.fullSync('account-1', force: true);
      final document = (await database.loadDocuments('account-1')).single;

      expect(report.documents, 1);
      expect(document.folder, 'remote');
      expect(document.title, 'remote title');
      expect(document.body, '# local body');
      expect(
        preferences.getString('sync.object_version.account-1.DOCUMENT.doc-1'),
        '3',
      );
    },
  );

  test('marks legacy review events as synced without sending them', () async {
    final adapter = _QueueAdapter([]);
    final coordinator = _buildCoordinator(database, preferences, adapter);
    await database.enqueueSync(
      _buildQueueItem(
        'legacy-1',
        DateTime(2026, 8, 2),
        objectType: 'REVIEW_EVENT',
        objectId: 'event-1',
      ),
    );

    final report = await coordinator.sync('account-1');
    final remaining = await database.loadPendingSync('account-1');

    expect(report.synced, 0);
    expect(report.failed, 0);
    expect(adapter.requests, isEmpty);
    expect(remaining, isEmpty);
  });

  test(
    'removes a card when the incremental response contains a tombstone',
    () async {
      await database.saveCard(_buildCard('card-1', folder: 'deck-1'));
      final adapter = _QueueAdapter([
        _FakeResponse.json({
          'syncTime': '2026-08-02T00:00:00.000Z',
          'objects': [
            {
              'objectType': 'CARD',
              'objectId': 'card-1',
              'objectVersion': 4,
              'deleted': true,
            },
          ],
        }),
      ]);
      final coordinator = _buildCoordinator(database, preferences, adapter);

      await coordinator.fullSync('account-1');

      expect(await database.loadCards('account-1'), isEmpty);
    },
  );

  test('removes a card when a tombstone has null data', () async {
    await database.saveCard(_buildCard('card-1', folder: 'deck-1'));
    final adapter = _QueueAdapter([
      _FakeResponse.json({
        'syncTime': '2026-08-02T00:00:00.000Z',
        'objects': [
          {'objectType': 'CARD', 'objectId': 'card-1', 'data': null},
        ],
      }),
    ]);
    final coordinator = _buildCoordinator(database, preferences, adapter);

    await coordinator.fullSync('account-1');

    expect(await database.loadCards('account-1'), isEmpty);
  });

  test('removes a stale local card when push conflicts with a tombstone', () async {
    await database.saveCard(_buildCard('card-1', folder: 'deck-1'));
    await database.enqueueSync(
      _buildQueueItem('queue-delete-conflict', DateTime(2026, 8, 2)),
    );
    final adapter = _QueueAdapter([
      _FakeResponse.json({
        'responses': [
          {
            'objectType': 'CARD',
            'objectId': 'card-1',
            'serverVersion': 5,
            'data': null,
            'metadata': {'deleted': true},
            'deleted': true,
            'conflict': true,
            'resolution': 'SERVER_WINS',
          },
        ],
      }),
    ]);
    final coordinator = _buildCoordinator(database, preferences, adapter);

    final report = await coordinator.sync('account-1');

    expect(report.synced, 1);
    expect(report.conflicts, 1);
    expect(await database.loadCards('account-1'), isEmpty);
    expect(await database.loadPendingSync('account-1'), isEmpty);
  });

  test('removes all local content in a deleted deck', () async {
    await database.saveCard(_buildCard('card-1', folder: 'deck-1'));
    await database.saveCard(_buildCard('card-2', folder: 'deck-2'));
    await database.saveDocument(
      DocumentModel(
        id: 'doc-1',
        accountId: 'account-1',
        folder: 'deck-1',
        title: 'Deck 1 note',
        body: 'body',
        updatedAt: DateTime(2026, 8, 1),
      ),
    );
    final adapter = _QueueAdapter([
      _FakeResponse.json({
        'syncTime': '2026-08-02T00:00:00.000Z',
        'deletions': [
          {'objectType': 'DECK', 'objectId': 'deck-1', 'folder': 'deck-1'},
        ],
      }),
    ]);
    final coordinator = _buildCoordinator(database, preferences, adapter);

    await coordinator.fullSync('account-1');

    expect((await database.loadCards('account-1')).map((card) => card.id), [
      'card-2',
    ]);
    expect(await database.loadDocuments('account-1'), isEmpty);
  });
}

SyncCoordinator _buildCoordinator(
  AppDatabase database,
  SharedPreferences preferences,
  _QueueAdapter adapter,
) {
  final dio = Dio()..httpClientAdapter = adapter;
  final client = ApiClient(
    config: const ApiConfig(baseUrl: 'http://test.invalid'),
    tokenReader: () async => 'test-token',
    dio: dio,
  );
  return SyncCoordinator(database, apiClient: client, preferences: preferences);
}

SyncQueueItemModel _buildQueueItem(
  String id,
  DateTime now, {
  String objectType = 'CARD',
  String objectId = 'card-1',
}) {
  return SyncQueueItemModel(
    id: id,
    accountId: 'account-1',
    objectType: objectType,
    objectId: objectId,
    objectVersion: 1,
    operation: SyncOperation.upsert,
    payload: jsonEncode({'id': objectId, 'question': 'question'}),
    status: SyncItemStatus.pending,
    attempts: 0,
    lastError: null,
    createdAt: now,
    updatedAt: now,
  );
}

CardModel _buildCard(String id, {required String folder}) {
  final now = DateTime(2026, 8, 1);
  return CardModel(
    id: id,
    accountId: 'account-1',
    type: CardType.single,
    folder: folder,
    question: 'question',
    options: const {'A': 'answer'},
    answer: const ['A'],
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
      difficulty: 0,
      reps: 0,
      lapses: 0,
    ),
  );
}

class _QueueAdapter implements HttpClientAdapter {
  _QueueAdapter(this.responses);

  final List<_FakeResponse> responses;
  final requests = <RequestOptions>[];
  var _index = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (_index >= responses.length) {
      return ResponseBody.fromString('{"responses":[]}', 200);
    }
    return responses[_index++].toBody();
  }

  @override
  void close({bool force = false}) {}
}

class _FakeResponse {
  const _FakeResponse(this.body, this.contentType);

  factory _FakeResponse.json(Map<String, dynamic> body) =>
      _FakeResponse(jsonEncode(body), Headers.jsonContentType);

  factory _FakeResponse.text(String body) =>
      _FakeResponse(body, Headers.textPlainContentType);

  final String body;
  final String contentType;

  ResponseBody toBody() => ResponseBody.fromString(
    body,
    200,
    headers: {
      Headers.contentTypeHeader: [contentType],
    },
  );
}
