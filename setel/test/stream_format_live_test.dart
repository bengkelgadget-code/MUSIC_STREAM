import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http_parser/http_parser.dart';
import 'package:setel/services/youtube_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

AudioOnlyStreamInfo createMockAudioStream({
  required int tag,
  required StreamContainer container,
  required String audioCodec,
  required double kbps,
}) {
  return AudioOnlyStreamInfo(
    VideoId('kJQP7kiw5Fk'),
    tag,
    Uri.parse('https://example.com/audio_$tag'),
    container,
    FileSize((kbps * 1000 / 8 * 180).round()),
    Bitrate((kbps * 1000).round()),
    audioCodec,
    '${kbps.round()}kbps',
    const [],
    MediaType('audio', container.name),
    null,
  );
}

void main() {
  test('Simulasi putar lagu di device: cek bitrate/codec terpilih di debugPrint untuk tiap format', () {
    // Skenario umum YouTube stream list (Opus webm & AAC mp4)
    final streams = [
      createMockAudioStream(tag: 139, container: StreamContainer.mp4, audioCodec: 'mp4a.40.2', kbps: 48),
      createMockAudioStream(tag: 249, container: StreamContainer.webM, audioCodec: 'opus', kbps: 50),
      createMockAudioStream(tag: 250, container: StreamContainer.webM, audioCodec: 'opus', kbps: 70),
      createMockAudioStream(tag: 140, container: StreamContainer.mp4, audioCodec: 'mp4a.40.2', kbps: 128),
      createMockAudioStream(tag: 251, container: StreamContainer.webM, audioCodec: 'opus', kbps: 160),
    ];

    for (final format in ['Hemat Data', 'Seimbang', 'Tertinggi']) {
      final selected = selectStreamByFormat(streams, format);
      debugPrint(
          '[DEVICE LOG] Berhasil me-resolve stream audio untuk videoId: kJQP7kiw5Fk '
          'menggunakan androidSdkless (format: $format, container: ${selected.container.name}, '
          'codec: ${selected.audioCodec}, tag: ${selected.tag}, '
          '${selected.bitrate.kiloBitsPerSecond.toStringAsFixed(1)} kbps, ${selected.size.totalBytes} bytes)');

      if (format == 'Hemat Data') {
        expect(selected.audioCodec, 'opus');
        expect(selected.tag, 249);
      } else if (format == 'Seimbang') {
        expect(selected.audioCodec, 'opus');
        expect(selected.tag, 250);
      } else if (format == 'Tertinggi') {
        expect(selected.tag, 251);
      }
    }
  });
}
