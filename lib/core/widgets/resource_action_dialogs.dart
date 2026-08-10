import 'package:flutter/material.dart';

Future<String?> showRenameResourceDialog(
  BuildContext context, {
  required String title,
  required String initialValue,
  required String hintText,
}) async {
  final controller = TextEditingController(text: initialValue);
  final formKey = GlobalKey<FormState>();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(hintText: hintText),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return '名称不能为空';
            }
            return null;
          },
          onFieldSubmitted: (_) {
            if (formKey.currentState?.validate() == true) {
              Navigator.of(dialogContext).pop(controller.text.trim());
            }
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() == true) {
              Navigator.of(dialogContext).pop(controller.text.trim());
            }
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
  // Navigator.pop completes the dialog future before the reverse transition
  // has necessarily finished. Let the route leave the overlay before the
  // caller invalidates the list provider.
  await Future<void>.delayed(const Duration(milliseconds: 240));
  controller.dispose();
  return result;
}

Future<bool> showDeleteResourceDialog(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final result =
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('删除'),
            ),
          ],
        ),
      ) ??
      false;
  await Future<void>.delayed(const Duration(milliseconds: 240));
  return result;
}
