import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../models/card_model.dart';
import '../models/document_model.dart';

part 'app_database.g.dart';

class Cards extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text()();
  TextColumn get type => text()();
  TextColumn get folder => text()();
  TextColumn get question => text()();
  TextColumn get optionsJson => text()();
  TextColumn get answerJson => text()();
  TextColumn get noteContent => text().withDefault(const Constant(''))();
  TextColumn get explanation => text().withDefault(const Constant(''))();
  TextColumn get tagsJson => text()();
  DateTimeColumn get dueAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get sortOrder => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get reviews => integer().withDefault(const Constant(0))();
  TextColumn get mastery => text().withDefault(const Constant(''))();
  BoolColumn get suspended => boolean().withDefault(const Constant(false))();
  TextColumn get fsrsJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {id, accountId};
}

class Documents extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text()();
  TextColumn get folder => text()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id, accountId};
}

class ReviewEvents extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text()();
  TextColumn get cardId => text()();
  TextColumn get question => text()();
  TextColumn get folder => text()();
  TextColumn get rating => text()();
  DateTimeColumn get reviewedAt => dateTime()();
  DateTimeColumn get nextDue => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id, accountId};
}

class SyncQueue extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text()();
  TextColumn get objectType => text()();
  TextColumn get objectId => text()();
  IntColumn get objectVersion => integer().withDefault(const Constant(1))();
  TextColumn get operation => text()();
  TextColumn get payloadJson => text()();
  TextColumn get status => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id, accountId};
}

