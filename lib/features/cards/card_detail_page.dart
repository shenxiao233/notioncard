import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_providers.dart';
import '../../core/models/card_model.dart';
import '../../core/models/card_highlight_model.dart';
import '../../core/widgets/app_visuals.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/markdown_content.dart';
import 'card_favorites.dart';
import 'card_share_page.dart';
import '../review/review_queue.dart';

enum _TagAction { edit, delete }

class CardDetailPage extends ConsumerWidget {
  const CardDetailPage({required this.cardId, super.key});

  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(cardsProvider);
    final favoriteCardIds = ref.watch(cardFavoritesProvider);
    final values = cards.valueOrNull ?? const <CardModel>[];
    final current = _findCard(values, cardId);
    final deckCards = current == null
        ? const <CardModel>[]
        : _orderedDeckCards(values, current.folder);
    final currentIndex = current == null
        ? -1
        : deckCards.indexWhere((card) => card.id == current.id);
    final previousCard = currentIndex > 0 ? deckCards[currentIndex - 1] : null;
    final nextCard = currentIndex >= 0 && currentIndex + 1 < deckCards.length
        ? deckCards[currentIndex + 1]
        : null;

    return Scaffold(
      backgroundColor: AppVisualColors.background,
      appBar: AppBar(
        title: const Text(
          '题目详情',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: '分享题目',
            onPressed: current == null
                ? null
                : () => _openSharePage(context, current),
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: cards.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppVisualColors.green),
        ),
        error: (error, _) => EmptyState(
          title: '卡片加载失败',
          message: '请检查本地缓存，然后重试。',
          icon: Icons.cloud_off_outlined,
          action: FilledButton.icon(
            onPressed: () => ref.invalidate(cardsProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ),
        data: (values) {
          final card = _findCard(values, cardId);
          if (card == null) {
            return const EmptyState(
              title: '卡片不存在',
              message: '它可能尚未同步，或已经从当前账户移除。',
              icon: Icons.style_outlined,
            );
          }
          final cardsInDeck = _orderedDeckCards(values, card.folder);
          final index = cardsInDeck.indexWhere((value) => value.id == card.id);
          final next = index >= 0 && index + 1 < cardsInDeck.length
              ? cardsInDeck[index + 1]
              : null;
          final highlights =
              ref.watch(cardHighlightsProvider(card.id)).valueOrNull ??
              const <CardHighlightModel>[];
          return _CardReader(
            card: card,
            position: index < 0 ? 1 : index + 1,
            total: cardsInDeck.isEmpty ? 1 : cardsInDeck.length,
            favorite: favoriteCardIds.contains(card.id),
            highlights: highlights,
            onToggleFavorite: () => unawaited(_toggleFavorite(ref, card.id)),
            onToggleReviewStatus: () => _toggleReviewStatus(context, ref, card),
            onTagLongPress: (tag) => _showTagActions(context, ref, card, tag),
            onEditTags: () => _editTags(context, ref, card),
            onAddHighlight: (section, selectedText) =>
                _addHighlight(context, ref, card, section, selectedText),
            onDeleteHighlight: (highlight) =>
                _deleteHighlight(context, ref, highlight),
            nextCard: next,
          );
        },
      ),
      bottomNavigationBar: current == null
          ? null
          : _DetailActionBar(
              card: current,
              previousCard: previousCard,
              nextCard: nextCard,
              onEditNote: () => _editNote(context, ref, current),
            ),
    );
  }

