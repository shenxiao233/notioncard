import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
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

  test('parses a valid market package and creates stable card ids', () async {
    final package = await MarketRepository().parseDeckPackage(
      MarketDeckDownload(
        bytes: _zip({
          'manifest.json': jsonEncode({
            'version': 7,
            'title': '测试牌组',
            'cardCount': 2,
            'files': ['manifest.json', 'cards.json'],
          }),
          'cards.json': jsonEncode([
            {
              'question': '第一张卡',
              'answer': '答案一',
              'content': '补充说明',
              'tags': ['基础'],
            },
            {
              'id': 'source-2',
              'order': 2,
              'type': 'single-choice',
              'front': '第二张卡',
              'back': ['答案二'],
              'options': ['选项 A', '选项 B'],
            },
          ]),
        }),
        version: 7,
      ),
      deckId: 'deck-demo',
      fallbackTitle: '备用名称',
      accountId: 'account-a',
    );

    expect(package.title, '测试牌组');
    expect(package.version, 7);
    expect(package.cards, hasLength(2));
    expect(package.cards[0].id, 'market-deck-demo-1');
    expect(package.cards[0].accountId, 'account-a');
    expect(package.cards[0].folder, '测试牌组');
    expect(package.cards[0].answer, ['答案一']);
    expect(package.cards[0].content, '补充说明');
    expect(package.cards[0].noteContent, isEmpty);
    expect(package.cards[0].tags, ['基础']);
    expect(package.cards[0].fsrs.state.name, 'newCard');
    expect(package.cards[0].sortOrder, 1);
    expect(package.cards[1].id, 'market-deck-demo-source-2');
    expect(package.cards[1].sortOrder, 2);
    expect(package.cards[1].type.name, 'single');
    expect(package.cards[1].options, {'A': '选项 A', 'B': '选项 B'});
  });

  test(
    'rejects packages missing required files or with a version mismatch',
    () async {
      final repository = MarketRepository();

      await expectLater(
        repository.parseDeckPackage(
          MarketDeckDownload(
            bytes: _zip({'cards.json': jsonEncode([])}),
            version: 1,
          ),
          deckId: 'deck-missing-manifest',
          fallbackTitle: '测试',
        ),
        throwsA(isA<MarketPackageException>()),
      );
      await expectLater(
        repository.parseDeckPackage(
          MarketDeckDownload(
            bytes: _zip({
              'manifest.json': jsonEncode({'version': 2}),
              'cards.json': jsonEncode([
                {'question': '题目'},
              ]),
            }),
            version: 1,
          ),
          deckId: 'deck-version-mismatch',
          fallbackTitle: '测试',
        ),
        throwsA(isA<MarketPackageException>()),
      );
    },
  );

  test('rejects archive paths that escape the package root', () async {
    final repository = MarketRepository();

    await expectLater(
      repository.parseDeckPackage(
        MarketDeckDownload(
          bytes: _zip({
            '../manifest.json': jsonEncode({'version': 1}),
            'cards.json': jsonEncode([
              {'question': '题目'},
            ]),
          }),
          version: 1,
        ),
        deckId: 'deck-unsafe-path',
        fallbackTitle: '测试',
      ),
      throwsA(isA<MarketPackageException>()),
    );
  });
}

Uint8List _zip(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final content = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, content.length, content));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}
