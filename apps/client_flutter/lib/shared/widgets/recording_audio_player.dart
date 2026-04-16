import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'recording_audio_player_controller.dart';

class RecordingAudioPlayer extends StatelessWidget {
  const RecordingAudioPlayer({
    super.key,
    required this.controller,
    required this.accessToken,
    required this.recordingId,
    this.compact = false,
    this.showHeader = true,
    this.framed = true,
  });

  final RecordingAudioPlayerController controller;
  final String accessToken;
  final String recordingId;
  final bool compact;
  final bool showHeader;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final child =
            controller.loadedRecordingId == recordingId && controller.isLoaded
                ? _buildLoadedPlayer(context)
                : _buildLoadState(context);

        if (!controller.isSupported) {
          return _buildUnavailableState(
            context,
            'O player embutido do MVP esta disponivel no Flutter web.',
          );
        }

        if (!framed) {
          return child;
        }

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(compact ? 14 : 18),
          decoration: BoxDecoration(
            color: compact ? const Color(0xFF121720) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(compact ? 22 : 18),
            border: Border.all(
              color: compact
                  ? const Color(0xFF313946).withValues(alpha: 0.72)
                  : const Color(0xFFE4E7EC),
              width: compact ? 0.8 : 1,
            ),
          ),
          child: child,
        );
      },
    );
  }

  Widget _buildLoadState(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (showHeader) ...<Widget>[
          Text(
            'Carregue o audio original para ouvir a gravacao nesta pagina.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: compact
                      ? const Color(0xFFAAB3C2)
                      : const Color(0xFF475467),
                  height: 1.5,
                ),
          ),
          SizedBox(height: compact ? 10 : 12),
        ],
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            FilledButton.icon(
              onPressed: controller.isFetchingAudio
                  ? null
                  : () => controller.loadForRecording(
                        accessToken: accessToken,
                        recordingId: recordingId,
                      ),
              icon: controller.isFetchingAudio
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.headphones),
              label: Text(compact ? 'Carregar' : 'Carregar audio'),
              style: compact
                  ? FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF5B7CFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    )
                  : null,
            ),
            if (!compact) ...const <Widget>[
              _PlayerHintChip(
                icon: Icons.lock_outline,
                label: 'Bucket privado',
              ),
              _PlayerHintChip(
                icon: Icons.multitrack_audio_outlined,
                label: 'Waveform visual',
              ),
            ],
          ],
        ),
        if (controller.errorMessage != null &&
            controller.errorMessage!.trim().isNotEmpty) ...<Widget>[
          SizedBox(height: compact ? 10 : 12),
          Text(
            controller.errorMessage!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFB42318),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ],
    );
  }

  Widget _buildLoadedPlayer(BuildContext context) {
    final duration = controller.duration;
    final position =
        controller.position > duration ? duration : controller.position;
    final maxMillis =
        duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds;
    final value = position.inMilliseconds.clamp(0, maxMillis).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (showHeader) ...<Widget>[
          Row(
            children: <Widget>[
              Container(
                width: compact ? 40 : 44,
                height: compact ? 40 : 44,
                decoration: BoxDecoration(
                  color: compact
                      ? const Color(0xFF1A2231)
                      : const Color(0xFFE8F0FF),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: controller.isLoadingSource
                      ? null
                      : controller.togglePlayback,
                  icon: Icon(
                    controller.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: compact
                        ? const Color(0xFF8AA0FF)
                        : const Color(0xFF1B67F8),
                  ),
                ),
              ),
              SizedBox(width: compact ? 10 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      controller.loadedFileName ?? 'Audio da gravacao',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: compact
                                ? const Color(0xFFF3F6FB)
                                : const Color(0xFF101828),
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      controller.isPlaying
                          ? 'Reproduzindo'
                          : 'Pronto para reproduzir',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: compact
                                ? const Color(0xFFAAB3C2)
                                : const Color(0xFF475467),
                          ),
                    ),
                  ],
                ),
              ),
              compact
                  ? IconButton(
                      tooltip: 'Recarregar',
                      onPressed: controller.isFetchingAudio
                          ? null
                          : () => controller.loadForRecording(
                                accessToken: accessToken,
                                recordingId: recordingId,
                              ),
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: Color(0xFFAAB3C2),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: controller.isFetchingAudio
                          ? null
                          : () => controller.loadForRecording(
                                accessToken: accessToken,
                                recordingId: recordingId,
                              ),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Recarregar'),
                    ),
            ],
          ),
          SizedBox(height: compact ? 10 : 14),
        ],
        _WaveformView(
          samples: controller.waveformSamples,
          progress: maxMillis == 0 ? 0 : value / maxMillis,
          height: compact ? (showHeader ? 42 : 30) : 76,
          onSeekRatio: (ratio) {
            controller.seek(
              Duration(
                milliseconds: (ratio * maxMillis).round(),
              ),
            );
          },
        ),
        if (!compact) ...<Widget>[
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF1B67F8),
              inactiveTrackColor: const Color(0xFFD0D5DD),
              thumbColor: const Color(0xFF1B67F8),
              overlayColor: const Color(0x331B67F8),
              trackHeight: 4,
            ),
            child: Slider(
              value: value,
              min: 0,
              max: maxMillis.toDouble(),
              onChanged: (nextValue) {
                controller.seek(
                  Duration(milliseconds: nextValue.round()),
                );
              },
            ),
          ),
        ] else
          const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Text(
              _formatDuration(position),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: compact
                        ? const Color(0xFFAAB3C2)
                        : const Color(0xFF475467),
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const Spacer(),
            if (compact && showHeader)
              Text(
                'Toque na waveform para navegar',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF7E8795),
                      fontWeight: FontWeight.w500,
                    ),
              ),
            if (compact && showHeader) const Spacer(),
            Text(
              _formatDuration(duration),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: compact
                        ? const Color(0xFFAAB3C2)
                        : const Color(0xFF475467),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        if (controller.errorMessage != null &&
            controller.errorMessage!.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            controller.errorMessage!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFB42318),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ],
    );
  }

  Widget _buildUnavailableState(BuildContext context, String message) {
    if (!framed) {
      return Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color:
                  compact ? const Color(0xFFAAB3C2) : const Color(0xFF475467),
            ),
      );
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: compact ? const Color(0xFF121720) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(compact ? 22 : 18),
        border: Border.all(
          color: compact
              ? const Color(0xFF313946).withValues(alpha: 0.72)
              : const Color(0xFFE4E7EC),
          width: compact ? 0.8 : 1,
        ),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color:
                  compact ? const Color(0xFFAAB3C2) : const Color(0xFF475467),
            ),
      ),
    );
  }

  String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _WaveformView extends StatelessWidget {
  const _WaveformView({
    required this.samples,
    required this.progress,
    required this.onSeekRatio,
    this.height = 76,
  });

  final List<double> samples;
  final double progress;
  final ValueChanged<double> onSeekRatio;
  final double height;

  @override
  Widget build(BuildContext context) {
    final normalizedProgress = progress.clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final width = constraints.maxWidth;
            if (width <= 0) {
              return;
            }
            final ratio = (details.localPosition.dx / width).clamp(0.0, 1.0);
            onSeekRatio(ratio);
          },
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _WaveformPainter(
                samples: samples,
                progress: normalizedProgress,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.samples,
    required this.progress,
  });

  final List<double> samples;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = samples.isEmpty ? 64 : samples.length;
    final barWidth = math.max(2.0, size.width / (barCount * 1.7));
    final gap = barWidth * 0.7;
    final baseline = size.height / 2;
    final progressX = size.width * progress;

    final inactivePaint = Paint()
      ..color = const Color(0xFFD0D5DD)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;
    final activePaint = Paint()
      ..color = const Color(0xFF1B67F8)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    for (var index = 0; index < barCount; index++) {
      final normalized = samples.isEmpty
          ? 0.18 + ((index % 5) * 0.08)
          : samples[index].clamp(0.08, 1.0);
      final x = (barWidth / 2) + index * (barWidth + gap);
      if (x > size.width) {
        break;
      }
      final halfHeight = math.max(6.0, (size.height * 0.42) * normalized);
      final paint = x <= progressX ? activePaint : inactivePaint;
      canvas.drawLine(
        Offset(x, baseline - halfHeight),
        Offset(x, baseline + halfHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.samples != samples;
  }
}

class _PlayerHintChip extends StatelessWidget {
  const _PlayerHintChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: const Color(0xFF475467)),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF344054),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
