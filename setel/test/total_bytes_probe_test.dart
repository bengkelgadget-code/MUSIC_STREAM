import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setel/services/youtube_audio_source.dart';
import 'package:setel/services/youtube_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  group('v1.3.16 totalBytes Probe & Proxy Safety Tests', () {
    // 1. Probe berhasil: mock HTTP 206 + Content-Range: bytes 0-0/3841024 untuk totalBytes = 0
    test('1. Probe berhasil: AudioStreamResult.totalBytes dan request() range terbuka', () async {
      int probeCount = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) {
        final range = request.headers.value('range');
        if (range == 'bytes=0-0') {
          probeCount++;
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set('Content-Range', 'bytes 0-0/3841024');
          request.response.headers.set('Content-Type', 'audio/webm');
          request.response.add([0]);
          request.response.close();
        } else {
          request.response.statusCode = HttpStatus.ok;
          request.response.close();
        }
      });

      final url = Uri.parse('http://${server.address.host}:${server.port}/stream');

      try {
        // Test probeStreamTotalBytes langsung
        final probedBytes = await probeStreamTotalBytes(
          url,
          {'User-Agent': 'TestUA'},
          tag: 249,
          videoId: 'test_vid',
        );
        expect(probedBytes, 3841024);
        expect(probeCount, 1);

        // Test AudioStreamResult dengan totalBytes probed
        final audioResult = AudioStreamResult(
          url: url,
          headers: {'User-Agent': 'TestUA'},
          clientName: 'androidSdkless',
          totalBytes: probedBytes!,
          contentType: 'audio/webm',
          tag: 249,
          codec: 'opus',
        );
        expect(audioResult.totalBytes, 3841024);

        // Test lazy probe di YouTubeAudioSource.request() untuk request range terbuka (start=0, end=null)
        final source = YouTubeAudioSource(
          uri: url,
          headers: {'User-Agent': 'TestUA'},
          totalBytes: 0, // Awalnya 0
          contentType: 'audio/webm',
          itag: 249,
          videoId: 'test_vid',
        );

        final response = await source.request(0, null);
        expect(response.rangeRequestsSupported, isTrue);
        expect(response.sourceLength, 3841024);
        expect(response.contentLength, isNotNull);
        expect(response.contentLength, 3841024);
        expect(response.offset, 0);
      } finally {
        await server.close();
      }
    });

    // 2. Probe gagal: status 404 / tanpa Content-Range -> rangeRequestsSupported: false & contentLength tidak null
    test('2. Probe gagal: request() mengembalikan rangeRequestsSupported == false dan contentLength terdefinisi', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.close();
      });

      final url = Uri.parse('http://${server.address.host}:${server.port}/not_found');

      try {
        final source = YouTubeAudioSource(
          uri: url,
          headers: {'User-Agent': 'TestUA'},
          totalBytes: 0,
          contentType: 'audio/webm',
          itag: 249,
          videoId: 'test_vid_fail',
        );

        // Request range terbuka (start=0, end=null) saat probe gagal
        final response = await source.request(0, null);
        expect(response.rangeRequestsSupported, isFalse);
        expect(response.sourceLength, isNull);
        expect(response.contentLength, isNotNull);
        expect(response.offset, isNull);
      } finally {
        await server.close();
      }
    });

    // 3. Regresi jalur normal: totalBytes > 0 tidak melakukan probe sama sekali
    test('3. Regresi jalur normal: totalBytes > 0 tidak memicu request probe', () async {
      int requestCount = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) {
        requestCount++;
        request.response.statusCode = HttpStatus.ok;
        request.response.close();
      });

      final url = Uri.parse('http://${server.address.host}:${server.port}/stream');

      try {
        final source = YouTubeAudioSource(
          uri: url,
          headers: {'User-Agent': 'TestUA'},
          totalBytes: 5242880,
          contentType: 'audio/webm',
          itag: 251,
          videoId: 'normal_vid',
        );

        final response = await source.request(0, null);
        // Tidak ada probe yang dikirim
        expect(requestCount, 0);
        expect(response.rangeRequestsSupported, isTrue);
        expect(response.sourceLength, 5242880);
        expect(response.contentLength, 5242880);
        expect(response.offset, 0);
      } finally {
        await server.close();
      }
    });

    // 4. Per format: itag 249/250 totalBytes = 0 menghasilkan > 0 lewat probe, 251 tetap > 0 tanpa probe
    test('4. Per format: Hemat Data (249) dan Seimbang (250) diprobe ke > 0, Tertinggi (251) tetap', () async {
      int probe249Count = 0;
      int probe250Count = 0;

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) {
        final path = request.uri.path;
        if (path.contains('itag249')) {
          probe249Count++;
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set('Content-Range', 'bytes 0-0/1200000');
          request.response.close();
        } else if (path.contains('itag250')) {
          probe250Count++;
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set('Content-Range', 'bytes 0-0/2400000');
          request.response.close();
        } else {
          request.response.statusCode = HttpStatus.ok;
          request.response.close();
        }
      });

      final url249 = Uri.parse('http://${server.address.host}:${server.port}/stream_itag249');
      final url250 = Uri.parse('http://${server.address.host}:${server.port}/stream_itag250');
      final url251 = Uri.parse('http://${server.address.host}:${server.port}/stream_itag251');
      final url140 = Uri.parse('http://${server.address.host}:${server.port}/stream_itag140');

      try {
        AudioOnlyStreamInfo createStream(int tag, Uri url, int totalBytes, int bps, String codec, String container) {
          return AudioOnlyStreamInfo.fromJson({
            'videoId': {'value': '0123456789a'},
            'tag': tag,
            'url': url.toString(),
            'container': {'name': container},
            'size': {'totalBytes': totalBytes},
            'bitrate': {'bitsPerSecond': bps},
            'audioCodec': codec,
            'qualityLabel': '${bps ~/ 1000}k',
            'fragments': [],
            'codec': 'audio/$container; codecs="$codec"',
            'audioTrack': null,
          });
        }

        final stream249 = createStream(249, url249, 0, 50000, 'opus', 'webm');
        final stream250 = createStream(250, url250, 0, 70000, 'opus', 'webm');
        final stream251 = createStream(251, url251, 4000000, 160000, 'opus', 'webm');
        final stream140 = createStream(140, url140, 3500000, 128000, 'mp4a.40.2', 'mp4');

        final streams = [stream249, stream250, stream251, stream140];

        // Format: Hemat Data -> memilih itag 249 (size 0)
        final selectedHemat = selectStreamByFormat(streams, 'Hemat Data');
        expect(selectedHemat.tag, 249);
        expect(selectedHemat.size.totalBytes, 0);

        var totalHemat = selectedHemat.size.totalBytes;
        if (totalHemat <= 0) {
          final probed = await probeStreamTotalBytes(selectedHemat.url, {}, tag: selectedHemat.tag);
          if (probed != null && probed > 0) totalHemat = probed;
        }
        expect(totalHemat, 1200000);
        expect(probe249Count, 1);

        // Format: Seimbang -> memilih itag 250 (size 0)
        final selectedSeimbang = selectStreamByFormat(streams, 'Seimbang');
        expect(selectedSeimbang.tag, 250);
        expect(selectedSeimbang.size.totalBytes, 0);

        var totalSeimbang = selectedSeimbang.size.totalBytes;
        if (totalSeimbang <= 0) {
          final probed = await probeStreamTotalBytes(selectedSeimbang.url, {}, tag: selectedSeimbang.tag);
          if (probed != null && probed > 0) totalSeimbang = probed;
        }
        expect(totalSeimbang, 2400000);
        expect(probe250Count, 1);

        // Format: Tertinggi -> memilih itag 251 (size 4000000)
        final selectedTertinggi = selectStreamByFormat(streams, 'Tertinggi');
        expect(selectedTertinggi.tag, 251);
        expect(selectedTertinggi.size.totalBytes, 4000000);
        // Karena totalBytes > 0, tidak perlu diprobe sama sekali
      } finally {
        await server.close();
      }
    });

    // 5. Probe sekali saja: dua request() berurutan pada satu sumber dengan totalBytes = 0 -> probe HTTP hanya 1x
    test('5. Probe sekali saja: dua request() berurutan memanggil probe HTTP tepat 1 kali', () async {
      int probeCallCount = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) {
        final range = request.headers.value('range');
        if (range == 'bytes=0-0') {
          probeCallCount++;
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set('Content-Range', 'bytes 0-0/3841024');
          request.response.close();
        } else {
          request.response.statusCode = HttpStatus.ok;
          request.response.close();
        }
      });

      final url = Uri.parse('http://${server.address.host}:${server.port}/stream');

      try {
        final source = YouTubeAudioSource(
          uri: url,
          headers: {'User-Agent': 'TestUA'},
          totalBytes: 0,
          contentType: 'audio/webm',
          itag: 249,
          videoId: 'cache_test_vid',
        );

        // Request pertama
        final r1 = await source.request(0, null);
        expect(r1.rangeRequestsSupported, isTrue);
        expect(r1.sourceLength, 3841024);
        expect(probeCallCount, 1);

        // Request kedua (misal range berikutnya dari ExoPlayer)
        final r2 = await source.request(512, null);
        expect(r2.rangeRequestsSupported, isTrue);
        expect(r2.sourceLength, 3841024);
        // probeCallCount TETAP 1 (tidak dipanggil lagi karena di-cache)
        expect(probeCallCount, 1);
      } finally {
        await server.close();
      }
    });
  });
}
