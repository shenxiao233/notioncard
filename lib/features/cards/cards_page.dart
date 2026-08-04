import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_providers.dart';
import '../../core/models/card_model.dart';
import '../../core/widgets/app_visuals.dart';
import '../../core/widgets/empty_state.dart';

enum _CardSort { due, recent, reviews, created }

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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                LayoutBuilder(
                  builder: (context, constraints) => AppVisualTitle(
                    title: '卡片',
                    subtitle: '先选择牌组，再浏览其中的复习卡片。',
                    compact: constraints.maxWidth < 380,
                    actions: [
                      AppVisualIconButton(
                        icon: Icons.sync_rounded,
                        onPressed: () => _refreshCards(ref),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _LibrarySummary(cards: values),
                const SizedBox(height: 24),
                AppVisualSectionTitle(
                  title: '我的牌组',
                  subtitle:
                      '${CardsPage._groupCards(values).length} 个牌组 · ${values.length} 张卡片',
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
                    (entry) => _DeckTile(folder: entry.key, cards: entry.value),
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
  bool? _dueOnly;
  _CardSort _sort = _CardSort.due;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(cardsProvider);
    return Scaffold(
      backgroundColor: AppVisualColors.background,
      body: cards.when(
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                AppVisualTitle(
                  title: widget.folder,
                  subtitle: '牌组详情与复习卡片',
                  actions: [
                    AppVisualIconButton(
                      icon: Icons.delete_outline_rounded,
                      onPressed: () =>
                          _confirmDeleteDeck(cards.valueOrNull ?? const []),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _DeckHeader(folder: widget.folder, cards: all),
                const SizedBox(height: 14),
                _SearchBar(
                  controller: _searchController,
                  query: _query,
                  hasFilters: _type != null || _dueOnly != null,
                  onChanged: (value) => setState(() => _query = value),
                  onClear: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                  onFilter: _showFilterSheet,
                  onSort: _showSortSheet,
                ),
                const SizedBox(height: 16),
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
                      onDelete: () => _confirmDeleteCard(card),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _folderOf(CardModel card) =>
      card.folder.trim().isEmpty ? '未分类' : card.folder;

  bool get _hasFilters =>
      _query.trim().isNotEmpty || _type != null || _dueOnly != null;

  List<CardModel> _filtered(List<CardModel> values) {
    final query = _query.trim().toLowerCase();
    final result = values.where((card) {
      return (_type == null || card.type == _type) &&
          (_dueOnly == null || card.isDue == _dueOnly) &&
          (query.isEmpty ||
              card.question.toLowerCase().contains(query) ||
              card.tags.any((tag) => tag.toLowerCase().contains(query)));
    }).toList();
    result.sort(
      (left, right) => switch (_sort) {
        _CardSort.due => left.dueAt.compareTo(right.dueAt),
        _CardSort.recent => right.updatedAt.compareTo(left.updatedAt),
        _CardSort.reviews => right.reviews.compareTo(left.reviews),
        _CardSort.created => right.createdAt.compareTo(left.createdAt),
      },
    );
    return result;
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _type = null;
      _dueOnly = null;
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
    var selectedDue = _dueOnly;
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
                initialValue: selectedDue,
                decoration: const InputDecoration(labelText: '复习状态'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('全部状态')),
                  DropdownMenuItem(value: true, child: Text('仅到期')),
                  DropdownMenuItem(value: false, child: Text('未到期')),
                ],
                onChanged: (value) => setSheetState(() => selectedDue = value),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    setState(() {
                      _type = selectedType;
                      _dueOnly = selectedDue;
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

  Future<void> _showSortSheet() async {
    final selected = await showModalBottomSheet<_CardSort>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _CardSort.values
              .map(
                (sort) => ListTile(
                  leading: Icon(
                    sort == _sort
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(_sortLabel(sort)),
                  selected: sort == _sort,
                  onTap: () => Navigator.of(context).pop(sort),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _sort = selected);
  }

  String _sortLabel(_CardSort sort) => switch (sort) {
    _CardSort.due => '按下次复习时间',
    _CardSort.recent => '按最近更新',
    _CardSort.reviews => '按复习次数',
    _CardSort.created => '按创建时间',
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
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('卡片已删除，等待同步。')));
    }
  }

  Future<void> _confirmDeleteDeck(Iterable<CardModel> allCards) async {
    final count = allCards
        .where((card) => _folderOf(card) == widget.folder)
        .length;
    final confirmed = await _confirm(
      title: '删除整个牌组？',
      message: '将删除牌组中的 $count 张卡片，并在下次同步时同步删除。',
    );
    if (!confirmed || !mounted) return;
    final account = ref.read(currentAccountProvider);
    if (account == null) return;
    await ref
        .read(contentRepositoryProvider)
        .deleteDeck(accountId: account.id, folder: widget.folder);
    ref.invalidate(cardsProvider);
    ref.invalidate(pendingSyncProvider);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('牌组已删除，等待同步。')));
      context.pop();
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
  const _DeckTile({required this.folder, required this.cards});

  final String folder;
  final List<CardModel> cards;

  @override
  Widget build(BuildContext context) {
    final due = cards.where((card) => card.isDue).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: appCardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/cards/deck', extra: folder),
          borderRadius: BorderRadius.circular(20),
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
    final due = cards.where((card) => card.isDue).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppVisualColors.paleGreen,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffedf4eb)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.layers_rounded,
            color: AppVisualColors.green,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '$folder · ${cards.length} 张卡片',
              style: const TextStyle(
                color: AppVisualColors.ink,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '$due 待复习',
            style: const TextStyle(
              color: AppVisualColors.darkGreen,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
    required this.onSort,
  });

  final TextEditingController controller;
  final String query;
  final bool hasFilters;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onFilter;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: AppVisualColors.green,
            ),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    onPressed: onClear,
                    icon: const Icon(Icons.clear_rounded),
                  ),
            hintText: '搜索题干或标签',
            hintStyle: const TextStyle(
              color: AppVisualColors.muted,
              fontSize: 13,
            ),
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(17),
              borderSide: const BorderSide(color: Color(0xffe8eee9)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(17),
              borderSide: const BorderSide(
                color: AppVisualColors.green,
                width: 1.4,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      AppVisualIconButton(
        onPressed: onFilter,
        icon: hasFilters ? Icons.filter_alt_rounded : Icons.tune_rounded,
      ),
      const SizedBox(width: 6),
      AppVisualIconButton(onPressed: onSort, icon: Icons.sort_rounded),
    ],
  );
}

class _CardListItem extends StatelessWidget {
  const _CardListItem({required this.card, required this.onDelete});

  final CardModel card;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final statusColor = card.suspended
        ? AppVisualColors.muted
        : card.isDue
        ? AppVisualColors.amber
        : AppVisualColors.green;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0b000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 3,
          ),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(_typeIcon(card.type), color: statusColor, size: 18),
          ),
          title: Text(
            card.question,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppVisualColors.ink,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${card.isDue ? '待复习' : '未到期'} · ${card.reviews} 次复习',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppVisualColors.muted,
                fontSize: 11,
              ),
            ),
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') onDelete();
            },
            icon: const Icon(
              Icons.more_horiz_rounded,
              color: AppVisualColors.muted,
            ),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'delete', child: Text('删除卡片')),
            ],
          ),
          onTap: () => context.push('/cards/${card.id}'),
        ),
      ),
    );
  }

  IconData _typeIcon(CardType type) => switch (type) {
    CardType.single => Icons.radio_button_checked,
    CardType.multiple => Icons.check_box_outlined,
    CardType.trueFalse => Icons.rule,
    CardType.note => Icons.lightbulb_outline,
  };
}
