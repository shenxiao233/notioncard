import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_providers.dart';
import '../../core/models/card_model.dart';
import '../../core/models/collection_model.dart';
import '../../core/models/document_model.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_visuals.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/resource_action_dialogs.dart';
import '../../core/widgets/swipe_action_tile.dart';

enum KnowledgeBaseSection { documents, cards }

class KnowledgeBasePage extends ConsumerStatefulWidget {
  const KnowledgeBasePage({
    this.initialSection = KnowledgeBaseSection.documents,
    super.key,
  });

  final KnowledgeBaseSection initialSection;

  @override
  ConsumerState<KnowledgeBasePage> createState() => _KnowledgeBasePageState();
}

class _KnowledgeBasePageState extends ConsumerState<KnowledgeBasePage> {
  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(documentsProvider);
    final cards = ref.watch(cardsProvider);
    final collections = ref.watch(collectionsProvider);

    return Scaffold(
      backgroundColor: AppVisualColors.background,
      body: SafeArea(
        bottom: false,
        child: documents.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppVisualColors.green),
          ),
          error: (error, _) => _KnowledgeBaseError(onRetry: _refresh),
          data: (documentValues) => cards.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppVisualColors.green),
            ),
            error: (error, _) => _KnowledgeBaseError(onRetry: _refresh),
            data: (cardValues) => collections.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppVisualColors.green),
              ),
              error: (error, _) => _KnowledgeBaseError(onRetry: _refresh),
              data: (collectionValues) => RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    AppLayoutMetrics.bottomNavigationContentPadding + 36,
                  ),
                  children: [
                    _ResourceHeader(
                      onSearch: () => _openSearch(
                        context,
                        documents: documentValues,
                        cards: cardValues,
                        collections: collectionValues,
                      ),
                    ),
                    _DocumentsSection(
                      documents: documentValues,
                      categories: collectionValues
                          .where(
                            (collection) =>
                                collection.type ==
                                    CollectionType.documentCategory &&
                                !collection.archived,
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 28),
                    _CardsSection(
                      decks: _SectionContent._groupCards(
                        cardValues,
                        collectionValues,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const _MarketPromoCard(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openSearch(
    BuildContext context, {
    required List<DocumentModel> documents,
    required List<CardModel> cards,
    required List<CollectionModel> collections,
  }) {
    showSearch<void>(
      context: context,
      delegate: _ResourceSearchDelegate(
        documents: documents,
        cards: cards,
        collections: collections,
      ),
    );
  }

  Future<void> _refresh() async {
    await ref
        .read(syncControllerProvider.notifier)
        .sync(reason: 'knowledge-base-refresh');
    ref.invalidate(documentsProvider);
    ref.invalidate(cardsProvider);
    ref.invalidate(collectionsProvider);
    ref.invalidate(marketSearchProvider(''));
    await Future.wait([
      ref.read(documentsProvider.future),
      ref.read(cardsProvider.future),
      ref.read(collectionsProvider.future),
    ]);
  }
}

class _SectionContent extends StatelessWidget {
  const _SectionContent({
    required this.section,
    required this.documents,
    required this.cards,
    required this.collections,
  });

  final KnowledgeBaseSection section;
  final List<DocumentModel> documents;
  final List<CardModel> cards;
  final List<CollectionModel> collections;

  @override
  Widget build(BuildContext context) {
    final decks = _groupCards(cards, collections);
    return switch (section) {
      KnowledgeBaseSection.documents => _DocumentsSection(
        documents: documents,
        categories: collections
            .where(
              (collection) =>
                  collection.type == CollectionType.documentCategory &&
                  !collection.archived,
            )
            .toList(),
      ),
      KnowledgeBaseSection.cards => _CardsSection(decks: decks),
    };
  }

  static List<_DeckSummary> _groupCards(
    List<CardModel> cards,
    List<CollectionModel> collections,
  ) {
    final groups = <String, List<CardModel>>{};
    for (final card in cards) {
      final folder = card.folder.trim();
      groups.putIfAbsent(folder, () => []).add(card);
    }
    for (final collection in collections.where(
      (value) => value.type == CollectionType.deck && !value.archived,
    )) {
      groups.putIfAbsent(collection.name.trim(), () => []);
    }
    final summaries =
        groups.entries
            .map(
              (entry) => _DeckSummary(
                folder: entry.key,
                cards: entry.value,
                collection: _collectionForFolder(collections, entry.key),
              ),
            )
            .toList()
          ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return summaries;
  }

  static CollectionModel? _collectionForFolder(
    List<CollectionModel> collections,
    String folder,
  ) {
    for (final collection in collections) {
      if (collection.type == CollectionType.deck &&
          collection.name.trim() == folder) {
        return collection;
      }
    }
    return null;
  }
}

class _DocumentsSection extends ConsumerWidget {
  const _DocumentsSection({required this.documents, required this.categories});

  final List<DocumentModel> documents;
  final List<CollectionModel> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoryEntries = [...categories]
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    final visibleEntries = categoryEntries.take(2).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResourceSectionHeader(
          title: '我的文档',
          subtitle: '${categories.length} 个分类 · ${documents.length} 篇文章',
          onViewAll: () => context.push('/library'),
        ),
        const SizedBox(height: 12),
        if (visibleEntries.isEmpty)
          const _ShelfEmptyState(
            title: '还没有文档',
            message: '创建一个文档类别，开始整理你的学习资料。',
          )
        else
          _ResourceList(
            entries: [
              for (final category in visibleEntries)
                _ResourceListEntry(
                  title: category.name,
                  subtitle:
                      '${documents.where((document) => document.folder == category.name).length} 篇文章',
                  updatedAt: category.updatedAt,
                  onTap: () => context.push(
                    Uri(
                      path: '/library',
                      queryParameters: {'folder': category.name},
                    ).toString(),
                  ),
                  onRename: () => _renameCategory(context, ref, category),
                  onArchive: () => _archiveCategory(context, ref, category),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _renameCategory(
    BuildContext context,
    WidgetRef ref,
    CollectionModel category,
  ) async {
    final name = await showRenameResourceDialog(
      context,
      title: '重命名文档类别',
      initialValue: category.name,
      hintText: '输入类别名称',
    );
    if (name == null || !context.mounted) return;
    try {
      await ref
          .read(contentRepositoryProvider)
          .renameCollection(collection: category, name: name);
      ref.invalidate(collectionsProvider);
      ref.invalidate(documentsProvider);
      ref.invalidate(pendingSyncProvider);
      ref
          .read(syncControllerProvider.notifier)
          .scheduleSync(reason: 'document-category-rename');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('文档类别已重命名，等待同步。')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('重命名失败：$error')));
      }
    }
  }

  Future<void> _archiveCategory(
    BuildContext context,
    WidgetRef ref,
    CollectionModel category,
  ) async {
    final confirmed = await showDeleteResourceDialog(
      context,
      title: '归档这个文档类别？',
      message: '文档不会被删除，归档后仍可通过同步数据恢复。',
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(contentRepositoryProvider).archiveCollection(category);
      ref.invalidate(collectionsProvider);
      ref.invalidate(pendingSyncProvider);
      ref
          .read(syncControllerProvider.notifier)
          .scheduleSync(reason: 'document-category-archive');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('文档类别已归档。')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('归档失败：$error')));
      }
    }
  }
}

class _CardsSection extends ConsumerWidget {
  const _CardsSection({required this.decks});

  final List<_DeckSummary> decks;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _ResourceSectionHeader(
        title: '我的卡牌',
        subtitle: '${_cardCount(decks)} 张卡牌 · ${decks.length} 个牌组',
        onViewAll: () => context.push('/cards'),
      ),
      const SizedBox(height: 12),
      if (decks.isEmpty)
        const _ShelfEmptyState(title: '还没有牌组', message: '创建一个牌组，开始整理你的记忆卡片。')
      else
        _ResourceList(
          entries: [
            for (final deck in decks.take(2))
              _ResourceListEntry(
                title: deck.name,
                subtitle: '${deck.cards.length} 张卡牌',
                updatedAt: deck.updatedAt,
                onTap: () =>
                    context.push('/cards/deck', extra: deck.routeFolder),
                onRename: () => _renameDeck(context, ref, deck),
                onArchive: () => _deleteDeck(context, ref, deck),
              ),
          ],
        ),
    ],
  );

  Future<void> _renameDeck(
    BuildContext context,
    WidgetRef ref,
    _DeckSummary deck,
  ) async {
    final name = await showRenameResourceDialog(
      context,
      title: '重命名牌组',
      initialValue: deck.name,
      hintText: '输入牌组名称',
    );
    if (name == null || !context.mounted) return;
    try {
      final count = deck.cards.length;
      if (deck.collection == null) {
        await ref
            .read(contentRepositoryProvider)
            .renameDeck(
              accountId: deck.accountId,
              folder: deck.routeFolder,
              name: name,
            );
      } else {
        await ref
            .read(contentRepositoryProvider)
            .renameCollection(collection: deck.collection!, name: name);
      }
      ref.invalidate(cardsProvider);
      ref.invalidate(collectionsProvider);
      ref.invalidate(pendingSyncProvider);
      ref
          .read(syncControllerProvider.notifier)
          .scheduleSync(reason: 'deck-rename');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('牌组已重命名，已更新 $count 张卡牌，等待同步。')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('重命名失败：$error')));
      }
    }
  }

  Future<void> _deleteDeck(
    BuildContext context,
    WidgetRef ref,
    _DeckSummary deck,
  ) async {
    final confirmed = await showDeleteResourceDialog(
      context,
      title: '归档这个牌组？',
      message: '牌组中的卡牌不会被删除，归档后仍可通过同步数据恢复。',
    );
    if (!confirmed || !context.mounted) return;
    try {
      if (deck.collection != null) {
        await ref
            .read(contentRepositoryProvider)
            .archiveCollection(deck.collection!);
      }
      ref.invalidate(cardsProvider);
      ref.invalidate(collectionsProvider);
      ref.invalidate(pendingSyncProvider);
      ref
          .read(syncControllerProvider.notifier)
          .scheduleSync(reason: 'deck-archive');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('牌组已归档，卡牌内容保留。')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  static int _cardCount(List<_DeckSummary> decks) {
    return decks.fold(0, (total, deck) => total + deck.cards.length);
  }
}

class _ResourceHeader extends StatelessWidget {
  const _ResourceHeader({required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 2, 0, 28),
    child: Semantics(
      button: true,
      label: '搜索资源',
      child: Material(
        color: const Color(0xfff7f7f6),
        borderRadius: BorderRadius.circular(25),
        child: InkWell(
          onTap: onSearch,
          borderRadius: BorderRadius.circular(25),
          child: const SizedBox(
            height: 50,
            child: Row(
              children: [
                SizedBox(width: 17),
                _SearchMark(color: Color(0xff7a7f7c)),
                SizedBox(width: 13),
                Text(
                  '搜索文件夹 / 卡牌 / 文档',
                  style: TextStyle(
                    color: Color(0xff7c817e),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _SearchMark extends StatelessWidget {
  const _SearchMark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(24, 24), painter: _SearchMarkPainter(color));
}

class _SearchMarkPainter extends CustomPainter {
  const _SearchMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(const Offset(9, 9), 6.5, paint);
    canvas.drawLine(const Offset(14, 14), const Offset(20, 20), paint);
  }

  @override
  bool shouldRepaint(covariant _SearchMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ResourceSectionHeader extends StatelessWidget {
  const _ResourceSectionHeader({
    required this.title,
    required this.subtitle,
    required this.onViewAll,
  });

  final String title;
  final String subtitle;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppVisualColors.ink,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppVisualColors.muted,
                fontSize: 13,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
      TextButton(
        onPressed: onViewAll,
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xff347b46),
          padding: const EdgeInsets.only(left: 4, right: 0),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('查看全部'),
            SizedBox(width: 3),
            Icon(Icons.chevron_right_rounded, size: 19),
          ],
        ),
      ),
    ],
  );
}

class _ShelfEmptyState extends StatelessWidget {
  const _ShelfEmptyState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: appCardShadow,
    ),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppVisualColors.softGreen,
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Text(
            '+',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppVisualColors.green,
              fontSize: 27,
              fontWeight: FontWeight.w300,
              height: 1.55,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppVisualColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppVisualColors.muted,
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
        const Text(
          '+',
          style: TextStyle(
            color: AppVisualColors.muted,
            fontSize: 22,
            fontWeight: FontWeight.w300,
          ),
        ),
      ],
    ),
  );
}

class _ResourceList extends StatelessWidget {
  const _ResourceList({required this.entries});

  final List<_ResourceListEntry> entries;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0d000000),
          blurRadius: 18,
          offset: Offset(0, 7),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Column(
        children: [
          for (var index = 0; index < entries.length; index++) ...[
            _ResourceRow(entry: entries[index]),
            if (index < entries.length - 1)
              const Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: Color(0xffeeeae3),
              ),
          ],
        ],
      ),
    ),
  );
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({required this.entry});

  final _ResourceListEntry entry;

  @override
  Widget build(BuildContext context) => SwipeActionTile(
    onTap: entry.onTap,
    onRename: entry.onRename,
    onDelete: entry.onArchive,
    borderRadius: BorderRadius.zero,
    boxShadow: const [],
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppVisualColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppVisualColors.muted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            DateFormat('MM-dd').format(entry.updatedAt.toLocal()),
            style: const TextStyle(color: AppVisualColors.muted, fontSize: 12),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.more_horiz_rounded,
            color: AppVisualColors.ink,
            size: 21,
          ),
        ],
      ),
    ),
  );
}

