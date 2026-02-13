import 'dart:async';
import 'package:flutter/material.dart';
import '../services/match_service.dart';

/// Screen shown when a match is active (after both players accept).
/// Displays the opponent name and "I Won" / "I Lost" buttons.
class MatchScreen extends StatefulWidget {
  final String matchId;
  final String opponentUsername;

  const MatchScreen({
    super.key,
    required this.matchId,
    required this.opponentUsername,
  });

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  final MatchService _matchService = MatchService();
  StreamSubscription<MatchUpdateEvent>? _matchSub;
  bool _isReporting = false;
  bool _matchEnded = false;

  @override
  void initState() {
    super.initState();

    // Listen for the ENDED event from the server (in case the OTHER player
    // reports first, or if we want confirmation of our own report).
    _matchSub = _matchService.onMatchUpdate.listen((event) {
      if (event.matchId == widget.matchId && event.status == 'ENDED') {
        if (!mounted) return;
        setState(() => _matchEnded = true);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Match result recorded!'),
            backgroundColor: Colors.green,
          ),
        );

        // Pop back to main screen after a short delay
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    });
  }

  @override
  void dispose() {
    _matchSub?.cancel();
    super.dispose();
  }

  Future<void> _reportWin() async {
    setState(() => _isReporting = true);
    await _matchService.reportResult(
      widget.matchId,
      _matchService.myUsername!, // I won → I am the winner
    );
    if (mounted) setState(() => _isReporting = false);
  }

  Future<void> _reportLoss() async {
    setState(() => _isReporting = true);
    await _matchService.reportResult(
      widget.matchId,
      widget.opponentUsername, // I lost → opponent is the winner
    );
    if (mounted) setState(() => _isReporting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Match'),
        automaticallyImplyLeading: false, // No back button during match
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // --- Match status icon ---
              Icon(
                _matchEnded ? Icons.check_circle : Icons.sports_esports,
                size: 80,
                color: _matchEnded ? Colors.green : const Color(0xFFBD0910),
              ),
              const SizedBox(height: 24),

              // --- Title ---
              Text(
                _matchEnded ? 'Match Complete' : 'Match In Progress',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // --- Opponent ---
              Text(
                'vs ${widget.opponentUsername}',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.grey[400],
                ),
              ),
              const SizedBox(height: 8),

              // --- Match ID (small, for debugging) ---
              Text(
                'Match: ${widget.matchId.substring(0, 8)}...',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 48),

              // --- Report buttons ---
              if (!_matchEnded) ...[
                const Text(
                  'Report the result:',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // I Won
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: ElevatedButton.icon(
                          onPressed: _isReporting ? null : _reportWin,
                          icon: const Icon(Icons.emoji_events),
                          label: const Text('I Won'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[700],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            textStyle: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // I Lost
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: ElevatedButton.icon(
                          onPressed: _isReporting ? null : _reportLoss,
                          icon: const Icon(Icons.sentiment_dissatisfied),
                          label: const Text('I Lost'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[700],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            textStyle: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              if (_isReporting) ...[
                const SizedBox(height: 24),
                const CircularProgressIndicator(),
                const SizedBox(height: 8),
                const Text('Submitting result...'),
              ],

              if (_matchEnded) ...[
                const SizedBox(height: 24),
                const Text(
                  'Returning to lobby...',
                  style: TextStyle(color: Colors.green),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
