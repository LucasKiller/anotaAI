import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'recording_audio_player_controller.dart';

class RecordingAudioPlayer extends StatelessWidget {
  const RecordingAudioPlayer({
    super.key,
    required this.controller,
    required this.accessToken,
    required this.recordingId,
  });

  final RecordingAudioPlayerController controller;
  final String accessToken;
  final String recordingId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.isSupported) {
          return _buildUnavailableState(
            context,
            'O player embutido do MVP esta disponivel no Flutter web.',
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE4E7EC)),
          ),
          child: controller.loadedRecordingId == recordingId && controller.isLoaded
              ? _buildLoadedPlayer(context)
              : _buildLoadState(context),
        );
      },
    );
  }

  Widget _buildLoadState(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Carregue o audio original para ouvir a gravacao nesta pagina.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF475467),
                height: 1.5,
              ),
        ),
        const SizedBox(height: 12),
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
              label: const Text('Carregar audio'),
            ),
            const _PlayerHintChip(
              icon: Icons.lock_outline,
              label: 'Bucket privado',
            ),
            const _PlayerHintChip(
              icon: Icons.multitrack_audio_outlined,
              label: 'Waveform visual',
            ),
          ],
        ),
        if (controller.errorMessage != null &&
            controller.errorMessage!.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
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
        Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFFE8F0FF),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: controller.isLoadingSource
                    ? null
                    : controller.togglePlayback,
                icon: Icon(
                  controller.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: const Color(0xFF1B67F8),
                ),
              ),
            ),
            const SizedBox(width: 12),
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
                          color: const Color(0xFF101828),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    controller.isPlaying
                        ? 'Reproduzindo'
                        : 'Pronto para reproduzir',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF475467),
                        ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
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
        const SizedBox(height: 14),
        _WaveformView(
          samples: controller.waveformSamples,
          progress: maxMillis == 0 ? 0 : value / maxMillis,
          onSeekRatio: (ratio) {
            controller.seek(
              Duration(
                milliseconds: (ratio * maxMillis).round(),
              ),
            );
          },
        ),
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
        Row(
          children: <Widget>[
            Text(
              _formatDuration(position),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475467),
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const Spacer(),
            Text(
              _formatDuration(duration),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475467),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF475467),
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
  });

  final List<double> samples;
  final double progress;
  final ValueChanged<double> onSeekRatio;

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
            height: 76,
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
