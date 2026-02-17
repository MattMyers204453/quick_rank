import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

import '../models/player.dart';
import '../services/api_service.dart';
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
  final MatchService _matchService = MatchService();

  // --- Search State ---
  final TextEditingController _searchController = TextEditingController();
  List<Player> _results = [];
  bool _isLoading = false;
  Timer? _debounce;

  // --- Check-In State ---
  bool _isCheckedIn = false;
  final TextEditingController _myUsernameController = TextEditingController();
  String? selectedCharacter;
  bool _isCheckingInOrOut = false;

  // --- WebSocket / Match State ---
  bool _wsConnected = false;
  bool _isChallenging = false;
  String? _pendingInviteId;
  String? _pendingInviteTarget;

  // --- Dialog tracking (both use showGeneralDialog + rootNavigator pop) ---
  bool _isPendingOverlayShowing = false;
  bool _isInviteDialogShowing = false;

  // Subscriptions
  StreamSubscription<InvitePayload>? _inviteSub;
  StreamSubscription<MatchUpdateEvent>? _matchUpdateSub;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<String>? _errorSub;

  late final List<DropdownMenuItem<String>> _dropdownCharacterItems;

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
    _myUsernameController.dispose();
    _inviteSub?.cancel();
    _matchUpdateSub?.cancel();
    _connectionSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Check In
  // ---------------------------------------------------------------------------
  Future<void> _handleCheckIn() async {
    final username = _myUsernameController.text.trim();
    final character = selectedCharacter?.trim() ?? '';

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
      _matchService.connect(username);
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
      _myUsernameController.text.trim(),
      selectedCharacter?.trim() ?? '',
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
        selectedCharacter = null;
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
  // Challenge
  // ---------------------------------------------------------------------------
  Future<void> _sendChallenge(Player opponent) async {
    if (!_wsConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WebSocket not connected yet')),
      );
      return;
    }

    if (opponent.username == _matchService.myUsername) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can't challenge yourself!")),
      );
      return;
    }

    setState(() => _isChallenging = true);

    final inviteId = await _matchService.sendInvite(opponent.username);

    if (!mounted) return;
    setState(() => _isChallenging = false);

    if (inviteId != null) {
      _pendingInviteId = inviteId;
      _pendingInviteTarget = opponent.username;
      _showPendingOverlay();
    }
  }

  // ---------------------------------------------------------------------------
  // Pending Overlay — challenger's full-screen blur (covers nav bar)
  // ---------------------------------------------------------------------------
  void _showPendingOverlay() {
    if (_isPendingOverlayShowing) return;
    _isPendingOverlayShowing = true;
    final target = _pendingInviteTarget!;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      pageBuilder: (dialogContext, _, __) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            color: Colors.black.withOpacity(0.4),
            child: Center(
              child: Card(
                elevation: 12,
                margin: const EdgeInsets.symmetric(horizontal: 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sports_esports,
                          size: 56, color: Color(0xFFBD0910)),
                      const SizedBox(height: 20),
                      const Text(
                        'Challenge Sent!',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Waiting for $target\nto accept...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[400],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            final inviteId = _pendingInviteId;
                            final opponent = _pendingInviteTarget;
                            _pendingInviteId = null;
                            _pendingInviteTarget = null;
                            Navigator.of(dialogContext).pop();
                            if (inviteId != null && opponent != null) {
                              _matchService.cancelInvite(inviteId, opponent);
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Cancel Challenge',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
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
    _pendingInviteId = null;
    _pendingInviteTarget = null;
    if (_isPendingOverlayShowing && mounted) {
      _isPendingOverlayShowing = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  // ---------------------------------------------------------------------------
  // Invite Dialog — opponent receives a challenge
  //
  // Uses showGeneralDialog (same mechanism as the pending overlay) so that
  // dismissal via Navigator.of(context, rootNavigator: true).pop() is reliable.
  // ---------------------------------------------------------------------------
  void _showInviteDialog(InvitePayload invite) {
    if (_isInviteDialogShowing) return;
    _isInviteDialogShowing = true;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (dialogContext, _, __) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.local_fire_department,
                      size: 48, color: Colors.orange),
                  const SizedBox(height: 16),
                  const Text(
                    'Challenge Received!',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${invite.from} wants to fight!',
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            if (!_isInviteDialogShowing) return;
                            _isInviteDialogShowing = false;
                            Navigator.of(dialogContext).pop();
                            _matchService.declineInvite(
                                invite.inviteId, invite.from);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 14),
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
                            _matchService.acceptInvite(
                                invite.inviteId, invite.from);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
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
                    // TextField(
                    //   controller: _myCharacterController,
                    //   decoration: const InputDecoration(
                    //     labelText: 'Character',
                    //     border: OutlineInputBorder(),
                    //     hintText: 'e.g. Marth',
                    //   ),
                    // ),
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
                                  : ElevatedButton(
                                      onPressed: _isChallenging
                                          ? null
                                          : () => _sendChallenge(player),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFFBD0910),
                                        foregroundColor: Colors.white,
                                      ),
                                      child: _isChallenging
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text('Challenge'),
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
