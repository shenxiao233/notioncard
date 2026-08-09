import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_providers.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/stat_tile.dart';
import '../../core/widgets/status_badge.dart';
import 'market_model.dart';
import 'market_repository.dart';

enum _DownloadState {
  idle,
  downloading,
  validating,
  importing,
  success,
  failure,
}

class DeckDetailPage extends ConsumerWidget {
  const DeckDetailPage({required this.deckId, super.key});

  final String deckId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deck = ref.watch(marketDeckProvider(deckId));
    return Scaffold(
      appBar: AppBar(title: const Text('牌组详情')),
      body: deck.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          title: '牌组加载失败',
          message: '请检查网络连接，稍后重试。',
          icon: Icons.cloud_off_outlined,
          action: FilledButton.icon(
            onPressed: () => ref.invalidate(marketDeckProvider(deckId)),
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ),
        data: (value) => value == null
            ? const EmptyState(
                title: '牌组不存在',
                message: '它可能已经下架，或当前网络暂时无法获取详情。',
                icon: Icons.inventory_2_outlined,
              )
            : _DeckDetails(deck: value, deckId: deckId),
      ),
    );
  }
}

class _DeckDetails extends ConsumerStatefulWidget {
  const _DeckDetails({required this.deck, required this.deckId});

  final MarketDeckModel deck;
  final String deckId;

  @override
  ConsumerState<_DeckDetails> createState() => _DeckDetailsState();
}

class _DeckDetailsState extends ConsumerState<_DeckDetails> {
  _DownloadState _state = _DownloadState.idle;
  String? _message;
  int? _downloadedVersion;
  String? _importedFolder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final deck = widget.deck;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              16,
              8,
              16,
              AppLayoutMetrics.bottomNavigationContentPadding + 24,
            ),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.collections_bookmark_outlined,
                      color: scheme.primary,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          deck.title,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${deck.author} · ${deck.category}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusBadge(
                    label: 'v${deck.version}',
                    icon: Icons.sell_outlined,
                  ),
                  StatusBadge(
                    label:
                        '更新于 ${DateFormat('yyyy年M月d日').format(deck.updatedAt.toLocal())}',
                    icon: Icons.update_outlined,
                  ),
                  if (deck.subscribed)
                    StatusBadge(
                      label: '已订阅',
                      icon: Icons.bookmark_outline,
                      backgroundColor: scheme.primaryContainer,
                      foregroundColor: scheme.onPrimaryContainer,
                    ),
                ],
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final tiles = [
                    StatTile(
                      label: '卡片',
                      value: '${deck.cardCount}',
                      icon: Icons.style_outlined,
                      expand: constraints.maxWidth >= 360,
                    ),
                    StatTile(
                      label: '下载',
                      value: _compactNumber(deck.downloads),
                      icon: Icons.download_outlined,
                      expand: constraints.maxWidth >= 360,
                    ),
                    StatTile(
                      label: '版本',
                      value: deck.version,
                      icon: Icons.history_outlined,
                      expand: constraints.maxWidth >= 360,
                    ),
                  ];
                  if (constraints.maxWidth >= 360) {
                    return Row(
                      children: [
                        tiles[0],
                        const SizedBox(width: 10),
                        tiles[1],
                        const SizedBox(width: 10),
                        tiles[2],
                      ],
                    );
                  }
                  final width = (constraints.maxWidth - 10) / 2;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: tiles
                        .map((tile) => SizedBox(width: width, child: tile))
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 24),
              Text('牌组简介', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Text(
                deck.description,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              if (deck.tags.isNotEmpty) ...[
                const SizedBox(height: 22),
                Text('标签', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: deck.tags
                      .map(
                        (tag) =>
                            StatusBadge(label: tag, icon: Icons.tag_outlined),
                      )
                      .toList(),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 22),
                _DownloadFeedback(state: _state, message: _message!),
              ],
            ],
          ),
        ),
        _DownloadActionBar(
          state: _state,
          subscribed: deck.subscribed,
          downloadedVersion: _downloadedVersion,
          importedFolder: _importedFolder,
          onReview: _importedFolder == null ? null : _reviewImportedDeck,
          onViewCards: _importedFolder == null ? null : _viewImportedCards,
          onDownload: _download,
        ),
      ],
    );
  }

  Future<void> _download() async {
    if (_state == _DownloadState.downloading ||
        _state == _DownloadState.validating ||
        _state == _DownloadState.importing) {
      return;
    }
    final account = ref.read(currentAccountProvider);
    if (account == null) {
      setState(() {
        _state = _DownloadState.failure;
        _message = '请先登录后再导入市场资源';
      });
      return;
    }
    setState(() {
      _state = _DownloadState.downloading;
      _message = '正在下载牌组包...';
      _importedFolder = null;
    });
    try {
      final repository = ref.read(marketRepositoryProvider);
      final download = await repository.downloadDeck(widget.deckId);
      if (!mounted) return;
      setState(() {
        _state = _DownloadState.validating;
        _message = '下载完成，正在校验 ZIP 包...';
      });
      final package = await repository.parseDeckPackage(
        download,
        deckId: widget.deckId,
        fallbackTitle: widget.deck.title,
        accountId: account.id,
      );
      if (!mounted) return;
      setState(() {
        _state = _DownloadState.importing;
        _message = '校验完成，正在导入 ${package.cards.length} 张卡片...';
      });
      final result = await ref
          .read(contentRepositoryProvider)
          .importCards(
            account.id,
            package.cards,
            deckId: package.deckId,
            deckTitle: package.title,
            deckVersion: package.version,
          );
      ref.invalidate(cardsProvider);
      ref.invalidate(pendingSyncProvider);
      if (!mounted) return;
      setState(() {
        _state = _DownloadState.success;
        _downloadedVersion = package.version;
        _importedFolder = package.title;
        _message = result.imported == 0
            ? '牌组已在我的卡牌中，${result.skipped} 张卡片无需重复导入。'
            : '已导入 ${result.imported} 张卡片${result.skipped > 0 ? '，跳过 ${result.skipped} 张重复卡片' : ''}。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _state = _DownloadState.failure;
        _message = '下载失败：${_readableError(error)}';
      });
    }
  }

  String _readableError(Object error) {
    if (error is MarketPackageException) return error.message;
    if (error is ApiException) {
      if (error.isNetworkFailure) return '网络连接不可用，请检查网络后重试';
      if (error.statusCode != null && error.statusCode! >= 500) {
        return '市场服务器暂时不可用，请稍后重试';
      }
      return '市场资源下载失败，请稍后重试';
    }
    final text = error.toString();
    if (text.contains('invalid') || text.contains('ZIP')) {
      return '服务器返回的牌组包无效';
    }
    if (text.contains('missing')) return '牌组包缺少版本信息';
    return '市场资源处理失败，请稍后重试';
  }

  void _reviewImportedDeck() {
    final folder = _importedFolder;
    if (folder == null) return;
    context.push(
      Uri(
        path: '/review/study',
        queryParameters: {'folder': folder},
      ).toString(),
    );
  }

  void _viewImportedCards() {
    final folder = _importedFolder;
    if (folder == null) return;
    context.push('/cards/deck', extra: folder);
  }

  String _compactNumber(int value) {
    if (value >= 10000) return '${(value / 10000).toStringAsFixed(1)}万';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
    return '$value';
  }
}

