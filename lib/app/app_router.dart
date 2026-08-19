import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/auth/register_page.dart';
import '../core/models/card_model.dart';
import '../features/cards/cards_page.dart';
import '../features/cards/card_detail_page.dart';
import '../features/cards/card_editor_page.dart';
import '../features/cards/card_import_page.dart';
import '../features/cards/cards_market_page.dart';
import '../features/library/library_page.dart';
import '../features/library/document_detail_page.dart';
import '../features/market/deck_detail_page.dart';
import '../features/market/market_page.dart';
import '../features/editor/editor_page.dart';
import '../features/review/review_home_page.dart';
import '../features/review/review_history_page.dart';
import '../features/review/study_page.dart';
import '../features/settings/account_page.dart';
import '../features/settings/settings_page.dart';
import '../features/settings/settings_preferences_page.dart';
import '../features/statistics/statistics_page.dart';
import 'app_providers.dart';
import 'app_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = ref.read(authControllerProvider.notifier);
  return GoRouter(
    initialLocation: '/review',
    refreshListenable: GoRouterRefreshStream(authNotifier.stream),
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loggedIn = auth.valueOrNull != null;
      final isLogin = state.matchedLocation == '/login';
      final isRegister = state.matchedLocation == '/register';
      if (!loggedIn && !isLogin && !isRegister) return '/login';
      if (loggedIn && (isLogin || isRegister)) return '/review';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/edit',
            builder: (context, state) => const EditorPage(),
          ),
          GoRoute(
            // Keep the card editor as a sibling route instead of nesting it
            // below `/edit`. This makes it a real standalone page: opening
            // it from the card list can return directly to that list rather
            // than revealing the old content-type chooser underneath it.
            path: '/edit/card',
            builder: (context, state) {
              final extra = state.extra;
              return CardEditorPage(
                initialCard: extra is CardModel ? extra : null,
                initialFolder: extra is String ? extra : null,
              );
            },
          ),
          GoRoute(
            path: '/edit/document',
            builder: (context, state) => const DocumentFolderPickerPage(),
            routes: [
              GoRoute(
                path: 'editor',
                builder: (context, state) => DocumentEditorPage(
                  selectedFolder: state.extra is String
                      ? state.extra! as String
                      : '',
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/review',
            builder: (context, state) => const ReviewHomePage(),
            routes: [
              GoRoute(
                path: 'study',
                builder: (context, state) => StudyPage(
                  selectedFolder: state.uri.queryParameters['folder'],
                ),
              ),
              GoRoute(
                path: 'history',
                builder: (context, state) => const ReviewHistoryPage(),
              ),
            ],
          ),
          GoRoute(
            path: '/statistics',
            builder: (context, state) => const StatisticsPage(),
          ),
          GoRoute(
            path: '/library',
            builder: (context, state) =>
                LibraryPage(initialFolder: state.uri.queryParameters['folder']),
            routes: [
              GoRoute(
                path: 'document/:documentId',
                builder: (context, state) => DocumentDetailPage(
                  documentId: state.pathParameters['documentId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/knowledge-base',
            builder: (context, state) => const KnowledgeBasePage(),
          ),
          GoRoute(
            path: '/cards-market',
            builder: (context, state) => const KnowledgeBasePage(),
          ),
          GoRoute(
            path: '/cards',
            builder: (context, state) => const CardsPage(),
            routes: [
              GoRoute(
                path: 'import',
                builder: (context, state) => CardImportPage(
                  initialFolder: state.extra is String
                      ? state.extra! as String
                      : null,
                ),
              ),
              GoRoute(
                path: 'deck',
                builder: (context, state) {
                  final folder = state.extra?.toString() ?? '未分类';
                  return DeckCardsPage(folder: folder);
                },
              ),
              GoRoute(
                path: ':cardId',
                builder: (context, state) =>
                    CardDetailPage(cardId: state.pathParameters['cardId']!),
              ),
            ],
          ),
          GoRoute(
            path: '/market',
            builder: (context, state) => const MarketPage(),
            routes: [
              GoRoute(
                path: 'deck/:deckId',
                builder: (context, state) =>
                    DeckDetailPage(deckId: state.pathParameters['deckId']!),
              ),
            ],
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsPage(),
            routes: [
              GoRoute(
                path: 'preferences',
                builder: (context, state) => const SettingsPreferencesPage(),
              ),
              GoRoute(
                path: 'account',
                builder: (context, state) => const AccountPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
