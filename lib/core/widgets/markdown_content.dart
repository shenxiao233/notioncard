import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import '../network/api_config.dart';
import '../utils/rich_text.dart';

class MarkdownHighlight {
  const MarkdownHighlight({
    required this.id,
    required this.text,
    required this.color,
  });

  final String id;
  final String text;
  final Color color;
}

/// Read-only Markdown renderer shared by documents, cards and review prompts.
class MarkdownContent extends StatelessWidget {
  const MarkdownContent({
    required this.data,
    this.selectable = true,
    this.textStyle,
    this.onTapLink,
    this.noteEntries = false,
    this.highlights = const <MarkdownHighlight>[],
    super.key,
  });

  final String data;
  final bool selectable;
  final TextStyle? textStyle;
  final MarkdownTapLinkCallback? onTapLink;
  final bool noteEntries;
  final List<MarkdownHighlight> highlights;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MarkdownBody(
      data: _prepareMarkdown(
        data,
        noteEntries: noteEntries,
        highlights: highlights,
      ),
      selectable: selectable,
      onTapLink: onTapLink,
      inlineSyntaxes: [
        if (noteEntries) _NoteLabelSyntax(),
        if (highlights.isNotEmpty) _HighlightSyntax(),
        _InlineLatexSyntax(),
      ],
      blockSyntaxes: [const _BlockLatexSyntax()],
      builders: {
        'latex-inline': _LatexBuilder(display: false),
        'pre': _LatexBuilder(display: true),
        if (noteEntries) 'note-label': _NoteLabelBuilder(),
        if (highlights.isNotEmpty) 'highlight': _HighlightBuilder(),
      },
      sizedImageBuilder: (config) => _NetworkMarkdownImage(config: config),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: textStyle ?? theme.textTheme.bodyLarge,
        pPadding: const EdgeInsets.only(bottom: 10),
        h1: theme.textTheme.headlineSmall,
        h2: theme.textTheme.titleLarge,
        h3: theme.textTheme.titleMedium,
        h1Padding: const EdgeInsets.only(top: 14, bottom: 8),
        h2Padding: const EdgeInsets.only(top: 14, bottom: 6),
        h3Padding: const EdgeInsets.only(top: 10, bottom: 4),
        blockquoteDecoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.55),
          border: Border(left: BorderSide(color: scheme.primary, width: 4)),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        codeblockDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outline),
        ),
        codeblockPadding: const EdgeInsets.all(14),
        tableBorder: TableBorder.all(color: scheme.outline),
        tableHead: theme.textTheme.titleMedium,
      ),
    );
  }
}

/// Returns image URLs embedded in plain text, Markdown, or HTML content.
///
/// Card questions are often imported as a bare URL rather than Markdown. The
/// detail renderer already understands those URLs; this helper lets compact
/// list views reuse the same detection rules without displaying the raw link.
List<String> extractImageLinkUrls(String source) {
  final normalized = htmlToMarkdown(source);
  final urls = <String>[];

  void add(String raw) {
    var value = raw.trim();
    value = value.replaceFirst(RegExp(r'[.,;:!，。；：！\)\]\}]+$'), '');
    if (value.isEmpty || !_looksLikeImageUrl(value) || urls.contains(value)) {
      return;
    }
    urls.add(value);
  }

  final markdownPattern = RegExp(
    r'!\[[^\]]*\]\(\s*<?((?:https?://|data:image/)[^)\s>]+)>?\s*\)',
    caseSensitive: false,
  );
  for (final match in markdownPattern.allMatches(normalized)) {
    final value = match.group(1);
    if (value != null) add(value);
  }

  final htmlPattern = RegExp(
    r'''<img\b[^>]*?\bsrc\s*=\s*(?:["']([^"']+)["']|([^\s>]+))[^>]*>''',
    caseSensitive: false,
  );
  for (final match in htmlPattern.allMatches(source)) {
    add(match.group(1) ?? match.group(2) ?? '');
  }

  final barePattern = RegExp(
    r'(?<![<(\[])((?:https?://|data:image/)[^\s<>]+)',
    caseSensitive: false,
  );
  for (final match in barePattern.allMatches(normalized)) {
    final value = match.group(1);
    if (value != null) add(value);
  }
  return urls;
}