  void _openSharePage(BuildContext context, CardModel card) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => CardSharePage(card: card)));
  }

  Future<void> _toggleReviewStatus(
    BuildContext context,
    WidgetRef ref,
    CardModel card,
  ) async {
    try {
      final updated = await ref
          .read(contentRepositoryProvider)
          .setCardReviewStatus(card: card, mastered: !card.isMastered);
      ref.invalidate(cardsProvider);
      ref.invalidate(pendingSyncProvider);
      ref
          .read(syncControllerProvider.notifier)
          .scheduleSync(reason: 'card-review-status');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(updated.isMastered ? '已标记为已掌握' : '已取消标记，将重新进入复习'),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新复习状态失败：$error')));
    }
  }

  Future<void> _toggleFavorite(WidgetRef ref, String cardId) async {
    await ref.read(cardFavoritesProvider.notifier).toggle(cardId);
    if (ref.read(currentAccountProvider) == null) return;
    ref.invalidate(pendingSyncProvider);
    ref
        .read(syncControllerProvider.notifier)
        .scheduleSync(reason: 'card-favorite');
  }

  Future<void> _addHighlight(
    BuildContext context,
    WidgetRef ref,
    CardModel card,
    CardHighlightSection section,
    String selectedText,
  ) async {
    final text = selectedText.trim();
    if (text.isEmpty) return;
    final color = await _pickHighlightColor(context);
    if (color == null || !context.mounted) return;

    final now = DateTime.now();
    final highlight = CardHighlightModel(
      id: 'highlight-${now.microsecondsSinceEpoch}',
      accountId: card.accountId,
      cardId: card.id,
      section: section,
      selectedText: text,
      color: _colorToHex(color),
      createdAt: now,
    );
    try {
      await ref
          .read(contentRepositoryProvider)
          .addCardHighlight(highlight);
      ref.invalidate(cardHighlightsProvider(card.id));
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('高亮已保存')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存高亮失败：$error')));
    }
  }

  Future<void> _deleteHighlight(
    BuildContext context,
    WidgetRef ref,
    CardHighlightModel highlight,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除高亮'),
        content: const Text('确认删除这条高亮标注吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(contentRepositoryProvider).removeCardHighlight(
        accountId: highlight.accountId,
        highlightId: highlight.id,
      );
      ref.invalidate(cardHighlightsProvider(highlight.cardId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('高亮已删除')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除高亮失败：$error')));
    }
  }

  Future<Color?> _pickHighlightColor(BuildContext context) async {
    const colors = <Color>[
      Color(0xfff7d97a),
      Color(0xff9ed69f),
      Color(0xff8cc2ff),
      Color(0xfff3a8c8),
    ];
    return await showModalBottomSheet<Color>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择高亮颜色',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: colors
                  .map(
                    (color) => InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => Navigator.of(sheetContext).pop(color),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.26),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color.withValues(alpha: 0.45),
                            width: 1.2,
                          ),
                        ),
                        child: Icon(
                          Icons.circle,
                          color: color,
                          size: 18,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editNote(
    BuildContext context,
    WidgetRef ref,
    CardModel card,
  ) async {
    final note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppVisualColors.background,
      builder: (_) => _NoteEditorSheet(initialValue: card.noteContent),
    );
    if (note == null || !context.mounted) return;

    try {
      final updated = card.copyWith(
        noteContent: note.trim(),
        updatedAt: DateTime.now(),
      );
      await ref.read(contentRepositoryProvider).updateCard(updated);
      ref.invalidate(cardsProvider);
      ref.invalidate(collectionsProvider);
      ref.invalidate(pendingSyncProvider);
      ref
          .read(syncControllerProvider.notifier)
          .scheduleSync(reason: 'card-note-update');
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('笔记已保存，等待同步')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('笔记保存失败：$error')));
    }
  }

  Future<void> _editTags(
    BuildContext context,
    WidgetRef ref,
    CardModel card,
  ) async {
    final tags = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppVisualColors.background,
      builder: (_) => _TagManagerSheet(initialTags: card.tags),
    );
    if (!context.mounted || tags == null) return;

    final normalized = _uniqueTags(tags);
    final unchanged =
        normalized.length == card.tags.length &&
        normalized.asMap().entries.every(
          (entry) => entry.value == card.tags[entry.key],
        );
    if (unchanged) return;
    await _saveTags(context, ref, card, normalized, successMessage: '知识点已保存');
  }

  Future<void> _showTagActions(
    BuildContext context,
    WidgetRef ref,
    CardModel card,
    String tag,
  ) async {
    final action = await showModalBottomSheet<_TagAction>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tag,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppVisualColors.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑标签'),
              onTap: () => Navigator.of(sheetContext).pop(_TagAction.edit),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xffc53b32),
              ),
              title: const Text(
                '删除标签',
                style: TextStyle(color: Color(0xffc53b32)),
              ),
              onTap: () => Navigator.of(sheetContext).pop(_TagAction.delete),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;

    switch (action) {
      case _TagAction.edit:
        await _editTag(context, ref, card, tag);
      case _TagAction.delete:
        await _deleteTag(context, ref, card, tag);
    }
  }

  Future<void> _editTag(
    BuildContext context,
    WidgetRef ref,
    CardModel card,
    String tag,
  ) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _TagEditorDialog(initialValue: tag),
    );
    if (!context.mounted || value == null) return;

    final replacement = value.trim();
    if (replacement.isEmpty) return;
    final tags = _uniqueTags(
      card.tags.map((item) => item == tag ? replacement : item),
    );
    await _saveTags(context, ref, card, tags, successMessage: '标签已更新');
  }

  Future<void> _deleteTag(
    BuildContext context,
    WidgetRef ref,
    CardModel card,
    String tag,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除标签？'),
        content: Text('确定删除“$tag”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xffc53b32),
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return;
    final tags = card.tags.where((item) => item != tag).toList();
    await _saveTags(context, ref, card, tags, successMessage: '标签已删除');
  }

  Future<void> _saveTags(
    BuildContext context,
    WidgetRef ref,
    CardModel card,
    List<String> tags, {
    required String successMessage,
  }) async {
    try {
      final updated = card.copyWith(
        tags: _uniqueTags(tags),
        updatedAt: DateTime.now(),
      );
      await ref.read(contentRepositoryProvider).updateCard(updated);
      ref.invalidate(cardsProvider);
      ref.invalidate(pendingSyncProvider);
      ref
          .read(syncControllerProvider.notifier)
          .scheduleSync(reason: 'card-tag-update');
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$successMessage，等待同步')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('标签保存失败：$error')));
    }
  }

  List<String> _uniqueTags(Iterable<String> values) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final tag = value.trim();
      if (tag.isEmpty || !seen.add(tag)) continue;
      result.add(tag);
    }
    return result;
  }

  static CardModel? _findCard(List<CardModel> cards, String id) {
    for (final card in cards) {
      if (card.id == id) return card;
    }
    return null;
  }

  static List<CardModel> _orderedDeckCards(
    List<CardModel> cards,
    String folder,
  ) {
    final deckCards = cards.where((card) => card.folder == folder).toList()
      ..sort(compareCardOrder);
    return deckCards;
  }
}

