import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/cache/avatar_cache.dart';
import '../../core/models/account_model.dart';
import '../../core/network/api_config.dart';

class AccountAvatar extends StatefulWidget {
  const AccountAvatar({
    required this.account,
    this.size = 70,
    this.borderWidth = 2,
    super.key,
  });

  final AccountModel? account;
  final double size;
  final double borderWidth;

  @override
  State<AccountAvatar> createState() => _AccountAvatarState();
}

class _AccountAvatarState extends State<AccountAvatar> {
  ImageProvider<Object>? _visibleImage;
  String? _visibleAvatar;
  ImageProvider<Object>? _pendingImage;
  String? _pendingAvatar;
  int _imageGeneration = 0;
  int _imageToken = 0;

  @override
  void initState() {
    super.initState();
    final avatar = _normalizedAvatar(widget.account);
    _visibleAvatar = avatar;
    _visibleImage = _inlineAvatarImage(avatar);
    if (avatar != null && _visibleImage == null) {
      unawaited(_loadRemoteAvatar(avatar));
    }
  }

  @override
  void didUpdateWidget(covariant AccountAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldAccount = oldWidget.account;
    final account = widget.account;

    if (oldAccount?.id != account?.id) {
      _imageGeneration++;
      _imageToken++;
      final avatar = _normalizedAvatar(account);
      setState(() {
        _visibleAvatar = null;
        _visibleImage = null;
        _pendingAvatar = avatar;
        _pendingImage = _inlineAvatarImage(avatar);
      });
      if (avatar != null && _pendingImage == null) {
        unawaited(_loadRemoteAvatar(avatar));
      }
      return;
    }

    final avatar = _normalizedAvatar(account);
    if (avatar == _visibleAvatar || avatar == _pendingAvatar) return;

    if (avatar == null) {
      _imageToken++;
      setState(() {
        _visibleAvatar = null;
        _visibleImage = null;
        _pendingAvatar = null;
        _pendingImage = null;
      });
      return;
    }

    _imageToken++;
    final inlineImage = _inlineAvatarImage(avatar);
    setState(() {
      _pendingAvatar = avatar;
      _pendingImage = inlineImage;
    });
    if (inlineImage == null) unawaited(_loadRemoteAvatar(avatar));
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(widget.borderWidth),
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _fallback(widget.account),
            if (_visibleImage != null)
              Image(
                key: ValueKey('visible-$_imageToken'),
                image: _visibleImage!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            if (_pendingImage != null)
              _pendingImageWidget(_pendingImage!, _pendingAvatar!),
          ],
        ),
      ),
    );
  }

  Widget _pendingImageWidget(ImageProvider<Object> image, String avatar) =>
      Image(
        key: ValueKey('pending-$_imageToken'),
        image: image,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          final ready = frame != null || wasSynchronouslyLoaded;
          if (ready) _schedulePromote(image, avatar);
          return AnimatedOpacity(
            opacity: ready ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: child,
          );
        },
        errorBuilder: (context, error, stackTrace) {
          _scheduleReject(image, avatar);
          return const SizedBox.shrink();
        },
      );

  void _schedulePromote(ImageProvider<Object> image, String avatar) {
    final generation = _imageGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _imageGeneration ||
          _pendingAvatar != avatar ||
          !identical(_pendingImage, image)) {
        return;
      }
      setState(() {
        _visibleAvatar = avatar;
        _visibleImage = image;
        _pendingAvatar = null;
        _pendingImage = null;
      });
    });
  }

  void _scheduleReject(ImageProvider<Object> image, String avatar) {
    final generation = _imageGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _imageGeneration ||
          _pendingAvatar != avatar ||
          !identical(_pendingImage, image)) {
        return;
      }
      setState(() {
        _pendingAvatar = null;
        _pendingImage = null;
      });
    });
  }

  String? _normalizedAvatar(AccountModel? account) => account?.avatar?.trim();

  Widget _fallback(AccountModel? account) => Container(
    color: const Color(0xffeff8ef),
    alignment: Alignment.center,
    child: Text(
      account == null ? '?' : _initial(account),
      style: TextStyle(
        color: const Color(0xff187c2d),
        fontSize: widget.size * 0.31,
        fontWeight: FontWeight.w800,
        height: 1,
      ),
    ),
  );

  ImageProvider<Object>? _inlineAvatarImage(String? source) {
    if (source == null || source.isEmpty) return null;
    if (source.startsWith('data:image/')) {
      final comma = source.indexOf(',');
      if (comma < 0) return null;
      try {
        return MemoryImage(base64Decode(source.substring(comma + 1)));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> _loadRemoteAvatar(String source) async {
    final generation = _imageGeneration;
    final resolved = _resolvedAvatarUrl(source);
    if (resolved == null) return;

    final bytes = await loadOrFetchAvatar(resolved);
    final ImageProvider<Object> image = bytes == null || bytes.isEmpty
        ? NetworkImage(resolved)
        : MemoryImage(bytes);
    if (!mounted || generation != _imageGeneration) return;
    if (_pendingAvatar != source && _visibleAvatar != source) return;

    setState(() {
      _pendingAvatar = source;
      _pendingImage = image;
    });
  }

  String? _resolvedAvatarUrl(String source) {
    final uri = Uri.tryParse(source);
    if (uri == null) return null;
    if (uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return uri.toString();
    }
    final base = Uri.tryParse(ApiConfig.defaultBaseUrl);
    final resolved = base?.resolve(source);
    return resolved?.toString();
  }

  String _initial(AccountModel value) {
    final name = value.nickname.trim().isNotEmpty
        ? value.nickname.trim()
        : value.username.trim();
    return name.isEmpty
        ? '?'
        : String.fromCharCode(name.runes.first).toUpperCase();
  }
}
