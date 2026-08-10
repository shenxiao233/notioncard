import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';

import '../../core/models/card_model.dart';
import 'market_model.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class MarketRepository {
  MarketRepository({this.apiClient});

  final ApiClient? apiClient;

  static const _maxPackageBytes = 50 * 1024 * 1024;
  static const _maxFileCount = 2000;
  static const _maxUncompressedBytes = 100 * 1024 * 1024;
  static const _maxJsonBytes = 10 * 1024 * 1024;
  static const _maxCardCount = 10000;
  static const _maxTextLength = 20000;

  Future<List<MarketDeckModel>> search({String query = ''}) async {
    if (apiClient != null) {
      try {
        final response = await apiClient!.get(
          '/api/v1/decks',
          queryParameters: {
            if (query.trim().isNotEmpty) 'search': query.trim(),
            'page': 1,
            'pageSize': 50,
          },
        );
        final body = response.data;
        final rawDecks = body is Map ? body['decks'] : body;
        if (rawDecks is List) {
          return rawDecks
              .whereType<Map>()
              .map((value) => _fromJson(Map<String, dynamic>.from(value)))
              .toList();
        }
      } on ApiException {
        // Offline mode falls back to the bundled sample market.
      }
    }
    final normalized = query.trim().toLowerCase();
    return _decks
        .where(
          (deck) =>
              normalized.isEmpty ||
              '${deck.title} ${deck.author} ${deck.category} ${deck.tags.join(' ')}'
                  .toLowerCase()
                  .contains(normalized),
        )
        .toList();
  }

  Future<MarketDeckModel?> findById(String id) async {
    if (apiClient != null) {
      try {
        final response = await apiClient!.get('/api/v1/decks/$id');
        if (response.data is Map) {
          return _fromJson(Map<String, dynamic>.from(response.data as Map));
        }
      } on ApiException {
        // Offline mode falls back to the bundled sample market.
      }
    }
    for (final deck in _decks) {
      if (deck.id == id) return deck;
    }
    return null;
  }

  Future<MarketDeckDownload> downloadDeck(String id) async {
    final client = apiClient;
    if (client == null) {
      throw const ApiException(
        statusCode: null,
        message: 'Market API is not configured',
      );
    }
    final response = await client.get(
      '/api/v1/decks/$id/download',
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data is Uint8List
        ? response.data as Uint8List
        : Uint8List.fromList(List<int>.from(response.data as List));
    if (bytes.length < 4 ||
        bytes[0] != 0x50 ||
        bytes[1] != 0x4b ||
        (bytes[2] != 0x03 && bytes[2] != 0x05 && bytes[2] != 0x07)) {
      throw const ApiException(
        statusCode: 502,
        message: 'Server returned an invalid deck ZIP package',
      );
    }
    final version = response.headers.value('x-deck-version');
    if (version == null || int.tryParse(version) == null) {
      throw const ApiException(
        statusCode: 502,
        message: 'Deck response is missing X-Deck-Version',
      );
    }
    return MarketDeckDownload(bytes: bytes, version: int.parse(version));
  }

  Future<MarketDeckPackage> parseDeckPackage(
    MarketDeckDownload download, {
    required String deckId,
    required String fallbackTitle,
    String accountId = '',
  }) async {
    if (download.bytes.length > _maxPackageBytes) {
      throw const MarketPackageException('牌组包过大，无法导入');
    }

    final archive = _decodeArchive(download.bytes);
    final files = <String, ArchiveFile>{};
    var uncompressedBytes = 0;
    var fileCount = 0;
    for (final file in archive) {
      final path = _safeArchivePath(file.name);
      if (file.isSymbolicLink) {
        throw const MarketPackageException('牌组包包含不支持的文件引用');
      }
      if (!file.isFile) continue;
      fileCount++;
      if (fileCount > _maxFileCount) {
        throw const MarketPackageException('牌组包文件数量超出限制');
      }
      uncompressedBytes += file.size;
      if (uncompressedBytes > _maxUncompressedBytes) {
        throw const MarketPackageException('牌组包解压后过大，无法导入');
      }
      if (files.containsKey(path)) {
        throw const MarketPackageException('牌组包包含重复文件');
      }
      files[path] = file;
    }

    final manifestFile = _findRequiredFile(files, 'manifest.json');
    final cardsFile = _findRequiredFile(files, 'cards.json');
    final manifest = _decodeObject(
      manifestFile,
      fileName: 'manifest.json',
      maxBytes: _maxJsonBytes,
    );
    final cardsJson = _decodeJson(
      cardsFile,
      fileName: 'cards.json',
      maxBytes: _maxJsonBytes,
    );

    _validateManifestFiles(manifest, files);
    final manifestVersion = _readVersion(manifest);
    if (manifestVersion == null) {
      throw const MarketPackageException('牌组包缺少版本信息');
    }
    if (manifestVersion != download.version) {
      throw const MarketPackageException('牌组包版本与下载信息不一致');
    }

    final title =
        _readText(
          manifest['title'] ?? manifest['name'],
          field: '牌组名称',
          required: false,
        ) ??
        fallbackTitle.trim();
    if (title.isEmpty) {
      throw const MarketPackageException('牌组缺少有效名称');
    }

    final rawCards =
        _extractCards(cardsJson) ??
        _extractCards(manifest['cards']) ??
        _extractCards(_decodeOptionalObject(files, 'deck.json'));
    if (rawCards == null) {
      throw const MarketPackageException('cards.json 中没有有效的卡片列表');
    }
    if (rawCards.isEmpty) {
      throw const MarketPackageException('牌组中没有可导入的卡片');
    }
    if (rawCards.length > _maxCardCount) {
      throw const MarketPackageException('牌组卡片数量超出限制');
    }

    final declaredCount = _readInt(manifest['cardCount']);
    if (declaredCount != null && declaredCount != rawCards.length) {
      throw const MarketPackageException('牌组卡片数量校验失败');
    }

    final now = DateTime.now();
    final ids = <String>{};
    final cards = <CardModel>[];
    for (var index = 0; index < rawCards.length; index++) {
      final raw = rawCards[index];
      if (raw is! Map) {
        throw MarketPackageException('第 ${index + 1} 张卡片格式无效');
      }
      final card = _cardFromJson(
        Map<String, dynamic>.from(raw),
        accountId: accountId,
        deckId: deckId,
        folder: title,
        index: index,
        now: now,
      );
      if (!ids.add(card.id)) {
        throw MarketPackageException('卡片 ID 重复：${card.id}');
      }
      cards.add(card);
    }

    return MarketDeckPackage(
      deckId: deckId,
      title: title,
      version: download.version,
      cards: cards,
    );
  }

  Archive _decodeArchive(Uint8List bytes) {
    try {
      return ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (_) {
      throw const MarketPackageException('服务器返回的牌组包损坏，无法解压');
    }
  }

  String _safeArchivePath(String rawPath) {
    final path = rawPath.replaceAll('\\', '/');
    final uri = Uri.tryParse(path);
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.startsWith('\\') ||
        RegExp(r'^[a-zA-Z]:').hasMatch(path) ||
        path.split('/').contains('..') ||
        (uri != null && uri.hasScheme)) {
      throw const MarketPackageException('牌组包包含不安全的文件路径');
    }
    return path.split('/').where((part) => part.isNotEmpty).join('/');
  }

  ArchiveFile _findRequiredFile(Map<String, ArchiveFile> files, String name) {
    final exact = files[name];
    if (exact != null) return exact;
    final matches = files.entries
        .where((entry) => entry.key.endsWith('/$name'))
        .map((entry) => entry.value)
        .toList();
    if (matches.length != 1) {
      throw MarketPackageException('牌组包缺少 $name');
    }
    return matches.single;
  }

  dynamic _decodeJson(
    ArchiveFile file, {
    required String fileName,
    required int maxBytes,
  }) {
    if (file.size > maxBytes) {
      throw MarketPackageException('$fileName 过大，无法解析');
    }
    try {
      final content = file.content;
      final bytes = content is List<int>
          ? content
          : List<int>.from(content as Iterable);
      return jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } catch (_) {
      throw MarketPackageException('$fileName 格式无效');
    }
  }

  Map<String, dynamic> _decodeObject(
    ArchiveFile file, {
    required String fileName,
    required int maxBytes,
  }) {
    final value = _decodeJson(file, fileName: fileName, maxBytes: maxBytes);
    if (value is! Map) {
      throw MarketPackageException('$fileName 必须是 JSON 对象');
    }
    return Map<String, dynamic>.from(value);
  }

  dynamic _decodeOptionalObject(Map<String, ArchiveFile> files, String name) {
    final file = files[name];
    if (file == null) return null;
    return _decodeJson(file, fileName: name, maxBytes: _maxJsonBytes);
  }

  List<dynamic>? _extractCards(dynamic value) {
    if (value is List) return List<dynamic>.from(value);
    if (value is Map) {
      for (final key in const ['cards', 'data', 'items']) {
        final nested = value[key];
        if (nested is List) return List<dynamic>.from(nested);
      }
    }
    return null;
  }

  void _validateManifestFiles(
    Map<String, dynamic> manifest,
    Map<String, ArchiveFile> files,
  ) {
    final declared = manifest['files'];
    if (declared == null) return;
    if (declared is! List) {
      throw const MarketPackageException('manifest.json 的文件清单格式无效');
    }
    for (final value in declared) {
      if (value is! String || value.trim().isEmpty) {
        throw const MarketPackageException('manifest.json 的文件清单格式无效');
      }
      final path = _safeArchivePath(value.trim());
      if (!files.containsKey(path) &&
          !files.keys.any((file) => file.endsWith('/$path'))) {
        throw MarketPackageException('牌组包缺少文件：$path');
      }
    }
  }

  int? _readVersion(Map<String, dynamic> manifest) {
    final value = manifest['version'] ?? manifest['deckVersion'];
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    if (value is String && value.trim().isNotEmpty) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  CardModel _cardFromJson(
    Map<String, dynamic> json, {
    required String accountId,
    required String deckId,
    required String folder,
    required int index,
    required DateTime now,
  }) {
    final sourceId = _readText(
      json['id'] ?? json['cardId'],
      field: '卡片 ID',
      required: false,
    );
    final id = _boundedText(
      sourceId == null || sourceId.isEmpty
          ? 'market-$deckId-${index + 1}'
          : 'market-$deckId-$sourceId',
      '卡片 ID',
    );
    final question = _readText(
      json['question'] ?? json['front'] ?? json['title'] ?? json['prompt'],
      field: '卡片题面',
    );
    if (question == null || question.isEmpty) {
      throw MarketPackageException('第 ${index + 1} 张卡片缺少题面');
    }

    final type = _parseCardType(json['type']);
    final answer = _readStringList(
      json['answer'] ??
          json['answers'] ??
          json['back'] ??
          json['correctAnswer'],
      field: '卡片答案',
    );
    final noteContent =
        _readText(
          json['noteContent'] ?? json['content'] ?? json['body'],
          field: '卡片内容',
          required: false,
        ) ??
        '';
    final explanation =
        _readText(
          json['explanation'] ?? json['analysis'],
          field: '卡片解析',
          required: false,
        ) ??
        '';
    final tags = _readStringList(json['tags'], field: '卡片标签', required: false);
    final declaredOrder = _readInt(json['sortOrder'] ?? json['order']);
    final sortOrder = declaredOrder != null && declaredOrder > 0
        ? declaredOrder
        : index + 1;

    return CardModel(
      id: id,
      accountId: accountId,
      type: type,
      folder: folder,
      question: question,
      options: _readOptions(json['options']),
      answer: answer,
      noteContent: noteContent,
      explanation: explanation,
      tags: tags,
      dueAt: now,
      // Preserve the source deck order explicitly. DateTime precision varies
      // between local database backends, so encoding the position in
      // createdAt is not reliable.
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
      reviews: 0,
      mastery: '',
      suspended: false,
      fsrs: FsrsSnapshot(
        state: FsrsState.newCard,
        dueAt: now,
        stability: 0,
        difficulty: 5,
        reps: 0,
        lapses: 0,
      ),
    );
  }

  CardType _parseCardType(Object? value) {
    final normalized = value?.toString().trim().toLowerCase().replaceAll(
      RegExp(r'[\s_-]'),
      '',
    );
    switch (normalized) {
      case null:
      case '':
      case 'note':
      case 'basic':
      case 'flashcard':
        return CardType.note;
      case 'single':
      case 'singlechoice':
      case 'singlechoicequestion':
        return CardType.single;
      case 'multiple':
      case 'multiplechoice':
      case 'multiplechoicequestion':
        return CardType.multiple;
      case 'truefalse':
      case 'boolean':
      case 'judge':
        return CardType.trueFalse;
      default:
        throw MarketPackageException('不支持的卡片类型：$value');
    }
  }

  Map<String, String> _readOptions(Object? value) {
    if (value == null) return const {};
    if (value is Map) {
      return value.map(
        (key, value) => MapEntry(
          _boundedText(key.toString(), '卡片选项'),
          _boundedText(value.toString(), '卡片选项'),
        ),
      );
    }
    if (value is List) {
      return {
        for (var index = 0; index < value.length; index++)
          String.fromCharCode(65 + index): _boundedText(
            value[index].toString(),
            '卡片选项',
          ),
      };
    }
    throw const MarketPackageException('卡片选项格式无效');
  }

  List<String> _readStringList(
    Object? value, {
    required String field,
    bool required = false,
  }) {
    if (value == null) {
      if (required) throw MarketPackageException('$field不能为空');
      return const [];
    }
    final values = value is List
        ? value
        : value is String
        ? (value.contains(',') ? value.split(',') : [value])
        : [value];
    final result = values
        .map((item) => item is String ? item.trim() : item.toString().trim())
        .where((item) => item.isNotEmpty)
        .map((item) => _boundedText(item, field))
        .toList();
    if (required && result.isEmpty) {
      throw MarketPackageException('$field不能为空');
    }
    return result;
  }

  String? _readText(
    Object? value, {
    required String field,
    bool required = true,
  }) {
    if (value == null) {
      if (required) throw MarketPackageException('$field不能为空');
      return null;
    }
    final text = value.toString().trim();
    if (required && text.isEmpty) {
      throw MarketPackageException('$field不能为空');
    }
    return text.isEmpty ? null : _boundedText(text, field);
  }

  String _boundedText(String value, String field) {
    if (value.length > _maxTextLength) {
      throw MarketPackageException('$field过长');
    }
    return value;
  }

  MarketDeckModel _fromJson(Map<String, dynamic> json) {
    final manifest = json['manifest'] is Map
        ? Map<String, dynamic>.from(json['manifest'] as Map)
        : const <String, dynamic>{};
    final owner = json['owner'] is Map
        ? Map<String, dynamic>.from(json['owner'] as Map)
        : const <String, dynamic>{};
    final updatedAt = DateTime.tryParse(
      json['updatedAt']?.toString() ?? json['publishedAt']?.toString() ?? '',
    );
    return MarketDeckModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? manifest['title']?.toString() ?? '',
      author:
          json['author']?.toString() ??
          owner['nickname']?.toString() ??
          owner['username']?.toString() ??
          '',
      description: json['description']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      tags:
          (manifest['tags'] as List?)?.map((value) => '$value').toList() ??
          const [],
      cardCount: (manifest['cardCount'] as num?)?.toInt() ?? 0,
      downloads: (json['downloadCount'] as num?)?.toInt() ?? 0,
      version: (json['version'] ?? manifest['version'] ?? 0).toString(),
      updatedAt: updatedAt ?? DateTime.now(),
      subscribed: false,
    );
  }

  static final _decks = [
    MarketDeckModel(
      id: 'deck-flutter',
      title: 'Flutter 工程实践',
      author: 'KNcard Team',
      description: '覆盖 Flutter Widget、状态管理、路由和本地数据的入门牌组。',
      category: '软件开发',
      tags: ['Flutter', 'Dart', 'Mobile'],
      cardCount: 80,
      downloads: 1240,
      version: '1.2.0',
      updatedAt: DateTime(2026, 7, 28),
      subscribed: true,
    ),
    MarketDeckModel(
      id: 'deck-fsrs',
      title: 'FSRS 复习方法',
      author: 'Learning Lab',
      description: '理解间隔重复、稳定性、难度和复习评分的核心概念。',
      category: '学习方法',
      tags: ['FSRS', 'Spaced repetition'],
      cardCount: 42,
      downloads: 860,
      version: '2.0.1',
      updatedAt: DateTime(2026, 7, 20),
      subscribed: false,
    ),
    MarketDeckModel(
      id: 'deck-product',
      title: '产品设计基础',
      author: 'Product Notes',
      description: '从用户问题、信息架构到验收标准的产品设计速记。',
      category: '产品设计',
      tags: ['Product', 'UX', 'Planning'],
      cardCount: 65,
      downloads: 512,
      version: '1.0.3',
      updatedAt: DateTime(2026, 7, 14),
      subscribed: false,
    ),
  ];
}

class MarketDeckDownload {
  const MarketDeckDownload({required this.bytes, required this.version});

  final Uint8List bytes;
  final int version;
}

class MarketDeckPackage {
  const MarketDeckPackage({
    required this.deckId,
    required this.title,
    required this.version,
    required this.cards,
  });

  final String deckId;
  final String title;
  final int version;
  final List<CardModel> cards;
}

class MarketPackageException implements Exception {
  const MarketPackageException(this.message);

  final String message;

  @override
  String toString() => message;
}
