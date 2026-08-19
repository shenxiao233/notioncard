import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_providers.dart';
import '../../core/models/account_model.dart';
import '../../core/repositories/auth_repository.dart';
import '../../core/widgets/app_visuals.dart';
import 'account_avatar.dart';

abstract final class _AccountColors {
  static const background = AppVisualColors.background;
  static const surface = Color(0xffffffff);
  static const ink = Color(0xff1c211e);
  static const muted = Color(0xff7a837d);
  static const line = Color(0xffe8ebe6);
  static const green = Color(0xff2d8b43);
  static const red = Color(0xffc44545);
}

abstract final class _AccountTypography {
  static const family = 'NotoSerifSC';

  static const pageTitle = TextStyle(
    fontFamily: family,
    color: _AccountColors.ink,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );

  static const rowLabel = TextStyle(
    fontFamily: family,
    color: _AccountColors.muted,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  static const rowValue = TextStyle(
    fontFamily: family,
    color: _AccountColors.ink,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  static const rowValueAccent = TextStyle(
    fontFamily: family,
    color: _AccountColors.green,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );
}

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  final _picker = ImagePicker();
  late final TextEditingController _nicknameController;
  String? _avatar;
  String? _savedAvatar;
  String _savedNickname = '';
  bool _avatarChanged = false;
  bool _saving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final account = ref.read(currentAccountProvider);
    _nicknameController = TextEditingController(text: account?.nickname ?? '');
    _avatar = account?.avatar;
    _savedAvatar = _avatar;
    _savedNickname = account?.nickname ?? '';
    _nicknameController.addListener(_clearErrorOnInput);
  }

  @override
  void dispose() {
    _nicknameController
      ..removeListener(_clearErrorOnInput)
      ..dispose();
    super.dispose();
  }

  AccountModel? get _account => ref.read(currentAccountProvider);

  bool get _hasChanges =>
      _nicknameController.text.trim() != _savedNickname.trim() ||
      _avatarChanged ||
      _avatar != _savedAvatar;

  void _clearErrorOnInput() {
    if (_errorText != null && mounted) setState(() => _errorText = null);
  }