class _ResourceListEntry {
  const _ResourceListEntry({
    required this.title,
    required this.subtitle,
    required this.updatedAt,
    required this.onTap,
    required this.onRename,
    required this.onArchive,
  });

  final String title;
  final String subtitle;
  final DateTime updatedAt;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onArchive;
}

class _MarketPromoCard extends StatelessWidget {
  const _MarketPromoCard();

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(26),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => context.push('/market'),
      child: Container(
        height: 136,
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xfffff8ed), Color(0xffffe5b8)],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.68),
            width: 1.2,
          ),
          boxShadow: appCardShadow,
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '资源市场',
                    style: TextStyle(
                      color: Color(0xff8d6338),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    '探索更多学习资源',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xff3f2a14),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '发现适合你的文档与牌组',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Color(0xff8a6946), fontSize: 11),
                  ),
                  const Spacer(),
                  const Text(
                    '立即探索  →',
                    style: TextStyle(
                      color: Color(0xff9d5d0e),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 2,
              top: -2,
              child: const SizedBox(
                width: 116,
                height: 116,
                child: _MarketArt(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MarketArt extends StatelessWidget {
  const _MarketArt();

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _MarketArtPainter(), size: Size(116, 116));
}

class _MarketArtPainter extends CustomPainter {
  const _MarketArtPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xffb97838).withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final paper = Paint()
      ..color = const Color(0xfffffbf4).withValues(alpha: 0.82)
      ..style = PaintingStyle.fill;
    final shadow = Paint()
      ..color = const Color(0xffb16d31).withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(size.width * 0.58, size.height * 0.52),
      52,
      Paint()..color = Colors.white.withValues(alpha: 0.34),
    );

    canvas.save();
    canvas.translate(4, 12);
    canvas.rotate(-0.1);
    final backPage = RRect.fromRectAndRadius(
      const Rect.fromLTWH(21, 21, 50, 65),
      const Radius.circular(9),
    );
    canvas.drawRRect(backPage, shadow);
    canvas.drawRRect(backPage, paper);
    canvas.drawRRect(backPage, stroke);
    canvas.restore();

    canvas.save();
    canvas.translate(16, 5);
    canvas.rotate(0.08);
    final frontPage = RRect.fromRectAndRadius(
      const Rect.fromLTWH(20, 20, 50, 66),
      const Radius.circular(9),
    );
    canvas.drawRRect(frontPage, paper);
    canvas.drawRRect(frontPage, stroke);
    canvas.drawLine(const Offset(29, 39), const Offset(62, 39), stroke);
    canvas.drawLine(const Offset(29, 50), const Offset(57, 50), stroke);
    canvas.drawLine(const Offset(29, 61), const Offset(64, 61), stroke);
    canvas.restore();

    final sparkle = Path()
      ..moveTo(98, 14)
      ..lineTo(101, 21)
      ..lineTo(108, 24)
      ..lineTo(101, 27)
      ..lineTo(98, 34)
      ..lineTo(95, 27)
      ..lineTo(88, 24)
      ..lineTo(95, 21)
      ..close();
    canvas.drawPath(sparkle, stroke);
  }

  @override
  bool shouldRepaint(covariant _MarketArtPainter oldDelegate) => false;
}

