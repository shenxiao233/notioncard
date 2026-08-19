import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/app_providers.dart';
import '../../core/models/account_model.dart';
import '../../core/update/app_update_controller.dart';
import '../../core/widgets/app_visuals.dart';
import 'account_avatar.dart';

abstract final class _PreferencesColors {
  static const background = AppVisualColors.background;
  static const surface = Color(0xffffffff);
  static const ink = Color(0xff1c211e);
  static const muted = Color(0xff7a837d);
  static const line = Color(0xffe8ebe6);
  static const green = Color(0xff2d8b43);
  static const red = Color(0xffc44545);
  static const softRed = Color(0xfffff1f0);
}

class SettingsPreferencesPage extends ConsumerWidget {
  const SettingsPreferencesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(currentAccountProvider);
    final update = ref.watch(appUpdateControllerProvider);

    return Scaffold(
      backgroundColor: _PreferencesColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < 420 ? 18.0 : 24.0;
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                8,
                horizontalPadding,
                32,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SettingsHeader(title: '设置'),
                      const SizedBox(height: 22),
                      _AccountEntry(
                        account: account,
                        onTap: account == null
                            ? null
                            : () => context.push('/settings/account'),
                      ),
                      const SizedBox(height: 28),
                      const _SectionLabel(label: '偏好设置'),
                      const SizedBox(height: 10),
                      const _SettingsCard(
                        children: [
                          _PreferenceRow(
                            icon: Icons.dark_mode_outlined,
                            title: '外观',
                            value: '浅色',
                          ),
                          _PreferenceRow(
                            icon: Icons.language_outlined,
                            title: '语言',
                            value: '简体中文',
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      const _SectionLabel(label: '关于应用'),
                      const SizedBox(height: 10),
                      _VersionCard(update: update, ref: ref),
                      const SizedBox(height: 28),
                      _SignOutCard(
                        enabled: account != null,
                        onTap: account == null
                            ? null
                            : () => _confirmLogout(context, ref),
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

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: _RoundIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: '返回',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        Text(
          title,
          style: const TextStyle(
            color: _PreferencesColors.ink,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
      ],
    ),
  );
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: _PreferencesColors.surface,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: _PreferencesColors.ink),
        ),
      ),
    ),
  );
}

class _AccountEntry extends StatelessWidget {
  const _AccountEntry({required this.account, required this.onTap});

  final AccountModel? account;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = account != null;
    final nickname = account?.nickname.trim();
    final username = account?.username.trim();
    return Material(
      color: _PreferencesColors.surface,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
          child: Row(
            children: [
              AccountAvatar(account: account, size: 62),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      enabled && nickname?.isNotEmpty == true
                          ? nickname!
                          : enabled
                          ? '未设置昵称'
                          : '未登录',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _PreferencesColors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      enabled && username?.isNotEmpty == true
                          ? '自托管版 · $username'
                          : '登录后管理账户资料',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _PreferencesColors.muted,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.chevron_right_rounded,
                color: _PreferencesColors.muted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(
      label,
      style: const TextStyle(
        color: _PreferencesColors.muted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
    ),
  );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: _PreferencesColors.surface,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index != children.length - 1)
            const Divider(
              height: 1,
              indent: 58,
              endIndent: 18,
              color: _PreferencesColors.line,
            ),
        ],
      ],
    ),
  );
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 64,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Icon(icon, color: _PreferencesColors.muted, size: 21),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _PreferencesColors.ink,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: _PreferencesColors.muted,
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ],
      ),
    ),
  );
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({required this.update, required this.ref});

  final AppUpdateState update;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) => Material(
    color: _PreferencesColors.surface,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        _VersionRow(
          title: '当前版本',
          trailing: FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) => Text(
              snapshot.data == null ? 'KNcard' : 'v${snapshot.data!.version}',
              style: const TextStyle(
                color: _PreferencesColors.muted,
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ),
        ),
        const Divider(
          height: 1,
          indent: 18,
          endIndent: 18,
          color: _PreferencesColors.line,
        ),
        _VersionRow(
          title: '检查更新',
          trailing: _UpdateAction(update: update, ref: ref),
        ),
      ],
    ),
  );
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.title, required this.trailing});

  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 64,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _PreferencesColors.ink,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
          trailing,
        ],
      ),
    ),
  );
}

class _UpdateAction extends StatelessWidget {
  const _UpdateAction({required this.update, required this.ref});

  final AppUpdateState update;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final label = switch (update.status) {
      AppUpdateStatus.checking => '检查中',
      AppUpdateStatus.upToDate => '已是最新',
      AppUpdateStatus.available => '有新版本',
      AppUpdateStatus.error => '重试',
      _ => '检查',
    };
    final busy = update.isBusy;
    return TextButton(
      onPressed: busy
          ? null
          : () => ref.read(appUpdateControllerProvider.notifier).check(),
      style: TextButton.styleFrom(
        foregroundColor: _PreferencesColors.green,
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}

class _SignOutCard extends StatelessWidget {
  const _SignOutCard({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: enabled ? _PreferencesColors.softRed : _PreferencesColors.surface,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 58,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.logout_rounded,
              size: 19,
              color: enabled
                  ? _PreferencesColors.red
                  : _PreferencesColors.muted,
            ),
            const SizedBox(width: 8),
            Text(
              '退出登录',
              style: TextStyle(
                color: enabled
                    ? _PreferencesColors.red
                    : _PreferencesColors.muted,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
