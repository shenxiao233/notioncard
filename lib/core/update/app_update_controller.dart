import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_update_model.dart';
import 'app_update_service.dart';

enum AppUpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  installing,
  installed,
  error,
}

class AppUpdateState {
  const AppUpdateState({
    this.status = AppUpdateStatus.idle,
    this.manifest,
    this.progress = 0,
    this.message,
    this.errorCode,
    this.checkedAt,
  });

  final AppUpdateStatus status;
  final AppUpdateManifest? manifest;
  final double progress;
  final String? message;
  final String? errorCode;
  final DateTime? checkedAt;

  bool get hasUpdate =>
      manifest != null &&
      (status == AppUpdateStatus.available || status == AppUpdateStatus.error);

  bool get isBusy =>
      status == AppUpdateStatus.checking ||
      status == AppUpdateStatus.downloading ||
      status == AppUpdateStatus.installing;
}

class AppUpdateController extends StateNotifier<AppUpdateState> {
  AppUpdateController(this._service) : super(const AppUpdateState()) {
    unawaited(check(silent: true));
  }

  final AppUpdateService _service;
  bool _checkRunning = false;

  Future<void> check({bool silent = false}) async {
    if (_checkRunning || state.isBusy) return;
    _checkRunning = true;
    if (!silent) {
      state = const AppUpdateState(status: AppUpdateStatus.checking);
    }
    try {
      final manifest = await _service.checkForUpdate();
      state = AppUpdateState(
        status: manifest == null
            ? AppUpdateStatus.upToDate
            : AppUpdateStatus.available,
        manifest: manifest,
        checkedAt: DateTime.now(),
      );
    } catch (error) {
      state = AppUpdateState(
        status: AppUpdateStatus.error,
        message: _message(error),
        checkedAt: DateTime.now(),
      );
    } finally {
      _checkRunning = false;
    }
  }

  Future<void> downloadAndInstall() async {
    final manifest = state.manifest;
    if (manifest == null || !manifest.canDownload || state.isBusy) return;

    state = AppUpdateState(
      status: AppUpdateStatus.downloading,
      manifest: manifest,
      progress: 0,
    );
    try {
      final file = await _service.downloadAndVerify(
        manifest,
        onProgress: (received, total) {
          if (total > 0 && !state.isBusy) return;
          state = AppUpdateState(
            status: AppUpdateStatus.downloading,
            manifest: manifest,
            progress: total > 0 ? received / total : 0,
          );
        },
      );
      state = AppUpdateState(
        status: AppUpdateStatus.installing,
        manifest: manifest,
        progress: 1,
        message: '下载完成，正在打开系统安装器',
      );
      await _service.installAndroidApk(file);
      state = AppUpdateState(
        status: AppUpdateStatus.installed,
        manifest: manifest,
        progress: 1,
        message: '安装器已打开，请完成系统安装',
      );
    } catch (error) {
      state = AppUpdateState(
        status: AppUpdateStatus.error,
        manifest: manifest,
        message: _message(error),
        errorCode: error is AppUpdateException ? error.code : null,
      );
    }
  }

  Future<void> openInstallPermissionSettings() {
    return _service.openAndroidInstallPermissionSettings();
  }

  String _message(Object error) {
    if (error is AppUpdateException) return error.message;
    return '检查更新失败，请稍后重试';
  }
}
