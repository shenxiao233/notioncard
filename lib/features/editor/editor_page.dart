import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_providers.dart';
import '../../core/models/card_model.dart';
import '../../core/models/collection_model.dart';
import '../../core/models/document_model.dart';
import '../../core/widgets/app_visuals.dart';
import '../cards/card_editor_page.dart';
import '../collections/collection_actions.dart';

/// Opens the editor on its own route.
///
/// The fallback keeps this helper usable in lightweight widget tests that do
/// not install a GoRouter. The real app always uses the standalone `/edit`
/// route, which also hides the bottom navigation while editing.
Future<void> showEditorSheet(BuildContext context) async {
  final router = GoRouter.maybeOf(context);
  if (router != null) {
    await router.push('/edit');
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (_) => const _EditorSheet(),
  );
}

/// The entry page for creating new content.
///
/// Keep this page deliberately small: it is only responsible for choosing
/// between a card and a document. The actual forms live on their own routes.
class EditorPage extends StatelessWidget {
  const EditorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('新建内容'),
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '选择编辑类型',
                style: TextStyle(
                  color: AppVisualColors.ink,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '选择合适的内容类型，开始创建',
                style: TextStyle(
                  color: AppVisualColors.muted,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 42),
              _EditorTypeCard(
                title: '卡片',
                description: '适合知识点、单词、公式、问答等内容；用于快速学习与复习。',
                onTap: () => context.push('/edit/card'),
              ),
              const SizedBox(height: 16),
              _EditorTypeCard(
                title: '文档',
                description: '适合笔记、教材、资料、长篇内容；用于整理完整知识体系。',
                onTap: () => context.push('/edit/document'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorTypeCard extends StatelessWidget {
  const _EditorTypeCard({
    required this.title,
    required this.description,
    required this.onTap,
  });

  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 20, 18, 20),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xffe3e7e4)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppVisualColors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      description,
                      style: const TextStyle(
                        color: AppVisualColors.muted,
                        fontSize: 14,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                '>',
                style: TextStyle(
                  color: AppVisualColors.muted,
                  fontSize: 24,
                  fontWeight: FontWeight.w400,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorSheet extends StatefulWidget {
  const _EditorSheet();

  @override
  State<_EditorSheet> createState() => _EditorSheetState();
}

class _EditorSheetState extends State<_EditorSheet> {
  bool? _document;
  String? _selectedFolder;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final availableHeight =
        mediaQuery.size.height - mediaQuery.viewInsets.bottom;
    final maxHeight = availableHeight * 0.92;

    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Material(
            color: AppVisualColors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            clipBehavior: Clip.antiAlias,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              reverseDuration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _document == null
                  ? _EditorTypeSheet(
                      key: const ValueKey('editor-type-sheet'),
                      onSelect: (document) => setState(() {
                        _document = document;
                        _selectedFolder = null;
                      }),
                    )
                  : !_document!
                  ? CardEditorPage(
                      key: const ValueKey('editor-card-form'),
                      onBack: () => setState(() => _document = null),
                      onClose: () => Navigator.of(context).pop(),
                    )
                  : _selectedFolder == null
                  ? DocumentFolderPickerPage(
                      key: const ValueKey('document-folder-picker'),
                      onBack: () => setState(() => _document = null),
                      onClose: () => Navigator.of(context).pop(),
                      onSelect: (folder) =>
                          setState(() => _selectedFolder = folder),
                    )
                  : DocumentEditorPage(
                      key: ValueKey('document-editor-$_selectedFolder'),
                      selectedFolder: _selectedFolder!,
                      onBack: () => setState(() => _selectedFolder = null),
                      onClose: () => Navigator.of(context).pop(),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorTypeSheet extends StatelessWidget {
  const _EditorTypeSheet({required this.onSelect, super.key});

  final ValueChanged<bool> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '选择编辑类型',
                    style: TextStyle(
                      color: AppVisualColors.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '关闭编辑',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '选择合适的内容类型，开始创建',
              style: TextStyle(
                color: AppVisualColors.muted,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 22),
            _EditorTypeCard(
              title: '卡片',
              description: '适合知识点、单词、公式、问答等内容；用于快速学习与复习。',
              onTap: () => onSelect(false),
            ),
            const SizedBox(height: 12),
            _EditorTypeCard(
              title: '文档',
              description: '适合笔记、教材、资料、长篇内容；用于整理完整知识体系。',
              onTap: () => onSelect(true),
            ),
          ],
        ),
      ),
    );
  }
}

/// The first step of the document flow. A document is always created inside
/// a knowledge base, so the destination is chosen before the editor opens.
class DocumentFolderPickerPage extends ConsumerWidget {
  const DocumentFolderPickerPage({
    this.onSelect,
    this.onBack,
    this.onClose,
    super.key,
  });

  final ValueChanged<String>? onSelect;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documents = ref.watch(documentsProvider);
    final cards = ref.watch(cardsProvider);
    final collections = ref.watch(collectionsProvider);

    return Scaffold(
      backgroundColor: AppVisualColors.background,
      appBar: AppBar(
        title: const Text('选择知识库'),
        backgroundColor: AppVisualColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: onBack == null ? '返回' : '返回编辑类型',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: onBack ?? () => Navigator.of(context).maybePop(),
        ),
        actions: [
          if (onClose != null)
            IconButton(
              tooltip: '关闭编辑',
              icon: const Icon(Icons.close_rounded),
              onPressed: onClose,
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _buildPickerBody(context, ref, documents, cards, collections),
      ),
    );
  }

  Widget _buildPickerBody(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<DocumentModel>> documents,
    AsyncValue<List<CardModel>> cards,
    AsyncValue<List<CollectionModel>> collections,
  ) {
    if (documents.isLoading || cards.isLoading || collections.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppVisualColors.green),
      );
    }

    if (documents.hasError || cards.hasError || collections.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 42,
                color: AppVisualColors.muted,
              ),
              const SizedBox(height: 12),
              const Text(
                '知识库暂时无法加载',
                style: TextStyle(
                  color: AppVisualColors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '请稍后重试，或先完成一次同步。',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppVisualColors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final summaries = _buildKnowledgeBaseSummaries(
      documents.valueOrNull ?? const <DocumentModel>[],
      cards.valueOrNull ?? const <CardModel>[],
      collections.valueOrNull ?? const <CollectionModel>[],
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 16),
          child: Text(
            '选择一个知识库，文档会自动归入这里。',
            style: TextStyle(
              color: AppVisualColors.muted,
              fontSize: 14,
              height: 1.35,
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _createDocumentCategory(context, ref),
          icon: const Icon(Icons.create_new_folder_outlined, size: 19),
          label: const Text('新建文档类别'),
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            foregroundColor: AppVisualColors.darkGreen,
            side: const BorderSide(color: AppVisualColors.line),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          ),
        ),
        const SizedBox(height: 14),
        ...summaries.map(
          (summary) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _KnowledgeBaseTile(
              summary: summary,
              onTap: () => _selectFolder(context, summary.folder),
            ),
          ),
        ),
      ],
    );
  }

  void _selectFolder(BuildContext context, String folder) {
    if (onSelect != null) {
      onSelect!(folder);
      return;
    }
    context.push('/edit/document/editor', extra: folder);
  }

  Future<void> _createDocumentCategory(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final created = await createCollectionFromSheet(
      context,
      ref,
      type: CollectionType.documentCategory,
    );
    if (created != null && context.mounted) {
      _selectFolder(context, created.name);
    }
  }
}

class _KnowledgeBaseSummary {
  const _KnowledgeBaseSummary({
    required this.folder,
    required this.documentCount,
    required this.cardCount,
    required this.latestUpdatedAt,
  });

