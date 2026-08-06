import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/update/app_update_controller.dart';
import '../core/widgets/app_brand.dart';
import 'app_providers.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  int _indexFor(String location) {
    if (location.startsWith('/library')) return 1;
    if (location.startsWith('/cards-market') || location.startsWith('/cards')) {
      return 2;
    }
    if (location.startsWith('/market')) return 3;
    if (location.startsWith('/settings')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final isStudyFlow = location == '/review/study';
    final update = ref.watch(appUpdateControllerProvider);
    return Scaffold(
      body: Column(
        children: [
          if (update.hasUpdate) _AppUpdateBanner(update: update),
          Expanded(child: AppContentFrame(child: child)),
        ],
      ),
      bottomNavigationBar: isStudyFlow
          ? null
          : _BottomNavigationBar(selectedIndex: _indexFor(location)),
    );
  }
}

class _BottomNavigationBar extends StatelessWidget {
  const _BottomNavigationBar({required this.selectedIndex});

  final int selectedIndex;

  static const _items = <(IconData, IconData, String, String)>[
    (Icons.home_outlined, Icons.home_rounded, '首页', '/review'),
    (Icons.menu_book_outlined, Icons.menu_book_rounded, '学习库', '/library'),
    (Icons.style_outlined, Icons.style_rounded, '卡片', '/cards'),
    (Icons.storefront_outlined, Icons.storefront_rounded, '市场', '/market'),
    (Icons.person_outline_rounded, Icons.person_rounded, '我的', '/settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: EdgeInsets.zero,
      child: Material(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        child: Container(
          height: 76,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xffe7ebe8))),
          ),
          child: Row(
            children: [
              for (var index = 0; index < _items.length; index++)
                Expanded(child: _item(context, index, _items[index])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    int index,
    (IconData, IconData, String, String) item,
  ) {
    final selected = index == selectedIndex;
    return Semantics(
      button: true,
      selected: selected,
      label: item.$3,
      child: Tooltip(
        message: item.$3,
        child: InkWell(
          onTap: selected ? null : () => context.go(item.$4),
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 66,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: Icon(
                    selected ? item.$2 : item.$1,
                    key: ValueKey(selected),
                    color: selected
                        ? const Color(0xff3e9d35)
                        : const Color(0xff5d605e),
                    size: 26,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.$3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xff3e9d35)
                        : const Color(0xff4f5250),
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 5,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: selected ? 18 : 0,
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xff3e9d35)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppUpdateBanner extends StatelessWidget {
  const _AppUpdateBanner({required this.update});

  final AppUpdateState update;

  @override
  Widget build(BuildContext context) {
    final manifest = update.manifest;
    if (manifest == null) return const SizedBox.shrink();
    return Material(
      color: const Color(0xffe9f5ed),
      child: InkWell(
        onTap: () => context.go('/settings'),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
            child: Row(
              children: [
                const Icon(Icons.system_update_alt_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '发现新版本 v${manifest.versionName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
