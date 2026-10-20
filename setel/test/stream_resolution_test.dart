import 'package:flutter_test/flutter_test.dart';
import 'package:setel/services/youtube_service.dart';

void main() {
  group('Stream Resolution Tests', () {
    test('streamClients list contains androidSdkless, androidVr, android, ios, tv with matching User-Agent', () {
      expect(YouTubeServiceImpl.streamClients.length, 5);

      final androidSdkless = YouTubeServiceImpl.streamClients[0];
      expect(androidSdkless.name, 'androidSdkless');
      expect(androidSdkless.userAgent, contains('com.google.android.youtube'));

      final androidVr = YouTubeServiceImpl.streamClients[1];
      expect(androidVr.name, 'androidVr');
      expect(androidVr.userAgent, contains('com.google.android.apps.youtube.vr.oculus'));

      final android = YouTubeServiceImpl.streamClients[2];
      expect(android.name, 'android');
      expect(android.userAgent, contains('com.google.android.youtube'));

      final ios = YouTubeServiceImpl.streamClients[3];
      expect(ios.name, 'ios');
      expect(ios.userAgent, contains('com.google.ios.youtube'));

      final tv = YouTubeServiceImpl.streamClients[4];
      expect(tv.name, 'tv');
      expect(tv.userAgent, contains('Cobalt'));
    });

    test('findClientIndex returns correct index and -1 for unknown', () {
      expect(YouTubeServiceImpl.findClientIndex('androidSdkless'), 0);
      expect(YouTubeServiceImpl.findClientIndex('androidVr'), 1);
      expect(YouTubeServiceImpl.findClientIndex('android'), 2);
      expect(YouTubeServiceImpl.findClientIndex('ios'), 3);
      expect(YouTubeServiceImpl.findClientIndex('tv'), 4);
      expect(YouTubeServiceImpl.findClientIndex('unknown'), -1);
    });

    test('AudioStreamResult stores url, headers, totalBytes, and contentType correctly', () {
      final uri = Uri.parse('https://googlevideo.com/videoplayback?itag=251');
      const ua = 'com.google.android.youtube/20.10.38';
      final result = AudioStreamResult(
        url: uri,
        headers: {'User-Agent': ua},
        clientName: 'androidSdkless',
        totalBytes: 5242880,
        contentType: 'audio/webm',
      );

      expect(result.url, uri);
      expect(result.headers['User-Agent'], ua);
      expect(result.clientName, 'androidSdkless');
      expect(result.totalBytes, 5242880);
      expect(result.contentType, 'audio/webm');
    });
  });
}