  final String folder;
  final int documentCount;
  final int cardCount;
  final DateTime? latestUpdatedAt;

  String get label => _folderLabel(folder);
}

List<_KnowledgeBaseSummary> _buildKnowledgeBaseSummaries(
  List<DocumentModel> documents,
  List<CardModel> cards,
  List<CollectionModel> collections,
) {
  final folders = <String>{''};
  folders.addAll(
    documents
        .map((document) => document.folder.trim())
        .where((folder) => folder.isNotEmpty),
  );
  folders.addAll(
    collections
        .where(
          (collection) =>
              collection.type == CollectionType.documentCategory &&
              !collection.archived,
        )
        .map((collection) => collection.name.trim())
        .where((folder) => folder.isNotEmpty),
  );

  final summaries = folders.map((folder) {
    final folderDocuments = documents.where(
      (document) => document.folder.trim() == folder,
    );
    final folderCards = cards.where((card) => card.folder.trim() == folder);
    final dates = <DateTime>[
      ...folderDocuments.map((document) => document.updatedAt),
      ...folderCards.map((card) => card.updatedAt),
    ];
    dates.sort();

    return _KnowledgeBaseSummary(
      folder: folder,
      documentCount: folderDocuments.length,
      cardCount: folderCards.length,
      latestUpdatedAt: dates.isEmpty ? null : dates.last,
    );
  }).toList();

  summaries.sort((left, right) {
    if (left.folder.isEmpty && right.folder.isNotEmpty) return -1;
    if (right.folder.isEmpty && left.folder.isNotEmpty) return 1;
    final leftDate = left.latestUpdatedAt;
    final rightDate = right.latestUpdatedAt;
    if (leftDate != null && rightDate != null) {
      final byDate = rightDate.compareTo(leftDate);
      if (byDate != 0) return byDate;
    } else if (leftDate != null) {
      return -1;
    } else if (rightDate != null) {
      return 1;
    }
    return left.label.compareTo(right.label);
  });

  return summaries;
}

String _folderLabel(String folder) {
  final value = folder.trim();
  return value.isEmpty ? '默认知识库' : value;
}

class _KnowledgeBaseTile extends StatelessWidget {
  const _KnowledgeBaseTile({required this.summary, required this.onTap});

