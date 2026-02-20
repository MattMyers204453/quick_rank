import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/player.dart';
import 'auth_service.dart';

class ApiService {
  // --- TOGGLE THIS TO SWITCH BETWEEN REAL API AND MOCK DATA ---
  static const bool useMockData = false;
  // -----------------------------------------------------------

  // Android Emulator uses 10.0.2.2 to access localhost
  //static const String _baseUrl = 'http://10.0.2.2:8080/api';

  // production URL
  static const String _baseUrl =
      'https://smashrank-api-production.up.railway.app/api';

  final AuthService _authService = AuthService();

  // ---------------------------------------------------------------------------
  // Auth headers — attaches Bearer token to all requests
  // ---------------------------------------------------------------------------
  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        if (_authService.accessToken != null)
          'Authorization': 'Bearer ${_authService.accessToken}',
      };

  /// Search for players in the active pool
  Future<List<Player>> searchActivePlayers(String query) async {
    // 1. Mock Data Path
    // if (useMockData) {
    //   await Future.delayed(const Duration(milliseconds: 500));
    //   return _getMockResults(query);
    // }

    // 2. Real API Path
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/pool/search?query=$query'),
        headers: _authHeaders,
      );

      if (response.statusCode == 200) {
        print(response.body);
        final List<dynamic> body = jsonDecode(response.body);
        return body.map((json) => Player.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load players: ${response.statusCode}');
      }
    } catch (e) {
      print('Error searching players: $e');
      return [];
    }
  }

  /// Check In to the pool
  Future<bool> checkIn(String username, String character, int elo) async {
    if (useMockData) {
      await Future.delayed(const Duration(milliseconds: 500));
      print('MOCK API: Checked in $username as $character with Elo $elo');
      return true;
    }

    try {
      final response = await http.post(
        Uri.parse(
            '$_baseUrl/pool/check-in?username=$username&character=$character&elo=$elo'),
        headers: _authHeaders,
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error checking in: $e');
      return false;
    }
  }

  /// Check Out of the pool
  Future<bool> checkOut(String username, String character, int elo) async {
    if (useMockData) {
      await Future.delayed(const Duration(milliseconds: 300));
      print('MOCK API: Checked out $username ($elo)');
      return true;
    }

    try {
      final response = await http.post(
        Uri.parse(
            '$_baseUrl/pool/check-out?username=$username&character=$character&elo=$elo'),
        headers: _authHeaders,
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error checking out: $e');
      return false;
    }
  }

  // --- Mock Data Logic ---

  // List<Player> _getMockResults(String query) {
  //   final mockPlayers = [
  //     Player(username: 'mew2king', lastTag: 'Fox', elo: 2000),
  //     Player(username: 'mang0', lastTag: 'Falco', elo: 2100),
  //     Player(username: 'zain', lastTag: 'Marth', elo: 2200),
  //   ];

  //   if (query.isEmpty) return mockPlayers;
  //   return mockPlayers
  //       .where((p) => p.username.toLowerCase().contains(query.toLowerCase()))
  //       .toList();
  // }
}
