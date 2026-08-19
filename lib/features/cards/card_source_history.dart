import 'package:shared_preferences/shared_preferences.dart';

/// Converts runs of three or more ordinary spaces into one underscore.
/// Single and double spaces are kept as-is.
String replaceSpacesWithUnderscores(String value) => value.replaceAllMapped(
  RegExp(r' {3,}'),
  (match) => '_' * match.group(0)!.length,
);

/// Persists the last non-empty source used for each deck and account.
///
/// The deck name is used as the key because the card editor currently stores
/// the deck relationship by folder name. Keeping the account in the key
/// prevents one signed-in user from seeing another user's suggestions on the
/// same device.
class CardSourceHistory {
  const CardSourceHistory(this._preferences);

  static const _keyPrefix = 'card_source_history_v1';

  final SharedPreferences _preferences;

  String? read({required String accountId, required String folder}) {
    final key = _key(accountId, folder);
    if (key == null) return null;
    final value = _preferences.getString(key)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<bool> remember({
    required String accountId,
    required String folder,
    required String source,
  }) {
    final key = _key(accountId, folder);
    final value = source.trim();
    if (key == null || value.isEmpty) return Future.value(false);
    return _preferences.setString(key, value);
  }

  static String? _key(String accountId, String folder) {
    final account = accountId.trim();
    final deck = folder.trim();
    if (account.isEmpty || deck.isEmpty) return null;
    return '$_keyPrefix:${Uri.encodeComponent(account)}:${Uri.encodeComponent(deck)}';
  }
}
