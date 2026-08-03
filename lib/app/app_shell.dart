import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/app_brand.dart';

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
    (Icons.school_outlined, Icons.school, '复习', '/review'),
    (Icons.menu_book_outlined, Icons.menu_book, '学习库', '/library'),
    (Icons.style_outlined, Icons.style, '卡片', '/cards'),
    (Icons.storefront_outlined, Icons.storefront, '市场', '/market'),
    (Icons.person_outline, Icons.person, '我的', '/settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 82,
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
    return Tooltip(
      message: item.$3,
      child: InkWell(
        onTap: () => context.go(item.$4),
        borderRadius: BorderRadius.circular(18),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 72,
            height: 66,
            decoration: BoxDecoration(
              color: selected ? const Color(0xfff1f8ef) : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? item.$2 : item.$1,
                  color: selected
                      ? const Color(0xff2f8d25)
                      : const Color(0xff777b78),
                  size: 29,
                ),
                const SizedBox(height: 3),
                Text(
                  item.$3,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xff2f8d25)
                        : const Color(0xff555955),
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
