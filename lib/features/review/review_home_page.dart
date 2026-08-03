import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_providers.dart';
import '../../core/models/card_model.dart';

abstract final class _ReviewColors {
  static const background = Color(0xfffcfdfb);
  static const ink = Color(0xff101311);
  static const green = Color(0xff159515);
  static const darkGreen = Color(0xff087408);
  static const softGreen = Color(0xffeef8ec);
  static const paleGreen = Color(0xfff7fbf5);
  static const line = Color(0xffdfe4df);
}

class ReviewHomePage extends ConsumerStatefulWidget {
  const ReviewHomePage({super.key});

  @override
  ConsumerState<ReviewHomePage> createState() => _ReviewHomePageState();
}

class _ReviewHomePageState extends ConsumerState<ReviewHomePage> {
  String? _selectedFolder;

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final cards = ref.watch(cardsProvider);
    final events = ref.watch(reviewEventsProvider);

    return Scaffold(
      backgroundColor: _ReviewColors.background,
      body: SafeArea(
        bottom: false,
        child: cards.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: _ReviewColors.green),
          ),
          error: (_, _) => _ReviewError(onRetry: () => _refreshReview(ref)),
          data: (values) {
            final folders = _folders(values);
            final selectedFolder = _resolveSelectedFolder(folders);
            final selectedCards = selectedFolder == null
                ? const <CardModel>[]
                : values
                      .where((card) => card.folder == selectedFolder)
                      .toList();
            final due = selectedCards.where((card) => card.isDue).toList();
            final recent = (events.valueOrNull ?? const <ReviewEventModel>[])
                .where((event) => event.folder == selectedFolder)
                .toList();
            final completedToday = recent
                .where((event) => _sameDay(event.reviewedAt, DateTime.now()))
                .length;
            final reviewed = selectedCards
                .where((card) => card.reviews > 0)
                .length;

            final streakDays = _streakDays(recent);
            final todayProgress = due.isEmpty
                ? 0
                : (completedToday / due.length * 100)
                      .round()
                      .clamp(0, 100)
                      .toInt();
            final completed = selectedCards.isEmpty
                ? 0
                : (reviewed / selectedCards.length * 5)
                      .round()
                      .clamp(0, 5)
                      .toInt();

            return LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final compact = constraints.maxHeight < 760 || width < 380;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        compact ? 3 : 6,
                        16,
                        compact ? 4 : 8,
                      ),
                      child: Column(
                        children: [
                          _WelcomeHeader(compact: compact),
                          SizedBox(height: compact ? 8 : 10),
                          _CurrentDeckCard(
                            folder: selectedFolder,
                            cardCount: selectedCards.length,
                            compact: compact,
                            onTap: folders.isEmpty
                                ? null
                                : () => _showFolderPicker(folders, values),
                          ),
                          SizedBox(height: compact ? 8 : 10),
                          _DailyPlanCard(
                            dueCount: due.length,
                            completed: completed,
                            streakDays: streakDays,
                            todayProgress: todayProgress,
                            compact: compact,
                            onStart: selectedFolder == null
                                ? null
                                : () => context.push(
                                    Uri(
                                      path: '/review/study',
                                      queryParameters: {
                                        'folder': selectedFolder,
                                      },
                                    ).toString(),
                                  ),
                          ),
                          SizedBox(height: compact ? 10 : 12),
                          _ProgressSection(
                            completed: completed,
                            compact: compact,
                            onDetails: () => context.push('/review/history'),
                          ),
                          SizedBox(height: compact ? 10 : 12),
                          _MotivationBanner(
                            completedToday: completedToday,
                            hasCards: selectedCards.isNotEmpty,
                            compact: compact,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  List<String> _folders(List<CardModel> cards) {
    final folders = cards
        .map((card) => card.folder.trim())
        .where((folder) => folder.isNotEmpty)
        .toSet()
        .toList();
    folders.sort();
    return folders;
  }

  String? _resolveSelectedFolder(List<String> folders) {
    if (folders.isEmpty) {
      if (_selectedFolder != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _selectedFolder != null) {
            setState(() => _selectedFolder = null);
          }
        });
      }
      return null;
    }
    if (_selectedFolder != null && folders.contains(_selectedFolder)) {
      return _selectedFolder;
    }
    final next = folders.first;
    if (_selectedFolder != next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedFolder != next) {
          setState(() => _selectedFolder = next);
        }
      });
    }
    return next;
  }

  Future<void> _showFolderPicker(
    List<String> folders,
    List<CardModel> cards,
  ) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  '切换牌组',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              ...folders.map((folder) {
                final count = cards
                    .where((card) => card.folder == folder)
                    .length;
                final current = folder == _selectedFolder;
                return ListTile(
                  onTap: () => Navigator.of(sheetContext).pop(folder),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  tileColor: current ? _ReviewColors.softGreen : null,
                  leading: Icon(
                    current
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: current
                        ? _ReviewColors.green
                        : const Color(0xff9aa69f),
                  ),
                  title: Text(
                    folder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('$count 张卡片'),
                );
              }),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted && selected != _selectedFolder) {
      setState(() => _selectedFolder = selected);
    }
  }

  Future<void> _refreshReview(WidgetRef ref) async {
    await ref
        .read(syncControllerProvider.notifier)
        .sync(reason: 'review-refresh');
    ref.invalidate(cardsProvider);
    ref.invalidate(reviewEventsProvider);
    await ref.read(cardsProvider.future);
    await ref.read(reviewEventsProvider.future);
  }

  static bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
  static int _streakDays(List<ReviewEventModel> events) {
    final reviewedDays = events
        .map(
          (event) => DateTime(
            event.reviewedAt.year,
            event.reviewedAt.month,
            event.reviewedAt.day,
          ),
        )
        .toSet();
    var cursor = DateTime.now();
    var streak = 0;
    while (reviewedDays.contains(
      DateTime(cursor.year, cursor.month, cursor.day),
    )) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: compact ? 116 : 138,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          right: -18,
          top: -28,
          width: compact ? 148 : 174,
          height: compact ? 156 : 184,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.66,
              child: Image.asset(
                'assets/review_leaves.jpg',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 14, right: 54),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(),
                style: TextStyle(
                  color: _ReviewColors.ink,
                  fontSize: compact ? 27 : 30,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 9),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: '准备好'),
                    const TextSpan(
                      text: '征服',
                      style: TextStyle(color: _ReviewColors.green),
                    ),
                    const TextSpan(text: '你的复习了吗？'),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _ReviewColors.ink,
                  fontSize: compact ? 22 : 26,
                  fontWeight: FontWeight.w700,
                  height: 1.12,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return '早上好，';
    if (hour < 18) return '下午好，';
    return '晚上好，';
  }
}

