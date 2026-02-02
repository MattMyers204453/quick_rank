import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/player.dart';

class ApiService {
  // --- TOGGLE THIS TO SWITCH BETWEEN REAL API AND MOCK DATA ---
  static const bool useMockData = false;
  // -----------------------------------------------------------

  // Android Emulator uses 10.0.2.2 to access localhost
  //static const String _baseUrl = 'http://10.0.2.2:8080/api';

  // production URL
  static const String _baseUrl =
      'https://smashrank-api-production.up.railway.app/api';

  /// Search for players in the active pool
  Future<List<Player>> searchActivePlayers(String query) async {
    // 1. Mock Data Path
    if (useMockData) {
      await Future.delayed(const Duration(milliseconds: 500));
      return _getMockResults(query);
    }

    // 2. Real API Path
    try {
      // Matches Spring: @GetMapping("/search") with @RequestParam String query
      final response = await http.get(
        Uri.parse('$_baseUrl/pool/search?query=$query'),
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
  /// UPDATED: Added [elo] to match Spring @RequestParam int elo
  Future<bool> checkIn(String username, String character, int elo) async {
    if (useMockData) {
      await Future.delayed(const Duration(milliseconds: 500));
      print('MOCK API: Checked in $username as $character with Elo $elo');
      return true;
    }

    try {
      // Matches Spring: @PostMapping("/check-in")
      final response = await http.post(
        Uri.parse(
            '$_baseUrl/pool/check-in?username=$username&character=$character&elo=$elo'),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error checking in: $e');
      return false;
    }
  }

  /// Check Out of the pool
  /// UPDATED: Added [elo] to match Spring @RequestParam int elo
  Future<bool> checkOut(String username, String character, int elo) async {
    if (useMockData) {
      await Future.delayed(const Duration(milliseconds: 300));
      print('MOCK API: Checked out $username ($elo)');
      return true;
    }

    try {
      // Matches Spring: @PostMapping("/check-out")
      final response = await http.post(
        Uri.parse(
            '$_baseUrl/pool/check-out?username=$username&character=$character&elo=$elo'),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error checking out: $e');
      return false;
    }
  }

  // --- Mock Data Logic ---

  List<Player> _getMockResults(String query) {
    if (query.isEmpty) return [];

    final lowercaseQuery = query.toLowerCase();

    return _mockPlayers.where((player) {
      return player.username.toLowerCase().contains(lowercaseQuery) ||
          player.character.toLowerCase().contains(lowercaseQuery);
    }).toList();
  }

  final List<Player> _mockPlayers = [
    Player(id: '1', username: 'MKLeo', character: 'Joker', rating: 2450),
    Player(id: '2', username: 'Sparg0', character: 'Cloud', rating: 2410),
    Player(id: '3', username: 'Tweek', character: 'Diddy Kong', rating: 2380),
    Player(id: '4', username: 'Light', character: 'Fox', rating: 2350),
    Player(id: '5', username: 'Glutonny', character: 'Wario', rating: 2320),
    Player(id: '6', username: 'Dabuz', character: 'Rosalina', rating: 2290),
    Player(id: '7', username: 'Kurama', character: 'Mario', rating: 2250),
    Player(id: '8', username: 'Tea', character: 'Pac-Man', rating: 2280),
    Player(
        id: '9',
        username: 'Maister',
        character: 'Mr. Game & Watch',
        rating: 2200),
    Player(id: '10', username: 'Riddles', character: 'Kazuya', rating: 2310),
    Player(id: '11', username: 'Smasher123', character: 'Samus', rating: 1500),
  ];
}
