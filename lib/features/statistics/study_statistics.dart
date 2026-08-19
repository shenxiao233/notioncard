import '../../core/models/card_model.dart';

enum StudyStatsRange { week, month, all }

extension StudyStatsRangeLabel on StudyStatsRange {
  String get label => switch (this) {
    StudyStatsRange.week => '本周',
    StudyStatsRange.month => '本月',
    StudyStatsRange.all => '全部',
  };
}

class StudyTrendPoint {
  const StudyTrendPoint({
    required this.date,
    required this.reviewed,
    required this.mastered,
    required this.fuzzy,
    required this.forgotten,
  });

  final DateTime date;
  final int reviewed;
  final int mastered;
  final int fuzzy;
  final int forgotten;

  int get maximum => [
    reviewed,
    mastered,
    fuzzy,
    forgotten,
  ].reduce((left, right) => left > right ? left : right);
}

class StudyDeckStatistics {
  const StudyDeckStatistics({
    required this.name,
    required this.total,
    required this.learned,
    required this.mastered,
    required this.fuzzy,
    required this.forgotten,
    required this.due,
    required this.newCards,
  });

  final String name;
  final int total;
  final int learned;
  final int mastered;
  final int fuzzy;
  final int forgotten;
  final int due;
  final int newCards;

  double get progress => total == 0 ? 0 : learned / total;

  double get masteryRate => learned == 0 ? 0 : mastered / learned;
}

class StudyStatistics {
  const StudyStatistics({
    required this.range,
    required this.totalCards,
    required this.learnedCards,
    required this.masteredCards,
    required this.fuzzyCards,
    required this.forgottenCards,
    required this.dueCards,
    required this.newCards,
    required this.reviewCount,
    required this.reviewedCardCount,
    required this.streakDays,
    required this.trend,
    required this.decks,
  });

  final StudyStatsRange range;
  final int totalCards;
  final int learnedCards;
  final int masteredCards;
  final int fuzzyCards;
  final int forgottenCards;
  final int dueCards;
  final int newCards;
  final int reviewCount;
  final int reviewedCardCount;
  final int streakDays;
  final List<StudyTrendPoint> trend;
  final List<StudyDeckStatistics> decks;

  double get masteryRate =>
      learnedCards == 0 ? 0 : masteredCards / learnedCards;

  int get trendMaximum => trend.fold<int>(
    0,
    (maximum, point) => point.maximum > maximum ? point.maximum : maximum,
  );
}

