import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/app_brand.dart';
import 'app_theme.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  int _indexFor(String location) {
    if (location.startsWith('/library')) return 1;
    if (location.startsWith('/cards')) return 2;
    if (location.startsWith('/market')) return 3;
    if (location.startsWith('/settings')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final isStudyFlow = location == '/review/study';
    return Scaffold(
      body: AppContentFrame(child: child),
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
    (Icons.schedule_outlined, Icons.schedule_rounded, '学习库', '/library'),
    (Icons.favorite_border_rounded, Icons.favorite_rounded, '卡片', '/cards'),
    (Icons.storefront_outlined, Icons.storefront_rounded, '市场', '/market'),
    (Icons.person_outline_rounded, Icons.person_rounded, '我的', '/settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: SizedBox(
        height: 88,
        child: Material(
          color: AppTheme.background,
          elevation: 10,
          shadowColor: const Color(0x26000000),
          borderRadius: BorderRadius.circular(32),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                for (var index = 0; index < _items.length; index++)
                  Expanded(child: _item(context, index, _items[index])),
              ],
            ),
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
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: 72,
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
                        ? const Color(0xff171918)
                        : const Color(0xff5d605e),
                    size: 28,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.$3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xff171918)
                        : const Color(0xff4f5250),
                    fontSize: 13,
                    height: 1.15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 5),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: selected ? 6 : 0,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xffe22d2d),
                    shape: BoxShape.circle,
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
