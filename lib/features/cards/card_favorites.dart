import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_providers.dart';
import '../../core/database/app_database.dart';
import '../../core/sync/settings_sync.dart';

class CardFavoritesController extends StateNotifier<Set<String>> {
  CardFavoritesController(this._preferences, this._accountId, this._database)
    : super(Set.unmodifiable(loadFavoriteCardIds(_preferences, _accountId)));

  final SharedPreferences _preferences;
  final String? _accountId;
  final AppDatabase? _database;

  Future<void> toggle(String cardId) async {
    final normalized = cardId.trim();
    if (normalized.isEmpty) return;
    await setFavorite(normalized, !state.contains(normalized));
  }

  Future<void> setFavorite(String cardId, bool favorite) async {
    final normalized = cardId.trim();
    if (normalized.isEmpty) return;

    final previous = state;
    final next = {...state};
    if (favorite) {
      next.add(normalized);
    } else {
      next.remove(normalized);
    }
    state = Set.unmodifiable(next);

    final saved = await saveFavoriteCardIds(_preferences, _accountId, next);
    if (!saved) {
      state = previous;
      return;
    }

    final accountId = _accountId;
    final database = _database;
    if (accountId != null && database != null) {
      await enqueueSettingsSync(
        preferences: _preferences,
        database: database,
        accountId: accountId,
      );
    }
  }
}

final cardFavoritesProvider =
    StateNotifierProvider<CardFavoritesController, Set<String>>((ref) {
      ref.watch(remoteSettingsRevisionProvider);
      final accountId = ref.watch(currentAccountProvider)?.id;
      return CardFavoritesController(
        ref.watch(sharedPreferencesProvider),
        accountId,
        accountId == null ? null : ref.watch(appDatabaseProvider),
      );
    });