StudyStatistics buildStudyStatistics({
  required List<CardModel> cards,
  required List<ReviewEventModel> events,
  required StudyStatsRange range,
  String? folder,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final normalizedFolder = _normalizedFolder(folder);
  final scopedCards = cards
      .where(
        (card) =>
            normalizedFolder == null ||
            _normalizedFolder(card.folder) == normalizedFolder,
      )
      .toList();
  final scopedEvents = events
      .where(
        (event) =>
            normalizedFolder == null ||
            _normalizedFolder(event.folder) == normalizedFolder,
      )
      .where((event) => !event.reviewedAt.isAfter(current))
      .toList();
  final rangeStart = _rangeStart(range, current, scopedEvents);
  final rangedEvents = scopedEvents
      .where((event) => !event.reviewedAt.isBefore(rangeStart))
      .toList();

  final learnedCards = scopedCards.where(_isLearned).length;
  final masteredCards = scopedCards.where((card) => card.isMastered).length;
  final fuzzyCards = scopedCards
      .where((card) => card.mastery.trim() == 'fuzzy')
      .length;
  final forgottenCards = scopedCards
      .where((card) => card.mastery.trim() == 'forgot')
      .length;
  final dueCards = scopedCards
      .where((card) => !card.suspended && !card.dueAt.isAfter(current))
      .length;
  final newCards = scopedCards
      .where((card) => card.fsrs.state == FsrsState.newCard)
      .length;
  final reviewedCardIds = rangedEvents.map((event) => event.cardId).toSet();

  return StudyStatistics(
    range: range,
    totalCards: scopedCards.length,
    learnedCards: learnedCards,
    masteredCards: masteredCards,
    fuzzyCards: fuzzyCards,
    forgottenCards: forgottenCards,
    dueCards: dueCards,
    newCards: newCards,
    reviewCount: rangedEvents.length,
    reviewedCardCount: reviewedCardIds.length,
    streakDays: _currentStreak(scopedEvents, current),
    trend: _buildTrend(rangeStart, current, rangedEvents),
    decks: _buildDecks(scopedCards, current),
  );
}

String? _normalizedFolder(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

bool _isLearned(CardModel card) => card.reviews > 0 || card.fsrs.reps > 0;

DateTime _rangeStart(
  StudyStatsRange range,
  DateTime current,
  List<ReviewEventModel> events,
) {
  final today = DateTime(current.year, current.month, current.day);
  return switch (range) {
    StudyStatsRange.week => today.subtract(const Duration(days: 6)),
    StudyStatsRange.month => DateTime(current.year, current.month),
    StudyStatsRange.all =>
      events.isEmpty
          ? today
          : _dayStart(
              events
                  .map((event) => event.reviewedAt)
                  .reduce((left, right) => left.isBefore(right) ? left : right),
            ),
  };
}

List<StudyTrendPoint> _buildTrend(
  DateTime start,
  DateTime current,
  List<ReviewEventModel> events,
) {
  final byDay = <int, _TrendCounter>{};
  for (final event in events) {
    final date = _dayStart(event.reviewedAt);
    final counter = byDay.putIfAbsent(_dayKey(date), _TrendCounter.new);
    counter.reviewed++;
    switch (event.rating) {
      case ReviewRating.again:
        counter.forgotten++;
      case ReviewRating.hard:
        counter.fuzzy++;
      case ReviewRating.good || ReviewRating.easy:
        counter.mastered++;
    }
  }

  final points = <StudyTrendPoint>[];
  var cursor = _dayStart(start);
  final lastDay = _dayStart(current);
  while (!cursor.isAfter(lastDay)) {
    final counter = byDay[_dayKey(cursor)] ?? _TrendCounter();
    points.add(
      StudyTrendPoint(
        date: cursor,
        reviewed: counter.reviewed,
        mastered: counter.mastered,
        fuzzy: counter.fuzzy,
        forgotten: counter.forgotten,
      ),
    );
    cursor = cursor.add(const Duration(days: 1));
  }
  return points;
}

List<StudyDeckStatistics> _buildDecks(List<CardModel> cards, DateTime current) {
  final grouped = <String, List<CardModel>>{};
  for (final card in cards) {
    final name = _normalizedFolder(card.folder) ?? '未分类';
    grouped.putIfAbsent(name, () => []).add(card);
  }
  final decks = grouped.entries.map((entry) {
    final values = entry.value;
    return StudyDeckStatistics(
      name: entry.key,
      total: values.length,
      learned: values.where(_isLearned).length,
      mastered: values.where((card) => card.isMastered).length,
      fuzzy: values.where((card) => card.mastery.trim() == 'fuzzy').length,
      forgotten: values.where((card) => card.mastery.trim() == 'forgot').length,
      due: values
          .where((card) => !card.suspended && !card.dueAt.isAfter(current))
          .length,
      newCards: values
          .where((card) => card.fsrs.state == FsrsState.newCard)
          .length,
    );
  }).toList();
  decks.sort((left, right) {
    final total = right.total.compareTo(left.total);
    return total == 0 ? left.name.compareTo(right.name) : total;
  });
  return decks;
}

int _currentStreak(List<ReviewEventModel> events, DateTime current) {
  final days = events.map((event) => _dayKey(event.reviewedAt)).toSet();
  var cursor = _dayStart(current);
  var streak = 0;
  while (days.contains(_dayKey(cursor))) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

DateTime _dayStart(DateTime value) =>
    DateTime(value.year, value.month, value.day);

int _dayKey(DateTime value) =>
    value.year * 10000 + value.month * 100 + value.day;

class _TrendCounter {
  int reviewed = 0;
  int mastered = 0;
  int fuzzy = 0;
  int forgotten = 0;
}
