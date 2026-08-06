import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_providers.dart';
import '../../core/models/account_model.dart';
import '../../core/network/api_config.dart';
import '../../core/sync/sync_controller.dart';
import '../../core/update/app_update_controller.dart';
import '../review/review_settings.dart';

abstract final class _ProfileColors {
  static const background = Color(0xfff5f8f5);
  static const ink = Color(0xff111412);
  static const muted = Color(0xff6f7975);
  static const green = Color(0xff26983b);
  static const darkGreen = Color(0xff187c2d);
  static const softGreen = Color(0xffeff8ef);
  static const line = Color(0xffe3e9e4);
  static const blue = Color(0xff2699e8);
  static const softBlue = Color(0xffedf7ff);
  static const amber = Color(0xffc48418);
}

abstract final class _ProfileTypography {
  static const name = TextStyle(
    color: _ProfileColors.ink,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.15,
  );
  static const username = TextStyle(
    color: _ProfileColors.darkGreen,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
  static const tagline = TextStyle(
    color: _ProfileColors.muted,
    fontSize: 12,
    height: 1.3,
  );
  static const statValue = TextStyle(
    color: _ProfileColors.ink,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1,
  );
  static const statLabel = TextStyle(
    color: _ProfileColors.muted,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
  static const sectionTitle = TextStyle(
    color: _ProfileColors.ink,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
  static const sectionHint = TextStyle(
    color: _ProfileColors.muted,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );
  static const rowTitle = TextStyle(
    color: _ProfileColors.ink,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );
  static const rowBody = TextStyle(
    color: _ProfileColors.muted,
    fontSize: 12,
    height: 1.35,
  );
  static const rowValue = TextStyle(
    color: _ProfileColors.darkGreen,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
  static const badge = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
  static const action = TextStyle(
    color: _ProfileColors.darkGreen,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
  static const motivationTitle = TextStyle(
    color: _ProfileColors.ink,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
  static const motivationBody = TextStyle(
    color: _ProfileColors.muted,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.25,
  );
  static const button = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
  static const avatarInitial = TextStyle(
    color: _ProfileColors.darkGreen,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    height: 1,
  );
}

ButtonStyle _compactTextButtonStyle() => TextButton.styleFrom(
  foregroundColor: _ProfileColors.darkGreen,
  minimumSize: Size.zero,
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  textStyle: _ProfileTypography.action,
);

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(currentAccountProvider);
    final cards = ref.watch(cardsProvider).valueOrNull?.length ?? 0;
    final documents = ref.watch(documentsProvider).valueOrNull?.length ?? 0;
    final sync = ref.watch(syncControllerProvider);
    final reviewSettings = ref.watch(reviewSettingsProvider);
    final update = ref.watch(appUpdateControllerProvider);

    return Scaffold(
      backgroundColor: _ProfileColors.background,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 390;
            return RefreshIndicator(
              color: _ProfileColors.green,
              backgroundColor: Colors.white,
              onRefresh: () => _refreshPage(ref),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 20,
                  6,
                  compact ? 16 : 20,
                  22,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProfileHero(
                          account: account,
                          onAccountActions: () =>
                              _showAccountActions(context, ref),
                          onNotifications: () => _showNotifications(context),
                        ),
                        const SizedBox(height: 12),
                        _ProfileStats(
                          documents: documents,
                          cards: cards,
                          pending: sync.pending,
                          compact: compact,
                        ),
                        const SizedBox(height: 16),
                        _ProfileSectionHeader(
                          title: '复习设置',
                          accent: _ProfileColors.green,
                          trailing: compact
                              ? null
                              : const _SectionTrailing(label: '管理我的学习计划'),
                        ),
                        const SizedBox(height: 8),
                        _SettingsGroup(
                          dividerIndent: 22,
                          children: [
                            _SettingsRow(
                              title: '每日新卡上限',
                              subtitle:
                                  '每天最多加入 ${reviewSettings.newCardsPerDay} 张未学习卡片',
                              trailing: _ValueTrailing(
                                value: '${reviewSettings.newCardsPerDay} 张',
                              ),
                              enabled: account != null,
                              onTap: account == null
                                  ? null
                                  : () => _editLimit(
                                      context,
                                      ref,
                                      newCards: true,
                                    ),
                            ),
                            _SettingsRow(
                              title: '每日复习上限',
                              subtitle:
                                  '每天最多加入 ${reviewSettings.reviewsPerDay} 张到期卡片',
                              trailing: _ValueTrailing(
                                value: '${reviewSettings.reviewsPerDay} 张',
                              ),
                              enabled: account != null,
                              onTap: account == null
                                  ? null
                                  : () => _editLimit(
                                      context,
                                      ref,
                                      newCards: false,
                                    ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _ProfileSectionHeader(
                          title: '同步',
                          accent: _ProfileColors.blue,
                          trailing: compact
                              ? null
                              : const _SectionTrailing(label: '数据安全，随时可用'),
                        ),
                        const SizedBox(height: 8),
                        _SyncGroup(
                          sync: sync,
                          accountExists: account != null,
                          ref: ref,
                        ),
                        const SizedBox(height: 14),
                        _MotivationCard(onPressed: () => context.go('/review')),
                        if (update.status != AppUpdateStatus.idle ||
                            update.hasUpdate) ...[
                          const SizedBox(height: 16),
                          const _ProfileSectionHeader(
                            title: '应用更新',
                            accent: _ProfileColors.amber,
                          ),
                          const SizedBox(height: 8),
                          _UpdateGroup(update: update, ref: ref),
                        ],
                        const SizedBox(height: 16),
                        const _ProfileSectionHeader(
                          title: '账户',
                          accent: _ProfileColors.muted,
                        ),
                        const SizedBox(height: 8),
                        _SettingsGroup(
                          children: [
                            _SettingsRow(
                              icon: Icons.logout_rounded,
                              title: '退出登录',
                              subtitle: '清除当前会话，不删除本地缓存',
                              enabled: account != null,
                              onTap: account == null
                                  ? null
                                  : () => _confirmLogout(context, ref),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _refreshPage(WidgetRef ref) async {
    await ref
        .read(syncControllerProvider.notifier)
        .sync(reason: 'settings-refresh');
    ref.invalidate(cardsProvider);
    ref.invalidate(documentsProvider);
    await Future.wait([
      ref.read(cardsProvider.future),
      ref.read(documentsProvider.future),
    ]);
  }

  Future<void> _showAccountActions(BuildContext context, WidgetRef ref) async {
    final account = ref.read(currentAccountProvider);
    if (account == null) {
      _showMessage(context, '登录后可以管理账户');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: const Icon(Icons.logout_rounded),
            title: const Text('退出登录'),
            subtitle: Text(account.username),
            onTap: () {
              Navigator.of(sheetContext).pop();
              _confirmLogout(context, ref);
            },
          ),
        ),
      ),
    );
  }

  void _showNotifications(BuildContext context) {
    _showMessage(context, '暂无新的通知');
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editLimit(
    BuildContext context,
    WidgetRef ref, {
    required bool newCards,
  }) async {
    final settings = ref.read(reviewSettingsProvider);
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _ReviewLimitDialog(
        title: newCards ? '每日新卡上限' : '每日复习上限',
        initialValue: newCards
            ? settings.newCardsPerDay
            : settings.reviewsPerDay,
      ),
    );
    if (value == null || !context.mounted) return;
    try {
      if (newCards) {
        await ref
            .read(reviewSettingsProvider.notifier)
            .setNewCardsPerDay(value);
      } else {
        await ref.read(reviewSettingsProvider.notifier).setReviewsPerDay(value);
      }
    } catch (_) {
      if (context.mounted) {
        _showMessage(context, '保存设置失败，请稍后重试');
      }
    }
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出当前账户？'),
        content: const Text('退出后仍保留本地缓存，重新登录后可以继续同步。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
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

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.account,
    required this.onAccountActions,
    required this.onNotifications,
  });

  final AccountModel? account;
  final VoidCallback onAccountActions;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final nickname = account?.nickname.trim();
    final username = account?.username.trim();
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ProfileActionButton(
                icon: Icons.settings_outlined,
                tooltip: '账户设置',
                onPressed: onAccountActions,
              ),
              const SizedBox(width: 6),
              _ProfileActionButton(
                icon: Icons.notifications_none_rounded,
                tooltip: '通知',
                onPressed: onNotifications,
                showDot: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _AccountAvatar(account: account),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nickname?.isNotEmpty == true ? nickname! : '欢迎回来',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _ProfileTypography.name,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: const BoxDecoration(
                      color: _ProfileColors.softGreen,
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    child: Text(
                      username?.isNotEmpty == true ? username! : '未登录',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _ProfileTypography.username,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text('专注学习，持续成长', style: _ProfileTypography.tagline),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProfileActionButton extends StatelessWidget {
  const _ProfileActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.showDot = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool showDot;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      label: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: 24,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 21, color: _ProfileColors.ink),
              if (showDot)
                Positioned(
                  right: 1,
                  top: 1,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xffe33c3c),
                      shape: BoxShape.circle,
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

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.account});

  final AccountModel? account;

  @override
  Widget build(BuildContext context) {
    final image = _avatarImage(account?.avatar?.trim());
    return Container(
      width: 70,
      height: 70,
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: image == null
            ? _fallback()
            : Image(
                image: image,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _fallback(),
              ),
      ),
    );
  }

  Widget _fallback() => Container(
    color: _ProfileColors.softGreen,
    alignment: Alignment.center,
    child: Text(
      account == null ? '?' : _initial(account!),
      style: _ProfileTypography.avatarInitial,
    ),
  );

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

class _ProfileStats extends StatelessWidget {
  const _ProfileStats({
    required this.documents,
    required this.cards,
    required this.pending,
    required this.compact,
  });

  final int documents;
  final int cards;
  final int pending;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    height: compact ? 86 : 90,
    padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 6, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _ProfileColors.line),
    ),
    child: Row(
      children: [
        Expanded(
          child: _ProfileStat(
            icon: Icons.menu_book_rounded,
            value: documents,
            label: '知识库文档',
            compact: compact,
          ),
        ),
        const _StatDivider(),
        Expanded(
          child: _ProfileStat(
            icon: Icons.style_rounded,
            value: cards,
            label: '复习卡片',
            compact: compact,
          ),
        ),
        const _StatDivider(),
        Expanded(
          child: _ProfileStat(
            icon: Icons.cloud_upload_rounded,
            value: pending,
            label: '待同步项目',
            compact: compact,
          ),
        ),
      ],
    ),
  );
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 50, color: _ProfileColors.line);
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.compact,
  });

  final IconData icon;
  final int value;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: _ProfileColors.green, size: compact ? 17 : 18),
          const SizedBox(width: 4),
          Text('$value', style: _ProfileTypography.statValue),
        ],
      ),
      const SizedBox(height: 5),
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _ProfileTypography.statLabel,
      ),
    ],
  );
}