  Future<void> _pickAvatar() async {
    if (_saving) return;
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 82,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        setState(() => _errorText = '无法读取这张图片');
        return;
      }
      final mime = file.mimeType ?? _mimeType(file.path);
      setState(() {
        _avatar = 'data:$mime;base64,${base64Encode(bytes)}';
        _avatarChanged = true;
        _errorText = null;
      });
    } catch (_) {
      if (mounted) setState(() => _errorText = '选择头像失败，请稍后重试');
    }
  }

  Future<void> _save() async {
    final account = _account;
    if (account == null) {
      setState(() => _errorText = '当前没有可编辑的账户');
      return;
    }
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      setState(() => _errorText = '昵称不能为空');
      return;
    }
    if (nickname.length > 32) {
      setState(() => _errorText = '昵称不能超过 32 个字符');
      return;
    }
    if (!_hasChanges) {
      _showMessage('没有需要保存的修改');
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });
    final result = await ref
        .read(authControllerProvider.notifier)
        .updateProfile(
          nickname: nickname,
          avatar: _avatar,
          updateAvatar: _avatarChanged || _avatar != _savedAvatar,
        );
    if (!mounted) return;

    if (result.isSuccess) {
      final updated = result.account ?? ref.read(currentAccountProvider);
      final updatedNickname = updated?.nickname ?? nickname;
      final updatedAvatar = updated?.avatar ?? _avatar;
      setState(() {
        _saving = false;
        _savedNickname = updatedNickname;
        _savedAvatar = updatedAvatar;
        _avatar = updatedAvatar;
        _avatarChanged = false;
        _nicknameController.value = _nicknameController.value.copyWith(
          text: updatedNickname,
          selection: TextSelection.collapsed(offset: updatedNickname.length),
          composing: TextRange.empty,
        );
      });
      _showMessage('个人信息已保存');
      return;
    }

    setState(() {
      _saving = false;
      _errorText = _failureMessage(result.failure);
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _mimeType(String path) {
    final extension = path.split('.').last.toLowerCase();
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/png',
    };
  }

  String _failureMessage(AuthFailure? failure) {
    return switch (failure?.type) {
      AuthFailureType.network => '网络不可用，请稍后重试',
      AuthFailureType.timeout => '请求超时，请稍后重试',
      AuthFailureType.invalidResponse => '服务器返回的数据无效',
      AuthFailureType.server => '资料保存失败，请稍后重试',
      _ => '资料保存失败，请稍后重试',
    };
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(currentAccountProvider);
    final previewAccount = account?.copyWith(avatar: _avatar);

    return Scaffold(
      backgroundColor: _AccountColors.background,
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
                    children: [
                      const _AccountHeader(),
                      const SizedBox(height: 30),
                      _AvatarPicker(
                        account: previewAccount,
                        enabled: !_saving && account != null,
                        onPick: _pickAvatar,
                      ),
                      const SizedBox(height: 28),
                      _ProfileCard(
                        account: account,
                        controller: _nicknameController,
                        enabled: !_saving && account != null,
                        errorText: _errorText,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _saving || account == null ? null : _save,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            backgroundColor: _AccountColors.green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('保存修改'),
                        ),
                      ),
                      if (account == null) ...[
                        const SizedBox(height: 16),
                        const Text(
                          '登录后可以修改个人信息',
                          style: TextStyle(
                            color: _AccountColors.muted,
                            fontSize: 13,
                          ),
                        ),
                      ],
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
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: '返回',
            child: Material(
              color: _AccountColors.surface,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                customBorder: const CircleBorder(),
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.arrow_back_rounded,
                    size: 20,
                    color: _AccountColors.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
        const Text('账号', style: _AccountTypography.pageTitle),
      ],
    ),
  );
}

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({
    required this.account,
    required this.enabled,
    required this.onPick,
  });

  final AccountModel? account;
  final bool enabled;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => Semantics(
    button: enabled,
    label: '上传头像',
    child: GestureDetector(
      onTap: enabled ? onPick : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AccountAvatar(account: account, size: 116, borderWidth: 3),
          if (enabled)
            Positioned(
              right: -4,
              bottom: 0,
              child: Semantics(
                button: true,
                label: '更换头像',
                child: Material(
                  color: _AccountColors.green,
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: onPick,
                    customBorder: const CircleBorder(),
                    child: const SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(
                        Icons.camera_alt_outlined,
                        size: 19,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.account,
    required this.controller,
    required this.enabled,
    required this.errorText,
  });

  final AccountModel? account;
  final TextEditingController controller;
  final bool enabled;
  final String? errorText;

  @override
  Widget build(BuildContext context) => Material(
    color: _AccountColors.surface,
    borderRadius: BorderRadius.circular(20),
    elevation: 2,
    shadowColor: const Color(0x263d8650),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
      child: Column(
        children: [
          _InfoRow(
            label: '账号 ID',
            value: account?.id.isNotEmpty == true ? account!.id : '未登录',
          ),
          const Divider(height: 1, color: _AccountColors.line),
          _EditableInfoRow(
            label: '昵称',
            controller: controller,
            enabled: enabled,
          ),
          const Divider(height: 1, color: _AccountColors.line),
          _InfoRow(
            label: '账户类型',
            value: _accountTypeLabel(account),
            valueColor: _AccountColors.green,
          ),
          if (errorText != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Text(
                  errorText!,
                  style: const TextStyle(
                    color: _AccountColors.red,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 72,
    child: Row(
      children: [
        Text(label, style: _AccountTypography.rowLabel),
        const SizedBox(width: 12),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: valueColor == null
                  ? _AccountTypography.rowValue
                  : _AccountTypography.rowValueAccent,
            ),
          ),
        ),
      ],
    ),
  );
}

String _accountTypeLabel(AccountModel? account) =>
    account?.role.trim().toLowerCase() == 'admin' ? '管理用户' : '许可用户';

class _EditableInfoRow extends StatelessWidget {
  const _EditableInfoRow({
    required this.label,
    required this.controller,
    required this.enabled,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 72,
    child: Row(
      children: [
        Text(label, style: _AccountTypography.rowLabel),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled,
            maxLength: 32,
            textAlign: TextAlign.end,
            textInputAction: TextInputAction.done,
            style: _AccountTypography.rowValue,
            decoration: const InputDecoration(
              hintText: '输入昵称',
              counterText: '',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    ),
  );
}
