import 'dart:typed_data';

import 'avatar_cache_stub.dart'
    if (dart.library.io) 'avatar_cache_io.dart'
    as implementation;

/// Loads an avatar from a persistent cache and fetches it on a cache miss.
///
/// The web implementation intentionally falls back to the normal image
/// provider because browser storage has different lifecycle and quota rules.
Future<Uint8List?> loadOrFetchAvatar(String url) =>
    implementation.loadOrFetchAvatar(url);