class _ProfileSectionHeader extends StatelessWidget {
  const _ProfileSectionHeader({
    required this.title,
    required this.accent,
    this.trailing,
  });

  final String title;
  final Color accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Container(
        width: 4,
        height: 18,
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      const SizedBox(width: 6),
      Expanded(child: Text(title, style: _ProfileTypography.sectionTitle)),
      ?trailing,
    ],
  );
}

class _SectionTrailing extends StatelessWidget {
  const _SectionTrailing({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _ProfileTypography.sectionHint,
        ),
      ),
      const SizedBox(width: 4),
      const Icon(
        Icons.chevron_right_rounded,
        size: 16,
        color: _ProfileColors.muted,
      ),
    ],
  );
}

class _ValueTrailing extends StatelessWidget {
  const _ValueTrailing({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(value, style: _ProfileTypography.rowValue),
      const SizedBox(width: 4),
      const Icon(
        Icons.chevron_right_rounded,
        size: 16,
        color: _ProfileColors.muted,
      ),
    ],
  );
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children, this.dividerIndent = 72});

  final List<Widget> children;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: _ProfileColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index != children.length - 1)
            Divider(
              height: 1,
              indent: dividerIndent,
              endIndent: 22,
              color: _ProfileColors.line,
            ),
        ],
      ],
    ),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    required this.subtitle,
    this.icon,
    this.trailing,
    this.enabled = true,
    this.onTap,
    this.iconColor,
    this.iconBackground,
  });

  final IconData? icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool enabled;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? iconBackground;

  @override
  Widget build(BuildContext context) {
    final titleColor = enabled
        ? _ProfileColors.ink
        : _ProfileColors.muted.withValues(alpha: 0.5);
    final subtitleColor = enabled
        ? _ProfileColors.muted
        : _ProfileColors.muted.withValues(alpha: 0.5);
    final accent = enabled
        ? iconColor ?? _ProfileColors.green
        : _ProfileColors.muted.withValues(alpha: 0.45);
    return ListTile(
      enabled: enabled,
      onTap: onTap,
      dense: true,
      contentPadding: EdgeInsets.symmetric(
        horizontal: icon == null ? 16 : 12,
        vertical: icon == null ? 4 : 3,
      ),
      leading: icon == null
          ? null
          : Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBackground ?? _ProfileColors.softGreen,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accent, size: 19),
            ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _ProfileTypography.rowTitle.copyWith(color: titleColor),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: _ProfileTypography.rowBody.copyWith(color: subtitleColor),
        ),
      ),
      trailing: trailing,
      minVerticalPadding: 2,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, this.warning = false});

  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: warning ? const Color(0xfffff4e1) : _ProfileColors.softGreen,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      style: _ProfileTypography.badge.copyWith(
        color: warning ? _ProfileColors.amber : _ProfileColors.darkGreen,
      ),
    ),
  );
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
    final offline = sync.connection == SyncConnectionState.offline;
    final failure = sync.phase == SyncPhase.failure;
    final statusColor = offline || failure
        ? _ProfileColors.amber
        : _ProfileColors.green;
    final statusLabel = offline
        ? '离线'
        : sync.isBusy
        ? '同步中'
        : failure
        ? '需重试'
        : '在线';
    return _SettingsGroup(
      dividerIndent: 84,
      children: [
        _SettingsRow(
          icon: offline
              ? Icons.cloud_off_outlined
              : sync.isBusy
              ? Icons.sync_rounded
              : Icons.cloud_done_outlined,
          iconColor: statusColor,
          iconBackground: _ProfileColors.softBlue,
          title: '连接状态',
          subtitle: _syncDescription(sync),
          trailing: _StatusBadge(
            label: statusLabel,
            warning: offline || failure,
          ),
        ),
        _SettingsRow(
          icon: Icons.pending_actions_outlined,
          iconColor: _ProfileColors.blue,
          iconBackground: _ProfileColors.softBlue,
          title: '待同步项目',
          subtitle: sync.pending == 0
              ? '没有等待处理的本地更改'
              : '${sync.pending} 个项目等待处理',
          trailing: sync.pending > 0
              ? TextButton(
                  style: _compactTextButtonStyle(),
                  onPressed: !accountExists || sync.isBusy
                      ? null
                      : () => ref
                            .read(syncControllerProvider.notifier)
                            .retryPending(),
                  child: const Text('重试'),
                )
              : const _ValueTrailing(value: '0 项'),
        ),
        _SettingsRow(
          icon: Icons.history_rounded,
          iconColor: _ProfileColors.blue,
          iconBackground: _ProfileColors.softBlue,
          title: '最近同步',
          subtitle: sync.lastSyncedAt == null
              ? '尚未完成同步'
              : _relativeTime(sync.lastSyncedAt!),
          trailing: _TextChevron(
            label: '查看历史',
            onTap: () => context.push('/review/history'),
          ),
          onTap: !accountExists || sync.isBusy
              ? null
              : () => ref.read(syncControllerProvider.notifier).sync(),
        ),
      ],
    );
  }

  String _syncDescription(SyncUiState sync) {
    if (sync.phase == SyncPhase.syncing) {
      return '正在同步本地内容，阅读和复习不会被阻塞';
    }
    if (sync.connection == SyncConnectionState.offline) {
      return '本地缓存可用，网络恢复后会自动同步';
    }
    if (sync.phase == SyncPhase.failure) {
      return '同步没有完成，可以手动重试';
    }
    if (sync.pending > 0) {
      return '有本地复习结果等待上传';
    }
    return '同步状态正常';
  }

  static String _relativeTime(DateTime value) {
    final difference = DateTime.now().difference(value.toLocal());
    if (difference.inSeconds < 60) return '刚刚';
    if (difference.inMinutes < 60) return '${difference.inMinutes} 分钟前';
    if (difference.inHours < 24) return '${difference.inHours} 小时前';
    if (difference.inDays < 7) return '${difference.inDays} 天前';
    return DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
  }
}