/// Shows a compact inline preview for image links found in card content.
/// Tapping a thumbnail opens a zoomable full-screen viewer.
class ImageLinkPreview extends StatelessWidget {
  const ImageLinkPreview({
    required this.data,
    this.textStyle,
    this.maxLines = 2,
    this.thumbnailWidth = 116,
    this.thumbnailHeight = 72,
    this.maxImages = 3,
    super.key,
  });

  final String data;
  final TextStyle? textStyle;
  final int maxLines;
  final double thumbnailWidth;
  final double thumbnailHeight;
  final int maxImages;

  @override
  Widget build(BuildContext context) {
    final normalized = htmlToMarkdown(data);
    final urls = extractImageLinkUrls(normalized);
    final label = _removeImageLinkReferences(normalized, urls);
    final visibleUrls = urls.take(maxImages < 1 ? 1 : maxImages).toList();

    if (label.isEmpty && visibleUrls.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          Text(
            label,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        if (visibleUrls.isNotEmpty) ...[
          if (label.isNotEmpty) const SizedBox(height: 7),
          SizedBox(
            height: thumbnailHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              itemCount: visibleUrls.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) => _ImageLinkThumbnail(
                source: visibleUrls[index],
                width: thumbnailWidth,
                height: thumbnailHeight,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

String _removeImageLinkReferences(String source, List<String> urls) {
  var value = source.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\(\s*<[^>]*>\s*\)', caseSensitive: false),
    (match) => match.group(1) ?? '',
  );
  value = value.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]*\)', caseSensitive: false),
    (match) => match.group(1) ?? '',
  );
  value = value.replaceAll(RegExp(r'<img\b[^>]*>', caseSensitive: false), '');
  for (final url in urls) {
    value = value.replaceAll(url, '');
  }
  return value
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s.,;:!，。；：！]+|[\s.,;:!，。；：！]+$'), '')
      .trim();
}

class _ImageLinkThumbnail extends StatelessWidget {
  const _ImageLinkThumbnail({
    required this.source,
    required this.width,
    required this.height,
  });

