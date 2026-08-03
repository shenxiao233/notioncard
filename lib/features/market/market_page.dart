import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_providers.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/status_badge.dart';
import 'market_model.dart';

enum _MarketSort { newest, downloads, cards }

class MarketPage extends ConsumerStatefulWidget {
  const MarketPage({super.key});

  @override
  ConsumerState<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends ConsumerState<MarketPage> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _category;
  _MarketSort _sort = _MarketSort.newest;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(marketSearchProvider(_query));
    return Scaffold(
      appBar: AppBar(
        title: const Text('牌组市场'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(marketSearchProvider(_query)),
            tooltip: '刷新牌组',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: decks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          title: '市场加载失败',
          message: '请检查网络连接，稍后重试。',
          icon: Icons.cloud_off_outlined,
          action: FilledButton.icon(
            onPressed: () => ref.invalidate(marketSearchProvider(_query)),
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ),
        data: (values) {
          final categories =
              values.map((deck) => deck.category).toSet().toList()..sort();
          final filtered = values
              .where((deck) => _category == null || deck.category == _category)
              .toList();
          filtered.sort((left, right) {
            return switch (_sort) {
              _MarketSort.newest => right.updatedAt.compareTo(left.updatedAt),
              _MarketSort.downloads => right.downloads.compareTo(
                left.downloads,
              ),
              _MarketSort.cards => right.cardCount.compareTo(left.cardCount),
            };
          });
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(marketSearchProvider(_query));
              await ref.read(marketSearchProvider(_query).future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
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
                          hintText: '搜索牌组、作者或标签',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: () => _showFilterSheet(context, categories),
                      tooltip: '筛选和排序',
                      icon: Badge(
                        isLabelVisible:
                            _category != null || _sort != _MarketSort.newest,
                        child: const Icon(Icons.tune),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SectionHeader(
                  title: '公开牌组',
                  subtitle: _category == null
                      ? '${values.length} 个牌组'
                      : '${filtered.length} 个匹配牌组',
                  trailing: StatusBadge(
                    label: '下载后使用',
                    icon: Icons.download_outlined,
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
                    title: values.isEmpty ? '暂无公开牌组' : '当前条件没有牌组',
                    message: values.isEmpty
                        ? '连接服务器后，公开牌组会出现在这里。'
                        : '尝试清除搜索或调整分类。',
                    icon: Icons.storefront_outlined,
                    action: values.isEmpty || (!_hasFilter && _query.isEmpty)
                        ? null
                        : OutlinedButton.icon(
                            onPressed: _clearFilters,
                            icon: const Icon(Icons.filter_alt_off_outlined),
                            label: const Text('清除筛选'),
                          ),
                  )
                else
                  ...filtered.map((deck) => _DeckTile(deck: deck)),
              ],
            ),
          );
        },
      ),
    );
  }

  bool get _hasFilter => _category != null || _sort != _MarketSort.newest;

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _category = null;
      _sort = _MarketSort.newest;
    });
  }

  Future<void> _showFilterSheet(
    BuildContext context,
    List<String> categories,
  ) async {
    var selectedCategory = _category;
    var selectedSort = _sort;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('筛选和排序', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 18),
              DropdownButtonFormField<String?>(
                initialValue: selectedCategory,
                decoration: const InputDecoration(labelText: '分类'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('全部分类'),
                  ),
                  ...categories.map(
                    (category) => DropdownMenuItem<String?>(
                      value: category,
                      child: Text(category),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    setSheetState(() => selectedCategory = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<_MarketSort>(
                initialValue: selectedSort,
                decoration: const InputDecoration(labelText: '排序方式'),
                items: _MarketSort.values
                    .map(
                      (sort) => DropdownMenuItem<_MarketSort>(
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
                      _category = selectedCategory;
                      _sort = selectedSort;
                    });
                    Navigator.of(sheetContext).pop();
                  },
                  child: const Text('应用'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _sortLabel(_MarketSort sort) {
    return switch (sort) {
      _MarketSort.newest => '最近更新',
      _MarketSort.downloads => '下载量最高',
      _MarketSort.cards => '卡片数量最多',
    };
  }
}

class _DeckTile extends StatelessWidget {
  const _DeckTile({required this.deck});

  final MarketDeckModel deck;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => context.push('/market/deck/${deck.id}'),
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
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                deck.title.isEmpty ? '?' : deck.title.substring(0, 1),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: scheme.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deck.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (deck.subscribed) ...[
                    const SizedBox(height: 6),
                    StatusBadge(
                      label: '已订阅',
                      icon: Icons.bookmark_outline,
                      backgroundColor: scheme.primaryContainer,
                      foregroundColor: scheme.onPrimaryContainer,
                    ),
                  ],
                  const SizedBox(height: 5),
                  Text(
                    '${deck.author} · ${deck.category}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${deck.cardCount} 张卡片 · ${_compactNumber(deck.downloads)} 次下载 · v${deck.version}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '更新于 ${DateFormat('M月d日').format(deck.updatedAt.toLocal())}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
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

  String _compactNumber(int value) {
    if (value >= 10000) return '${(value / 10000).toStringAsFixed(1)}万';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
    return '$value';
  }
}
