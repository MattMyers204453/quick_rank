import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/player.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  PlayerProfile? _profile;
  List<CharacterStat> _characters = [];
  List<MatchHistoryEntry> _matches = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final username = _authService.username;
    if (username == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _apiService.getProfile(username, matchLimit: 20);
      if (!mounted) return;

      if (result != null) {
        setState(() {
          _profile = result.profile;
          _characters = result.characters;
          _matches = result.matches;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Profile not found';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load profile';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFBD0910)));
    }

    if (_error != null || _profile == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error ?? 'Something went wrong',
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadProfile, child: const Text('Retry')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadProfile,
      color: const Color(0xFFBD0910),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatsCard(),
          const SizedBox(height: 20),
          _buildCharacterSection(),
          const SizedBox(height: 20),
          _buildMatchHistorySection(),
        ],
      ),
    );
  }

  // ===========================================================================
  // Global Stats Card
  // ===========================================================================

  Widget _buildStatsCard() {
    final p = _profile!;

    return Card(
      color: const Color(0xFF2A2A2A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Username + Rank
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.username,
                        style: GoogleFonts.spaceMono(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    if (p.mainCharacter != null) ...[
                      const SizedBox(height: 4),
                      Text('Main: ${p.mainCharacter}',
                          style:
                              TextStyle(color: Colors.grey[400], fontSize: 13)),
                    ],
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFBD0910).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFBD0910)),
                  ),
                  child: Text(
                    'Rank #${p.rank} of ${p.totalActivePlayers}',
                    style: GoogleFonts.spaceMono(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFBD0910)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Big Elo display
            Text('${p.elo}',
                style: GoogleFonts.spaceMono(
                    fontSize: 52,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            Text('Best Character Elo',
                style:
                    GoogleFonts.spaceMono(fontSize: 13, color: Colors.white54)),

            const SizedBox(height: 20),
            const Divider(color: Colors.white12),
            const SizedBox(height: 16),

            // Aggregate stats
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statColumn('Peak', '${p.peakElo}', Colors.amber),
                _statColumn('Wins', '${p.wins}', Colors.green),
                _statColumn('Losses', '${p.losses}', Colors.red),
                _statColumn('Win %', '${p.winRate.toStringAsFixed(1)}%',
                    Colors.white70),
              ],
            ),

            if (p.totalGames == 0) ...[
              const SizedBox(height: 16),
              const Text('Play your first match to see your stats!',
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statColumn(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(value,
            style: GoogleFonts.spaceMono(
                fontSize: 18, fontWeight: FontWeight.bold, color: valueColor)),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
      ],
    );
  }

  // ===========================================================================
  // Character Breakdown
  // ===========================================================================

  Widget _buildCharacterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Characters',
            style: GoogleFonts.spaceMono(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white70)),
        const SizedBox(height: 10),
        if (_characters.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
                child: Text('No character stats yet',
                    style: TextStyle(color: Colors.white38, fontSize: 14))),
          )
        else
          ..._characters.map(_buildCharacterCard),
      ],
    );
  }

  Widget _buildCharacterCard(CharacterStat stat) {
    final isMain = stat.character == _profile?.mainCharacter;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
        border: isMain
            ? Border.all(color: const Color(0xFFBD0910).withOpacity(0.5))
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Character name + main badge
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(stat.character,
                          style: GoogleFonts.spaceMono(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      if (isMain) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFBD0910).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('MAIN',
                              style: TextStyle(
                                  color: Color(0xFFBD0910),
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${stat.wins}W-${stat.losses}L  •  Rank #${stat.characterRank}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),

            // Elo display
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${stat.elo}',
                    style: GoogleFonts.spaceMono(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                Text('peak ${stat.peakElo}',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // Match History
  // ===========================================================================

  Widget _buildMatchHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recent Matches',
            style: GoogleFonts.spaceMono(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white70)),
        const SizedBox(height: 10),
        if (_matches.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
                child: Text('No match history yet',
                    style: TextStyle(color: Colors.white38, fontSize: 14))),
          )
        else
          ..._matches.map(_buildMatchTile),
      ],
    );
  }

  Widget _buildMatchTile(MatchHistoryEntry match) {
    final won = match.won;
    final resultColor = won ? Colors.green : Colors.red;

    String eloChangeText = '';
    Color eloChangeColor = Colors.white54;
    if (match.eloDelta != null) {
      final d = match.eloDelta!;
      eloChangeText = d >= 0 ? '+$d' : '$d';
      eloChangeColor = d >= 0 ? Colors.green : Colors.red;
    }

    String timeText = '';
    if (match.playedAt != null) {
      try {
        final dt = DateTime.parse(match.playedAt!);
        final diff = DateTime.now().difference(dt);
        if (diff.inMinutes < 60) {
          timeText = '${diff.inMinutes}m ago';
        } else if (diff.inHours < 24) {
          timeText = '${diff.inHours}h ago';
        } else {
          timeText = '${diff.inDays}d ago';
        }
      } catch (_) {}
    }

    // Character display
    final myChar = match.myCharacter ?? '?';
    final oppChar = match.opponentCharacter ?? '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: resultColor, width: 3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Icon(won ? Icons.emoji_events : Icons.close,
            color: resultColor, size: 28),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'vs ${match.opponent}',
                style: GoogleFonts.spaceMono(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (eloChangeText.isNotEmpty)
              Text(eloChangeText,
                  style: GoogleFonts.spaceMono(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: eloChangeColor)),
          ],
        ),
        subtitle: Row(
          children: [
            Text('$myChar vs $oppChar',
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
            if (timeText.isNotEmpty) ...[
              const Text('  •  ',
                  style: TextStyle(color: Colors.white24, fontSize: 11)),
              Text(timeText,
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}
