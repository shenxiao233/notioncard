import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_providers.dart';
import '../../core/models/document_model.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/app_brand.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/status_badge.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(documentsProvider);
    return Scaffold(
      body: documents.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          title: '文档加载失败',
          message: '请检查网络或本地缓存，然后重试。',
          icon: Icons.cloud_off_outlined,
          action: FilledButton.icon(
            onPressed: () => _refreshDocuments(),
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ),
        data: (values) {
          final query = _query.trim().toLowerCase();
          final filtered =
              values.where((document) {
                return query.isEmpty ||
                    document.title.toLowerCase().contains(query) ||
                    document.body.toLowerCase().contains(query) ||
                    document.folder.toLowerCase().contains(query);
              }).toList()..sort(
                (left, right) => right.updatedAt.compareTo(left.updatedAt),
              );
          return RefreshIndicator(
            onRefresh: _refreshDocuments,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 36),
              children: [
                const AppPageHeader(title: '知识库', subtitle: '只读浏览你的文档与学习资料。'),
                const SizedBox(height: 24),
                TextField(
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
                    hintText: '搜索标题、文件夹或正文',
                  ),
                ),
                const SizedBox(height: 22),
                SectionHeader(
                  title: '全部文档',
                  subtitle: _query.isEmpty
                      ? '${values.length} 篇文档'
                      : '匹配 ${filtered.length} 篇文档',
                  trailing: StatusBadge(
                    label: '只读阅读',
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
                    title: values.isEmpty ? '还没有同步文档' : '当前筛选条件没有文档',
                    message: values.isEmpty
                        ? '完成首次同步后，已缓存的文档会出现在这里。'
                        : '尝试修改搜索词，或清除当前搜索条件。',
                    icon: Icons.menu_book_outlined,
                    action: values.isEmpty || _query.isEmpty
                        ? null
                        : OutlinedButton.icon(
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.clear),
                            label: const Text('清除搜索'),
                          ),
                  )
                else
                  ...filtered.map(
                    (document) => _DocumentItem(document: document),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _refreshDocuments() async {
    await ref
        .read(syncControllerProvider.notifier)
        .sync(reason: 'library-refresh');
    if (!mounted) return;
    ref.invalidate(documentsProvider);
    await ref.read(documentsProvider.future);
  }
}

class _DocumentItem extends StatelessWidget {
  const _DocumentItem({required this.document});

  final DocumentModel document;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => context.push('/library/document/${document.id}'),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outline)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.description_outlined, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${document.folder} · 更新于 ${DateFormat('M月d日').format(document.updatedAt.toLocal())}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
