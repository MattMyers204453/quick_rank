import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:stomp_dart_client/stomp_dart_client.dart';

import 'auth_service.dart';

// =============================================================================
// Data classes
// =============================================================================

class InvitePayload {
  final String inviteId;
  final String from;
  final String status; // PENDING, CANCELLED

  InvitePayload(
      {required this.inviteId, required this.from, required this.status});

  factory InvitePayload.fromJson(Map<String, dynamic> json) {
    return InvitePayload(
      inviteId: json['inviteId'] as String,
      from: json['from'] as String,
      status: json['status'] as String,
    );
  }
}

// =============================================================================
// match_service.dart — REPLACE MatchUpdateEvent class
// =============================================================================

class MatchUpdateEvent {
  final String? matchId;
  final String status;
  final String player1;
  final String player2;
  final String? reporterUsername;
  final String? claimedWinner;
  final String? result;

  // Elo fields (REMATCH_OFFERED with result=COMPLETED only)
  final int? player1EloDelta;
  final int? player2EloDelta;
  final int? player1NewElo;
  final int? player2NewElo;

  // Character fields (present on most events)
  final String? player1Character;
  final String? player2Character;

  MatchUpdateEvent({
    required this.matchId,
    required this.status,
    required this.player1,
    required this.player2,
    this.reporterUsername,
    this.claimedWinner,
    this.result,
    this.player1EloDelta,
    this.player2EloDelta,
    this.player1NewElo,
    this.player2NewElo,
    this.player1Character,
    this.player2Character,
  });

  factory MatchUpdateEvent.fromJson(Map<String, dynamic> json) {
    return MatchUpdateEvent(
      matchId: json['matchId'] as String?,
      status: json['status'] as String? ?? '',
      player1: json['player1'] as String? ?? '',
      player2: json['player2'] as String? ?? '',
      reporterUsername: json['reporterUsername'] as String?,
      claimedWinner: json['claimedWinner'] as String?,
      result: json['result'] as String?,
      player1EloDelta: (json['player1EloDelta'] as num?)?.toInt(),
      player2EloDelta: (json['player2EloDelta'] as num?)?.toInt(),
      player1NewElo: (json['player1NewElo'] as num?)?.toInt(),
      player2NewElo: (json['player2NewElo'] as num?)?.toInt(),
      player1Character: json['player1Character'] as String?,
      player2Character: json['player2Character'] as String?,
    );
  }

  /// Get Elo delta for a player by username.
  int? getEloDeltaForPlayer(String username) {
    if (username == player1) return player1EloDelta;
    if (username == player2) return player2EloDelta;
    return null;
  }

  /// Get new Elo for a player by username.
  int? getNewEloForPlayer(String username) {
    if (username == player1) return player1NewElo;
    if (username == player2) return player2NewElo;
    return null;
  }

  /// Get character for a player by username.
  String? getCharacterForPlayer(String username) {
    if (username == player1) return player1Character;
    if (username == player2) return player2Character;
    return null;
  }
}

// =============================================================================
// MatchService — Singleton
// =============================================================================

class MatchService {
  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------
  static final MatchService _instance = MatchService._internal();
  factory MatchService() => _instance;
  MatchService._internal();

  // ---------------------------------------------------------------------------
  // Configuration — toggle between local and Railway
  // ---------------------------------------------------------------------------
  // Production (Railway)
  static const String _wsBase =
      'wss://smashrank-api-production.up.railway.app/ws-smashrank';
  static const String _httpBase =
      'https://smashrank-api-production.up.railway.app/api';

  // Local development — uncomment these and comment out the above:
  // static const String _wsBase = 'ws://localhost:8080/ws-smashrank';
  // static const String _httpBase = 'http://localhost:8080/api';

  // ---------------------------------------------------------------------------
  // Dependencies
  // ---------------------------------------------------------------------------
  final AuthService _authService = AuthService();

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------
  StompClient? _stompClient;
  String? _myUsername;
  bool _isConnected = false;

  String? get myUsername => _myUsername;
  bool get isConnected => _isConnected;

  /// The current active match ID (set on STARTED, cleared on REMATCH_DECLINED).
  String? activeMatchId;

