import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_providers.dart';
import '../../core/models/card_model.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/markdown_content.dart';
import 'review_queue.dart';
import 'review_settings.dart';

const _studyBackground = Color(0xfff8faf9);
const _studyGreen = Color(0xff319a70);
const _studyInk = Color(0xff1d2420);
const _studyMuted = Color(0xff7b847f);

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
  bool _speedMode = false;
  ReviewRating? _rating;
  int _completed = 0;
  final _ratingCounts = <ReviewRating, int>{};
  List<String>? _queueIds;
  bool _favorite = false;

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(cardsProvider);
    final events =
        ref.watch(reviewEventsProvider).valueOrNull ??
        const <ReviewEventModel>[];
    final settings = ref.watch(reviewSettingsProvider);

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        backgroundColor: _studyBackground,
        body: SafeArea(
          child: cards.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: _studyGreen),
            ),
            error: (error, _) =>
                _StudyError(onRetry: () => ref.invalidate(cardsProvider)),
            data: (values) {
              final limitedQueue = buildReviewQueue(
                cards: values,
                settings: settings,
                folder: widget.selectedFolder,
              );
              _queueIds ??= limitedQueue.map((card) => card.id).toList();
              final cardsById = {for (final card in values) card.id: card};
              final queue = _queueIds!
                  .map((id) => cardsById[id])
                  .whereType<CardModel>()
                  .where(
                    (card) =>
                        widget.selectedFolder == null ||
                        card.folder == widget.selectedFolder,
                  )
                  .toList();
              if (queue.isEmpty || _index >= queue.length) {
                return _Finished(completed: _completed, counts: _ratingCounts);
              }

              final card = queue[_index];
              final deckCards = values.where((item) {
                return widget.selectedFolder == null ||
                    item.folder == widget.selectedFolder;
              }).length;
              final todayTotal = queue.length + _completed;
              final masteredToday = events.where((event) {
                return _isToday(event.reviewedAt) &&
                    (event.rating == ReviewRating.good ||
                        event.rating == ReviewRating.easy);
              }).length;
              final streak = _learningStreak(events);
              final previews = {
                for (final rating in ReviewRating.values)
                  rating: _nextDueLabel(card, rating),
              };

              return _StudyCard(
                key: ValueKey(card.id),
                card: card,
                index: _index,
                total: queue.length,
                todayCompleted: _completed,
                todayTotal: todayTotal,
                deckSize: deckCards,
                masteredToday: masteredToday,
                streakDays: streak,
                selected: _selected,
                answered: _answered,
                rating: _rating,
                saving: _saving,
                speedMode: _speedMode,
                previews: previews,
                favorite: _favorite,
                onExit: _confirmExit,
                onToggleSpeedMode: () =>
                    setState(() => _speedMode = !_speedMode),
                onMore: () => _showMoreActions(queue),
                onToggleFavorite: () => setState(() => _favorite = !_favorite),
                onOpenAnswerCard: () => _showAnswerCard(queue),
                onSelect: (key) => _select(card, key),
                onSubmit: () => _submitAnswer(card),
                onRate: (rating) => _rate(card, rating),
              );
            },
          ),
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
        if (card.type == CardType.single || card.type == CardType.trueFalse) {
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
      if (!mounted) return;
      ref.invalidate(cardsProvider);
      ref.invalidate(reviewEventsProvider);
      setState(() {
        _completed++;
        _index++;
        _selected.clear();
        _answered = false;
        _rating = null;
        _favorite = false;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('复习结果保存失败，请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showAnswerCard(List<CardModel> queue) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * .68,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 14, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '答题卡',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  itemCount: queue.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, itemIndex) {
                    final item = queue[itemIndex];
                    final current = itemIndex == _index;
                    return ListTile(
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        if (!mounted || current) return;
                        setState(() {
                          _index = itemIndex;
                          _selected.clear();
                          _answered = false;
                          _rating = null;
                        });
                      },
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      tileColor: current
                          ? const Color(0xffeaf6ef)
                          : _studyBackground,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: current
                            ? _studyGreen
                            : const Color(0xffe8eeeb),
                        child: Text(
                          '${itemIndex + 1}',
                          style: TextStyle(
                            color: current
                                ? Colors.white
                                : const Color(0xff61716a),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      title: Text(
                        _plainText(item.question),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: current
                          ? const Icon(
                              Icons.radio_button_checked,
                              color: _studyGreen,
                            )
                          : const Icon(Icons.chevron_right_rounded),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMoreActions(List<CardModel> queue) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.view_list_outlined),
              title: const Text('查看答题卡'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showAnswerCard(queue);
              },
            ),
            ListTile(
              leading: const Icon(Icons.exit_to_app_outlined),
              title: const Text('退出复习'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmExit();
              },
            ),
          ],
        ),
      ),
    );
  }

  String _nextDueLabel(CardModel card, ReviewRating rating) {
    final next = ref
        .read(reviewEngineProvider)
        .review(card, rating, DateTime.now())
        .dueAt;
    final difference = next.difference(DateTime.now());
    if (difference.inMinutes < 60)
      return '${difference.inMinutes.clamp(1, 59)} 分钟';
    if (difference.inHours < 24) return '${difference.inHours} 小时';
    if (difference.inDays < 7) return '${difference.inDays} 天';
    return '${next.month}/${next.day}';
  }

  Future<void> _confirmExit() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出本轮复习？'),
        content: Text(
          _completed == 0 ? '当前卡片的答案尚未保存。' : '已完成的 $_completed 张卡片会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('继续复习'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (shouldExit == true && mounted) context.pop();
  }

  int _learningStreak(List<ReviewEventModel> events) {
    final days = events
        .map((event) => DateUtils.dateOnly(event.reviewedAt))
        .toSet();
    var cursor = DateUtils.dateOnly(DateTime.now());
    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  bool _isToday(DateTime value) {
    final today = DateTime.now();
    return value.year == today.year &&
        value.month == today.month &&
        value.day == today.day;
  }

  String _plainText(String value) => value
      .replaceAll(RegExp(r'[#*_`>\[\]]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _StudyCard extends StatelessWidget {
  const _StudyCard({
    required super.key,
    required this.card,
    required this.index,
    required this.total,
    required this.todayCompleted,
    required this.todayTotal,
    required this.deckSize,
    required this.masteredToday,
    required this.streakDays,
    required this.selected,
    required this.answered,
    required this.rating,
    required this.saving,
    required this.speedMode,
    required this.previews,
    required this.favorite,
    required this.onExit,
    required this.onToggleSpeedMode,
    required this.onMore,
    required this.onToggleFavorite,
    required this.onOpenAnswerCard,
    required this.onSelect,
    required this.onSubmit,
    required this.onRate,
  });

  final CardModel card;
  final int index;
  final int total;
  final int todayCompleted;
  final int todayTotal;
  final int deckSize;
  final int masteredToday;
  final int streakDays;
  final Set<String> selected;
  final bool answered;
  final ReviewRating? rating;
  final bool saving;
  final bool speedMode;
  final Map<ReviewRating, String> previews;
  final bool favorite;
  final VoidCallback onExit;
  final VoidCallback onToggleSpeedMode;
  final VoidCallback onMore;
  final VoidCallback onToggleFavorite;
  final VoidCallback onOpenAnswerCard;
  final ValueChanged<String> onSelect;
  final VoidCallback onSubmit;
  final ValueChanged<ReviewRating> onRate;

  @override
  Widget build(BuildContext context) {
    final progress = todayTotal == 0
        ? 0.0
        : (todayCompleted / todayTotal).clamp(0.0, 1.0);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 0),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: onExit,
                    tooltip: '退出复习',
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Expanded(
                    child: Text(
                      '复习中',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: _studyInk,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: onToggleSpeedMode,
                    icon: Icon(
                      Icons.bolt_rounded,
                      size: 17,
                      color: speedMode ? _studyGreen : _studyMuted,
                    ),
                    label: const Text('速记模式'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: speedMode ? _studyGreen : _studyInk,
                      side: BorderSide(
                        color: speedMode
                            ? _studyGreen
                            : const Color(0xffe1e7e3),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  IconButton(
                    onPressed: onMore,
                    tooltip: '更多操作',
                    icon: const Icon(Icons.more_horiz_rounded, size: 25),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    '今日进度 ',
                    style: TextStyle(fontSize: 19, color: _studyInk),
                  ),
                  Text(
                    '$todayCompleted / $todayTotal',
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w700,
                      color: _studyGreen,
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      card.folder.isEmpty ? '全部牌组' : card.folder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _studyInk,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: progress,
                  backgroundColor: const Color(0xffe4e9e6),
                  valueColor: const AlwaysStoppedAnimation(_studyGreen),
                ),
              ),
              const SizedBox(height: 5),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '总词量 $deckSize',
                  style: const TextStyle(fontSize: 13, color: _studyMuted),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StudyStat(
                      icon: Icons.local_fire_department_outlined,
                      text: '已连续学习 $streakDays 天',
                      color: const Color(0xffe98658),
                    ),
                  ),
                  Expanded(
                    child: _StudyStat(
                      icon: Icons.bar_chart_rounded,
                      text: '今日已掌握 $masteredToday 个',
                      color: _studyGreen,
                      alignEnd: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0d000000),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: _CardBody(
                card: card,
                selected: selected,
                answered: answered,
                speedMode: speedMode,
                favorite: favorite,
                onToggleFavorite: onToggleFavorite,
                onOpenAnswerCard: onOpenAnswerCard,
                onSelect: onSelect,
              ),
            ),
          ),
        ),
        if (card.type != CardType.note && !answered)
          _SubmitBar(
            enabled: selected.isNotEmpty,
            favorite: favorite,
            onToggleFavorite: onToggleFavorite,
            onOpenAnswerCard: onOpenAnswerCard,
            onSubmit: onSubmit,
          )
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
}

class _StudyStat extends StatelessWidget {
  const _StudyStat({
    required this.icon,
    required this.text,
    required this.color,
    this.alignEnd = false,
  });

  final IconData icon;
  final String text;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: alignEnd
        ? MainAxisAlignment.end
        : MainAxisAlignment.start,
    children: [
      Icon(icon, color: color, size: 21),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _studyInk, fontSize: 14),
        ),
      ),
    ],
  );
}

