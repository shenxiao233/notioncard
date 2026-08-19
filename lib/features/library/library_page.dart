import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_providers.dart';
import '../../core/models/document_model.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_visuals.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/resource_action_dialogs.dart';
import '../../core/widgets/swipe_action_tile.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({this.initialFolder, super.key});

  final String? initialFolder;

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _searchController = TextEditingController();
  String _query = '';
  late final String _folderFilter = widget.initialFolder?.trim() ?? '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(documentsProvider);
    return Scaffold(
      backgroundColor: AppVisualColors.background,
      body: SafeArea(
        bottom: false,
        child: documents.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppVisualColors.green),
          ),
          error: (error, _) => _LibraryError(onRetry: _refreshDocuments),
          data: (values) {
            final query = _query.trim().toLowerCase();
            final folder = _folderFilter.trim();
            final filtered =
                values.where((document) {
                  final matchesQuery =
                      query.isEmpty ||
                      document.title.toLowerCase().contains(query) ||
                      document.body.toLowerCase().contains(query) ||
                      document.folder.toLowerCase().contains(query);
                  final matchesFolder =
                      folder.isEmpty || document.folder.trim() == folder;
                  return matchesQuery && matchesFolder;
                }).toList()..sort(
                  (left, right) => right.updatedAt.compareTo(left.updatedAt),
                );
            return RefreshIndicator(
              onRefresh: _refreshDocuments,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  AppLayoutMetrics.bottomNavigationContentPadding + 28,
                ),
                children: [
                  _LibrarySearchField(
                    controller: _searchController,
                    query: _query,
                    onChanged: (value) => setState(() => _query = value),
                    onClear: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                  ),
                  const SizedBox(height: 16),
                  AppVisualSectionTitle(
                    title: folder.isEmpty ? '全部文档' : folder,
                    subtitle: folder.isEmpty
                        ? (_query.isEmpty
                              ? '${values.length} 篇文档'
                              : '匹配 ${filtered.length} 篇文档')
                        : (_query.isEmpty
                              ? '${filtered.length} 篇文档'
                              : '匹配 ${filtered.length} 篇文档'),
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
                      (document) => _DocumentItem(
                        document: document,
                        onRename: () => _renameDocument(document),
                        onDelete: () => _deleteDocument(document),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
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

  Future<void> _renameDocument(DocumentModel document) async {
    final title = await showRenameResourceDialog(
      context,
      title: '重命名文档',
      initialValue: document.title,
      hintText: '输入文档名称',
    );
    if (title == null || !mounted) return;
    try {
      await ref
          .read(contentRepositoryProvider)
          .renameDocument(document: document, title: title);
      ref.invalidate(documentsProvider);
      ref.invalidate(pendingSyncProvider);
      ref
          .read(syncControllerProvider.notifier)
          .scheduleSync(reason: 'document-rename');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('文档已重命名，等待同步。')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('重命名失败：$error')));
      }
    }
  }

  Future<void> _deleteDocument(DocumentModel document) async {
    final confirmed = await showDeleteResourceDialog(
      context,
      title: '删除这篇文档？',
      message: '删除后会从本地移除，并在下次同步时从其他设备删除。',
    );
    if (!confirmed || !mounted) return;
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('文档已删除，等待同步。')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }
}

class _DocumentItem extends StatelessWidget {
  const _DocumentItem({
    required this.document,
    required this.onRename,
    required this.onDelete,
  });

  final DocumentModel document;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => SwipeActionTile(
    margin: const EdgeInsets.only(bottom: 10),
    onTap: () => context.push('/library/document/${document.id}'),
    onRename: onRename,
    onDelete: onDelete,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppVisualColors.softGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.description_rounded,
              color: AppVisualColors.green,
              size: 21,
            ),
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
                  style: const TextStyle(
                    color: AppVisualColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${document.folder} · 更新于 ${DateFormat('M月d日').format(document.updatedAt.toLocal())}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppVisualColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, color: AppVisualColors.muted),
        ],
      ),
    ),
  );
}

class _LibrarySearchField extends StatelessWidget {
  const _LibrarySearchField({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => TextField(
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
      hintText: '搜索标题、文件夹或正文',
      hintStyle: const TextStyle(color: AppVisualColors.muted, fontSize: 13),
      fillColor: Colors.white,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: Color(0xffe8eee9)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: AppVisualColors.green, width: 1.4),
      ),
    ),
  );
}

class _LibraryError extends StatelessWidget {
  const _LibraryError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: EmptyState(
      title: '文档加载失败',
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
