import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../../core/models/card_model.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_visuals.dart';
import 'study_statistics.dart';

const _statsBlue = Color(0xff377fdc);
const _statsGreen = Color(0xff7aa676);
const _statsAmber = Color(0xffc9a36d);
const _statsRed = Color(0xffd26c68);

class StatisticsPage extends ConsumerStatefulWidget {
  const StatisticsPage({super.key});

  @override
  ConsumerState<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends ConsumerState<StatisticsPage> {
  StudyStatsRange _range = StudyStatsRange.month;
  String? _folder;

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(cardsProvider);
    final events = ref.watch(reviewEventsProvider);

    return Scaffold(
      backgroundColor: AppVisualColors.background,
      body: SafeArea(
        bottom: false,
        child: cards.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppVisualColors.green),
          ),
          error: (_, _) => _StatisticsError(onRetry: _refresh),
          data: (cardValues) => events.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppVisualColors.green),
            ),
            error: (_, _) => _StatisticsError(onRetry: _refresh),
            data: (eventValues) {
              final folders = _folders(cardValues);
              final folder = folders.contains(_folder) ? _folder : null;
              final statistics = buildStudyStatistics(
                cards: cardValues,
                events: eventValues,
                range: _range,
                folder: folder,
              );
              return _StatisticsContent(
                statistics: statistics,
                folders: folders,
                selectedFolder: folder,
                onRangeChanged: (range) => setState(() => _range = range),
                onFolderChanged: (value) => setState(() => _folder = value),
                onRefresh: _refresh,
                onChooseFolder: () => _showFolderPicker(folders, folder),
              );
            },
          ),
        ),
      ),
    );
  }

  List<String> _folders(List<CardModel> cards) {
    final values = cards
        .map((card) => card.folder.trim())
        .where((folder) => folder.isNotEmpty)
        .toSet()
        .toList();
    values.sort();
    return values;
  }

  Future<void> _showFolderPicker(List<String> folders, String? selected) async {
    final value = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            16,
            0,
            16,
            AppLayoutMetrics.bottomNavigationContentPadding + 18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  '统计范围',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              _FolderOption(
                title: '全部牌组',
                selected: selected == null,
                onTap: () => Navigator.of(sheetContext).pop(),
              ),
              ...folders.map(
                (folder) => _FolderOption(
                  title: folder,
                  selected: folder == selected,
                  onTap: () => Navigator.of(sheetContext).pop(folder),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _folder = value);
  }

  Future<void> _refresh() async {
    await ref
        .read(syncControllerProvider.notifier)
        .sync(reason: 'statistics-refresh');
    ref.invalidate(cardsProvider);
    ref.invalidate(reviewEventsProvider);
    await Future.wait([
      ref.read(cardsProvider.future),
      ref.read(reviewEventsProvider.future),
    ]);
  }
}

class _StatisticsContent extends StatelessWidget {
  const _StatisticsContent({
    required this.statistics,
    required this.folders,
    required this.selectedFolder,
    required this.onRangeChanged,
    required this.onFolderChanged,
    required this.onRefresh,
    required this.onChooseFolder,
  });

  final StudyStatistics statistics;
  final List<String> folders;
  final String? selectedFolder;
  final ValueChanged<StudyStatsRange> onRangeChanged;
  final ValueChanged<String?> onFolderChanged;
  final Future<void> Function() onRefresh;
  final VoidCallback onChooseFolder;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    color: AppVisualColors.green,
    backgroundColor: Colors.white,
    onRefresh: onRefresh,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(
        16,
        12,
        16,
        AppLayoutMetrics.bottomNavigationContentPadding + 28,
      ),
      children: [
        _StatisticsHeader(
          range: statistics.range,
          onRangeChanged: onRangeChanged,
        ),
        const SizedBox(height: 12),
        _FolderFilter(
          folders: folders,
          selectedFolder: selectedFolder,
          onChanged: onFolderChanged,
          onChoose: onChooseFolder,
        ),
        const SizedBox(height: 14),
        _OverviewPanel(statistics: statistics),
        const SizedBox(height: 12),
        _KpiRow(statistics: statistics),
        const SizedBox(height: 14),
        _TrendPanel(statistics: statistics),
        const SizedBox(height: 14),
        _DeckDimensionPanel(statistics: statistics),
      ],
    ),
  );
}