class _CurrentDeckCard extends StatelessWidget {
  const _CurrentDeckCard({
    required this.folder,
    required this.cardCount,
    required this.compact,
    required this.onTap,
  });

  final String? folder;
  final int cardCount;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: compact ? 56 : 62,
        padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xffe8eee9)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0d000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: compact ? 34 : 38,
              height: compact ? 34 : 38,
              decoration: const BoxDecoration(
                color: _ReviewColors.softGreen,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.folder_rounded,
                color: _ReviewColors.green,
                size: compact ? 18 : 20,
              ),
            ),
            SizedBox(width: compact ? 9 : 11),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前牌组',
                    style: TextStyle(
                      color: const Color(0xff68746f),
                      fontSize: compact ? 11 : 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    folder ?? '暂无可用牌组',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _ReviewColors.ink,
                      fontSize: compact ? 15 : 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (folder != null) ...[
              Text(
                '$cardCount 张',
                style: TextStyle(
                  color: _ReviewColors.darkGreen,
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.unfold_more_rounded,
                color: onTap == null
                    ? const Color(0xffb5beb8)
                    : _ReviewColors.green,
                size: compact ? 20 : 22,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _DailyPlanCard extends StatelessWidget {
  const _DailyPlanCard({
    required this.dueCount,
    required this.completed,
    required this.streakDays,
    required this.todayProgress,
    required this.compact,
    required this.onStart,
  });

  final int dueCount;
  final int completed;
  final int streakDays;
  final int todayProgress;
  final bool compact;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) => Container(
    height: compact ? 214 : 244,
    padding: EdgeInsets.fromLTRB(
      compact ? 15 : 18,
      compact ? 13 : 17,
      compact ? 15 : 18,
      compact ? 10 : 13,
    ),
    decoration: BoxDecoration(
      color: _ReviewColors.paleGreen,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xffedf4eb)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x140d3d0c),
          blurRadius: 20,
          offset: Offset(0, 9),
        ),
      ],
    ),
    child: Column(
      children: [
        Row(
          children: [
            Icon(
              Icons.calendar_month_rounded,
              size: compact ? 24 : 27,
              color: _ReviewColors.ink,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '今日复习计划',
                style: TextStyle(
                  color: _ReviewColors.ink,
                  fontSize: compact ? 18 : 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const _StreakBadge(),
          ],
        ),
        SizedBox(height: compact ? 4 : 6),
        SizedBox(
          height: compact ? 82 : 102,
          child: Row(
            children: [
              SizedBox(
                width: compact ? 72 : 86,
                height: compact ? 82 : 96,
                child: CustomPaint(painter: _CardCheckPainter()),
              ),
              SizedBox(width: compact ? 5 : 8),
              SizedBox(
                width: compact ? 84 : 104,
                child: _PlanCount(count: dueCount, compact: compact),
              ),
              SizedBox(width: compact ? 5 : 8),
              Expanded(
                child: _StartButton(compact: compact, onPressed: onStart),
              ),
            ],
          ),
        ),
        SizedBox(height: compact ? 4 : 6),
        Expanded(
          child: _DailyStatsRow(
            completed: completed,
            streakDays: streakDays,
            todayProgress: todayProgress,
            compact: compact,
          ),
        ),
      ],
    ),
  );
}

class _DailyStatsRow extends StatelessWidget {
  const _DailyStatsRow({
    required this.completed,
    required this.streakDays,
    required this.todayProgress,
    required this.compact,
  });

  final int completed;
  final int streakDays;
  final int todayProgress;
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _DailyStat(
          icon: Icons.track_changes_rounded,
          value: '$completed/5',
          label: '阶段目标',
          color: _ReviewColors.green,
          progress: completed / 5,
          compact: compact,
        ),
      ),
      _StatDivider(compact: compact),
      Expanded(
        child: _DailyStat(
          icon: Icons.calendar_month_rounded,
          value: '$streakDays 天',
          label: '连续坚持',
          color: _ReviewColors.green,
          progress: streakDays == 0 ? 0 : 1,
          compact: compact,
        ),
      ),
      _StatDivider(compact: compact),
      Expanded(
        child: _DailyStat(
          icon: Icons.emoji_events_rounded,
          value: '$todayProgress%',
          label: '今日进度',
          color: const Color(0xfff0a300),
          progress: todayProgress / 100,
          compact: compact,
        ),
      ),
    ],
  );
}

