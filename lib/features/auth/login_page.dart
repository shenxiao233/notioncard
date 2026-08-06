import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_providers.dart';
import 'auth_widgets.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocusNode = FocusNode();
  String? _error;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _error = null);
    final username = _username.text;
    final password = _password.text;
    final result = await ref
        .read(authControllerProvider.notifier)
        .login(username, password);
    if (!result.isSuccess && mounted) {
      setState(() => _error = result.failure?.userMessage ?? '??????????');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final busy = authState.isLoading;
    final compact = MediaQuery.sizeOf(context).height < 700;
    final fieldHeight = compact ? 50.0 : 56.0;
    final buttonHeight = compact ? 50.0 : 54.0;

    return AuthPageFrame(
      compact: compact,
      showDecoration: !compact && _error == null,
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
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _login(),
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
            label: '登录',
            onPressed: busy ? null : _login,
          ),
          SizedBox(height: compact ? 8 : 10),
          AuthRegisterPrompt(
            fontSize: compact ? 15 : 16,
            label: '立即注册',
            onTap: () => context.go('/register'),
          ),
        ],
      ),
    );
  }
}
