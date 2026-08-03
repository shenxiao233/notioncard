import '../../core/models/card_model.dart';

class ReviewCalculation {
  const ReviewCalculation({
    required this.fsrs,
    required this.dueAt,
    required this.mastery,
  });

  final FsrsSnapshot fsrs;
  final DateTime dueAt;
  final String mastery;
}

class ReviewEngine {
  ReviewCalculation review(CardModel card, ReviewRating rating, DateTime now) {
    final current = card.fsrs;
    final days = switch (rating) {
      ReviewRating.again => 0.04,
      ReviewRating.hard => 1.0,
      ReviewRating.good =>
        current.reps == 0 ? 2.0 : (current.stability * 1.8).clamp(2.0, 30.0),
      ReviewRating.easy =>
        current.reps == 0 ? 4.0 : (current.stability * 3.2).clamp(4.0, 90.0),
    };
    final nextDue = now.add(Duration(minutes: (days * 24 * 60).round()));
    final nextState = rating == ReviewRating.again
        ? FsrsState.relearning
        : FsrsState.review;
    final stability = switch (rating) {
      ReviewRating.again => 0.2,
      ReviewRating.hard => (current.stability + 0.5).clamp(0.5, 365.0),
      ReviewRating.good => (current.stability * 1.8).clamp(2.0, 365.0),
      ReviewRating.easy => (current.stability * 3.2).clamp(4.0, 365.0),
    };
    return ReviewCalculation(
      fsrs: FsrsSnapshot(
        state: nextState,
        dueAt: nextDue,
        stability: stability,
        difficulty:
            (current.difficulty + (rating == ReviewRating.hard ? 0.1 : -0.05))
                .clamp(1.0, 10.0),
        reps: current.reps + 1,
        lapses: current.lapses + (rating == ReviewRating.again ? 1 : 0),
      ),
      dueAt: nextDue,
      mastery: switch (rating) {
        ReviewRating.again => 'forgot',
        ReviewRating.hard => 'fuzzy',
        ReviewRating.good => 'familiar',
        ReviewRating.easy => 'tooEasy',
      },
    );
  }
}
