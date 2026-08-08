import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ReviewSessionSnapshot {
  const ReviewSessionSnapshot({
    required this.queueIds,
    required this.completedIds,
    this.autonomousLearning,
  });

  final List<String> queueIds;
  final Set<String> completedIds;
  final bool? autonomousLearning;
}

String reviewStudySessionKey(String accountId, String? folder) {
  final encodedFolder = base64UrlEncode(utf8.encode(folder ?? '__all__'));
  return 'review.study_session.$accountId.$encodedFolder';
}

ReviewSessionSnapshot? loadReviewSession(
  SharedPreferences preferences,
  String accountId,
  String? folder, {
  DateTime? now,
}) {
  final raw = preferences.getString(reviewStudySessionKey(accountId, folder));
  if (raw == null || raw.isEmpty) return null;
  try {
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic> ||
        data['date'] != reviewDateKey(now ?? DateTime.now())) {
      return null;
    }
    final queueIds = (data['queueIds'] as List?)?.whereType<String>().toList();
    final completedIds = (data['completedIds'] as List?)
        ?.whereType<String>()
        .toSet();
    if (queueIds == null || completedIds == null) return null;
    return ReviewSessionSnapshot(
      queueIds: queueIds,
      completedIds: completedIds,
      autonomousLearning: data['autonomousLearning'] is bool
          ? data['autonomousLearning'] as bool
          : null,
    );
  } catch (_) {
    return null;
  }
}

String reviewDateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

bool isSameReviewDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
