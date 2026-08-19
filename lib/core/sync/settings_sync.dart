import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../models/card_model.dart';

const cardFavoritesKeyPrefix = 'card.favorites';

String cardFavoritesKey(String accountId) =>
    '$cardFavoritesKeyPrefix.$accountId';

Set<String> loadFavoriteCardIds(
  SharedPreferences preferences,
  String? accountId,
) {
  if (accountId == null || accountId.trim().isEmpty) {
    return <String>{};
  }
  final raw = preferences.getString(cardFavoritesKey(accountId));
  if (raw == null || raw.trim().isEmpty) return <String>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();
    }
  } catch (_) {
    // A malformed local value is recoverable by the next favorite change.
  }
  return <String>{};
}

Future<bool> saveFavoriteCardIds(
  SharedPreferences preferences,
  String? accountId,
  Iterable<String> cardIds,
) {
  if (accountId == null || accountId.trim().isEmpty) {
    return Future.value(true);
  }
  final values =
      cardIds
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  return preferences.setString(cardFavoritesKey(accountId), jsonEncode(values));
}

Future<void> enqueueSettingsSync({
  required SharedPreferences preferences,
  required AppDatabase database,
  required String accountId,
}) async {
  final now = DateTime.now();
  final random = Random.secure();
  await database.enqueueSync(
    SyncQueueItemModel(
      id: 'settings-review-$accountId-${now.microsecondsSinceEpoch}-${random.nextInt(1 << 32)}',
      accountId: accountId,
      objectType: 'SETTINGS',
      objectId: 'review',
      objectVersion: 1,
      operation: SyncOperation.upsert,
      payload: jsonEncode({
        'newCardsPerDay': _readInt(
          preferences,
          'review.new_cards_per_day.$accountId',
          20,
        ),
        'reviewsPerDay': _readInt(
          preferences,
          'review.reviews_per_day.$accountId',
          100,
        ),
        'autonomousLearning': _readBool(
          preferences,
          'review.autonomous_learning.$accountId',
          false,
        ),
        'selectedFolder': preferences.getString(
          'review.selected_folder.$accountId',
        ),
        'favorites': loadFavoriteCardIds(preferences, accountId).toList()
          ..sort(),
      }),
      status: SyncItemStatus.pending,
      attempts: 0,
      lastError: null,
      createdAt: now,
      updatedAt: now,
    ),
  );
}

int _readInt(SharedPreferences preferences, String key, int fallback) {
  final raw = preferences.get(key);
  if (raw is num) return raw.toInt();
  return int.tryParse('$raw') ?? fallback;
}

bool _readBool(SharedPreferences preferences, String key, bool fallback) {
  final raw = preferences.get(key);
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  final normalized = '$raw'.trim().toLowerCase();
  if (normalized == 'true' || normalized == '1') return true;
  if (normalized == 'false' || normalized == '0') return false;
  return fallback;
}
