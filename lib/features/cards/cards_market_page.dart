import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_providers.dart';
import '../../core/models/card_model.dart';
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
                padding: const EdgeInsets.fromLTRB(
                  16,
                  10,
                  16,
                  AppLayoutMetrics.bottomNavigationContentPadding + 32,
                ),
                children: [
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

class _DocumentsSection extends ConsumerWidget {
  const _DocumentsSection({required this.documents});

  final List<DocumentModel> documents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = [...documents]
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return _LimitedResourceSection(
      title: '我的文档',
      subtitle: '${documents.length} 篇文档',
      entries: entries
          .map(
            (document) => _ResourceEntry(
              title: document.title,
              subtitle: _folderLabel(document.folder),
              updatedAt: document.updatedAt,
              icon: Icons.description_rounded,
              iconColor: AppVisualColors.green,
              iconBackground: AppVisualColors.softGreen,
              onTap: () => context.push('/library/document/${document.id}'),
              onRename: () => _renameDocument(context, ref, document),
              onDelete: () => _deleteDocument(context, ref, document),
            ),
          )
          .toList(),
      emptyState: const EmptyState(
        title: '还没有同步文档',
        message: '完成首次同步后，文档会显示在这里。',
        icon: Icons.description_outlined,
      ),
    );
  }

  Future<void> _renameDocument(
    BuildContext context,
    WidgetRef ref,
    DocumentModel document,
  ) async {
    final title = await showRenameResourceDialog(
      context,
      title: '重命名文档',
      initialValue: document.title,
      hintText: '输入文档名称',
    );
    if (title == null || !context.mounted) return;
    try {
      await ref
          .read(contentRepositoryProvider)
          .renameDocument(document: document, title: title);
      ref.invalidate(documentsProvider);
      ref.invalidate(pendingSyncProvider);
      ref
          .read(syncControllerProvider.notifier)
          .scheduleSync(reason: 'document-rename');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('文档已重命名，等待同步。')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('重命名失败：$error')));
      }
    }
  }

  Future<void> _deleteDocument(
    BuildContext context,
    WidgetRef ref,
    DocumentModel document,
  ) async {
    final confirmed = await showDeleteResourceDialog(
      context,
      title: '删除这篇文档？',
      message: '删除后会从本地移除，并在下次同步时从其他设备删除。',
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref
          .read(contentRepositoryProvider)
          .deleteDocument(
            accountId: document.accountId,
            documentId: document.id,
          );
      ref.invalidate(documentsProvider);
      ref.invalidate(pendingSyncProvider);
      ref
          .read(syncControllerProvider.notifier)
          .scheduleSync(reason: 'document-delete');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('文档已删除，等待同步。')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }
}

class _CardsSection extends ConsumerWidget {
  const _CardsSection({required this.decks});

  final List<_DeckSummary> decks;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _LimitedResourceSection(
    title: '我的卡牌',
    subtitle: '${decks.length} 个牌组 · ${_cardCount(decks)} 张卡牌',
    entries: decks
        .map(
          (deck) => _ResourceEntry(
            title: deck.name,
            subtitle: '${deck.cards.length} 张卡牌 · ${deck.dueCount} 张待复习',
            updatedAt: deck.updatedAt,
            icon: Icons.style_rounded,
            iconColor: const Color(0xff4778e8),
            iconBackground: const Color(0xfff0f4ff),
            onTap: () => context.push('/cards/deck', extra: deck.routeFolder),
            onRename: () => _renameDeck(context, ref, deck),
            onDelete: () => _deleteDeck(context, ref, deck),
          ),
        )
        .toList(),
    emptyState: const EmptyState(
      title: '还没有本地卡牌',
      message: '同步内容后，牌组会显示在这里。',
      icon: Icons.style_outlined,
    ),
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
      final count = await ref
          .read(contentRepositoryProvider)
          .renameDeck(
            accountId: deck.cards.first.accountId,
            folder: deck.routeFolder,
            name: name,
          );
      ref.invalidate(cardsProvider);
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
      title: '删除这个牌组？',
      message: '牌组中的 ${deck.cards.length} 张卡牌会从本地移除，并在下次同步时从其他设备删除。',
    );
    if (!confirmed || !context.mounted) return;
    try {
      final count = await ref
          .read(contentRepositoryProvider)
          .deleteDeck(
            accountId: deck.cards.first.accountId,
            folder: deck.routeFolder,
          );
      ref.invalidate(cardsProvider);
      ref.invalidate(pendingSyncProvider);
      ref
          .read(syncControllerProvider.notifier)
          .scheduleSync(reason: 'deck-delete');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已删除 $count 张卡牌，等待同步。')));
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

class _LimitedResourceSection extends StatefulWidget {
  const _LimitedResourceSection({
    required this.title,
    required this.subtitle,
    required this.entries,
    required this.emptyState,
  });

  static const maxInitialEntries = 5;

  final String title;
  final String subtitle;
  final List<_ResourceEntry> entries;
  final Widget emptyState;

  @override
  State<_LimitedResourceSection> createState() =>
      _LimitedResourceSectionState();
}

class _LimitedResourceSectionState extends State<_LimitedResourceSection> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final hasMore =
        widget.entries.length > _LimitedResourceSection.maxInitialEntries;
    final visibleEntries =
        widget.entries.length <= _LimitedResourceSection.maxInitialEntries ||
            _showAll
        ? widget.entries
        : widget.entries
              .take(_LimitedResourceSection.maxInitialEntries)
              .toList();

    return _SectionPanel(
      title: widget.title,
      subtitle: widget.subtitle,
      trailing: hasMore
          ? TextButton.icon(
              onPressed: () => setState(() => _showAll = !_showAll),
              icon: Icon(
                _showAll
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18,
              ),
              label: Text(_showAll ? '收起' : '显示更多'),
              style: TextButton.styleFrom(
                foregroundColor: AppVisualColors.darkGreen,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            )
          : null,
      child: widget.entries.isEmpty
          ? widget.emptyState
          : _ResourceList(entries: visibleEntries),
    );
  }
}

class _SectionPanel extends StatelessWidget {
  const _SectionPanel({
    required this.title,
    required this.subtitle,
    this.trailing,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AppVisualSectionTitle(title: title, subtitle: subtitle),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Padding(padding: const EdgeInsets.only(top: 1), child: trailing!),
          ],
        ],
      ),
      const SizedBox(height: 10),
      child,
    ],
  );
}

class _ResourceList extends StatelessWidget {
  const _ResourceList({required this.entries});

  final List<_ResourceEntry> entries;

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

  final _ResourceEntry entry;

  @override
  Widget build(BuildContext context) => SwipeActionTile(
    onTap: entry.onTap,
    onRename: entry.onRename,
    onDelete: entry.onDelete,
    borderRadius: BorderRadius.zero,
    boxShadow: const [],
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
  );
}

class _ResourceEntry {
  const _ResourceEntry({
    required this.title,
    required this.subtitle,
    required this.updatedAt,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final String title;
  final String subtitle;
  final DateTime updatedAt;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
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
