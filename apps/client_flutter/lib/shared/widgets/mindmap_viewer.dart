import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/artifact_model.dart';
import '../models/transcript_model.dart';

class MindmapViewer extends StatefulWidget {
  const MindmapViewer({
    super.key,
    required this.artifact,
    required this.transcript,
    required this.transcriptSegments,
    this.emptyMessage = 'Ainda sem mapa mental. Rode o processamento para gerar.',
  });

  final ArtifactModel? artifact;
  final TranscriptModel? transcript;
  final List<TranscriptSegmentModel> transcriptSegments;
  final String emptyMessage;

  @override
  State<MindmapViewer> createState() => _MindmapViewerState();
}

class _MindmapViewerState extends State<MindmapViewer> {
  static const String _rootId = 'root';
  static const List<Color> _branchPalette = <Color>[
    Color(0xFFFF8A3D),
    Color(0xFFB45CFF),
    Color(0xFF8DE212),
    Color(0xFF3F82FF),
    Color(0xFFFF4E59),
    Color(0xFF19D1C3),
  ];

  final TransformationController _transformationController =
      TransformationController();
  Set<String> _expandedIds = <String>{_rootId};

  _MindmapData? _data;
  _MindmapLayout? _fromLayout;
  _MindmapLayout? _toLayout;
  int _animationSeed = 0;

  @override
  void initState() {
    super.initState();
    _resetMindmap();
  }

