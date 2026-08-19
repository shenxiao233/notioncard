import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kncard_app/app/app_providers.dart';
import 'package:kncard_app/features/editor/editor_page.dart';

void main() {
  testWidgets('editor entry shows choices and a working back affordance', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: EditorPage()));

    expect(find.text('选择编辑类型'), findsOneWidget);
    expect(find.text('选择合适的内容类型，开始创建'), findsOneWidget);
    expect(find.text('卡片'), findsOneWidget);
    expect(find.text('文档'), findsOneWidget);
    expect(find.text('适合知识点、单词、公式、问答等内容；用于快速学习与复习。'), findsOneWidget);
    expect(find.text('适合笔记、教材、资料、长篇内容；用于整理完整知识体系。'), findsOneWidget);
    expect(find.text('>'), findsNWidgets(2));
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('opens the editor as a dismissible upward sheet', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showEditorSheet(context),
              child: const Text('打开编辑'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();

    expect(find.text('选择编辑类型'), findsOneWidget);
    expect(find.byTooltip('关闭编辑'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭编辑'));
    await tester.pumpAndSettle();

    expect(find.text('选择编辑类型'), findsNothing);
  });

  testWidgets('document flow chooses a knowledge base before editing', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentsProvider.overrideWith((ref) async => const []),
          cardsProvider.overrideWith((ref) async => const []),
          collectionsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showEditorSheet(context),
                child: const Text('打开编辑'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文档'));
    await tester.pumpAndSettle();

    expect(find.text('选择知识库'), findsOneWidget);
    expect(find.text('默认知识库'), findsOneWidget);

    await tester.tap(find.text('默认知识库'));
    await tester.pumpAndSettle();

    expect(find.text('无标题文档'), findsOneWidget);
    expect(find.text('请输入正文'), findsOneWidget);
    expect(find.text('默认知识库'), findsOneWidget);
    expect(find.byTooltip('保存文档'), findsOneWidget);
  });
}
