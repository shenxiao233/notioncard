import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/app_providers.dart';
import '../../core/models/card_model.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/app_brand.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/status_badge.dart';

enum _CardSort { due, recent, reviews, created }

class CardsPage extends ConsumerStatefulWidget {
  const CardsPage({super.key});

  @override
  ConsumerState<CardsPage> createState() => _CardsPageState();
}

class _CardsPageState extends ConsumerState<CardsPage> {
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
      body: cards.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          title: '卡片加载失败',
          message: '请检查网络或本地缓存，然后重试。',
          icon: Icons.cloud_off_outlined,
          action: FilledButton.icon(
            onPressed: () => _refreshCards(),
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ),
        data: (values) {
          final filtered = _filtered(values);
          return RefreshIndicator(
            onRefresh: _refreshCards,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 36),
              children: [
                const AppPageHeader(title: '卡片库', subtitle: '浏览、筛选并进入每一张复习卡片。'),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _query = value),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '清除搜索',
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _query = '');
                                  },
                                  icon: const Icon(Icons.clear),
                                ),
                          hintText: '搜索题干或牌组',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: () => _showFilterSheet(context),
                      tooltip: '筛选卡片',
                      icon: Badge(
                        isLabelVisible: _type != null || _dueOnly != null,
                        child: const Icon(Icons.tune),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _showSortSheet(context),
                      tooltip: '排序',
                      icon: const Icon(Icons.sort),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SectionHeader(
                  title: '全部卡片',
                  subtitle: _filterSummary(values.length, filtered.length),
                  trailing: StatusBadge(
                    label: '只读查看',
                    icon: Icons.visibility_outlined,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    foregroundColor: Theme.of(
                      context,
                    ).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 10),
                if (filtered.isEmpty)
                  EmptyState(
                    title: values.isEmpty ? '还没有本地卡片' : '当前筛选条件没有卡片',
                    message: values.isEmpty
                        ? '同步内容后，卡片会出现在这里。'
                        : '尝试清除搜索词或调整筛选条件。',
                    icon: Icons.style_outlined,
                    action: values.isEmpty || !_hasFilters
                        ? null
                        : OutlinedButton.icon(
                            onPressed: _clearFilters,
                            icon: const Icon(Icons.filter_alt_off_outlined),
                            label: const Text('清除筛选'),
                          ),
                  )
                else
                  ...filtered.map((card) => _CardListItem(card: card)),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _refreshCards() async {
    await ref
        .read(syncControllerProvider.notifier)
        .sync(reason: 'cards-refresh');
    if (!mounted) return;
    ref.invalidate(cardsProvider);
    await ref.read(cardsProvider.future);
  }

  bool get _hasFilters =>
      _query.trim().isNotEmpty || _type != null || _dueOnly != null;

  List<CardModel> _filtered(List<CardModel> values) {
    final query = _query.trim().toLowerCase();
    final result = values.where((card) {
      return (_type == null || card.type == _type) &&
          (_dueOnly == null || card.isDue == _dueOnly) &&
          (query.isEmpty ||
              card.question.toLowerCase().contains(query) ||
              card.folder.toLowerCase().contains(query) ||
              card.tags.any((tag) => tag.toLowerCase().contains(query)));
    }).toList();
    result.sort((left, right) {
      return switch (_sort) {
        _CardSort.due => left.dueAt.compareTo(right.dueAt),
        _CardSort.recent => right.updatedAt.compareTo(left.updatedAt),
        _CardSort.reviews => right.reviews.compareTo(left.reviews),
        _CardSort.created => right.createdAt.compareTo(left.createdAt),
      };
    });
    return result;
  }

  String _filterSummary(int total, int visible) {
    final parts = <String>[];
    if (_type != null) parts.add(_type!.label);
    if (_dueOnly == true) parts.add('到期');
    if (_dueOnly == false) parts.add('未到期');
    if (_query.trim().isNotEmpty) parts.add('搜索结果');
    return parts.isEmpty ? '$total 张卡片' : '${parts.join(' · ')} · $visible 张';
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _type = null;
      _dueOnly = null;
    });
  }

  Future<void> _showFilterSheet(BuildContext context) async {
    var selectedType = _type;
    var selectedDue = _dueOnly;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('筛选卡片', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 18),
              DropdownButtonFormField<CardType?>(
                initialValue: selectedType,
                decoration: const InputDecoration(labelText: '卡片类型'),
                items: [
                  const DropdownMenuItem<CardType?>(
                    value: null,
                    child: Text('全部类型'),
                  ),
                  ...CardType.values.map(
                    (type) => DropdownMenuItem<CardType?>(
                      value: type,
                      child: Text(type.label),
                    ),
                  ),
                ],
                onChanged: (value) => setSheetState(() => selectedType = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<bool?>(
                initialValue: selectedDue,
                decoration: const InputDecoration(labelText: '复习状态'),
                items: const [
                  DropdownMenuItem<bool?>(value: null, child: Text('全部状态')),
                  DropdownMenuItem<bool?>(value: true, child: Text('仅到期')),
                  DropdownMenuItem<bool?>(value: false, child: Text('未到期')),
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

  Future<void> _showSortSheet(BuildContext context) async {
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
                    color: sort == _sort
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
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

  String _sortLabel(_CardSort sort) {
    return switch (sort) {
      _CardSort.due => '按下次复习时间',
      _CardSort.recent => '按最近更新',
      _CardSort.reviews => '按复习次数',
      _CardSort.created => '按创建时间',
    };
  }
}

class _CardListItem extends StatelessWidget {
  const _CardListItem({required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = card.suspended
        ? scheme.onSurfaceVariant
        : card.isDue
        ? scheme.secondary
        : scheme.primary;
    return InkWell(
      onTap: () => context.push('/cards/${card.id}'),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outline)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_typeIcon(card.type), color: statusColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StatusBadge(
                        label: card.type.label,
                        icon: _typeIcon(card.type),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          card.isDue
                              ? '到期'
                              : card.suspended
                              ? '已暂停'
                              : '未到期',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    card.question,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${card.folder} · ${card.mastery.isEmpty ? '未复习' : card.mastery} · ${card.reviews} 次复习',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (card.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      card.tags.map((tag) => '#$tag').join('  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: scheme.primary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  IconData _typeIcon(CardType type) {
    return switch (type) {
      CardType.single => Icons.radio_button_checked,
      CardType.multiple => Icons.check_box_outlined,
      CardType.trueFalse => Icons.rule,
      CardType.note => Icons.lightbulb_outline,
    };
  }
}