  final String source;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(9);
    return Semantics(
      button: true,
      label: '预览图片',
      child: SizedBox(
        width: width,
        height: height,
        child: Material(
          color: Colors.white,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: radius,
            onTap: () => _showImageLinkViewer(context, source),
            // Contain keeps the complete source image visible. Cover would
            // crop wide or tall question images inside the fixed thumbnail.
            child: _ImageLinkSource(source: source, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

class _ImageLinkSource extends StatelessWidget {
  const _ImageLinkSource({required this.source, required this.fit});

  final String source;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = _decodeDataUri(source);
    if (data != null) {
      return Image.memory(
        data,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) =>
            _ImageFallback(label: '图片无法显示'),
      );
    }

    final parsed = Uri.tryParse(source);
    final uri = parsed == null ? null : _resolveUri(parsed);
    if (uri == null) return _ImageFallback(label: source);
    return Image.network(
      uri.toString(),
      fit: fit,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : Container(
              color: scheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
      errorBuilder: (context, error, stackTrace) =>
          _ImageFallback(label: '图片加载失败'),
    );
  }
}

void _showImageLinkViewer(BuildContext context, String source) {
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭图片预览',
    barrierColor: Colors.black87,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final size = MediaQuery.sizeOf(dialogContext);
      return SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.7,
                maxScale: 4,
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: _ImageLinkSource(source: source, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                tooltip: '关闭预览',
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      );
    },
  );
}

String _prepareMarkdown(
  String source, {
  bool noteEntries = false,
  List<MarkdownHighlight> highlights = const <MarkdownHighlight>[],
}) {
  final converted = htmlToMarkdown(source);
  final value = converted.trim().isEmpty ? '暂无内容' : converted;
  final lines = value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  var fenced = false;
  final prepared = lines
      .map((line) {
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
          fenced = !fenced;
          return line;
        }
        if (fenced) return line;
        var prepared = _convertHtmlImages(_convertBareImageUrls(line));
        if (noteEntries) prepared = _convertNoteEntry(prepared);
        return prepared;
      })
      .join('\n');
  return _applyHighlights(prepared, highlights);
}

String _applyHighlights(
  String source,
  List<MarkdownHighlight> highlights,
) {
  if (highlights.isEmpty) return source;
  var value = source;
  final ordered = [...highlights]
    ..removeWhere((highlight) => highlight.text.trim().isEmpty)
    ..sort((left, right) => right.text.length.compareTo(left.text.length));
  for (final highlight in ordered) {
    final text = highlight.text;
    final marker =
        '[[highlight:${highlight.id}|${_colorToHex(highlight.color)}]]'
        '$text[[/highlight]]';
    value = value.replaceFirst(RegExp.escape(text), marker);
  }
  return value;
}

String _colorToHex(Color color) {
  final value = color.toARGB32().toRadixString(16).padLeft(8, '0');
  return value.substring(2);
}

String _convertNoteEntry(String line) {
  final match = RegExp(
    r'^(\s*)(专题|真题|例句)(?:(?:\s*[:：]\s*)|(?:\s+))?(.*)$',
  ).firstMatch(line);
  if (match == null) return line;
  final label = match.group(2)!;
  final content = match.group(3)!.trim();
  return '${match.group(1)}[[note-label:$label]]${content.isEmpty ? '' : ' $content'}';
}

String _convertHtmlImages(String line) {
  final pattern = RegExp(
    r'''<img\b[^>]*?\bsrc\s*=\s*(?:["']([^"']+)["']|([^\s>]+))[^>]*>''',
    caseSensitive: false,
  );
  return line.replaceAllMapped(pattern, (match) {
    final source = (match.group(1) ?? match.group(2) ?? '').trim();
    return source.isEmpty ? '' : '![](<$source>)';
  });
}

String _convertBareImageUrls(String line) {
  final urlPattern = RegExp(
    r'(?<![<(\[])https?://[^\s<>]+',
    caseSensitive: false,
  );
  return line.replaceAllMapped(urlPattern, (match) {
    final raw = match.group(0)!;
    final trailing =
        RegExp(r'[.,;:!?，。；：！？)）】》]+$').firstMatch(raw)?.group(0) ?? '';
    final url = trailing.isEmpty
        ? raw
        : raw.substring(0, raw.length - trailing.length);
    if (!_looksLikeImageUrl(url)) return raw;
    return '![](<$url>)$trailing';
  });
}

bool _looksLikeImageUrl(String value) {
  if (value.toLowerCase().startsWith('data:image/')) return true;
  final uri = Uri.tryParse(value);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https'))
    return false;
  final path = uri.path.toLowerCase();
  return RegExp(r'\.(png|jpe?g|gif|webp|svg|bmp|avif)$').hasMatch(path) ||
      path.contains('/image') ||
      path.contains('/upload') ||
      uri.queryParameters.keys.any(
        (key) => const {
          'format',
          'image',
          'filename',
          'file',
        }.contains(key.toLowerCase()),
      );
}

class _InlineLatexSyntax extends md.InlineSyntax {
  _InlineLatexSyntax()
    : super(
        r'(?:\\\(([^\n]*?)\\\)|\\\[([^\n]*?)\\\]|\$\$([^\n]*?)\$\$|\$([^$\n]+?)\$)',
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final formula =
        (match.group(1) ??
                match.group(2) ??
                match.group(3) ??
                match.group(4) ??
                '')
            .trim();
    if (formula.isEmpty) return false;
    parser.addNode(
      md.Element.text('latex-inline', formula)
        ..attributes['data-display'] =
            (match.group(2) != null || match.group(3) != null).toString(),
    );
    return true;
  }
}

class _NoteLabelSyntax extends md.InlineSyntax {
  _NoteLabelSyntax() : super(r'\[\[note-label:(专题|真题|例句)\]\]');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('note-label', match.group(1)!));
    return true;
  }
}

