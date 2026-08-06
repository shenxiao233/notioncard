import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_providers.dart';
import 'auth_widgets.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _invitationCode = TextEditingController();
  final _passwordFocusNode = FocusNode();
  final _invitationFocusNode = FocusNode();
  String? _error;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _invitationCode.dispose();
    _passwordFocusNode.dispose();
    _invitationFocusNode.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _error = null);
    final username = _username.text;
    final password = _password.text;
    final invitationCode = _invitationCode.text;
    final result = await ref
        .read(authControllerProvider.notifier)
        .register(username, password, invitationCode);
    if (!result.isSuccess && mounted) {
      setState(() => _error = result.failure?.userMessage ?? '??????????');
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(authControllerProvider).isLoading;
    final compact = MediaQuery.sizeOf(context).height < 700;
    final fieldHeight = compact ? 50.0 : 56.0;
    final buttonHeight = compact ? 50.0 : 54.0;

    return AuthPageFrame(
      compact: compact,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthBrand(markSize: compact ? 72 : 84, compact: compact),
          SizedBox(height: compact ? 16 : 20),
          AuthField(
            height: fieldHeight,
            controller: _username,
            hintText: '用户名',
            icon: Icons.person_outline_rounded,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _passwordFocusNode.requestFocus(),
          ),
          const SizedBox(height: 12),
          AuthField(
            height: fieldHeight,
            controller: _password,
            focusNode: _passwordFocusNode,
            hintText: '密码',
            icon: Icons.lock_outline_rounded,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _invitationFocusNode.requestFocus(),
            suffix: IconButton(
              tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: compact ? 21 : 23,
              ),
            ),
          ),
          const SizedBox(height: 12),
          AuthField(
            height: fieldHeight,
            controller: _invitationCode,
            focusNode: _invitationFocusNode,
            hintText: '邀请码',
            icon: Icons.confirmation_number_outlined,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _register(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xffb3261e), fontSize: 13),
              ),
            ),
          ],
          SizedBox(height: compact ? 14 : 16),
          AuthSubmitButton(
            height: buttonHeight,
            busy: busy,
            label: '注册',
            onPressed: busy ? null : _register,
          ),
          SizedBox(height: compact ? 8 : 10),
          AuthRegisterPrompt(
            fontSize: compact ? 15 : 16,
            label: '返回登录',
            onTap: () => context.go('/login'),
          ),
        ],
      ),
    );
  }
}
