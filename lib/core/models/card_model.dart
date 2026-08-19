enum CardType { single, multiple, trueFalse, note }

enum FsrsState { newCard, learning, review, relearning }

enum ReviewRating { again, hard, good, easy }

enum CardHighlightSection { question, content, note, explanation }

extension CardTypeLabel on CardType {
  String get label {
    switch (this) {
      case CardType.single:
        return '单选题';
      case CardType.multiple:
        return '多选题';
      case CardType.trueFalse:
        return '判断题';
      case CardType.note:
        return '速记词条';
    }
  }
}

extension ReviewRatingLabel on ReviewRating {
  String get label {
    switch (this) {
      case ReviewRating.again:
        return '忘记了';
      case ReviewRating.hard:
        return '模糊';
      case ReviewRating.good:
        return '熟悉';
      case ReviewRating.easy:
        return '太简单';
    }
  }

  String get description {
    switch (this) {
      case ReviewRating.again:
        return '没记住';
      case ReviewRating.hard:
        return '想起来了';
      case ReviewRating.good:
        return '熟悉';
      case ReviewRating.easy:
        return '太简单';
    }
  }

  int get value => index + 1;
}

class FsrsSnapshot {
  const FsrsSnapshot({
    required this.state,
    required this.dueAt,
    required this.stability,
    required this.difficulty,
    required this.reps,
    required this.lapses,
  });

  final FsrsState state;
  final DateTime dueAt;
  final double stability;
  final double difficulty;
  final int reps;
  final int lapses;
}

class CardModel {
  const CardModel({
    required this.id,
    required this.accountId,
    required this.type,
    required this.folder,
    this.source = '',
    required this.question,
    required this.options,
    required this.answer,
    required this.content,
    required this.noteContent,
    required this.explanation,
    required this.tags,
    required this.dueAt,
    required this.createdAt,
    this.sortOrder,
    required this.updatedAt,
    required this.reviews,
    required this.mastery,
    required this.suspended,
    required this.fsrs,
  });

  final String id;
  final String accountId;
  final CardType type;
  final String folder;

  /// A user-editable origin for the card, independent from its deck/folder.
  ///
  /// Older cards do not have this value and fall back to [folder] when they
  /// are displayed.
  final String source;
  final String question;
  final Map<String, String> options;
  final List<String> answer;

  /// The body/back content of a [CardType.note] card.
  ///
  /// This is deliberately separate from [noteContent], which is the user's
  /// private note attached to any card type.
  final String content;
  final String noteContent;
  final String explanation;
  final List<String> tags;
  final DateTime dueAt;
  final DateTime createdAt;

  /// Stable position within the source deck. This is intentionally separate
  /// from [createdAt], which is a timestamp and cannot represent import order
  /// reliably on every local database backend.
  final int? sortOrder;
  final DateTime updatedAt;
  final int reviews;
  final String mastery;
  final bool suspended;
  final FsrsSnapshot fsrs;

  bool get isDue => !suspended && !dueAt.isAfter(DateTime.now());

  CardModel copyWith({
    String? folder,
    String? source,
    String? question,
    String? content,
    String? noteContent,
    List<String>? tags,
    DateTime? dueAt,
    int? sortOrder,
    DateTime? updatedAt,
    int? reviews,
    String? mastery,
    bool? suspended,
    FsrsSnapshot? fsrs,
  }) {
    return CardModel(
      id: id,
      accountId: accountId,
      type: type,
      folder: folder ?? this.folder,
      source: source ?? this.source,
      question: question ?? this.question,
      options: options,
      answer: answer,
      content: content ?? this.content,
      noteContent: noteContent ?? this.noteContent,
      explanation: explanation,
      tags: tags ?? this.tags,
      dueAt: dueAt ?? this.dueAt,
      createdAt: createdAt,
      sortOrder: sortOrder ?? this.sortOrder,
      updatedAt: updatedAt ?? this.updatedAt,
      reviews: reviews ?? this.reviews,
      mastery: mastery ?? this.mastery,
      suspended: suspended ?? this.suspended,
      fsrs: fsrs ?? this.fsrs,
    );
  }
}

/// Canonical values used by the two-state review UI.
const masteredCardMastery = 'mastered';
const reviewingCardMastery = 'reviewing';

extension CardReviewStatus on CardModel {
  /// Older review snapshots used `familiar` and `tooEasy`. They remain
  /// equivalent to the new "已掌握" presentation so upgrading the UI does
  /// not make existing progress look like it was lost.
  bool get isMastered =>
      mastery == masteredCardMastery ||
      mastery == 'familiar' ||
      mastery == 'tooEasy';

  String get reviewStatusLabel => isMastered ? '已掌握' : '复习中';

  String get reviewCountLabel => reviews > 0 ? '$reviews 次复习' : '';
}

class ReviewEventModel {
  const ReviewEventModel({
    required this.id,
    required this.accountId,
    required this.cardId,
    required this.question,
    required this.folder,
    required this.rating,
    required this.reviewedAt,
    required this.nextDue,
  });

  final String id;
  final String accountId;
  final String cardId;
  final String question;
  final String folder;
  final ReviewRating rating;
  final DateTime reviewedAt;
  final DateTime nextDue;
}

enum SyncOperation { upsert, delete }

enum SyncItemStatus { pending, failed, synced }

class SyncQueueItemModel {
  const SyncQueueItemModel({
    required this.id,
    required this.accountId,
    required this.objectType,
    required this.objectId,
    this.objectVersion = 1,
    required this.operation,
    required this.payload,
    required this.status,
    required this.attempts,
    required this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String accountId;
  final String objectType;
  final String objectId;
  final int objectVersion;
  final SyncOperation operation;
  final String payload;
  final SyncItemStatus status;
  final int attempts;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
}