class _TextChevron extends StatelessWidget {
  const _TextChevron({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: _ProfileTypography.action),
        const SizedBox(width: 3),
        const Icon(
          Icons.chevron_right_rounded,
          size: 16,
          color: _ProfileColors.muted,
        ),
      ],
    );
    return onTap == null
        ? content
        : InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: content,
            ),
          );
  }
}

class _MotivationCard extends StatelessWidget {
  const _MotivationCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      height: 112,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/review_motivation.jpg',
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
          const ColoredBox(color: Color(0x38f7fff0)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '学习是一场马拉松',
                  style: _ProfileTypography.motivationTitle,
                ),
                const SizedBox(height: 4),
                const Text(
                  '每天进步一点点，未来的你会感谢现在的坚持',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _ProfileTypography.motivationBody,
                ),
                const Spacer(),
                FilledButton(
                  onPressed: onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: _ProfileColors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(96, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: _ProfileTypography.button,
                  ),
                  child: const Text('继续学习'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _UpdateGroup extends StatelessWidget {
  const _UpdateGroup({required this.update, required this.ref});

  final AppUpdateState update;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final manifest = update.manifest;
    final busy =
        update.status == AppUpdateStatus.checking ||
        update.status == AppUpdateStatus.downloading ||
        update.status == AppUpdateStatus.installing;
    final availableManifest = update.hasUpdate ? manifest : null;
    final hasUpdate = availableManifest != null;
    final title = switch (update.status) {
      AppUpdateStatus.checking => '正在检查更新',
      AppUpdateStatus.downloading => '正在下载更新',
      AppUpdateStatus.installing => '正在准备安装',
      AppUpdateStatus.installed => '安装器已打开',
      AppUpdateStatus.error => '更新检查失败',
      AppUpdateStatus.upToDate => '已经是最新版本',
      AppUpdateStatus.available => '发现新版本',
      AppUpdateStatus.idle => '检查应用更新',
    };
    final subtitle = switch (update.status) {
      AppUpdateStatus.checking => '正在从服务器获取最新版本信息',
      AppUpdateStatus.downloading =>
        '已下载 ${(update.progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
      AppUpdateStatus.installing => update.message ?? '请稍候',
      AppUpdateStatus.installed => update.message ?? '请完成系统安装',
      AppUpdateStatus.error => update.message ?? '网络或更新包校验失败',
      AppUpdateStatus.upToDate => '当前没有可用更新',
      AppUpdateStatus.available =>
        'v${manifest?.versionName ?? ''} · ${manifest?.mandatory == true ? '必须更新' : '可选更新'}',
      AppUpdateStatus.idle => '检查服务器是否有新的应用版本',
    };
    return _SettingsGroup(
      children: [
        _SettingsRow(
          icon: hasUpdate
              ? Icons.new_releases_outlined
              : Icons.system_update_alt_rounded,
          title: title,
          subtitle: subtitle,
          trailing: hasUpdate
              ? TextButton(
                  style: _compactTextButtonStyle(),
                  onPressed: busy || !availableManifest.canDownload
                      ? null
                      : () => ref
                            .read(appUpdateControllerProvider.notifier)
                            .downloadAndInstall(),
                  child: Text(
                    update.status == AppUpdateStatus.error
                        ? '重试下载'
                        : availableManifest.mandatory
                        ? '立即更新'
                        : '下载更新',
                  ),
                )
              : TextButton(
                  style: _compactTextButtonStyle(),
                  onPressed: busy
                      ? null
                      : () => ref
                            .read(appUpdateControllerProvider.notifier)
                            .check(),
                  child: Text(busy ? '处理中' : '检查更新'),
                ),
        ),
        if (update.errorCode == 'install_permission_required')
          _SettingsRow(
            icon: Icons.security_outlined,
            title: '需要允许安装未知应用',
            subtitle: '开启权限后，才能安装从服务器下载的 APK',
            trailing: TextButton(
              style: _compactTextButtonStyle(),
              onPressed: () => ref
                  .read(appUpdateControllerProvider.notifier)
                  .openInstallPermissionSettings(),
              child: const Text('去开启'),
            ),
          ),
        if (availableManifest != null &&
            availableManifest.notes.trim().isNotEmpty)
          _SettingsRow(
            icon: Icons.notes_outlined,
            title: '更新说明',
            subtitle: availableManifest.notes.trim(),
          ),
        if (hasUpdate && !availableManifest.canDownload)
          const _SettingsRow(
            icon: Icons.verified_user_outlined,
            title: '暂不可下载此更新',
            subtitle: '服务端必须提供有效的 APK 地址和 SHA-256 校验值',
          ),
      ],
    );
  }
}

class _ReviewLimitDialog extends StatefulWidget {
  const _ReviewLimitDialog({required this.title, required this.initialValue});

  final String title;
  final int initialValue;

  @override
  State<_ReviewLimitDialog> createState() => _ReviewLimitDialogState();
}

class _ReviewLimitDialogState extends State<_ReviewLimitDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.initialValue}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value < 0 || value > 9999) {
      setState(() => _errorText = '请输入 0 到 9999 之间的整数');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: false,
        signed: false,
      ),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: '卡片数量',
        helperText: '可填写 0 - 9999',
        errorText: _errorText,
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('保存')),
    ],
  );
}
