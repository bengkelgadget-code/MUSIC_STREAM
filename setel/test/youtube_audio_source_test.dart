import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:setel/services/youtube_audio_source.dart';

void main() {
  group('YouTubeAudioSource Tests', () {
    test('properties are set correctly', () {
      final uri = Uri.parse('https://example.com/audio.m4a');
      final source = YouTubeAudioSource(
        uri: uri,
        headers: {'User-Agent': 'TestUA'},
        totalBytes: 1048576,
        contentType: 'audio/mp4',
        tag: 'test_tag',
      );

      expect(source.uri, uri);
      expect(source.headers['User-Agent'], 'TestUA');
      expect(source.totalBytes, 1048576);
      expect(source.contentType, 'audio/mp4');
      expect(source.tag, 'test_tag');
    });

    test('request returns valid StreamAudioResponse with rangeRequestsSupported', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set('Content-Type', 'audio/mp4');
        request.response.headers.set('Content-Range', 'bytes 0-4/100');
        request.response.add([1, 2, 3, 4, 5]);
        request.response.close();
      });

      final uri = Uri.parse('http://${server.address.host}:${server.port}/stream');
      final source = YouTubeAudioSource(
        uri: uri,
        headers: {'User-Agent': 'TestUA'},
        totalBytes: 100,
        contentType: 'audio/mp4',
      );

      try {
        final response = await source.request(0, 5);
        expect(response.rangeRequestsSupported, isTrue);
        expect(response.sourceLength, 100);
        expect(response.contentLength, 5);
        expect(response.contentType, 'audio/mp4');

        final bytes = await response.stream.fold<List<int>>([], (prev, elem) => prev..addAll(elem));
        expect(bytes, [1, 2, 3, 4, 5]);
      } finally {
        await server.close();
      }
    });

    test('body pendek memicu retry dan berhasil ketika body lengkap diterima', () async {
      int requestCount = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) {
        requestCount++;
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set('Content-Type', 'audio/mp4');
        request.response.headers.set('Content-Range', 'bytes 0-4/5');
        if (requestCount == 1) {
          // Body pendek (hanya 2 byte dari 5 byte yang diminta)
          request.response.add([1, 2]);
        } else {
          // Retry berhasil dengan full 5 bytes
          request.response.add([1, 2, 3, 4, 5]);
        }
        request.response.close();
      });

      final uri = Uri.parse('http://${server.address.host}:${server.port}/stream');
      final source = YouTubeAudioSource(
        uri: uri,
        headers: {'User-Agent': 'TestUA'},
        totalBytes: 5,
        contentType: 'audio/mp4',
      );

      try {
        final response = await source.request(0, 5);
        final bytes = await response.stream.fold<List<int>>([], (prev, elem) => prev..addAll(elem));
        expect(requestCount, greaterThanOrEqualTo(2));
        expect(bytes, [1, 2, 3, 4, 5]);
      } finally {
        await server.close();
      }
    });

    test('status 200 pada Range request hanya menghasilkan jendela byte yang diminta', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) {
        // CDN salah mengirim status 200 (seluruh file) bukan 206
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set('Content-Type', 'audio/mp4');
        request.response.add([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
        request.response.close();
      });

      final uri = Uri.parse('http://${server.address.host}:${server.port}/stream');
      final source = YouTubeAudioSource(
        uri: uri,
        headers: {'User-Agent': 'TestUA'},
        totalBytes: 10,
        contentType: 'audio/mp4',
      );

      try {
        // Meminta range [2, 5) -> offset 2, requestedEnd 5 (bytes 2, 3, 4)
        final response = await source.request(2, 5);
        final bytes = await response.stream.fold<List<int>>([], (prev, elem) => prev..addAll(elem));
        expect(bytes, [2, 3, 4]);
      } finally {
        await server.close();
      }
    });

    test('status 416 dengan current >= totalBytes mengakhiri stream secara normal', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set('Content-Range', 'bytes */100');
        request.response.close();
      });

      final uri = Uri.parse('http://${server.address.host}:${server.port}/stream');
      final source = YouTubeAudioSource(
        uri: uri,
        headers: {'User-Agent': 'TestUA'},
        totalBytes: 100,
        contentType: 'audio/mp4',
      );

      try {
        // startByte >= totalBytes
        final response = await source.request(100, 110);
        final bytes = await response.stream.fold<List<int>>([], (prev, elem) => prev..addAll(elem));
        expect(bytes, isEmpty);
      } finally {
        await server.close();
      }
    });

    test('kegagalan chunk setelah 3x retry melempar StreamChunkException', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.close();
      });

      final uri = Uri.parse('http://${server.address.host}:${server.port}/stream');
      final source = YouTubeAudioSource(
        uri: uri,
        headers: {'User-Agent': 'TestUA'},
        totalBytes: 100,
        contentType: 'audio/mp4',
        videoId: 'test_vid',
      );

      try {
        final response = await source.request(0, 10);
        expect(
          () => response.stream.fold<List<int>>([], (prev, elem) => prev..addAll(elem)),
          throwsA(isA<StreamChunkException>()),
        );
      } finally {
        await server.close();
      }
    });
  });
}
