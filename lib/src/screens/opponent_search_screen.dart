import 'dart:async';
import 'package:flutter/material.dart';

import '../models/player.dart';
import '../services/api_service.dart';

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/player.dart';

class OpponentSearchScreen extends StatefulWidget {
  const OpponentSearchScreen({super.key});

  @override
  State<OpponentSearchScreen> createState() => _OpponentSearchScreenState();
}

class _OpponentSearchScreenState extends State<OpponentSearchScreen> {
  final ApiService _apiService = ApiService();

  // --- Search State ---
  final TextEditingController _searchController = TextEditingController();
  List<Player> _results = [];
  bool _isLoading = false;
  Timer? _debounce;

  // --- Check-In State ---
  bool _isCheckedIn = false; // The master toggle
  final TextEditingController _myUsernameController = TextEditingController();
  final TextEditingController _myCharacterController = TextEditingController();
  bool _isCheckingInOrOut = false; // To show spinner on the button

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _myUsernameController.dispose();
    _myCharacterController.dispose();
    super.dispose();
  }

  // --- Logic: Check In ---
  Future<void> _handleCheckIn() async {
    final username = _myUsernameController.text.trim();
    final character = _myCharacterController.text.trim();

    if (username.isEmpty || character.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter username and character')),
      );
      return;
    }

    setState(() => _isCheckingInOrOut = true);

    final success = await _apiService.checkIn(username, character, 1800);

    if (!mounted) return;
    setState(() => _isCheckingInOrOut = false);

    if (success) {
      setState(() => _isCheckedIn = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to check in')),
      );
    }
  }

  // --- Logic: Check Out ---
  Future<void> _handleCheckOut() async {
    setState(() => _isCheckingInOrOut = true);

    final success = await _apiService.checkOut(
        _myUsernameController.text.trim(),
        _myCharacterController.text.trim(),
        1800);

    if (!mounted) return;
    setState(() => _isCheckingInOrOut = false);

    if (success) {
      setState(() {
        _isCheckedIn = false;
        _results.clear(); // Clear old search results
        _searchController.clear(); // Clear search bar
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to check out')),
      );
    }
  }

  // --- Logic: Search (Same as before) ---
  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (query.isNotEmpty) {
        _performSearch(query);
      } else {
        setState(() => _results = []);
      }
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isLoading = true);
    final players = await _apiService.searchActivePlayers(query);
    if (!mounted) return;
    setState(() {
      _results = players;
      _isLoading = false;
    });
  }

  // ===========================================================================
  // UI: The Switcher
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    // If checked in, show the Search Screen. If not, show the Check-In Screen.
    return _isCheckedIn ? _buildSearchPage() : _buildCheckInPage();
  }

  // --- Page 1: Check In ---
  Widget _buildCheckInPage() {
    return Scaffold(
      appBar: AppBar(title: const Text('Join Pool')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.videogame_asset, size: 80, color: Colors.grey),
            const SizedBox(height: 32),
            TextField(
              controller: _myUsernameController,
              decoration: const InputDecoration(
                labelText: 'Your Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _myCharacterController,
              decoration: const InputDecoration(
                labelText: 'Your Character (e.g. Mario)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isCheckingInOrOut ? null : _handleCheckIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isCheckingInOrOut
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('CHECK IN', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }

  // --- Page 2: Search Bar + Results ---
  Widget _buildSearchPage() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Opponent'),
        actions: [
          // The Check Out Button
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            tooltip: 'Check Out',
            onPressed: _isCheckingInOrOut ? null : _handleCheckOut,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              autofocus: true,
              textCapitalization: TextCapitalization.none,
              decoration: InputDecoration(
                hintText: 'Type opponent username...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : null,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey[200],
              ),
            ),
          ),
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
                          child: Text(player.character[0].toUpperCase(),
                              style: const TextStyle(color: Colors.white)),
                        ),
                        title: Text(player.username,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Playing: ${player.character}'),
                        trailing: player.rating > 0
                            ? Text('Elo: ${player.rating}',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 12))
                            : null,
                        onTap: () {
                          // Match logic later
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
