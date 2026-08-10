import 'package:flutter/material.dart';

import 'app_visuals.dart';

class SwipeActionTile extends StatefulWidget {
  const SwipeActionTile({
    required this.child,
    required this.onRename,
    required this.onDelete,
    this.onTap,
    this.margin = EdgeInsets.zero,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.backgroundColor = Colors.white,
    this.boxShadow = appCardShadow,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final EdgeInsetsGeometry margin;
  final BorderRadius borderRadius;
  final Color backgroundColor;
  final List<BoxShadow> boxShadow;

  @override
  State<SwipeActionTile> createState() => _SwipeActionTileState();
}

class _SwipeActionTileState extends State<SwipeActionTile> {
  static const _actionWidth = 152.0;

  double _offset = 0;
  bool _dragging = false;

  void _handleDragStart(DragStartDetails details) {
    setState(() => _dragging = true);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      _offset = (_offset + details.delta.dx).clamp(-_actionWidth, 0.0);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    setState(() {
      _dragging = false;
      _offset = _offset < -_actionWidth * 0.45 ? -_actionWidth : 0;
    });
  }

  void _handleTap() {
    if (_offset != 0) {
      setState(() => _offset = 0);
      return;
    }
    widget.onTap?.call();
  }

  void _closeAnd(VoidCallback action) {
    if (_offset == 0) {
      action();
      return;
    }
    setState(() => _offset = 0);
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (mounted) action();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: widget.borderRadius,
        boxShadow: widget.boxShadow,
      ),
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: Stack(
          children: [
            Positioned.fill(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _SwipeActionButton(
                    width: _actionWidth / 2,
                    color: AppVisualColors.green,
                    icon: Icons.edit_rounded,
                    label: '重命名',
                    onPressed: () => _closeAnd(widget.onRename),
                  ),
                  _SwipeActionButton(
                    width: _actionWidth / 2,
                    color: const Color(0xffd94a45),
                    icon: Icons.delete_outline_rounded,
                    label: '删除',
                    onPressed: () => _closeAnd(widget.onDelete),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: _dragging
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(_offset, 0, 0),
              color: widget.backgroundColor,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _handleTap,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: _handleDragStart,
                    onHorizontalDragUpdate: _handleDragUpdate,
                    onHorizontalDragEnd: _handleDragEnd,
                    child: SizedBox(
                      width: double.infinity,
                      child: widget.child,
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
}

class _SwipeActionButton extends StatelessWidget {
  const _SwipeActionButton({
    required this.width,
    required this.color,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final double width;
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: double.infinity,
    child: Material(
      color: color,
      child: InkWell(
        onTap: onPressed,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
