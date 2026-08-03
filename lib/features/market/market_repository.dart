import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'market_model.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class MarketRepository {
  MarketRepository({this.apiClient});

  final ApiClient? apiClient;

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
