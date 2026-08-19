import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_providers.dart';
import '../../core/models/card_model.dart';
import '../../core/models/collection_model.dart';
import '../../core/widgets/app_visuals.dart';
import '../collections/collection_actions.dart';
import 'card_source_history.dart';

const _cardEditorPurple = Color(0xff6553e8);
const _cardEditorBlue = Color(0xff2f8fe8);
const _cardEditorGreen = Color(0xff25a94b);
const _cardEditorBorder = Color(0xffe4e7eb);

class CardEditorPage extends ConsumerStatefulWidget {
  const CardEditorPage({
    this.initialCard,
    this.initialFolder,
    this.onBack,
    this.onClose,
    super.key,
  });

  final CardModel? initialCard;
  final String? initialFolder;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  @override
  ConsumerState<CardEditorPage> createState() => _CardEditorPageState();
}

class _CardEditorPageState extends ConsumerState<CardEditorPage> {
  late final TextEditingController _questionController;
  late final TextEditingController _contentController;
  late final TextEditingController _noteController;
  late final TextEditingController _explanationController;
  late final TextEditingController _sourceController;
  final _options = <_CardOptionDraft>[];

  late CardType _type;
  String? _folder;
  String? _recentSource;
  String? _error;
  bool _saving = false;

  bool get _isEditing => widget.initialCard != null;
  bool get _isNote => _type == CardType.note;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCard;
    _type = switch (initial?.type) {
      CardType.multiple => CardType.multiple,
      CardType.note => CardType.note,
      _ => CardType.single,
    };
    final initialFolder = widget.initialFolder?.trim();
    _folder =
        initialFolder == null || initialFolder.isEmpty || initialFolder == '未分类'
        ? (initial?.folder.trim().isEmpty ?? true ? null : initial!.folder)
        : initialFolder;
    _questionController = TextEditingController(text: initial?.question ?? '');
    _contentController = TextEditingController(text: initial?.content ?? '');
    _noteController = TextEditingController(text: initial?.noteContent ?? '');
    _explanationController = TextEditingController(
      text: initial?.explanation ?? '',
    );
    _sourceController = TextEditingController(text: initial?.source ?? '');
    _recentSource = _readRecentSource(_folder);

