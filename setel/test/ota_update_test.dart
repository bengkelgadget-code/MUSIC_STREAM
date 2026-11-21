import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:setel/services/update_service.dart';

class MockHttpClientAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;
  MockHttpClientAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('5.6: OTA Update Tests (Buku Konter Style)', () {
    late Directory tempDir;
    late MethodChannel channel;
    const MethodChannel pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    final List<MethodCall> methodCalls = [];

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('setel_test_ota_');
      channel = const MethodChannel('com.bengkel.setel/installer');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, (MethodCall call) async {
        return tempDir.path;
      });

      PackageInfo.setMockInitialValues(
        appName: 'Setel',
        packageName: 'com.bengkel.setel',
        version: '1.3.13',
        buildNumber: '31',
        buildSignature: '',
      );
      SharedPreferences.setMockInitialValues({
        'autoDownloadUpdate': true,
        'hidePlayProtectNotice': false,
      });

      UpdateService.isDownloading = false;
      UpdateService.pendingUpdate = null;
      UpdateService.pendingApkPath = null;
      methodCalls.clear();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        methodCalls.add(call);
        return true;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, null);
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test('version.json diambil dengan cache-busting (timestamp URL & no-cache headers)', () async {
      RequestOptions? capturedOptions;
      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter((options) async {
        capturedOptions = options;
        const jsonStr = '''
        {
          "version_code": 32,
          "version_name": "1.3.14",
          "download_url": "https://example.com/Setel.apk",
          "changelog": "Update",
          "force_update": false
        }
        ''';
        return ResponseBody.fromString(jsonStr, 200, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        });
      });

      final info = await UpdateService.fetchVersionInfo(client: dio);
      expect(info, isNotNull);
      expect(info!.versionCode, 32);
      expect(info.versionName, '1.3.14');
      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.path, contains('?t='));
      expect(capturedOptions!.headers['Cache-Control'], 'no-cache');
    });

    testWidgets('auto-download dimulai otomatis saat non-force & toggle nyala, file terverifikasi',
        (tester) async {
      final apkContent = utf8.encode('DUMMY_VALID_APK_PAYLOAD_TEST');
      final expectedSha = sha256.convert(apkContent).toString();

      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter((options) async {
        if (options.path.contains('version.json')) {
          final jsonStr = jsonEncode({
            'version_code': 32,
            'version_name': '1.3.14',
            'download_url': 'https://example.com/Setel.apk',
            'changelog': 'Pembaruan OTA otomatis',
            'force_update': false,
            'apk_checksum': expectedSha,
            'apk_size_bytes': apkContent.length,
          });
          return ResponseBody.fromString(jsonStr, 200);
        } else {
          return ResponseBody.fromBytes(apkContent, 200);
        }
      });

      late BuildContext buildCtx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                buildCtx = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await tester.runAsync(() async {
        await UpdateService.checkUpdate(
          buildCtx,
          client: dio,
          testIsPlaying: false,
        );
      });
      await tester.pumpAndSettle();

      // Verifikasi dialog "Pembaruan Siap Dipasang" langsung muncul tanpa harus klik Unduh dulu!
      expect(find.text('Pembaruan Siap Dipasang'), findsOneWidget);
      expect(find.text('Pasang Sekarang'), findsOneWidget);

      // Klik Pasang Sekarang
      await tester.tap(find.text('Pasang Sekarang'));
      await tester.pumpAndSettle();

      // Platform installer harus dipanggil
      expect(methodCalls.length, 1);
      expect(methodCalls.first.method, 'installApk');
      expect(methodCalls.first.arguments['filePath'], contains('update_Setel_v32.apk'));
    });

    testWidgets('toggle autoDownloadUpdate mati: tidak auto-download, dialog lama muncul',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'autoDownloadUpdate': false,
      });

      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter((options) async {
        final jsonStr = jsonEncode({
          'version_code': 32,
          'version_name': '1.3.14',
          'download_url': 'https://example.com/Setel.apk',
          'changelog': 'Pembaruan manual',
          'force_update': false,
        });
        return ResponseBody.fromString(jsonStr, 200);
      });

      late BuildContext buildCtx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                buildCtx = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await tester.runAsync(() async {
        await UpdateService.checkUpdate(
          buildCtx,
          client: dio,
          testIsPlaying: false,
        );
      });
      await tester.pumpAndSettle();

      // Menampilkan dialog "Pembaruan Tersedia" dengan tombol "Unduh & Pasang"
      expect(find.text('Pembaruan Tersedia'), findsOneWidget);
      expect(find.text('Unduh & Pasang'), findsOneWidget);
      expect(find.text('Pembaruan Siap Dipasang'), findsNothing);
    });

    testWidgets('update force == true: langsung tampilkan dialog modal tanpa auto-download diam-diam',
        (tester) async {
      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter((options) async {
        final jsonStr = jsonEncode({
          'version_code': 32,
          'version_name': '1.3.14',
          'download_url': 'https://example.com/Setel.apk',
          'changelog': 'Force update penting',
          'force_update': true,
        });
        return ResponseBody.fromString(jsonStr, 200);
      });

      late BuildContext buildCtx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                buildCtx = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await tester.runAsync(() async {
        await UpdateService.checkUpdate(
          buildCtx,
          client: dio,
          testIsPlaying: false,
        );
      });
      await tester.pumpAndSettle();

      expect(find.text('Pembaruan Tersedia'), findsOneWidget);
      expect(find.text('Unduh & Pasang'), findsOneWidget);
      // Dialog modal force tidak memiliki tombol 'Nanti'
      expect(find.text('Nanti'), findsNothing);
    });

    testWidgets('unduh gagal checksum: file dihapus dan TIDAK ada installer dipanggil',
        (tester) async {
      final apkContent = utf8.encode('CORRUPT_APK_CONTENT');
      const badChecksum = 'bad_checksum_1234567890abcdef1234567890abcdef';

      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter((options) async {
        if (options.path.contains('version.json')) {
          final jsonStr = jsonEncode({
            'version_code': 32,
            'version_name': '1.3.14',
            'download_url': 'https://example.com/Setel.apk',
            'changelog': 'Checksum test',
            'force_update': false,
            'apk_checksum': badChecksum,
          });
          return ResponseBody.fromString(jsonStr, 200);
        } else {
          return ResponseBody.fromBytes(apkContent, 200);
        }
      });

      late BuildContext buildCtx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                buildCtx = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await tester.runAsync(() async {
        await UpdateService.checkUpdate(
          buildCtx,
          client: dio,
          testIsPlaying: false,
        );
      });
      await tester.pumpAndSettle();

      // Installer TIDAK boleh dipanggil
      expect(methodCalls.isEmpty, isTrue);

      // File sementara harus bersih/dihapus
      final targetFile = File('${tempDir.path}/update_Setel_v32.apk');
      expect(targetFile.existsSync(), isFalse);
    });

    testWidgets('unduh selesai saat lagu SEDANG DIPUTAR: TIDAK memicu dialog/installer (disimpan pending)',
        (tester) async {
      final apkContent = utf8.encode('SAFE_APK_CONTENT');

      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter((options) async {
        if (options.path.contains('version.json')) {
          final jsonStr = jsonEncode({
            'version_code': 32,
            'version_name': '1.3.14',
            'download_url': 'https://example.com/Setel.apk',
            'changelog': 'Safe test',
            'force_update': false,
          });
          return ResponseBody.fromString(jsonStr, 200);
        } else {
          return ResponseBody.fromBytes(apkContent, 200);
        }
      });

      late BuildContext buildCtx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                buildCtx = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await tester.runAsync(() async {
        await UpdateService.checkUpdate(
          buildCtx,
          client: dio,
          testIsPlaying: true, // LAGU SEDANG DIPUTAR!
        );
      });
      await tester.pump();

      // Dialog "Pembaruan Siap Dipasang" TIDAK boleh muncul karena lagu sedang diputar!
      expect(find.text('Pembaruan Siap Dipasang'), findsNothing);
      expect(methodCalls.isEmpty, isTrue);

      // File tersimpan sebagai pending
      expect(UpdateService.pendingApkPath, isNotNull);
      expect(File(UpdateService.pendingApkPath!).existsSync(), isTrue);
    });
  });
}
