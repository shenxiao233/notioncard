import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
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
    unawaited(_refreshConnection());
    unawaited(refreshPending());
  }

  final SyncCoordinator _coordinator;
  final Connectivity _connectivity;
  final AccountModel? Function() _account;
  final FutureOr<void> Function()? onDataChanged;
  late final StreamSubscription<List<ConnectivityResult>>
  _connectivitySubscription;
  DateTime? _lastAutomaticSyncAt;
  CancelToken? _cancelToken;
  Future<void>? _activeSync;
  bool _activePullRemote = false;
  Timer? _scheduledSync;
  String? _activeAccountId;
  int? _activeGeneration;
  int _sessionGeneration = 0;
  static const _automaticSyncCooldown = Duration(seconds: 20);

  Future<void> _refreshConnection() async {
    final values = await _connectivity.checkConnectivity();
    if (!mounted) return;
    _updateConnection(values);
  }

  void _onConnectivityChanged(List<ConnectivityResult> values) {
    _updateConnection(values);
    if (_hasNetwork(values)) {
      unawaited(sync(reason: 'network-restored'));
    }
  }

  void _updateConnection(List<ConnectivityResult> values) {
    if (!mounted) return;
    final online = _hasNetwork(values);
    state = state.copyWith(
      connection: online
          ? SyncConnectionState.online
          : SyncConnectionState.offline,
      phase: online || state.phase == SyncPhase.syncing
          ? (online && state.phase == SyncPhase.offline
                ? SyncPhase.idle
                : state.phase)
          : SyncPhase.offline,
      message: online ? null : '当前处于离线状态，本地内容仍可使用，网络恢复后会自动同步',
    );
  }

  bool _hasNetwork(List<ConnectivityResult> values) =>
      values.any((value) => value != ConnectivityResult.none);

  /// Runs one task at a time. A caller in the same account session only waits
  /// for the existing task; a caller after an account reset waits for the old
  /// task to fully exit and then starts a task for the new session.
  Future<void> sync({String reason = 'manual'}) =>
      _requestSync(reason: reason, pullRemote: true);

  Future<void> pushPending({String reason = 'local-change'}) =>
      _requestSync(reason: reason, pullRemote: false);

  Future<void> _requestSync({
    required String reason,
    required bool pullRemote,
  }) async {
    _scheduledSync?.cancel();
    _scheduledSync = null;
    for (var pass = 0; pass < 2; pass++) {
      final account = _account();
      if (account == null) return;
      final active = _activeSync;
      if (active != null) {
        final sameSession =
            _activeAccountId == account.id &&
            _activeGeneration == _sessionGeneration;
        final activePullRemote = _activePullRemote;
        await active;
        if (sameSession) {
          // A review can be saved while the previous sync is in flight. If
          // that happened, drain the newly-created queue item once the first
          // task completes; otherwise preserve the existing single-flight
          // behavior.
          if (state.phase != SyncPhase.success) return;
          final pending = await _coordinator.pendingCount(account.id);
          final needsPull = pullRemote && !activePullRemote;
          if (pending == 0 && !needsPull) return;
          if (identical(_activeSync, active)) _clearActiveTask(active);
        } else if (identical(_activeSync, active)) {
          _clearActiveTask(active);
        }
      }
      await _startSync(reason, pullRemote: pullRemote);
      if (!mounted || state.phase != SyncPhase.success) return;
      final pending = await _coordinator.pendingCount(account.id);
      if (pending == 0) return;
    }
  }

  void scheduleSync({String reason = 'local-change'}) {
    _scheduledSync?.cancel();
    _scheduledSync = Timer(const Duration(milliseconds: 800), () {
      _scheduledSync = null;
      unawaited(pushPending(reason: reason));
    });
  }

  Future<void> _startSync(String reason, {required bool pullRemote}) {
    final active = _activeSync;
    if (active != null) return active;

    late final Future<void> task;
    task = _runSync(reason, pullRemote: pullRemote);
    _activeSync = task;
    _activePullRemote = pullRemote;
    _activeAccountId = _account()?.id;
    _activeGeneration = _sessionGeneration;
    unawaited(
      task.then<void>(
        (_) => _clearActiveTask(task),
        onError: (Object error, StackTrace stackTrace) =>
            _clearActiveTask(task),
      ),
    );
    return task;
  }

  void _clearActiveTask(Future<void> task) {
    if (identical(_activeSync, task)) {
      _activeSync = null;
      _activePullRemote = false;
      _activeAccountId = null;
      _activeGeneration = null;
    }
  }

  Future<void> _runSync(String reason, {required bool pullRemote}) async {
    final account = _account();
    if (account == null) return;

    final isAutomatic =
        reason == 'login' ||
        reason == 'resumed' ||
        reason == 'network-restored';
    final now = DateTime.now();
    if (isAutomatic &&
        _lastAutomaticSyncAt != null &&
        now.difference(_lastAutomaticSyncAt!) < _automaticSyncCooldown) {
      return;
    }

    final generation = _sessionGeneration;
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    if (mounted) {
      state = state.copyWith(
        phase: SyncPhase.syncing,
        message: '正在同步本地内容，阅读和复习不会被阻塞',
      );
    }

    try {
      final pendingBefore = await _coordinator.pendingCount(account.id);
      var report = const SyncReport();
      final requiresInitialPull = _coordinator.needsInitialFullSync(account.id);

      // Flush local changes first. This keeps the user's latest FSRS snapshot
      // ahead of a pull and lets the server return the current version for
      // conflict handling.
      if (pendingBefore > 0) {
        report = await _coordinator.pushPending(
          account.id,
          cancelToken: cancelToken,
        );
      }
      if (report.networkFailure) {
        throw const ApiException(statusCode: null, message: '网络连接不可用');
      }
      // Pulling is an explicit phase. Review sessions use pushPending(), so
      // they never perform a remote pull or merge while the user is studying.
      // Once the first pull has completed, use the account revision as a cheap
      // change detector. A normal local edit can be acknowledged without
      // downloading the whole account again.
      var shouldPullRemote = pullRemote;
      if (pullRemote && !requiresInitialPull) {
        if (pendingBefore == 0) {
          final status = await _coordinator.checkSyncStatus(account.id);
          if (status.revision != null) {
            await _coordinator.saveSyncRevision(account.id, status.revision);
          }
          shouldPullRemote = !status.supported || status.changed;
        } else {
          // A batch response carries the server revision it observed. If the
          // server did not return that field (old deployment), keep the old
          // safe behavior and pull once.
          shouldPullRemote =
              report.failed > 0 ||
              report.remoteChanged ||
              report.syncRevision == null;
        }
      }
      if (shouldPullRemote) {
        await _coordinator.fullSync(
          account.id,
          force: requiresInitialPull,
          cancelToken: cancelToken,
        );
        final tailReport = await _coordinator.pushPending(
          account.id,
          cancelToken: cancelToken,
        );
        report = _mergeReports(report, tailReport);
      }
      if (!_isCurrent(generation, cancelToken)) return;

      final pending = await _coordinator.pendingCount(account.id);
      if (!_isCurrent(generation, cancelToken)) return;
      await onDataChanged?.call();
      if (!_isCurrent(generation, cancelToken)) return;

      _lastAutomaticSyncAt = isAutomatic
          ? DateTime.now()
          : _lastAutomaticSyncAt;
      if (!mounted) return;
      final complete = pending == 0 && report.failed == 0;
      state = state.copyWith(
        phase: complete ? SyncPhase.success : SyncPhase.failure,
        pending: pending,
        lastSyncedAt: DateTime.now(),
        message: complete ? '同步完成' : '同步部分完成，仍有 $pending 项等待处理',
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) || cancelToken.isCancelled) return;
      _lastAutomaticSyncAt = null;
      await _showFailure(account.id, generation, _syncErrorMessage(error));
    } on ApiException catch (error) {
      if (!_isCurrent(generation, cancelToken)) return;
      _lastAutomaticSyncAt = null;
      await _showFailure(account.id, generation, _apiErrorMessage(error));
    } catch (error) {
      if (!_isCurrent(generation, cancelToken)) return;
      _lastAutomaticSyncAt = null;
      await _showFailure(account.id, generation, '同步失败，请稍后重试');
    } finally {
      if (identical(_cancelToken, cancelToken)) _cancelToken = null;
    }
  }

  SyncReport _mergeReports(SyncReport first, SyncReport second) {
    return SyncReport(
      synced: first.synced + second.synced,
      failed: first.failed + second.failed,
      conflicts: first.conflicts + second.conflicts,
      networkFailure: first.networkFailure || second.networkFailure,
      syncRevision: _latestRevision(first.syncRevision, second.syncRevision),
      remoteChanged: first.remoteChanged || second.remoteChanged,
    );
  }

  String? _latestRevision(String? first, String? second) {
    if (first == null || first.isEmpty) return second;
    if (second == null || second.isEmpty) return first;
    final firstValue = BigInt.tryParse(first);
    final secondValue = BigInt.tryParse(second);
    if (firstValue == null) return second;
    if (secondValue == null) return first;
    return secondValue > firstValue ? second : first;
  }

  bool _isCurrent(int generation, CancelToken cancelToken) =>
      mounted && generation == _sessionGeneration && !cancelToken.isCancelled;

  Future<void> _showFailure(
    String accountId,
    int generation,
    String message,
  ) async {
    if (!mounted || generation != _sessionGeneration) return;
    final pending = await _coordinator.pendingCount(accountId);
    if (!mounted || generation != _sessionGeneration) return;
    state = state.copyWith(
      phase: state.connection == SyncConnectionState.offline
          ? SyncPhase.offline
          : SyncPhase.failure,
      pending: pending,
      message: message,
    );
  }

  String _syncErrorMessage(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return '连接超时，请检查网络后重试';
    }
    if (error.type == DioExceptionType.connectionError) {
      return '无法连接到同步服务器';
    }
    return '同步失败，请稍后重试';
  }

  String _apiErrorMessage(ApiException error) {
    if (error.isNetworkFailure) return '网络连接不可用，请检查网络后重试';
    if (error.statusCode != null && error.statusCode! >= 500) {
      return '同步服务器暂时不可用，请稍后重试';
    }
    return '同步失败，请稍后重试';
  }

  /// Invalidates the current account generation immediately, but keeps the
  /// active task as a barrier until its cancellation and database work exit.
  Future<void> resetForAccountChange() async {
    _sessionGeneration++;
    _lastAutomaticSyncAt = null;
    _scheduledSync?.cancel();
    _scheduledSync = null;
    _cancelToken?.cancel('account changed');
    if (mounted) state = const SyncUiState();
  }

  Future<void> refreshPending() async {
    final generation = _sessionGeneration;
    final account = _account();
    if (account == null) {
      if (mounted && generation == _sessionGeneration) {
        state = state.copyWith(pending: 0);
      }
      return;
    }
    final pending = await _coordinator.pendingCount(account.id);
    if (mounted &&
        generation == _sessionGeneration &&
        _account()?.id == account.id) {
      state = state.copyWith(pending: pending);
    }
  }

  Future<void> retryPending() async {
    final account = _account();
    if (account == null) return;
    final generation = _sessionGeneration;
    await _coordinator.retryPending(account.id);
    if (generation != _sessionGeneration || _account()?.id != account.id) {
      return;
    }
    await pushPending(reason: 'retry-pending');
  }

  @override
  void dispose() {
    _scheduledSync?.cancel();
    _cancelToken?.cancel('controller disposed');
    _connectivitySubscription.cancel();
    super.dispose();
  }
}
