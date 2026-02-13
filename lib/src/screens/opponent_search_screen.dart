import 'dart:async';
import 'package:flutter/material.dart';

import '../models/player.dart';
import '../services/api_service.dart';
import '../services/match_service.dart';
import 'match_screen.dart';

class OpponentSearchScreen extends StatefulWidget {
  const OpponentSearchScreen({super.key});

  @override
  State<OpponentSearchScreen> createState() => _OpponentSearchScreenState();
}

class _OpponentSearchScreenState extends State<OpponentSearchScreen> {
  final ApiService _apiService = ApiService();
  final MatchService _matchService = MatchService();

  // --- Search State ---
  final TextEditingController _searchController = TextEditingController();
  List<Player> _results = [];
  bool _isLoading = false;
  Timer? _debounce;

  // --- Check-In State ---
  bool _isCheckedIn = false;
  final TextEditingController _myUsernameController = TextEditingController();
  final TextEditingController _myCharacterController = TextEditingController();
  bool _isCheckingInOrOut = false;

  // --- WebSocket / Match State ---
  bool _wsConnected = false;
  bool _isChallenging = false; // shows spinner when sending invite
  String? _pendingInviteTarget; // who we challenged (waiting for accept)

  // Subscriptions
  StreamSubscription<InvitePayload>? _inviteSub;
  StreamSubscription<MatchUpdateEvent>? _matchUpdateSub;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<String>? _errorSub;

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  void _setupListeners() {
    // --- Connection status ---
    _connectionSub = _matchService.onConnectionChanged.listen((connected) {
      if (!mounted) return;
      setState(() => _wsConnected = connected);
    });

    // --- Incoming invites → show modal ---
    _inviteSub = _matchService.onInviteReceived.listen((invite) {
      if (!mounted) return;
      _showInviteDialog(invite);
    });

    // --- Match lifecycle events ---
    _matchUpdateSub = _matchService.onMatchUpdate.listen((event) {
      if (!mounted) return;

      if (event.status == 'STARTED') {
        // Navigate to the match screen
        setState(() {
          _pendingInviteTarget = null;
          _isChallenging = false;
        });
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MatchScreen(
              matchId: event.matchId!,
              opponentUsername: _matchService.activeOpponent!,
            ),
          ),
        );
      }

      if (event.status == 'DECLINED') {
        setState(() {
          _pendingInviteTarget = null;
          _isChallenging = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Challenge was declined.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });

    // --- Errors ---
    _errorSub = _matchService.onError.listen((msg) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _myUsernameController.dispose();
    _myCharacterController.dispose();
    _inviteSub?.cancel();
    _matchUpdateSub?.cancel();
    _connectionSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Check In — also connects WebSocket
  // ---------------------------------------------------------------------------
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

    final success = await _apiService.checkIn(username, character, 1200);

    if (!mounted) return;

    if (success) {
      setState(() {
        _isCheckedIn = true;
        _isCheckingInOrOut = false;
      });

      // Connect WebSocket now that we have an identity
      _matchService.connect(username);
    } else {
      setState(() => _isCheckingInOrOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to check in')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Check Out — disconnects WebSocket
  // ---------------------------------------------------------------------------
  Future<void> _handleCheckOut() async {
    setState(() => _isCheckingInOrOut = true);

    final success = await _apiService.checkOut(
      _myUsernameController.text.trim(),
      _myCharacterController.text.trim(),
      1200,
    );

    if (!mounted) return;
    setState(() => _isCheckingInOrOut = false);

    if (success) {
      _matchService.disconnect();
      setState(() {
        _isCheckedIn = false;
        _wsConnected = false;
        _results.clear();
        _searchController.clear();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to check out')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------
  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (query.trim().isEmpty) {
        setState(() => _results.clear());
        return;
      }
      _performSearch(query.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isLoading = true);

    final results = await _apiService.searchActivePlayers(query);

    if (!mounted) return;
    setState(() {
      _results = results;
      _isLoading = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Challenge — tap a search result to send invite
  // ---------------------------------------------------------------------------
  Future<void> _sendChallenge(Player opponent) async {
    if (!_wsConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WebSocket not connected yet')),
      );
      return;
    }

    // Don't challenge yourself
    if (opponent.username == _matchService.myUsername) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can't challenge yourself!")),
      );
      return;
    }

    setState(() {
      _isChallenging = true;
      _pendingInviteTarget = opponent.username;
    });

    final inviteId = await _matchService.sendInvite(opponent.username);

    if (!mounted) return;

    if (inviteId == null) {
      setState(() {
        _isChallenging = false;
        _pendingInviteTarget = null;
      });
    } else {
      // Invite sent — we stay in "waiting" state until STARTED or DECLINED
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Challenge sent to ${opponent.username}!'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Invite Received Dialog
  // ---------------------------------------------------------------------------
  void _showInviteDialog(InvitePayload invite) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Challenge Received!'),
        content: Text('${invite.from} wants to fight!'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _matchService.declineInvite(invite.inviteId, invite.from);
            },
            child: const Text('Decline', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _matchService.acceptInvite(invite.inviteId, invite.from);
              // The STARTED event will trigger navigation via the listener
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // --- Connection indicator ---
          if (_isCheckedIn)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: _wsConnected
                    ? Colors.green.withOpacity(0.15)
                    : Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _wsConnected ? Icons.wifi : Icons.wifi_off,
                    size: 16,
                    color: _wsConnected ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _wsConnected
                        ? 'Connected as ${_matchService.myUsername}'
                        : 'Connecting...',
                    style: TextStyle(
                      color: _wsConnected ? Colors.green : Colors.orange,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

          // --- Waiting indicator (after sending challenge) ---
          if (_pendingInviteTarget != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Waiting for $_pendingInviteTarget to respond...',
                    style: const TextStyle(color: Colors.blue, fontSize: 13),
                  ),
                ],
              ),
            ),

          // --- Check-In Card ---
          if (!_isCheckedIn) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Check In to Play',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _myUsernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                        hintText: 'e.g. mew2king',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _myCharacterController,
                      decoration: const InputDecoration(
                        labelText: 'Character',
                        border: OutlineInputBorder(),
                        hintText: 'e.g. Marth',
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _isCheckingInOrOut ? null : _handleCheckIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFBD0910),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _isCheckingInOrOut
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Check In',
                              style: TextStyle(fontSize: 16)),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            // --- Checked-in: show search + check-out ---
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: const InputDecoration(
                      hintText: 'Search for your opponent...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _isCheckingInOrOut ? null : _handleCheckOut,
                  child: const Text('Check Out',
                      style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // --- Results ---
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              )
            else
              Expanded(
                child: _results.isEmpty
                    ? Center(
                        child: Text(
                          _searchController.text.isEmpty
                              ? 'Search for your opponent above'
                              : 'No players found',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final player = _results[index];
                          final isMe =
                              player.username == _matchService.myUsername;
                          final isTarget =
                              player.username == _pendingInviteTarget;

                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isMe
                                    ? Colors.grey
                                    : const Color(0xFFBD0910),
                                child: Text(
                                  player.username[0].toUpperCase(),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(
                                player.username,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(player.character),
                              trailing: isMe
                                  ? const Chip(label: Text('You'))
                                  : isTarget
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : ElevatedButton(
                                          onPressed: (_isChallenging)
                                              ? null
                                              : () => _sendChallenge(player),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFFBD0910),
                                            foregroundColor: Colors.white,
                                          ),
                                          child: const Text('Challenge'),
                                        ),
                            ),
                          );
                        },
                      ),
              ),
          ],
        ],
      ),
    );
  }
}
