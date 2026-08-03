import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_providers.dart';
import '../../core/models/document_model.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/markdown_content.dart';
import '../../core/widgets/status_badge.dart';

class DocumentDetailPage extends ConsumerWidget {
  const DocumentDetailPage({required this.documentId, super.key});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documents = ref.watch(documentsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('文档阅读'),
        actions: [
          IconButton(
            onPressed: () => _refreshDocument(ref),
            tooltip: '刷新文档',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: documents.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          title: '文档加载失败',
          message: '请检查网络或本地缓存，然后重试。',
          icon: Icons.cloud_off_outlined,
          action: FilledButton.icon(
            onPressed: () => _refreshDocument(ref),
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ),
        data: (values) {
          DocumentModel? document;
          for (final value in values) {
            if (value.id == documentId) document = value;
          }
          if (document == null) {
            return const EmptyState(
              title: '文档不存在',
              message: '它可能尚未同步，或已经从当前账户移除。',
              icon: Icons.find_in_page_outlined,
            );
          }
          return _DocumentReader(document: document);
        },
      ),
    );
  }

  Future<void> _refreshDocument(WidgetRef ref) async {
    await ref
        .read(syncControllerProvider.notifier)
        .sync(reason: 'document-refresh');
    ref.invalidate(documentsProvider);
    await ref.read(documentsProvider.future);
  }
}

class _DocumentReader extends StatelessWidget {
  const _DocumentReader({required this.document});

  final DocumentModel document;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
        children: [
          Text(document.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusBadge(label: document.folder, icon: Icons.folder_outlined),
              StatusBadge(
                label:
                    '更新于 ${DateFormat('yyyy年M月d日').format(document.updatedAt.toLocal())}',
                icon: Icons.update_outlined,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Divider(color: scheme.outline),
          const SizedBox(height: 18),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: MarkdownContent(
              data: document.body,
              onTapLink: (text, href, title) => _showLink(context, href),
            ),
          ),
        ],
      ),
    );
  }

  void _showLink(BuildContext context, String? href) {
    if (href == null ||
        !(href.startsWith('https://') || href.startsWith('http://'))) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('外部链接：$href')));
  }
}