class _StatisticsHeader extends StatelessWidget {
  const _StatisticsHeader({required this.range, required this.onRangeChanged});

  final StudyStatsRange range;
  final ValueChanged<StudyStatsRange> onRangeChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '学习统计',
        style: TextStyle(
          color: AppVisualColors.ink,
          fontSize: 27,
          fontWeight: FontWeight.w800,
          height: 1.15,
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<StudyStatsRange>(
          segments: const [
            ButtonSegment(value: StudyStatsRange.week, label: Text('本周')),
            ButtonSegment(value: StudyStatsRange.month, label: Text('本月')),
            ButtonSegment(value: StudyStatsRange.all, label: Text('全部')),
          ],
          selected: {range},
          showSelectedIcon: false,
          onSelectionChanged: (values) {
            final value = values.firstOrNull;
            if (value != null) onRangeChanged(value);
          },
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            ),
            textStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? AppVisualColors.darkGreen
                  : AppVisualColors.muted,
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? AppVisualColors.softGreen
                  : Colors.white,
            ),
            side: WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: states.contains(WidgetState.selected)
                    ? AppVisualColors.green.withValues(alpha: 0.52)
                    : AppVisualColors.line,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _FolderFilter extends StatelessWidget {
  const _FolderFilter({
    required this.folders,
    required this.selectedFolder,
    required this.onChanged,
    required this.onChoose,
  });

  final List<String> folders;
  final String? selectedFolder;
  final ValueChanged<String?> onChanged;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Text(
        '牌组范围',
        style: TextStyle(
          color: AppVisualColors.muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const Spacer(),
      if (folders.isEmpty)
        const Text(
          '暂无牌组',
          style: TextStyle(color: AppVisualColors.muted, fontSize: 13),
        )
      else
        OutlinedButton.icon(
          onPressed: onChoose,
          icon: const Icon(Icons.filter_list_rounded, size: 17),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              selectedFolder ?? '全部牌组',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppVisualColors.ink,
            backgroundColor: Colors.white,
            minimumSize: const Size(0, 38),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            side: const BorderSide(color: AppVisualColors.line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
    ],
  );
}

class _OverviewPanel extends StatelessWidget {
  const _OverviewPanel({required this.statistics});

  final StudyStatistics statistics;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _OverviewMetric(
                value: statistics.learnedCards,
                label: '已学习卡片',
                color: _statsBlue,
              ),
            ),
            const _VerticalRule(),
            Expanded(
              child: _OverviewMetric(
                value: statistics.masteredCards,
                label: '已掌握',
                color: _statsGreen,
              ),
            ),
            const _VerticalRule(),
            Expanded(
              child: _OverviewMetric(
                value: statistics.forgottenCards,
                label: '当前忘记',
                color: _statsRed,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 13),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 8,
          children: [
            _InlineMetric(
              value: statistics.streakDays,
              label: '连续学习',
              color: _statsAmber,
            ),
            _InlineMetric(
              value: statistics.reviewCount,
              label: '本期复习',
              color: _statsBlue,
            ),
            _InlineMetric(
              value: statistics.totalCards,
              label: '题库卡片',
              color: _statsGreen,
            ),
          ],
        ),
      ],
    ),
  );
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.statistics});

  final StudyStatistics statistics;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _KpiPanel(
          label: '掌握率',
          value: '${(statistics.masteryRate * 100).round()}%',
          color: _statsGreen,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _KpiPanel(
          label: '待复习',
          value: '${statistics.dueCards}',
          color: _statsAmber,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _KpiPanel(
          label: '未学新卡',
          value: '${statistics.newCards}',
          color: _statsBlue,
        ),
      ),
    ],
  );
}

class _TrendPanel extends StatelessWidget {
  const _TrendPanel({required this.statistics});

  final StudyStatistics statistics;

  @override
  Widget build(BuildContext context) => _Panel(
    padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '学习反馈趋势',
          style: TextStyle(
            color: AppVisualColors.ink,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        const Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            _Legend(color: _statsBlue, label: '复习次数'),
            _Legend(color: _statsGreen, label: '掌握'),
            _Legend(color: _statsAmber, label: '模糊'),
            _Legend(color: _statsRed, label: '忘记'),
          ],
        ),
        const SizedBox(height: 8),
        if (statistics.reviewCount == 0)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 56),
            child: Center(
              child: Text(
                '选择牌组开始复习后，这里会显示趋势',
                style: TextStyle(color: AppVisualColors.muted, fontSize: 13),
              ),
            ),
          )
        else
          _TrendChart(points: statistics.trend),
        if (statistics.reviewedCardCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '本期复习 ${statistics.reviewedCardCount} 张不同卡片',
              style: const TextStyle(
                color: AppVisualColors.muted,
                fontSize: 12,
              ),
            ),
          ),
      ],
    ),
  );
}