class _DownloadActionBar extends StatelessWidget {
  const _DownloadActionBar({
    required this.state,
    required this.subscribed,
    required this.downloadedVersion,
    required this.importedFolder,
    required this.onReview,
    required this.onViewCards,
    required this.onDownload,
  });

  final _DownloadState state;
  final bool subscribed;
  final int? downloadedVersion;
  final String? importedFolder;
  final VoidCallback? onReview;
  final VoidCallback? onViewCards;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final busy =
        state == _DownloadState.downloading ||
        state == _DownloadState.validating ||
        state == _DownloadState.importing;
    final completed = state == _DownloadState.success;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            children: [
              if (busy) ...[
                LinearProgressIndicator(
                  minHeight: 4,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 8),
              ],
              if (completed && importedFolder != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onReview,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('立即复习'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onViewCards,
                        icon: const Icon(Icons.style_outlined),
                        label: const Text('查看卡牌'),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: Text('重新导入 v$downloadedVersion'),
                ),
              ] else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: busy ? null : onDownload,
                    icon: Icon(
                      state == _DownloadState.failure
                          ? Icons.refresh
                          : subscribed
                          ? Icons.check
                          : Icons.download_outlined,
                    ),
                    label: Text(
                      busy
                          ? switch (state) {
                              _DownloadState.validating => '校验中...',
                              _DownloadState.importing => '导入中...',
                              _ => '下载中...',
                            }
                          : state == _DownloadState.failure
                          ? '重新下载'
                          : subscribed
                          ? '已订阅，下载并导入'
                          : '下载并导入牌组',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadFeedback extends StatelessWidget {
  const _DownloadFeedback({required this.state, required this.message});

  final _DownloadState state;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final success = state == _DownloadState.success;
    final color = state == _DownloadState.failure
        ? scheme.error
        : scheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (state == _DownloadState.failure
            ? scheme.errorContainer
            : scheme.primaryContainer),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            success
                ? Icons.check_circle_outline
                : state == _DownloadState.failure
                ? Icons.error_outline
                : state == _DownloadState.importing
                ? Icons.file_download_done_outlined
                : Icons.sync,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
