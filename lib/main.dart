import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_providers.dart';
import 'app/app_router.dart';
import 'app/app_theme.dart';
import 'core/sound/app_sound_settings.dart';
import 'core/sync/sync_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final preferences = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: const KNcardApp(),
    ),
  );
}

class KNcardApp extends ConsumerStatefulWidget {
  const KNcardApp({super.key});

  @override
  ConsumerState<KNcardApp> createState() => _KNcardAppState();
}

class _KNcardAppState extends ConsumerState<KNcardApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(syncControllerProvider.notifier).sync(reason: 'resumed');
      if (ref.read(currentAccountProvider) != null) {
        ref.read(appUpdateControllerProvider.notifier).check(silent: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(syncControllerProvider, (previous, next) {
      if (previous?.isBusy != true || next.isBusy) return;
      final event = switch (next.phase) {
        SyncPhase.success => AppSoundEvent.syncSuccess,
        SyncPhase.failure => AppSoundEvent.syncFailure,
        _ => null,
      };
      if (event != null) {
        unawaited(ref.read(appSoundServiceProvider).play(event));
      }
    });
    return MaterialApp.router(
      title: 'KNcard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
