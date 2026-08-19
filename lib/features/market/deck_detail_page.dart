import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_providers.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/app_visuals.dart';
import '../../core/widgets/empty_state.dart';
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
      backgroundColor: AppVisualColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _DeckDetailHeader(),
            Expanded(
              child: deck.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: AppVisualColors.green,
                  ),
                ),
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
            ),
          ],
        ),
      ),
    );
  }
}

class _DeckDetailHeader extends StatelessWidget {
  const _DeckDetailHeader();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 6, 16, 10),
    child: Row(
      children: [
        IconButton(
          tooltip: '返回资源市场',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
        ),
        const SizedBox(width: 4),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '资源市场',
                style: TextStyle(
                  color: AppVisualColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '牌组详情',
                style: TextStyle(
                  color: AppVisualColors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            color: AppVisualColors.softGreen,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.collections_bookmark_rounded,
            color: AppVisualColors.darkGreen,
            size: 20,
          ),
        ),
      ],
    ),
  );
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
    final deck = widget.deck;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
            children: [
              _DeckHeroCard(deck: deck),
              const SizedBox(height: 16),
              _DeckStatsCard(deck: deck),
              const SizedBox(height: 16),
              _DeckInfoCard(
                title: '牌组简介',
                icon: Icons.subject_rounded,
                child: Text(
                  deck.description.trim().isEmpty ? '暂无简介' : deck.description,
                  style: const TextStyle(
                    color: AppVisualColors.ink,
                    fontSize: 14,
                    height: 1.65,
                  ),
                ),
              ),
              if (deck.tags.isNotEmpty) ...[
                const SizedBox(height: 16),
                _DeckInfoCard(
                  title: '标签',
                  icon: Icons.sell_outlined,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: deck.tags
                        .map((tag) => _DeckTag(label: tag))
                        .toList(),
                  ),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 16),
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
            restoreDeleted: true,
          );
      ref.invalidate(cardsProvider);
      ref.invalidate(pendingSyncProvider);
      ref
          .read(syncControllerProvider.notifier)
          .scheduleSync(reason: 'deck-import');
      if (!mounted) return;
      setState(() {
        _state = _DownloadState.success;
        _downloadedVersion = package.version;
        _importedFolder = package.title;
        _message = result.imported == 0 && result.updated == 0
            ? '牌组已在我的卡牌中，${result.skipped} 张卡片无需重复导入。'
            : '已导入 ${result.imported} 张卡片'
                  '${result.updated > 0 ? '，修复 ${result.updated} 张卡片的原始顺序' : ''}'
                  '${result.skipped > 0 ? '，跳过 ${result.skipped} 张重复卡片' : ''}。';
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
}

class _DeckHeroCard extends StatelessWidget {
  const _DeckHeroCard({required this.deck});

  final MarketDeckModel deck;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xffe9f7e8), Colors.white],
      ),
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: const Color(0xffdceedd)),
      boxShadow: appCardShadow,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 70,
              height: 70,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppVisualColors.green,
                borderRadius: BorderRadius.circular(23),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x24159515),
                    blurRadius: 16,
                    offset: Offset(0, 7),
                  ),
                ],
              ),
              child: const Icon(
                Icons.collections_bookmark_rounded,
                color: Colors.white,
                size: 34,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deck.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppVisualColors.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${deck.author} · ${deck.category}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppVisualColors.muted,
                      fontSize: 13,
                    ),
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
            _DeckPill(icon: Icons.sell_outlined, label: '版本 ${deck.version}'),
            _DeckPill(
              icon: Icons.update_outlined,
              label:
                  '更新于 ${DateFormat('yyyy年M月d日').format(deck.updatedAt.toLocal())}',
            ),
            if (deck.subscribed)
              const _DeckPill(
                icon: Icons.bookmark_rounded,
                label: '已订阅',
                active: true,
              ),
          ],
        ),
      ],
    ),
  );
}

class _DeckStatsCard extends StatelessWidget {
  const _DeckStatsCard({required this.deck});

  final MarketDeckModel deck;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      boxShadow: appCardShadow,
    ),
    child: Row(
      children: [
        Expanded(
          child: _DeckStat(
            icon: Icons.style_outlined,
            value: deck.cardCount.toString(),
            label: '张卡片',
          ),
        ),
        const _DeckStatDivider(),
        Expanded(
          child: _DeckStat(
            icon: Icons.download_outlined,
            value: _compactNumber(deck.downloads),
            label: '次下载',
          ),
        ),
        const _DeckStatDivider(),
        Expanded(
          child: _DeckStat(
            icon: Icons.history_rounded,
            value: deck.version,
            label: '当前版本',
          ),
        ),
      ],
    ),
  );

  String _compactNumber(int value) {
    if (value >= 10000) {
      return '${(value / 10000).toStringAsFixed(1)}万';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return value.toString();
  }
}

class _DeckStat extends StatelessWidget {
  const _DeckStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, color: AppVisualColors.green, size: 19),
      const SizedBox(height: 7),
      Text(
        value,
        style: const TextStyle(
          color: AppVisualColors.ink,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: const TextStyle(color: AppVisualColors.muted, fontSize: 11),
      ),
    ],
  );
}

class _DeckStatDivider extends StatelessWidget {
  const _DeckStatDivider();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 48,
    child: VerticalDivider(width: 1, color: AppVisualColors.line),
  );
}

class _DeckInfoCard extends StatelessWidget {
  const _DeckInfoCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 15, 16, 17),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      boxShadow: appCardShadow,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppVisualColors.green, size: 19),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: AppVisualColors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _DeckPill extends StatelessWidget {
  const _DeckPill({
    required this.icon,
    required this.label,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: active ? AppVisualColors.green : Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: active ? AppVisualColors.green : AppVisualColors.line,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: active ? Colors.white : AppVisualColors.darkGreen,
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : AppVisualColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _DeckTag extends StatelessWidget {
  const _DeckTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: AppVisualColors.softGreen,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: AppVisualColors.darkGreen,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
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
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, -5),
          ),
        ],
        border: Border(top: BorderSide(color: AppVisualColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            children: [
              if (busy) ...[
                LinearProgressIndicator(
                  minHeight: 4,
                  color: AppVisualColors.green,
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