class _DeckDimensionPanel extends StatelessWidget {
  const _DeckDimensionPanel({required this.statistics});

  final StudyStatistics statistics;

  @override
  Widget build(BuildContext context) => _Panel(
    padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '题库维度',
          style: TextStyle(
            color: AppVisualColors.ink,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        if (statistics.decks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                '还没有可以统计的卡片',
                style: TextStyle(color: AppVisualColors.muted, fontSize: 13),
              ),
            ),
          )
        else
          for (var index = 0; index < statistics.decks.length; index++) ...[
            if (index > 0) const Divider(height: 24),
            _DeckSummary(deck: statistics.decks[index]),
          ],
      ],
    ),
  );
}

class _DeckSummary extends StatelessWidget {
  const _DeckSummary({required this.deck});

  final StudyDeckStatistics deck;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              deck.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppVisualColors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${deck.total} 张卡',
            style: const TextStyle(color: AppVisualColors.muted, fontSize: 12),
          ),
        ],
      ),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          minHeight: 8,
          value: deck.progress.clamp(0, 1),
          backgroundColor: const Color(0xffedf2ef),
          valueColor: const AlwaysStoppedAnimation(_statsGreen),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 12,
        runSpacing: 5,
        children: [
          _DeckValue(label: '已学', value: deck.learned, color: _statsBlue),
          _DeckValue(label: '掌握', value: deck.mastered, color: _statsGreen),
          _DeckValue(label: '模糊', value: deck.fuzzy, color: _statsAmber),
          _DeckValue(label: '忘记', value: deck.forgotten, color: _statsRed),
          _DeckValue(label: '待复习', value: deck.due, color: _statsAmber),
          _DeckValue(label: '新卡', value: deck.newCards, color: _statsBlue),
        ],
      ),
    ],
  );
}

class _TrendChart extends StatefulWidget {
  const _TrendChart({required this.points});

  final List<StudyTrendPoint> points;

