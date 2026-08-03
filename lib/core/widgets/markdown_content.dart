import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import '../network/api_config.dart';
import '../utils/rich_text.dart';

/// Read-only Markdown renderer shared by documents, cards and review prompts.
class MarkdownContent extends StatelessWidget {
  const MarkdownContent({
    required this.data,
    this.selectable = true,
    this.textStyle,
    this.onTapLink,
    this.noteEntries = false,
    super.key,
  });

  final String data;
  final bool selectable;
  final TextStyle? textStyle;
  final MarkdownTapLinkCallback? onTapLink;
  final bool noteEntries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MarkdownBody(
      data: _prepareMarkdown(data, noteEntries: noteEntries),
      selectable: selectable,
      onTapLink: onTapLink,
      inlineSyntaxes: [
        if (noteEntries) _NoteLabelSyntax(),
        _InlineLatexSyntax(),
      ],
      blockSyntaxes: [const _BlockLatexSyntax()],
      builders: {
        'latex-inline': _LatexBuilder(display: false),
        'pre': _LatexBuilder(display: true),
        if (noteEntries) 'note-label': _NoteLabelBuilder(),
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

String _prepareMarkdown(String source, {bool noteEntries = false}) {
  final converted = htmlToMarkdown(source);
  final value = converted.trim().isEmpty ? '暂无内容' : converted;
  final lines = value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  var fenced = false;
  return lines
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
    return Container(
      margin: const EdgeInsets.only(right: 6),
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
    );
  }
}

class _NetworkMarkdownImage extends StatelessWidget {
  const _NetworkMarkdownImage({required this.config});

  final MarkdownImageConfig config;

  @override
  Widget build(BuildContext context) {
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: Image.network(
            uri.toString(),
            width: double.infinity,
            height: config.height,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : Container(
                    height: 120,
                    alignment: Alignment.center,
                    color: scheme.surfaceContainerHighest,
                    child: const CircularProgressIndicator(),
                  ),
            errorBuilder: (context, error, stackTrace) => _ImageFallback(
              label: config.alt?.trim().isNotEmpty == true
                  ? config.alt!
                  : uri.toString(),
            ),
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

Uri? _resolveUri(Uri source) {
  if (source.hasScheme &&
      (source.scheme == 'http' || source.scheme == 'https')) {
    return source;
  }
  final base = Uri.tryParse(ApiConfig.defaultBaseUrl);
  return base?.resolve(source.toString());
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