    if (initial != null && initial.options.isNotEmpty) {
      for (final entry in initial.options.entries) {
        _options.add(
          _CardOptionDraft(
            value: entry.value,
            correct: initial.answer.contains(entry.key),
          ),
        );
      }
    }
    if (!_isNote) _ensureOptions();
  }

  @override
  void dispose() {
    _questionController.dispose();
    _contentController.dispose();
    _noteController.dispose();
    _explanationController.dispose();
    _sourceController.dispose();
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collections =
        ref.watch(collectionsProvider).valueOrNull ?? const <CollectionModel>[];
    final cards = ref.watch(cardsProvider).valueOrNull ?? const <CardModel>[];
    final folders = _folderValues(collections, cards);

    return Scaffold(
      backgroundColor: AppVisualColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 64,
        leading: IconButton(
          tooltip: '返回',
          onPressed: widget.onBack ?? () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(_isEditing ? '编辑闪卡' : '新建闪卡'),
        actions: [
          TextButton.icon(
            onPressed: _showPreview,
            icon: const Icon(Icons.visibility_outlined, size: 19),
            label: const Text('预览'),
            style: TextButton.styleFrom(
              foregroundColor: AppVisualColors.ink,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          if (widget.onClose != null)
            IconButton(
              tooltip: '关闭编辑',
              onPressed: widget.onClose,
              icon: const Icon(Icons.close_rounded),
            ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Tooltip(
              message: '保存',
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: _cardEditorPurple,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(68, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('保存'),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
          children: [
            const Text(
              '选择卡片类型',
              style: TextStyle(
                color: AppVisualColors.ink,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              // The type cards live inside a vertical ListView. Give this
              // horizontal row a finite height so the cards' internal
              // spacing cannot request infinite height during layout.
              height: 132,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _typeChoice(CardType.single)),
                  const SizedBox(width: 10),
                  Expanded(child: _typeChoice(CardType.multiple)),
                  const SizedBox(width: 10),
                  Expanded(child: _typeChoice(CardType.note)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _EditorPanel(
              title: '题目',
              icon: Icons.edit_note_rounded,
              iconColor: _cardEditorPurple,
              child: [
                TextField(
                  controller: _questionController,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 1000,
                  onChanged: (_) => _clearError(),
                  decoration: _fieldDecoration('请输入题目内容…'),
                ),
                _EditorToolbar(
                  onInsert: (left, right) =>
                      _insertMarkup(_questionController, left, right),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _replaceQuestionSpaces,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                    label: const Text('空格转下划线'),
                    style: TextButton.styleFrom(
                      foregroundColor: _cardEditorPurple,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_isNote)
              _EditorPanel(
                title: '内容',
                icon: Icons.note_alt_outlined,
                iconColor: _cardEditorGreen,
                child: [
                  TextField(
                    controller: _contentController,
                    minLines: 5,
                    maxLines: 10,
                    maxLength: 2000,
                    decoration: _fieldDecoration('请输入速记词条内容…'),
                  ),
                  const Text(
                    '这是速记词条的正文，复习时会作为词条背面内容展示。',
                    style: TextStyle(
                      color: AppVisualColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              )
            else
              _choicePanel(),
            const SizedBox(height: 18),
            _notePanel(),
            const SizedBox(height: 18),
            _EditorPanel(
              title: '解析（可选）',
              icon: Icons.description_outlined,
              iconColor: _cardEditorBlue,
              child: [
                TextField(
                  controller: _explanationController,
                  minLines: 5,
                  maxLines: 10,
                  maxLength: 2000,
                  decoration: _fieldDecoration('请输入解析内容，帮助更好地理解知识点…'),
                ),
                _EditorToolbar(
                  onInsert: (left, right) =>
                      _insertMarkup(_explanationController, left, right),
                ),
                const Text(
                  '解析可以帮助你在答错后理解知识点，建议写清楚原因。',
                  style: TextStyle(color: AppVisualColors.muted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _EditorPanel(
              title: '来源（可选）',
              icon: Icons.public_outlined,
              iconColor: _cardEditorPurple,
              child: [
                TextField(
                  controller: _sourceController,
                  maxLength: 200,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _clearError(),
                  decoration: _fieldDecoration('可填写教材、试卷、课程、网站或其他来源'),
                ),
                if (_recentSource != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ActionChip(
                      avatar: const Icon(Icons.history_rounded, size: 17),
                      label: Text('使用最近来源：$_recentSource'),
                      onPressed: _useRecentSource,
                      backgroundColor: const Color(0xfff2f0ff),
                      side: BorderSide.none,
                      labelStyle: const TextStyle(
                        color: _cardEditorPurple,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const Text(
                  '来源与归入牌组相互独立，方便你按自己的方式整理卡片。',
                  style: TextStyle(color: AppVisualColors.muted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _EditorPanel(
              title: '归入牌组',
              icon: Icons.folder_open_outlined,
              iconColor: AppVisualColors.muted,
              child: [
                DropdownButtonFormField<String>(
                  initialValue: folders.contains(_folder) ? _folder : null,
                  decoration: _fieldDecoration('选择一个牌组（可选）'),
                  hint: const Text('未分类'),
                  items: folders
                      .map(
                        (folder) => DropdownMenuItem(
                          value: folder,
                          child: Text(folder),
                        ),
                      )
                      .toList(),
                  onChanged: _selectFolder,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _createDeck,
                    icon: const Icon(
                      Icons.create_new_folder_outlined,
                      size: 18,
                    ),
                    label: const Text('新建牌组'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppVisualColors.ink,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _ErrorMessage(_error!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _typeChoice(CardType type) {
    final selected = _type == type;
    final data = switch (type) {
      CardType.single => (
        title: '单选题',
        description: '选择一个正确答案',
        icon: Icons.radio_button_checked_rounded,
      ),
      CardType.multiple => (
        title: '多选题',
        description: '选择一个或多个正确答案',
        icon: Icons.checklist_rounded,
      ),
      CardType.note => (
        title: '速记词条',
        description: '正面显示题目，背面显示答案',
        icon: Icons.short_text_rounded,
      ),
      CardType.trueFalse => (
        title: '判断题',
        description: '选择正确或错误',
        icon: Icons.rule_rounded,
      ),
    };
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _type = type;
            _error = null;
            if (!_isNote) _ensureOptions();
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 108),
          padding: const EdgeInsets.fromLTRB(11, 12, 9, 11),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xfff6f4ff)
                : Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? _cardEditorPurple : _cardEditorBorder,
              width: selected ? 1.4 : 1,
            ),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x146553e8),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    data.icon,
                    size: 19,
                    color: selected ? _cardEditorPurple : AppVisualColors.muted,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? _cardEditorPurple
                            : AppVisualColors.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                data.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppVisualColors.muted,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choicePanel() {
    final selectedCount = _options.where((option) => option.correct).length;
    return _EditorPanel(
      title: '答案',
      icon: Icons.check_circle_outline_rounded,
      iconColor: _cardEditorGreen,
      child: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xfff0faf2),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: _cardEditorGreen,
                size: 18,
              ),
              const SizedBox(width: 7),
              Text(
                _type == CardType.multiple ? '请选择正确答案（可选择多个）' : '请选择一个正确答案',
                style: const TextStyle(
                  color: _cardEditorGreen,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < _options.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _AnswerOptionRow(
              option: _options[index],
              label: _optionLabel(index),
              multiple: _type == CardType.multiple,
              onToggle: () => _toggleOption(index),
              onDelete: () => _removeOption(index),
            ),
          ),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _addOption,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加选项'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppVisualColors.muted,
                side: const BorderSide(color: _cardEditorBorder),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _clearAnswers,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('清空选择'),
              style: TextButton.styleFrom(
                foregroundColor: AppVisualColors.muted,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '已选择 $selectedCount 个正确答案',
          style: const TextStyle(
            color: _cardEditorGreen,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _notePanel() {
    return _EditorPanel(
      title: '笔记（可选）',
      icon: Icons.note_alt_outlined,
      iconColor: _cardEditorBlue,
      child: [
        TextField(
          controller: _noteController,
          minLines: 3,
          maxLines: 8,
          maxLength: 2000,
          decoration: _fieldDecoration('补充记忆提示、易错点或其他笔记…'),
        ),
        const Text(
          '保存后会在题目详情页的“笔记”区域展示。',
          style: TextStyle(color: AppVisualColors.muted, fontSize: 12),
        ),
      ],
    );
  }

  List<String> _folderValues(
    List<CollectionModel> collections,
    List<CardModel> cards,
  ) {
    final values = <String>{
      ...cards
          .map((card) => card.folder.trim())
          .where((folder) => folder.isNotEmpty),
      ...collections
          .where(
            (collection) =>
                collection.type == CollectionType.deck && !collection.archived,
          )
          .map((collection) => collection.name.trim())
          .where((folder) => folder.isNotEmpty),
    };
    final result = values.toList()..sort();
    return result;
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xff9aa1aa), fontSize: 14),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: _cardEditorBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: _cardEditorBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: _cardEditorPurple, width: 1.4),
    ),
  );

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  String? _readRecentSource(String? folder) {
    try {
      final account = ref.read(currentAccountProvider);
      if (account == null || folder == null || folder.trim().isEmpty) {
        return null;
      }
      return CardSourceHistory(
        ref.read(sharedPreferencesProvider),
      ).read(accountId: account.id, folder: folder);
    } on UnimplementedError {
      // Standalone widget tests may not provide app-level preferences.
      return null;
    }
  }

  void _selectFolder(String? value) {
    setState(() {
      _folder = value;
      _recentSource = _readRecentSource(value);
    });
  }

  void _useRecentSource() {
    final recent = _recentSource;
    if (recent == null || recent.isEmpty) return;
    setState(() {
      _sourceController.value = TextEditingValue(
        text: recent,
        selection: TextSelection.collapsed(offset: recent.length),
      );
      _error = null;
    });
  }

  void _replaceQuestionSpaces() {
    final current = _questionController.text;
    final replaced = replaceSpacesWithUnderscores(current);
    if (replaced == current) return;
    final selection = _questionController.selection;
    _questionController.value = TextEditingValue(
      text: replaced,
      selection: _mapQuestionSelection(current, replaced, selection),
    );
    _clearError();
  }

  TextSelection _mapQuestionSelection(
    String original,
    String replaced,
    TextSelection selection,
  ) {
    if (!selection.isValid ||
        selection.baseOffset < 0 ||
        selection.extentOffset < 0) {
      return TextSelection.collapsed(offset: replaced.length);
    }

    int mapOffset(int offset) {
      final safeOffset = offset < 0
          ? 0
          : offset > original.length
          ? original.length
          : offset;
      return replaceSpacesWithUnderscores(
        original.substring(0, safeOffset),
      ).length;
    }

    return TextSelection(
      baseOffset: mapOffset(selection.baseOffset),
      extentOffset: mapOffset(selection.extentOffset),
      affinity: selection.affinity,
      isDirectional: selection.isDirectional,
    );
  }

  Future<void> _rememberRecentSource(String folder, String source) async {
    try {
      final account = ref.read(currentAccountProvider);
      if (account == null || folder.trim().isEmpty || source.trim().isEmpty) {
        return;
      }
      await CardSourceHistory(
        ref.read(sharedPreferencesProvider),
      ).remember(accountId: account.id, folder: folder, source: source);
    } on UnimplementedError {
      // The editor can still save cards when app-level preferences are absent.
    }
  }

  void _ensureOptions() {
    while (_options.length < 4) {
      _options.add(_CardOptionDraft());
    }
  }

  String _optionLabel(int index) => String.fromCharCode(65 + index);

  void _toggleOption(int index) {
    setState(() {
      if (_type == CardType.single) {
        for (final option in _options) {
          option.correct = false;
        }
        _options[index].correct = true;
      } else {
        _options[index].correct = !_options[index].correct;
      }
      _error = null;
    });
  }

  void _addOption() {
    setState(() {
      _options.add(_CardOptionDraft());
      _error = null;
    });
  }

  void _removeOption(int index) {
    if (_options.length <= 2) {
      setState(() => _error = '至少保留两个选项');
      return;
    }
    setState(() {
      _options.removeAt(index).dispose();
      _error = null;
    });
  }

  void _clearAnswers() {
    setState(() {
      for (final option in _options) {
        option.correct = false;
      }
      _error = null;
    });
  }

  Future<void> _createDeck() async {
    final created = await createCollectionFromSheet(
      context,
      ref,
      type: CollectionType.deck,
    );
    if (created != null && mounted) {
      setState(() => _folder = created.name);
    }
  }

  void _insertMarkup(
    TextEditingController controller,
    String left,
    String right,
  ) {
    final value = controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final selected = value.text.substring(start, end);
    final replacement = '$left$selected$right';
    final text = value.text.replaceRange(start, end, replacement);
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
  }

  void _showPreview() {
    // The preview action is commonly used while an option or the question is
    // focused. Close the IME first so the dialog is laid out against the full
    // window instead of competing with the keyboard's inset animation.
    FocusManager.instance.primaryFocus?.unfocus();

    final options = _options
        .map((option) => option.controller.text.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final correct = <String>[];
    for (var index = 0; index < _options.length; index++) {
      if (_options[index].correct) correct.add(_optionLabel(index));
    }
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.78,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '卡片预览',
                        style: TextStyle(
                          color: AppVisualColors.ink,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭预览',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _type.label,
                  style: const TextStyle(
                    color: _cardEditorPurple,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _questionController.text.trim().isEmpty
                      ? '还没有输入题目'
                      : _questionController.text.trim(),
                  style: const TextStyle(
                    color: AppVisualColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
                if (_isNote && _contentController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('内容：${_contentController.text.trim()}'),
                ],
                if (_noteController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('笔记：${_noteController.text.trim()}'),
                ],
                if (!_isNote && options.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  for (var index = 0; index < options.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Text(
                        '${String.fromCharCode(65 + index)}. ${options[index]}${correct.contains(String.fromCharCode(65 + index)) ? '  ✓' : ''}',
                      ),
                    ),
                ],
                if (_explanationController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '解析：${_explanationController.text.trim()}',
                    style: const TextStyle(color: AppVisualColors.muted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final question = _questionController.text.trim();
    if (question.isEmpty) {
      setState(() => _error = '请输入题目内容');
      return;
    }

    final options = <String, String>{};
    final answers = <String>[];
    if (!_isNote) {
      final filled = _options
          .where((option) => option.controller.text.trim().isNotEmpty)
          .length;
      if (filled < 2) {
        setState(() => _error = '请至少填写两个选项');
        return;
      }
      for (var index = 0; index < _options.length; index++) {
        final value = _options[index].controller.text.trim();
        if (value.isEmpty) continue;
        final label = _optionLabel(index);
        options[label] = value;
        if (_options[index].correct) answers.add(label);
      }
      if (answers.isEmpty) {
        setState(() => _error = '请选择正确答案');
        return;
      }
      if (_type == CardType.single && answers.length != 1) {
        setState(() => _error = '单选题只能选择一个正确答案');
        return;
      }
    }

    final account = ref.read(currentAccountProvider);
    if (account == null) return;
    final now = DateTime.now();
    final previous = widget.initialCard;
    final folder = (_folder ?? '').trim();
    final source = _sourceController.text.trim();
    final card = CardModel(
      id: previous?.id ?? 'local-card-${now.microsecondsSinceEpoch}',
      accountId: previous?.accountId ?? account.id,
      type: _type,
      folder: folder,
      source: source,
      question: question,
      options: options,
      answer: answers,
      content: _isNote ? _contentController.text.trim() : '',
      noteContent: _noteController.text.trim(),
      explanation: _explanationController.text.trim(),
      tags: previous?.tags ?? const [],
      dueAt: previous?.dueAt ?? now,
      createdAt: previous?.createdAt ?? now,
      sortOrder: previous?.sortOrder,
      updatedAt: now,
      reviews: previous?.reviews ?? 0,
      mastery: previous?.mastery ?? '',
      suspended: previous?.suspended ?? false,
      fsrs:
          previous?.fsrs ??
          FsrsSnapshot(
            state: FsrsState.newCard,
            dueAt: now,
            stability: 0,
            difficulty: 5,
            reps: 0,
            lapses: 0,
          ),
    );

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = ref.read(contentRepositoryProvider);
      if (previous == null) {
        await repository.createCard(card);
      } else {
        await repository.updateCard(card);
      }
      await _rememberRecentSource(folder, source);
      ref.invalidate(cardsProvider);
      ref.invalidate(collectionsProvider);
      ref.invalidate(pendingSyncProvider);
      ref
          .read(syncControllerProvider.notifier)
          .scheduleSync(
            reason: previous == null ? 'card-create' : 'card-update',
          );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(previous == null ? '卡片已保存' : '卡片已更新')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _CardOptionDraft {
  _CardOptionDraft({String value = '', this.correct = false})
    : controller = TextEditingController(text: value);

  final TextEditingController controller;
  bool correct;

  void dispose() => controller.dispose();
}

class _EditorPanel extends StatelessWidget {
  const _EditorPanel({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14, 15, 14, 14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: const Color(0xffedf0f2)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0b000000),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: 23),
            const SizedBox(width: 9),
            Text(
              title,
              style: const TextStyle(
                color: AppVisualColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ...child,
      ],
    ),
  );
}

class _AnswerOptionRow extends StatelessWidget {
  const _AnswerOptionRow({
    required this.option,
    required this.label,
    required this.multiple,
    required this.onToggle,
    required this.onDelete,
  });

  final _CardOptionDraft option;
  final String label;
  final bool multiple;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 25,
          height: 25,
          decoration: BoxDecoration(
            color: option.correct ? _cardEditorGreen : Colors.white,
            shape: multiple ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: multiple ? BorderRadius.circular(5) : null,
            border: Border.all(
              color: option.correct
                  ? _cardEditorGreen
                  : const Color(0xffb7bdc4),
              width: 1.6,
            ),
          ),
          child: option.correct
              ? const Icon(Icons.check, color: Colors.white, size: 17)
              : null,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: TextField(
          controller: option.controller,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: '选项 $label',
            hintStyle: const TextStyle(color: Color(0xff9aa1aa)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 11,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: _cardEditorBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: _cardEditorBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(
                color: _cardEditorPurple,
                width: 1.4,
              ),
            ),
          ),
        ),
      ),
      IconButton(
        tooltip: '删除选项',
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline_rounded),
        color: AppVisualColors.muted,
        visualDensity: VisualDensity.compact,
      ),
    ],
  );
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({required this.onInsert});

  final void Function(String left, String right) onInsert;

  @override
  Widget build(BuildContext context) => Container(
    height: 39,
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Color(0xffedf0f2))),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _ToolbarButton('B', () => onInsert('**', '**'), bold: true),
          _ToolbarButton('I', () => onInsert('*', '*'), italic: true),
          _ToolbarButton('U', () => onInsert('<u>', '</u>')),
          _ToolbarButton('S', () => onInsert('~~', '~~')),
          const _ToolbarDivider(),
          _ToolbarButton('</>', () => onInsert('`', '`')),
          _ToolbarButton('•', () => onInsert('\n- ', '')),
          _ToolbarButton('1.', () => onInsert('\n1. ', '')),
          const _ToolbarDivider(),
          _ToolbarButton('Ω', () => onInsert('\\(', '\\)')),
          _ToolbarButton('↶', () {}),
          _ToolbarButton('↷', () {}),
        ],
      ),
    ),
  );
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton(
    this.label,
    this.onPressed, {
    this.bold = false,
    this.italic = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool bold;
  final bool italic;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: label,
    padding: const EdgeInsets.symmetric(horizontal: 7),
    constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
    visualDensity: VisualDensity.compact,
    icon: Text(
      label,
      style: TextStyle(
        color: const Color(0xff4d555f),
        fontSize: label.length > 2 ? 12 : 17,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      ),
    ),
  );
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 20,
    margin: const EdgeInsets.symmetric(horizontal: 3),
    color: const Color(0xffedf0f2),
  );
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xfffff1ef),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      message,
      style: const TextStyle(
        color: Color(0xffb3261e),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
