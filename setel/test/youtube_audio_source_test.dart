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

    test('chunk ke-2 balas 403 memicu self-healing re-resolve 1x dan stream berlanjut sukses', () async {
      int reResolveCalls = 0;
      final server1 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final server2 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      // Server 1: chunk 1 (0-524287) sukses, chunk 2 (524288-1048575) balas 403
      server1.listen((HttpRequest request) {
        final range = request.headers.value('Range') ?? '';
        if (range.contains('bytes=0-')) {
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set('Content-Range', 'bytes 0-524287/1048576');
          request.response.add(List.filled(512 * 1024, 1));
          request.response.close();
        } else {
          request.response.statusCode = HttpStatus.forbidden;
          request.response.close();
        }
      });

      // Server 2: URL segar setelah re-resolve, melayani chunk 2 dengan sukses
      server2.listen((HttpRequest request) {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set('Content-Range', 'bytes 524288-1048575/1048576');
        request.response.add(List.filled(512 * 1024, 2));
        request.response.close();
      });

      final uri1 = Uri.parse('http://${server1.address.host}:${server1.port}/stream1');
      final uri2 = Uri.parse('http://${server2.address.host}:${server2.port}/stream2');

      final source = YouTubeAudioSource(
        uri: uri1,
        headers: {'User-Agent': 'TestUA'},
        totalBytes: 1048576,
        contentType: 'audio/mp4',
        videoId: 'midstream_403_vid',
        onReResolveUrl: ({bool fallbackNonOpus = false}) async {
          reResolveCalls++;
          return (url: uri2, headers: {'User-Agent': 'TestUA_Fresh'}, totalBytes: 1048576);
        },
      );

      try {
        final response = await source.request(0, 1048576);
        final bytes = await response.stream.fold<List<int>>([], (prev, elem) => prev..addAll(elem));
        expect(reResolveCalls, 1);
        expect(bytes.length, 1048576);
        expect(bytes.sublist(0, 5), [1, 1, 1, 1, 1]);
        expect(bytes.sublist(bytes.length - 5), [2, 2, 2, 2, 2]);
      } finally {
        await server1.close();
        await server2.close();
      }
    });

    test('chunk ke-2 403 dengan re-resolve gagal melempar StreamChunkException dan maks 1x re-resolve', () async {
      int reResolveCalls = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      server.listen((HttpRequest request) {
        final range = request.headers.value('Range') ?? '';
        if (range.contains('bytes=0-')) {
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set('Content-Range', 'bytes 0-524287/1048576');
          request.response.add(List.filled(512 * 1024, 1));
          request.response.close();
        } else {
          // Chunk 2 selalu 403
          request.response.statusCode = HttpStatus.forbidden;
          request.response.close();
        }
      });

      final uri = Uri.parse('http://${server.address.host}:${server.port}/stream');

      final source = YouTubeAudioSource(
        uri: uri,
        headers: {'User-Agent': 'TestUA'},
        totalBytes: 1048576,
        contentType: 'audio/mp4',
        videoId: 'midstream_403_fail_vid',
        onReResolveUrl: ({bool fallbackNonOpus = false}) async {
          reResolveCalls++;
          return (url: uri, headers: {'User-Agent': 'TestUA'}, totalBytes: 1048576);
        },
      );

      try {
        final response = await source.request(0, 1048576);
        await expectLater(
          response.stream.fold<List<int>>([], (prev, elem) => prev..addAll(elem)),
          throwsA(isA<StreamChunkException>().having((e) => e.statusCode, 'statusCode', 403)),
        );
        // Maksimal 1x re-resolve dipanggil dalam satu byteStream
        expect(reResolveCalls, 1);
      } finally {
        await server.close();
      }
    });

    test('proxy timeout: pembacaan body chunk yang menggantung melempar StreamChunkException timeout setelah 3x', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) {
        // Balas headers partial content tapi jangan kirim byte apa pun (gantung)
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set('Content-Range', 'bytes 0-9/100');
        // Jangan close response agar stream body menggantung
      });

      final uri = Uri.parse('http://${server.address.host}:${server.port}/stream');
      final source = YouTubeAudioSource(
        uri: uri,
        headers: {'User-Agent': 'TestUA'},
        totalBytes: 100,
        contentType: 'audio/mp4',
        videoId: 'stall_vid',
        chunkTimeout: const Duration(milliseconds: 50), // Timeout cepat untuk unit test
      );

      try {
        final response = await source.request(0, 10);
        await expectLater(
          response.stream.fold<List<int>>([], (prev, elem) => prev..addAll(elem)),
          throwsA(isA<StreamChunkException>().having((e) => e.message.toLowerCase(), 'message', contains('timeout'))),
        );
      } finally {
        await server.close(force: true);
      }
    });

    test('totalBytes dikoreksi dari header Content-Range respons 206 pertama', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) {
        final range = request.headers.value('Range') ?? '';
        request.response.statusCode = HttpStatus.partialContent;
        if (range.contains('bytes=0-')) {
          // Server mengembalikan total 1048576 padahal manifest mengklaim 100000
          request.response.headers.set('Content-Range', 'bytes 0-524287/1048576');
          request.response.add(List.filled(512 * 1024, 7));
        } else {
          request.response.headers.set('Content-Range', 'bytes 524288-1048575/1048576');
          request.response.add(List.filled(512 * 1024, 8));
        }
        request.response.close();
      });

      final uri = Uri.parse('http://${server.address.host}:${server.port}/stream');
      final source = YouTubeAudioSource(
        uri: uri,
        headers: {'User-Agent': 'TestUA'},
        totalBytes: 100000, // Manifest salah (lebih kecil)
        contentType: 'audio/mp4',
        videoId: 'correct_total_vid',
      );

      try {
        // Panggil tanpa end agar stream dibatasi oleh totalBytes/effectiveEnd
        final response = await source.request(0);
        final bytes = await response.stream.fold<List<int>>([], (prev, elem) => prev..addAll(elem));
        // Stream tidak berhenti di 100000, melainkan lanjut mengambil seluruh 1048576 bytes
        expect(bytes.length, 1048576);
      } finally {
        await server.close();
      }
    });

    test('respons 200: 10 chunk berturut-turut semuanya berhasil tanpa error koneksi', () async {
      int requestCount = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      const chunkSize = 512 * 1024;
      const totalChunks = 10;
      final totalSize = totalChunks * chunkSize;
      final fullData = List.filled(totalSize, 9);

      server.listen((HttpRequest request) {
        requestCount++;
        // CDN salah membalas 200 OK untuk setiap chunk (mengirim seluruh data file)
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set('Content-Type', 'audio/mp4');
        request.response.add(fullData);
        request.response.close();
      });

      final uri = Uri.parse('http://${server.address.host}:${server.port}/stream');
      final source = YouTubeAudioSource(
        uri: uri,
        headers: {'User-Agent': 'TestUA'},
        totalBytes: totalSize,
        contentType: 'audio/mp4',
        videoId: 'ten_chunks_200_vid',
      );

      try {
        final response = await source.request(0, totalSize);
        final bytes = await response.stream.fold<List<int>>([], (prev, elem) => prev..addAll(elem));
        expect(requestCount, totalChunks);
        expect(bytes.length, totalSize);
      } finally {
        await server.close();
      }
    });

    test('dua request() bersamaan pada satu sumber: satu re-resolve, stream lainnya tidak terpengaruh', () async {
      final server1 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final server2 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      final List<String> server1Paths = [];
      final List<String> server2Paths = [];

      server1.listen((HttpRequest request) {
        server1Paths.add(request.uri.path);
        final range = request.headers.value('Range') ?? '';
        final clientHeader = request.headers.value('X-Client-Id') ?? '';
        if (clientHeader == 'StreamA' && !range.contains('bytes=0-')) {
          // Stream A chunk 2 gagal 403
          request.response.statusCode = HttpStatus.forbidden;
          request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set('Content-Range', '${range.replaceFirst('bytes=', 'bytes ')}/1048576');
        request.response.add(List.filled(512 * 1024, 1));
        request.response.close();
      });

      server2.listen((HttpRequest request) {
        server2Paths.add(request.uri.path);
        final range = request.headers.value('Range') ?? '';
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set('Content-Range', '${range.replaceFirst('bytes=', 'bytes ')}/1048576');
        request.response.add(List.filled(512 * 1024, 2));
        request.response.close();
      });

      final uri1 = Uri.parse('http://${server1.address.host}:${server1.port}/stream1');
      final uri2 = Uri.parse('http://${server2.address.host}:${server2.port}/stream2');

      final source = YouTubeAudioSource(
        uri: uri1,
        headers: {'User-Agent': 'TestUA'},
        totalBytes: 1048576,
        contentType: 'audio/mp4',
        videoId: 'concurrent_vid',
        onReResolveUrl: ({bool fallbackNonOpus = false}) async {
          return (url: uri2, headers: {'User-Agent': 'TestUA_Fresh', 'X-Client-Id': 'StreamA'}, totalBytes: 1048576);
        },
      );

      try {
        // Stream A (akan re-resolve di chunk 2)
        final reqA = await source.request(0, 1048576);
        // Stream B (harus tetap berjalan di uri1 tanpa terpengaruh re-resolve Stream A)
        final reqB = await source.request(0, 1048576);

        final futA = reqA.stream.fold<List<int>>([], (prev, elem) => prev..addAll(elem));
        final futB = reqB.stream.fold<List<int>>([], (prev, elem) => prev..addAll(elem));

        final res = await Future.wait([futA, futB]);
        expect(res[0].length, 1048576);
        expect(res[1].length, 1048576);

        // Pastikan field instance uri dari source tidak bermutasi
        expect(source.uri, uri1);
      } finally {
        await server1.close();
        await server2.close();
      }
    });

    test('re-resolve mengembalikan totalBytes baru dan effectiveEnd lokal diperbarui', () async {
      final server1 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final server2 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      // Server 1 chunk 1 ok, chunk 2 403
      server1.listen((HttpRequest request) {
        final range = request.headers.value('Range') ?? '';
        if (range.contains('bytes=0-')) {
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set('Content-Range', 'bytes 0-524287/1048576');
          request.response.add(List.filled(512 * 1024, 1));
          request.response.close();
        } else {
          request.response.statusCode = HttpStatus.forbidden;
          request.response.close();
        }
      });

      // Server 2 setelah re-resolve memberi tahu bahwa totalBytes sebenarnya hanya 524288 (1 chunk saja)
      server2.listen((HttpRequest request) {
        // Server 2 membalas 416 karena file hanya 524288 bytes
        request.response.statusCode = 416;
        request.response.headers.set('Content-Range', 'bytes */524288');
        request.response.close();
      });

      final uri1 = Uri.parse('http://${server1.address.host}:${server1.port}/stream1');
      final uri2 = Uri.parse('http://${server2.address.host}:${server2.port}/stream2');

      final source = YouTubeAudioSource(
        uri: uri1,
        headers: {'User-Agent': 'TestUA'},
        totalBytes: 1048576,
        contentType: 'audio/mp4',
        videoId: 'update_total_vid',
        onReResolveUrl: ({bool fallbackNonOpus = false}) async {
          // Stream baru lebih pendek (hanya 524288 bytes)
          return (url: uri2, headers: {'User-Agent': 'TestUA'}, totalBytes: 524288);
        },
      );

      try {
        final response = await source.request(0);
        final bytes = await response.stream.fold<List<int>>([], (prev, elem) => prev..addAll(elem));
        // Stream selesai normal karena current (524288) >= new totalBytes (524288)
        expect(bytes.length, 524288);
      } finally {
        await server1.close();
        await server2.close();
      }
    });
  });
}
