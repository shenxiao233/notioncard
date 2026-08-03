import 'package:flutter_test/flutter_test.dart';
import 'package:kncard_app/core/sync/sync_controller.dart';

void main() {
  test('SyncUiState copyWith preserves and updates sync metadata', () {
    final syncedAt = DateTime(2026, 8, 1, 12);
    const initial = SyncUiState(
      connection: SyncConnectionState.offline,
      phase: SyncPhase.offline,
      pending: 2,
      message: 'offline',
    );

    final updated = initial.copyWith(
      connection: SyncConnectionState.online,
      phase: SyncPhase.success,
      pending: 0,
      lastSyncedAt: syncedAt,
      message: 'done',
    );

    expect(updated.connection, SyncConnectionState.online);
    expect(updated.phase, SyncPhase.success);
    expect(updated.pending, 0);
    expect(updated.lastSyncedAt, syncedAt);
    expect(updated.message, 'done');
    expect(initial.pending, 2);
    expect(initial.message, 'offline');
  });

  test('SyncUiState clearMessage removes a previous status message', () {
    const state = SyncUiState(message: 'previous status');

    expect(state.copyWith(clearMessage: true).message, isNull);
  });
}
