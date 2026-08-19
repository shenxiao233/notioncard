import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../../core/models/card_model.dart';
import '../../core/models/collection_model.dart';
import '../../core/platform/json_file_picker.dart';
import '../../core/widgets/app_visuals.dart';
import 'card_import_parser.dart';

class CardImportPage extends ConsumerStatefulWidget {
  const CardImportPage({this.initialFolder, super.key});

  final String? initialFolder;

  @override
  ConsumerState<CardImportPage> createState() => _CardImportPageState();
}

class _CardImportPageState extends ConsumerState<CardImportPage> {
  static const _newDeckValue = '__new_deck__';
  static const _uncategorizedValue = '未分类';

  final _newFolderController = TextEditingController();
  BrowserCardImportDocument? _document;
  String? _fileName;
  String? _selectedFolder;
  String? _error;
  bool _picking = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialFolder?.trim();
    _selectedFolder = initial == null || initial.isEmpty ? null : initial;
  }

  @override
  void dispose() {
    _newFolderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(cardsProvider).valueOrNull ?? const <CardModel>[];
    final collections =
        ref.watch(collectionsProvider).valueOrNull ?? const <CollectionModel>[];
    final folders = _deckFolders(cards, collections);
    final folderValue = _folderDropdownValue(folders);
    final targetFolder = _targetFolder(folderValue);
    final duplicateCount = _duplicateCount(cards, targetFolder);
    final validCount = _document?.cards.length ?? 0;

    return Scaffold(
      backgroundColor: AppVisualColors.background,
      appBar: AppBar(
        title: const Text(
          '批量导入卡片',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            _ImportIntro(onPick: _pickFile, picking: _picking),
            if (_fileName != null) ...[
              const SizedBox(height: 12),
              _FileSummary(
                fileName: _fileName!,
                document: _document,
                onReplace: _pickFile,
                picking: _picking,
              ),
            ],
            if (_document != null) ...[
              const SizedBox(height: 16),
              _ImportSection(
                title: '导入到牌组',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      value: folderValue,
                      decoration: const InputDecoration(
                        labelText: '目标牌组',
                        prefixIcon: Icon(Icons.folder_outlined),
                      ),
                      items: [
                        ...folders.map(
                          (folder) => DropdownMenuItem<String>(
                            value: folder,
                            child: Text(folder),
                          ),
                        ),
                        const DropdownMenuItem<String>(
                          value: _newDeckValue,
                          child: Text('新建牌组'),
                        ),
                      ],
                      onChanged: _importing
                          ? null
                          : (value) => setState(() {
                              _selectedFolder = value;
                              _error = null;
                            }),
                    ),
                    if (folderValue == _newDeckValue) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _newFolderController,
                        enabled: !_importing,
                        decoration: const InputDecoration(
                          labelText: '新牌组名称',
                          hintText: '例如：2026 行测错题',
                          prefixIcon: Icon(Icons.create_new_folder_outlined),
                        ),
                        onChanged: (_) => setState(() => _error = null),
                      ),
                    ],
                    if (folderValue == _uncategorizedValue)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          '未分类会保存为空牌组名称，之后仍可在卡片页面移动或重命名。',
                          style: TextStyle(
                            color: AppVisualColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _ImportSection(
                title: '导入预览',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PreviewStatRow(
                      label: '可导入题目',
                      value: '$validCount 道',
                      color: AppVisualColors.darkGreen,
                    ),
                    _PreviewStatRow(
                      label: '重复题目',
                      value: '$duplicateCount 道（将跳过）',
                      color: duplicateCount == 0
                          ? AppVisualColors.muted
                          : AppVisualColors.amber,
                    ),
                    if (_document!.issues.isNotEmpty)
                      _PreviewStatRow(
                        label: '无法识别',
                        value: '${_document!.issues.length} 道',
                        color: const Color(0xffc53b32),
                      ),
                    const SizedBox(height: 12),
                    ..._document!.cards.take(3).map(_DraftPreviewTile.new),
                    if (_document!.cards.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '还有 ${_document!.cards.length - 3} 道题目将在导入时一并处理。',
                          style: const TextStyle(
                            color: AppVisualColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(message: _error!),
            ],
            if (_document != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      _importing || validCount == 0 || targetFolder == null
                      ? null
                      : () => _import(cards, targetFolder),
                  icon: _importing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_download_outlined),
                  label: Text(_importing ? '正在导入…' : '导入 $validCount 道卡片'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<String> _deckFolders(
    List<CardModel> cards,
    List<CollectionModel> collections,
  ) {
    final folders = <String>{_uncategorizedValue};
    folders.addAll(
      collections
          .where((value) => value.type == CollectionType.deck)
          .map((value) => value.name.trim())
          .where((value) => value.isNotEmpty),
    );
    folders.addAll(
      cards
          .map((card) => card.folder.trim())
          .where((value) => value.isNotEmpty),
    );
    return folders.toList()..sort((left, right) {
      if (left == _uncategorizedValue) return -1;
      if (right == _uncategorizedValue) return 1;
      return left.compareTo(right);
    });
  }

  String? _folderDropdownValue(List<String> folders) {
    final selected = _selectedFolder;
    if (selected == _newDeckValue) return _newDeckValue;
    if (selected != null && folders.contains(selected)) return selected;
    if (widget.initialFolder != null &&
        folders.contains(widget.initialFolder!.trim())) {
      return widget.initialFolder!.trim();
    }
    return _document == null ? null : _newDeckValue;
  }

  String? _targetFolder(String? dropdownValue) {
    if (dropdownValue == null) return null;
    if (dropdownValue == _newDeckValue) {
      final value = _newFolderController.text.trim();
      return value.isEmpty ? null : value;
    }
    return dropdownValue == _uncategorizedValue ? '' : dropdownValue.trim();
  }

  int _duplicateCount(List<CardModel> cards, String? targetFolder) {
    final document = _document;
    if (document == null || targetFolder == null) return 0;
    final existing = cards.where(
      (card) => card.folder.trim() == targetFolder.trim(),
    );
    final ids = existing.map((card) => card.id).toSet();
    final questions = existing.map((card) => _cardFingerprint(card)).toSet();
    return document.cards.where((draft) {
      final id = importedCardId(
        accountId: ref.read(currentAccountProvider)?.id ?? '',
        folder: targetFolder,
        draft: draft,
      );
      return ids.contains(id) || questions.contains(draft.fingerprint);
    }).length;
  }

  Future<void> _pickFile() async {
    if (_picking || _importing) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final file = await pickJsonFile();
      if (file == null) return;
      final raw = file.content;
      if (raw.trim().isEmpty) throw const FormatException('文件内容为空');
      final document = parseBrowserCardJson(raw);
      if (!mounted) return;
      setState(() {
        _fileName = file.name;
        _document = document;
        _selectedFolder ??= widget.initialFolder?.trim();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '读取 JSON 失败：$error');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _import(List<CardModel> existing, String targetFolder) async {
    final account = ref.read(currentAccountProvider);
    final document = _document;
    if (account == null || document == null) return;

    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final existingIds = existing.map((card) => card.id).toSet();
      final existingFingerprints = existing
          .where((card) => card.folder.trim() == targetFolder.trim())
          .map(_cardFingerprint)
          .toSet();
      final cards = <CardModel>[];
      var skippedBeforeRepository = 0;
      for (final draft in document.cards) {
        final id = importedCardId(
          accountId: account.id,
          folder: targetFolder,
          draft: draft,
        );
        if (existingIds.contains(id) ||
            existingFingerprints.contains(draft.fingerprint)) {
          skippedBeforeRepository++;
          continue;
        }
        cards.add(
          _toCard(
            accountId: account.id,
            folder: targetFolder,
            draft: draft,
            createdAt: now.add(Duration(microseconds: cards.length)),
          ),
        );
      }

      final result = await ref
          .read(contentRepositoryProvider)
          .importCards(account.id, cards, deckTitle: targetFolder);
      ref.invalidate(cardsProvider);
      ref.invalidate(collectionsProvider);
      ref.invalidate(pendingSyncProvider);
      ref
          .read(syncControllerProvider.notifier)
          .scheduleSync(reason: 'browser-card-import');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('导入完成'),
          content: Text(
            '成功导入 ${result.imported} 道，跳过 ${result.skipped + skippedBeforeRepository} 道重复题。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = '导入失败：$error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}

CardModel _toCard({
  required String accountId,
  required String folder,
  required BrowserCardDraft draft,
  required DateTime createdAt,
}) {
  return CardModel(
    id: importedCardId(accountId: accountId, folder: folder, draft: draft),
    accountId: accountId,
    type: draft.type,
    folder: folder,
    source: draft.source,
    question: draft.question,
    options: draft.options,
    answer: draft.answer,
    content: '',
    noteContent: '',
    explanation: draft.explanation,
    tags: draft.tags,
    dueAt: createdAt,
    createdAt: createdAt,
    updatedAt: createdAt,
    reviews: 0,
    mastery: reviewingCardMastery,
    suspended: false,
    fsrs: FsrsSnapshot(
      state: FsrsState.newCard,
      dueAt: createdAt,
      stability: 0,
      difficulty: 0,
      reps: 0,
      lapses: 0,
    ),
  );
}

String _cardFingerprint(CardModel card) => BrowserCardDraft(
  sourceIndex: 0,
  externalId: '',
  externalKey: '',
  type: card.type,
  source: card.source,
  question: card.question,
  options: card.options,
  answer: card.answer,
  explanation: card.explanation,
  tags: card.tags,
).fingerprint;

class _ImportIntro extends StatelessWidget {
  const _ImportIntro({required this.onPick, required this.picking});

  final VoidCallback onPick;
  final bool picking;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
    decoration: BoxDecoration(
      color: AppVisualColors.softGreen,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xffd6ecd2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '导入浏览器错题 JSON',
          style: TextStyle(
            color: AppVisualColors.ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          '会保留题目中的填空线、图片链接、解析和知识点，并转换为当前卡片格式。',
          style: TextStyle(
            color: AppVisualColors.muted,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: picking ? null : onPick,
          icon: picking
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.folder_open_outlined),
          label: Text(picking ? '正在读取…' : '选择 JSON 文件'),
        ),
      ],
    ),
  );
}

class _FileSummary extends StatelessWidget {
  const _FileSummary({
    required this.fileName,
    required this.document,
    required this.onReplace,
    required this.picking,
  });

  final String fileName;
  final BrowserCardImportDocument? document;
  final VoidCallback onReplace;
  final bool picking;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppVisualColors.line),
    ),
    child: Row(
      children: [
        const Icon(Icons.data_object_rounded, color: AppVisualColors.darkGreen),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (document != null)
                Text(
                  '${document!.cards.length} 道可识别题目${document!.issues.isEmpty ? '' : ' · ${document!.issues.length} 道异常'}',
                  style: const TextStyle(
                    color: AppVisualColors.muted,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: '更换文件',
          onPressed: picking ? null : onReplace,
          icon: const Icon(Icons.swap_horiz_rounded),
        ),
      ],
    ),
  );
}

class _ImportSection extends StatelessWidget {
  const _ImportSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppVisualColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppVisualColors.ink,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _PreviewStatRow extends StatelessWidget {
  const _PreviewStatRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppVisualColors.muted, fontSize: 13),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _DraftPreviewTile extends StatelessWidget {
  const _DraftPreviewTile(this.draft);

  final BrowserCardDraft draft;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: AppVisualColors.paleGreen,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TypePill(label: draft.type.label),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            _plainPreview(draft.question),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, height: 1.35),
          ),
        ),
      ],
    ),
  );
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: AppVisualColors.darkGreen,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xfffff3f0),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xfff0c6bd)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, color: Color(0xffc53b32), size: 19),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: Color(0xff9f3029),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

String _plainPreview(String value) => value
    .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '[图片]')
    .replaceAll(RegExp(r'[#*_>`]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
