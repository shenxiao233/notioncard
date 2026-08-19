import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_providers.dart';
import '../../core/models/card_model.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_visuals.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/markdown_content.dart';
import '../../core/widgets/resource_action_dialogs.dart';
import '../../core/widgets/swipe_action_tile.dart';
import 'card_favorites.dart';
import '../review/review_queue.dart';

enum _CardSort { original, due, recent, reviews, created }

enum _CardSortDirection { ascending, descending }

enum _CardReviewFilter { mastered, reviewing }

class CardsPage extends ConsumerWidget {
  const CardsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(cardsProvider);
    return Scaffold(
      backgroundColor: AppVisualColors.background,
      body: SafeArea(
        bottom: false,
        child: cards.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppVisualColors.green),
          ),
          error: (error, _) =>
              _CardsError(onRetry: () => ref.invalidate(cardsProvider)),
          data: (values) => RefreshIndicator(
            onRefresh: () => _refreshCards(ref),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                16,
                12,
                16,
                AppLayoutMetrics.bottomNavigationContentPadding + 28,
              ),
              children: [
                _LibrarySummary(cards: values),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: AppVisualSectionTitle(
                        title: '我的牌组',
                        subtitle: '管理牌组与批量导入卡片',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/cards/import'),
                      icon: const Icon(Icons.file_upload_outlined, size: 17),
                      label: const Text('导入'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppVisualColors.darkGreen,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (values.isEmpty)
                  const EmptyState(
                    title: '还没有本地卡片',
                    message: '同步内容后，牌组会显示在这里。',
                    icon: Icons.style_outlined,
                  )
                else
                  ..._groupCards(values).entries.map(
                    (entry) => _DeckTile(
                      folder: entry.key,
                      cards: entry.value,
                      onRename: () => _renameDeck(context, ref, entry.key),
                      onDelete: () => _deleteDeck(context, ref, entry.key),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _refreshCards(WidgetRef ref) async {
    await ref
        .read(syncControllerProvider.notifier)
        .sync(reason: 'cards-refresh');
    ref.invalidate(cardsProvider);
    await ref.read(cardsProvider.future);
  }

  Future<void> _renameDeck(
    BuildContext context,
    WidgetRef ref,
    String folder,
  ) async {
    final name = await showRenameResourceDialog(
      context,
      title: '重命名牌组',
      initialValue: folder,
      hintText: '输入牌组名称',
    );
    if (name == null || !context.mounted) return;
    try {
      final count = await ref
          .read(contentRepositoryProvider)
          .renameDeck(
            accountId: ref.read(currentAccountProvider)!.id,
            folder: folder,
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
    String folder,
  ) async {
    final cards = await ref.read(cardsProvider.future);
    final count = cards.where((card) {
      final cardFolder = card.folder.trim();
      return folder == '未分类' ? cardFolder.isEmpty : cardFolder == folder.trim();
    }).length;
    if (!context.mounted) return;
    final confirmed = await showDeleteResourceDialog(
      context,
      title: '删除这个牌组？',
      message: '牌组中的 $count 张卡牌会从本地移除，并在下次同步时从其他设备删除。',
    );
    if (!confirmed || !context.mounted) return;
    try {
      final deleted = await ref
          .read(contentRepositoryProvider)
          .deleteDeck(
            accountId: ref.read(currentAccountProvider)!.id,
            folder: folder,
          );
      ref.invalidate(cardsProvider);
      ref.invalidate(pendingSyncProvider);
      ref
          .read(syncControllerProvider.notifier)
          .scheduleSync(reason: 'deck-delete');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已删除 $deleted 张卡牌，等待同步。')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  static Map<String, List<CardModel>> _groupCards(List<CardModel> cards) {
    final groups = <String, List<CardModel>>{};
    for (final card in cards) {
      groups
          .putIfAbsent(
            card.folder.trim().isEmpty ? '未分类' : card.folder,
            () => [],
          )
          .add(card);
    }
    final entries = groups.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return {for (final entry in entries) entry.key: entry.value};
  }
}

class DeckCardsPage extends ConsumerStatefulWidget {
  const DeckCardsPage({required this.folder, super.key});

  final String folder;

  @override
  ConsumerState<DeckCardsPage> createState() => _DeckCardsPageState();
}

class _DeckCardsPageState extends ConsumerState<DeckCardsPage> {
  final _searchController = TextEditingController();
  String _query = '';
  CardType? _type;
  _CardReviewFilter? _reviewFilter;
  _CardSort _sort = _CardSort.original;
  _CardSortDirection? _sortDirection;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(cardsProvider);
    final favoriteCardIds = ref.watch(cardFavoritesProvider);
    return Scaffold(
      backgroundColor: AppVisualColors.background,
      body: SafeArea(
        bottom: false,
        child: cards.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppVisualColors.green),
          ),
          error: (error, _) =>
              _CardsError(onRetry: () => ref.invalidate(cardsProvider)),
          data: (values) {
            final all = values
                .where((card) => _folderOf(card) == widget.folder)
                .toList();
            final filtered = _filtered(all);
            return RefreshIndicator(
              onRefresh: _refreshCards,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 28),
                children: [
                  _DeckHeader(folder: widget.folder, cards: all),
                  const SizedBox(height: 22),
                  _SearchBar(
                    controller: _searchController,
                    query: _query,
                    hasFilters:
                        _type != null ||
                        _reviewFilter != null ||
                        _sort != _CardSort.original ||
                        _sortDirection != null,
                    onChanged: (value) => setState(() => _query = value),
                    onClear: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    onFilter: _showFilterSheet,
                  ),
                  const SizedBox(height: 18),
                  if (filtered.isEmpty)
                    EmptyState(
                      title: all.isEmpty ? '牌组为空' : '没有匹配的卡片',
                      message: all.isEmpty ? '可以从桌面端同步卡片到这里。' : '尝试清除搜索或筛选条件。',
                      icon: Icons.style_outlined,
                      action: all.isEmpty || !_hasFilters
                          ? null
                          : OutlinedButton(
                              onPressed: _clearFilters,
                              child: const Text('清除筛选'),
                            ),
                    )
                  else
                    ...filtered.map(
                      (card) => _CardListItem(
                        card: card,
                        favorite: favoriteCardIds.contains(card.id),
                        onEdit: () => _openExistingCardEditor(card),
                        onDelete: () => _confirmDeleteCard(card),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.small(
        tooltip: '新增卡片',
        onPressed: _openCardEditor,
        backgroundColor: AppVisualColors.green,
        foregroundColor: Colors.white,
        elevation: 5,
        shape: const CircleBorder(),
        child: const Icon(Icons.add_rounded, size: 22),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  String _folderOf(CardModel card) =>
      card.folder.trim().isEmpty ? '未分类' : card.folder;

  bool get _hasFilters =>
      _query.trim().isNotEmpty ||
      _type != null ||
      _reviewFilter != null ||
      _sort != _CardSort.original ||
      _sortDirection != null;

  List<CardModel> _filtered(List<CardModel> values) {
    final query = _query.trim().toLowerCase();
    final result = values.where((card) {
      return (_type == null || card.type == _type) &&
          (_reviewFilter == null ||
              (_reviewFilter == _CardReviewFilter.mastered
                  ? card.isMastered
                  : !card.isMastered)) &&
          (query.isEmpty ||
              card.question.toLowerCase().contains(query) ||
              card.tags.any((tag) => tag.toLowerCase().contains(query)));
    }).toList();
    result.sort(_compareCards);
    return result;
  }

  int _compareCards(CardModel left, CardModel right) {
    final base = switch (_sort) {
      _CardSort.original => compareCardOrder(left, right),
      _CardSort.due => left.dueAt.compareTo(right.dueAt),
      _CardSort.recent => left.updatedAt.compareTo(right.updatedAt),
      _CardSort.reviews => left.reviews.compareTo(right.reviews),
      _CardSort.created => left.createdAt.compareTo(right.createdAt),
    };
    final direction = _sortDirection ?? _defaultSortDirection(_sort);
    final comparison = direction == _CardSortDirection.ascending ? base : -base;
    return comparison != 0 ? comparison : left.id.compareTo(right.id);
  }

  _CardSortDirection _defaultSortDirection(_CardSort sort) => switch (sort) {
    _CardSort.original => _CardSortDirection.ascending,
    _CardSort.due => _CardSortDirection.ascending,
    _CardSort.recent => _CardSortDirection.descending,
    _CardSort.reviews => _CardSortDirection.descending,
    _CardSort.created => _CardSortDirection.descending,
  };

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _type = null;
      _reviewFilter = null;
      _sort = _CardSort.original;
      _sortDirection = null;
    });
  }

  Future<void> _refreshCards() async {
    await ref
        .read(syncControllerProvider.notifier)
        .sync(reason: 'cards-deck-refresh');
    ref.invalidate(cardsProvider);
    await ref.read(cardsProvider.future);
  }

  Future<void> _showFilterSheet() async {
    var selectedType = _type;
    var selectedReviewFilter = _reviewFilter;
    var selectedSort = _sort;
    var selectedDirection = _sortDirection;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('筛选卡片', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<CardType?>(
                initialValue: selectedType,
                decoration: const InputDecoration(labelText: '卡片类型'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('全部类型')),
                  ...CardType.values.map(
                    (type) =>
                        DropdownMenuItem(value: type, child: Text(type.label)),
                  ),
                ],
                onChanged: (value) => setSheetState(() => selectedType = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<bool?>(
                initialValue: selectedReviewFilter == null
                    ? null
                    : selectedReviewFilter == _CardReviewFilter.mastered,
                decoration: const InputDecoration(labelText: '复习状态'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('全部状态')),
                  DropdownMenuItem(value: true, child: Text('已掌握')),
                  DropdownMenuItem(value: false, child: Text('复习中')),
                ],
                onChanged: (value) => setSheetState(
                  () => selectedReviewFilter = value == null
                      ? null
                      : value
                      ? _CardReviewFilter.mastered
                      : _CardReviewFilter.reviewing,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<_CardSort>(
                initialValue: selectedSort,
                decoration: const InputDecoration(labelText: '排序方式'),
                items: _CardSort.values
                    .map(
                      (sort) => DropdownMenuItem(
                        value: sort,
                        child: Text(_sortLabel(sort)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setSheetState(() => selectedSort = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<_CardSortDirection?>(
                initialValue: selectedDirection,
                decoration: const InputDecoration(labelText: '排序方向'),
                items: [
                  const DropdownMenuItem<_CardSortDirection?>(
                    value: null,
                    child: Text('默认顺序'),
                  ),
                  ..._CardSortDirection.values.map(
                    (direction) => DropdownMenuItem<_CardSortDirection?>(
                      value: direction,
                      child: Text(_sortDirectionLabel(direction)),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    setSheetState(() => selectedDirection = value),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    setState(() {
                      _type = selectedType;
                      _reviewFilter = selectedReviewFilter;
                      _sort = selectedSort;
                      _sortDirection = selectedDirection;
                    });
                    Navigator.of(sheetContext).pop();
                  },
                  child: const Text('应用筛选'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCardEditor() async {
    await context.push('/edit/card', extra: widget.folder);
    if (mounted) ref.invalidate(cardsProvider);
  }

  Future<void> _openExistingCardEditor(CardModel card) async {
    await context.push('/edit/card', extra: card);
    if (mounted) ref.invalidate(cardsProvider);
  }

  String _sortLabel(_CardSort sort) => switch (sort) {
    _CardSort.original => '按原始顺序',
    _CardSort.due => '按下次复习时间',
    _CardSort.recent => '按最近更新',
    _CardSort.reviews => '按复习次数',
    _CardSort.created => '按创建时间',
  };

  String _sortDirectionLabel(_CardSortDirection direction) =>
      switch (direction) {
        _CardSortDirection.ascending => '升序',
        _CardSortDirection.descending => '降序',
      };

  Future<void> _confirmDeleteCard(CardModel card) async {
    final confirmed = await _confirm(
      title: '删除这张卡片？',
      message: '删除后会从本地移除，并在下次同步时从其他设备删除。',
    );
    if (!confirmed || !mounted) return;
    final account = ref.read(currentAccountProvider);
    if (account == null) return;
    await ref
        .read(contentRepositoryProvider)
        .deleteCard(accountId: account.id, cardId: card.id);
    ref.invalidate(cardsProvider);
    ref.invalidate(pendingSyncProvider);
    ref
        .read(syncControllerProvider.notifier)
        .scheduleSync(reason: 'card-delete');
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('卡片已删除，等待同步。')));
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _CardsError extends StatelessWidget {
  const _CardsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
    title: '卡片加载失败',
    message: '请检查网络或本地缓存，然后重试。',
    icon: Icons.cloud_off_outlined,
    action: FilledButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh),
      label: const Text('重试'),
    ),
  );
}

class _LibrarySummary extends StatelessWidget {
  const _LibrarySummary({required this.cards});

  final List<CardModel> cards;

  @override
  Widget build(BuildContext context) {
    final due = cards.where((card) => card.isDue).length;
    return Row(
      children: [
        Expanded(
          child: _SummaryMetric(
            label: '牌组',
            value: '${CardsPage._groupCards(cards).length}',
            icon: Icons.folder_copy_rounded,
            color: AppVisualColors.green,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _SummaryMetric(
            label: '卡片',
            value: '${cards.length}',
            icon: Icons.style_rounded,
            color: AppVisualColors.darkGreen,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _SummaryMetric(
            label: '待复习',
            value: '$due',
            icon: Icons.schedule_rounded,
            color: due > 0 ? AppVisualColors.amber : AppVisualColors.green,
          ),
        ),
      ],
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    height: 82,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: appCardShadow,
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppVisualColors.darkGreen,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: AppVisualColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class _DeckTile extends StatelessWidget {
  const _DeckTile({
    required this.folder,
    required this.cards,
    required this.onRename,
    required this.onDelete,
  });

  final String folder;
  final List<CardModel> cards;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final due = cards.where((card) => card.isDue).length;
    return SwipeActionTile(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: () => context.push('/cards/deck', extra: folder),
      onRename: onRename,
      onDelete: onDelete,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: AppVisualColors.softGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.folder_copy_rounded,
                color: AppVisualColors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppVisualColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${cards.length} 张卡片 · $due 张待复习',
                    style: const TextStyle(
                      color: AppVisualColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppVisualColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _DeckHeader extends StatelessWidget {
  const _DeckHeader({required this.folder, required this.cards});

  final String folder;
  final List<CardModel> cards;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(_titleSpan, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 5),
        Text(
          '${cards.length} 张卡片',
          style: const TextStyle(
            color: AppVisualColors.muted,
            fontSize: 13,
            height: 1.25,
          ),
        ),
      ],
    );
  }

  InlineSpan get _titleSpan {
    final match = RegExp(r'(\d+\s*词)$').firstMatch(folder);
    if (match == null) {
      return TextSpan(
        text: folder,
        style: TextStyle(
          color: AppVisualColors.ink,
          fontSize: 21,
          fontWeight: FontWeight.w700,
          height: 1.15,
        ),
      );
    }
    final index = match.start;
    return TextSpan(
      children: [
        TextSpan(text: folder.substring(0, index)),
        TextSpan(
          text: folder.substring(index),
          style: const TextStyle(color: AppVisualColors.green),
        ),
      ],
      style: const TextStyle(
        color: AppVisualColors.ink,
        fontSize: 21,
        fontWeight: FontWeight.w700,
        height: 1.15,
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.query,
    required this.hasFilters,
    required this.onChanged,
    required this.onClear,
    required this.onFilter,
  });

  final TextEditingController controller;
  final String query;
  final bool hasFilters;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) => Container(
    height: 50,
    padding: const EdgeInsets.only(left: 14, right: 3),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0a000000),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      children: [
        const Icon(
          Icons.search_rounded,
          color: AppVisualColors.muted,
          size: 22,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            textAlignVertical: TextAlignVertical.center,
            cursorColor: AppVisualColors.green,
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              isDense: true,
              isCollapsed: true,
              contentPadding: EdgeInsets.zero,
              hintText: '搜索题干或标签',
              hintStyle: TextStyle(
                color: AppVisualColors.muted,
                fontSize: 13,
                height: 1.25,
              ),
            ),
            style: const TextStyle(
              color: AppVisualColors.ink,
              fontSize: 14,
              height: 1.25,
            ),
          ),
        ),
        if (query.isNotEmpty)
          IconButton(
            tooltip: '清除搜索',
            onPressed: onClear,
            icon: const Icon(Icons.clear_rounded, size: 19),
            color: AppVisualColors.muted,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 38, height: 38),
            padding: EdgeInsets.zero,
          ),
        IconButton(
          tooltip: '筛选和排序',
          onPressed: onFilter,
          icon: Icon(
            hasFilters ? Icons.filter_alt_rounded : Icons.tune_rounded,
            size: 21,
          ),
          color: hasFilters ? AppVisualColors.green : AppVisualColors.muted,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 38, height: 38),
          padding: EdgeInsets.zero,
        ),
      ],
    ),
  );
}

class _CardListItem extends StatefulWidget {
  const _CardListItem({
    required this.card,
    required this.favorite,
    required this.onEdit,
    required this.onDelete,
  });

  final CardModel card;
  final bool favorite;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_CardListItem> createState() => _CardListItemState();
}

class _CardListItemState extends State<_CardListItem> {
  static const _actionWidth = 144.0;
  double _offset = 0;
  bool _dragging = false;

  void _handleDragStart(DragStartDetails details) {
    setState(() => _dragging = true);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      _offset = (_offset + details.delta.dx).clamp(-_actionWidth, 0.0);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    setState(() {
      _dragging = false;
      _offset = _offset < -_actionWidth * 0.45 ? -_actionWidth : 0;
    });
  }

  void _close() {
    if (_offset == 0) return;
    setState(() => _offset = 0);
  }

  void _openOrNavigate(BuildContext context) {
    if (_offset != 0) {
      _close();
      return;
    }
    context.push('/cards/${widget.card.id}');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0b000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Positioned.fill(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _SwipeAction(
                    width: _actionWidth / 2,
                    color: AppVisualColors.green,
                    icon: Icons.edit_rounded,
                    label: '修改',
                    onPressed: () {
                      _close();
                      widget.onEdit();
                    },
                  ),
                  _SwipeAction(
                    width: _actionWidth / 2,
                    color: const Color(0xffd94a45),
                    icon: Icons.delete_outline_rounded,
                    label: '删除',
                    onPressed: () {
                      _close();
                      widget.onDelete();
                    },
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: _dragging
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(_offset, 0, 0),
              alignment: Alignment.centerLeft,
              color: Colors.white,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openOrNavigate(context),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 88),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: _handleDragStart,
                      onHorizontalDragUpdate: _handleDragUpdate,
                      onHorizontalDragEnd: _handleDragEnd,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: const BoxDecoration(
                                color: AppVisualColors.softGreen,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.lightbulb_outline_rounded,
                                color: AppVisualColors.green,
                                size: 19,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ImageLinkPreview(
                                    data: widget.card.question,
                                    maxLines: 2,
                                    thumbnailWidth: 116,
                                    thumbnailHeight: 72,
                                    textStyle: const TextStyle(
                                      color: AppVisualColors.ink,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      height: 1.25,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Row(
                                    children: [
                                      _CardStateBadge(card: widget.card),
                                      if (widget.favorite) ...[
                                        const SizedBox(width: 6),
                                        const Icon(
                                          Icons.star_rounded,
                                          size: 15,
                                          color: Color(0xffe1a633),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AppVisualColors.muted,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardStateBadge extends StatelessWidget {
  const _CardStateBadge({required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context) {
    final mastered = card.isMastered;
    final background = mastered
        ? const Color(0xffedf8ee)
        : const Color(0xfff6f2ea);
    final foreground = mastered
        ? AppVisualColors.darkGreen
        : const Color(0xff9b5d25);
    final label = card.reviewCountLabel.isEmpty
        ? card.reviewStatusLabel
        : '${card.reviewStatusLabel} · ${card.reviewCountLabel}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          height: 1.1,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SwipeAction extends StatelessWidget {
  const _SwipeAction({
    required this.width,
    required this.color,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final double width;
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: double.infinity,
    child: Material(
      color: color,
      child: InkWell(
        onTap: onPressed,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
