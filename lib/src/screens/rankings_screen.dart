import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/player.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class RankingsScreen extends StatefulWidget {
  const RankingsScreen({super.key});

  @override
  State<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends State<RankingsScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  // State
  bool _isLoading = true;
  String? _error;

  // Character filter
  List<String> _characters = [];
  String? _selectedCharacter; // null = Global

  // Rankings data
  List<GlobalRankedPlayer> _globalRankings = [];
  List<CharacterRankedPlayer> _characterRankings = [];

  bool get _isGlobal => _selectedCharacter == null;

  @override
  void initState() {
    super.initState();
    _loadCharacters();
    _loadRankings();
  }

  Future<void> _loadCharacters() async {
    final chars = await _apiService.getPlayedCharacters();
    if (mounted) setState(() => _characters = chars);
  }

  Future<void> _loadRankings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_isGlobal) {
        final rankings = await _apiService.getGlobalRankings(limit: 50);
        if (!mounted) return;
        setState(() {
          _globalRankings = rankings;
          _isLoading = false;
        });
      } else {
        final rankings = await _apiService
            .getCharacterRankings(_selectedCharacter!, limit: 50);
        if (!mounted) return;
        setState(() {
          _characterRankings = rankings;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load rankings';
        _isLoading = false;
      });
    }
  }

  void _onCharacterChanged(String? character) {
    setState(() => _selectedCharacter = character);
    _loadRankings();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Character filter bar
        _buildFilterBar(),

        // Rankings list
        Expanded(child: _buildBody()),
      ],
    );
  }

  // ===========================================================================
  // Filter Bar
  // ===========================================================================

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFF222222),
      child: Row(
        children: [
          Text(
            'Leaderboard',
            style: GoogleFonts.spaceMono(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF333333),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _selectedCharacter,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF333333),
                  style:
                      GoogleFonts.spaceMono(fontSize: 13, color: Colors.white),
                  hint: Text('Global (All Characters)',
                      style: GoogleFonts.spaceMono(
                          fontSize: 13, color: Colors.white)),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Global (All Characters)'),
                    ),
                    ..._characters.map((c) => DropdownMenuItem<String?>(
                          value: c,
                          child: Text(c),
                        )),
                  ],
                  onChanged: _onCharacterChanged,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Body
  // ===========================================================================

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFBD0910)));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: _loadRankings, child: const Text('Retry')),
          ],
        ),
      );
    }

    final isEmpty =
        _isGlobal ? _globalRankings.isEmpty : _characterRankings.isEmpty;
    if (isEmpty) {
      return Center(
        child: Text(
          _isGlobal
              ? 'No ranked players yet.\nPlay some matches!'
              : 'No one has played $_selectedCharacter yet.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    final myUsername = _authService.username;
    final int itemCount =
        _isGlobal ? _globalRankings.length : _characterRankings.length;

    return RefreshIndicator(
      onRefresh: _loadRankings,
      color: const Color(0xFFBD0910),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (_isGlobal) {
            return _buildGlobalTile(_globalRankings[index], myUsername);
          } else {
            return _buildCharacterTile(_characterRankings[index], myUsername);
          }
        },
      ),
    );
  }

  // ===========================================================================
  // Ranking Tiles
  // ===========================================================================

  Widget _buildGlobalTile(GlobalRankedPlayer p, String? myUsername) {
    final isMe = p.username == myUsername;
    final rankColor = _rankColor(p.rank);

    return _tileContainer(
      isMe: isMe,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: _rankBadge(p.rank, rankColor),
        title: Row(
          children: [
            Text(p.username,
                style: GoogleFonts.spaceMono(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isMe ? const Color(0xFFBD0910) : Colors.white)),
            if (isMe) ...[
              const SizedBox(width: 6),
              const Text('(you)',
                  style: TextStyle(color: Color(0xFFBD0910), fontSize: 12)),
            ],
          ],
        ),
        subtitle: Text(
          '${p.wins}W-${p.losses}L  •  ${p.bestCharacter ?? "?"}',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${p.elo}',
                style: GoogleFonts.spaceMono(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: rankColor ?? Colors.white)),
            Text('peak ${p.peakElo}',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildCharacterTile(CharacterRankedPlayer p, String? myUsername) {
    final isMe = p.username == myUsername;
    final rankColor = _rankColor(p.rank);

    return _tileContainer(
      isMe: isMe,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: _rankBadge(p.rank, rankColor),
        title: Row(
          children: [
            Text(p.username,
                style: GoogleFonts.spaceMono(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isMe ? const Color(0xFFBD0910) : Colors.white)),
            if (isMe) ...[
              const SizedBox(width: 6),
              const Text('(you)',
                  style: TextStyle(color: Color(0xFFBD0910), fontSize: 12)),
            ],
          ],
        ),
        subtitle: Text(
          '${p.wins}W-${p.losses}L  •  ${p.winRate.toStringAsFixed(0)}% win rate',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${p.elo}',
                style: GoogleFonts.spaceMono(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: rankColor ?? Colors.white)),
            Text('peak ${p.peakElo}',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  Widget _tileContainer({required bool isMe, required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: isMe
            ? const Color(0xFFBD0910).withOpacity(0.15)
            : const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(10),
        border: isMe
            ? Border.all(color: const Color(0xFFBD0910), width: 1.5)
            : null,
      ),
      child: child,
    );
  }

  Widget _rankBadge(int rank, Color? color) {
    return SizedBox(
      width: 40,
      child: Center(
        child: Text('#$rank',
            style: GoogleFonts.spaceMono(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color ?? Colors.white70)),
      ),
    );
  }

  Color? _rankColor(int rank) {
    if (rank == 1) return const Color(0xFFFFD700); // Gold
    if (rank == 2) return const Color(0xFFC0C0C0); // Silver
    if (rank == 3) return const Color(0xFFCD7F32); // Bronze
    return null;
  }
}
