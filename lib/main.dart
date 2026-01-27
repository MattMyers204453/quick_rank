// lib/main.dart
import 'package:flutter/material.dart';
import 'package:quick_rank/src/app.dart';

void main() {
  runApp(const SmashRankApp());
}

class SmashRankApp extends StatelessWidget {
  const SmashRankApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmashRank',
      theme: ThemeData(
        // Smash Bros Ultimate uses a lot of black, white, and red.
        primarySwatch: Colors.red,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      home: const MyApp(),
    );
  }
}
