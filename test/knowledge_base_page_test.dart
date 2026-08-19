import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kncard_app/app/app_providers.dart';
import 'package:kncard_app/core/models/collection_model.dart';
import 'package:kncard_app/core/models/document_model.dart';
import 'package:kncard_app/features/cards/cards_market_page.dart';

void main() {
  testWidgets('resource page uses the reference layout and preview limits', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 18);
    final collections = [
      _collection(
        id: 'category-study',
        name: 'folder-study',
        type: CollectionType.documentCategory,
        updatedAt: now.subtract(const Duration(days: 8)),
      ),
      _collection(
        id: 'category-frontend',
        name: 'folder-frontend',
        type: CollectionType.documentCategory,
        updatedAt: now.subtract(const Duration(days: 23)),
      ),
      _collection(
        id: 'category-legacy',
        name: 'folder-legacy',
        type: CollectionType.documentCategory,
        updatedAt: now.subtract(const Duration(days: 30)),
      ),
      _collection(
        id: 'deck-powder',
        name: '粉笔错题',
        type: CollectionType.deck,
        updatedAt: now,
      ),
      _collection(
        id: 'deck-idioms',
        name: '高频成语实词1000词',
        type: CollectionType.deck,
        updatedAt: now.subtract(const Duration(days: 2)),
      ),
      _collection(
        id: 'deck-legacy',
        name: '历史牌组',
        type: CollectionType.deck,
        updatedAt: now.subtract(const Duration(days: 30)),
      ),
    ];
    final documents = List.generate(
      7,
      (index) => DocumentModel(
        id: 'document-$index',
        accountId: 'account-test',
        folder: index < 5 ? 'folder-study' : 'folder-frontend',
        title: '文章 $index',
        body: '',
        updatedAt: now.subtract(Duration(days: index)),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentsProvider.overrideWith((ref) async => documents),
          cardsProvider.overrideWith((ref) async => const []),
          collectionsProvider.overrideWith((ref) async => collections),
        ],
        child: const MaterialApp(home: KnowledgeBasePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('搜索文件夹 / 卡牌 / 文档'), findsOneWidget);
    expect(find.text('我的文档'), findsOneWidget);
    expect(find.text('我的卡牌'), findsOneWidget);
    expect(find.text('查看全部'), findsNWidgets(2));
    expect(find.text('folder-study'), findsOneWidget);
    expect(find.text('folder-frontend'), findsOneWidget);
    expect(find.text('folder-legacy'), findsNothing);
    expect(find.text('历史牌组'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('资源市场'), findsOneWidget);
  });
}

CollectionModel _collection({
  required String id,
  required String name,
  required CollectionType type,
  required DateTime updatedAt,
}) => CollectionModel(
  id: id,
  accountId: 'account-test',
  type: type,
  name: name,
  icon: '',
  color: '',
  archived: false,
  createdAt: updatedAt,
  updatedAt: updatedAt,
);
