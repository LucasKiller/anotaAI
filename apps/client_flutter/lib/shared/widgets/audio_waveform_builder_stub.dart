import 'dart:math' as math;

Future<List<double>> buildWaveformSamplesImpl(
  List<int> bytes, {
  int sampleCount = 72,
}) async {
  if (bytes.isEmpty || sampleCount <= 0) {
    return const <double>[];
  }

  final chunkSize = math.max(1, bytes.length ~/ sampleCount);
  final samples = <double>[];

  for (var start = 0; start < bytes.length && samples.length < sampleCount; start += chunkSize) {
    final end = math.min(bytes.length, start + chunkSize);
    var sum = 0.0;
    for (var index = start; index < end; index++) {
      sum += (bytes[index] - 128).abs() / 128;
    }
    final average = sum / math.max(1, end - start);
    samples.add(average.clamp(0.08, 1.0));
  }

  while (samples.length < sampleCount) {
    samples.add(0.12);
  }

  return samples;
}
