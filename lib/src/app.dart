import 'package:flutter/material.dart';
import 'screens/opponent_search_screen.dart'; // Import your screen

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // The text that appears in the task switcher
      title: 'SmashRank',

      // Theme logic (Red/Black/Dark as requested for Smash Bros)
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark, // Smash Ultimate uses a dark UI
        primaryColor: const Color(0xFFBD0910), // Smash Bros Red
        scaffoldBackgroundColor:
            const Color(0xFF1A1A1A), // Dark Grey Background
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFBD0910),
          foregroundColor: Colors.white,
        ),
      ),

      // Force the app to start on your Search Screen
      home: const OpponentSearchScreen(),
    );
  }
}
