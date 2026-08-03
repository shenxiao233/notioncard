import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_providers.dart';
import '../../core/models/account_model.dart';
import '../../core/network/api_config.dart';
import '../../core/sync/sync_controller.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/status_badge.dart';
import '../review/review_settings.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(currentAccountProvider);
    final cards = ref.watch(cardsProvider).valueOrNull?.length ?? 0;
    final documents = ref.watch(documentsProvider).valueOrNull?.length ?? 0;
    final sync = ref.watch(syncControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    final reviewSettings = ref.watch(reviewSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _AccountHeader(account: account),
          const SizedBox(height: 26),
          const SectionHeader(title: '本地内容', subtitle: '已缓存内容可在离线时继续使用'),
          const SizedBox(height: 10),
          _SettingsGroup(
            children: [
              _SettingsRow(
                icon: Icons.menu_book_outlined,
                title: '知识库文档',
                subtitle: '$documents 篇已缓存文档',
              ),
              _SettingsRow(
                icon: Icons.style_outlined,
                title: '复习卡片',
                subtitle: '$cards 张本地卡片',
              ),
            ],
          ),
          const SizedBox(height: 26),
          const SectionHeader(title: '同步', subtitle: '查看网络状态和待处理项目'),
          const SizedBox(height: 10),
          _SyncGroup(sync: sync, accountExists: account != null, ref: ref),
          const SizedBox(height: 26),
          const SectionHeader(title: '复习设置', subtitle: '调整 FSRS 每天加入复习计划的卡片数量'),
          const SizedBox(height: 10),
          _SettingsGroup(
            children: [
              _SettingsRow(
                icon: Icons.school_outlined,
                title: '每日新卡上限',
                subtitle: '每天最多加入 ${reviewSettings.newCardsPerDay} 张未学习卡片',
                trailing: const Icon(Icons.chevron_right_rounded),
                enabled: account != null,
                onTap: account == null
                    ? null
                    : () => _editLimit(context, ref, newCards: true),
              ),
              _SettingsRow(
                icon: Icons.replay_outlined,
                title: '每日复习上限',
                subtitle: '每天最多加入 ${reviewSettings.reviewsPerDay} 张到期卡片',
                trailing: const Icon(Icons.chevron_right_rounded),
                enabled: account != null,
                onTap: account == null
                    ? null
                    : () => _editLimit(context, ref, newCards: false),
              ),
            ],
          ),
          const SizedBox(height: 26),
          const SectionHeader(title: '内容权限', subtitle: '当前移动端以阅读和复习为主'),
          const SizedBox(height: 10),
          _SettingsGroup(
            children: [
              _SettingsRow(
                icon: Icons.lock_outline,
                title: '只读内容',
                subtitle: '文档、卡片和牌组不会在 App 内被修改',
                trailing: StatusBadge(
                  label: '只读',
                  icon: Icons.visibility_outlined,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              _SettingsRow(
                icon: Icons.task_alt_outlined,
                title: '允许写入',
                subtitle: '复习结果、FSRS 状态和同步队列',
                trailing: StatusBadge(
                  label: '已启用',
                  icon: Icons.check_circle_outline,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          const SectionHeader(title: '账户', subtitle: '管理当前登录会话'),
          const SizedBox(height: 10),
          _SettingsGroup(
            children: [
              _SettingsRow(
                icon: Icons.person_outline,
                title: account?.username ?? '未登录',
                subtitle: account == null
                    ? '登录后可同步内容'
                    : '账户状态：${account.status}',
              ),
              _SettingsRow(
                icon: Icons.logout,
                title: '退出登录',
                subtitle: '清除当前会话，不删除本地缓存',
                enabled: account != null,
                onTap: account == null
                    ? null
                    : () => _confirmLogout(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Center(
            child: Text(
              'KNcard · 移动端只读复习版',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editLimit(
    BuildContext context,
    WidgetRef ref, {
    required bool newCards,
  }) async {
    final settings = ref.read(reviewSettingsProvider);
    final controller = TextEditingController(
      text: '${newCards ? settings.newCardsPerDay : settings.reviewsPerDay}',
    );
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(newCards ? '每日新卡上限' : '每日复习上限'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '卡片数量',
            helperText: '可填写 0 - 9999',
          ),
          onSubmitted: (_) {
            final parsed = int.tryParse(controller.text);
            if (parsed != null) Navigator.of(dialogContext).pop(parsed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text);
              if (parsed != null) Navigator.of(dialogContext).pop(parsed);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !context.mounted) return;
    if (newCards) {
      await ref.read(reviewSettingsProvider.notifier).setNewCardsPerDay(value);
    } else {
      await ref.read(reviewSettingsProvider.notifier).setReviewsPerDay(value);
    }
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出当前账户？'),
        content: const Text('退出后仍保留本地缓存，重新登录后可以继续同步。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.account});

  final AccountModel? account;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _AccountAvatar(account: account, scheme: scheme),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account?.nickname ?? '欢迎使用 KNcard',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  account == null ? '登录后同步你的学习内容' : account?.username ?? '',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          StatusBadge(
            label: account == null ? '未登录' : '已登录',
            icon: account == null
                ? Icons.person_off_outlined
                : Icons.verified_user_outlined,
            backgroundColor: Colors.white.withValues(alpha: 0.6),
            foregroundColor: scheme.onPrimaryContainer,
          ),
        ],
      ),
    );
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.account, required this.scheme});

  final AccountModel? account;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final source = account?.avatar?.trim();
    final image = _avatarImage(source);
    return CircleAvatar(
      radius: 28,
      backgroundColor: scheme.primary,
      child: image != null
          ? ClipOval(
              child: SizedBox.square(
                dimension: 56,
                child: Image(
                  image: image,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _fallback(context),
                ),
              ),
            )
          : Text(
              account == null ? ' ' : _initial(account!),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }

  Widget _fallback(BuildContext context) {
    return Center(
      child: Text(
        account == null ? ' ' : _initial(account!),
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: scheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  ImageProvider<Object>? _avatarImage(String? source) {
    if (source == null || source.isEmpty) return null;
    if (source.startsWith('data:image/')) {
      final comma = source.indexOf(',');
      if (comma < 0) return null;
      try {
        return MemoryImage(base64Decode(source.substring(comma + 1)));
      } catch (_) {
        return null;
      }
    }
    final uri = Uri.tryParse(source);
    if (uri == null) return null;
    if (uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return NetworkImage(uri.toString());
    }
    final base = Uri.tryParse(ApiConfig.defaultBaseUrl);
    final resolved = base?.resolve(source);
    return resolved == null ? null : NetworkImage(resolved.toString());
  }

  String _initial(AccountModel value) {
    final name = value.nickname.trim().isNotEmpty
        ? value.nickname.trim()
        : value.username.trim();
    return name.isEmpty
        ? '?'
        : String.fromCharCode(name.runes.first).toUpperCase();
  }
}

class _SyncGroup extends StatelessWidget {
  const _SyncGroup({
    required this.sync,
    required this.accountExists,
    required this.ref,
  });

  final SyncUiState sync;
  final bool accountExists;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final offline = sync.connection == SyncConnectionState.offline;
    final failure = sync.phase == SyncPhase.failure;
    return _SettingsGroup(
      children: [
        _SettingsRow(
          icon: offline
              ? Icons.cloud_off_outlined
              : sync.isBusy
              ? Icons.sync
              : Icons.cloud_done_outlined,
          title: offline
              ? '当前离线'
              : sync.isBusy
              ? '正在同步'
              : failure
              ? '同步失败'
              : '连接正常',
          subtitle: _syncDescription(sync),
          trailing: StatusBadge(
            label: offline
                ? '离线可用'
                : sync.isBusy
                ? '处理中'
                : failure
                ? '需重试'
                : '在线',
            icon: offline
                ? Icons.cloud_off_outlined
                : failure
                ? Icons.error_outline
                : Icons.cloud_done_outlined,
            backgroundColor: offline || failure
                ? scheme.secondaryContainer
                : scheme.primaryContainer,
            foregroundColor: offline || failure
                ? scheme.onSecondaryContainer
                : scheme.onPrimaryContainer,
          ),
        ),
        _SettingsRow(
          icon: Icons.pending_actions_outlined,
          title: '待同步项目',
          subtitle: sync.pending == 0
              ? '没有等待处理的本地变更'
              : '${sync.pending} 个项目等待处理',
          trailing: sync.pending > 0
              ? TextButton(
                  onPressed: !accountExists || sync.isBusy
                      ? null
                      : () => ref
                            .read(syncControllerProvider.notifier)
                            .retryPending(),
                  child: const Text('重试'),
                )
              : null,
        ),
        _SettingsRow(
          icon: Icons.schedule_outlined,
          title: '最近同步',
          subtitle: sync.lastSyncedAt == null
              ? '尚未完成同步'
              : DateFormat(
                  'yyyy年M月d日 H:mm',
                ).format(sync.lastSyncedAt!.toLocal()),
          trailing: TextButton(
            onPressed: !accountExists || sync.isBusy
                ? null
                : () => ref.read(syncControllerProvider.notifier).sync(),
            child: Text(sync.isBusy ? '同步中' : '立即同步'),
          ),
        ),
        if (failure && sync.message != null)
          _SettingsRow(
            icon: Icons.info_outline,
            title: '最近失败原因',
            subtitle: sync.message!,
          ),
      ],
    );
  }

  String _syncDescription(SyncUiState sync) {
    if (sync.phase == SyncPhase.syncing) return '正在同步本地内容，阅读和复习不会被阻塞';
    if (sync.connection == SyncConnectionState.offline) {
      return '本地缓存可用，网络恢复后会自动同步';
    }
    if (sync.phase == SyncPhase.failure) return '同步没有完成，可以手动重试';
    if (sync.pending > 0) return '有本地复习结果等待上传';
    return '同步状态正常';
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              const Divider(indent: 56, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.enabled = true,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? Theme.of(context).colorScheme.onSurface
        : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    return ListTile(
      enabled: enabled,
      onTap: onTap,
      leading: Icon(icon, color: color),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: trailing,
      minVerticalPadding: 12,
    );
  }
}