class _StatDivider extends StatelessWidget {
  const _StatDivider({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: compact ? 42 : 54,
    color: const Color(0xffedf1ed),
  );
}

class _DailyStat extends StatelessWidget {
  const _DailyStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.progress,
    required this.compact,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final double progress;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: compact ? 22 : 25),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: TextStyle(
                color: color == const Color(0xfff0a300)
                    ? _ReviewColors.darkGreen
                    : _ReviewColors.darkGreen,
                fontSize: compact ? 19 : 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 2),
      Text(
        label,
        maxLines: 1,
        style: TextStyle(
          color: _ReviewColors.ink,
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      SizedBox(height: compact ? 5 : 7),
      SizedBox(
        width: compact ? 64 : 82,
        height: compact ? 6 : 7,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress.clamp(0, 1),
            backgroundColor: const Color(0xffedf1ed),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: compact ? 6 : 7,
          ),
        ),
      ),
    ],
  );
}

class _PlanCount extends StatelessWidget {
  const _PlanCount({required this.count, required this.compact});

  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final displayCount = count > 999 ? '999+' : '$count';
    final countSize = compact
        ? (count > 999 ? 29.0 : 34.0)
        : (count > 999 ? 34.0 : 39.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          displayCount,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: _ReviewColors.darkGreen,
            fontSize: countSize,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '待复习卡片',
          maxLines: 1,
          style: TextStyle(
            color: _ReviewColors.ink,
            fontSize: compact ? 12 : 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.compact, required this.onPressed});

  final bool compact;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: compact ? 58 : 66,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _ReviewColors.green,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              '开始复习',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 16 : 19,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Container(
            width: compact ? 29 : 34,
            height: compact ? 29 : 34,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.play_arrow_rounded,
              color: _ReviewColors.green,
              size: compact ? 20 : 23,
            ),
          ),
        ],
      ),
    ),
  );
}