  /// The opponent username in the current active match.
  String? activeOpponent;

  // ---------------------------------------------------------------------------
  // Event streams — UI listens to these
  // ---------------------------------------------------------------------------
  final _inviteController = StreamController<InvitePayload>.broadcast();
  final _matchUpdateController = StreamController<MatchUpdateEvent>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  Stream<InvitePayload> get onInviteReceived => _inviteController.stream;
  Stream<MatchUpdateEvent> get onMatchUpdate => _matchUpdateController.stream;
  Stream<bool> get onConnectionChanged => _connectionController.stream;
  Stream<String> get onError => _errorController.stream;

  // ---------------------------------------------------------------------------
  // HTTP headers helper — attaches Bearer token to all requests
  // ---------------------------------------------------------------------------
  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        if (_authService.accessToken != null)
          'Authorization': 'Bearer ${_authService.accessToken}',
      };

  // ---------------------------------------------------------------------------
  // 1. Connect — call after check-in
  // ---------------------------------------------------------------------------
  void connect() {
    final username = _authService.username;
    final token = _authService.accessToken;

    if (username == null || token == null) {
      _errorController.add('Not logged in. Please sign in first.');
      return;
    }

    if (_isConnected && _myUsername == username) return;

    _myUsername = username;

    // Phase 4: Connect using JWT token instead of raw username.
    // The server's UserHandshakeHandler validates the token and extracts
    // the username as the Principal (same STOMP routing as before).
    final url = '$_wsBase?token=$token';

    _stompClient = StompClient(
      config: StompConfig(
        url: url,
        onConnect: _onConnect,
        onWebSocketError: (error) {
          print('[WS] WebSocket error: $error');
          _errorController.add('WebSocket error: $error');
        },
        onStompError: (frame) {
          print('[WS] STOMP error: ${frame.body}');
          _errorController.add('STOMP error: ${frame.body}');
        },
        onDisconnect: (frame) {
          print('[WS] Disconnected');
          _isConnected = false;
          _connectionController.add(false);
        },
      ),
    );

    print('[WS] Connecting as $username (JWT)...');
    _stompClient!.activate();
  }

  void _onConnect(StompFrame frame) {
    print('[WS] Connected!');
    _isConnected = true;
    _connectionController.add(true);

    // Subscribe to incoming challenges
    _stompClient!.subscribe(
      destination: '/user/queue/invites',
      callback: (frame) {
        if (frame.body == null) return;
        final json = jsonDecode(frame.body!);
        final invite = InvitePayload.fromJson(json);
        print('[WS] Invite received from ${invite.from}: ${invite.inviteId}');
        _inviteController.add(invite);
      },
    );

    // Subscribe to match lifecycle events
    _stompClient!.subscribe(
      destination: '/user/queue/match-updates',
      callback: (frame) {
        if (frame.body == null) return;
        final json = jsonDecode(frame.body!);
        final event = MatchUpdateEvent.fromJson(json);
        print('[WS] Match update [${event.status}]: ${event.matchId}');

        // Track active match state
        if (event.status == 'STARTED') {
          activeMatchId = event.matchId;
          activeOpponent =
              event.player1 == _myUsername ? event.player2 : event.player1;
        } else if (event.status == 'REMATCH_DECLINED') {
          activeMatchId = null;
          activeOpponent = null;
        }

        _matchUpdateController.add(event);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Challenge Flow — invite, accept, decline, cancel
  // ---------------------------------------------------------------------------

  Future<String?> sendChallenge(String targetUsername) async {
    try {
      final res = await http.post(
        Uri.parse('$_httpBase/matches/invite'),
        headers: _authHeaders,
        body: jsonEncode({
          'challengerUsername': _myUsername,
          'targetUsername': targetUsername,
        }),
      );

      if (res.statusCode == 200) {
        print('[HTTP] Invite sent. ID: ${res.body}');
        return res.body; // The inviteId
      } else {
        print('[HTTP] Invite failed: ${res.body}');
        _errorController.add(res.body);
        return null;
      }
    } catch (e) {
      print('[HTTP] Invite error: $e');
      _errorController.add('Network error: $e');
      return null;
    }
  }

  Future<void> acceptChallenge(
      String inviteId, String challengerUsername) async {
    try {
      final res = await http.post(
        Uri.parse('$_httpBase/matches/accept'),
        headers: _authHeaders,
        body: jsonEncode({
          'inviteId': inviteId,
          'challengerUsername': challengerUsername,
          'opponentUsername': _myUsername,
        }),
      );
      print('[HTTP] Accept result: ${res.statusCode} ${res.body}');
    } catch (e) {
      print('[HTTP] Accept error: $e');
      _errorController.add('Network error: $e');
    }
  }

  Future<void> declineChallenge(
      String inviteId, String challengerUsername) async {
    try {
      final res = await http.post(
        Uri.parse('$_httpBase/matches/decline'),
        headers: _authHeaders,
        body: jsonEncode({
          'inviteId': inviteId,
          'challengerUsername': challengerUsername,
          'opponentUsername': _myUsername,
        }),
      );
      print('[HTTP] Decline result: ${res.statusCode} ${res.body}');
    } catch (e) {
      print('[HTTP] Decline error: $e');
    }
  }

  Future<void> cancelChallenge(String inviteId, String targetUsername) async {
    try {
      final res = await http.post(
        Uri.parse('$_httpBase/matches/cancel'),
        headers: _authHeaders,
        body: jsonEncode({
          'inviteId': inviteId,
          'challengerUsername': _myUsername,
          'opponentUsername': targetUsername,
        }),
      );
      print('[HTTP] Cancel result: ${res.statusCode} ${res.body}');
    } catch (e) {
      print('[HTTP] Cancel error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 3. Match Flow — report, confirm
  // ---------------------------------------------------------------------------

  Future<bool> reportResult(String matchId, String claimedWinner) async {
    try {
      final res = await http.post(
        Uri.parse('$_httpBase/matches/report'),
        headers: _authHeaders,
        body: jsonEncode({
          'matchId': matchId,
          'reporterUsername': _myUsername,
          'claimedWinner': claimedWinner,
        }),
      );

      if (res.statusCode == 200) {
        print('[HTTP] Result reported. Claimed winner: $claimedWinner');
        return true;
      } else {
        print('[HTTP] Report failed: ${res.body}');
        _errorController.add(res.body);
        return false;
      }
    } catch (e) {
      print('[HTTP] Report error: $e');
      _errorController.add('Network error: $e');
      return false;
    }
  }

  Future<bool> confirmResult(String matchId, String claimedWinner) async {
    try {
      final res = await http.post(
        Uri.parse('$_httpBase/matches/confirm'),
        headers: _authHeaders,
        body: jsonEncode({
          'matchId': matchId,
          'confirmerUsername': _myUsername,
          'claimedWinner': claimedWinner,
        }),
      );

      if (res.statusCode == 200) {
        print('[HTTP] Result confirmed. Claimed winner: $claimedWinner');
        return true;
      } else {
        print('[HTTP] Confirm failed: ${res.body}');
        _errorController.add(res.body);
        return false;
      }
    } catch (e) {
      print('[HTTP] Confirm error: $e');
      _errorController.add('Network error: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // 4. Rematch Flow
  // ---------------------------------------------------------------------------

  Future<bool> requestRematch(String matchId, bool accept) async {
    try {
      final res = await http.post(
        Uri.parse('$_httpBase/matches/rematch'),
        headers: _authHeaders,
        body: jsonEncode({
          'matchId': matchId,
          'username': _myUsername,
          'accept': accept,
        }),
      );

      if (res.statusCode == 200) {
        print(
            '[HTTP] Rematch response sent (accept: $accept). Server: ${res.body}');
        return true;
      } else {
        print('[HTTP] Rematch failed: ${res.body}');
        _errorController.add(res.body);
        return false;
      }
    } catch (e) {
      print('[HTTP] Rematch error: $e');
      _errorController.add('Network error: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------
  void disconnect() {
    _stompClient?.deactivate();
    _isConnected = false;
    _myUsername = null;
    activeMatchId = null;
    activeOpponent = null;
    _connectionController.add(false);
  }

  void dispose() {
    disconnect();
    _inviteController.close();
    _matchUpdateController.close();
    _connectionController.close();
    _errorController.close();
  }
}