class _CardReader extends StatelessWidget {
  const _CardReader({
    required this.card,
    required this.position,
    required this.total,
    required this.favorite,
    required this.highlights,
    required this.onToggleFavorite,
    required this.onToggleReviewStatus,
    required this.onTagLongPress,
    required this.onEditTags,
    required this.onAddHighlight,
    required this.onDeleteHighlight,
    required this.nextCard,
  });

  final CardModel card;
  final int position;
  final int total;
  final bool favorite;
  final List<CardHighlightModel> highlights;
  final VoidCallback onToggleFavorite;
  final VoidCallback onToggleReviewStatus;
  final ValueChanged<String> onTagLongPress;
  final VoidCallback onEditTags;
  final Future<void> Function(CardHighlightSection section, String selectedText)
  onAddHighlight;
  final Future<void> Function(CardHighlightModel highlight) onDeleteHighlight;
  final CardModel? nextCard;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              Text(
                '第 $position / $total 题',
                style: const TextStyle(
                  color: AppVisualColors.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              _DetailBadge(
                label: card.type.label,
                icon: _typeIcon(card.type),
                backgroundColor: const Color(0xfff1f2f1),
                foregroundColor: AppVisualColors.ink,
              ),
              const SizedBox(width: 8),
              _ReviewStatusButton(card: card, onPressed: onToggleReviewStatus),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            children: [
              _QuestionCard(
                card: card,
                favorite: favorite,
                highlights: highlights,
                onToggleFavorite: onToggleFavorite,
                onAddHighlight: onAddHighlight,
                onDeleteHighlight: onDeleteHighlight,
              ),
              if (card.explanation.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                _ExplanationSection(
                  explanation: card.explanation,
                  highlights: highlights,
                  onAddHighlight: onAddHighlight,
                  onDeleteHighlight: onDeleteHighlight,
                ),
              ],
              const SizedBox(height: 14),
              _KnowledgeSection(
                card: card,
                onTagLongPress: onTagLongPress,
                onEdit: onEditTags,
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _typeIcon(CardType type) => switch (type) {
    CardType.single => Icons.radio_button_checked_rounded,
    CardType.multiple => Icons.check_box_outlined,
    CardType.trueFalse => Icons.rule_rounded,
    CardType.note => Icons.lightbulb_outline_rounded,
  };
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.card,
    required this.favorite,
    required this.highlights,
    required this.onToggleFavorite,
    required this.onAddHighlight,
    required this.onDeleteHighlight,
  });

  final CardModel card;
  final bool favorite;
  final List<CardHighlightModel> highlights;
  final VoidCallback onToggleFavorite;
  final Future<void> Function(CardHighlightSection section, String selectedText)
  onAddHighlight;
  final Future<void> Function(CardHighlightModel highlight) onDeleteHighlight;

  List<CardHighlightModel> _sectionHighlights(CardHighlightSection section) {
    return highlights.where((highlight) => highlight.section == section).toList();
  }

  @override
  Widget build(BuildContext context) {
    final content = card.content.trim();
    final noteContent = card.noteContent.trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppVisualColors.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0b000000),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '题目',
                  style: TextStyle(
                    color: AppVisualColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: onToggleFavorite,
                tooltip: favorite ? '取消收藏' : '收藏',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  favorite ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 26,
                  color: favorite
                      ? const Color(0xffe1a633)
                      : AppVisualColors.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SelectableMarkdownBlock(
            section: CardHighlightSection.question,
            data: card.question,
            highlights: _sectionHighlights(CardHighlightSection.question),
            onAddHighlight: onAddHighlight,
            onDeleteHighlight: onDeleteHighlight,
            textStyle: const TextStyle(
              color: AppVisualColors.ink,
              fontSize: 15,
              height: 1.5,
            ),
          ),
          if (card.type == CardType.note && content.isNotEmpty) ...[
            const Divider(height: 22),
            const Text(
              '内容',
              style: TextStyle(
                color: AppVisualColors.ink,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            _SelectableMarkdownBlock(
              section: CardHighlightSection.content,
              data: content,
              highlights: _sectionHighlights(CardHighlightSection.content),
              onAddHighlight: onAddHighlight,
              onDeleteHighlight: onDeleteHighlight,
              noteEntries: true,
              textStyle: const TextStyle(
                color: AppVisualColors.ink,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
          if (noteContent.isNotEmpty) ...[
            const Divider(height: 22),
            const Text(
              '笔记',
              style: TextStyle(
                color: AppVisualColors.ink,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            _SelectableMarkdownBlock(
              section: CardHighlightSection.note,
              data: card.noteContent,
              highlights: _sectionHighlights(CardHighlightSection.note),
              onAddHighlight: onAddHighlight,
              onDeleteHighlight: onDeleteHighlight,
              noteEntries: true,
              textStyle: const TextStyle(
                color: AppVisualColors.ink,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
          // A legacy import can leave placeholder A-D options on a note
          // card. A quick-note card is content-based, so never render choice options
          // for it even when stale option data is still present locally.
          if (card.type != CardType.note && card.options.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...card.options.entries.map(
              (entry) => _AnswerOption(
                label: entry.key,
                value: entry.value,
                correct: card.answer.contains(entry.key),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectableMarkdownBlock extends StatefulWidget {
  const _SelectableMarkdownBlock({
    required this.section,
    required this.data,
    required this.highlights,
    required this.onAddHighlight,
    required this.onDeleteHighlight,
    this.noteEntries = false,
    this.textStyle,
  });

  final CardHighlightSection section;
  final String data;
  final List<CardHighlightModel> highlights;
  final bool noteEntries;
  final TextStyle? textStyle;
  final Future<void> Function(CardHighlightSection section, String selectedText)
  onAddHighlight;
  final Future<void> Function(CardHighlightModel highlight) onDeleteHighlight;

  @override
  State<_SelectableMarkdownBlock> createState() =>
      _SelectableMarkdownBlockState();
}

class _SelectableMarkdownBlockState extends State<_SelectableMarkdownBlock> {
  String _selectedText = '';

  List<MarkdownHighlight> get _markdownHighlights => widget.highlights
      .map(
        (highlight) => MarkdownHighlight(
          id: highlight.id,
          text: highlight.selectedText,
          color: _highlightColorFromHex(highlight.color),
        ),
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    final visibleHighlights = widget.highlights
        .where((highlight) => highlight.selectedText.trim().isNotEmpty)
        .toList();
    return SelectionArea(
      onSelectionChanged: (content) {
        final text = content?.plainText.trim() ?? '';
        if (text == _selectedText) return;
        setState(() => _selectedText = text);
      },
      contextMenuBuilder: (context, regionState) {
        final items = [...regionState.contextMenuButtonItems];
        if (_selectedText.isNotEmpty) {
          items.add(
            ContextMenuButtonItem(
              type: ContextMenuButtonType.custom,
              label: '高亮',
              onPressed: () {
                regionState.hideToolbar();
                widget.onAddHighlight(widget.section, _selectedText);
              },
            ),
          );
        }
        return AdaptiveTextSelectionToolbar.buttonItems(
          buttonItems: items,
          anchors: regionState.contextMenuAnchors,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarkdownContent(
            data: widget.data,
            selectable: false,
            noteEntries: widget.noteEntries,
            highlights: _markdownHighlights,
            textStyle: widget.textStyle,
          ),
          if (visibleHighlights.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: visibleHighlights.map((highlight) {
                final color = _highlightColorFromHex(highlight.color);
                return InputChip(
                  label: Text(
                    highlight.selectedText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  backgroundColor: color.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  side: BorderSide(color: color.withValues(alpha: 0.25)),
                  onDeleted: () => widget.onDeleteHighlight(highlight),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnswerOption extends StatelessWidget {
  const _AnswerOption({
    required this.label,
    required this.value,
    required this.correct,
  });

  final String label;
  final String value;
  final bool correct;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: correct ? const Color(0xfff4fbf8) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: correct ? const Color(0xff168d76) : AppVisualColors.line,
          width: correct ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                label,
                style: TextStyle(
                  color: correct
                      ? const Color(0xff168d76)
                      : AppVisualColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: MarkdownContent(
              data: value,
              selectable: true,
              textStyle: const TextStyle(
                color: AppVisualColors.ink,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ),
          if (correct) ...[
            const SizedBox(width: 8),
            const Icon(Icons.check_rounded, color: Color(0xff168d76), size: 24),
          ],
        ],
      ),
    );
  }
}

class _ExplanationSection extends StatelessWidget {
  const _ExplanationSection({
    required this.explanation,
    required this.highlights,
    required this.onAddHighlight,
    required this.onDeleteHighlight,
  });

  final String explanation;
  final List<CardHighlightModel> highlights;
  final Future<void> Function(CardHighlightSection section, String selectedText)
  onAddHighlight;
  final Future<void> Function(CardHighlightModel highlight) onDeleteHighlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppVisualColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '解析',
            style: TextStyle(
              color: AppVisualColors.ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _SelectableMarkdownBlock(
            section: CardHighlightSection.explanation,
            data: explanation,
            highlights: highlights,
            onAddHighlight: onAddHighlight,
            onDeleteHighlight: onDeleteHighlight,
            textStyle: const TextStyle(
              color: AppVisualColors.ink,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _KnowledgeSection extends StatelessWidget {
  const _KnowledgeSection({
    required this.card,
    required this.onTagLongPress,
    required this.onEdit,
  });

  final CardModel card;
  final ValueChanged<String> onTagLongPress;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppVisualColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '知识点',
                  style: TextStyle(
                    color: AppVisualColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('编辑'),
                style: TextButton.styleFrom(
                  foregroundColor: AppVisualColors.darkGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          if (card.tags.isNotEmpty) ...[
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...card.tags.map(
                  (tag) => _TagChip(
                    label: tag,
                    onLongPress: () => onTagLongPress(tag),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            const Text(
              '暂无知识点，点击右上角“编辑”添加',
              style: TextStyle(color: AppVisualColors.muted, fontSize: 12),
            ),
          ],
          const Padding(
            padding: EdgeInsets.only(top: 13),
            child: Divider(height: 1),
          ),
          const SizedBox(height: 9),
          Text(
            '来源：${_displaySource(card)}',
            style: const TextStyle(color: AppVisualColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _displaySource(CardModel card) {
    final source = card.source.trim();
    if (source.isNotEmpty) return source;
    final folder = card.folder.trim();
    return folder.isEmpty ? '未分类' : folder;
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, this.onLongPress});

  final String label;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xffeef7f0),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppVisualColors.darkGreen,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ),
  );
}

class _DetailBadge extends StatelessWidget {
  const _DetailBadge({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: foregroundColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: foregroundColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewStatusButton extends StatelessWidget {
  const _ReviewStatusButton({required this.card, required this.onPressed});

  final CardModel card;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final mastered = card.isMastered;
    final color = mastered
        ? AppVisualColors.darkGreen
        : const Color(0xffa85e2b);
    return Material(
      color: mastered ? const Color(0xffeef8ec) : const Color(0xfffff0e5),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                mastered ? Icons.replay_rounded : Icons.check_circle_outline,
                size: 17,
                color: color,
              ),
              const SizedBox(width: 5),
              Text(
                mastered ? '重新复习' : '标记掌握',
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailActionBar extends StatelessWidget {
  const _DetailActionBar({
    required this.card,
    required this.previousCard,
    required this.nextCard,
    required this.onEditNote,
  });

  final CardModel card;
  final CardModel? previousCard;
  final CardModel? nextCard;
  final VoidCallback onEditNote;

  @override
  Widget build(BuildContext context) {
    final buttonTextStyle = const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: previousCard == null
                  ? null
                  : () => context.pushReplacement('/cards/${previousCard!.id}'),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('上一题'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                textStyle: buttonTextStyle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onEditNote,
              icon: const Icon(Icons.note_alt_outlined, size: 18),
              label: const Text('编辑笔记'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                textStyle: buttonTextStyle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: nextCard == null
                  ? null
                  : () => context.pushReplacement('/cards/${nextCard!.id}'),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('下一题'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                textStyle: buttonTextStyle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteEditorSheet extends StatefulWidget {
  const _NoteEditorSheet({required this.initialValue});

  final String initialValue;

  @override
  State<_NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<_NoteEditorSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 22 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '编辑笔记',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: '取消编辑',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const Divider(height: 1),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 5,
            maxLines: 12,
            maxLength: 2000,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: '记录记忆提示、易错点或补充说明…',
              alignLabelWithHint: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppVisualColors.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppVisualColors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppVisualColors.green,
                  width: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(_controller.text),
              icon: const Icon(Icons.check_rounded),
              label: const Text('保存笔记'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagManagerSheet extends StatefulWidget {
  const _TagManagerSheet({required this.initialTags});

  final List<String> initialTags;

  @override
  State<_TagManagerSheet> createState() => _TagManagerSheetState();
}

class _TagManagerSheetState extends State<_TagManagerSheet> {
  late final TextEditingController _controller;
  late List<String> _tags;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _tags = _normalize(widget.initialTags);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<String> _normalize(Iterable<String> values) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final tag = value.trim();
      if (tag.isEmpty || !seen.add(tag)) continue;
      result.add(tag);
    }
    return result;
  }

  void _addTag([String? raw]) {
    final value = (raw ?? _controller.text).trim();
    if (value.isEmpty) return;
    setState(() {
      if (!_tags.contains(value)) _tags = [..._tags, value];
      _controller.clear();
    });
  }

  void _removeTag(int index) {
    setState(() => _tags = [..._tags]..removeAt(index));
  }

  Future<void> _renameTag(int index) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _TagEditorDialog(initialValue: _tags[index]),
    );
    if (!mounted || value == null) return;
    final replacement = value.trim();
    if (replacement.isEmpty) return;
    setState(() {
      final values = [..._tags]..[index] = replacement;
      _tags = _normalize(values);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 18 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '编辑知识点',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: '关闭编辑',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const Divider(height: 1),
            const SizedBox(height: 12),
            const Text(
              '点击知识点可重命名，点击右侧按钮删除',
              style: TextStyle(color: AppVisualColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 10),
            if (_tags.isEmpty)
              const Text(
                '暂无知识点，先添加一个吧',
                style: TextStyle(color: AppVisualColors.muted, fontSize: 14),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var index = 0; index < _tags.length; index++)
                    InputChip(
                      label: Text(_tags[index]),
                      onPressed: () => _renameTag(index),
                      onDeleted: () => _removeTag(index),
                      backgroundColor: const Color(0xffeef7f0),
                      side: BorderSide.none,
                      labelStyle: const TextStyle(
                        color: AppVisualColors.darkGreen,
                        fontSize: 13,
                      ),
                      deleteIconColor: AppVisualColors.darkGreen,
                    ),
                ],
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _addTag(),
              decoration: InputDecoration(
                labelText: '添加知识点',
                hintText: '输入后按回车确认',
                filled: true,
                fillColor: Colors.white,
                suffixIcon: IconButton(
                  tooltip: '添加知识点',
                  onPressed: _addTag,
                  icon: const Icon(Icons.add_rounded),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppVisualColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppVisualColors.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppVisualColors.green,
                    width: 1.4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(_tags),
                icon: const Icon(Icons.check_rounded),
                label: const Text('保存知识点'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagEditorDialog extends StatefulWidget {
  const _TagEditorDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends State<_TagEditorDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑标签'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        decoration: const InputDecoration(
          labelText: '标签名称',
          hintText: '输入标签名称',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  void _save() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }
}

String _colorToHex(Color color) {
  final value = color.toARGB32().toRadixString(16).padLeft(8, '0');
  return value.substring(2);
}

Color _highlightColorFromHex(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return const Color(0xfff7d97a);
  }
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) return const Color(0xfff7d97a);
  return Color(0xff000000 | parsed);
}