class _HighlightSyntax extends md.InlineSyntax {
  _HighlightSyntax()
    : super(
        r'\[\[highlight:([^\|\]]+)\|([0-9a-fA-F]{6})\]\]([\s\S]*?)\[\[\/highlight\]\]',
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element.text('highlight', match.group(3)!)
        ..attributes['data-highlight-id'] = match.group(1)!
        ..attributes['data-highlight-color'] = match.group(2)!,
    );
    return true;
  }
}

class _BlockLatexSyntax extends md.BlockSyntax {
  const _BlockLatexSyntax();

  @override
  RegExp get pattern => RegExp(r'^\s*(?:\$\$|\\\[)\s*$');

  @override
  md.Node parse(md.BlockParser parser) {
    final opening = parser.current.content;
    final isBracket = opening.trim().startsWith(r'\[');
    parser.advance();
    final lines = <String>[];
    while (!parser.isDone) {
      final line = parser.current.content;
      final closes = isBracket ? line.trim() == r'\]' : line.trim() == r'$$';
      if (closes) {
        parser.advance();
        break;
      }
      lines.add(line);
      parser.advance();
    }
    return md.Element.text('pre', lines.join('\n').trim())
      ..attributes['data-latex'] = 'true';
  }
}

class _LatexBuilder extends MarkdownElementBuilder {
  _LatexBuilder({required this.display});

  final bool display;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (element.tag == 'pre' && element.attributes['data-latex'] != 'true') {
      return null;
    }
    final isDisplay = display || element.attributes['data-display'] == 'true';
    final formula = element.textContent.trim();
    if (formula.isEmpty) return null;
    final formulaWidget = Math.tex(
      formula,
      mathStyle: isDisplay ? MathStyle.display : MathStyle.text,
      onErrorFallback: (error) => Text(
        isDisplay ? r'\[' + formula + r'\]' : r'$' + formula + r'$',
        style: preferredStyle,
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isDisplay ? 10 : 2),
      child: isDisplay
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: formulaWidget,
            )
          : formulaWidget,
    );
  }

  @override
  bool isBlockElement() => display;
}

class _NoteLabelBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final label = element.textContent;
    final color = switch (label) {
      '专题' => const Color(0xffc45151),
      '真题' => const Color(0xffc47a3b),
      _ => const Color(0xff2f8b78),
    };
    // Keep the badge inside the surrounding RichText so the following example
    // text stays on the same line whenever there is enough room.
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const TextSpan(text: ' '),
        ],
      ),
      style: preferredStyle,
    );
  }
}

class _HighlightBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final color = _colorFromHex(element.attributes['data-highlight-color']);
    return Text.rich(
      TextSpan(
        text: element.textContent,
        style: (preferredStyle ?? const TextStyle()).copyWith(
          backgroundColor: color.withValues(alpha: 0.24),
        ),
      ),
    );
  }
}

Color _colorFromHex(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return const Color(0xfff7d97a);
  }
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) return const Color(0xfff7d97a);
  return Color(0xff000000 | parsed);
}

class _NetworkMarkdownImage extends StatelessWidget {
  const _NetworkMarkdownImage({required this.config});

  final MarkdownImageConfig config;

  @override
  Widget build(BuildContext context) {
    return _MarkdownImageFrame(
      source: config.uri.toString(),
      child: _buildImage(context),
    );
  }