  @override
  void didUpdateWidget(covariant MindmapViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedArtifact = oldWidget.artifact?.id != widget.artifact?.id ||
        oldWidget.artifact?.version != widget.artifact?.version;
    if (changedArtifact) {
      _resetMindmap();
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final fromLayout = _fromLayout;
    final toLayout = _toLayout;
    if (data == null || fromLayout == null || toLayout == null) {
      return _buildEmptyState(widget.emptyMessage);
    }

    return Container(
      width: double.infinity,
      height: 600,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF030406),
            Color(0xFF090A0F),
            Color(0xFF11141C),
          ],
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: <Widget>[
            const Positioned.fill(child: _MindmapBackdrop()),
            TweenAnimationBuilder<double>(
              key: ValueKey(_animationSeed),
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeInOutCubic,
              builder: (context, progress, _) {
                final frame = _InterpolatedLayoutFrame.build(
                  from: fromLayout,
                  to: toLayout,
                  t: progress,
                );
                return Positioned.fill(
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    boundaryMargin: const EdgeInsets.all(180),
                    constrained: false,
                    minScale: 0.62,
                    maxScale: 2.3,
                    child: SizedBox(
                      width: frame.canvasSize.width,
                      height: frame.canvasSize.height,
                      child: Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _MindmapPainter(
                                segments: frame.segments,
                              ),
                            ),
                          ),
                          ...frame.placements.values.map(
                            (placement) => _buildLabel(frame, placement),
                          ),
                          ...toLayout.placements.values
                              .where((placement) => placement.hasChildren)
                              .map(
                                (placement) => _buildToggleNode(
                                  frame.placements[placement.id] ??
                                      _AnimatedNodePlacement.fromStatic(
                                        placement,
                                        opacity: 1,
                                      ),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const <Widget>[
                  _HintPill(text: 'Clique nos círculos para expandir'),
                  _HintPill(text: 'Clique no texto para abrir trecho relacionado'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF0C0E13),
            Color(0xFF151821),
          ],
        ),
      ),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFE6EAEE),
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(
    _InterpolatedLayoutFrame frame,
    _AnimatedNodePlacement placement,
  ) {
    final width = placement.depth == 0
        ? 220.0
        : placement.depth == 1
            ? 228.0
            : 192.0;
    final left = placement.depth == 0
        ? placement.anchor.dx - 268
        : placement.labelCenter.dx - (width / 2);
    final top = placement.depth == 0
        ? placement.anchor.dy - 34
        : placement.anchor.dy - 48;
    final canInspect = placement.opacity > 0.98;

    final child = AnimatedOpacity(
      opacity: placement.opacity,
      duration: const Duration(milliseconds: 140),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: canInspect ? () => _openTranscriptInsight(placement) : null,
          child: Container(
            padding: placement.depth == 0
                ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: placement.depth == 0
                  ? Colors.transparent
                  : const Color(0x12000000),
              borderRadius: BorderRadius.circular(18),
              border: placement.depth == 0
                  ? null
                  : Border.all(color: const Color(0x14FFFFFF)),
              boxShadow: placement.depth == 0
                  ? const <BoxShadow>[]
                  : <BoxShadow>[
                      BoxShadow(
                        color: placement.color.withValues(alpha: 0.08),
                        blurRadius: 20,
                        spreadRadius: 0.5,
                      ),
                    ],
            ),
            child: Text(
              placement.label,
              textAlign:
                  placement.depth == 0 ? TextAlign.right : TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: placement.depth == 0 ? 18 : 14,
                height: 1.35,
                fontWeight:
                    placement.depth <= 1 ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );

    return Positioned(
      left: left,
      top: top,
      width: width,
      child: child,
    );
  }

  Widget _buildToggleNode(_AnimatedNodePlacement placement) {
    final targetExpanded = _expandedIds.contains(placement.id);
    final badgeSize = placement.id == _rootId ? 24.0 : 26.0;
    final label = targetExpanded ? '−' : placement.childCount.toString();

    return Positioned(
      left: placement.anchor.dx - badgeSize / 2,
      top: placement.anchor.dy - badgeSize / 2,
      width: badgeSize,
      height: badgeSize,
      child: IgnorePointer(
        ignoring: placement.opacity < 0.98,
        child: Opacity(
          opacity: placement.opacity,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _toggleNode(placement.id),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: targetExpanded
                      ? const Color(0xFF090D16)
                      : placement.color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: placement.color,
                    width: targetExpanded ? 2 : 0,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: placement.color.withValues(alpha: 0.32),
                      blurRadius: targetExpanded ? 20 : 14,
                      spreadRadius: targetExpanded ? 1.2 : 0.2,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: placement.id == _rootId ? 14 : 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _resetMindmap() {
    _expandedIds = <String>{_rootId};
    _transformationController.value = Matrix4.identity();
    final parsed = _MindmapData.tryParse(widget.artifact?.contentJson);
    final layout = parsed == null
        ? null
        : _MindmapLayoutEngine(
            expandedIds: _expandedIds,
            palette: _branchPalette,
          ).build(parsed);

    setState(() {
      _data = parsed;
      _fromLayout = layout;
      _toLayout = layout;
      _animationSeed++;
    });
  }

  void _toggleNode(String nodeId) {
    final data = _data;
    final oldLayout = _toLayout;
    if (data == null || oldLayout == null) {
      return;
    }

    final nextExpandedIds = Set<String>.from(_expandedIds);
    if (nextExpandedIds.contains(nodeId)) {
      if (nodeId != _rootId) {
        nextExpandedIds.removeWhere(
          (item) => item == nodeId || item.startsWith('$nodeId/'),
        );
      }
    } else {
      nextExpandedIds.add(nodeId);
    }

    final nextLayout = _MindmapLayoutEngine(
      expandedIds: nextExpandedIds,
      palette: _branchPalette,
    ).build(data);

    setState(() {
      _expandedIds = nextExpandedIds;
      _fromLayout = oldLayout;
      _toLayout = nextLayout;
      _animationSeed++;
    });
  }

  Future<void> _openTranscriptInsight(_AnimatedNodePlacement placement) async {
    final insight = _buildInsight(placement.label);
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 520),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xFF0A0D12),
                  Color(0xFF101621),
                  Color(0xFF161E2B),
                ],
              ),
              border: Border.all(color: const Color(0x22FFFFFF)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x44000000),
                  blurRadius: 28,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 52,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0x44FFFFFF),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: placement.color.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: placement.color.withValues(alpha: 0.55)),
                        ),
                        child: Text(
                          placement.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (insight.timeRange != null)
                        _MetaPill(label: insight.timeRange!),
                      _MetaPill(
                        label: insight.isApproximate
                            ? 'correspondência aproximada'
                            : 'correspondência direta',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    insight.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    insight.subtitle,
                    style: const TextStyle(
                      color: Color(0xFFB9C2CE),
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0x6610141D),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0x19FFFFFF)),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          insight.content,
                          style: const TextStyle(
                            color: Color(0xFFF0F3F7),
                            fontSize: 15,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  _TranscriptInsight _buildInsight(String label) {
    final segments = widget.transcriptSegments;
    final transcript = widget.transcript;

    final keywords = _keywords(label);
    TranscriptSegmentModel? bestSegment;
    double bestScore = 0;

    for (final segment in segments) {
      final score = _scoreSegment(segment.text, label, keywords);
      if (score > bestScore) {
        bestScore = score;
        bestSegment = segment;
      }
    }

    if (bestSegment != null && bestScore > 0) {
      return _TranscriptInsight(
        title: 'Trecho relacionado da transcrição',
        subtitle:
            'Trecho mais provável encontrado para este nó do mapa mental.',
        content: bestSegment.text.trim(),
        timeRange: _formatRange(bestSegment.startMs, bestSegment.endMs),
        isApproximate: bestScore < 6,
      );
    }

    final transcriptText = transcript?.fullText.trim() ?? '';
    if (transcriptText.isNotEmpty) {
      final excerpt = _findExcerpt(transcriptText, label, keywords);
      return _TranscriptInsight(
        title: 'Trecho aproximado do conteúdo',
        subtitle:
            'Não houve correspondência forte por segmento, então este trecho foi extraído por proximidade textual.',
        content: excerpt,
        timeRange: null,
        isApproximate: true,
      );
    }

    return _TranscriptInsight(
      title: 'Sem trecho relacionado',
      subtitle:
          'Ainda não há transcrição suficiente para relacionar este nó a um trecho específico.',
      content: 'Processe a gravação para gerar transcrição com segmentos.',
      timeRange: null,
      isApproximate: true,
    );
  }

  Set<String> _keywords(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9áàâãéèêíïóôõöúçñ ]'), ' ')
        .split(RegExp(r'\s+'))
        .map((item) => item.trim())
        .where((item) => item.length >= 3)
        .toSet();
  }

  double _scoreSegment(String text, String label, Set<String> keywords) {
    final normalizedText = text.toLowerCase();
    final normalizedLabel = label.toLowerCase();
    double score = 0;

    if (normalizedText.contains(normalizedLabel)) {
      score += 10;
    }

    for (final keyword in keywords) {
      if (normalizedText.contains(keyword)) {
        score += keyword.length >= 6 ? 2.4 : 1.5;
      }
    }

    return score;
  }

  String _findExcerpt(String fullText, String label, Set<String> keywords) {
    final lower = fullText.toLowerCase();
    var index = lower.indexOf(label.toLowerCase());
    if (index < 0) {
      for (final keyword in keywords) {
        index = lower.indexOf(keyword);
        if (index >= 0) {
          break;
        }
      }
    }

    if (index < 0) {
      final cutoff = math.min(fullText.length, 420);
      return '${fullText.substring(0, cutoff)}${cutoff < fullText.length ? '…' : ''}';
    }

    final start = math.max(0, index - 140);
    final end = math.min(fullText.length, index + 260);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < fullText.length ? '…' : '';
    return '$prefix${fullText.substring(start, end).trim()}$suffix';
  }

  String _formatRange(int startMs, int endMs) {
    return '${_formatMs(startMs)} - ${_formatMs(endMs)}';
  }

  String _formatMs(int value) {
    final totalSeconds = math.max(0, value ~/ 1000);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _HintPill extends StatelessWidget {
  const _HintPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xAA090B10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xCCF3F5F7),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFEAEFF6),
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MindmapBackdrop extends StatelessWidget {
  const _MindmapBackdrop();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MindmapBackdropPainter(),
    );
  }
}

class _MindmapBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final glowPaint = Paint()
      ..shader = const RadialGradient(
        colors: <Color>[
          Color(0x221A3A8E),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.58, size.height * 0.48),
          radius: math.max(size.width, size.height) * 0.5,
        ),
      );

    canvas.drawRect(Offset.zero & size, glowPaint);

    final gridPaint = Paint()
      ..color = const Color(0x10FFFFFF)
      ..strokeWidth = 1;

    const step = 56.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MindmapPainter extends CustomPainter {
  const _MindmapPainter({
    required this.segments,
  });

  final List<_AnimatedBranchSegment> segments;

  @override
  void paint(Canvas canvas, Size size) {
    for (final segment in segments) {
      if (segment.opacity <= 0.01) {
        continue;
      }

      final path = Path()
        ..moveTo(segment.start.dx, segment.start.dy)
        ..cubicTo(
          segment.controlStart.dx,
          segment.controlStart.dy,
          segment.controlEnd.dx,
          segment.controlEnd.dy,
          segment.end.dx,
          segment.end.dy,
        );

      final glowPaint = Paint()
        ..color = segment.color.withValues(alpha: 0.18 * segment.opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      final linePaint = Paint()
        ..color = segment.color.withValues(alpha: segment.opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MindmapPainter oldDelegate) {
    return oldDelegate.segments != segments;
  }
}

class _MindmapLayoutEngine {
  _MindmapLayoutEngine({
    required this.expandedIds,
    required this.palette,
  });

  final Set<String> expandedIds;
  final List<Color> palette;

  static const double _horizontalGap = 280;
  static const double _verticalGap = 132;
  static const double _topPadding = 120;
  static const double _leftPadding = 320;

  final Map<String, _NodePlacement> _placements = <String, _NodePlacement>{};
  int _leafIndex = 0;
  int _maxDepth = 0;

  _MindmapLayout build(_MindmapData data) {
    _placements.clear();
    _leafIndex = 0;
    _maxDepth = 0;

    _layoutNode(
      node: data.root,
      id: 'root',
      parentId: null,
      depth: 0,
      color: const Color(0xFF456BFF),
      forceExpanded: true,
    );

    final width = _leftPadding + ((_maxDepth + 1) * _horizontalGap) + 300;
    final height = math.max(
      500.0,
      (_leafIndex * _verticalGap) + (_topPadding * 1.3),
    );

    return _MindmapLayout(
      canvasSize: Size(width, height),
      placements: Map<String, _NodePlacement>.unmodifiable(_placements),
    );
  }

  _NodePlacement _layoutNode({
    required _MindmapNode node,
    required String id,
    required String? parentId,
    required int depth,
    required Color color,
    bool forceExpanded = false,
  }) {
    _maxDepth = math.max(_maxDepth, depth);

    final hasChildren = node.children.isNotEmpty;
    final isExpanded = forceExpanded || expandedIds.contains(id);
    final childPlacements = <_NodePlacement>[];

    if (hasChildren && isExpanded) {
      for (var index = 0; index < node.children.length; index++) {
        final child = node.children[index];
        final childColor = depth == 0 ? palette[index % palette.length] : color;
        childPlacements.add(
          _layoutNode(
            node: child,
            id: '$id/$index',
            parentId: id,
            depth: depth + 1,
            color: childColor,
          ),
        );
      }
    }

    final x = _leftPadding + (depth * _horizontalGap);
    final y = childPlacements.isEmpty
        ? _topPadding + (_leafIndex++ * _verticalGap)
        : (childPlacements.first.anchor.dy + childPlacements.last.anchor.dy) /
            2;

    final placement = _NodePlacement(
      id: id,
      parentId: parentId,
      label: node.label,
      depth: depth,
      anchor: Offset(x, y),
      color: color,
      hasChildren: hasChildren,
      childCount: node.children.length,
      isExpanded: isExpanded,
    );

    _placements[id] = placement;
    return placement;
  }
}

class _InterpolatedLayoutFrame {
  const _InterpolatedLayoutFrame({
    required this.canvasSize,
    required this.placements,
    required this.segments,
  });

  final Size canvasSize;
  final Map<String, _AnimatedNodePlacement> placements;
  final List<_AnimatedBranchSegment> segments;

  static _InterpolatedLayoutFrame build({
    required _MindmapLayout from,
    required _MindmapLayout to,
    required double t,
  }) {
    final nodeIds = <String>{
      ...from.placements.keys,
      ...to.placements.keys,
    };

    final placements = <String, _AnimatedNodePlacement>{};
    for (final id in nodeIds) {
      final fromPlacement = from.placements[id];
      final toPlacement = to.placements[id];
      final meta = toPlacement ?? fromPlacement;
      if (meta == null) {
        continue;
      }

      final startAnchor = fromPlacement?.anchor ??
          _fallbackAnchor(id: id, primary: from, secondary: to);
      final endAnchor =
          toPlacement?.anchor ?? _fallbackAnchor(id: id, primary: to, secondary: from);

      final startOpacity = fromPlacement != null ? 1.0 : 0.0;
      final endOpacity = toPlacement != null ? 1.0 : 0.0;

      placements[id] = _AnimatedNodePlacement(
        id: id,
        parentId: meta.parentId,
        label: meta.label,
        depth: meta.depth,
        anchor: Offset.lerp(startAnchor, endAnchor, t) ?? endAnchor,
        color: meta.color,
        hasChildren: meta.hasChildren,
        childCount: meta.childCount,
        isExpanded: toPlacement?.isExpanded ?? meta.isExpanded,
        opacity: lerpDouble(startOpacity, endOpacity, t) ?? endOpacity,
      );
    }

    final segments = <_AnimatedBranchSegment>[];
    for (final placement in placements.values) {
      if (placement.parentId == null || placement.opacity <= 0.01) {
        continue;
      }
      final parent = placements[placement.parentId];
      if (parent == null || parent.opacity <= 0.01) {
        continue;
      }
      segments.add(
        _AnimatedBranchSegment.fromNodes(
          start: parent.anchor,
          end: placement.anchor,
          color: placement.color,
          opacity: math.min(parent.opacity, placement.opacity),
        ),
      );
    }

    return _InterpolatedLayoutFrame(
      canvasSize: Size(
        lerpDouble(from.canvasSize.width, to.canvasSize.width, t) ??
            to.canvasSize.width,
        lerpDouble(from.canvasSize.height, to.canvasSize.height, t) ??
            to.canvasSize.height,
      ),
      placements: placements,
      segments: segments,
    );
  }

  static Offset _fallbackAnchor({
    required String id,
    required _MindmapLayout primary,
    required _MindmapLayout secondary,
  }) {
    final parentId = _parentIdOf(id);
    if (parentId == null) {
      return const Offset(320, 240);
    }
    return primary.placements[parentId]?.anchor ??
        secondary.placements[parentId]?.anchor ??
        const Offset(320, 240);
  }

  static String? _parentIdOf(String id) {
    final slash = id.lastIndexOf('/');
    if (slash < 0) {
      return null;
    }
    return id.substring(0, slash);
  }
}

class _MindmapLayout {
  const _MindmapLayout({
    required this.canvasSize,
    required this.placements,
  });

  final Size canvasSize;
  final Map<String, _NodePlacement> placements;
}

class _NodePlacement {
  const _NodePlacement({
    required this.id,
    required this.parentId,
    required this.label,
    required this.depth,
    required this.anchor,
    required this.color,
    required this.hasChildren,
    required this.childCount,
    required this.isExpanded,
  });

  final String id;
  final String? parentId;
  final String label;
  final int depth;
  final Offset anchor;
  final Color color;
  final bool hasChildren;
  final int childCount;
  final bool isExpanded;
}

class _AnimatedNodePlacement {
  const _AnimatedNodePlacement({
    required this.id,
    required this.parentId,
    required this.label,
    required this.depth,
    required this.anchor,
    required this.color,
    required this.hasChildren,
    required this.childCount,
    required this.isExpanded,
    required this.opacity,
  });

  factory _AnimatedNodePlacement.fromStatic(
    _NodePlacement placement, {
    required double opacity,
  }) {
    return _AnimatedNodePlacement(
      id: placement.id,
      parentId: placement.parentId,
      label: placement.label,
      depth: placement.depth,
      anchor: placement.anchor,
      color: placement.color,
      hasChildren: placement.hasChildren,
      childCount: placement.childCount,
      isExpanded: placement.isExpanded,
      opacity: opacity,
    );
  }

  final String id;
  final String? parentId;
  final String label;
  final int depth;
  final Offset anchor;
  final Color color;
  final bool hasChildren;
  final int childCount;
  final bool isExpanded;
  final double opacity;

  Offset get labelCenter => depth == 0
      ? Offset(anchor.dx - 150, anchor.dy)
      : Offset(anchor.dx - 84, anchor.dy - (depth == 1 ? 8 : 4));
}

class _AnimatedBranchSegment {
  const _AnimatedBranchSegment({
    required this.start,
    required this.end,
    required this.controlStart,
    required this.controlEnd,
    required this.color,
    required this.opacity,
  });

  factory _AnimatedBranchSegment.fromNodes({
    required Offset start,
    required Offset end,
    required Color color,
    required double opacity,
  }) {
    final bendX = start.dx + ((end.dx - start.dx) * 0.36);
    return _AnimatedBranchSegment(
      start: start,
      end: end,
      controlStart: Offset(bendX, start.dy),
      controlEnd: Offset(bendX, end.dy),
      color: color,
      opacity: opacity,
    );
  }

  final Offset start;
  final Offset end;
  final Offset controlStart;
  final Offset controlEnd;
  final Color color;
  final double opacity;
}

class _MindmapData {
  const _MindmapData({
    required this.root,
  });

  final _MindmapNode root;

  static _MindmapData? tryParse(Object? raw) {
    if (raw is! Map) {
      return null;
    }

    final title = raw['title'];
    final nodesRaw = raw['nodes'];
    if (title is! String || title.trim().isEmpty || nodesRaw is! List) {
      return null;
    }

    final children = nodesRaw
        .map(_MindmapNode.fromDynamic)
        .whereType<_MindmapNode>()
        .toList();

    return _MindmapData(
      root: _MindmapNode(
        label: title.trim(),
        children: children,
      ),
    );
  }
}

class _MindmapNode {
  const _MindmapNode({
    required this.label,
    required this.children,
  });

  final String label;
  final List<_MindmapNode> children;

  static _MindmapNode? fromDynamic(Object? raw) {
    if (raw is! Map) {
      return null;
    }

    final label = raw['label'];
    if (label is! String || label.trim().isEmpty) {
      return null;
    }

    final childrenRaw = raw['children'];
    final children = childrenRaw is List
        ? childrenRaw.map(fromDynamic).whereType<_MindmapNode>().toList()
        : <_MindmapNode>[];

    return _MindmapNode(
      label: label.trim(),
      children: children,
    );
  }
}

class _TranscriptInsight {
  const _TranscriptInsight({
    required this.title,
    required this.subtitle,
    required this.content,
    required this.timeRange,
    required this.isApproximate,
  });

  final String title;
  final String subtitle;
  final String content;
  final String? timeRange;
  final bool isApproximate;
}
