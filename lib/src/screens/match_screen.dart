import 'dart:async';
import 'package:flutter/material.dart';
import '../services/match_service.dart';

enum MatchPhase {
  playing, // Both players see "I Won" / "I Lost"
  waitingForConfirm, // Reporter's view: waiting for opponent + countdown
  confirming, // Opponent's view: see claim + "I Won" / "I Lost" + countdown
  rematchOffer, // Both players see result + "Rematch" / "Leave" + countdown
}

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

  // --- Phase state ---
  MatchPhase _phase = MatchPhase.playing;
  bool _isSubmitting = false;

  // --- Current match tracking (may change on rematch) ---
  late String _currentMatchId;
  late String _currentOpponent;

  // --- Confirmation state (populated on AWAITING_CONFIRMATION) ---
  String? _reporterUsername;
  String? _claimedWinner;

  // --- Rematch state (populated on REMATCH_OFFERED) ---
  String? _matchResult; // "COMPLETED" or "DISPUTED"
  String? _matchWinner; // winner username or null if disputed
  bool _rematchWaiting =
      false; // true if this player accepted, waiting for opponent

  // --- Countdown (shared between confirmation and rematch phases) ---
  static const int _confirmTimeoutSeconds = 20;
  static const int _rematchTimeoutSeconds = 15;
  int _secondsRemaining = _confirmTimeoutSeconds;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _currentMatchId = widget.matchId;
    _currentOpponent = widget.opponentUsername;

    _matchSub = _matchService.onMatchUpdate.listen(_handleMatchEvent);
  }

  @override
  void dispose() {
    _matchSub?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  // ===========================================================================
  // Event Handler — Central routing for all match-update events
  // ===========================================================================
  void _handleMatchEvent(MatchUpdateEvent event) {
    if (!mounted) return;

    switch (event.status) {
      // --- Confirmation phase ---
      case 'AWAITING_CONFIRMATION':
        if (event.matchId != _currentMatchId) return;
        _reporterUsername = event.reporterUsername;
        _claimedWinner = event.claimedWinner;

        final bool iAmReporter =
            event.reporterUsername == _matchService.myUsername;

        setState(() {
          _phase = iAmReporter
              ? MatchPhase.waitingForConfirm
              : MatchPhase.confirming;
        });
        _startCountdown(_confirmTimeoutSeconds, _onConfirmTimeout);
        break;

      // --- Rematch offered (replaces ENDED / DISPUTED) ---
      case 'REMATCH_OFFERED':
        if (event.matchId != _currentMatchId) return;
        _countdownTimer?.cancel();

        setState(() {
          _matchResult = event.result;
          _matchWinner = event.claimedWinner;
          _rematchWaiting = false;
          _isSubmitting = false;
          _phase = MatchPhase.rematchOffer;
        });
        _startCountdown(_rematchTimeoutSeconds, _onRematchTimeout);
        break;

      // --- Rematch: this player accepted, waiting for opponent ---
      case 'REMATCH_WAITING':
        if (event.matchId != _currentMatchId) return;
        setState(() {
          _rematchWaiting = true;
        });
        break;

      // --- Rematch declined: pop back to lobby ---
      case 'REMATCH_DECLINED':
        if (event.matchId != _currentMatchId) return;
        _countdownTimer?.cancel();
        if (mounted) {
          Navigator.of(context).pop();
        }
        break;

      // --- Match started (new match or rematch accepted) ---
      case 'STARTED':
        _countdownTimer?.cancel();
        // Reset for new match — could be the initial start or a rematch
        setState(() {
          _currentMatchId = event.matchId!;
          _currentOpponent = event.player1 == _matchService.myUsername
              ? event.player2
              : event.player1;
          _phase = MatchPhase.playing;
          _isSubmitting = false;
          _reporterUsername = null;
          _claimedWinner = null;
          _matchResult = null;
          _matchWinner = null;
          _rematchWaiting = false;
        });
        break;
    }
  }

  // ===========================================================================
  // Countdown logic
  // ===========================================================================
  void _startCountdown(int seconds, VoidCallback onTimeout) {
    _countdownTimer?.cancel();
    _secondsRemaining = seconds;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _secondsRemaining--;
      });
      if (_secondsRemaining <= 0) {
        timer.cancel();
        onTimeout();
      }
    });
  }

  void _onConfirmTimeout() {
    // Auto-agree with reporter's claim
    if (_phase == MatchPhase.confirming && _claimedWinner != null) {
      _matchService.confirmResult(_currentMatchId, _claimedWinner!);
    }
  }

  void _onRematchTimeout() {
    // Auto-decline rematch
    if (_phase == MatchPhase.rematchOffer && !_rematchWaiting) {
      _matchService.requestRematch(_currentMatchId, false);
    }
  }

  // ===========================================================================
  // Player actions
  // ===========================================================================

  /// Phase 1 (playing): First player reports who won.
  Future<void> _reportWinner(String winnerUsername) async {
    setState(() => _isSubmitting = true);
    final success =
        await _matchService.reportResult(_currentMatchId, winnerUsername);
    if (!success && mounted) {
      setState(() => _isSubmitting = false);
    }
  }

  /// Phase 3 (confirming): Second player submits their independent claim.
  Future<void> _confirmWinner(String winnerUsername) async {
    setState(() => _isSubmitting = true);
    _countdownTimer?.cancel();
    await _matchService.confirmResult(_currentMatchId, winnerUsername);
    // Don't reset _isSubmitting — REMATCH_OFFERED event will handle transition
  }

  /// Phase 6 (rematchOffer): Player taps Rematch or Leave.
  Future<void> _respondRematch(bool accept) async {
    setState(() => _isSubmitting = true);
    if (!accept) {
      _countdownTimer?.cancel();
    }
    await _matchService.requestRematch(_currentMatchId, accept);
    if (!accept && mounted) {
      // If decline, server sends REMATCH_DECLINED which pops us back.
      // But if the HTTP call itself fails, re-enable buttons.
      setState(() => _isSubmitting = false);
    }
  }

  // ===========================================================================
  // UI Build
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('vs $_currentOpponent'),
        automaticallyImplyLeading: false, // no back button during match
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _buildPhaseContent(),
        ),
      ),
    );
  }

  Widget _buildPhaseContent() {
    switch (_phase) {
      case MatchPhase.playing:
        return _buildPlayingPhase();
      case MatchPhase.waitingForConfirm:
        return _buildWaitingPhase();
      case MatchPhase.confirming:
        return _buildConfirmingPhase();
      case MatchPhase.rematchOffer:
        return _buildRematchPhase();
    }
  }

  // --- Phase 1: Playing ---
  Widget _buildPlayingPhase() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.sports_esports, size: 64, color: Colors.blueGrey),
        const SizedBox(height: 24),
        Text('Match in progress',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('Playing against $_currentOpponent',
            style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () => _reportWinner(_matchService.myUsername!),
                icon: const Icon(Icons.emoji_events),
                label: const Text('I Won'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () => _reportWinner(_currentOpponent),
                icon: const Icon(Icons.close),
                label: const Text('I Lost'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
        if (_isSubmitting) ...[
          const SizedBox(height: 16),
          const CircularProgressIndicator(),
        ],
      ],
    );
  }

  // --- Phase 2: Waiting for confirm (reporter's view) ---
  Widget _buildWaitingPhase() {
    final iClaimedWin = _claimedWinner == _matchService.myUsername;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCountdownRing(_confirmTimeoutSeconds),
        const SizedBox(height: 24),
        Text(
          iClaimedWin ? 'You reported: I Won' : 'You reported: I Lost',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text('Waiting for $_currentOpponent to confirm...',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: Colors.grey[600])),
      ],
    );
  }

  // --- Phase 3: Confirming (opponent's view) ---
  Widget _buildConfirmingPhase() {
    final reporterClaimedWin = _claimedWinner == _reporterUsername;
    final bannerText = reporterClaimedWin
        ? '$_reporterUsername says they won'
        : '$_reporterUsername says they lost';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCountdownRing(_confirmTimeoutSeconds),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              Text(bannerText,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade900)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('What was the result?',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () => _confirmWinner(_matchService.myUsername!),
                icon: const Icon(Icons.emoji_events),
                label: const Text('I Won'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () => _confirmWinner(_currentOpponent),
                icon: const Icon(Icons.close),
                label: const Text('I Lost'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- Phase 6: Rematch offer ---
  Widget _buildRematchPhase() {
    final isDisputed = _matchResult == 'DISPUTED';
    final iWon = _matchWinner == _matchService.myUsername;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Result display
        Icon(
          isDisputed
              ? Icons.warning_amber_rounded
              : (iWon ? Icons.emoji_events : Icons.close),
          size: 64,
          color:
              isDisputed ? Colors.orange : (iWon ? Colors.amber : Colors.red),
        ),
        const SizedBox(height: 16),
        Text(
          isDisputed ? 'Disputed' : (iWon ? 'You Won!' : 'You Lost'),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDisputed
                    ? Colors.orange
                    : (iWon ? Colors.green : Colors.red),
              ),
        ),
        if (isDisputed) ...[
          const SizedBox(height: 4),
          Text('No winner recorded',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey[600])),
        ],
        const SizedBox(height: 32),

        // Countdown
        _buildCountdownRing(_rematchTimeoutSeconds),
        const SizedBox(height: 24),

        // Rematch prompt
        if (_rematchWaiting) ...[
          Text('Waiting for $_currentOpponent...',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.grey[600])),
          const SizedBox(height: 16),
          const CircularProgressIndicator(),
        ] else ...[
          Text('Rematch?', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : () => _respondRematch(true),
                  icon: const Icon(Icons.replay),
                  label: const Text('Rematch'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed:
                      _isSubmitting ? null : () => _respondRematch(false),
                  icon: const Icon(Icons.exit_to_app),
                  label: const Text('Leave'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // --- Shared countdown ring widget ---
  Widget _buildCountdownRing(int totalSeconds) {
    final progress = totalSeconds > 0 ? _secondsRemaining / totalSeconds : 0.0;
    final color = _secondsRemaining > 5 ? Colors.blue : Colors.red;

    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 4,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
          Center(
            child: Text(
              '$_secondsRemaining',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