  @override
  State<_TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<_TrendChart> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final selected = _selectedIndex == null || widget.points.isEmpty
        ? null
        : widget.points[_selectedIndex!.clamp(0, widget.points.length - 1)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            if (widget.points.length < 2) return;
            final width = context.size?.width ?? 0;
            if (width <= 0) return;
            final ratio = (details.localPosition.dx / width).clamp(0.0, 1.0);
            setState(
              () =>
                  _selectedIndex = (ratio * (widget.points.length - 1)).round(),
            );
          },
          child: SizedBox(
            height: 242,
            width: double.infinity,
            child: CustomPaint(
              painter: _TrendPainter(
                points: widget.points,
                selectedIndex: _selectedIndex,
              ),
            ),
          ),
        ),
        if (selected != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(38, 2, 0, 0),
            child: Text(
              '${selected.date.month}/${selected.date.day}  ·  复习 ${selected.reviewed}  掌握 ${selected.mastered}  模糊 ${selected.fuzzy}  忘记 ${selected.forgotten}',
              style: const TextStyle(
                color: AppVisualColors.muted,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.points, required this.selectedIndex});

  final List<StudyTrendPoint> points;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const left = 36.0;
    const top = 12.0;
    const bottom = 28.0;
    const right = 6.0;
    final chart = Rect.fromLTRB(
      left,
      top,
      math.max(left + 1, size.width - right),
      math.max(top + 1, size.height - bottom),
    );
    final maxValue = math.max(
      1,
      points.fold<int>(0, (maximum, point) => math.max(maximum, point.maximum)),
    );
    final gridPaint = Paint()
      ..color = AppVisualColors.line.withValues(alpha: 0.72)
      ..strokeWidth = 1;
    final axisStyle = const TextStyle(
      color: AppVisualColors.muted,
      fontSize: 10,
    );
    for (var index = 0; index < 5; index++) {
      final ratio = index / 4;
      final y = chart.bottom - chart.height * ratio;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      _drawText(
        canvas,
        '${(maxValue * ratio).round()}',
        Offset(0, y - 7),
        axisStyle,
        width: chart.left - 8,
        align: TextAlign.right,
      );
    }

    final series = [
      (color: _statsBlue, value: (StudyTrendPoint point) => point.reviewed),
      (color: _statsGreen, value: (StudyTrendPoint point) => point.mastered),
      (color: _statsAmber, value: (StudyTrendPoint point) => point.fuzzy),
      (color: _statsRed, value: (StudyTrendPoint point) => point.forgotten),
    ];
    for (final item in series) {
      final path = Path();
      for (var index = 0; index < points.length; index++) {
        final x = points.length == 1
            ? chart.center.dx
            : chart.left + chart.width * index / (points.length - 1);
        final y =
            chart.bottom - chart.height * item.value(points[index]) / maxValue;
        final offset = Offset(x, y);
        if (index == 0) {
          path.moveTo(offset.dx, offset.dy);
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = item.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final selected = selectedIndex;
    if (selected != null && selected >= 0 && selected < points.length) {
      final x = points.length == 1
          ? chart.center.dx
          : chart.left + chart.width * selected / (points.length - 1);
      final guidePaint = Paint()
        ..color = AppVisualColors.muted.withValues(alpha: 0.35)
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(x, chart.top),
        Offset(x, chart.bottom),
        guidePaint,
      );
      for (final item in series) {
        final y =
            chart.bottom -
            chart.height * item.value(points[selected]) / maxValue;
        canvas.drawCircle(
          Offset(x, y),
          5,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(Offset(x, y), 4, Paint()..color = item.color);
      }
    }

    final labelIndices = points.length <= 3
        ? List<int>.generate(points.length, (index) => index)
        : [0, (points.length - 1) ~/ 2, points.length - 1];
    for (final index in labelIndices.toSet()) {
      final x = points.length == 1
          ? chart.center.dx
          : chart.left + chart.width * index / (points.length - 1);
      _drawText(
        canvas,
        '${points[index].date.month}/${points[index].date.day}',
        Offset(x - 22, chart.bottom + 8),
        axisStyle,
        width: 44,
        align: TextAlign.center,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.selectedIndex != selectedIndex;

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style, {
    required double width,
    required TextAlign align,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: width);
    painter.paint(canvas, offset);
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppVisualColors.line.withValues(alpha: 0.72)),
    ),
    child: child,
  );
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
    required this.value,
    required this.label,
    required this.color,
  });

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        '$value',
        style: TextStyle(
          color: color,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
      const SizedBox(height: 7),
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppVisualColors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _InlineMetric extends StatelessWidget {
  const _InlineMetric({
    required this.value,
    required this.label,
    required this.color,
  });

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => RichText(
    text: TextSpan(
      style: const TextStyle(
        color: AppVisualColors.muted,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      children: [
        TextSpan(
          text: '$value',
          style: TextStyle(color: color, fontSize: 16),
        ),
        TextSpan(text: ' $label'),
      ],
    ),
  );
}

class _KpiPanel extends StatelessWidget {
  const _KpiPanel({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => _Panel(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 15),
    child: Column(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppVisualColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ],
    ),
  );
}

class _DeckValue extends StatelessWidget {
  const _DeckValue({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => RichText(
    text: TextSpan(
      style: const TextStyle(
        color: AppVisualColors.muted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      children: [
        TextSpan(
          text: '$value',
          style: TextStyle(color: color, fontSize: 15),
        ),
        TextSpan(text: ' $label'),
      ],
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(
          color: AppVisualColors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _VerticalRule extends StatelessWidget {
  const _VerticalRule();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 48, color: AppVisualColors.line);
}

class _FolderOption extends StatelessWidget {
  const _FolderOption({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    tileColor: selected ? AppVisualColors.softGreen : null,
    leading: Icon(
      selected
          ? Icons.radio_button_checked_rounded
          : Icons.radio_button_unchecked_rounded,
      color: selected ? AppVisualColors.green : AppVisualColors.muted,
    ),
    title: Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
  );
}

class _StatisticsError extends StatelessWidget {
  const _StatisticsError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.analytics_outlined,
            size: 42,
            color: AppVisualColors.muted,
          ),
          const SizedBox(height: 12),
          const Text(
            '统计加载失败',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text('请刷新后重试。', style: TextStyle(color: AppVisualColors.muted)),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ],
      ),
    ),
  );
}
