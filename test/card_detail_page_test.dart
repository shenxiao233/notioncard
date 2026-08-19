import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kncard_app/app/app_providers.dart';
import 'package:kncard_app/core/models/card_model.dart';
import 'package:kncard_app/features/cards/card_detail_page.dart';

void main() {
  testWidgets('question title favorite star toggles', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final card = CardModel(
      id: 'card-favorite-test',
      accountId: 'account-favorite-test',
      type: CardType.single,
      folder: '默认牌组',
      question: '测试题目',
      options: const {'A': '选项 A'},
      answer: const ['A'],
      content: '',
      noteContent: '这是题目的补充笔记。',
      explanation: '',
      tags: const [],
      dueAt: DateTime(2026, 8, 16),
      createdAt: DateTime(2026, 8, 16),
      updatedAt: DateTime(2026, 8, 16),
      reviews: 0,
      mastery: reviewingCardMastery,
      suspended: false,
      fsrs: FsrsSnapshot(
        state: FsrsState.newCard,
        dueAt: DateTime(2026, 8, 16),
        stability: 0,
        difficulty: 0,
        reps: 0,
        lapses: 0,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          cardsProvider.overrideWith((ref) async => [card]),
        ],
        child: MaterialApp(home: CardDetailPage(cardId: card.id)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('题目'), findsOneWidget);
    expect(find.text('这是题目的补充笔记。'), findsOneWidget);
    expect(find.byTooltip('收藏'), findsOneWidget);
    expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
    expect(find.byTooltip('分享题目'), findsOneWidget);

    await tester.tap(find.byTooltip('收藏'));
    await tester.pump();

    expect(find.byTooltip('取消收藏'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '编辑笔记'));
    await tester.pumpAndSettle();

    expect(find.text('编辑笔记'), findsNWidgets(2));
    expect(find.text('保存笔记'), findsOneWidget);
    expect(find.byTooltip('取消编辑'), findsOneWidget);

    await tester.tap(find.byTooltip('取消编辑'));
    await tester.pumpAndSettle();
    expect(find.text('保存笔记'), findsNothing);
  });

  testWidgets('note content and personal note stay separate', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final date = DateTime(2026, 8, 16);
    final card = CardModel(
      id: 'card-note-separation-test',
      accountId: 'account-note-separation-test',
      type: CardType.note,
      folder: '默认牌组',
      question: '速记题面',
      options: const {'A': '暂无内容', 'B': '暂无内容', 'C': '暂无内容', 'D': '暂无内容'},
      answer: const [],
      content: '词条正文',
      noteContent: '我的个人笔记',
      explanation: '',
      tags: const ['标签一'],
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          cardsProvider.overrideWith((ref) async => [card]),
        ],
        child: MaterialApp(home: CardDetailPage(cardId: card.id)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('内容'), findsOneWidget);
    expect(find.text('词条正文'), findsOneWidget);
    expect(find.text('笔记'), findsOneWidget);
    expect(find.text('我的个人笔记'), findsOneWidget);
    expect(find.text('暂无内容'), findsNothing);
    expect(find.text('默认牌组'), findsNothing);
    expect(find.text('来源：默认牌组'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑知识点'), findsOneWidget);
    expect(find.text('添加知识点'), findsOneWidget);
    expect(find.byType(InputChip), findsOneWidget);

    await tester.tap(find.byTooltip('关闭编辑'));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('标签一'));
    await tester.pumpAndSettle();
    expect(find.text('编辑标签'), findsOneWidget);
    expect(find.text('删除标签'), findsOneWidget);
  });
}