class _CardBody extends StatefulWidget {
  const _CardBody({
    required this.card,
    required this.selected,
    required this.answered,
    required this.speedMode,
    required this.favorite,
    required this.onToggleFavorite,
    required this.onOpenAnswerCard,
    required this.onSelect,
  });

  final CardModel card;
  final Set<String> selected;
  final bool answered;
  final bool speedMode;
  final bool favorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onOpenAnswerCard;
  final ValueChanged<String> onSelect;

  @override
  State<_CardBody> createState() => _CardBodyState();
}

class _CardBodyState extends State<_CardBody> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final isCorrect =
        widget.selected.length == card.answer.length &&
        widget.selected.containsAll(card.answer);
    final titleSize = widget.speedMode ? 23.0 : 27.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: MarkdownContent(
                data: card.question,
                textStyle: TextStyle(
                  color: _studyInk,
                  fontSize: titleSize,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (card.tags.isNotEmpty)
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 5,
                runSpacing: 5,
                children: card.tags
                    .take(3)
                    .map((tag) => _Tag(text: tag))
                    .toList(),
              ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            onPressed: () => Feedback.forTap(context),
            tooltip: '播放发音',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            icon: const Icon(
              Icons.volume_up_outlined,
              color: _studyMuted,
              size: 25,
            ),
          ),
        ),
        const Divider(height: 20, color: Color(0xffedf0ee)),
        if (card.type == CardType.note) ...[
          _ReviewContent(data: card.noteContent, expanded: _expanded),
          if (card.noteContent.trim().isNotEmpty)
            _ExpandButton(
              expanded: _expanded,
              onTap: () => setState(() => _expanded = !_expanded),
            ),
        ] else ...[
          const Text(
            '请选择答案',
            style: TextStyle(fontSize: 15, color: _studyMuted),
          ),
          const SizedBox(height: 10),
          ...card.options.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _OptionTile(
                entry: entry,
                selected: widget.selected.contains(entry.key),
                answered: widget.answered,
                isCorrect: card.answer.contains(entry.key),
                onTap: () => widget.onSelect(entry.key),
              ),
            ),
          ),
          if (widget.answered) ...[
            const SizedBox(height: 2),
            Text(
              isCorrect ? '回答正确' : '再看一下正确答案',
              style: TextStyle(
                color: isCorrect ? _studyGreen : const Color(0xffc53b32),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (widget.answered && card.explanation.isNotEmpty) ...[
            const SizedBox(height: 18),
            _ReviewContent(data: card.explanation, expanded: true),
          ],
        ],
        const SizedBox(height: 12),
        Text(
          '来源：${card.folder.isEmpty ? '未分类' : card.folder}',
          style: const TextStyle(color: Color(0xffa4aca7), fontSize: 13),
        ),
      ],
    );
  }
}

