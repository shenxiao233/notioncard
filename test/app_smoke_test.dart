import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kncard_app/app/app_providers.dart';
import 'package:kncard_app/main.dart';

void main() {
  testWidgets('shows the styled login and register flow', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const KNcardApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Notion Card'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.tap(find.text('立即注册'));
    await tester.pumpAndSettle();

    expect(find.text('注册'), findsOneWidget);
    expect(find.text('邀请码'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.byType(SingleChildScrollView), findsNothing);
  });
}
