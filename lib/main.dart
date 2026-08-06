import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_providers.dart';
import 'app/app_router.dart';
import 'app/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
    return MaterialApp.router(
      title: 'KNcard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
