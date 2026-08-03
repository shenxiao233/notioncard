import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../core/database/app_database.dart';
import '../core/models/account_model.dart';
import '../core/models/card_model.dart';
import '../core/models/document_model.dart';
import '../core/network/api_client.dart';
import '../core/network/api_config.dart';
import '../core/repositories/auth_repository.dart';
import '../core/repositories/content_repository.dart';
import '../core/sync/sync_coordinator.dart';
import '../core/sync/sync_controller.dart';
import '../features/market/market_model.dart';
import '../features/market/market_repository.dart';
import '../features/review/review_engine.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

final sessionEventsProvider = Provider<SessionEvents>((ref) {
  final events = SessionEvents();
  ref.onDispose(events.dispose);
  return events;
});

final apiConfigProvider = Provider<ApiConfig>((ref) {
  return const ApiConfig(baseUrl: ApiConfig.defaultBaseUrl);
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return ApiClient(
    config: ref.watch(apiConfigProvider),
    tokenReader: () => storage.read(key: AuthRepository.tokenKey),
    onUnauthorized: () async => ref.read(sessionEventsProvider).invalidate(),
  );
});

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(sharedPreferencesProvider),
    apiClient: ref.watch(apiClientProvider),
    secureStorage: ref.watch(secureStorageProvider),
  );
});

final contentRepositoryProvider = Provider<ContentRepository>((ref) {
  return ContentRepository(ref.watch(appDatabaseProvider));
});

final reviewEngineProvider = Provider<ReviewEngine>((ref) => ReviewEngine());

final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  return SyncCoordinator(
    ref.watch(appDatabaseProvider),
    apiClient: ref.watch(apiClientProvider),
    preferences: ref.watch(sharedPreferencesProvider),
  );
});

final marketRepositoryProvider = Provider<MarketRepository>((ref) {
  return MarketRepository(apiClient: ref.watch(apiClientProvider));
});

class AuthController extends StateNotifier<AsyncValue<AccountModel?>> {
  AuthController(this._repository, SessionEvents events)
    : super(const AsyncLoading()) {
    events.listen(_invalidateSession);
    _restore();
  }

  final AuthRepository _repository;

  Future<void> _invalidateSession() async {
    await _repository.clearSession();
    state = const AsyncData(null);
  }

  Future<void> _restore() async {
    state = AsyncData(_repository.currentAccount);
  }

  Future<bool> login(String username, String password) async {
    state = const AsyncLoading();
    final account = await _repository.login(username, password);
    state = AsyncData(account);
    return account != null;
  }

  Future<bool> register(
    String username,
    String password,
    String invitationCode,
  ) async {
    state = const AsyncLoading();
    final account = await _repository.register(
      username,
      password,
      invitationCode,
    );
    state = AsyncData(account);
    return account != null;
  }

  Future<void> logout() async {
    await _repository.logout();
    state = const AsyncData(null);
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<AccountModel?>>((ref) {
      return AuthController(
        ref.watch(authRepositoryProvider),
        ref.watch(sessionEventsProvider),
      );
    });

final currentAccountProvider = Provider<AccountModel?>((ref) {
  return ref.watch(authControllerProvider).valueOrNull;
});

final syncControllerProvider =
    StateNotifierProvider<SyncController, SyncUiState>((ref) {
      return SyncController(
        ref.watch(syncCoordinatorProvider),
        Connectivity(),
        () => ref.read(currentAccountProvider),
        onDataChanged: () {
          ref.invalidate(cardsProvider);
          ref.invalidate(documentsProvider);
          ref.invalidate(reviewEventsProvider);
        },
      );
    });

class SessionEvents {
  final _listeners = <Future<void> Function()>[];

  void listen(Future<void> Function() listener) => _listeners.add(listener);

  Future<void> invalidate() async {
    for (final listener in List.of(_listeners)) {
      await listener();
    }
  }

  void dispose() => _listeners.clear();
}

final cardsProvider = FutureProvider<List<CardModel>>((ref) async {
  final account = ref.watch(currentAccountProvider);
  if (account == null) return const [];
  return ref.watch(contentRepositoryProvider).cards(account.id);
});

final documentsProvider = FutureProvider<List<DocumentModel>>((ref) async {
  final account = ref.watch(currentAccountProvider);
  if (account == null) return const [];
  return ref.watch(contentRepositoryProvider).documents(account.id);
});

final reviewEventsProvider = FutureProvider((ref) async {
  final account = ref.watch(currentAccountProvider);
  if (account == null) return const <ReviewEventModel>[];
  return ref.watch(appDatabaseProvider).loadReviewEvents(account.id);
});

final pendingSyncProvider = FutureProvider<int>((ref) async {
  final account = ref.watch(currentAccountProvider);
  if (account == null) return 0;
  return ref.watch(syncCoordinatorProvider).pendingCount(account.id);
});

final marketSearchProvider =
    FutureProvider.family<List<MarketDeckModel>, String>((ref, query) {
      return ref.watch(marketRepositoryProvider).search(query: query);
    });

final marketDeckProvider = FutureProvider.family<MarketDeckModel?, String>((
  ref,
  id,
) {
  return ref.watch(marketRepositoryProvider).findById(id);
});
