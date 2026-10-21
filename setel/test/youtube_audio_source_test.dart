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
      // Setup a dummy local HttpServer that serves 206 Partial Content
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set('Content-Type', 'audio/mp4');
        request.response.headers.set('Content-Range', 'bytes 0-10/100');
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

    test('request streams continuous data through chunks', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) {
        final rangeHeader = request.headers.value('range');
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set('Content-Type', 'audio/mp4');
        request.response.headers.set('Content-Range', '$rangeHeader/10');
        request.response.add([10, 20, 30]);
        request.response.close();
      });

      final uri = Uri.parse('http://${server.address.host}:${server.port}/stream');
      final source = YouTubeAudioSource(
        uri: uri,
        headers: {'User-Agent': 'TestUA'},
        totalBytes: 3,
        contentType: 'audio/mp4',
      );

      try {
        final response = await source.request(0, 3);
        final bytes = await response.stream.fold<List<int>>([], (prev, elem) => prev..addAll(elem));
        expect(bytes, [10, 20, 30]);
      } finally {
        await server.close();
      }
    });
  });
}
