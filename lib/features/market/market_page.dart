import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_providers.dart';
import '../../core/widgets/app_visuals.dart';
import '../../core/widgets/empty_state.dart';
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
      backgroundColor: AppVisualColors.background,
      body: SafeArea(
        bottom: false,
        child: decks.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppVisualColors.green),
          ),
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
                .where(
                  (deck) => _category == null || deck.category == _category,
                )
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
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  _MarketSearchBar(
                    controller: _searchController,
                    query: _query,
                    hasFilter: _category != null || _sort != _MarketSort.newest,
                    onChanged: (value) => setState(() => _query = value),
                    onClear: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    onFilter: () => _showFilterSheet(context, categories),
                  ),
                  const SizedBox(height: 16),
                  AppVisualSectionTitle(
                    title: '公开牌组',
                    subtitle: _category == null
                        ? '${values.length} 个牌组'
                        : '${filtered.length} 个匹配牌组',
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: appCardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/market/deck/${deck.id}'),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppVisualColors.softGreen,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    deck.title.isEmpty ? '?' : deck.title.substring(0, 1),
                    style: const TextStyle(
                      color: AppVisualColors.green,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              deck.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppVisualColors.ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                            ),
                          ),
                          if (deck.subscribed) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.bookmark_rounded,
                              color: AppVisualColors.green,
                              size: 17,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${deck.author} · ${deck.category}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppVisualColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${deck.cardCount} 张卡片 · ${_compactNumber(deck.downloads)} 次下载 · v${deck.version}',
                        style: const TextStyle(
                          color: AppVisualColors.darkGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '更新于 ${DateFormat('M月d日').format(deck.updatedAt.toLocal())}',
                        style: const TextStyle(
                          color: AppVisualColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
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

  String _compactNumber(int value) {
    if (value >= 10000) return '${(value / 10000).toStringAsFixed(1)}万';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
    return '$value';
  }
}

class _MarketSearchBar extends StatelessWidget {
  const _MarketSearchBar({
    required this.controller,
    required this.query,
    required this.hasFilter,
    required this.onChanged,
    required this.onClear,
    required this.onFilter,
  });

  final TextEditingController controller;
  final String query;
  final bool hasFilter;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onFilter;

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
                    tooltip: '清除搜索',
                    onPressed: onClear,
                    icon: const Icon(Icons.clear_rounded),
                  ),
            hintText: '搜索牌组、作者或标签',
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
        icon: hasFilter ? Icons.filter_alt_rounded : Icons.tune_rounded,
      ),
    ],
  );
}
