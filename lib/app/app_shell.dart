import 'dart:ui' show ImageFilter;

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
    if (location.startsWith('/knowledge-base') ||
        location.startsWith('/cards-market') ||
        location.startsWith('/cards') ||
        location.startsWith('/market')) {
      return 2;
    }
    if (location.startsWith('/settings')) return 3;
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
    (Icons.menu_book_outlined, Icons.menu_book_rounded, '学习', '/library'),
    (Icons.archive_outlined, Icons.archive_rounded, '资源', '/knowledge-base'),
    (Icons.person_outline_rounded, Icons.person_rounded, '我的', '/settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: FractionallySizedBox(
        widthFactor: 0.9,
        child: SizedBox(
          height: 86,
          child: Material(
            color: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 4,
            shadowColor: const Color(0x1c26302a),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(34),
              side: const BorderSide(color: Color(0x08000000)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const glowWidth = 90.0;
                  final itemWidth = constraints.maxWidth / _items.length;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 520),
                        curve: Curves.easeOutCubic,
                        left:
                            itemWidth * selectedIndex +
                            (itemWidth - glowWidth) / 2,
                        top: -5,
                        width: glowWidth,
                        height: 62,
                        child: const IgnorePointer(
                          child: _DiffuseSelectionGlow(),
                        ),
                      ),
                      Row(
                        children: [
                          for (var index = 0; index < _items.length; index++)
                            Expanded(
                              child: _item(context, index, _items[index]),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
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
    final VoidCallback? onTap = selected ? null : () => context.go(item.$4);
    return Semantics(
      button: true,
      selected: selected,
      label: item.$3,
      onTap: onTap,
      child: Tooltip(
        message: item.$3,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: 76,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 54,
                  height: 31,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      reverseDuration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        final curved = CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        );
                        return FadeTransition(
                          opacity: curved,
                          child: ScaleTransition(
                            scale: Tween<double>(
                              begin: 0.84,
                              end: 1,
                            ).animate(curved),
                            child: child,
                          ),
                        );
                      },
                      child: Icon(
                        selected ? item.$2 : item.$1,
                        key: ValueKey(selected),
                        color: selected
                            ? const Color(0xff172019)
                            : const Color(0xff65706a),
                        size: 25,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xff172019)
                        : const Color(0xff65706a),
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  child: Text(
                    item.$3,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 5),
                SizedBox(
                  width: 7,
                  height: 7,
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutBack,
                    scale: selected ? 1 : 0,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xff159c3b),
                        shape: BoxShape.circle,
                      ),
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

class _DiffuseSelectionGlow extends StatefulWidget {
  const _DiffuseSelectionGlow();

  @override
  State<_DiffuseSelectionGlow> createState() => _DiffuseSelectionGlowState();
}

class _DiffuseSelectionGlowState extends State<_DiffuseSelectionGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathingController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _breathingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _breathingController,
      child: SizedBox(
        width: 90,
        height: 62,
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 6),
          child: const Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-0.18, -0.22),
                    radius: 0.78,
                    colors: [
                      Color(0x2495e09b),
                      Color(0x1895e09b),
                      Color(0x0795e09b),
                      Color(0x0095e09b),
                    ],
                    stops: [0, 0.26, 0.64, 1],
                  ),
                ),
              ),
              Align(
                alignment: Alignment(0.18, 0.14),
                child: SizedBox(
                  width: 54,
                  height: 38,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(-0.2, -0.2),
                        radius: 0.9,
                        colors: [Color(0x1495e09b), Color(0x0095e09b)],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      builder: (context, child) {
        final breathing = Curves.easeInOut.transform(
          _breathingController.value,
        );
        return Opacity(
          opacity: 0.72 + breathing * 0.28,
          child: Transform.scale(scale: 0.97 + breathing * 0.03, child: child),
        );
      },
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
