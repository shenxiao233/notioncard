import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/models/card_model.dart';
import '../../core/utils/rich_text.dart';

/// A normalized question from the browser's error-question export format.
class BrowserCardDraft {
  const BrowserCardDraft({
    required this.sourceIndex,
    required this.externalId,
    required this.externalKey,
    required this.type,
    required this.source,
    required this.question,
    required this.options,
    required this.answer,
    required this.explanation,
    required this.tags,
  });

  final int sourceIndex;
  final String externalId;
  final String externalKey;
  final CardType type;
  final String source;
  final String question;
  final Map<String, String> options;
  final List<String> answer;
  final String explanation;
  final List<String> tags;

  String get fingerprint {
    final payload = jsonEncode({
      'source': source,
      'question': question,
      'options': options,
      'answer': answer,
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  String get importIdentity =>
      externalKey.trim().isNotEmpty ? 'key:$externalKey' : 'hash:$fingerprint';
}

class BrowserCardImportIssue {
  const BrowserCardImportIssue({required this.index, required this.message});

  final int index;
  final String message;
}

class BrowserCardImportDocument {
  const BrowserCardImportDocument({
    required this.exportedAt,
    required this.cards,
    required this.issues,
  });

  final DateTime? exportedAt;
  final List<BrowserCardDraft> cards;
  final List<BrowserCardImportIssue> issues;
}

BrowserCardImportDocument parseBrowserCardJson(String raw) {
  final decoded = jsonDecode(raw.replaceFirst('\uFEFF', ''));
  if (decoded is! Map) {
    throw const FormatException('JSON 根节点必须是对象');
  }

  final data = decoded['data'];
  if (data is! List) {
    throw const FormatException('JSON 中没有可导入的 data 数组');
  }

  final exportedAt = DateTime.tryParse(_stringValue(decoded['exportedAt']));
  final cards = <BrowserCardDraft>[];
  final issues = <BrowserCardImportIssue>[];
  for (var index = 0; index < data.length; index++) {
    final item = data[index];
    try {
      if (item is! Map) {
        throw const FormatException('题目数据不是对象');
      }
      cards.add(_parseDraft(item, index));
    } catch (error) {
      issues.add(
        BrowserCardImportIssue(
          index: index,
          message: error is FormatException ? error.message : '$error',
        ),
      );
    }
  }

  return BrowserCardImportDocument(
    exportedAt: exportedAt,
    cards: cards,
    issues: issues,
  );
}

BrowserCardDraft _parseDraft(Map<dynamic, dynamic> item, int index) {
  final question = normalizeImportedRichText(_stringValue(item['content']));
  if (question.trim().isEmpty) {
    throw const FormatException('题目内容为空');
  }

  final correctAnswer = item['correctAnswer'];
  final choice = correctAnswer is Map ? correctAnswer['choice'] : null;
  final typeCode = correctAnswer is Map
      ? _intValue(correctAnswer['type'])
      : null;
  final rawOptions = item['options'];

  final options = <String, String>{};
  final judgmentWithoutOptions = _isJudgmentWithoutOptions(
    question: question,
    rawOptions: rawOptions,
    rawChoice: choice,
    typeCode: typeCode,
  );
  if (judgmentWithoutOptions) {
    options['A'] = '正确';
    options['B'] = '错误';
  } else {
    if (rawOptions is! List || rawOptions.isEmpty) {
      throw const FormatException('选项为空');
    }
    for (var optionIndex = 0; optionIndex < rawOptions.length; optionIndex++) {
      final label = _optionLabel(optionIndex);
      options[label] = normalizeImportedRichText(
        _stringValue(rawOptions[optionIndex]),
      );
    }
  }

  final answer = _answerLabels(choice, options.length);
  if (answer.isEmpty) {
    throw const FormatException('没有识别到正确答案');
  }

  final type = judgmentWithoutOptions
      ? CardType.trueFalse
      : _cardType(
          typeCode: typeCode,
          options: options,
          answerCount: answer.length,
        );

  final rawTags = item['keypoints'];
  final tags = rawTags is List
      ? rawTags
            .map(_stringValue)
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
      : const <String>[];

  return BrowserCardDraft(
    sourceIndex: index,
    externalId: _stringValue(item['id']),
    externalKey: _stringValue(item['key']),
    type: type,
    source: _stringValue(item['source']).trim(),
    question: question,
    options: options,
    answer: answer,
    explanation: normalizeImportedRichText(_stringValue(item['solution'])),
    tags: tags,
  );
}

bool _isJudgmentWithoutOptions({
  required String question,
  required dynamic rawOptions,
  required dynamic rawChoice,
  required int? typeCode,
}) {
  if (rawOptions is! List || rawOptions.isNotEmpty) return false;
  if (typeCode == 203) return _hasBinaryChoice(rawChoice);

  // Some browser exports mark judgment questions as type 201 (single choice)
  // and omit the two display options. The blank parentheses in the prompt
  // are the reliable signal for that legacy representation.
  return _hasJudgmentBlank(question) && _hasBinaryChoice(rawChoice);
}

bool _hasBinaryChoice(dynamic rawChoice) {
  if (rawChoice is List) {
    return rawChoice.length == 1 && _choiceToLabel(rawChoice.single, 2) != null;
  }
  return _choiceToLabel(rawChoice, 2) != null;
}

bool _hasJudgmentBlank(String question) {
  return RegExp(r'[\(（]\s*[\)）]').hasMatch(question);
}

/// Converts browser HTML into the Markdown format already rendered by cards.
///
/// The export uses whitespace-only `<u>` elements for fill-in-the-blank
/// lines. Those spaces must become an equal number of underscores before the
/// generic HTML converter removes the underline tag; otherwise Markdown will
/// collapse or hide the blank line.
String normalizeImportedRichText(String source) {
  var value = source
      .replaceAll('\uFEFF', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');

  value = value.replaceAllMapped(
    RegExp(r'<u\b[^>]*>([\s\S]*?)</u>', caseSensitive: false),
    (match) {
      final inner = decodeHtmlEntities(match.group(1) ?? '')
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'<[^>]+>', caseSensitive: false), '');
      if (inner.trim().isNotEmpty) return match.group(0) ?? '';

      final whitespaceCount = RegExp(r'\s').allMatches(inner).length;
      if (whitespaceCount < 3) return inner;
      return '_' * whitespaceCount;
    },
  );

  return htmlToMarkdown(value);
}

String importedCardId({
  required String accountId,
  required String folder,
  required BrowserCardDraft draft,
}) {
  final material = [
    accountId.trim(),
    folder.trim(),
    draft.importIdentity,
  ].join('|');
  final digest = sha256.convert(utf8.encode(material)).toString();
  return 'file-import-${digest.substring(0, 32)}';
}

String _optionLabel(int index) {
  var value = index;
  var label = '';
  do {
    label = String.fromCharCode(65 + (value % 26)) + label;
    value = value ~/ 26 - 1;
  } while (value >= 0);
  return label;
}

List<String> _answerLabels(dynamic rawChoice, int optionCount) {
  final choices = <dynamic>[];
  if (rawChoice is List) {
    choices.addAll(rawChoice);
  } else if (rawChoice != null) {
    final text = _stringValue(rawChoice).trim();
    if (RegExp(r'[,，、/|\s]').hasMatch(text)) {
      choices.addAll(text.split(RegExp(r'[,，、/|\s]+')));
    } else {
      choices.add(rawChoice);
    }
  }

  final labels = <String>[];
  for (final choice in choices) {
    final label = _choiceToLabel(choice, optionCount);
    if (label != null && !labels.contains(label)) labels.add(label);
  }
  return labels;
}

String? _choiceToLabel(dynamic rawChoice, int optionCount) {
  if (rawChoice is num) {
    return _indexToLabel(rawChoice.toInt(), optionCount);
  }

  final value = _stringValue(rawChoice).trim();
  if (value.isEmpty) return null;
  final upper = value.toUpperCase();
  if (RegExp(r'^[A-Z]+$').hasMatch(upper)) {
    final index = _labelToIndex(upper);
    return index >= 0 && index < optionCount ? upper : null;
  }

  final index = int.tryParse(value);
  return index == null ? null : _indexToLabel(index, optionCount);
}

String? _indexToLabel(int index, int optionCount) {
  if (index < 0 || index >= optionCount) return null;
  return _optionLabel(index);
}

int _labelToIndex(String value) {
  var result = 0;
  for (final codeUnit in value.codeUnits) {
    result = result * 26 + codeUnit - 64;
  }
  return result - 1;
}

CardType _cardType({
  required int? typeCode,
  required Map<String, String> options,
  required int answerCount,
}) {
  if (answerCount > 1 || typeCode == 202) return CardType.multiple;
  if (typeCode == 203 || _looksLikeTrueFalse(options)) {
    return CardType.trueFalse;
  }
  return CardType.single;
}

bool _looksLikeTrueFalse(Map<String, String> options) {
  if (options.length != 2) return false;
  final values = options.values
      .map((value) => htmlToMarkdown(value).trim())
      .toSet();
  return values.contains('正确') && values.contains('错误') ||
      values.contains('对') && values.contains('错') ||
      values.contains('是') && values.contains('否');
}

String _stringValue(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  return '$value';
}

int? _intValue(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(_stringValue(value));
}
