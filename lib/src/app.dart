import 'package:flutter/material.dart'; // Import your screen

import 'screens/main_navigation_shell.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmashRank',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFBD0910),
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFBD0910),
          foregroundColor: Colors.white,
        ),
      ),
      // NEW: Point home to the shell
      home: const MainNavigationShell(),
    );
  }
}
