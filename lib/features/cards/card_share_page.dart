import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/card_model.dart';
import '../../core/widgets/app_visuals.dart';
import '../../core/widgets/markdown_content.dart';

class CardSharePage extends StatefulWidget {
  const CardSharePage({required this.card, super.key});

  final CardModel card;

  @override
  State<CardSharePage> createState() => _CardSharePageState();
}

class _CardSharePageState extends State<CardSharePage> {
  final _captureKey = GlobalKey();
  bool _showAnswer = true;
  bool _showExplanation = true;
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;

    setState(() => _sharing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 250));

      final renderObject = _captureKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        throw StateError('分享图片尚未准备完成');
      }

      final image = await renderObject.toImage(pixelRatio: 2);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) throw StateError('无法生成分享图片');

      final directory = await getTemporaryDirectory();
      final safeId = widget.card.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final file = File('${directory.path}/kncard-card-$safeId.png');
      await file.writeAsBytes(
        byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
        flush: true,
      );

      await Share.shareXFiles([XFile(file.path)], subject: '分享题目');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('分享失败：$error')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppVisualColors.background,
      appBar: AppBar(
        title: const Text(
          '分享题目',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: '分享长图',
            onPressed: _sharing ? null : _share,
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = (constraints.maxWidth - 32).clamp(0.0, 520.0);
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Center(
                    child: RepaintBoundary(
                      key: _captureKey,
                      child: SizedBox(
                        width: width,
                        child: _CardShareImage(
                          card: widget.card,
                          showAnswer: _showAnswer,
                          showExplanation: _showExplanation,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppVisualColors.line)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('显示答案')),
                      Switch.adaptive(
                        value: _showAnswer,
                        onChanged: _sharing
                            ? null
                            : (value) => setState(() => _showAnswer = value),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Expanded(child: Text('显示解析')),
                      Switch.adaptive(
                        value: _showExplanation,
                        onChanged: _sharing
                            ? null
                            : (value) =>
                                  setState(() => _showExplanation = value),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _sharing ? null : _share,
                      icon: _sharing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.share_outlined),
                      label: Text(_sharing ? '正在生成长图…' : '分享长图'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardShareImage extends StatelessWidget {
  const _CardShareImage({
    required this.card,
    required this.showAnswer,
    required this.showExplanation,
  });

  final CardModel card;
  final bool showAnswer;
  final bool showExplanation;

  bool get _hasQuestion => card.question.trim().isNotEmpty;
  bool get _hasContent =>
      card.type == CardType.note && card.content.trim().isNotEmpty;
  bool get _hasOptions => card.type != CardType.note && card.options.isNotEmpty;
  bool get _hasQuestionSection => _hasQuestion || _hasContent || _hasOptions;
  bool get _hasMeta => card.tags.isNotEmpty || card.source.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppVisualColors.background,
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hasQuestionSection)
            _ShareQuestionSection(card: card, showAnswer: showAnswer),
          if (showExplanation && card.explanation.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _ShareExplanationSection(explanation: card.explanation),
          ],
          if (_hasMeta) ...[
            const SizedBox(height: 14),
            _ShareMetaSection(card: card),
          ],
        ],
      ),
    );
  }
}

class _ShareQuestionSection extends StatelessWidget {
  const _ShareQuestionSection({required this.card, required this.showAnswer});

  final CardModel card;
  final bool showAnswer;

  @override
  Widget build(BuildContext context) {
    final question = card.question.trim();
    final content = card.content.trim();
    final showContent = card.type == CardType.note && content.isNotEmpty;
    final showOptions = card.type != CardType.note && card.options.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppVisualColors.line),
        boxShadow: appCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '题目',
                  style: TextStyle(
                    color: AppVisualColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _ShareBadge(label: card.type.label),
            ],
          ),
          if (question.isNotEmpty) ...[
            const SizedBox(height: 10),
            MarkdownContent(
              data: card.question,
              selectable: false,
              textStyle: _shareBodyStyle,
            ),
          ],
          if (showContent) ...[
            const Divider(height: 22),
            const Text('内容', style: _shareSectionLabelStyle),
            const SizedBox(height: 5),
            MarkdownContent(
              data: card.content,
              selectable: false,
              noteEntries: true,
              textStyle: _shareSecondaryBodyStyle,
            ),
          ],
          if (showOptions) ...[
            const SizedBox(height: 6),
            ...card.options.entries.map(
              (entry) => _ShareAnswerOption(
                label: entry.key,
                value: entry.value,
                correct: showAnswer && card.answer.contains(entry.key),
              ),
            ),
            if (showAnswer && card.answer.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '答案：${card.answer.join('、')}',
                style: const TextStyle(
                  color: AppVisualColors.darkGreen,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ShareAnswerOption extends StatelessWidget {
  const _ShareAnswerOption({
    required this.label,
    required this.value,
    required this.correct,
  });

  final String label;
  final String value;
  final bool correct;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: correct ? const Color(0xfff4fbf8) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: correct ? const Color(0xff168d76) : AppVisualColors.line,
          width: correct ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                label,
                style: TextStyle(
                  color: correct
                      ? const Color(0xff168d76)
                      : AppVisualColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: MarkdownContent(
              data: value,
              selectable: false,
              textStyle: _shareSecondaryBodyStyle.copyWith(height: 1.35),
            ),
          ),
          if (correct) ...[
            const SizedBox(width: 8),
            const Icon(Icons.check_rounded, color: Color(0xff168d76), size: 20),
          ],
        ],
      ),
    );
  }
}

class _ShareExplanationSection extends StatelessWidget {
  const _ShareExplanationSection({required this.explanation});

  final String explanation;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppVisualColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('解析', style: _shareTitleStyle),
          const SizedBox(height: 8),
          MarkdownContent(
            data: explanation,
            selectable: false,
            textStyle: _shareSecondaryBodyStyle,
          ),
        ],
      ),
    );
  }
}

class _ShareMetaSection extends StatelessWidget {
  const _ShareMetaSection({required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context) {
    final source = card.source.trim();
    final hasTags = card.tags.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppVisualColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasTags) ...[
            const Text('知识点', style: _shareTitleStyle),
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: card.tags.map((tag) => _ShareTag(label: tag)).toList(),
            ),
          ],
          if (source.isNotEmpty) ...[
            if (hasTags)
              const Padding(
                padding: EdgeInsets.only(top: 13),
                child: Divider(height: 1),
              ),
            const SizedBox(height: 9),
            Text(
              '来源：$source',
              style: const TextStyle(
                color: AppVisualColors.muted,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShareBadge extends StatelessWidget {
  const _ShareBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xfff1f2f1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppVisualColors.ink,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ShareTag extends StatelessWidget {
  const _ShareTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xffeef7f0),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppVisualColors.darkGreen,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

const _shareBodyStyle = TextStyle(
  color: AppVisualColors.ink,
  fontSize: 15,
  height: 1.5,
);

const _shareSecondaryBodyStyle = TextStyle(
  color: AppVisualColors.ink,
  fontSize: 14,
  height: 1.45,
);

const _shareTitleStyle = TextStyle(
  color: AppVisualColors.ink,
  fontSize: 16,
  fontWeight: FontWeight.w700,
);

const _shareSectionLabelStyle = TextStyle(
  color: AppVisualColors.ink,
  fontSize: 15,
  fontWeight: FontWeight.w700,
);
