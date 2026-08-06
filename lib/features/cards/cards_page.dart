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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
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
                        _dueOnly != null ||
                        _sort != _CardSort.due,
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
                      message: all.isEmpty
                          ? '可以从桌面端同步卡片到这里。'
                          : '尝试清除搜索或筛选条件。',
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
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '新增卡片',
        onPressed: _showAddCardSheet,
        backgroundColor: AppVisualColors.green,
        foregroundColor: Colors.white,
        elevation: 5,
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  String _folderOf(CardModel card) =>
      card.folder.trim().isEmpty ? '未分类' : card.folder;

  bool get _hasFilters =>
      _query.trim().isNotEmpty ||
      _type != null ||
      _dueOnly != null ||
      _sort != _CardSort.due;

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
      _sort = _CardSort.due;
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
    var selectedSort = _sort;
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
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    setState(() {
                      _type = selectedType;
                      _dueOnly = selectedDue;
                      _sort = selectedSort;
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

  Future<void> _showAddCardSheet() async {
    final draft = await showModalBottomSheet<_NewCardDraft>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _AddCardSheet(),
    );
    if (draft == null || !mounted) return;

    final account = ref.read(currentAccountProvider);
    if (account == null) return;
    final now = DateTime.now();
    final card = CardModel(
      id: 'local-card-${now.microsecondsSinceEpoch}',
      accountId: account.id,
      type: CardType.note,
      folder: widget.folder == '未分类' ? '' : widget.folder,
      question: draft.question,
      options: const {},
      answer: const [],
      noteContent: draft.noteContent,
      explanation: '',
      tags: const [],
      dueAt: now,
      createdAt: now,
      updatedAt: now,
      reviews: 0,
      mastery: '',
      suspended: false,
      fsrs: FsrsSnapshot(
        state: FsrsState.newCard,
        dueAt: now,
        stability: 0,
        difficulty: 5,
        reps: 0,
        lapses: 0,
      ),
    );

    try {
      await ref.read(contentRepositoryProvider).createCard(card);
      ref.invalidate(cardsProvider);
      ref.invalidate(pendingSyncProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('卡片已添加，等待同步。')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加卡片失败：$error')),
        );
      }
    }
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                _titleSpan,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 5),
              Text(
                '${cards.length} 张卡片',
                style: const TextStyle(
                  color: AppVisualColors.muted,
                  fontSize: 14,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          margin: const EdgeInsets.only(top: 3),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: AppVisualColors.softGreen,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            '$due 待复习',
            style: const TextStyle(
              color: AppVisualColors.darkGreen,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
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
          fontSize: 24,
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
        fontSize: 24,
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
    height: 58,
    padding: const EdgeInsets.only(left: 16, right: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(29),
      border: Border.all(color: const Color(0xffe8eee9)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0b000000),
          blurRadius: 14,
          offset: Offset(0, 5),
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
            cursorColor: AppVisualColors.green,
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
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
        ),
      ],
    ),
  );
}

class _CardListItem extends StatelessWidget {
  const _CardListItem({required this.card, required this.onDelete});

  final CardModel card;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0b000000),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/cards/${card.id}'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 112),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: AppVisualColors.softGreen,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lightbulb_outline_rounded,
                      color: AppVisualColors.green,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.question,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppVisualColors.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          '${card.isDue ? '待复习' : '未到期'} · ${card.reviews} 次复习',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppVisualColors.muted,
                            fontSize: 13,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '更多操作',
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewCardDraft {
  const _NewCardDraft({required this.question, required this.noteContent});

  final String question;
  final String noteContent;
}

class _AddCardSheet extends StatefulWidget {
  const _AddCardSheet();

  @override
  State<_AddCardSheet> createState() => _AddCardSheetState();
}

class _AddCardSheetState extends State<_AddCardSheet> {
  final _questionController = TextEditingController();
  final _noteController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _questionController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    final question = _questionController.text.trim();
    if (question.isEmpty) {
      setState(() => _error = '请输入题干或词条');
      return;
    }
    Navigator.of(context).pop(
      _NewCardDraft(
        question: question,
        noteContent: _noteController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '新增卡片',
                style: TextStyle(
                  color: AppVisualColors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                '保存后会加入当前牌组，并在下次同步时上传。',
                style: TextStyle(
                  color: AppVisualColors.muted,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _questionController,
                autofocus: true,
                maxLines: 2,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '题干或词条',
                  hintText: '例如：什么是间隔重复？',
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: '内容（可选）',
                  hintText: '补充答案、解释或记忆提示',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xffb3261e),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.add_rounded, size: 19),
                  label: const Text('添加卡片'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
