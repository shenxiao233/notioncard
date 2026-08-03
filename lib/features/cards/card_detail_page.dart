import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_providers.dart';
import '../../core/models/card_model.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/markdown_content.dart';
import '../../core/widgets/status_badge.dart';

class CardDetailPage extends ConsumerWidget {
  const CardDetailPage({required this.cardId, super.key});

  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(cardsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('卡片详情')),
      body: cards.when(
        loading: () => const Center(child: CircularProgressIndicator()),
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
          CardModel? card;
          for (final value in values) {
            if (value.id == cardId) card = value;
          }
          if (card == null) {
            return const EmptyState(
              title: '卡片不存在',
              message: '它可能尚未同步，或已经从当前账户移除。',
              icon: Icons.style_outlined,
            );
          }
          return _CardReader(card: card);
        },
      ),
    );
  }
}

class _CardReader extends StatelessWidget {
  const _CardReader({required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatusBadge(label: card.type.label, icon: _typeIcon(card.type)),
            StatusBadge(
              label: card.suspended
                  ? '已暂停'
                  : card.isDue
                  ? '到期'
                  : '未到期',
              icon: card.suspended
                  ? Icons.pause_circle_outline
                  : card.isDue
                  ? Icons.schedule
                  : Icons.check_circle_outline,
              backgroundColor: card.isDue
                  ? scheme.secondaryContainer
                  : scheme.surfaceContainerHighest,
              foregroundColor: card.isDue
                  ? scheme.onSecondaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ],
        ),
        const SizedBox(height: 18),
        MarkdownContent(
          data: card.question,
          selectable: true,
          textStyle: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(card.folder, style: Theme.of(context).textTheme.bodyMedium),
        if (card.type == CardType.note) ...[
          const SizedBox(height: 20),
          _ReadOnlyPanel(
            title: '速记内容',
            icon: Icons.lightbulb_outline,
            child: MarkdownContent(data: card.noteContent, noteEntries: true),
          ),
        ] else ...[
          const SizedBox(height: 20),
          Text('选项', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          ...card.options.entries.map(
            (entry) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: card.answer.contains(entry.key)
                    ? scheme.primaryContainer
                    : scheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: card.answer.contains(entry.key)
                      ? scheme.primary
                      : scheme.outline,
                ),
              ),
              child: Row(
                children: [
                  Text(
                    entry.key,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MarkdownContent(data: entry.value, selectable: true),
                  ),
                  if (card.answer.contains(entry.key))
                    Icon(Icons.check_circle, color: scheme.primary),
                ],
              ),
            ),
          ),
        ],
        if (card.explanation.isNotEmpty) ...[
          const SizedBox(height: 18),
          _ReadOnlyPanel(
            title: '解析',
            icon: Icons.menu_book_outlined,
            child: MarkdownContent(data: card.explanation),
          ),
        ],
        const SizedBox(height: 22),
        Text('复习信息', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        _InfoRow(
          label: '掌握状态',
          value: card.mastery.isEmpty ? '未复习' : card.mastery,
        ),
        _InfoRow(label: '复习次数', value: '${card.reviews} 次'),
        _InfoRow(label: '下次复习', value: _dueText(card.dueAt)),
        if (card.tags.isNotEmpty)
          _InfoRow(
            label: '标签',
            value: card.tags.map((tag) => '#$tag').join('  '),
          ),
        const SizedBox(height: 12),
        StatusBadge(
          label: '只读内容，复习结果会自动保存',
          icon: Icons.lock_outline,
          backgroundColor: scheme.surfaceContainerHighest,
        ),
      ],
    );
  }

  String _dueText(DateTime dateTime) {
    if (card.isDue) return '现在到期';
    return DateFormat('yyyy年M月d日 H:mm').format(dateTime.toLocal());
  }

  IconData _typeIcon(CardType type) {
    return switch (type) {
      CardType.single => Icons.radio_button_checked,
      CardType.multiple => Icons.check_box_outlined,
      CardType.trueFalse => Icons.rule,
      CardType.note => Icons.lightbulb_outline,
    };
  }
}

class _ReadOnlyPanel extends StatelessWidget {
  const _ReadOnlyPanel({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}
