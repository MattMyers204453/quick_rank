import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/Player.dart';

class ApiService {
  // --- TOGGLE THIS TO SWITCH BETWEEN REAL API AND MOCK DATA ---
  static const bool useMockData = true;
  // -----------------------------------------------------------

  // Android Emulator uses 10.0.2.2 to access localhost
  static const String _baseUrl = 'http://10.0.2.2:8080/api';

  Future<List<Player>> searchActivePlayers(String query) async {
    // 1. Simulate API Latency if using mock data
    if (useMockData) {
      await Future.delayed(const Duration(milliseconds: 500));
      return _getMockResults(query);
    }

    // 2. Real API Call
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/pool/search?q=$query'),
      );

      if (response.statusCode == 200) {
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

  // --- Mock Data Logic ---

  List<Player> _getMockResults(String query) {
    if (query.isEmpty) return [];

    final lowercaseQuery = query.toLowerCase();

    // Filter the hardcoded list based on the search query
    return _mockPlayers.where((player) {
      return player.username.toLowerCase().contains(lowercaseQuery) ||
          player.character.toLowerCase().contains(lowercaseQuery);
    }).toList();
  }

  // Hardcoded test data representing your "Active Pool"
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
    // A generic one for testing simple searches
    Player(id: '11', username: 'Smasher123', character: 'Samus', rating: 1500),
  ];
}
