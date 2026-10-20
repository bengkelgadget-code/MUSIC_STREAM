import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'data/hive_init.dart';
import 'services/audio_handler.dart';

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Global Flutter error logging
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint(
          'FlutterError caught: ${details.exceptionAsString()}\n${details.stack}');
    };

    // Global asynchronous platform dispatcher error logging
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('PlatformDispatcher caught error: $error\n$stack');
      return true;
    };

    // Initialize Hive storage and register all model adapters
    await HiveInit.init();

    // Initialize audio_service background handler
    await initAudioService();

    runApp(
      const ProviderScope(
        child: SetelApp(),
      ),
    );
  }, (error, stack) {
    debugPrint('runZonedGuarded caught unhandled error: $error\n$stack');
  });
}
