import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_providers.dart';

class ReviewSettings {
  const ReviewSettings({this.newCardsPerDay = 20, this.reviewsPerDay = 100});

  final int newCardsPerDay;
  final int reviewsPerDay;

  ReviewSettings copyWith({int? newCardsPerDay, int? reviewsPerDay}) {
    return ReviewSettings(
      newCardsPerDay: newCardsPerDay ?? this.newCardsPerDay,
      reviewsPerDay: reviewsPerDay ?? this.reviewsPerDay,
    );
  }
}

class ReviewSettingsController extends StateNotifier<ReviewSettings> {
  ReviewSettingsController(this._preferences, this._accountId)
    : super(_load(_preferences, _accountId));

  static const _newCardsKey = 'review.new_cards_per_day';
  static const _reviewsKey = 'review.reviews_per_day';

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
    );
  }

  static int _readInt(
    SharedPreferences preferences,
    String key,
    String accountId,
    int fallback,
  ) {
    final value = preferences.getInt('$key.$accountId');
    return value == null ? fallback : value.clamp(0, 9999);
  }

  Future<void> setNewCardsPerDay(int value) async {
    final normalized = value.clamp(0, 9999);
    state = state.copyWith(newCardsPerDay: normalized);
    if (_accountId != null) {
      await _preferences.setInt('$_newCardsKey.$_accountId', normalized);
    }
  }

  Future<void> setReviewsPerDay(int value) async {
    final normalized = value.clamp(0, 9999);
    state = state.copyWith(reviewsPerDay: normalized);
    if (_accountId != null) {
      await _preferences.setInt('$_reviewsKey.$_accountId', normalized);
    }
  }
}

final reviewSettingsProvider =
    StateNotifierProvider<ReviewSettingsController, ReviewSettings>((ref) {
      return ReviewSettingsController(
        ref.watch(sharedPreferencesProvider),
        ref.watch(currentAccountProvider)?.id,
      );
    });
