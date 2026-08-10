import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_providers.dart';
import '../../core/models/card_model.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/markdown_content.dart';
import 'review_queue.dart';
import 'review_settings.dart';
import 'review_session.dart';

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
  ReviewRating? _rating;
  final _completedCardIds = <String>{};
  final _ratingCounts = <ReviewRating, int>{};
  List<String>? _queueIds;
  String? _sessionKey;
  Future<void> _sessionWrite = Future<void>.value();
  bool _sessionInitialized = false;
  bool _sessionAutonomousLearning = false;
  bool _favorite = false;

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(cardsProvider);
    final settings = ref.watch(reviewSettingsProvider);
    final reviewEvents = ref.watch(reviewEventsProvider);

    return PopScope<void>(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _scheduleSessionSync();
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
              if (!_sessionInitialized &&
                  reviewEvents.valueOrNull == null &&
                  !reviewEvents.hasError) {
                return const Center(
                  child: CircularProgressIndicator(color: _studyGreen),
                );
              }
              final generatedQueue = buildReviewQueue(
                cards: values,
                settings: settings,
                folder: widget.selectedFolder,
              );
              final cardsById = {for (final card in values) card.id: card};
              _initializeSession(
                generatedQueue: generatedQueue,
                cardsById: cardsById,
                events: reviewEvents.valueOrNull,
                autonomousLearning: settings.autonomousLearning,
              );
              final queueIds = _reconcileQueue(
                cardsById: cardsById,
                generatedQueue: generatedQueue,
                events: reviewEvents.valueOrNull,
                autonomousLearning: settings.autonomousLearning,
              );
              final queue = queueIds
                  .map((id) => cardsById[id])
                  .whereType<CardModel>()
                  .toList();
              final completed = _completedCardIds
                  .where((id) => queue.any((card) => card.id == id))
                  .length;
              if (queue.isEmpty || _index >= queue.length) {
                return _Finished(completed: completed, counts: _ratingCounts);
              }

              final card = queue[_index];
              final todayTotal = queue.length;
              final previews = {
                for (final rating in ReviewRating.values)
                  rating: _nextDueLabel(card, rating),
              };

              return _StudyCard(
                key: ValueKey(card.id),
                card: card,
                todayCompleted: completed,
                todayTotal: todayTotal,
                selected: _selected,
                answered: _answered,
                rating: _rating,
                saving: _saving,
                previews: previews,
                favorite: _favorite,
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

  void _initializeSession({
    required List<CardModel> generatedQueue,
    required Map<String, CardModel> cardsById,
    required List<ReviewEventModel>? events,
    required bool autonomousLearning,
  }) {
    if (_sessionInitialized) return;
    final account = ref.read(currentAccountProvider);
    if (account == null) return;

    _sessionKey = reviewStudySessionKey(account.id, widget.selectedFolder);
    final snapshot = loadReviewSession(
      ref.read(sharedPreferencesProvider),
      account.id,
      widget.selectedFolder,
    );
    final generatedQueueIds = generatedQueue.map((card) => card.id).toList();
    final savedQueueIds = snapshot?.queueIds ?? const <String>[];
    final queueIds = switch (snapshot?.autonomousLearning) {
      true when !autonomousLearning => generatedQueueIds,
      _ when autonomousLearning => _appendQueueIds(
        savedQueueIds,
        generatedQueueIds,
      ),
      _ => snapshot == null ? generatedQueueIds : savedQueueIds,
    };
    _queueIds = _orderedActiveQueueIds(queueIds, cardsById);
    _sessionAutonomousLearning = autonomousLearning;
    final completedIds = {
      ...?snapshot?.completedIds,
      ..._completedIdsFromEvents(events, _queueIds!, cardsById),
    };
    _completedCardIds.addAll(completedIds.where(_queueIds!.toSet().contains));
    _index = _firstPendingIndex(_queueIds!, _completedCardIds);
    _sessionInitialized = true;
    unawaited(_persistSession());
  }

  List<String> _reconcileQueue({
    required Map<String, CardModel> cardsById,
    required List<CardModel> generatedQueue,
    required List<ReviewEventModel>? events,
    required bool autonomousLearning,
  }) {
    final currentQueueIds = _queueIds ?? const <String>[];
    final generatedQueueIds = generatedQueue.map((card) => card.id).toList();
    final modeChanged = _sessionAutonomousLearning != autonomousLearning;
    final desiredQueueIds = autonomousLearning
        ? _appendQueueIds(currentQueueIds, generatedQueueIds)
        : modeChanged
        ? generatedQueueIds
        : currentQueueIds;
    final activeQueueIds = _orderedActiveQueueIds(desiredQueueIds, cardsById);
    final changed =
        activeQueueIds.length != currentQueueIds.length ||
        activeQueueIds.asMap().entries.any(
          (entry) => entry.value != currentQueueIds[entry.key],
        );
    _sessionAutonomousLearning = autonomousLearning;
    if (changed) {
      _queueIds = activeQueueIds;
      _completedCardIds.retainAll(activeQueueIds.toSet());
      _completedCardIds.addAll(
        _completedIdsFromEvents(events, activeQueueIds, cardsById),
      );
      _index = _firstPendingIndex(activeQueueIds, _completedCardIds);
      unawaited(_persistSession());
    } else if (modeChanged) {
      unawaited(_persistSession());
    }
    return activeQueueIds;
  }

  List<String> _appendQueueIds(List<String> current, List<String> additions) {
    final result = [...current];
    final existing = result.toSet();
    for (final id in additions) {
      if (existing.add(id)) result.add(id);
    }
    return result;
  }

  List<String> _activeQueueIds(
    List<String> queueIds,
    Map<String, CardModel> cardsById,
  ) {
    return queueIds.where((id) {
      final card = cardsById[id];
      return card != null &&
          (widget.selectedFolder == null ||
              card.folder.trim() == widget.selectedFolder!.trim());
    }).toList();
  }

  List<String> _orderedActiveQueueIds(
    List<String> queueIds,
    Map<String, CardModel> cardsById,
  ) {
    final active = _activeQueueIds(queueIds, cardsById);
    active.sort((left, right) {
      final leftCard = cardsById[left];
      final rightCard = cardsById[right];
      if (leftCard == null || rightCard == null) return 0;
      return compareReviewCardOrder(leftCard, rightCard);
    });
    return active;
  }

  Set<String> _completedIdsFromEvents(
    List<ReviewEventModel>? events,
    List<String> queueIds,
    Map<String, CardModel> cardsById,
  ) {
    if (events == null) return <String>{};
    final queueSet = queueIds.toSet();
    final now = DateTime.now();
    return events
        .where(
          (event) =>
              (widget.selectedFolder == null ||
                  event.folder.trim() == widget.selectedFolder!.trim()) &&
              _sameDay(event.reviewedAt, now) &&
              queueSet.contains(event.cardId) &&
              cardsById.containsKey(event.cardId),
        )
        .map((event) => event.cardId)
        .toSet();
  }

  int _firstPendingIndex(List<String> queueIds, Set<String> completedIds) {
    final index = queueIds.indexWhere((id) => !completedIds.contains(id));
    return index == -1 ? queueIds.length : index;
  }

  Future<void> _persistSession() {
    final key = _sessionKey;
    final queueIds = _queueIds;
    if (key == null || queueIds == null) return Future<void>.value();
    final payload = jsonEncode({
      'date': reviewDateKey(DateTime.now()),
      'queueIds': queueIds,
      'completedIds': _completedCardIds.toList(),
      'autonomousLearning': _sessionAutonomousLearning,
    });
    final write = _sessionWrite.then(
      (_) => ref.read(sharedPreferencesProvider).setString(key, payload),
    );
    _sessionWrite = write.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return write;
  }

  static bool _sameDay(DateTime left, DateTime right) =>
      isSameReviewDay(left, right);

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
      final sessionComplete =
          _queueIds != null && _index + 1 >= _queueIds!.length;
      if (sessionComplete) {
        _scheduleSessionSync();
      }
      if (!mounted) return;
      ref.invalidate(cardsProvider);
      ref.invalidate(reviewEventsProvider);
      setState(() {
        _completedCardIds.add(card.id);
        _index++;
        _selected.clear();
        _answered = false;
        _rating = null;
        _favorite = false;
      });
      await _persistSession();
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

  String _nextDueLabel(CardModel card, ReviewRating rating) {
    final next = ref
        .read(reviewEngineProvider)
        .review(card, rating, DateTime.now())
        .dueAt;
    final difference = next.difference(DateTime.now());
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes.clamp(1, 59)} 分钟';
    }
    if (difference.inHours < 24) {
      return '${difference.inHours} 小时';
    }
    if (difference.inDays < 7) {
      return '${difference.inDays} 天';
    }
    return '${next.month}/${next.day}';
  }

  void _scheduleSessionSync() {
    ref
        .read(syncControllerProvider.notifier)
        .scheduleSync(reason: 'review-session-finished');
  }

  String _plainText(String value) => value
      .replaceAll(RegExp(r'[#*_`>\[\]]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _StudyCard extends StatefulWidget {
  const _StudyCard({
    required super.key,
    required this.card,
    required this.todayCompleted,
    required this.todayTotal,
    required this.selected,
    required this.answered,
    required this.rating,
    required this.saving,
    required this.previews,
    required this.favorite,
    required this.onToggleFavorite,
    required this.onOpenAnswerCard,
    required this.onSelect,
    required this.onSubmit,
    required this.onRate,
  });

  final CardModel card;
  final int todayCompleted;
  final int todayTotal;
  final Set<String> selected;
  final bool answered;
  final ReviewRating? rating;
  final bool saving;
  final Map<ReviewRating, String> previews;
  final bool favorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onOpenAnswerCard;
  final ValueChanged<String> onSelect;
  final VoidCallback onSubmit;
  final ValueChanged<ReviewRating> onRate;

  @override
  State<_StudyCard> createState() => _StudyCardState();
}

class _StudyCardState extends State<_StudyCard> {
  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final selected = widget.selected;
    final answered = widget.answered;
    final favorite = widget.favorite;
    final saving = widget.saving;
    final rating = widget.rating;
    final previews = widget.previews;
    final todayCompleted = widget.todayCompleted;
    final todayTotal = widget.todayTotal;
    final progress = todayTotal == 0
        ? 0.0
        : (todayCompleted / todayTotal).clamp(0.0, 1.0);
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(14, 2, 14, 6),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0b000000),
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    '今日进度',
                    style: TextStyle(fontSize: 14, color: _studyInk),
                  ),
                  const Spacer(),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$todayCompleted',
                          style: const TextStyle(
                            fontSize: 20,
                            height: 1.05,
                            fontWeight: FontWeight.w700,
                            color: _studyGreen,
                          ),
                        ),
                        const TextSpan(
                          text: ' / ',
                          style: TextStyle(
                            fontSize: 17,
                            color: _studyMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        TextSpan(
                          text: '$todayTotal',
                          style: const TextStyle(
                            fontSize: 20,
                            height: 1.05,
                            fontWeight: FontWeight.w700,
                            color: _studyInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  minHeight: 5,
                  value: progress,
                  backgroundColor: const Color(0xffe7ece9),
                  valueColor: const AlwaysStoppedAnimation(_studyGreen),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
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
                favorite: favorite,
                onToggleFavorite: widget.onToggleFavorite,
                onOpenAnswerCard: widget.onOpenAnswerCard,
                onSelect: widget.onSelect,
              ),
            ),
          ),
        ),
        if (card.type != CardType.note && !answered)
          _SubmitBar(
            enabled: selected.isNotEmpty,
            favorite: favorite,
            onToggleFavorite: widget.onToggleFavorite,
            onOpenAnswerCard: widget.onOpenAnswerCard,
            onSubmit: widget.onSubmit,
          )
        else
          _RatingBar(
            rating: rating,
            saving: saving,
            previews: previews,
            onRate: widget.onRate,
          ),
      ],
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.card,
    required this.selected,
    required this.answered,
    required this.favorite,
    required this.onToggleFavorite,
    required this.onOpenAnswerCard,
    required this.onSelect,
  });

  final CardModel card;
  final Set<String> selected;
  final bool answered;
  final bool favorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onOpenAnswerCard;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final isCorrect =
        selected.length == card.answer.length &&
        selected.containsAll(card.answer);
    const titleSize = 14.0;
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
            if (card.type == CardType.note && card.tags.isNotEmpty)
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
        const Divider(height: 20, color: Color(0xffedf0ee)),
        if (card.type == CardType.note) ...[
          _ReviewContent(data: card.noteContent),
        ] else ...[
          const Text(
            '请选择答案',
            style: TextStyle(fontSize: 13, color: _studyMuted),
          ),
          const SizedBox(height: 10),
          ...card.options.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
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
            const SizedBox(height: 2),
            Text(
              isCorrect ? '回答正确' : '再看一下正确答案',
              style: TextStyle(
                color: isCorrect ? _studyGreen : const Color(0xffc53b32),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (answered && card.explanation.isNotEmpty) ...[
            const SizedBox(height: 18),
            _ReviewContent(data: card.explanation),
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
  const _ReviewContent({required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    return MarkdownContent(
      data: data,
      noteEntries: true,
      textStyle: const TextStyle(color: _studyInk, fontSize: 15, height: 1.5),
    );
  }
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
                  fontSize: 14,
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
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
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
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
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
          const SizedBox(height: 7),
          _RatingButton(
            value: ReviewRating.good,
            nextDue: previews[ReviewRating.good] ?? '',
            selected: rating == ReviewRating.good,
            saving: saving,
            onTap: () => onRate(ReviewRating.good),
            fullWidth: true,
          ),
          const SizedBox(height: 7),
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
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: saving ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: fullWidth ? double.infinity : null,
          height: fullWidth ? 58 : 68,
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
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      nextDue,
                      style: TextStyle(
                        color: selected ? Colors.white : colors.$2,
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