  final _KnowledgeBaseSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final documentLabel = summary.documentCount == 0
        ? '暂无文档'
        : '${summary.documentCount} 篇文档';
    final cardLabel = summary.cardCount == 0
        ? null
        : '${summary.cardCount} 张卡片';
    final counts = cardLabel == null
        ? documentLabel
        : '$documentLabel · $cardLabel';
    final updated = summary.latestUpdatedAt == null
        ? '尚未更新'
        : '最近更新 ${DateFormat('M月d日 HH:mm').format(summary.latestUpdatedAt!.toLocal())}';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 48, 18),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppVisualColors.softGreen,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.folder_rounded,
                      color: AppVisualColors.green,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppVisualColors.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          counts,
                          style: const TextStyle(
                            color: AppVisualColors.muted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          updated,
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
            Positioned(
              top: 0,
              right: 0,
              child: ClipPath(
                clipper: _TopRightTriangleClipper(),
                child: Container(
                  width: 45,
                  height: 45,
                  color: AppVisualColors.softGreen,
                  alignment: Alignment.topRight,
                  padding: const EdgeInsets.only(top: 7, right: 7),
                  child: const Icon(
                    Icons.north_east_rounded,
                    color: AppVisualColors.green,
                    size: 14,
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

class _TopRightTriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// A focused, distraction-free editor used after the destination is chosen.
class DocumentEditorPage extends ConsumerStatefulWidget {
  const DocumentEditorPage({
    required this.selectedFolder,
    this.onBack,
    this.onClose,
    super.key,
  });

  final String selectedFolder;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  @override
  ConsumerState<DocumentEditorPage> createState() => _DocumentEditorPageState();
}

class _DocumentEditorPageState extends ConsumerState<DocumentEditorPage> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _history = <_DocumentDraft>[const _DocumentDraft.empty()];
  int _historyIndex = 0;
  String? _error;
  bool _saving = false;
  bool _restoringDraft = false;

  bool get _canUndo => _historyIndex > 0;
  bool get _canRedo => _historyIndex < _history.length - 1;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_recordDraft);
    _bodyController.addListener(_recordDraft);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.onBack == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && widget.onBack != null) widget.onBack!();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              _DocumentEditorToolbar(
                onBack: _goBack,
                onSave: _save,
                onUndo: _canUndo ? _undo : null,
                onRedo: _canRedo ? _redo : null,
                onOutline: _showOutline,
                saving: _saving,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppVisualColors.softGreen,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.folder_outlined,
                            size: 15,
                            color: AppVisualColors.darkGreen,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _folderLabel(widget.selectedFolder),
                            style: const TextStyle(
                              color: AppVisualColors.darkGreen,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
                  children: [
                    TextField(
                      controller: _titleController,
                      maxLines: 4,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: _clearError,
                      style: const TextStyle(
                        color: AppVisualColors.ink,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        height: 1.18,
                      ),
                      decoration: const InputDecoration(
                        hintText: '无标题文档',
                        hintStyle: TextStyle(
                          color: Color(0xffaeb8b1),
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          height: 1.18,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Divider(height: 1, color: AppVisualColors.line),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _bodyController,
                      maxLines: null,
                      minLines: 14,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      onChanged: _clearError,
                      style: const TextStyle(
                        color: AppVisualColors.ink,
                        fontSize: 17,
                        height: 1.65,
                      ),
                      decoration: const InputDecoration(
                        hintText: '请输入正文',
                        hintStyle: TextStyle(
                          color: Color(0xffaeb8b1),
                          fontSize: 17,
                          height: 1.65,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        alignLabelWithHint: true,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _ErrorText(_error!),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _goBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _recordDraft() {
    if (_restoringDraft) return;
    final draft = _DocumentDraft(
      title: _titleController.text,
      body: _bodyController.text,
    );
    if (draft == _history[_historyIndex]) return;
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(draft);
    _historyIndex = _history.length - 1;
    if (_history.length > 100) {
      _history.removeAt(0);
      _historyIndex--;
    }
    if (mounted) setState(() {});
  }

  void _restoreDraft(_DocumentDraft draft) {
    _restoringDraft = true;
    _titleController.value = TextEditingValue(
      text: draft.title,
      selection: TextSelection.collapsed(offset: draft.title.length),
    );
    _bodyController.value = TextEditingValue(
      text: draft.body,
      selection: TextSelection.collapsed(offset: draft.body.length),
    );
    _restoringDraft = false;
    setState(() {});
  }

  void _undo() {
    if (!_canUndo) return;
    _historyIndex--;
    _restoreDraft(_history[_historyIndex]);
  }

  void _redo() {
    if (!_canRedo) return;
    _historyIndex++;
    _restoreDraft(_history[_historyIndex]);
  }

  void _clearError(String _) {
    if (_error != null) setState(() => _error = null);
  }

  void _showOutline() {
    final title = _titleController.text.trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(title.isEmpty ? '填写标题后，这里会显示文档目录。' : '目录功能将在文档内容中自动生成。'),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;

    final title = _titleController.text.trim().isEmpty
        ? '无标题文档'
        : _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (body.isEmpty) {
      setState(() => _error = '请输入正文');
      return;
    }

    final account = ref.read(currentAccountProvider);
    if (account == null) {
      setState(() => _error = '当前没有登录账号');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref
          .read(contentRepositoryProvider)
          .createDocument(
            accountId: account.id,
            title: title,
            body: body,
            folder: widget.selectedFolder,
          );
      ref.invalidate(documentsProvider);
      ref.invalidate(collectionsProvider);
      ref.invalidate(pendingSyncProvider);
      ref
          .read(syncControllerProvider.notifier)
          .scheduleSync(reason: 'editor-document-create');

      if (!mounted) return;
      _restoringDraft = true;
      _titleController.clear();
      _bodyController.clear();
      _restoringDraft = false;
      _history
        ..clear()
        ..add(const _DocumentDraft.empty());
      _historyIndex = 0;
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('文档已保存，等待同步')));
    } catch (error) {
      if (mounted) setState(() => _error = '保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _DocumentDraft {
  const _DocumentDraft({required this.title, required this.body});

  const _DocumentDraft.empty() : title = '', body = '';

  final String title;
  final String body;

  @override
  bool operator ==(Object other) {
    return other is _DocumentDraft &&
        other.title == title &&
        other.body == body;
  }

  @override
  int get hashCode => Object.hash(title, body);
}

class _DocumentEditorToolbar extends StatelessWidget {
  const _DocumentEditorToolbar({
    required this.onBack,
    required this.onSave,
    required this.onUndo,
    required this.onRedo,
    required this.onOutline,
    required this.saving,
  });

  final VoidCallback onBack;
  final VoidCallback onSave;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback onOutline;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 3),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回选择知识库',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: onBack,
          ),
          Tooltip(
            message: '保存文档',
            child: Material(
              color: AppVisualColors.green,
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                onTap: saving ? null : onSave,
                borderRadius: BorderRadius.circular(13),
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Center(
                    child: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: '撤销',
                  onPressed: onUndo,
                  icon: const Icon(Icons.undo_rounded),
                ),
                IconButton(
                  tooltip: '重做',
                  onPressed: onRedo,
                  icon: const Icon(Icons.redo_rounded),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '文档目录',
            icon: const Icon(Icons.format_list_bulleted_rounded),
            onPressed: onOutline,
          ),
        ],
      ),
    );
  }
}

/// Shared form page used by the card and document creation routes.
class EditorFormPage extends ConsumerStatefulWidget {
  const EditorFormPage({
    required this.document,
    this.onBack,
    this.onClose,
    super.key,
  });

  final bool document;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  @override
  ConsumerState<EditorFormPage> createState() => _EditorFormPageState();
}

class _EditorFormPageState extends ConsumerState<EditorFormPage> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  String? _folder;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(cardsProvider).valueOrNull ?? const <CardModel>[];
    final documents =
        ref.watch(documentsProvider).valueOrNull ?? const <DocumentModel>[];
    final collections =
        ref.watch(collectionsProvider).valueOrNull ?? const <CollectionModel>[];
    final folders = <String>{
      ...cards
          .map((card) => card.folder.trim())
          .where((folder) => folder.isNotEmpty),
      ...documents
          .map((document) => document.folder.trim())
          .where((folder) => folder.isNotEmpty),
      ...collections
          .where(
            (collection) =>
                collection.type ==
                    (widget.document
                        ? CollectionType.documentCategory
                        : CollectionType.deck) &&
                !collection.archived,
          )
          .map((collection) => collection.name.trim())
          .where((folder) => folder.isNotEmpty),
    };
    final folderValues = folders.toList()..sort();
    final selectedFolder = folderValues.contains(_folder) ? _folder : null;

    return Scaffold(
      backgroundColor: AppVisualColors.background,
      appBar: AppBar(
        title: Text(widget.document ? '新建文档' : '新建卡片'),
        centerTitle: false,
        backgroundColor: AppVisualColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: widget.onBack == null ? '返回' : '返回类型选择',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
        ),
        actions: [
          if (widget.onClose != null)
            IconButton(
              tooltip: '关闭编辑',
              icon: const Icon(Icons.close_rounded),
              onPressed: widget.onClose,
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _EditorCard(
              title: widget.document ? '新建文档' : '新建速记卡片',
              subtitle: widget.document
                  ? '支持 Markdown，适合整理完整的学习笔记和资料。'
                  : '适合记录一个词条、概念或需要反复记忆的内容。',
              children: [
                TextField(
                  controller: _titleController,
                  maxLines: widget.document ? 1 : 2,
                  textInputAction: TextInputAction.next,
                  onChanged: _clearError,
                  decoration: InputDecoration(
                    labelText: widget.document ? '文档标题' : '卡片正面',
                    hintText: widget.document
                        ? '例如：FSRS 复习方法整理'
                        : '例如：什么是间隔重复？',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bodyController,
                  maxLines: widget.document ? 12 : 6,
                  onChanged: _clearError,
                  decoration: InputDecoration(
                    labelText: widget.document ? '文档内容' : '卡片背面（可选）',
                    hintText: widget.document
                        ? '输入正文内容，支持 Markdown'
                        : '补充答案、解释或记忆提示',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                _FolderField(
                  values: folderValues,
                  selected: selectedFolder,
                  onChanged: (value) => setState(() => _folder = value),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _createFolder,
                    icon: const Icon(
                      Icons.create_new_folder_outlined,
                      size: 18,
                    ),
                    label: Text(widget.document ? '新建文档类别' : '新建牌组'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppVisualColors.darkGreen,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                if (_error != null) _ErrorText(_error!),
                const SizedBox(height: 18),
                _SaveButton(
                  label: widget.document ? '保存文档' : '保存卡片',
                  saving: _saving,
                  onPressed: _save,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _clearError(String _) {
    if (_error != null) setState(() => _error = null);
  }

  Future<void> _createFolder() async {
    final created = await createCollectionFromSheet(
      context,
      ref,
      type: widget.document
          ? CollectionType.documentCategory
          : CollectionType.deck,
    );
    if (created != null && mounted) {
      setState(() => _folder = created.name);
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = widget.document ? '请输入文档标题' : '请输入卡片正面内容');
      return;
    }
    if (widget.document && body.isEmpty) {
      setState(() => _error = '请输入文档内容');
      return;
    }

    final account = ref.read(currentAccountProvider);
    if (account == null) return;
    final folder = _folder == null || _folder == '未分类' ? '' : _folder!;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (widget.document) {
        await ref
            .read(contentRepositoryProvider)
            .createDocument(
              accountId: account.id,
              title: title,
              body: body,
              folder: folder,
            );
        ref.invalidate(documentsProvider);
      } else {
        final now = DateTime.now();
        await ref
            .read(contentRepositoryProvider)
            .createCard(
              CardModel(
                id: 'local-card-${now.microsecondsSinceEpoch}',
                accountId: account.id,
                type: CardType.note,
                folder: folder,
                question: title,
                options: const {},
                answer: const [],
                content: body,
                noteContent: '',
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
              ),
            );
        ref.invalidate(cardsProvider);
        ref.invalidate(collectionsProvider);
      }

      ref.invalidate(pendingSyncProvider);
      ref
          .read(syncControllerProvider.notifier)
          .scheduleSync(
            reason: widget.document
                ? 'editor-document-create'
                : 'editor-card-create',
          );

      if (!mounted) return;
      _titleController.clear();
      _bodyController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.document ? '文档已保存，等待同步' : '卡片已保存，等待同步')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _EditorCard extends StatelessWidget {
  const _EditorCard({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 17, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xffe7ede8)),
        boxShadow: appCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppVisualColors.ink,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppVisualColors.muted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }
}

class _FolderField extends StatelessWidget {
  const _FolderField({
    required this.values,
    required this.selected,
    required this.onChanged,
  });

  final List<String> values;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: selected,
      decoration: const InputDecoration(labelText: '归入分组'),
      hint: const Text('未分类'),
      items: values
          .map((value) => DropdownMenuItem(value: value, child: Text(value)))
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.label,
    required this.saving,
    required this.onPressed,
  });

  final String label;
  final bool saving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: saving ? null : onPressed,
        child: saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xffb3261e), fontSize: 12),
      ),
    );
  }
}