class _ReviewContent extends StatelessWidget {
  const _ReviewContent({required this.data, required this.expanded});

  final String data;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final content = MarkdownContent(
      data: data,
      noteEntries: true,
      textStyle: const TextStyle(color: _studyInk, fontSize: 17, height: 1.55),
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      constraints: expanded ? null : const BoxConstraints(maxHeight: 220),
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: content,
    );
  }
}

class _ExpandButton extends StatelessWidget {
  const _ExpandButton({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton.icon(
      onPressed: onTap,
      icon: Icon(
        expanded
            ? Icons.keyboard_arrow_up_rounded
            : Icons.keyboard_arrow_down_rounded,
        color: _studyGreen,
      ),
      label: Text(
        expanded ? '收起全文' : '展开全文',
        style: const TextStyle(color: _studyGreen, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xfffff0ef),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xffc65b54),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
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
    final wrong = answered && selected && !isCorrect;
    final correct = answered && isCorrect;
    final color = correct
        ? _studyGreen
        : wrong
        ? const Color(0xffc53b32)
        : const Color(0xffdbe4df);
    return InkWell(
      onTap: answered ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: correct
              ? const Color(0xffeef8ec)
              : wrong
              ? const Color(0xfffff1ef)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected || correct || wrong
                ? color
                : const Color(0xffe8eeeb),
            width: selected || correct || wrong ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              correct
                  ? Icons.check_circle
                  : wrong
                  ? Icons.cancel
                  : selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected || correct || wrong ? color : _studyMuted,
              size: 21,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: MarkdownContent(
                data: entry.value,
                textStyle: const TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  color: _studyInk,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({
    required this.enabled,
    required this.favorite,
    required this.onToggleFavorite,
    required this.onOpenAnswerCard,
    required this.onSubmit,
  });

  final bool enabled;
  final bool favorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onOpenAnswerCard;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: onToggleFavorite,
            tooltip: '收藏',
            icon: Icon(
              favorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: favorite ? const Color(0xffe1a633) : _studyMuted,
            ),
          ),
          IconButton(
            onPressed: onOpenAnswerCard,
            tooltip: '答题卡',
            icon: const Icon(Icons.view_list_outlined, color: _studyMuted),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: FilledButton(
              onPressed: enabled ? onSubmit : null,
              style: FilledButton.styleFrom(
                backgroundColor: _studyGreen,
                minimumSize: const Size.fromHeight(49),
              ),
              child: const Text('提交答案'),
            ),
          ),
        ],
      ),
    ),
  );
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
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _RatingButton(
                  value: ReviewRating.again,
                  nextDue: previews[ReviewRating.again] ?? '',
                  selected: rating == ReviewRating.again,
                  saving: saving,
                  onTap: () => onRate(ReviewRating.again),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RatingButton(
                  value: ReviewRating.hard,
                  nextDue: previews[ReviewRating.hard] ?? '',
                  selected: rating == ReviewRating.hard,
                  saving: saving,
                  onTap: () => onRate(ReviewRating.hard),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          _RatingButton(
            value: ReviewRating.good,
            nextDue: previews[ReviewRating.good] ?? '',
            selected: rating == ReviewRating.good,
            saving: saving,
            onTap: () => onRate(ReviewRating.good),
            fullWidth: true,
          ),
          const SizedBox(height: 9),
          _RatingButton(
            value: ReviewRating.easy,
            nextDue: previews[ReviewRating.easy] ?? '',
            selected: rating == ReviewRating.easy,
            saving: saving,
            onTap: () => onRate(ReviewRating.easy),
            fullWidth: true,
          ),
        ],
      ),
    ),
  );
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.value,
    required this.nextDue,
    required this.selected,
    required this.saving,
    required this.onTap,
    this.fullWidth = false,
  });

  final ReviewRating value;
  final String nextDue;
  final bool selected;
  final bool saving;
  final VoidCallback onTap;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final colors = switch (value) {
      ReviewRating.again => (const Color(0xffffe9e8), const Color(0xffb63c3b)),
      ReviewRating.hard => (const Color(0xfffff0e3), const Color(0xffb56b26)),
      ReviewRating.good => (_studyGreen, Colors.white),
      ReviewRating.easy => (const Color(0xffeaf5f7), const Color(0xff2d8591)),
    };
    return Material(
      color: selected ? colors.$2 : colors.$1,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: saving ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: fullWidth ? double.infinity : null,
          height: fullWidth ? 64 : 82,
          child: saving && selected
              ? const Center(
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      value.label,
                      style: TextStyle(
                        color: selected ? Colors.white : colors.$2,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      nextDue,
                      style: TextStyle(
                        color: selected ? Colors.white : colors.$2,
                        fontSize: 15,
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

class _Finished extends StatelessWidget {
  const _Finished({required this.completed, required this.counts});

  final int completed;
  final Map<ReviewRating, int> counts;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: EmptyState(
        title: completed == 0 ? '当前没有待复习卡片' : '本轮复习完成',
        message: completed == 0
            ? '可以先同步内容，稍后再回来查看新的复习任务。'
            : '完成 $completed 张卡片，今天的学习节奏保持得不错。',
        icon: completed == 0 ? Icons.event_available_outlined : Icons.task_alt,
        action: FilledButton.icon(
          onPressed: () => context.go('/review'),
          icon: const Icon(Icons.home_outlined),
          label: const Text('返回复习首页'),
        ),
      ),
    ),
  );
}

class _StudyError extends StatelessWidget {
  const _StudyError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
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
