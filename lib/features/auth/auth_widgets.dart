import 'package:flutter/material.dart';

class AuthPageFrame extends StatefulWidget {
  const AuthPageFrame({
    required this.child,
    this.compact = false,
    this.showDecoration = false,
    super.key,
  });

  final Widget child;
  final bool compact;
  final bool showDecoration;

  @override
  State<AuthPageFrame> createState() => _AuthPageFrameState();
}

class _AuthPageFrameState extends State<AuthPageFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xfff6f6f4),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < 380 ? 20.0 : 24.0;
            final contentWidth = (constraints.maxWidth - horizontalPadding * 2)
                .clamp(0.0, 420.0)
                .toDouble();
            final topPadding = widget.compact ? 24.0 : 36.0;

            return Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  topPadding,
                  horizontalPadding,
                  12,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SlideTransition(
                        position: _slide,
                        child: FadeTransition(
                          opacity: _fade,
                          child: widget.child,
                        ),
                      ),
                      if (widget.showDecoration) ...[
                        const SizedBox(height: 8),
                        FadeTransition(
                          opacity: _fade,
                          child: const SizedBox(
                            width: double.infinity,
                            height: 70,
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: SizedBox(
                                width: 360,
                                height: 112,
                                child: AuthCardDecoration(),
                              ),
                            ),
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

class AuthBrand extends StatelessWidget {
  const AuthBrand({required this.markSize, this.compact = false, super.key});

  final double markSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AuthLayeredCardMark(size: markSize),
        SizedBox(height: compact ? 8 : 12),
        Text(
          'Notion Card',
          style: TextStyle(
            color: const Color(0xff171717),
            fontSize: compact ? 27 : 32,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

class AuthLayeredCardMark extends StatelessWidget {
  const AuthLayeredCardMark({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 0.95,
      height: size * 1.05,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.translate(
            offset: Offset(size * 0.17, -size * 0.08),
            child: Transform.rotate(
              angle: 0.09,
              child: AuthMarkCard(
                width: size * 0.64,
                height: size * 0.75,
                color: const Color(0xff688b80),
                shadowColor: const Color(0x22688b80),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(size * 0.08, -size * 0.02),
            child: Transform.rotate(
              angle: 0.05,
              child: AuthMarkCard(
                width: size * 0.64,
                height: size * 0.75,
                color: const Color(0xffa7bcb4),
                shadowColor: const Color(0x22a7bcb4),
              ),
            ),
          ),
          Positioned(
            left: size * 0.07,
            bottom: 0,
            child: AuthMarkCard(
              width: size * 0.64,
              height: size * 0.75,
              color: Colors.white,
              shadowColor: const Color(0x16000000),
              child: Text(
                'N',
                style: TextStyle(
                  color: const Color(0xff171717),
                  fontSize: size * 0.38,
                  fontWeight: FontWeight.w500,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AuthMarkCard extends StatelessWidget {
  const AuthMarkCard({
    required this.width,
    required this.height,
    required this.color,
    required this.shadowColor,
    this.child,
    super.key,
  });

  final double width;
  final double height;
  final Color color;
  final Color shadowColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 12,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }
}

class AuthField extends StatelessWidget {
  const AuthField({
    required this.height,
    required this.controller,
    required this.hintText,
    required this.icon,
    this.focusNode,
    this.obscureText = false,
    this.suffix,
    this.textInputAction,
    this.onSubmitted,
    super.key,
  });

  final double height;
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final FocusNode? focusNode;
  final bool obscureText;
  final Widget? suffix;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final small = height <= 50;
    return SizedBox(
      height: height,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscureText,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        style: TextStyle(
          color: const Color(0xff202020),
          fontSize: small ? 16 : 17,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: Colors.black.withValues(alpha: 0.42),
            fontSize: small ? 16 : 17,
          ),
          prefixIcon: Icon(
            icon,
            size: small ? 24 : 26,
            color: const Color(0xff202020),
          ),
          suffixIcon: suffix,
          prefixIconConstraints: BoxConstraints(
            minWidth: small ? 54 : 58,
            minHeight: height,
          ),
          suffixIconConstraints: BoxConstraints(
            minWidth: small ? 50 : 54,
            minHeight: height,
          ),
          filled: true,
          fillColor: const Color(0xfffbfaf8),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xffe3e1df)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xffe3e1df)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xff688b80), width: 1.5),
          ),
        ),
      ),
    );
  }
}

class AuthSubmitButton extends StatelessWidget {
  const AuthSubmitButton({
    required this.height,
    required this.busy,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final double height;
  final bool busy;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xff171717),
          disabledBackgroundColor: const Color(0xff8c8c8c),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          ),
          child: busy
              ? const SizedBox.square(
                  key: ValueKey('busy'),
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label,
                  key: const ValueKey('label'),
                  style: TextStyle(
                    fontSize: height <= 50 ? 17 : 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}

class AuthRegisterPrompt extends StatelessWidget {
  const AuthRegisterPrompt({
    required this.fontSize,
    required this.label,
    required this.onTap,
    super.key,
  });

  final double fontSize;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          label == '立即注册' ? '还没有账号？' : '已有账号？',
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.42),
            fontSize: fontSize,
          ),
        ),
        const SizedBox(width: 14),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xff3b665a),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 5),
              const Icon(Icons.chevron_right_rounded, size: 21),
            ],
          ),
        ),
      ],
    );
  }
}

class AuthCardDecoration extends StatelessWidget {
  const AuthCardDecoration({super.key});

  @override
  Widget build(BuildContext context) {
    final lineColor = const Color(0xffc8d5d0).withValues(alpha: 0.24);
    return SizedBox(
      height: 112,
      child: Opacity(
        opacity: 0.78,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              left: 8,
              top: 34,
              child: Transform.rotate(
                angle: -0.82,
                child: AuthOutlineCard(color: lineColor, width: 58, height: 75),
              ),
            ),
            Positioned(
              left: 105,
              top: 4,
              child: Transform.rotate(
                angle: 0.19,
                child: AuthOutlineCard(
                  color: lineColor,
                  width: 72,
                  height: 96,
                  child: const Text(
                    'A',
                    style: TextStyle(
                      color: Color(0xff8fa89e),
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 115,
              top: 20,
              child: Transform.rotate(
                angle: -0.24,
                child: AuthOutlineCard(
                  color: lineColor,
                  width: 76,
                  height: 88,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(width: 38, height: 2, color: lineColor),
                      const SizedBox(height: 8),
                      Container(width: 30, height: 2, color: lineColor),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 5,
              top: 18,
              child: Transform.rotate(
                angle: -0.52,
                child: AuthOutlineCard(color: lineColor, width: 58, height: 78),
              ),
            ),
            const Positioned(
              left: 72,
              top: 45,
              child: Icon(
                Icons.auto_awesome,
                size: 23,
                color: Color(0x2690a89e),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthOutlineCard extends StatelessWidget {
  const AuthOutlineCard({
    required this.color,
    required this.width,
    required this.height,
    this.child,
    super.key,
  });

  final Color color;
  final double width;
  final double height;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: 2),
      ),
      child: child,
    );
  }
}
