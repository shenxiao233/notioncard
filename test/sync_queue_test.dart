import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kncard_app/core/database/app_database.dart';
import 'package:kncard_app/core/models/card_model.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('sync queue stores pending items and updates failures', () async {
    final now = DateTime(2026, 8, 1);
    await database.enqueueSync(
      SyncQueueItemModel(
        id: 'sync-1',
        accountId: 'account-1',
        objectType: 'REVIEW_EVENT',
        objectId: 'event-1',
        operation: SyncOperation.upsert,
        payload: '{}',
        status: SyncItemStatus.pending,
        attempts: 0,
        lastError: null,
        createdAt: now,
        updatedAt: now,
      ),
    );

    expect(await database.countPendingSync('account-1'), 1);
    await database.markSyncFailed('sync-1', 'account-1', 'offline');
    final items = await database.loadPendingSync('account-1');
    expect(items.single.status, SyncItemStatus.failed);
    expect(items.single.attempts, 1);
    expect(items.single.lastError, 'offline');
    await database.markSyncSynced('sync-1', 'account-1');
    expect(await database.countPendingSync('account-1'), 0);
  });
}
