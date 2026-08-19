import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kncard_app/core/models/card_model.dart';
import 'package:kncard_app/features/cards/card_share_page.dart';

void main() {
  testWidgets(
    'share preview omits private notes and keeps answer controls visible',
    (tester) async {
      final card = _buildNoteCard();

      await tester.pumpWidget(MaterialApp(home: CardSharePage(card: card)));
      await tester.pumpAndSettle();

      expect(find.text('题目'), findsOneWidget);
      expect(find.text('Question'), findsOneWidget);
      expect(find.text('内容'), findsOneWidget);
      expect(find.text('Content'), findsOneWidget);
      expect(find.text('Private note'), findsNothing);
      expect(find.text('显示答案'), findsOneWidget);
      expect(find.text('显示解析'), findsOneWidget);
      expect(find.text('知识点'), findsNothing);
      expect(find.textContaining('来源：'), findsNothing);
      expect(find.byType(Switch), findsNWidgets(2));
    },
  );

  testWidgets('share preview can hide answer and explanation', (tester) async {
    final card = _buildChoiceCard();

    await tester.pumpWidget(MaterialApp(home: CardSharePage(card: card)));
    await tester.pumpAndSettle();

    expect(find.text('答案：A'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch).at(0)).value, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isTrue);

    await tester.tap(find.byType(Switch).at(0));
    await tester.pumpAndSettle();

    expect(find.text('答案：A'), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch).at(0)).value, isFalse);

    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isFalse);
  });
}

CardModel _buildNoteCard() {
  final date = DateTime(2026, 8, 19);
  return CardModel(
    id: 'share-preview-test',
    accountId: 'share-preview-account',
    type: CardType.note,
    folder: 'Deck',
    source: '',
    question: 'Question',
    options: const {},
    answer: const [],
    content: 'Content',
    noteContent: 'Private note',
    explanation: '',
    tags: const [],
    dueAt: date,
    createdAt: date,
    updatedAt: date,
    reviews: 0,
    mastery: reviewingCardMastery,
    suspended: false,
    fsrs: FsrsSnapshot(
      state: FsrsState.newCard,
      dueAt: date,
      stability: 0,
      difficulty: 0,
      reps: 0,
      lapses: 0,
    ),
  );
}

CardModel _buildChoiceCard() {
  final date = DateTime(2026, 8, 19);
  return CardModel(
    id: 'share-choice-test',
    accountId: 'share-choice-account',
    type: CardType.single,
    folder: 'Deck',
    source: '',
    question: 'Question',
    options: const {'A': 'Option A', 'B': 'Option B'},
    answer: const ['A'],
    content: '',
    noteContent: 'Private note',
    explanation: '解析',
    tags: const [],
    dueAt: date,
    createdAt: date,
    updatedAt: date,
    reviews: 0,
    mastery: reviewingCardMastery,
    suspended: false,
    fsrs: FsrsSnapshot(
      state: FsrsState.newCard,
      dueAt: date,
      stability: 0,
      difficulty: 0,
      reps: 0,
      lapses: 0,
    ),
  );
}
