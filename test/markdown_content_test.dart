import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kncard_app/core/utils/rich_text.dart';
import 'package:kncard_app/core/widgets/markdown_content.dart';

void main() {
  test('converts Electron html, latex attributes, images, and entities', () {
    final markdown = htmlToMarkdown(
      '\uFEFF<div><h2>第一篇</h2>'
      r'<p><span data-latex-source="\frac{a}{b}" data-latex-display="true"></span></p>'
      '<p><img src=https://example.com/diagram.png alt="图示"></p>'
      '<p>&amp; &lt;保留标签&gt;</p></div>',
    );

    expect(markdown, contains('## 第一篇'));
    expect(markdown, contains(r'\frac{a}{b}'));
    expect(markdown, contains('\n\n'));
    expect(markdown, contains('![图示](https://example.com/diagram.png)'));
    expect(markdown, contains('& <保留标签>'));
  });

  test('does not replace a valid document with empty html paragraphs', () {
    expect(htmlToMarkdown('<p>正文</p><p></p>'), '正文');
  });

  testWidgets('renders markdown, latex, and image fallback content', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownContent(
            data: r'''# 公式

行内公式 $E=mc^2$，块公式：

$$
\\frac{a}{b}
$$

![示例](https://invalid.example/image.png)
''',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('公式'), findsOneWidget);
    expect(find.byType(MarkdownContent), findsOneWidget);
  });

  testWidgets('renders custom note entries and bare image urls', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownContent(
            noteEntries: true,
            data: '''专题 改革创新
真题：25副省级
例句 **推陈出新**
https://invalid.example/image.png''',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('专题'), findsOneWidget);
    expect(find.text('真题'), findsOneWidget);
    expect(find.text('例句'), findsOneWidget);
  });
}