class _StreakBadge extends StatelessWidget {
  const _StreakBadge();

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 124),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(22),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.local_fire_department_outlined,
          color: _ReviewColors.green,
          size: 17,
        ),
        SizedBox(width: 4),
        Flexible(
          child: Text(
            '坚持就是胜利!',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _ReviewColors.green,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ProgressSection extends StatelessWidget {
  const _ProgressSection({
    required this.completed,
    required this.compact,
    required this.onDetails,
  });

  final int completed;
  final bool compact;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) => Container(
    height: compact ? 112 : 122,
    padding: EdgeInsets.fromLTRB(
      compact ? 12 : 18,
      compact ? 8 : 11,
      compact ? 12 : 18,
      compact ? 7 : 9,
    ),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      boxShadow: const [
        BoxShadow(
          color: Color(0x10000000),
          blurRadius: 18,
          offset: Offset(0, 7),
        ),
      ],
    ),
    child: Column(
      children: [
        SizedBox(
          height: 32,
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: _ReviewColors.softGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.insights_rounded,
                  color: _ReviewColors.green,
                  size: 18,
                ),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  '你的进度',
                  style: TextStyle(
                    color: _ReviewColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onDetails,
                style: TextButton.styleFrom(
                  foregroundColor: _ReviewColors.ink,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                label: const Text(
                  '查看详情',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: CustomPaint(
            size: const Size(double.infinity, 42),
            painter: _ProgressLinePainter(completed),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Text(
                '$completed/5 阶段已完成',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _ReviewColors.darkGreen,
                  fontSize: compact ? 11 : 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                completed == 5 ? '全部完成!' : '继续加油!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _ReviewColors.darkGreen,
                  fontSize: compact ? 11 : 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _MotivationBanner extends StatelessWidget {
  const _MotivationBanner({
    required this.completedToday,
    required this.hasCards,
    required this.compact,
  });

  final int completedToday;
  final bool hasCards;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    height: compact ? 102 : 112,
    padding: EdgeInsets.fromLTRB(
      compact ? 8 : 12,
      compact ? 3 : 5,
      compact ? 8 : 12,
      compact ? 3 : 5,
    ),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      boxShadow: const [
        BoxShadow(
          color: Color(0x10000000),
          blurRadius: 18,
          offset: Offset(0, 7),
        ),
      ],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: compact ? 132 : 150,
          height: compact ? 92 : 102,
          child: Image.asset(
            'assets/review_motivation.jpg',
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        ),
        SizedBox(width: compact ? 6 : 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: '保持'),
                    const TextSpan(
                      text: '学习',
                      style: TextStyle(color: _ReviewColors.green),
                    ),
                    const TextSpan(text: '的动力!'),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _ReviewColors.ink,
                  fontSize: compact ? 16 : 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _ReviewColors.ink,
                  fontSize: compact ? 12 : 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  String get _message {
    if (!hasCards) return '先添加一些卡片，\n每天进步一点点。';
    if (completedToday > 0) return '今天已经完成 $completedToday 张，\n继续保持这份节奏！';
    return '每天进步一点点，\n未来的你会感谢现在的努力！';
  }
}

class _ReviewError extends StatelessWidget {
  const _ReviewError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 44,
            color: _ReviewColors.green,
          ),
          const SizedBox(height: 12),
          const Text('无法加载复习数据，请重试。', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    ),
  );
}

class _CardCheckPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 132, size.height / 122);
    canvas.save();
    canvas.translate(size.width * .02, size.height * .04);
    canvas.scale(scale);
    final paint = Paint();
    for (final (offset, angle, color) in [
      (const Offset(22, 24), -.18, const Color(0x8fb3dda5)),
      (const Offset(45, 13), .1, const Color(0x7db0d9a1)),
      (const Offset(33, 33), .02, const Color(0xff7fbe70)),
    ]) {
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.rotate(angle);
      paint.color = color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 66, 78),
          const Radius.circular(8),
        ),
        paint,
      );
      canvas.restore();
    }
    canvas.drawCircle(const Offset(84, 79), 22, Paint()..color = Colors.white);
    canvas.drawPath(
      Path()
        ..moveTo(74, 79)
        ..lineTo(82, 87)
        ..lineTo(96, 70),
      Paint()
        ..color = _ReviewColors.green
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ProgressLinePainter extends CustomPainter {
  _ProgressLinePainter(this.completed);

  final int completed;

  @override
  void paint(Canvas canvas, Size size) {
    const horizontalPadding = 24.0;
    final y = size.height / 2;
    final spacing = (size.width - horizontalPadding * 2) / 4;
    final points = List.generate(
      5,
      (index) => Offset(horizontalPadding + spacing * index, y),
    );

    final linePaint = Paint()
      ..color = _ReviewColors.line
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(points.first, points.last, linePaint);
    if (completed > 1) {
      canvas.drawLine(
        points.first,
        points[completed - 1],
        Paint()
          ..color = _ReviewColors.green
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }

    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      if (index < completed) {
        canvas.drawCircle(point, 13, Paint()..color = _ReviewColors.green);
        canvas.drawPath(
          Path()
            ..moveTo(point.dx - 6, point.dy)
            ..lineTo(point.dx - 1, point.dy + 5)
            ..lineTo(point.dx + 6, point.dy - 6),
          Paint()
            ..color = Colors.white
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke,
        );
      } else {
        canvas.drawCircle(point, 13, Paint()..color = Colors.white);
        canvas.drawCircle(
          point,
          13,
          Paint()
            ..color = _ReviewColors.line
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        final label = TextPainter(
          text: TextSpan(
            text: '${index + 1}',
            style: const TextStyle(
              color: Color(0xffb9c0bb),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, point - Offset(label.width / 2, label.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressLinePainter oldDelegate) =>
      oldDelegate.completed != completed;
}
