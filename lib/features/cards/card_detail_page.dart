import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_providers.dart';
import '../../core/models/card_model.dart';
import '../../core/widgets/app_visuals.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/markdown_content.dart';
import '../review/review_queue.dart';

class CardDetailPage extends ConsumerWidget {
  const CardDetailPage({required this.cardId, super.key});

  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(cardsProvider);
    final values = cards.valueOrNull ?? const <CardModel>[];
    final current = _findCard(values, cardId);
    final deckCards = current == null
        ? const <CardModel>[]
        : _orderedDeckCards(values, current.folder);
    final currentIndex = current == null
        ? -1
        : deckCards.indexWhere((card) => card.id == current.id);
    final nextCard = currentIndex >= 0 && currentIndex + 1 < deckCards.length
        ? deckCards[currentIndex + 1]
        : null;

    return Scaffold(
      backgroundColor: AppVisualColors.background,
      appBar: AppBar(
        title: const Text(
          '题目详情',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
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
          return _CardReader(
            card: card,
            position: index < 0 ? 1 : index + 1,
            total: cardsInDeck.isEmpty ? 1 : cardsInDeck.length,
            nextCard: next,
          );
        },
      ),
      bottomNavigationBar: current == null
          ? null
          : _DetailActionBar(card: current, nextCard: nextCard),
    );
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
    required this.nextCard,
  });

  final CardModel card;
  final int position;
  final int total;
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
                  fontSize: 15,
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
              _DetailBadge(
                label: card.suspended
                    ? '已暂停'
                    : card.isDue
                    ? '今日到期'
                    : '未到期',
                icon: card.suspended
                    ? Icons.pause_circle_outline
                    : Icons.schedule_rounded,
                backgroundColor: card.isDue
                    ? const Color(0xfffff0e5)
                    : const Color(0xffeef8ec),
                foregroundColor: card.isDue
                    ? const Color(0xffa85e2b)
                    : AppVisualColors.darkGreen,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            children: [
              _QuestionCard(card: card),
              if (card.explanation.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                _ExplanationSection(explanation: card.explanation),
              ],
              if (card.tags.isNotEmpty || card.folder.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                _KnowledgeSection(card: card),
              ],
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
  const _QuestionCard({required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context) {
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
          const Text(
            '题目',
            style: TextStyle(
              color: AppVisualColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          MarkdownContent(
            data: card.question,
            selectable: true,
            textStyle: const TextStyle(
              color: AppVisualColors.ink,
              fontSize: 16,
              height: 1.55,
            ),
          ),
          if (card.type == CardType.note &&
              card.noteContent.trim().isNotEmpty) ...[
            const Divider(height: 22),
            const Text(
              '内容',
              style: TextStyle(
                color: AppVisualColors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            MarkdownContent(
              data: card.noteContent,
              selectable: true,
              noteEntries: true,
              textStyle: const TextStyle(
                color: AppVisualColors.ink,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ] else if (card.options.isNotEmpty) ...[
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
                  fontSize: 16,
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
                fontSize: 16,
                height: 1.4,
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
  const _ExplanationSection({required this.explanation});

  final String explanation;

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
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          MarkdownContent(
            data: explanation,
            selectable: true,
            textStyle: const TextStyle(
              color: AppVisualColors.ink,
              fontSize: 15,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _KnowledgeSection extends StatelessWidget {
  const _KnowledgeSection({required this.card});

  final CardModel card;

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
          const Text(
            '知识点',
            style: TextStyle(
              color: AppVisualColors.ink,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...card.tags.map((tag) => _TagChip(label: tag)),
              if (card.folder.trim().isNotEmpty)
                _TagChip(label: card.folder, muted: true),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 13),
            child: Divider(height: 1),
          ),
          const SizedBox(height: 9),
          Text(
            '来源：${card.folder.trim().isEmpty ? '未分类' : card.folder}',
            style: const TextStyle(color: AppVisualColors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: muted ? const Color(0xfff4f5f4) : const Color(0xffeef7f0),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: muted ? AppVisualColors.muted : AppVisualColors.darkGreen,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
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

class _DetailActionBar extends StatelessWidget {
  const _DetailActionBar({required this.card, required this.nextCard});

  final CardModel card;
  final CardModel? nextCard;

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
              onPressed: () => _startReview(context),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('加入复习'),
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
              onPressed: () => _showNote(context),
              icon: const Icon(Icons.note_alt_outlined, size: 18),
              label: const Text('笔记'),
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

  void _startReview(BuildContext context) {
    final folder = card.folder.trim();
    final route = folder.isEmpty
        ? '/review/study'
        : '/review/study?folder=${Uri.encodeQueryComponent(folder)}';
    context.push(route);
  }

  void _showNote(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppVisualColors.background,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '笔记',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Divider(height: 1),
                const SizedBox(height: 14),
                MarkdownContent(
                  data: card.noteContent.trim().isEmpty
                      ? '这张卡片还没有笔记。'
                      : card.noteContent,
                  selectable: true,
                  noteEntries: true,
                  textStyle: const TextStyle(fontSize: 15, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
