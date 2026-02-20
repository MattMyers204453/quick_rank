import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/main_navigation_shell.dart';
import 'services/auth_service.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AuthService _authService = AuthService();
  bool _isLoggedIn = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _authService.init();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = _authService.isLoggedIn;
      _isInitialized = true;
    });

    // Listen for auth state changes (login, logout, token refresh)
    _authService.onAuthStateChanged.listen((loggedIn) {
      if (!mounted) return;
      setState(() => _isLoggedIn = loggedIn);
    });
  }

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
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (!_isInitialized) {
      // Show a loading screen while AuthService restores tokens
      return const Scaffold(
        backgroundColor: Color(0xFF1A1A1A),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFBD0910)),
        ),
      );
    }

    return _isLoggedIn ? const MainNavigationShell() : const LoginScreen();
  }
}
