import 'dart:async';
import 'package:flutter/material.dart';
import '../services/match_service.dart';

enum MatchPhase {
  playing, // Both players see "I Won" / "I Lost"
  waitingForConfirm, // Reporter's view: waiting for opponent + countdown
  confirming, // Opponent's view: see claim + "I Won" / "I Lost" + countdown
  ended, // Match finalized (players agreed)
  disputed, // Match finalized (players disagreed)
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

  // --- Confirmation state (populated on AWAITING_CONFIRMATION) ---
  String? _reporterUsername;
  String? _claimedWinner;

  // --- Countdown ---
  static const int _confirmTimeoutSeconds = 20;
  int _secondsRemaining = _confirmTimeoutSeconds;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();

    _matchSub = _matchService.onMatchUpdate.listen((event) {
      if (event.matchId != widget.matchId) return;
      if (!mounted) return;

      switch (event.status) {
        case 'AWAITING_CONFIRMATION':
          _reporterUsername = event.reporterUsername;
          _claimedWinner = event.claimedWinner;

          final bool iAmReporter =
              event.reporterUsername == _matchService.myUsername;

          setState(() {
            _phase = iAmReporter
                ? MatchPhase.waitingForConfirm
                : MatchPhase.confirming;
            _isSubmitting = false;
          });

          _startCountdown();
          break;

        case 'ENDED':
          _countdownTimer?.cancel();
          setState(() => _phase = MatchPhase.ended);
          _popAfterDelay();
          break;

        case 'DISPUTED':
          _countdownTimer?.cancel();
          setState(() => _phase = MatchPhase.disputed);
          _popAfterDelay();
          break;
      }
    });
  }

  @override
  void dispose() {
    _matchSub?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Countdown
  // ---------------------------------------------------------------------------
  void _startCountdown() {
    _countdownTimer?.cancel();
    _secondsRemaining = _confirmTimeoutSeconds;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsRemaining--);
      if (_secondsRemaining <= 0) {
        timer.cancel();
        _handleTimeout();
      }
    });
  }

  void _handleTimeout() {
    if (_phase == MatchPhase.confirming && _claimedWinner != null) {
      // Auto-confirm: agree with the reporter's claim
      _matchService.confirmResult(widget.matchId, _claimedWinner!);
    }
    // If we're the reporter (waitingForConfirm), the opponent's client
    // handles the auto-confirm. We just keep waiting.
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// First report: either player taps "I Won" or "I Lost" during playing phase.
  Future<void> _report(String claimedWinner) async {
    setState(() => _isSubmitting = true);
    await _matchService.reportResult(widget.matchId, claimedWinner);
    // Don't reset _isSubmitting — the AWAITING_CONFIRMATION event will
    // transition the phase, which rebuilds the entire view.
  }

  /// Confirmation: the non-reporter taps "I Won" or "I Lost" during confirming phase.
  Future<void> _confirm(String claimedWinner) async {
    _countdownTimer?.cancel();
    setState(() => _isSubmitting = true);
    await _matchService.confirmResult(widget.matchId, claimedWinner);
    // ENDED or DISPUTED event will transition the phase.
  }

  void _popAfterDelay() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Match'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: _buildPhaseContent(),
        ),
      ),
    );
  }

  Widget _buildPhaseContent() {
    switch (_phase) {
      case MatchPhase.playing:
        return _buildPlayingView();
      case MatchPhase.waitingForConfirm:
        return _buildWaitingView();
      case MatchPhase.confirming:
        return _buildConfirmingView();
      case MatchPhase.ended:
        return _buildEndedView();
      case MatchPhase.disputed:
        return _buildDisputedView();
    }
  }

  // ===========================================================================
  // PLAYING — Both players see "I Won" / "I Lost"
  // ===========================================================================
  Widget _buildPlayingView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.sports_esports, size: 80, color: Color(0xFFBD0910)),
        const SizedBox(height: 24),
        const Text('Match In Progress',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('vs ${widget.opponentUsername}',
            style: TextStyle(fontSize: 20, color: Colors.grey[400])),
        const SizedBox(height: 8),
        _buildMatchIdLabel(),
        const SizedBox(height: 48),
        const Text('Report the result:', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 16),
        _buildWinLossButtons(
          onWin: () => _report(_matchService.myUsername!),
          onLoss: () => _report(widget.opponentUsername),
          disabled: _isSubmitting,
        ),
        if (_isSubmitting) ...[
          const SizedBox(height: 24),
          const CircularProgressIndicator(),
          const SizedBox(height: 8),
          const Text('Submitting...'),
        ],
      ],
    );
  }

  // ===========================================================================
  // WAITING — Reporter sees countdown while opponent confirms
  // ===========================================================================
  Widget _buildWaitingView() {
    // What did I report?
    final bool iClaimedWin = _claimedWinner == _matchService.myUsername;
    final String myReport = iClaimedWin
        ? 'You reported: You won'
        : 'You reported: ${widget.opponentUsername} won';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.hourglass_top, size: 80, color: Colors.orange),
        const SizedBox(height: 24),
        const Text('Awaiting Confirmation',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(myReport, style: TextStyle(fontSize: 16, color: Colors.grey[400])),
        const SizedBox(height: 8),
        Text('Waiting for ${widget.opponentUsername} to respond...',
            style: TextStyle(fontSize: 14, color: Colors.grey[500])),
        const SizedBox(height: 32),
        _buildCountdownRing(),
        const SizedBox(height: 16),
        Text(
          'If no response, your result stands.',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
      ],
    );
  }

  // ===========================================================================
  // CONFIRMING — Opponent sees the claim and picks "I Won" / "I Lost"
  // ===========================================================================
  Widget _buildConfirmingView() {
    // Describe the reporter's claim in relatable terms
    final String claimDescription;
    if (_claimedWinner == _reporterUsername) {
      claimDescription = '$_reporterUsername says they won.';
    } else {
      claimDescription = '$_reporterUsername says you won.';
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.how_to_vote, size: 80, color: Colors.orange),
        const SizedBox(height: 24),
        const Text('Confirm the Result',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        // Show what the reporter claimed
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: Text(
            claimDescription,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.orange),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Select the match outcome:', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 16),
        _buildWinLossButtons(
          onWin: () => _confirm(_matchService.myUsername!),
          onLoss: () => _confirm(widget.opponentUsername),
          disabled: _isSubmitting,
        ),
        if (_isSubmitting) ...[
          const SizedBox(height: 24),
          const CircularProgressIndicator(),
        ],
        const SizedBox(height: 32),
        _buildCountdownRing(),
        const SizedBox(height: 8),
        Text(
          'Auto-accepts in $_secondsRemaining seconds',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
      ],
    );
  }

  // ===========================================================================
  // ENDED — Both players agreed
  // ===========================================================================
  Widget _buildEndedView() {
    final String winnerDisplay;
    if (_claimedWinner == _matchService.myUsername) {
      winnerDisplay = 'You won!';
    } else if (_claimedWinner == widget.opponentUsername) {
      winnerDisplay = '${widget.opponentUsername} won.';
    } else {
      winnerDisplay = 'Match complete.';
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, size: 80, color: Colors.green),
        const SizedBox(height: 24),
        const Text('Match Complete',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(winnerDisplay,
            style: TextStyle(fontSize: 18, color: Colors.grey[400])),
        const SizedBox(height: 24),
        const Text('Returning to lobby...',
            style: TextStyle(color: Colors.green)),
      ],
    );
  }

  // ===========================================================================
  // DISPUTED — Players disagreed
  // ===========================================================================
  Widget _buildDisputedView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.warning_amber_rounded, size: 80, color: Colors.red),
        const SizedBox(height: 24),
        const Text('Result Disputed',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'You and ${widget.opponentUsername} reported different outcomes.\nThis match has been flagged for review.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey[400]),
        ),
        const SizedBox(height: 24),
        const Text('Returning to lobby...',
            style: TextStyle(color: Colors.red)),
      ],
    );
  }

  // ===========================================================================
  // Shared widgets
  // ===========================================================================

  Widget _buildWinLossButtons({
    required VoidCallback onWin,
    required VoidCallback onLoss,
    required bool disabled,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ElevatedButton.icon(
              onPressed: disabled ? null : onWin,
              icon: const Icon(Icons.emoji_events),
              label: const Text('I Won'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ElevatedButton.icon(
              onPressed: disabled ? null : onLoss,
              icon: const Icon(Icons.sentiment_dissatisfied),
              label: const Text('I Lost'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCountdownRing() {
    final double progress = _secondsRemaining / _confirmTimeoutSeconds;
    final Color ringColor = _secondsRemaining > 5 ? Colors.orange : Colors.red;

    return SizedBox(
      width: 90,
      height: 90,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 6,
            backgroundColor: Colors.grey[800],
            valueColor: AlwaysStoppedAnimation<Color>(ringColor),
          ),
          Center(
            child: Text(
              '$_secondsRemaining',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: ringColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchIdLabel() {
    return Text(
      'Match: ${widget.matchId.substring(0, 8)}...',
      style: TextStyle(
        fontSize: 12,
        color: Colors.grey[600],
        fontFamily: 'monospace',
      ),
    );
  }
}