class _ResourceSearchDelegate extends SearchDelegate<void> {
  _ResourceSearchDelegate({
    required this.documents,
    required this.cards,
    required this.collections,
  }) : super(searchFieldLabel: '搜索文件夹、牌组或内容');

  final List<DocumentModel> documents;
  final List<CardModel> cards;
  final List<CollectionModel> collections;

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: '清除搜索',
        onPressed: () => query = '',
        icon: const Icon(Icons.clear_rounded),
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    tooltip: '返回',
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back_rounded),
  );

  @override
  Widget buildResults(BuildContext context) => _buildResultList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildResultList(context);

  Widget _buildResultList(BuildContext context) {
    final keyword = query.trim().toLowerCase();
    final categories = collections
        .where(
          (collection) =>
              collection.type == CollectionType.documentCategory &&
              !collection.archived &&
              _matches(collection.name, keyword),
        )
        .toList();
    final decks = _SectionContent._groupCards(
      cards,
      collections,
    ).where((deck) => _matches(deck.name, keyword)).toList();
    final matchingDocuments = documents
        .where(
          (document) =>
              _matches(document.title, keyword) ||
              _matches(document.folder, keyword),
        )
        .take(8)
        .toList();
    final matchingCards = cards
        .where(
          (card) =>
              _matches(card.question, keyword) ||
              _matches(card.folder, keyword),
        )
        .take(8)
        .toList();

    if (categories.isEmpty &&
        decks.isEmpty &&
        matchingDocuments.isEmpty &&
        matchingCards.isEmpty) {
      return const Center(
        child: EmptyState(
          title: '没有找到资源',
          message: '试试搜索文件夹、牌组名称或文章内容。',
          icon: Icons.search_off_rounded,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (categories.isNotEmpty) ...[
          const _SearchGroupTitle(title: '我的文档'),
          for (final category in categories)
            _SearchResultTile(
              label: '文档',
              color: _collectionColor(category.color, AppVisualColors.green),
              title: category.name,
              subtitle: '打开这个文档分类',
              onTap: () {
                final router = GoRouter.of(context);
                close(context, null);
                router.push(
                  Uri(
                    path: '/library',
                    queryParameters: {'folder': category.name},
                  ).toString(),
                );
              },
            ),
        ],
        if (decks.isNotEmpty) ...[
          const _SearchGroupTitle(title: '牌组'),
          for (final deck in decks)
            _SearchResultTile(
              label: '牌组',
              color: _collectionColor(
                deck.collection?.color ?? '',
                const Color(0xff4778e8),
              ),
              title: deck.name,
              subtitle: '${deck.cards.length} 张卡牌',
              onTap: () {
                final router = GoRouter.of(context);
                close(context, null);
                router.push('/cards/deck', extra: deck.routeFolder);
              },
            ),
        ],
        if (matchingDocuments.isNotEmpty) ...[
          const _SearchGroupTitle(title: '文章'),
          for (final document in matchingDocuments)
            _SearchResultTile(
              label: '文',
              color: AppVisualColors.green,
              title: document.title,
              subtitle: document.folder.trim().isEmpty
                  ? '未分类文档'
                  : document.folder,
              onTap: () {
                final router = GoRouter.of(context);
                close(context, null);
                router.push('/library/document/${document.id}');
              },
            ),
        ],
        if (matchingCards.isNotEmpty) ...[
          const _SearchGroupTitle(title: '卡牌'),
          for (final card in matchingCards)
            _SearchResultTile(
              label: '卡',
              color: const Color(0xff4778e8),
              title: card.question,
              subtitle: card.folder.trim().isEmpty ? '未分类牌组' : card.folder,
              onTap: () {
                final router = GoRouter.of(context);
                close(context, null);
                router.push('/cards/${card.id}');
              },
            ),
        ],
      ],
    );
  }

  static bool _matches(String value, String keyword) {
    if (keyword.isEmpty) return true;
    return value.toLowerCase().contains(keyword);
  }
}

