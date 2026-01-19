import 'dart:async';
import 'package:flutter/material.dart';

import '../models/Player.dart';
import '../services/api_service.dart';

class OpponentSearchScreen extends StatefulWidget {
  const OpponentSearchScreen({super.key});

  @override
  State<OpponentSearchScreen> createState() => _OpponentSearchScreenState();
}

class _OpponentSearchScreenState extends State<OpponentSearchScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();

  List<Player> _results = [];
  bool _isLoading = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    // 300ms debounce to prevent API flooding
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (query.isNotEmpty) {
        _performSearch(query);
      } else {
        setState(() {
          _results = [];
        });
      }
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isLoading = true);

    final players = await _apiService.searchActivePlayers(query);

    // Check if mounted to ensure we don't call setState on a disposed widget
    if (!mounted) return;

    setState(() {
      _results = players;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Opponent'),
        backgroundColor: Colors.redAccent, // Smash Bros theme color
      ),
      body: Column(
        children: [
          // --- Search Bar ---
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              autofocus: true, // Keyboard pops up immediately
              decoration: InputDecoration(
                hintText: 'Type opponent username...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[200],
              ),
            ),
          ),

          // --- Results List ---
          Expanded(
            child: _results.isEmpty &&
                    _searchController.text.isNotEmpty &&
                    !_isLoading
                ? const Center(child: Text('No active players found'))
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (ctx, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final player = _results[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.black,
                          child: Text(
                            player.character[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          player.username,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('Playing: ${player.character}'),
                        trailing: Text(
                          'Elo: ${player.rating}',
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        onTap: () {
                          // TODO: Navigate to Match Confirmation / Game Session screen
                          print('Selected ${player.username}');
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
