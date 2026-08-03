String htmlToMarkdown(String source) {
  var value = source
      .replaceAll('\uFEFF', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .trim();
  if (value.isEmpty ||
      !RegExp(r'<[a-z][^>]*>', caseSensitive: false).hasMatch(value)) {
    return decodeHtmlEntities(value);
  }

  final protected = <String>[];
  String protect(String content) {
    final token = '\uE000${protected.length}\uE001';
    protected.add(content);
    return token;
  }

  value = value.replaceAllMapped(
    RegExp(r'<pre\b[^>]*>([\s\S]*?)</pre>', caseSensitive: false),
    (match) {
      final code = decodeHtmlEntities(_stripTags(match.group(1) ?? '').trim());
      return protect(code.isEmpty ? '```\n```' : '```\n$code\n```');
    },
  );
  value = value.replaceAllMapped(
    RegExp(
      r'''<[^>]*\bdata-latex-source\s*=\s*(?:"([\s\S]*?)"|'([\s\S]*?)'|([^\s>]+))[^>]*>''',
      caseSensitive: false,
    ),
    (match) {
      final source = decodeHtmlEntities(
        match.group(1) ?? match.group(2) ?? match.group(3) ?? '',
      ).trim();
      if (source.isEmpty) return '';
      final tag = match.group(0) ?? '';
      final display = _htmlAttribute(tag, 'data-latex-display') == 'true';
      return protect(display ? '\$\$\n$source\n\$\$' : '\$$source\$');
    },
  );
  value = value.replaceAllMapped(
    RegExp(r'<img\b[^>]*>', caseSensitive: false),
    (match) {
      final tag = match.group(0)!;
      final src = _htmlAttribute(tag, 'src');
      if (src == null || src.isEmpty) return '';
      final alt = _htmlAttribute(tag, 'alt') ?? '';
      return protect('![$alt]($src)');
    },
  );
  value = value.replaceAllMapped(
    RegExp(
      r'''<a\b[^>]*\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))[^>]*>([\s\S]*?)</a>''',
      caseSensitive: false,
    ),
    (match) {
      final href = match.group(1) ?? match.group(2) ?? match.group(3) ?? '';
      final label = _stripTags(match.group(4) ?? '').trim();
      if (href.isEmpty) return label;
      return protect('[$label]($href)');
    },
  );

  value = value
      .replaceAll(RegExp(r'<h1\b[^>]*>', caseSensitive: false), '\n# ')
      .replaceAll(RegExp(r'<h2\b[^>]*>', caseSensitive: false), '\n## ')
      .replaceAll(RegExp(r'<h3\b[^>]*>', caseSensitive: false), '\n### ')
      .replaceAll(RegExp(r'<h4\b[^>]*>', caseSensitive: false), '\n#### ')
      .replaceAll(RegExp(r'<h5\b[^>]*>', caseSensitive: false), '\n##### ')
      .replaceAll(RegExp(r'<h6\b[^>]*>', caseSensitive: false), '\n###### ')
      .replaceAll(RegExp(r'</h[1-6]>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '\n- ')
      .replaceAll(RegExp(r'</li>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<blockquote\b[^>]*>', caseSensitive: false), '\n> ')
      .replaceAll(RegExp(r'</blockquote>', caseSensitive: false), '\n\n')
      .replaceAll(
        RegExp(
          r'<(p|div|section|article|figure)\b[^>]*>',
          caseSensitive: false,
        ),
        '\n',
      )
      .replaceAll(
        RegExp(r'</(p|div|section|article|figure)>', caseSensitive: false),
        '\n\n',
      )
      .replaceAll(RegExp(r'<hr\s*/?>', caseSensitive: false), '\n---\n')
      .replaceAll(
        RegExp(r'<strong\b[^>]*>|<b\b[^>]*>', caseSensitive: false),
        '**',
      )
      .replaceAll(RegExp(r'</strong>|</b>', caseSensitive: false), '**')
      .replaceAll(RegExp(r'<em\b[^>]*>|<i\b[^>]*>', caseSensitive: false), '*')
      .replaceAll(RegExp(r'</em>|</i>', caseSensitive: false), '*')
      .replaceAll(RegExp(r'<code\b[^>]*>', caseSensitive: false), '`')
      .replaceAll(RegExp(r'</code>', caseSensitive: false), '`');

  value = _stripTags(value);
  value = decodeHtmlEntities(value)
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  for (var index = 0; index < protected.length; index++) {
    value = value.replaceAll('\uE000$index\uE001', protected[index]);
  }
  return value;
}

String decodeHtmlEntities(String source) {
  var value = source
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");
  value = value.replaceAllMapped(
    RegExp(r'&#x([0-9a-f]+);', caseSensitive: false),
    (match) {
      final codePoint = int.tryParse(match.group(1)!, radix: 16);
      return codePoint == null
          ? match.group(0)!
          : String.fromCharCode(codePoint);
    },
  );
  return value.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
    final codePoint = int.tryParse(match.group(1)!);
    return codePoint == null ? match.group(0)! : String.fromCharCode(codePoint);
  });
}

String? _htmlAttribute(String tag, String name) {
  final doubleQuoted = RegExp(
    '\\b$name\\s*=\\s*"([^"]*)"',
    caseSensitive: false,
  ).firstMatch(tag);
  if (doubleQuoted != null) return doubleQuoted.group(1);

  final singleQuoted = RegExp(
    "\\b$name\\s*=\\s*'([^']*)'",
    caseSensitive: false,
  ).firstMatch(tag);
  if (singleQuoted != null) return singleQuoted.group(1);

  return RegExp(
    '\\b$name\\s*=\\s*([^\\s>]+)',
    caseSensitive: false,
  ).firstMatch(tag)?.group(1);
}

String _stripTags(String source) =>
    source.replaceAll(RegExp(r'<[^>]+>', caseSensitive: false), '');