  Widget _buildImage(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rawSource = config.uri.toString();
    final data = _decodeDataUri(rawSource);
    if (data != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: Image.memory(
              data,
              width: double.infinity,
              height: config.height,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              errorBuilder: (context, error, stackTrace) => _ImageFallback(
                label: config.alt?.trim().isNotEmpty == true
                    ? config.alt!
                    : '图片无法显示',
              ),
            ),
          ),
        ),
      );
    }

    final uri = _resolveUri(config.uri);
    if (uri == null)
      return _ImageFallback(label: config.alt ?? config.uri.toString());

    final isFormula = isFormulaImageUri(uri);
    final image = Image.network(
      uri.toString(),
      // Formula images are rendered at their intrinsic size. Normal images
      // keep the existing full-content-width behavior.
      width: isFormula ? config.width : double.infinity,
      height: config.height,
      fit: BoxFit.contain,
      alignment: Alignment.centerLeft,
      filterQuality: FilterQuality.high,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : Container(
              width: isFormula ? 48 : double.infinity,
              height: isFormula ? 36 : 120,
              alignment: Alignment.center,
              color: scheme.surfaceContainerHighest,
              child: const CircularProgressIndicator(),
            ),
      errorBuilder: (context, error, stackTrace) => _ImageFallback(
        label: config.alt?.trim().isNotEmpty == true
            ? config.alt!
            : uri.toString(),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: isFormula
            ? Align(
                alignment: Alignment.centerLeft,
                // Shrink-wrap the image so adjacent text/formulas can share
                // the same Markdown paragraph line.
                widthFactor: 1,
                heightFactor: 1,
                child: image,
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 520),
                child: image,
              ),
      ),
    );
  }
}

class _MarkdownImageFrame extends StatelessWidget {
  const _MarkdownImageFrame({required this.source, required this.child});

  final String source;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(10);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Semantics(
        button: true,
        label: '点击放大图片',
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: radius,
            onTap: () => _showImageLinkViewer(context, source),
            child: ClipRRect(borderRadius: radius, child: child),
          ),
        ),
      ),
    );
  }
}

Uint8List? _decodeDataUri(String value) {
  if (!value.toLowerCase().startsWith('data:image/')) return null;
  final comma = value.indexOf(',');
  if (comma < 0) return null;
  final metadata = value.substring(5, comma).toLowerCase();
  if (metadata.startsWith('svg') || metadata.contains('svg+xml')) return null;
  final payload = value.substring(comma + 1).replaceAll(RegExp(r'\s+'), '');
  try {
    if (metadata.contains(';base64')) {
      return base64Decode(payload.replaceAll('-', '+').replaceAll('_', '/'));
    }
    return Uint8List.fromList(utf8.encode(Uri.decodeComponent(payload)));
  } catch (_) {
    return null;
  }
}

/// Resolves an image URI and applies known CDN compatibility rules.
///
/// Some exported image URLs use `fb.fenbike.cn`. That host currently serves
/// the PNG bytes with `Content-Encoding: br`, while Flutter's default
/// `Image.network` path does not decode that response on the target device.
/// The same path is available from `fb.fbstatic.cn` without Brotli encoding.
/// Keep the original URL in card data and only rewrite it at render time so
/// existing imports and user-edited content remain unchanged.
Uri? _resolveUri(Uri source) {
  if (source.hasScheme &&
      (source.scheme == 'http' || source.scheme == 'https')) {
    return compatibleImageUri(source);
  }
  final base = Uri.tryParse(ApiConfig.defaultBaseUrl);
  final resolved = base?.resolve(source.toString());
  return resolved == null ? null : compatibleImageUri(resolved);
}

Uri compatibleImageUri(Uri source) {
  if (source.host.toLowerCase() != 'fb.fenbike.cn') return source;
  return source.replace(host: 'fb.fbstatic.cn');
}

/// Formula images exported by the browser use the `latex` image endpoint.
/// They are small rasterized formulas and must keep their intrinsic size
/// instead of being stretched to the content width like diagrams.
bool isFormulaImageUri(Uri source) {
  return source.path.toLowerCase().contains('/formulas') &&
      source.queryParameters.containsKey('latex');
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: scheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
