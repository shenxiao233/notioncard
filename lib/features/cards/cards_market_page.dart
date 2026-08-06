import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_providers.dart';
import '../../core/models/card_model.dart';
import '../../core/models/document_model.dart';
import '../../core/widgets/app_visuals.dart';
import '../../core/widgets/empty_state.dart';

enum KnowledgeBaseSection { recent, documents, cards }

class KnowledgeBasePage extends ConsumerStatefulWidget {
  const KnowledgeBasePage({
    this.initialSection = KnowledgeBaseSection.recent,
    super.key,
  });

  final KnowledgeBaseSection initialSection;

  @override
  ConsumerState<KnowledgeBasePage> createState() => _KnowledgeBasePageState();
}

class _KnowledgeBasePageState extends ConsumerState<KnowledgeBasePage> {
  late KnowledgeBaseSection _section = widget.initialSection;

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(documentsProvider);
    final cards = ref.watch(cardsProvider);
    final marketDecks = ref.watch(marketSearchProvider('')).valueOrNull;

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
            data: (cardValues) => RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
                children: [
                  _KnowledgeBaseHeader(
                    onSearch: () => _showSearch(documentValues, cardValues),
                  ),
                  const SizedBox(height: 18),
                  _ShortcutRow(
                    documentCount: documentValues.length,
                    cardCount: cardValues.length,
                    marketCount: marketDecks?.length,
                    onDocuments: () => _select(KnowledgeBaseSection.documents),
                    onCards: () => _select(KnowledgeBaseSection.cards),
                    onMarket: () => context.push('/market'),
                  ),
                  const SizedBox(height: 24),
                  _SectionSwitcher(selected: _section, onChanged: _select),
                  const SizedBox(height: 18),
                  _SectionContent(
                    section: _section,
                    documents: documentValues,
                    cards: cardValues,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _select(KnowledgeBaseSection section) {
    if (_section == section) return;
    setState(() => _section = section);
  }

  Future<void> _refresh() async {
    await ref
        .read(syncControllerProvider.notifier)
        .sync(reason: 'knowledge-base-refresh');
    ref.invalidate(documentsProvider);
    ref.invalidate(cardsProvider);
    ref.invalidate(marketSearchProvider(''));
    await Future.wait([
      ref.read(documentsProvider.future),
      ref.read(cardsProvider.future),
    ]);
  }

  Future<void> _showSearch(
    List<DocumentModel> documents,
    List<CardModel> cards,
  ) async {
    final result = await showSearch<_KnowledgeBaseSearchResult?>(
      context: context,
      delegate: _KnowledgeBaseSearchDelegate(
        documents: documents,
        cards: cards,
      ),
    );
    if (!mounted || result == null) return;
    context.push(result.route);
  }
}

class _KnowledgeBaseHeader extends StatelessWidget {
  const _KnowledgeBaseHeader({required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      const Expanded(
        child: Text(
          '知识库',
          style: TextStyle(
            color: AppVisualColors.ink,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
      ),
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onSearch,
          borderRadius: BorderRadius.circular(18),
          child: const SizedBox(
            width: 56,
            height: 56,
            child: Icon(
              Icons.search_rounded,
              size: 28,
              color: AppVisualColors.ink,
            ),
          ),
        ),
      ),
    ],
  );
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({
    required this.documentCount,
    required this.cardCount,
    required this.marketCount,
    required this.onDocuments,
    required this.onCards,
    required this.onMarket,
  });

  final int documentCount;
  final int cardCount;
  final int? marketCount;
  final VoidCallback onDocuments;
  final VoidCallback onCards;
  final VoidCallback onMarket;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _ShortcutCard(
          title: '全部文档',
          detail: '$documentCount 篇文档',
          icon: Icons.folder_rounded,
          foreground: const Color(0xff159c3a),
          background: const Color(0xfff0faef),
          onTap: onDocuments,
        ),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: _ShortcutCard(
          title: '我的卡牌',
          detail: '$cardCount 张卡牌',
          icon: Icons.style_rounded,
          foreground: const Color(0xff4778e8),
          background: const Color(0xfff0f4ff),
          onTap: onCards,
        ),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: _ShortcutCard(
          title: '资源市场',
          detail: marketCount == null ? '浏览新牌组' : '$marketCount 个牌组',
          icon: Icons.shopping_bag_rounded,
          foreground: const Color(0xffe9950b),
          background: const Color(0xfffff8eb),
          onTap: onMarket,
        ),
      ),
    ],
  );
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.title,
    required this.detail,
    required this.icon,
    required this.foreground,
    required this.background,
    required this.onTap,
  });

  final String title;
  final String detail;
  final IconData icon;
  final Color foreground;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: background,
    borderRadius: BorderRadius.circular(22),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: 126,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: foreground, size: 30),
              const Spacer(),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppVisualColors.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppVisualColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: foreground,
                    size: 20,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SectionSwitcher extends StatelessWidget {
  const _SectionSwitcher({required this.selected, required this.onChanged});

  final KnowledgeBaseSection selected;
  final ValueChanged<KnowledgeBaseSection> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 62,
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      boxShadow: appCardShadow,
    ),
    child: Row(
      children: [
        _SectionButton(
          label: '最近使用',
          section: KnowledgeBaseSection.recent,
          selected: selected,
          onChanged: onChanged,
        ),
        _SectionButton(
          label: '我的文档',
          section: KnowledgeBaseSection.documents,
          selected: selected,
          onChanged: onChanged,
        ),
        _SectionButton(
          label: '我的卡牌',
          section: KnowledgeBaseSection.cards,
          selected: selected,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _SectionButton extends StatelessWidget {
  const _SectionButton({
    required this.label,
    required this.section,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final KnowledgeBaseSection section;
  final KnowledgeBaseSection selected;
  final ValueChanged<KnowledgeBaseSection> onChanged;

  @override
  Widget build(BuildContext context) {
    final active = section == selected;
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: InkWell(
          onTap: () => onChanged(section),
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 52,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: active
                        ? AppVisualColors.darkGreen
                        : AppVisualColors.muted,
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: active ? 30 : 0,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppVisualColors.green,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionContent extends StatelessWidget {
  const _SectionContent({
    required this.section,
    required this.documents,
    required this.cards,
  });

  final KnowledgeBaseSection section;
  final List<DocumentModel> documents;
  final List<CardModel> cards;

  @override
  Widget build(BuildContext context) {
    final decks = _groupCards(cards);
    return switch (section) {
      KnowledgeBaseSection.recent => _RecentSection(
        documents: documents,
        decks: decks,
      ),
      KnowledgeBaseSection.documents => _DocumentsSection(documents: documents),
      KnowledgeBaseSection.cards => _CardsSection(decks: decks),
    };
  }

  static List<_DeckSummary> _groupCards(List<CardModel> cards) {
    final groups = <String, List<CardModel>>{};
    for (final card in cards) {
      final folder = card.folder.trim();
      groups.putIfAbsent(folder, () => []).add(card);
    }
    final summaries =
        groups.entries
            .map((entry) => _DeckSummary(folder: entry.key, cards: entry.value))
            .toList()
          ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return summaries;
  }
}

class _RecentSection extends StatelessWidget {
  const _RecentSection({required this.documents, required this.decks});

  final List<DocumentModel> documents;
  final List<_DeckSummary> decks;

  @override
  Widget build(BuildContext context) {
    final entries = <_RecentEntry>[
      ...documents.map(
        (document) => _RecentEntry(
          title: document.title,
          subtitle: '${_folderLabel(document.folder)} · 文档',
          updatedAt: document.updatedAt,
          icon: Icons.description_rounded,
          iconColor: AppVisualColors.green,
          iconBackground: AppVisualColors.softGreen,
          onTap: () => context.push('/library/document/${document.id}'),
        ),
      ),
      ...decks.map(
        (deck) => _RecentEntry(
          title: deck.name,
          subtitle: '本地牌组 · ${deck.cards.length} 张卡牌',
          updatedAt: deck.updatedAt,
          icon: Icons.style_rounded,
          iconColor: const Color(0xff4778e8),
          iconBackground: const Color(0xfff0f4ff),
          onTap: () => context.push('/cards/deck', extra: deck.routeFolder),
        ),
      ),
    ]..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));

    final visible = entries.take(5).toList();
    return _SectionPanel(
      title: '最近使用',
      subtitle: visible.isEmpty ? null : '最近打开的文档和牌组',
      child: visible.isEmpty
          ? const EmptyState(
              title: '还没有最近使用的资源',
              message: '打开文档或牌组后，这里会显示最近内容。',
              icon: Icons.history_rounded,
            )
          : _ResourceList(entries: visible),
    );
  }
}

class _DocumentsSection extends StatelessWidget {
  const _DocumentsSection({required this.documents});

  final List<DocumentModel> documents;

  @override
  Widget build(BuildContext context) {
    final entries = [...documents]
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return _SectionPanel(
      title: '我的文档',
      subtitle: '${documents.length} 篇文档',
      child: entries.isEmpty
          ? const EmptyState(
              title: '还没有同步文档',
              message: '完成首次同步后，文档会显示在这里。',
              icon: Icons.description_outlined,
            )
          : _ResourceList(
              entries: entries
                  .map(
                    (document) => _RecentEntry(
                      title: document.title,
                      subtitle: _folderLabel(document.folder),
                      updatedAt: document.updatedAt,
                      icon: Icons.description_rounded,
                      iconColor: AppVisualColors.green,
                      iconBackground: AppVisualColors.softGreen,
                      onTap: () =>
                          context.push('/library/document/${document.id}'),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _CardsSection extends StatelessWidget {
  const _CardsSection({required this.decks});

  final List<_DeckSummary> decks;

  @override
  Widget build(BuildContext context) => _SectionPanel(
    title: '我的卡牌',
    subtitle: '${decks.length} 个牌组 · ${_cardCount(decks)} 张卡牌',
    child: decks.isEmpty
        ? const EmptyState(
            title: '还没有本地卡牌',
            message: '同步内容后，牌组会显示在这里。',
            icon: Icons.style_outlined,
          )
        : _ResourceList(
            entries: decks
                .map(
                  (deck) => _RecentEntry(
                    title: deck.name,
                    subtitle:
                        '${deck.cards.length} 张卡牌 · ${deck.dueCount} 张待复习',
                    updatedAt: deck.updatedAt,
                    icon: Icons.style_rounded,
                    iconColor: const Color(0xff4778e8),
                    iconBackground: const Color(0xfff0f4ff),
                    onTap: () =>
                        context.push('/cards/deck', extra: deck.routeFolder),
                  ),
                )
                .toList(),
          ),
  );

  static int _cardCount(List<_DeckSummary> decks) {
    return decks.fold(0, (total, deck) => total + deck.cards.length);
  }
}

class _SectionPanel extends StatelessWidget {
  const _SectionPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppVisualSectionTitle(title: title, subtitle: subtitle),
      const SizedBox(height: 10),
      child,
    ],
  );
}

class _ResourceList extends StatelessWidget {
  const _ResourceList({required this.entries});

  final List<_RecentEntry> entries;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: appCardShadow,
    ),
    child: Column(
      children: [
        for (var index = 0; index < entries.length; index++) ...[
          _ResourceRow(entry: entries[index]),
          if (index < entries.length - 1)
            const Divider(indent: 74, endIndent: 14, color: Color(0xffedf0ed)),
        ],
      ],
    ),
  );
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({required this.entry});

  final _RecentEntry entry;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: entry.onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: entry.iconBackground,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(entry.icon, color: entry.iconColor, size: 23),
            ),
            const SizedBox(width: 12),
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
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    entry.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppVisualColors.muted,
                      fontSize: 12,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  DateFormat('MM-dd').format(entry.updatedAt.toLocal()),
                  style: const TextStyle(
                    color: AppVisualColors.muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppVisualColors.muted,
                  size: 19,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _RecentEntry {
  const _RecentEntry({
    required this.title,
    required this.subtitle,
    required this.updatedAt,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final DateTime updatedAt;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final VoidCallback onTap;
}

class _DeckSummary {
  const _DeckSummary({required this.folder, required this.cards});

  final String folder;
  final List<CardModel> cards;

  String get name => folder.trim().isEmpty ? '未分类' : folder;

  String get routeFolder => folder.trim().isEmpty ? '未分类' : folder;

  DateTime get updatedAt {
    var latest = cards.first.updatedAt;
    for (final card in cards.skip(1)) {
      if (card.updatedAt.isAfter(latest)) latest = card.updatedAt;
    }
    return latest;
  }

  int get dueCount => cards.where((card) => card.isDue).length;
}

String _folderLabel(String folder) {
  final value = folder.trim();
  return value.isEmpty ? '未分类' : value;
}

class _KnowledgeBaseError extends StatelessWidget {
  const _KnowledgeBaseError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: EmptyState(
      title: '知识库加载失败',
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

class _KnowledgeBaseSearchResult {
  const _KnowledgeBaseSearchResult({required this.route});

  final String route;
}

class _KnowledgeBaseSearchDelegate
    extends SearchDelegate<_KnowledgeBaseSearchResult?> {
  _KnowledgeBaseSearchDelegate({required this.documents, required this.cards});

  final List<DocumentModel> documents;
  final List<CardModel> cards;

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
  Widget buildResults(BuildContext context) => _buildResults(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildResults(context);

  Widget _buildResults(BuildContext context) {
    final value = query.trim().toLowerCase();
    if (value.isEmpty) {
      return const EmptyState(
        title: '搜索知识库',
        message: '输入标题、牌组或卡牌内容',
        icon: Icons.search_rounded,
      );
    }

    final results = <_SearchListItem>[
      ...documents
          .where(
            (document) =>
                '${document.title} ${document.folder} ${document.body}'
                    .toLowerCase()
                    .contains(value),
          )
          .map(
            (document) => _SearchListItem(
              title: document.title,
              subtitle: '${_folderLabel(document.folder)} · 文档',
              icon: Icons.description_rounded,
              color: AppVisualColors.green,
              background: AppVisualColors.softGreen,
              result: _KnowledgeBaseSearchResult(
                route: '/library/document/${document.id}',
              ),
            ),
          ),
      ...cards
          .where(
            (card) =>
                '${card.question} ${card.noteContent} ${card.tags.join(' ')}'
                    .toLowerCase()
                    .contains(value),
          )
          .take(20)
          .map(
            (card) => _SearchListItem(
              title: card.question,
              subtitle: '${_folderLabel(card.folder)} · 卡牌',
              icon: Icons.style_rounded,
              color: const Color(0xff4778e8),
              background: const Color(0xfff0f4ff),
              result: _KnowledgeBaseSearchResult(route: '/cards/${card.id}'),
            ),
          ),
    ];

    if (results.isEmpty) {
      return const EmptyState(
        title: '没有匹配内容',
        message: '尝试修改搜索词。',
        icon: Icons.search_off_rounded,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = results[index];
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            leading: CircleAvatar(
              backgroundColor: item.background,
              foregroundColor: item.color,
              child: Icon(item.icon, size: 20),
            ),
            title: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(item.subtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => close(context, item.result),
          ),
        );
      },
    );
  }
}

class _SearchListItem {
  const _SearchListItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.background,
    required this.result,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color background;
  final _KnowledgeBaseSearchResult result;
}
