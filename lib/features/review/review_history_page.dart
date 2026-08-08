import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../../core/models/card_model.dart';
import '../../core/widgets/app_layout.dart';

class ReviewHistoryPage extends ConsumerWidget {
  const ReviewHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(reviewEventsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('复习统计')),
      body: events.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('统计加载失败：$error')),
        data: (values) {
          final today = values
              .where((event) => _sameDay(event.reviewedAt, DateTime.now()))
              .toList();
          final ratingCounts = <String, int>{};
          for (final event in values) {
            ratingCounts[event.rating.label] =
                (ratingCounts[event.rating.label] ?? 0) + 1;
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              16,
              14,
              16,
              AppLayoutMetrics.bottomNavigationContentPadding + 30,
            ),
            children: [
              _StatsCard(total: values.length, today: today.length),
              const SizedBox(height: 18),
              Text(
                '评分分布',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ratingCounts.entries
                    .map(
                      (entry) =>
                          Chip(label: Text('${entry.key} ${entry.value}')),
                    )
                    .toList(),
              ),
              const SizedBox(height: 18),
              Text(
                '复习历史',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (values.isEmpty)
                const Text('完成复习后，这里会显示按时间倒序的复习记录。')
              else
                ...values.map(
                  (event) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child: Text(event.rating.value.toString()),
                    ),
                    title: Text(
                      event.question,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${event.folder} · ${event.rating.label} · ${_time(event.reviewedAt)}',
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
  String _time(DateTime value) =>
      '${value.month}/${value.day} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.total, required this.today});
  final int total;
  final int today;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Metric(label: '累计复习', value: '$total'),
          _Metric(label: '今日复习', value: '$today'),
        ],
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      Text(label),
    ],
  );
}
