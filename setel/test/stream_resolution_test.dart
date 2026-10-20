import 'package:flutter_test/flutter_test.dart';
import 'package:setel/services/youtube_service.dart';

void main() {
  group('Stream Resolution Tests', () {
    test('streamClients list contains androidVr, ios, tv with matching User-Agent', () {
      expect(YouTubeServiceImpl.streamClients.length, 3);

      final androidVr = YouTubeServiceImpl.streamClients[0];
      expect(androidVr.name, 'androidVr');
      expect(androidVr.userAgent, contains('com.google.android.apps.youtube.vr.oculus'));

      final ios = YouTubeServiceImpl.streamClients[1];
      expect(ios.name, 'ios');
      expect(ios.userAgent, contains('com.google.ios.youtube'));

      final tv = YouTubeServiceImpl.streamClients[2];
      expect(tv.name, 'tv');
      expect(tv.userAgent, contains('Cobalt'));
    });

    test('findClientIndex returns correct index and -1 for unknown', () {
      expect(YouTubeServiceImpl.findClientIndex('androidVr'), 0);
      expect(YouTubeServiceImpl.findClientIndex('ios'), 1);
      expect(YouTubeServiceImpl.findClientIndex('tv'), 2);
      expect(YouTubeServiceImpl.findClientIndex('unknown'), -1);
    });

    test('AudioStreamResult stores url and User-Agent headers correctly', () {
      final uri = Uri.parse('https://googlevideo.com/videoplayback?itag=251');
      const ua = 'com.google.android.apps.youtube.vr.oculus/1.56.21';
      final result = AudioStreamResult(
        url: uri,
        headers: {'User-Agent': ua},
        clientName: 'androidVr',
      );

      expect(result.url, uri);
      expect(result.headers['User-Agent'], ua);
      expect(result.clientName, 'androidVr');
    });
  });
}
