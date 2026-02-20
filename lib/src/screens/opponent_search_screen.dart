import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

import '../models/player.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/match_service.dart';
import '../util/characters_util.dart';
import 'match_screen.dart';

class OpponentSearchScreen extends StatefulWidget {
  const OpponentSearchScreen({super.key});

  @override
  State<OpponentSearchScreen> createState() => _OpponentSearchScreenState();
}

class _OpponentSearchScreenState extends State<OpponentSearchScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final MatchService _matchService = MatchService();

  // --- Search State ---
  final TextEditingController _searchController = TextEditingController();
  List<Player> _results = [];
  bool _isLoading = false;
  Timer? _debounce;

  // --- Check-In State ---
  bool _isCheckedIn = false;
  String? selectedCharacter;
  bool _isCheckingInOrOut = false;

  // --- WebSocket / Match State ---
  bool _wsConnected = false;
  bool _isChallenging = false;
  String? _pendingInviteId;
  String? _pendingInviteTarget;

  // --- Dialog tracking ---
  bool _isPendingOverlayShowing = false;
  bool _isInviteDialogShowing = false;

  // Subscriptions
  StreamSubscription<InvitePayload>? _inviteSub;
  StreamSubscription<MatchUpdateEvent>? _matchUpdateSub;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<String>? _errorSub;

  late final List<DropdownMenuItem<String>> _dropdownCharacterItems;

  /// The logged-in user's username, from AuthService.
  String get _myUsername => _authService.username ?? '';

  @override
  void initState() {
    super.initState();
    _dropdownCharacterItems = CharactersUtil.getCharacterDropdownItems();
    _setupListeners();
  }

  void _setupListeners() {
    _connectionSub = _matchService.onConnectionChanged.listen((connected) {
      if (!mounted) return;
      setState(() => _wsConnected = connected);
    });

    _inviteSub = _matchService.onInviteReceived.listen((invite) {
      if (!mounted) return;

      if (invite.status == 'PENDING') {
        _showInviteDialog(invite);
      } else if (invite.status == 'CANCELLED') {
        _dismissInviteDialog();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${invite.from} cancelled their challenge.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });

    _matchUpdateSub = _matchService.onMatchUpdate.listen((event) {
      if (!mounted) return;

      if (event.status == 'STARTED') {
        // Dismiss whichever dialog is showing
        _dismissPendingOverlay();
        _dismissInviteDialog();
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
        _dismissPendingOverlay();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Challenge was declined.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });

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
    _inviteSub?.cancel();
    _matchUpdateSub?.cancel();
    _connectionSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Check In — no more username text field, uses AuthService.username
  // ---------------------------------------------------------------------------
  Future<void> _handleCheckIn() async {
    final username = _myUsername;
    final character = selectedCharacter?.trim() ?? '';

    if (character.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a character')),
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
      // Phase 4: connect() reads username and token from AuthService
      _matchService.connect();
    } else {
      setState(() => _isCheckingInOrOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to check in')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Check Out
  // ---------------------------------------------------------------------------
  Future<void> _handleCheckOut() async {
    setState(() => _isCheckingInOrOut = true);

    final success = await _apiService.checkOut(
      _myUsername,
      selectedCharacter?.trim() ?? '',
      1200,
    );

    if (!mounted) return;

    _matchService.disconnect();
    setState(() {
      _isCheckedIn = false;
      _isCheckingInOrOut = false;
      _results = [];
      _searchController.clear();
    });
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------
  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isLoading = true);
    final results = await _apiService.searchActivePlayers(query);
    if (!mounted) return;

    // Exclude the current user from the results (case-insensitive).
    final myLower = _myUsername.toLowerCase();
    final filtered =
        results.where((p) => p.username.toLowerCase() != myLower).toList();

    setState(() {
      _results = filtered;
      _isLoading = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Challenge
  // ---------------------------------------------------------------------------
  Future<void> _sendChallenge(Player opponent) async {
    setState(() => _isChallenging = true);

    final inviteId = await _matchService.sendChallenge(opponent.username);

    if (!mounted) return;

    if (inviteId != null) {
      _pendingInviteId = inviteId;
      _pendingInviteTarget = opponent.username;
      _showPendingOverlay(opponent.username, inviteId);
    }

    setState(() => _isChallenging = false);
  }

  // ---------------------------------------------------------------------------
  // Pending Overlay (waiting for opponent response)
  // ---------------------------------------------------------------------------
  void _showPendingOverlay(String opponentUsername, String inviteId) {
    _isPendingOverlayShowing = true;
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      pageBuilder: (context, anim1, anim2) {
        return PopScope(
          canPop: false,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Center(
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text('Waiting for $opponentUsername to respond...'),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () {
                          if (!_isPendingOverlayShowing) return;
                          _isPendingOverlayShowing = false;
                          Navigator.of(context, rootNavigator: true).pop();
                          _matchService.cancelChallenge(
                              inviteId, opponentUsername);
                        },
                        child: const Text('Cancel',
                            style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ).then((_) {
      _isPendingOverlayShowing = false;
    });
  }

  void _dismissPendingOverlay() {
    if (_isPendingOverlayShowing && mounted) {
      _isPendingOverlayShowing = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  // ---------------------------------------------------------------------------
  // Invite Dialog (incoming challenge)
  // ---------------------------------------------------------------------------
  void _showInviteDialog(InvitePayload invite) {
    _isInviteDialogShowing = true;
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      pageBuilder: (dialogContext, anim1, anim2) {
        return PopScope(
          canPop: false,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Center(
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sports_esports,
                          size: 48, color: Color(0xFFBD0910)),
                      const SizedBox(height: 12),
                      Text(
                        '${invite.from} wants to battle!',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                if (!_isInviteDialogShowing) return;
                                _isInviteDialogShowing = false;
                                Navigator.of(dialogContext).pop();
                                _matchService.declineChallenge(
                                    invite.inviteId, invite.from);
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Decline',
                                  style: TextStyle(fontSize: 16)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                if (!_isInviteDialogShowing) return;
                                _isInviteDialogShowing = false;
                                Navigator.of(dialogContext).pop();
                                _matchService.acceptChallenge(
                                    invite.inviteId, invite.from);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Accept',
                                  style: TextStyle(fontSize: 16)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ).then((_) {
      _isInviteDialogShowing = false;
    });
  }

  void _dismissInviteDialog() {
    if (_isInviteDialogShowing && mounted) {
      _isInviteDialogShowing = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
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
                        ? 'Connected as $_myUsername'
                        : 'Connecting...',
                    style: TextStyle(
                      color: _wsConnected ? Colors.green : Colors.orange,
                      fontSize: 13,
                    ),
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
                    Text(
                      'Check In as $_myUsername',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    // Phase 4: No username text field — identity from auth
                    DropdownButton<String>(
                      value: selectedCharacter,
                      hint: const Text('Select Character'),
                      isExpanded: true,
                      menuMaxHeight: MediaQuery.of(context).size.height * 0.4,
                      onChanged: (String? newValue) {
                        setState(() {
                          selectedCharacter = newValue;
                        });
                      },
                      items: _dropdownCharacterItems,
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
                              ? 'Search for an opponent by name'
                              : 'No players found',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final player = _results[index];
                          return ListTile(
                            leading: const Icon(Icons.person),
                            title: Text(player.username),
                            subtitle: Text(player.character),
                            trailing: ElevatedButton(
                              onPressed: _isChallenging
                                  ? null
                                  : () => _sendChallenge(player),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFBD0910),
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Challenge'),
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
