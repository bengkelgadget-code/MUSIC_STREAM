import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'data/hive_init.dart';
import 'services/audio_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive storage and register all model adapters
  await HiveInit.init();

  // Initialize audio_service background handler
  await initAudioService();

  runApp(
    const ProviderScope(
      child: SetelApp(),
    ),
  );
}
