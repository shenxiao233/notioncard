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

  test('extracts image links from card-style plain URLs and Markdown', () {
    const plain = 'https://fb.example/api/tarzan/images/card.png?token=123';
    const markdown = '![鍥剧墖](https://example.com/diagram.webp)';

    expect(extractImageLinkUrls(plain), [plain]);
    expect(extractImageLinkUrls(markdown), [
      'https://example.com/diagram.webp',
    ]);
    expect(extractImageLinkUrls('https://example.com/article/123'), isEmpty);
  });

  test('uses the compatible static CDN for exported fenbike image URLs', () {
    const source =
        'https://fb.fenbike.cn/api/tarzan/images/19dd20818593290.png?width=700';

    expect(
      compatibleImageUri(Uri.parse(source)).toString(),
      'https://fb.fbstatic.cn/api/tarzan/images/19dd20818593290.png?width=700',
    );
    expect(
      compatibleImageUri(Uri.parse('https://example.com/image.png')).toString(),
      'https://example.com/image.png',
    );
    expect(
      isFormulaImageUri(
        Uri.parse(
          'https://fb.fbstatic.cn/api/planet/accessories/formulas?latex=abc',
        ),
      ),
      isTrue,
    );
    expect(
      isFormulaImageUri(
        Uri.parse(
          'https://fb.fbstatic.cn/api/tarzan/images/diagram.png?width=700',
        ),
      ),
      isFalse,
    );
  });

  testWidgets('keeps formula images at intrinsic size', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownContent(
            data:
                '![formula](https://fb.fenbike.cn/api/planet/accessories/formulas?latex=abc)',
          ),
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image).first);
    expect(image.width, isNull);
    expect(image.height, isNull);
    final formulaAlign = tester.widget<Align>(find.byType(Align).first);
    expect(formulaAlign.widthFactor, 1);
    expect(formulaAlign.heightFactor, 1);
  });

  testWidgets('renders a compact preview for a bare image URL', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ImageLinkPreview(data: 'https://invalid.example/image.png'),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ImageLinkPreview), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.contain);
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

  testWidgets('opens a zoomable viewer when a detail image is tapped', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownContent(
            data: '![鍥剧墖](https://invalid.example/image.png)',
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(Image));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
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
