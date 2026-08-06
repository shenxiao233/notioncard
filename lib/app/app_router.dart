import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/auth/register_page.dart';
import '../features/cards/cards_page.dart';
import '../features/cards/card_detail_page.dart';
import '../features/cards/cards_market_page.dart';
import '../features/library/library_page.dart';
import '../features/library/document_detail_page.dart';
import '../features/market/deck_detail_page.dart';
import '../features/market/market_page.dart';
import '../features/review/review_home_page.dart';
import '../features/review/review_history_page.dart';
import '../features/review/study_page.dart';
import '../features/settings/settings_page.dart';
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
            path: '/library',
            builder: (context, state) => const LibraryPage(),
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
            path: '/cards-market',
            builder: (context, state) => CardsMarketPage(
              initialTab: state.uri.queryParameters['tab'] == 'market' ? 1 : 0,
            ),
          ),
          GoRoute(
            path: '/cards',
            builder: (context, state) => const CardsPage(),
            routes: [
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
