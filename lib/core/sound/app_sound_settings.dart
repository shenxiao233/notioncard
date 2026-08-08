import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_providers.dart';

const appSoundEnabledKey = 'app.sound.enabled';
const reviewSoundEnabledKey = 'app.sound.review_enabled';

class AppSoundSettings {
  const AppSoundSettings({
    this.enabled = true,
    this.reviewFeedbackEnabled = true,
  });

  final bool enabled;
  final bool reviewFeedbackEnabled;

  AppSoundSettings copyWith({bool? enabled, bool? reviewFeedbackEnabled}) {
    return AppSoundSettings(
      enabled: enabled ?? this.enabled,
      reviewFeedbackEnabled:
          reviewFeedbackEnabled ?? this.reviewFeedbackEnabled,
    );
  }
}

class AppSoundSettingsController extends StateNotifier<AppSoundSettings> {
  AppSoundSettingsController(this._preferences) : super(_load(_preferences));

  final SharedPreferences _preferences;

  static AppSoundSettings _load(SharedPreferences preferences) {
    return AppSoundSettings(
      enabled: preferences.getBool(appSoundEnabledKey) ?? true,
      reviewFeedbackEnabled: preferences.getBool(reviewSoundEnabledKey) ?? true,
    );
  }

  Future<void> setEnabled(bool value) async {
    await _preferences.setBool(appSoundEnabledKey, value);
    state = state.copyWith(enabled: value);
  }

  Future<void> setReviewFeedbackEnabled(bool value) async {
    await _preferences.setBool(reviewSoundEnabledKey, value);
    state = state.copyWith(reviewFeedbackEnabled: value);
  }
}

final appSoundSettingsProvider =
    StateNotifierProvider<AppSoundSettingsController, AppSoundSettings>(
      (ref) => AppSoundSettingsController(ref.watch(sharedPreferencesProvider)),
    );

enum AppSoundEvent {
  reviewAgain,
  reviewHard,
  reviewGood,
  reviewEasy,
  sessionComplete,
  syncSuccess,
  syncFailure,
}

extension on AppSoundEvent {
  bool get isReviewFeedback => switch (this) {
    AppSoundEvent.reviewAgain ||
    AppSoundEvent.reviewHard ||
    AppSoundEvent.reviewGood ||
    AppSoundEvent.reviewEasy => true,
    _ => false,
  };
}

class AppSoundService {
  AppSoundService(this._preferences);

  final SharedPreferences _preferences;

  Future<void> play(AppSoundEvent event) async {
    if (!(_preferences.getBool(appSoundEnabledKey) ?? true)) return;
    if (event.isReviewFeedback &&
        !(_preferences.getBool(reviewSoundEnabledKey) ?? true)) {
      return;
    }

    switch (event) {
      case AppSoundEvent.reviewAgain:
      case AppSoundEvent.reviewHard:
      case AppSoundEvent.syncSuccess:
        await _click();
      case AppSoundEvent.reviewGood:
        await _sequence(2, const Duration(milliseconds: 90));
      case AppSoundEvent.reviewEasy:
        await _sequence(3, const Duration(milliseconds: 90));
      case AppSoundEvent.sessionComplete:
        await _sequence(3, const Duration(milliseconds: 120));
        unawaited(HapticFeedback.successNotification());
      case AppSoundEvent.syncFailure:
        await _click();
        unawaited(HapticFeedback.warningNotification());
    }
  }

  Future<void> _sequence(int count, Duration gap) async {
    for (var index = 0; index < count; index++) {
      if (index > 0) await Future<void>.delayed(gap);
      await _click();
    }
  }

  Future<void> _click() => SystemSound.play(SystemSoundType.click);
}

final appSoundServiceProvider = Provider<AppSoundService>((ref) {
  return AppSoundService(ref.watch(sharedPreferencesProvider));
});
