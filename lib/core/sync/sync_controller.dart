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
          ? state.phase
          : SyncPhase.offline,
      message: online ? null : '?????????????????',
    );
  }

  bool _hasNetwork(List<ConnectivityResult> values) =>
      values.any((value) => value != ConnectivityResult.none);

  /// Runs one task at a time. A caller in the same account session only waits
  /// for the existing task; a caller after an account reset waits for the old
  /// task to fully exit and then starts a task for the new session.
  Future<void> sync({String reason = 'manual'}) async {
    final account = _account();
    if (account == null) return;
    final active = _activeSync;
    if (active != null) {
      final sameSession =
          _activeAccountId == account.id &&
          _activeGeneration == _sessionGeneration;
      await active;
      if (sameSession) return;
      if (identical(_activeSync, active)) {
        _clearActiveTask(active);
      }
    }
    await _startSync(reason);
  }

  Future<void> _startSync(String reason) {
    final active = _activeSync;
    if (active != null) return active;

    late final Future<void> task;
    task = _runSync(reason);
    _activeSync = task;
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
      _activeAccountId = null;
      _activeGeneration = null;
    }
  }

  Future<void> _runSync(String reason) async {
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
      state = state.copyWith(phase: SyncPhase.syncing, clearMessage: true);
    }

    try {
      final report = await _coordinator.sync(
        account.id,
        cancelToken: cancelToken,
      );
      if (report.networkFailure) {
        throw const ApiException(statusCode: null, message: '??????????????');
      }
      await _coordinator.fullSync(
        account.id,
        force: _coordinator.needsInitialFullSync(account.id),
        cancelToken: cancelToken,
      );
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
        message: complete
            ? '????'
            : '???????? $pending ??????? ${report.synced} ??',
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
      await _showFailure(account.id, generation, '???????$error');
    } finally {
      if (identical(_cancelToken, cancelToken)) _cancelToken = null;
    }
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
      return '????????????';
    }
    if (error.type == DioExceptionType.connectionError) {
      return '??????????????';
    }
    return '???????${error.message ?? '?????'}';
  }

  String _apiErrorMessage(ApiException error) {
    if (error.isNetworkFailure) return '??????????????';
    return '???????${error.message}';
  }

  /// Invalidates the current account generation immediately, but keeps the
  /// active task as a barrier until its cancellation and database work exit.
  Future<void> resetForAccountChange() async {
    _sessionGeneration++;
    _lastAutomaticSyncAt = null;
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
    await sync(reason: 'retry-pending');
  }

  @override
  void dispose() {
    _cancelToken?.cancel('controller disposed');
    _connectivitySubscription.cancel();
    super.dispose();
  }
}