@DriftDatabase(tables: [Cards, Documents, ReviewEvents, SyncQueue])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'kncard_app',
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.js'),
              ),
            ),
      );

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _createIndexes();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await m.createTable(syncQueue);
      } else if (from < 3) {
        await m.addColumn(syncQueue, syncQueue.objectVersion);
      }
      if (from < 4) await _createIndexes();
      if (from < 5) await _createIndexes();
      if (from < 6) {
        await m.addColumn(cards, cards.sortOrder);
        await customStatement(
          'DROP INDEX IF EXISTS idx_cards_account_due_order',
        );
        await _createIndexes();
      }
    },
  );

  Future<void> _createIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_cards_account_due '
      'ON cards (account_id, due_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_cards_account_due_order '
      'ON cards (account_id, due_at, sort_order, created_at, id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_documents_account_updated '
      'ON documents (account_id, updated_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_review_events_account_reviewed '
      'ON review_events (account_id, reviewed_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_account_status_created '
      'ON sync_queue (account_id, status, created_at)',
    );
  }

  Future<List<CardModel>> loadCards(String accountId) async {
    final rows =
        await (select(cards)
              ..where((row) => row.accountId.equals(accountId))
              ..orderBy([
                (row) => OrderingTerm(expression: row.dueAt),
                (row) => OrderingTerm(expression: row.createdAt),
                (row) => OrderingTerm(expression: row.id),
              ]))
            .get();
    return rows.map(_cardFromRow).toList();
  }

  Future<CardModel?> loadCard(String id, String accountId) async {
    final row =
        await (select(cards)..where(
              (value) =>
                  value.id.equals(id) & value.accountId.equals(accountId),
            ))
            .getSingleOrNull();
    return row == null ? null : _cardFromRow(row);
  }

  Future<void> replaceCards(String accountId, List<CardModel> values) async {
    await transaction(() async {
      await (delete(
        cards,
      )..where((row) => row.accountId.equals(accountId))).go();
      await batch((batch) {
        batch.insertAll(cards, values.map(_cardToCompanion).toList());
      });
    });
  }

  Future<void> saveCard(CardModel value) =>
      into(cards).insertOnConflictUpdate(_cardToCompanion(value));

  Future<void> saveCards(Iterable<CardModel> values) async {
    final companions = values.map(_cardToCompanion).toList();
    if (companions.isEmpty) return;
    await batch((batch) {
      batch.insertAllOnConflictUpdate(cards, companions);
    });
  }

  Future<void> deleteCard(String id, String accountId) => (delete(
    cards,
  )..where((row) => row.id.equals(id) & row.accountId.equals(accountId))).go();

  Future<void> deleteCardsByIds(String accountId, Iterable<String> ids) async {
    final values = ids.where((id) => id.isNotEmpty).toSet();
    if (values.isEmpty) return;
    await (delete(cards)..where(
          (row) => row.accountId.equals(accountId) & row.id.isIn(values),
        ))
        .go();
  }

  Future<void> deleteCardsByFolder(String folder, String accountId) =>
      (delete(cards)..where(
            (row) =>
                row.folder.equals(folder) & row.accountId.equals(accountId),
          ))
          .go();

  Future<int> countCardsByFolder(String accountId, String folder) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS card_count FROM cards '
      'WHERE account_id = ? AND folder = ?',
      variables: [Variable<String>(accountId), Variable<String>(folder)],
      readsFrom: {cards},
    ).getSingle();
    return row.read<int>('card_count');
  }

  Future<int> updateCardsFolder({
    required String accountId,
    required String fromFolder,
    required String toFolder,
    DateTime? updatedAt,
  }) =>
      (update(cards)..where(
            (row) =>
                row.accountId.equals(accountId) & row.folder.equals(fromFolder),
          ))
          .write(
            CardsCompanion(
              folder: Value(toFolder),
              // A deck rename is a collection-level metadata change. Do not
              // touch every card's content timestamp, otherwise later dirty
              // checks can mistake the rename for N card edits.
              updatedAt: updatedAt == null
                  ? const Value.absent()
                  : Value(updatedAt),
            ),
          );

  Future<void> deleteReviewEventsByCard(String cardId, String accountId) =>
      (delete(reviewEvents)..where(
            (row) =>
                row.cardId.equals(cardId) & row.accountId.equals(accountId),
          ))
          .go();

  Future<void> deleteReviewEventsByCards(
    String accountId,
    Iterable<String> cardIds,
  ) async {
    final ids = cardIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return;
    await (delete(reviewEvents)..where(
          (row) => row.accountId.equals(accountId) & row.cardId.isIn(ids),
        ))
        .go();
  }

  Future<List<DocumentModel>> loadDocuments(String accountId) async {
    final rows =
        await (select(documents)
              ..where((row) => row.accountId.equals(accountId))
              ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
            .get();
    return rows
        .map(
          (row) => DocumentModel(
            id: row.id,
            accountId: row.accountId,
            folder: row.folder,
            title: row.title,
            body: row.body,
            updatedAt: row.updatedAt,
          ),
        )
        .toList();
  }

  Future<void> replaceDocuments(
    String accountId,
    List<DocumentModel> values,
  ) async {
    await transaction(() async {
      await (delete(
        documents,
      )..where((row) => row.accountId.equals(accountId))).go();
      await batch((batch) {
        batch.insertAll(
          documents,
          values
              .map(
                (value) => DocumentsCompanion.insert(
                  id: value.id,
                  accountId: value.accountId,
                  folder: value.folder,
                  title: value.title,
                  body: value.body,
                  updatedAt: value.updatedAt,
                ),
              )
              .toList(),
        );
      });
    });
  }

  Future<void> saveDocument(DocumentModel value) =>
      into(documents).insertOnConflictUpdate(
        DocumentsCompanion.insert(
          id: value.id,
          accountId: value.accountId,
          folder: value.folder,
          title: value.title,
          body: value.body,
          updatedAt: value.updatedAt,
        ),
      );

  Future<void> saveDocuments(Iterable<DocumentModel> values) async {
    final companions = values
        .map(
          (value) => DocumentsCompanion.insert(
            id: value.id,
            accountId: value.accountId,
            folder: value.folder,
            title: value.title,
            body: value.body,
            updatedAt: value.updatedAt,
          ),
        )
        .toList();
    if (companions.isEmpty) return;
    await batch((batch) {
      batch.insertAllOnConflictUpdate(documents, companions);
    });
  }

  Future<void> deleteDocument(String id, String accountId) => (delete(
    documents,
  )..where((row) => row.id.equals(id) & row.accountId.equals(accountId))).go();

  Future<void> deleteDocumentsByIds(
    String accountId,
    Iterable<String> ids,
  ) async {
    final values = ids.where((id) => id.isNotEmpty).toSet();
    if (values.isEmpty) return;
    await (delete(documents)..where(
          (row) => row.accountId.equals(accountId) & row.id.isIn(values),
        ))
        .go();
  }

  Future<void> deleteDocumentsByFolder(String folder, String accountId) =>
      (delete(documents)..where(
            (row) =>
                row.folder.equals(folder) & row.accountId.equals(accountId),
          ))
          .go();

  Future<void> updateReviewEventsFolder({
    required String accountId,
    required String fromFolder,
    required String toFolder,
  }) =>
      (update(reviewEvents)..where(
            (row) =>
                row.accountId.equals(accountId) & row.folder.equals(fromFolder),
          ))
          .write(ReviewEventsCompanion(folder: Value(toFolder)));

  Future<List<ReviewEventModel>> loadReviewEvents(String accountId) async {
    final rows =
        await (select(reviewEvents)
              ..where((row) => row.accountId.equals(accountId))
              ..orderBy([(row) => OrderingTerm.desc(row.reviewedAt)]))
            .get();
    return rows
        .map(
          (row) => ReviewEventModel(
            id: row.id,
            accountId: row.accountId,
            cardId: row.cardId,
            question: row.question,
            folder: row.folder,
            rating: ReviewRating.values.firstWhere(
              (value) => value.name == row.rating,
              orElse: () => ReviewRating.again,
            ),
            reviewedAt: row.reviewedAt,
            nextDue: row.nextDue,
          ),
        )
        .toList();
  }

  Future<void> saveReviewEvent(ReviewEventModel value) =>
      into(reviewEvents).insert(
        ReviewEventsCompanion.insert(
          id: value.id,
          accountId: value.accountId,
          cardId: value.cardId,
          question: value.question,
          folder: value.folder,
          rating: value.rating.name,
          reviewedAt: value.reviewedAt,
          nextDue: value.nextDue,
        ),
      );

  Future<List<SyncQueueItemModel>> loadPendingSync(String accountId) async {
    final rows =
        await (select(syncQueue)
              ..where(
                (row) =>
                    row.accountId.equals(accountId) &
                    (row.status.equals('pending') |
                        row.status.equals('failed')),
              )
              ..orderBy([(row) => OrderingTerm(expression: row.createdAt)]))
            .get();
    return rows.map(_syncFromRow).toList();
  }

  Future<SyncQueueItemModel?> loadPendingSyncItem(
    String accountId, {
    required String objectType,
    required String objectId,
  }) async {
    final row =
        await (select(syncQueue)
              ..where(
                (value) =>
                    value.accountId.equals(accountId) &
                    value.objectType.equals(objectType) &
                    value.objectId.equals(objectId) &
                    (value.status.equals('pending') |
                        value.status.equals('failed')),
              )
              ..orderBy([(value) => OrderingTerm.desc(value.updatedAt)])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _syncFromRow(row);
  }

  Future<int> countPendingSync(String accountId) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS pending_count FROM sync_queue '
      'WHERE account_id = ? AND status IN (?, ?)',
      variables: [
        Variable<String>(accountId),
        const Variable<String>('pending'),
        const Variable<String>('failed'),
      ],
      readsFrom: {syncQueue},
    ).getSingle();
    return row.read<int>('pending_count');
  }

  Future<void> enqueueSync(SyncQueueItemModel value) async {
    await transaction(() async {
      // Keep only the newest unsent snapshot for an object. The queue row ID
      // is also its mutationId, so replacing the row creates a new idempotent
      // mutation while preventing review sessions from building an unbounded
      // backlog of obsolete progress states. The delete and insert must be
      // one transaction: direct callers such as settings can otherwise
      // interleave and leave two snapshots for the same object.
      await (delete(syncQueue)..where(
            (row) =>
                row.accountId.equals(value.accountId) &
                row.objectType.equals(value.objectType) &
                row.objectId.equals(value.objectId),
          ))
          .go();
      await into(syncQueue).insert(
        SyncQueueCompanion.insert(
          id: value.id,
          accountId: value.accountId,
          objectType: value.objectType,
          objectId: value.objectId,
          objectVersion: Value(value.objectVersion),
          operation: value.operation.name,
          payloadJson: value.payload,
          status: value.status.name,
          attempts: Value(value.attempts),
          lastError: Value(value.lastError),
          updatedAt: value.updatedAt,
          createdAt: value.createdAt,
        ),
      );
    });
  }

  Future<void> enqueueSyncItems(Iterable<SyncQueueItemModel> values) async {
    final latestByObject = <String, SyncQueueItemModel>{};
    for (final value in values) {
      final key =
          '${value.accountId}\u0000${value.objectType}\u0000${value.objectId}';
      final previous = latestByObject[key];
      if (previous == null || !value.updatedAt.isBefore(previous.updatedAt)) {
        latestByObject[key] = value;
      }
    }
    // Callers normally provide one item per object, but enforcing that here
    // prevents a malformed/retried batch from creating duplicate mutations.
    final items = latestByObject.values.toList(growable: false);
    final companions = items
        .map(
          (value) => SyncQueueCompanion.insert(
            id: value.id,
            accountId: value.accountId,
            objectType: value.objectType,
            objectId: value.objectId,
            objectVersion: Value(value.objectVersion),
            operation: value.operation.name,
            payloadJson: value.payload,
            status: value.status.name,
            attempts: Value(value.attempts),
            lastError: Value(value.lastError),
            createdAt: value.createdAt,
            updatedAt: value.updatedAt,
          ),
        )
        .toList();
    if (companions.isEmpty) return;

    await transaction(() async {
      // A mutation queue stores only the newest snapshot for each object. The
      // old implementation deleted one row at a time, which made a 1,210-card
      // relearn execute 1,210 SQLite statements before it could insert the new
      // snapshots. Group the deletes by account/type and chunk the IN clause so
      // this remains below SQLite's bound-variable limit on Android. Keep the
      // replacement atomic for direct callers as well.
      final objectIdsByScope = <String, Map<String, Set<String>>>{};
      for (final value in items) {
        objectIdsByScope
            .putIfAbsent(value.accountId, () => <String, Set<String>>{})
            .putIfAbsent(value.objectType, () => <String>{})
            .add(value.objectId);
      }
      for (final accountEntry in objectIdsByScope.entries) {
        for (final typeEntry in accountEntry.value.entries) {
          final ids = typeEntry.value.toList(growable: false);
          for (var offset = 0; offset < ids.length; offset += 400) {
            final chunk = ids.skip(offset).take(400).toSet();
            await (delete(syncQueue)..where(
                  (row) =>
                      row.accountId.equals(accountEntry.key) &
                      row.objectType.equals(typeEntry.key) &
                      row.objectId.isIn(chunk),
                ))
                .go();
          }
        }
      }
      await batch((batch) {
        batch.insertAllOnConflictUpdate(syncQueue, companions);
      });
    });
  }

  Future<void> markSyncFailed(
    String id,
    String accountId,
    String message,
  ) async {
    final row =
        await (select(syncQueue)..where(
              (value) =>
                  value.id.equals(id) & value.accountId.equals(accountId),
            ))
            .getSingleOrNull();
    if (row == null) return;
    await (update(syncQueue)..where(
          (value) => value.id.equals(id) & value.accountId.equals(accountId),
        ))
        .write(
          SyncQueueCompanion(
            status: const Value('failed'),
            attempts: Value(row.attempts + 1),
            lastError: Value(message),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> markSyncFailedItems(
    String accountId,
    Iterable<SyncQueueItemModel> values,
    String message,
  ) async {
    final ids = values
        .map((value) => value.id)
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return;
    final rows =
        await (select(syncQueue)..where(
              (row) => row.accountId.equals(accountId) & row.id.isIn(ids),
            ))
            .get();
    final now = DateTime.now();
    await batch((batch) {
      for (final row in rows) {
        batch.update(
          syncQueue,
          SyncQueueCompanion(
            status: const Value('failed'),
            attempts: Value(row.attempts + 1),
            lastError: Value(message),
            updatedAt: Value(now),
          ),
          where: (value) =>
              value.accountId.equals(accountId) & value.id.equals(row.id),
        );
      }
    });
  }

  Future<void> markSyncSynced(String id, String accountId) =>
      (delete(syncQueue)..where(
            (value) => value.id.equals(id) & value.accountId.equals(accountId),
          ))
          .go();

  Future<void> markSyncItemsSynced(
    String accountId,
    Iterable<String> itemIds,
  ) async {
    final ids = itemIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return;
    await (delete(
      syncQueue,
    )..where((row) => row.accountId.equals(accountId) & row.id.isIn(ids))).go();
  }

  Future<void> markPendingSyncObjectsSynced(
    String accountId,
    Iterable<String> objectIds,
  ) async {
    final ids = objectIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return;
    await (delete(syncQueue)..where(
          (row) => row.accountId.equals(accountId) & row.objectId.isIn(ids),
        ))
        .go();
  }

  Future<void> discardPendingSyncItems(
    String accountId, {
    required String objectType,
    required Iterable<String> objectIds,
  }) async {
    final ids = objectIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return;
    await (delete(syncQueue)..where(
          (row) =>
              row.accountId.equals(accountId) &
              row.objectType.equals(objectType) &
              row.objectId.isIn(ids),
        ))
        .go();
  }

  SyncQueueItemModel _syncFromRow(SyncQueueData row) => SyncQueueItemModel(
    id: row.id,
    accountId: row.accountId,
    objectType: row.objectType,
    objectId: row.objectId,
    objectVersion: row.objectVersion,
    operation: SyncOperation.values.firstWhere(
      (value) => value.name == row.operation,
      orElse: () => SyncOperation.upsert,
    ),
    payload: row.payloadJson,
    status: SyncItemStatus.values.firstWhere(
      (value) => value.name == row.status,
      orElse: () => SyncItemStatus.pending,
    ),
    attempts: row.attempts,
    lastError: row.lastError,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  CardModel _cardFromRow(Card row) {
    final fsrs = jsonDecode(row.fsrsJson) as Map<String, dynamic>;
    return CardModel(
      id: row.id,
      accountId: row.accountId,
      type: CardType.values.firstWhere(
        (value) => value.name == row.type,
        orElse: () => CardType.single,
      ),
      folder: row.folder,
      question: row.question,
      options: Map<String, String>.from(jsonDecode(row.optionsJson) as Map),
      answer: List<String>.from(jsonDecode(row.answerJson) as List),
      noteContent: row.noteContent,
      explanation: row.explanation,
      tags: List<String>.from(jsonDecode(row.tagsJson) as List),
      dueAt: row.dueAt,
      createdAt: row.createdAt,
      sortOrder: row.sortOrder,
      updatedAt: row.updatedAt,
      reviews: row.reviews,
      mastery: row.mastery,
      suspended: row.suspended,
      fsrs: FsrsSnapshot(
        state: FsrsState.values.firstWhere(
          (value) => value.name == fsrs['state'],
        ),
        dueAt: DateTime.parse(fsrs['dueAt'] as String),
        stability: (fsrs['stability'] as num).toDouble(),
        difficulty: (fsrs['difficulty'] as num).toDouble(),
        reps: fsrs['reps'] as int,
        lapses: fsrs['lapses'] as int,
      ),
    );
  }

  CardsCompanion _cardToCompanion(CardModel value) => CardsCompanion.insert(
    id: value.id,
    accountId: value.accountId,
    type: value.type.name,
    folder: value.folder,
    question: value.question,
    optionsJson: jsonEncode(value.options),
    answerJson: jsonEncode(value.answer),
    noteContent: Value(value.noteContent),
    explanation: Value(value.explanation),
    tagsJson: jsonEncode(value.tags),
    dueAt: value.dueAt,
    createdAt: value.createdAt,
    sortOrder: Value(value.sortOrder),
    updatedAt: value.updatedAt,
    reviews: Value(value.reviews),
    mastery: Value(value.mastery),
    suspended: Value(value.suspended),
    fsrsJson: jsonEncode({
      'state': value.fsrs.state.name,
      'dueAt': value.fsrs.dueAt.toIso8601String(),
      'stability': value.fsrs.stability,
      'difficulty': value.fsrs.difficulty,
      'reps': value.fsrs.reps,
      'lapses': value.fsrs.lapses,
    }),
  );
}
