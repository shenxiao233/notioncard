import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

import '../../app/app_providers.dart';
import '../../core/models/account_model.dart';
import '../../core/network/api_config.dart';
import '../../core/sync/sync_controller.dart';
import '../review/review_settings.dart';

abstract final class _ProfileColors {
  static const background = Color(0xfffcfdfb);
  static const ink = Color(0xff101311);
  static const muted = Color(0xff68746f);
  static const green = Color(0xff159515);
  static const darkGreen = Color(0xff087408);
  static const softGreen = Color(0xffeef8ec);
  static const paleGreen = Color(0xfff7fbf5);
  static const line = Color(0xffdfe4df);
  static const amber = Color(0xffe8a21a);
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(currentAccountProvider);
    final cards = ref.watch(cardsProvider).valueOrNull?.length ?? 0;
    final documents = ref.watch(documentsProvider).valueOrNull?.length ?? 0;
    final sync = ref.watch(syncControllerProvider);
    final reviewSettings = ref.watch(reviewSettingsProvider);

    return Scaffold(
      backgroundColor: _ProfileColors.background,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 380;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                compact ? 8 : 12,
                16,
                compact ? 24 : 30,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ProfileTitle(account: account, compact: compact),
                      SizedBox(height: compact ? 12 : 16),
                      _AccountHeader(account: account),
                      SizedBox(height: compact ? 10 : 12),
                      _ProfileStats(
                        documents: documents,
                        cards: cards,
                        pending: sync.pending,
                        compact: compact,
                      ),
                      SizedBox(height: compact ? 22 : 26),
                      const _ProfileSectionHeader(title: '复习设置'),
                      const SizedBox(height: 9),
                      _SettingsGroup(
                        children: [
                          _SettingsRow(
                            icon: Icons.school_outlined,
                            title: '每日新卡上限',
                            subtitle:
                                '每天最多加入 ${reviewSettings.newCardsPerDay} 张未学习卡片',
                            trailing: const Icon(Icons.chevron_right_rounded),
                            enabled: account != null,
                            onTap: account == null
                                ? null
                                : () =>
                                      _editLimit(context, ref, newCards: true),
                          ),
                          _SettingsRow(
                            icon: Icons.replay_outlined,
                            title: '每日复习上限',
                            subtitle:
                                '每天最多加入 ${reviewSettings.reviewsPerDay} 张到期卡片',
                            trailing: const Icon(Icons.chevron_right_rounded),
                            enabled: account != null,
                            onTap: account == null
                                ? null
                                : () =>
                                      _editLimit(context, ref, newCards: false),
                          ),
                        ],
                      ),
                      SizedBox(height: compact ? 22 : 26),
                      const _ProfileSectionHeader(title: '同步'),
                      const SizedBox(height: 9),
                      _SyncGroup(
                        sync: sync,
                        accountExists: account != null,
                        ref: ref,
                      ),
                      SizedBox(height: compact ? 22 : 26),
                      const _ProfileSectionHeader(title: '账户'),
                      const SizedBox(height: 9),
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
            );
          },
        ),
      ),
    );
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存设置失败，请稍后重试')));
      }
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

class _ProfileTitle extends StatelessWidget {
  const _ProfileTitle({required this.account, required this.compact});

  final AccountModel? account;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '我的',
        style: TextStyle(
          color: _ProfileColors.ink,
          fontSize: compact ? 27 : 30,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        account == null ? '登录后同步你的学习内容' : '管理你的学习数据和复习计划',
        style: TextStyle(
          color: _ProfileColors.muted,
          fontSize: compact ? 13 : 14,
          height: 1.3,
        ),
      ),
    ],
  );
}

