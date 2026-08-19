import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kncard_app/app/app_providers.dart';
import 'package:kncard_app/core/models/account_model.dart';
import 'package:kncard_app/core/models/card_model.dart';
import 'package:kncard_app/features/review/study_page.dart';

void main() {
  testWidgets('keeps the daily total fixed at 100 cards', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      _studyApp(preferences: preferences, cards: _cards(100)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText() == '0 / 100',
      ),
      findsOneWidget,
    );
  });

  testWidgets('restores completed cards when the study page is reopened', (
    tester,
  ) async {
    final cards = _cards(100);
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      _sessionKey('account-a', 'deck'): jsonEncode({
        'date': _dateKey(now),
        'queueIds': cards.map((card) => card.id).toList(),
        'completedIds': ['card-0', 'card-1'],
      }),
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(_studyApp(preferences: preferences, cards: cards));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText() == '2 / 100',
      ),
      findsOneWidget,
    );
  });

  testWidgets('removes deleted cards from a saved study queue', (tester) async {
    final cards = _cards(2);
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      _sessionKey('account-a', 'deck'): jsonEncode({
        'date': _dateKey(now),
        'queueIds': ['deleted-card', 'card-0', 'card-1'],
        'completedIds': ['deleted-card', 'card-0'],
      }),
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(_studyApp(preferences: preferences, cards: cards));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == '1 / 2',
      ),
      findsOneWidget,
    );
  });
}

Widget _studyApp({
  required SharedPreferences preferences,
  required List<CardModel> cards,
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      currentAccountProvider.overrideWithValue(
        const AccountModel(
          id: 'account-a',
          username: 'tester',
          nickname: 'Tester',
          status: 'ACTIVE',
        ),
      ),
      cardsProvider.overrideWith((ref) async => cards),
      reviewEventsProvider.overrideWith((ref) async => const []),
    ],
    child: const MaterialApp(home: StudyPage(selectedFolder: 'deck')),
  );
}

List<CardModel> _cards(int count) {
  final due = DateTime.now().subtract(const Duration(minutes: 1));
  return List.generate(
    count,
    (index) => CardModel(
      id: 'card-$index',
      accountId: 'account-a',
      type: CardType.note,
      folder: 'deck',
      question: 'Question $index',
      options: const {},
      answer: const [],
      content: 'Note $index',
      noteContent: '',
      explanation: '',
      tags: const [],
      dueAt: due,
      createdAt: due,
      updatedAt: due,
      reviews: 1,
      mastery: '',
      suspended: false,
      fsrs: FsrsSnapshot(
        state: FsrsState.review,
        dueAt: due,
        stability: 1,
        difficulty: 5,
        reps: 1,
        lapses: 0,
      ),
    ),
  );
}

String _sessionKey(String accountId, String folder) =>
    'review.study_session.$accountId.${base64UrlEncode(utf8.encode(folder))}';

String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
