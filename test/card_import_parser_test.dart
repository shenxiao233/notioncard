import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:kncard_app/core/models/card_model.dart';
import 'package:kncard_app/features/cards/card_import_parser.dart';

void main() {
  test('parses the browser export and preserves rich content', () {
    final file = File(
      r'C:\Users\yang\.agents-anywhere\attachments\sess_codex_92d2bc7e9a1fc6ab22d34092\file_8wpIMwubwJXGh3OY-1771881868.json',
    );
    final document = parseBrowserCardJson(file.readAsStringSync());

    expect(document.cards, hasLength(25));
    expect(document.issues, isEmpty);
    expect(
      document.cards.every((card) => card.type == CardType.single),
      isTrue,
    );
    expect(document.cards.every((card) => card.options.length == 4), isTrue);
    expect(document.cards.every((card) => card.answer.length == 1), isTrue);
    expect(document.cards.every((card) => card.source.isNotEmpty), isTrue);
    expect(document.cards.any((card) => card.tags.isNotEmpty), isTrue);

    final blank = document.cards.firstWhere(
      (card) => card.question.contains('___'),
    );
    expect(blank.question, contains('___'));
    expect(blank.question, isNot(contains('<u>')));

    final image = document.cards.firstWhere(
      (card) => card.question.contains('![]('),
    );
    expect(image.question, contains('https://'));
    expect(image.question, contains('![]('));
    expect(
      document.cards.any((card) => card.explanation.contains('![](')),
      isTrue,
    );
  });

  test('keeps the exact width of whitespace-only underline elements', () {
    final document = parseBrowserCardJson('''
{
  "data": [{
    "id": 1,
    "key": "blank-test",
    "content": "<p>A<u>&nbsp;&nbsp;&nbsp;&nbsp;</u>B</p>",
    "options": ["x", "y"],
    "correctAnswer": {"choice": "0", "type": 201},
    "solution": "",
    "source": "source",
    "keypoints": []
  }]
}
''');

    expect(document.issues, isEmpty);
    expect(document.cards.single.question, 'A____B');
  });

  test('imports judgment questions whose export omits the options', () {
    final document = parseBrowserCardJson('''
{
  "data": [{
    "id": 17445399,
    "key": "3_1_gkcgn",
    "content": "<p>这是一条需要判断的表述。（&nbsp; &nbsp; ）</p>",
    "options": [],
    "correctAnswer": {"choice": "1", "type": 201},
    "solution": "<p>故表述错误。</p>",
    "source": "判断题测试",
    "keypoints": []
  }]
}
''');

    expect(document.issues, isEmpty);
    expect(document.cards.single.type, CardType.trueFalse);
    expect(document.cards.single.options, {'A': '正确', 'B': '错误'});
    expect(document.cards.single.answer, ['B']);
  });

  test(
    'does not turn an arbitrary empty-options record into a judgment card',
    () {
      final document = parseBrowserCardJson('''
{
  "data": [{
    "content": "没有判断题标记",
    "options": [],
    "correctAnswer": {"choice": "1", "type": 201}
  }]
}
''');

      expect(document.cards, isEmpty);
      expect(document.issues, hasLength(1));
      expect(document.issues.single.message, contains('选项为空'));
    },
  );
}
