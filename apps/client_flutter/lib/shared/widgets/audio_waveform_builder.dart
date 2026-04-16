import 'audio_waveform_builder_stub.dart';

Future<List<double>> buildWaveformSamples(
  List<int> bytes, {
  int sampleCount = 72,
}) =>
    buildWaveformSamplesImpl(bytes, sampleCount: sampleCount);