class _ProfileSectionHeader extends StatelessWidget {
  const _ProfileSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: const TextStyle(
      color: _ProfileColors.ink,
      fontSize: 18,
      fontWeight: FontWeight.w700,
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
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _ProfileStat(
          icon: Icons.menu_book_rounded,
          value: documents,
          label: '知识库文档',
          color: _ProfileColors.green,
          compact: compact,
        ),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: _ProfileStat(
          icon: Icons.style_rounded,
          value: cards,
          label: '复习卡片',
          color: _ProfileColors.darkGreen,
          compact: compact,
        ),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: _ProfileStat(
          icon: Icons.cloud_upload_rounded,
          value: pending,
          label: '待同步项目',
          color: pending > 0 ? _ProfileColors.amber : _ProfileColors.green,
          compact: compact,
        ),
      ),
    ],
  );
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.compact,
  });

  final IconData icon;
  final int value;
  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    height: compact ? 82 : 90,
    padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 10, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(
          color: Color(0x10000000),
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: compact ? 18 : 20),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                '$value',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _ProfileColors.darkGreen,
                  fontSize: compact ? 20 : 23,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: _ProfileColors.muted,
            fontSize: compact ? 11 : 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
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

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.account});

  final AccountModel? account;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _ProfileColors.paleGreen,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xffedf4eb)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x140d3d0c),
          blurRadius: 20,
          offset: Offset(0, 9),
        ),
      ],
    ),
    child: Row(
      children: [
        _AccountAvatar(account: account),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                account?.nickname ?? '欢迎使用 KNcard',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ProfileColors.ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                account == null ? '登录后同步你的学习内容' : account?.username ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ProfileColors.muted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _ProfileBadge(
          label: account == null ? '未登录' : '已登录',
          icon: account == null
              ? Icons.person_off_outlined
              : Icons.verified_rounded,
          warning: account == null,
        ),
      ],
    ),
  );
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.account});

  final AccountModel? account;

  @override
  Widget build(BuildContext context) {
    final source = account?.avatar?.trim();
    final image = _avatarImage(source);
    return CircleAvatar(
      radius: 28,
      backgroundColor: _ProfileColors.green,
      child: image != null
          ? ClipOval(
              child: SizedBox.square(
                dimension: 56,
                child: Image(
                  image: image,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => _fallback(),
                ),
              ),
            )
          : _fallback(),
    );
  }

  Widget _fallback() => Text(
    account == null ? '?' : _initial(account!),
    style: const TextStyle(
      color: Colors.white,
      fontSize: 21,
      fontWeight: FontWeight.w700,
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

class _ProfileBadge extends StatelessWidget {
  const _ProfileBadge({
    required this.label,
    required this.icon,
    this.warning = false,
  });

  final String label;
  final IconData icon;
  final bool warning;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: warning ? const Color(0xfffff3df) : Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: warning ? const Color(0xffb77812) : _ProfileColors.green,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: warning ? const Color(0xff9d6810) : _ProfileColors.darkGreen,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
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
        ? const Color(0xffb77812)
        : _ProfileColors.green;
    return _SettingsGroup(
      children: [
        _SettingsRow(
          icon: offline
              ? Icons.cloud_off_outlined
              : sync.isBusy
              ? Icons.sync_rounded
              : Icons.cloud_done_outlined,
          title: offline
              ? '当前离线'
              : sync.isBusy
              ? '正在同步'
              : failure
              ? '同步失败'
              : '连接正常',
          subtitle: _syncDescription(sync),
          trailing: _ProfileBadge(
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
            warning: offline || failure,
          ),
          iconColor: statusColor,
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
            icon: Icons.info_outline_rounded,
            title: '最近失败原因',
            subtitle: sync.message!,
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
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    clipBehavior: Clip.antiAlias,
    child: Container(
      decoration: BoxDecoration(
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
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              const Divider(
                height: 1,
                indent: 60,
                endIndent: 16,
                color: _ProfileColors.line,
              ),
          ],
        ],
      ),
    ),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.enabled = true,
    this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool enabled;
  final VoidCallback? onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? _ProfileColors.ink
        : _ProfileColors.muted.withValues(alpha: 0.5);
    final accent = enabled
        ? iconColor ?? _ProfileColors.green
        : _ProfileColors.muted.withValues(alpha: 0.45);
    return ListTile(
      enabled: enabled,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      leading: Container(
        width: 38,
        height: 38,
        decoration: const BoxDecoration(
          color: _ProfileColors.softGreen,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: accent, size: 19),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: color,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: enabled
              ? _ProfileColors.muted
              : _ProfileColors.muted.withValues(alpha: 0.5),
          fontSize: 12,
          height: 1.35,
        ),
      ),
      trailing: trailing,
      minVerticalPadding: 8,
    );
  }
}
