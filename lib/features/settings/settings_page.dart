import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_providers.dart';
import '../../core/models/account_model.dart';
import '../../core/sound/app_sound_settings.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/sync/sync_controller.dart';
import '../review/review_settings.dart';
import 'account_avatar.dart';

abstract final class _ProfileColors {
  static const background = Color(0xfff5f8f5);
  static const ink = Color(0xff111412);
  static const muted = Color(0xff6f7975);
  static const green = Color(0xff26983b);
  static const darkGreen = Color(0xff187c2d);
  static const softGreen = Color(0xffeff8ef);
  static const line = Color(0xffe3e9e4);
  static const amber = Color(0xffc48418);
}

abstract final class _ProfileTypography {
  static const name = TextStyle(
    color: _ProfileColors.ink,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.15,
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
    color: _ProfileColors.muted,
    fontSize: 14,
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
    final pending = ref.watch(pendingSyncProvider).valueOrNull ?? sync.pending;
    final reviewSettings = ref.watch(reviewSettingsProvider);
    final soundSettings = ref.watch(appSoundSettingsProvider);

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
                  AppLayoutMetrics.bottomNavigationContentPadding + 22,
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
                          pending: pending,
                          compact: compact,
                        ),
                        const SizedBox(height: 16),
                        _ProfileSectionHeader(title: '复习设置'),
                        const SizedBox(height: 8),
                        _SettingsGroup(
                          dividerIndent: 22,
                          children: [
                            _SettingsRow(
                              title: '自主学习',
                              subtitle: '不限制每日新词和复习数量',
                              trailing: Switch(
                                value: reviewSettings.autonomousLearning,
                                activeThumbColor: _ProfileColors.green,
                                onChanged: account == null
                                    ? null
                                    : (enabled) => _setAutonomousLearning(
                                        context,
                                        ref,
                                        enabled,
                                      ),
                              ),
                              enabled: account != null,
                              onTap: account == null
                                  ? null
                                  : () => _setAutonomousLearning(
                                      context,
                                      ref,
                                      !reviewSettings.autonomousLearning,
                                    ),
                            ),
                            _SettingsRow(
                              title: '每日新卡上限',
                              subtitle: reviewSettings.autonomousLearning
                                  ? '自主学习已开启，不限制每日新词数量'
                                  : '每天最多加入 ${reviewSettings.newCardsPerDay} 张未学习卡片',
                              trailing: _ValueTrailing(
                                value: reviewSettings.autonomousLearning
                                    ? '不限制'
                                    : '${reviewSettings.newCardsPerDay} 张',
                              ),
                              enabled: account != null,
                              onTap:
                                  account == null ||
                                      reviewSettings.autonomousLearning
                                  ? null
                                  : () => _editLimit(
                                      context,
                                      ref,
                                      newCards: true,
                                    ),
                            ),
                            _SettingsRow(
                              title: '每日复习上限',
                              subtitle: reviewSettings.autonomousLearning
                                  ? '自主学习已开启，不限制每日复习数量'
                                  : '每天最多加入 ${reviewSettings.reviewsPerDay} 张到期卡片',
                              trailing: _ValueTrailing(
                                value: reviewSettings.autonomousLearning
                                    ? '不限制'
                                    : '${reviewSettings.reviewsPerDay} 张',
                              ),
                              enabled: account != null,
                              onTap:
                                  account == null ||
                                      reviewSettings.autonomousLearning
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
                        _ProfileSectionHeader(title: '同步'),
                        const SizedBox(height: 8),
                        _SyncGroup(
                          sync: sync,
                          pending: pending,
                          accountExists: account != null,
                          ref: ref,
                        ),
                        const SizedBox(height: 16),
                        const _ProfileSectionHeader(title: '声音设置'),
                        const SizedBox(height: 8),
                        _SoundSettingsGroup(settings: soundSettings, ref: ref),
                        const SizedBox(height: 22),
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

  void _showAccountActions(BuildContext context, WidgetRef ref) {
    final account = ref.read(currentAccountProvider);
    if (account == null) {
      _showMessage(context, '登录后可以管理账户');
      return;
    }
    context.push('/settings/preferences');
  }

  void _showNotifications(BuildContext context) {
    _showMessage(context, '暂无新的通知');
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setAutonomousLearning(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    try {
      await ref
          .read(reviewSettingsProvider.notifier)
          .setAutonomousLearning(enabled);
    } catch (_) {
      if (context.mounted) {
        _showMessage(context, '保存设置失败，请稍后重试');
      }
    }
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
            AccountAvatar(account: account),
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
            value: documents,
            label: '知识库文档',
            compact: compact,
          ),
        ),
        const _StatDivider(),
        Expanded(
          child: _ProfileStat(value: cards, label: '复习卡片', compact: compact),
        ),
        const _StatDivider(),
        Expanded(
          child: _ProfileStat(value: pending, label: '待同步项目', compact: compact),
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
    required this.value,
    required this.label,
    required this.compact,
  });

  final int value;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        '$value',
        style: _ProfileTypography.statValue.copyWith(
          fontSize: compact ? 22 : 24,
          color: _ProfileColors.darkGreen,
        ),
      ),
      const SizedBox(height: 7),
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
  const _ProfileSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2),
    child: Text(title, style: _ProfileTypography.sectionTitle),
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
    this.trailing,
    this.enabled = true,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final titleColor = enabled
        ? _ProfileColors.ink
        : _ProfileColors.muted.withValues(alpha: 0.5);
    final subtitleColor = enabled
        ? _ProfileColors.muted
        : _ProfileColors.muted.withValues(alpha: 0.5);
    return ListTile(
      enabled: enabled,
      onTap: onTap,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
    required this.pending,
    required this.accountExists,
    required this.ref,
  });

  final SyncUiState sync;
  final int pending;
  final bool accountExists;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final offline = sync.connection == SyncConnectionState.offline;
    final failure = sync.phase == SyncPhase.failure;
    final statusLabel = offline
        ? '离线'
        : sync.isBusy
        ? '同步中'
        : failure
        ? '需重试'
        : '在线';
    return _SettingsGroup(
      dividerIndent: 16,
      children: [
        _SettingsRow(
          title: '连接状态',
          subtitle: _syncDescription(sync, pending),
          trailing: _StatusBadge(
            label: statusLabel,
            warning: offline || failure,
          ),
        ),
        _SettingsRow(
          title: '待同步项目',
          subtitle: pending == 0 ? '没有等待处理的本地更改' : '$pending 个项目等待处理',
          trailing: pending > 0
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
          title: '最近同步',
          subtitle: sync.lastSyncedAt == null
              ? '尚未完成同步'
              : _relativeTime(sync.lastSyncedAt!),
          trailing: _TextChevron(
            label: '立即同步',
            onTap: !accountExists || sync.isBusy
                ? null
                : () => ref.read(syncControllerProvider.notifier).sync(),
          ),
          onTap: !accountExists || sync.isBusy
              ? null
              : () => ref.read(syncControllerProvider.notifier).sync(),
        ),
      ],
    );
  }

  String _syncDescription(SyncUiState sync, int pending) {
    if (sync.phase == SyncPhase.syncing) {
      return '正在同步本地内容，阅读和复习不会被阻塞';
    }
    if (sync.connection == SyncConnectionState.offline) {
      return '本地缓存可用，网络恢复后会自动同步';
    }
    if (sync.phase == SyncPhase.failure) {
      return '同步没有完成，可以手动重试';
    }
    if (pending > 0) {
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

class _SoundSettingsGroup extends StatelessWidget {
  const _SoundSettingsGroup({required this.settings, required this.ref});

  final AppSoundSettings settings;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) => _SettingsGroup(
    children: [
      _SettingsRow(
        title: '界面音效',
        subtitle: '复习、完成和同步时播放轻提示音',
        trailing: Switch(
          value: settings.enabled,
          activeThumbColor: _ProfileColors.green,
          onChanged: (value) =>
              ref.read(appSoundSettingsProvider.notifier).setEnabled(value),
        ),
        onTap: () => ref
            .read(appSoundSettingsProvider.notifier)
            .setEnabled(!settings.enabled),
      ),
      _SettingsRow(
        title: '复习反馈音',
        subtitle: settings.enabled ? '答题后播放轻柔提示音' : '开启界面音效后可用',
        enabled: settings.enabled,
        trailing: Switch(
          value: settings.reviewFeedbackEnabled,
          activeThumbColor: _ProfileColors.green,
          onChanged: settings.enabled
              ? (value) => ref
                    .read(appSoundSettingsProvider.notifier)
                    .setReviewFeedbackEnabled(value)
              : null,
        ),
        onTap: settings.enabled
            ? () => ref
                  .read(appSoundSettingsProvider.notifier)
                  .setReviewFeedbackEnabled(!settings.reviewFeedbackEnabled)
            : null,
      ),
    ],
  );
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
