import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account_model.dart';
import '../network/api_exception.dart';
import 'sync_coordinator.dart';

enum SyncConnectionState { unknown, online, offline }

enum SyncPhase { idle, syncing, success, offline, failure }

class SyncUiState {
  const SyncUiState({
    this.connection = SyncConnectionState.unknown,
    this.phase = SyncPhase.idle,
    this.pending = 0,
    this.lastSyncedAt,
    this.message,
  });

  final SyncConnectionState connection;
  final SyncPhase phase;
  final int pending;
  final DateTime? lastSyncedAt;
  final String? message;

  bool get isBusy => phase == SyncPhase.syncing;

  SyncUiState copyWith({
    SyncConnectionState? connection,
    SyncPhase? phase,
    int? pending,
    DateTime? lastSyncedAt,
    String? message,
    bool clearMessage = false,
  }) => SyncUiState(
    connection: connection ?? this.connection,
    phase: phase ?? this.phase,
    pending: pending ?? this.pending,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    message: clearMessage ? null : message ?? this.message,
  );
}

class SyncController extends StateNotifier<SyncUiState> {
  SyncController(
    this._coordinator,
    this._connectivity,
    this._account, {
    this.onDataChanged,
  }) : super(const SyncUiState()) {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );
    _refreshConnection();
    refreshPending();
  }

  final SyncCoordinator _coordinator;
  final Connectivity _connectivity;
  final AccountModel? Function() _account;
  final FutureOr<void> Function()? onDataChanged;
  late final StreamSubscription<List<ConnectivityResult>>
  _connectivitySubscription;
  bool _running = false;

  Future<void> _refreshConnection() async {
    final values = await _connectivity.checkConnectivity();
    _updateConnection(values);
  }

  void _onConnectivityChanged(List<ConnectivityResult> values) {
    _updateConnection(values);
    if (_hasNetwork(values)) {
      unawaited(sync(reason: 'network-restored'));
    }
  }

  void _updateConnection(List<ConnectivityResult> values) {
    final online = _hasNetwork(values);
    state = state.copyWith(
      connection: online
          ? SyncConnectionState.online
          : SyncConnectionState.offline,
      phase: online || state.phase == SyncPhase.syncing
          ? state.phase
          : SyncPhase.offline,
      message: online ? null : '当前处于离线状态，本地复习仍可继续',
    );
  }

  bool _hasNetwork(List<ConnectivityResult> values) =>
      values.any((value) => value != ConnectivityResult.none);

  Future<void> sync({String reason = 'manual'}) async {
    if (_running) return;
    final account = _account();
    if (account == null) return;
    _running = true;
    state = state.copyWith(phase: SyncPhase.syncing, clearMessage: true);
    try {
      final report = await _coordinator.sync(account.id);
      if (report.networkFailure) {
        throw const ApiException(statusCode: null, message: '网络不可用，复习结果暂未上传');
      }
      await _coordinator.fullSync(
        account.id,
        force: _coordinator.needsInitialFullSync(account.id),
      );
      final pending = await _coordinator.pendingCount(account.id);
      await onDataChanged?.call();
      state = state.copyWith(
        phase: pending == 0 && report.failed == 0
            ? SyncPhase.success
            : SyncPhase.failure,
        pending: pending,
        lastSyncedAt: DateTime.now(),
        message: pending == 0 && report.failed == 0
            ? '同步完成'
            : '同步完成，但仍有 $pending 项待处理（成功 ${report.synced} 项）',
      );
    } catch (error) {
      final pending = await _coordinator.pendingCount(account.id);
      state = state.copyWith(
        phase: state.connection == SyncConnectionState.offline
            ? SyncPhase.offline
            : SyncPhase.failure,
        pending: pending,
        message: '同步暂未完成：$error',
      );
    } finally {
      _running = false;
    }
  }

  Future<void> refreshPending() async {
    final account = _account();
    if (account == null) {
      state = state.copyWith(pending: 0);
      return;
    }
    state = state.copyWith(
      pending: await _coordinator.pendingCount(account.id),
    );
  }

  Future<void> retryPending() async {
    final account = _account();
    if (account == null || _running) return;
    await _coordinator.retryPending(account.id);
    await sync(reason: 'retry-pending');
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }
}
