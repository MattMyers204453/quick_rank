import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages authentication state: login, register, token storage, and refresh.
/// Singleton — accessed throughout the app via AuthService().
class AuthService {
  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // ---------------------------------------------------------------------------
  // Configuration — same base URL as MatchService
  // ---------------------------------------------------------------------------
  // Production (Railway)
  static const String _httpBase =
      'https://smashrank-api-production.up.railway.app/api';

  // Local development — uncomment and comment out the above:
  // static const String _httpBase = 'http://localhost:8080/api';

  // ---------------------------------------------------------------------------
  // Storage
  // ---------------------------------------------------------------------------
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const _keyAccessToken = 'smashrank_access_token';
  static const _keyRefreshToken = 'smashrank_refresh_token';
  static const _keyUsername = 'smashrank_username';
  static const _keyUserId = 'smashrank_user_id';

  // ---------------------------------------------------------------------------
  // In-memory state
  // ---------------------------------------------------------------------------
  String? _accessToken;
  String? _refreshToken;
  String? _username;
  String? _userId;

  String? get accessToken => _accessToken;
  String? get username => _username;
  String? get userId => _userId;
  bool get isLoggedIn => _accessToken != null;

  /// Stream for auth state changes (true = logged in, false = logged out).
  final _authStateController = StreamController<bool>.broadcast();
  Stream<bool> get onAuthStateChanged => _authStateController.stream;

  // ---------------------------------------------------------------------------
  // Initialize — call on app startup to restore saved session
  // ---------------------------------------------------------------------------
  Future<void> init() async {
    _accessToken = await _storage.read(key: _keyAccessToken);
    _refreshToken = await _storage.read(key: _keyRefreshToken);
    _username = await _storage.read(key: _keyUsername);
    _userId = await _storage.read(key: _keyUserId);

    // If we have a refresh token but the access token might be expired,
    // try to refresh silently.
    if (_accessToken == null && _refreshToken != null) {
      await _tryRefresh();
    }

    _authStateController.add(isLoggedIn);
  }

  // ---------------------------------------------------------------------------
  // Register
  // ---------------------------------------------------------------------------
  Future<AuthResult> register(String username, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$_httpBase/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      if (res.statusCode == 201) {
        final json = jsonDecode(res.body);
        await _saveTokens(json);
        return AuthResult.success();
      } else {
        final json = jsonDecode(res.body);
        return AuthResult.failure(json['error'] ?? 'Registration failed.');
      }
    } catch (e) {
      return AuthResult.failure('Network error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Login
  // ---------------------------------------------------------------------------
  Future<AuthResult> login(String username, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$_httpBase/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        await _saveTokens(json);
        return AuthResult.success();
      } else {
        final json = jsonDecode(res.body);
        return AuthResult.failure(json['error'] ?? 'Login failed.');
      }
    } catch (e) {
      return AuthResult.failure('Network error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Logout
  // ---------------------------------------------------------------------------
  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    _username = null;
    _userId = null;
    await _storage.deleteAll();
    _authStateController.add(false);
  }

  // ---------------------------------------------------------------------------
  // Token refresh
  // ---------------------------------------------------------------------------
  Future<bool> refreshTokens() async {
    return _tryRefresh();
  }

  Future<bool> _tryRefresh() async {
    if (_refreshToken == null) return false;

    try {
      final res = await http.post(
        Uri.parse('$_httpBase/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': _refreshToken}),
      );

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        await _saveTokens(json);
        return true;
      } else {
        // Refresh token is invalid/expired — force re-login
        await logout();
        return false;
      }
    } catch (e) {
      debugPrint('[Auth] Refresh error: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Authenticated HTTP helper
  // ---------------------------------------------------------------------------
  /// Makes an HTTP request with the Bearer token attached.
  /// Automatically refreshes the token on 401 and retries once.
  Future<http.Response> authenticatedPost(String path,
      {Map<String, dynamic>? body}) async {
    var res = await _doPost(path, body: body);

    // If 401, try refreshing and retry once
    if (res.statusCode == 401) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        res = await _doPost(path, body: body);
      }
    }

    return res;
  }

  Future<http.Response> authenticatedGet(String path) async {
    var res = await _doGet(path);

    if (res.statusCode == 401) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        res = await _doGet(path);
      }
    }

    return res;
  }

  Future<http.Response> _doPost(String path,
      {Map<String, dynamic>? body}) async {
    return http.post(
      Uri.parse('$_httpBase$path'),
      headers: {
        'Content-Type': 'application/json',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      },
      body: body != null ? jsonEncode(body) : null,
    );
  }

  Future<http.Response> _doGet(String path) async {
    return http.get(
      Uri.parse('$_httpBase$path'),
      headers: {
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------
  Future<void> _saveTokens(Map<String, dynamic> json) async {
    _accessToken = json['accessToken'];
    _refreshToken = json['refreshToken'];
    _username = json['username'];
    _userId = json['userId'];

    await _storage.write(key: _keyAccessToken, value: _accessToken);
    await _storage.write(key: _keyRefreshToken, value: _refreshToken);
    await _storage.write(key: _keyUsername, value: _username);
    await _storage.write(key: _keyUserId, value: _userId);

    _authStateController.add(true);
  }

  void dispose() {
    _authStateController.close();
  }
}

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------
class AuthResult {
  final bool isSuccess;
  final String? error;

  AuthResult.success()
      : isSuccess = true,
        error = null;

  AuthResult.failure(this.error) : isSuccess = false;
}
