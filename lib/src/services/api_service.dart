import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/player.dart';

class ApiService {
  // --- TOGGLE THIS TO SWITCH BETWEEN REAL API AND MOCK DATA ---
  static const bool useMockData = true;
  // -----------------------------------------------------------

  // Android Emulator uses 10.0.2.2 to access localhost
  static const String _baseUrl = 'http://127.0.0.1:8080/api';

  /// Search for players in the active pool
  Future<List<Player>> searchActivePlayers(String query) async {
    // 1. Mock Data Path
    if (useMockData) {
      await Future.delayed(const Duration(milliseconds: 500));
      return _getMockResults(query);
    }

    // 2. Real API Path
    try {
      // UPDATED: Changed parameter from 'q' to 'query' to match Spring @RequestParam
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
  Future<bool> checkIn(String username, String character) async {
    if (useMockData) {
      await Future.delayed(const Duration(milliseconds: 500));
      print('MOCK API: Checked in $username as $character');
      return true;
    }

    try {
      // Spring @RequestParam on POST usually expects query parameters
      // or x-www-form-urlencoded. We'll use query params here.
      final response = await http.post(
        Uri.parse(
            '$_baseUrl/pool/check-in?username=$username&character=$character'),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error checking in: $e');
      return false;
    }
  }

  /// Check Out of the pool
  Future<bool> checkOut(String username, String character) async {
    if (useMockData) {
      await Future.delayed(const Duration(milliseconds: 300));
      print('MOCK API: Checked out $username');
      return true;
    }

    try {
      final response = await http.post(
        Uri.parse(
            '$_baseUrl/pool/check-out?username=$username&character=$character'),
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
