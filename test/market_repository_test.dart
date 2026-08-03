import 'package:flutter_test/flutter_test.dart';
import 'package:kncard_app/features/market/market_repository.dart';

void main() {
  test('market search matches title, author, and tags', () async {
    final repository = MarketRepository();

    expect(
      (await repository.search(query: 'Flutter')).single.id,
      'deck-flutter',
    );
    expect((await repository.search(query: 'FSRS')).single.id, 'deck-fsrs');
    expect(await repository.search(query: 'not-found'), isEmpty);
  });

  test('market details can be loaded by id', () async {
    final deck = await MarketRepository().findById('deck-product');

    expect(deck, isNotNull);
    expect(deck!.cardCount, 65);
    expect(await MarketRepository().findById('missing'), isNull);
  });
}
