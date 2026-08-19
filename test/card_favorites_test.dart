import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kncard_app/core/database/app_database.dart';
import 'package:kncard_app/core/sync/settings_sync.dart';
import 'package:kncard_app/features/cards/card_favorites.dart';

void main() {
  test('card favorites persist per account', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    final first = CardFavoritesController(preferences, 'account-a', null);
    await first.toggle('card-1');

    expect(first.state, contains('card-1'));
    expect(loadFavoriteCardIds(preferences, 'account-a'), contains('card-1'));
    expect(loadFavoriteCardIds(preferences, 'account-b'), isEmpty);

    final restored = CardFavoritesController(preferences, 'account-a', null);
    expect(restored.state, contains('card-1'));

    await restored.toggle('card-1');
    expect(restored.state, isNot(contains('card-1')));
    expect(loadFavoriteCardIds(preferences, 'account-a'), isEmpty);

    first.dispose();
    restored.dispose();
  });

  test('card favorite changes enqueue a settings snapshot', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = CardFavoritesController(
      preferences,
      'account-a',
      database,
    );

    await controller.toggle('card-1');

    final pending = await database.loadPendingSync('account-a');
    expect(pending, hasLength(1));
    expect(pending.single.objectType, 'SETTINGS');
    expect(pending.single.objectId, 'review');
    expect(pending.single.payload, contains('"favorites":["card-1"]'));

    controller.dispose();
  });
}
