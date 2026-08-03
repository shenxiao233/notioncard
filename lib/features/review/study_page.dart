import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_providers.dart';
import '../../core/models/card_model.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/markdown_content.dart';
import '../../core/widgets/stat_tile.dart';
import '../../core/widgets/status_badge.dart';

class StudyPage extends ConsumerStatefulWidget {
  const StudyPage({this.selectedFolder, super.key});

  final String? selectedFolder;

  @override
  ConsumerState<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends ConsumerState<StudyPage> {
  int _index = 0;
  final _selected = <String>{};
  bool _answered = false;
  bool _saving = false;
  ReviewRating? _rating;
  int _completed = 0;
  final _ratingCounts = <ReviewRating, int>{};
  List<String>? _queueIds;

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(cardsProvider);
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('复习中'),
          leading: IconButton(
            onPressed: _confirmExit,
            tooltip: '退出复习',
            icon: const Icon(Icons.close),
          ),
        ),
        body: cards.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              _StudyError(onRetry: () => ref.invalidate(cardsProvider)),
          data: (values) {
            final due = values
                .where(
                  (card) =>
                      card.isDue &&
                      (widget.selectedFolder == null ||
                          card.folder == widget.selectedFolder),
                )
                .toList();
            _queueIds ??= due.map((card) => card.id).toList();
            final cardsById = {for (final card in values) card.id: card};
            final queue = _queueIds!
                .map((id) => cardsById[id])
                .whereType<CardModel>()
                .toList();
            if (queue.isEmpty || _index >= queue.length) {
              return _Finished(completed: _completed, counts: _ratingCounts);
            }
            final card = queue[_index];
            final previews = {
              for (final rating in ReviewRating.values)
                rating: _nextDueLabel(card, rating),
            };
            return _StudyCard(
              card: card,
              index: _index,
              total: queue.length,
              selected: _selected,
              answered: _answered,
              rating: _rating,
              saving: _saving,
              previews: previews,
              onSelect: (key) => _select(card, key),
              onSubmit: () => _submitAnswer(card),
              onRate: (rating) => _rate(card, rating),
            );
          },
        ),
      ),
    );
  }

  void _select(CardModel card, String key) {
    if (_answered) return;
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        if (card.type == CardType.single) {
          _selected.clear();
        }
        _selected.add(key);
      }
    });
  }

  void _submitAnswer(CardModel card) {
    if (_selected.isEmpty) return;
    setState(() => _answered = true);
  }

  Future<void> _rate(CardModel card, ReviewRating rating) async {
    if (_saving) return;
    if (!_answered && card.type != CardType.note) return;
    final now = DateTime.now();
    final calculation = ref
        .read(reviewEngineProvider)
        .review(card, rating, now);
    final updated = card.copyWith(
      dueAt: calculation.dueAt,
      updatedAt: now,
      reviews: card.reviews + 1,
      mastery: calculation.mastery,
      fsrs: calculation.fsrs,
    );
    final account = ref.read(currentAccountProvider);
    if (account == null) return;
    setState(() {
      _saving = true;
      _rating = rating;
    });
    final event = ReviewEventModel(
      id: '${card.id}-${now.microsecondsSinceEpoch}',
      accountId: account.id,
      cardId: card.id,
      question: card.question,
      folder: card.folder,
      rating: rating,
      reviewedAt: now,
      nextDue: calculation.dueAt,
    );
    try {
      await ref
          .read(contentRepositoryProvider)
          .saveReview(card: updated, event: event);
      _ratingCounts[rating] = (_ratingCounts[rating] ?? 0) + 1;
      if (mounted) {
        ref.invalidate(cardsProvider);
        ref.invalidate(reviewEventsProvider);
        setState(() {
          _completed++;
          _index++;
          _selected.clear();
          _answered = false;
          _rating = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _rating = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('复习结果保存失败，当前卡片仍保留，可以重试。'),
            action: SnackBarAction(label: '知道了', onPressed: () {}),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _nextDueLabel(CardModel card, ReviewRating rating) {
    final next = ref
        .read(reviewEngineProvider)
        .review(card, rating, DateTime.now())
        .dueAt;
    final difference = next.difference(DateTime.now());
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes.clamp(1, 59)} 分钟';
    }
    if (difference.inHours < 24) return '${difference.inHours} 小时';
    if (difference.inDays < 7) return '${difference.inDays} 天';
    return '${next.month}/${next.day}';
  }

  Future<void> _confirmExit() async {
    if (!mounted) return;
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出本轮复习？'),
        content: Text(
          _completed == 0 ? '当前卡片的答案尚未保存。' : '已完成的 $_completed 张卡片会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('继续复习'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (shouldExit == true && mounted) context.pop();
  }
}

class _StudyCard extends StatelessWidget {
  const _StudyCard({
    required this.card,
    required this.index,
    required this.total,
    required this.selected,
    required this.answered,
    required this.rating,
    required this.saving,
    required this.previews,
    required this.onSelect,
    required this.onSubmit,
    required this.onRate,
  });

  final CardModel card;
  final int index;
  final int total;
  final Set<String> selected;
  final bool answered;
  final ReviewRating? rating;
  final bool saving;
  final Map<ReviewRating, String> previews;
  final ValueChanged<String> onSelect;
  final VoidCallback onSubmit;
  final ValueChanged<ReviewRating> onRate;

  @override
  Widget build(BuildContext context) {
    final isCorrect =
        selected.length == card.answer.length &&
        selected.containsAll(card.answer);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    '${index + 1} / $total',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      card.folder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  StatusBadge(
                    label: card.type.label,
                    icon: _typeIcon(card.type),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: total == 0 ? 0 : (index + 1) / total,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            children: [
              MarkdownContent(
                data: card.question,
                selectable: true,
                textStyle: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontSize: 20, height: 1.45),
              ),
              if (card.type == CardType.note) ...[
                const SizedBox(height: 18),
                _ContentPanel(
                  icon: Icons.lightbulb_outline,
                  child: MarkdownContent(
                    data: card.noteContent,
                    noteEntries: true,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 20),
                ...card.options.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _OptionTile(
                      entry: entry,
                      selected: selected.contains(entry.key),
                      answered: answered,
                      isCorrect: card.answer.contains(entry.key),
                      onTap: () => onSelect(entry.key),
                    ),
                  ),
                ),
                if (answered) ...[
                  const SizedBox(height: 8),
                  _AnswerFeedback(isCorrect: isCorrect),
                ],
              ],
              if (answered || card.type == CardType.note) ...[
                if (card.explanation.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _ContentPanel(
                    icon: Icons.menu_book_outlined,
                    title: '解析',
                    child: MarkdownContent(data: card.explanation),
                  ),
                ],
                const SizedBox(height: 12),
                Text('根据记忆感受评分', style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (card.type != CardType.note && !answered)
          _SubmitBar(enabled: selected.isNotEmpty, onSubmit: onSubmit)
        else
          _RatingBar(
            rating: rating,
            saving: saving,
            previews: previews,
            onRate: onRate,
          ),
      ],
    );
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

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.entry,
    required this.selected,
    required this.answered,
    required this.isCorrect,
    required this.onTap,
  });

  final MapEntry<String, String> entry;
  final bool selected;
  final bool answered;
  final bool isCorrect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isWrongSelection = answered && selected && !isCorrect;
    final isCorrectAnswer = answered && isCorrect;
    final borderColor = isCorrectAnswer
        ? scheme.primary
        : isWrongSelection
        ? scheme.error
        : selected
        ? scheme.primary
        : scheme.outline;
    final backgroundColor = isCorrectAnswer
        ? scheme.primaryContainer
        : isWrongSelection
        ? scheme.errorContainer
        : selected
        ? scheme.primaryContainer.withValues(alpha: 0.6)
        : scheme.surface;
    return Semantics(
      button: true,
      selected: selected,
      label: '选项 ${entry.key}：${entry.value}',
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: answered ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: borderColor,
                width: selected || answered ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: borderColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    entry.key,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: borderColor),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MarkdownContent(data: entry.value, selectable: false),
                ),
                const SizedBox(width: 8),
                Icon(
                  isCorrectAnswer
                      ? Icons.check_circle
                      : isWrongSelection
                      ? Icons.cancel
                      : selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: borderColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnswerFeedback extends StatelessWidget {
  const _AnswerFeedback({required this.isCorrect});

  final bool isCorrect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isCorrect ? scheme.primaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isCorrect ? Icons.check_circle_outline : Icons.info_outline,
            color: isCorrect
                ? scheme.onPrimaryContainer
                : scheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Text(
            isCorrect ? '回答正确' : '再想一想，已标出正确答案',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: isCorrect
                  ? scheme.onPrimaryContainer
                  : scheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentPanel extends StatelessWidget {
  const _ContentPanel({required this.icon, required this.child, this.title});

  final IconData icon;
  final String? title;
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
          if (title != null) ...[
            Row(
              children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(title!, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }
}

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({required this.enabled, required this.onSubmit});

  final bool enabled;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return _BottomActionSurface(
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: enabled ? onSubmit : null,
          icon: const Icon(Icons.check),
          label: const Text('提交答案'),
        ),
      ),
    );
  }
}

class _RatingBar extends StatelessWidget {
  const _RatingBar({
    required this.rating,
    required this.saving,
    required this.previews,
    required this.onRate,
  });

  final ReviewRating? rating;
  final bool saving;
  final Map<ReviewRating, String> previews;
  final ValueChanged<ReviewRating> onRate;

  @override
  Widget build(BuildContext context) {
    return _BottomActionSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('选择记忆难度', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final buttons = ReviewRating.values
                  .map(
                    (value) => _RatingButton(
                      value: value,
                      nextDue: previews[value]!,
                      selected: rating == value,
                      saving: saving,
                      onTap: () => onRate(value),
                    ),
                  )
                  .toList();
              if (constraints.maxWidth < 360) {
                final width = (constraints.maxWidth - 6) / 2;
                return Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: buttons
                      .map((button) => SizedBox(width: width, child: button))
                      .toList(),
                );
              }
              return Row(
                children: [
                  for (var index = 0; index < buttons.length; index++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: index == buttons.length - 1 ? 0 : 6,
                        ),
                        child: buttons[index],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.value,
    required this.nextDue,
    required this.selected,
    required this.saving,
    required this.onTap,
  });

  final ReviewRating value;
  final String nextDue;
  final bool selected;
  final bool saving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (value) {
      ReviewRating.again => scheme.error,
      ReviewRating.hard => scheme.secondary,
      ReviewRating.good => scheme.primary,
      ReviewRating.easy => const Color(0xff48795e),
    };
    return Semantics(
      button: true,
      label: '${value.label}，${value.description}，$nextDue后复习',
      child: Material(
        color: selected ? color : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: saving ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 58,
            child: saving && selected
                ? const Center(
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        value.label,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: selected ? Colors.white : color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        nextDue,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: selected ? Colors.white : color),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _BottomActionSurface extends StatelessWidget {
  const _BottomActionSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: child,
        ),
      ),
    );
  }
}

class _Finished extends StatelessWidget {
  const _Finished({required this.completed, required this.counts});

  final int completed;
  final Map<ReviewRating, int> counts;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
      children: [
        EmptyState(
          title: completed == 0 ? '当前没有待复习卡片' : '本轮复习完成',
          message: completed == 0
              ? '可以先同步内容，或稍后再回来查看新的复习任务。'
              : '完成 $completed 张卡片，今天的学习节奏保持得不错。',
          icon: completed == 0
              ? Icons.event_available_outlined
              : Icons.task_alt,
        ),
        if (completed > 0) ...[
          const SizedBox(height: 8),
          Row(
            children: ReviewRating.values
                .map(
                  (rating) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: rating == ReviewRating.easy ? 0 : 6,
                      ),
                      child: StatTile(
                        label: rating.label,
                        value: '${counts[rating] ?? 0}',
                        color: _ratingColor(context, rating),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => context.go('/review'),
          icon: const Icon(Icons.home_outlined),
          label: const Text('返回复习首页'),
        ),
        if (completed > 0) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => context.go('/review/history'),
            icon: const Icon(Icons.insights_outlined),
            label: const Text('查看复习历史'),
          ),
        ],
      ],
    );
  }

  Color _ratingColor(BuildContext context, ReviewRating rating) {
    final scheme = Theme.of(context).colorScheme;
    return switch (rating) {
      ReviewRating.again => scheme.error,
      ReviewRating.hard => scheme.secondary,
      ReviewRating.good => scheme.primary,
      ReviewRating.easy => const Color(0xff48795e),
    };
  }
}

class _StudyError extends StatelessWidget {
  const _StudyError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      title: '复习数据加载失败',
      message: '请检查本地内容或网络状态，然后重试。',
      icon: Icons.cloud_off_outlined,
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('重试'),
      ),
    );
  }
}
