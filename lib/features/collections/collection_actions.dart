import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../../core/models/collection_model.dart';
import '../../core/widgets/app_visuals.dart';

class CollectionDraft {
  const CollectionDraft({
    required this.name,
    required this.icon,
    required this.color,
  });

  final String name;
  final String icon;
  final String color;
}

Future<CollectionDraft?> showCreateCollectionSheet(
  BuildContext context, {
  required CollectionType type,
}) async {
  return showModalBottomSheet<CollectionDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _CreateCollectionSheet(type: type),
  );
}

Future<CollectionModel?> createCollectionFromSheet(
  BuildContext context,
  WidgetRef ref, {
  required CollectionType type,
}) async {
  final draft = await showCreateCollectionSheet(context, type: type);
  if (draft == null || !context.mounted) return null;
  final account = ref.read(currentAccountProvider);
  if (account == null) return null;

  try {
    final collection = await ref
        .read(contentRepositoryProvider)
        .createCollection(
          accountId: account.id,
          type: type,
          name: draft.name,
          icon: draft.icon,
          color: draft.color,
        );
    ref.invalidate(collectionsProvider);
    ref.invalidate(cardsProvider);
    ref.invalidate(documentsProvider);
    ref.invalidate(pendingSyncProvider);
    ref
        .read(syncControllerProvider.notifier)
        .scheduleSync(reason: 'collection-create');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(type == CollectionType.deck ? '牌组已创建' : '文档类别已创建'),
        ),
      );
    }
    return collection;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('创建失败：$error')));
    }
    return null;
  }
}

class _CreateCollectionSheet extends StatefulWidget {
  const _CreateCollectionSheet({required this.type});

  final CollectionType type;

  @override
  State<_CreateCollectionSheet> createState() => _CreateCollectionSheetState();
}

class _CreateCollectionSheetState extends State<_CreateCollectionSheet> {
  final _nameController = TextEditingController();
  String _selectedIcon = 'folder';
  String _selectedColor = 'green';
  String? _error;

  static const _colors = <String, Color>{
    'green': AppVisualColors.green,
    'blue': Color(0xff4778e8),
    'orange': Color(0xffe9950b),
    'purple': Color(0xff8d61d8),
  };

  static const _icons = <String, IconData>{
    'folder': Icons.folder_rounded,
    'style': Icons.style_rounded,
    'book': Icons.menu_book_rounded,
    'lightbulb': Icons.lightbulb_rounded,
  };

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDeck = widget.type == CollectionType.deck;
    final title = isDeck ? '新建牌组' : '新建文档类别';
    final hint = isDeck ? '例如：Flutter 基础' : '例如：项目笔记';
    return Material(
      color: AppVisualColors.background,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppVisualColors.ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                isDeck ? '创建后可以直接添加卡片和开始复习。' : '创建后文档会自动归入这个类别。',
                style: const TextStyle(
                  color: AppVisualColors.muted,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 22),
              TextField(
                controller: _nameController,
                autofocus: true,
                maxLength: 80,
                textInputAction: TextInputAction.done,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: isDeck ? '牌组名称' : '文档类别名称',
                  hintText: hint,
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '选择图标',
                style: TextStyle(
                  color: AppVisualColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                children: _icons.entries.map((entry) {
                  final selected = entry.key == _selectedIcon;
                  return _ChoiceIcon(
                    icon: entry.value,
                    color: _colors[_selectedColor]!,
                    selected: selected,
                    onTap: () => setState(() => _selectedIcon = entry.key),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              const Text(
                '选择颜色',
                style: TextStyle(
                  color: AppVisualColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                children: _colors.entries.map((entry) {
                  final selected = entry.key == _selectedColor;
                  return _ChoiceColor(
                    color: entry.value,
                    selected: selected,
                    onTap: () => setState(() => _selectedColor = entry.key),
                  );
                }).toList(),
              ),
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(isDeck ? '创建牌组' : '创建文档类别'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请输入名称');
      return;
    }
    Navigator.of(context).pop(
      CollectionDraft(name: name, icon: _selectedIcon, color: _selectedColor),
    );
  }
}

class _ChoiceIcon extends StatelessWidget {
  const _ChoiceIcon({
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: 0.12) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? color : AppVisualColors.line,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: Icon(icon, color: color, size: 23),
    ),
  );
}

class _ChoiceColor extends StatelessWidget {
  const _ChoiceColor({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 36,
      height: 36,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? color : Colors.transparent,
          width: 2,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: selected
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
            : null,
      ),
    ),
  );
}
