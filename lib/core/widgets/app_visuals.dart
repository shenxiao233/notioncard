import 'package:flutter/material.dart';

abstract final class AppVisualColors {
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

const appCardShadow = <BoxShadow>[
  BoxShadow(color: Color(0x10000000), blurRadius: 18, offset: Offset(0, 7)),
];

class AppVisualTitle extends StatelessWidget {
  const AppVisualTitle({
    required this.title,
    required this.subtitle,
    this.actions = const <Widget>[],
    this.compact = false,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: compact ? 104 : 118,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          right: -20,
          top: -34,
          width: compact ? 146 : 170,
          height: compact ? 154 : 178,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.62,
              child: Image.asset(
                'assets/review_leaves.jpg',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12, right: 58),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppVisualColors.ink,
                        fontSize: compact ? 27 : 30,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppVisualColors.muted,
                        fontSize: compact ? 13 : 14,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: 8),
                Row(mainAxisSize: MainAxisSize.min, children: actions),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class AppVisualSectionTitle extends StatelessWidget {
  const AppVisualSectionTitle({required this.title, this.subtitle, super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: AppVisualColors.ink,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 3),
        Text(
          subtitle!,
          style: const TextStyle(
            color: AppVisualColors.muted,
            fontSize: 12,
            height: 1.3,
          ),
        ),
      ],
    ],
  );
}

class AppVisualIconButton extends StatelessWidget {
  const AppVisualIconButton({
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(15),
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(15),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Icon(
          icon,
          size: 20,
          color: onPressed == null
              ? AppVisualColors.muted.withValues(alpha: 0.45)
              : AppVisualColors.darkGreen,
        ),
      ),
    ),
  );
}
