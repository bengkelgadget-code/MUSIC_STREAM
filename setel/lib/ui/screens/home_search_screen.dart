import 'package:flutter/material.dart';

class HomeSearchScreen extends StatelessWidget {
  const HomeSearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setel - Cari Musik'),
      ),
      body: const Center(
        child: Text('Cari lagu, artis, atau album'),
      ),
    );
  }
}
