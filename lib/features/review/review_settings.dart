import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_providers.dart';

const reviewSelectedFolderKeyPrefix = 'review.selected_folder';

String reviewSelectedFolderKey(String accountId) =>
    '$reviewSelectedFolderKeyPrefix.$accountId';

String? loadSelectedReviewFolder(
  SharedPreferences preferences,
  String? accountId,
) {
  if (accountId == null) return null;
  return preferences.getString(reviewSelectedFolderKey(accountId));
}

Future<bool> saveSelectedReviewFolder(
  SharedPreferences preferences,
  String? accountId,
  String? folder,
) {
  if (accountId == null) return Future.value(true);
  if (folder == null || folder.isEmpty) {
    return preferences.remove(reviewSelectedFolderKey(accountId));
  }
  return preferences.setString(reviewSelectedFolderKey(accountId), folder);
}

class ReviewSettings {
  const ReviewSettings({
    this.newCardsPerDay = 20,
    this.reviewsPerDay = 100,
    this.autonomousLearning = false,
  });

  final int newCardsPerDay;
  final int reviewsPerDay;
  final bool autonomousLearning;

  ReviewSettings copyWith({
    int? newCardsPerDay,
    int? reviewsPerDay,
    bool? autonomousLearning,
  }) {
    return ReviewSettings(
      newCardsPerDay: newCardsPerDay ?? this.newCardsPerDay,
      reviewsPerDay: reviewsPerDay ?? this.reviewsPerDay,
      autonomousLearning: autonomousLearning ?? this.autonomousLearning,
    );
  }
}

class ReviewSettingsController extends StateNotifier<ReviewSettings> {
  ReviewSettingsController(this._preferences, this._accountId)
    : super(_load(_preferences, _accountId));

  static const _newCardsKey = 'review.new_cards_per_day';
  static const _reviewsKey = 'review.reviews_per_day';
  static const _autonomousLearningKey = 'review.autonomous_learning';

  final SharedPreferences _preferences;
  final String? _accountId;

  static ReviewSettings _load(
    SharedPreferences preferences,
    String? accountId,
  ) {
    if (accountId == null) return const ReviewSettings();
    return ReviewSettings(
      newCardsPerDay: _readInt(preferences, _newCardsKey, accountId, 20),
      reviewsPerDay: _readInt(preferences, _reviewsKey, accountId, 100),
      autonomousLearning: _readBool(
        preferences,
        _autonomousLearningKey,
        accountId,
        false,
      ),
    );
  }

  static int _readInt(
    SharedPreferences preferences,
    String key,
    String accountId,
    int fallback,
  ) {
    final raw = preferences.get('$key.$accountId');
    final value = raw is num ? raw.toInt() : int.tryParse('$raw');
    return _normalize(value ?? fallback);
  }

  static bool _readBool(
    SharedPreferences preferences,
    String key,
    String accountId,
    bool fallback,
  ) {
    final raw = preferences.get('$key.$accountId');
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final normalized = '$raw'.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
    return fallback;
  }

  Future<void> setNewCardsPerDay(int value) async {
    final normalized = _normalize(value);
    if (_accountId != null) {
      await _preferences.setInt('$_newCardsKey.$_accountId', normalized);
    }
    state = state.copyWith(newCardsPerDay: normalized);
  }

  Future<void> setReviewsPerDay(int value) async {
    final normalized = _normalize(value);
    if (_accountId != null) {
      await _preferences.setInt('$_reviewsKey.$_accountId', normalized);
    }
    state = state.copyWith(reviewsPerDay: normalized);
  }

  Future<void> setAutonomousLearning(bool enabled) async {
    if (_accountId != null) {
      await _preferences.setBool(
        '$_autonomousLearningKey.$_accountId',
        enabled,
      );
    }
    state = state.copyWith(autonomousLearning: enabled);
  }

  static int _normalize(int value) {
    if (value < 0) return 0;
    if (value > 9999) return 9999;
    return value;
  }
}

final reviewSettingsProvider =
    StateNotifierProvider<ReviewSettingsController, ReviewSettings>((ref) {
      return ReviewSettingsController(
        ref.watch(sharedPreferencesProvider),
        ref.watch(currentAccountProvider)?.id,
      );
    });
