import 'package:flutter/material.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sedang Memutar'),
      ),
      body: const Center(
        child: Text('Now Playing'),
      ),
    );
  }
}
