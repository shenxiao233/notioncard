import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_providers.dart';
import '../../core/database/app_database.dart';
import '../../core/models/card_model.dart';

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
  String? folder, {
  AppDatabase? database,
}) {
  if (accountId == null) return Future.value(true);
  return _saveSelectedReviewFolder(
    preferences,
    accountId,
    folder,
    database: database,
  );
}

Future<bool> _saveSelectedReviewFolder(
  SharedPreferences preferences,
  String accountId,
  String? folder, {
  AppDatabase? database,
}) async {
  final saved = folder == null || folder.isEmpty
      ? await preferences.remove(reviewSelectedFolderKey(accountId))
      : await preferences.setString(reviewSelectedFolderKey(accountId), folder);
  if (saved && database != null) {
    await _enqueueReviewSettingsSync(
      preferences: preferences,
      database: database,
      accountId: accountId,
    );
  }
  return saved;
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
  ReviewSettingsController(this._preferences, this._accountId, [this._database])
    : super(_load(_preferences, _accountId));

  static const _newCardsKey = 'review.new_cards_per_day';
  static const _reviewsKey = 'review.reviews_per_day';
  static const _autonomousLearningKey = 'review.autonomous_learning';

  final SharedPreferences _preferences;
  final String? _accountId;
  final AppDatabase? _database;
  final Random _mutationRandom = Random.secure();

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
    await _enqueueSync();
  }

  Future<void> setReviewsPerDay(int value) async {
    final normalized = _normalize(value);
    if (_accountId != null) {
      await _preferences.setInt('$_reviewsKey.$_accountId', normalized);
    }
    state = state.copyWith(reviewsPerDay: normalized);
    await _enqueueSync();
  }

  Future<void> setAutonomousLearning(bool enabled) async {
    if (_accountId != null) {
      await _preferences.setBool(
        '$_autonomousLearningKey.$_accountId',
        enabled,
      );
    }
    state = state.copyWith(autonomousLearning: enabled);
    await _enqueueSync();
  }

  Future<void> _enqueueSync() async {
    final accountId = _accountId;
    final database = _database;
    if (accountId == null || database == null) return;
    await _enqueueReviewSettingsSync(
      preferences: _preferences,
      database: database,
      accountId: accountId,
      settings: state,
      random: _mutationRandom,
    );
  }

  static int _normalize(int value) {
    if (value < 0) return 0;
    if (value > 9999) return 9999;
    return value;
  }
}

Future<void> _enqueueReviewSettingsSync({
  required SharedPreferences preferences,
  required AppDatabase database,
  required String accountId,
  ReviewSettings? settings,
  Random? random,
}) async {
  final value =
      settings ?? ReviewSettingsController._load(preferences, accountId);
  final now = DateTime.now();
  final mutationRandom = random ?? Random.secure();
  await database.enqueueSync(
    SyncQueueItemModel(
      id: 'settings-review-$accountId-${now.microsecondsSinceEpoch}-${mutationRandom.nextInt(1 << 32)}',
      accountId: accountId,
      objectType: 'SETTINGS',
      objectId: 'review',
      objectVersion: 1,
      operation: SyncOperation.upsert,
      payload: jsonEncode({
        'newCardsPerDay': value.newCardsPerDay,
        'reviewsPerDay': value.reviewsPerDay,
        'autonomousLearning': value.autonomousLearning,
        'selectedFolder': loadSelectedReviewFolder(preferences, accountId),
      }),
      status: SyncItemStatus.pending,
      attempts: 0,
      lastError: null,
      createdAt: now,
      updatedAt: now,
    ),
  );
}

final reviewSettingsProvider =
    StateNotifierProvider<ReviewSettingsController, ReviewSettings>((ref) {
      ref.watch(remoteSettingsRevisionProvider);
      return ReviewSettingsController(
        ref.watch(sharedPreferencesProvider),
        ref.watch(currentAccountProvider)?.id,
        ref.watch(appDatabaseProvider),
      );
    });