class _SearchGroupTitle extends StatelessWidget {
  const _SearchGroupTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
    child: Text(
      title,
      style: const TextStyle(
        color: AppVisualColors.ink,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.label,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String label;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      boxShadow: appCardShadow,
    ),
    child: ListTile(
      onTap: onTap,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: label.length > 2 ? 9 : 15,
              fontWeight: FontWeight.w800,
              letterSpacing: label.length > 2 ? 0.4 : 0,
            ),
          ),
        ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppVisualColors.ink,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppVisualColors.muted, fontSize: 12),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppVisualColors.muted,
      ),
    ),
  );
}

Color _collectionColor(String value, Color fallback) {
  switch (value.trim().toLowerCase()) {
    case 'green':
      return AppVisualColors.green;
    case 'blue':
      return const Color(0xff4778e8);
    case 'orange':
      return const Color(0xffe9950b);
    case 'purple':
      return const Color(0xff8d61d8);
  }

  var hex = value.trim().toLowerCase();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length != 6 && hex.length != 8) return fallback;
  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) return fallback;
  return Color(hex.length == 6 ? 0xff000000 | parsed : parsed);
}

class _DeckSummary {
  const _DeckSummary({
    required this.folder,
    required this.cards,
    this.collection,
  });

  final String folder;
  final List<CardModel> cards;
  final CollectionModel? collection;

  String get name =>
      collection?.name ?? (folder.trim().isEmpty ? '未分类' : folder);

  String get routeFolder => name;

  String get accountId =>
      cards.isNotEmpty ? cards.first.accountId : collection?.accountId ?? '';

  DateTime get updatedAt {
    if (cards.isEmpty) return collection?.updatedAt ?? DateTime.now();
    var latest = cards.first.updatedAt;
    for (final card in cards.skip(1)) {
      if (card.updatedAt.isAfter(latest)) latest = card.updatedAt;
    }
    return latest;
  }

  int get dueCount => cards.where((card) => card.isDue).length;
}

class _KnowledgeBaseError extends StatelessWidget {
  const _KnowledgeBaseError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: EmptyState(
      title: '资源加载失败',
      message: '请检查网络或本地缓存，然后重试。',
      icon: Icons.cloud_off_outlined,
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('重试'),
      ),
    ),
  );
}
