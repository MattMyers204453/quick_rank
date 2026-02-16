import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:stomp_dart_client/stomp_dart_client.dart';

/// Payload received on /user/queue/invites
class InvitePayload {
  final String inviteId;
  final String from;
  final String status; // PENDING or CANCELLED

  InvitePayload({
    required this.inviteId,
    required this.from,
    required this.status,
  });

  factory InvitePayload.fromJson(Map<String, dynamic> json) {
    return InvitePayload(
      inviteId: json['inviteId'] as String,
      from: json['from'] as String,
      status: json['status'] as String,
    );
  }
}

/// Payload received on /user/queue/match-updates
class MatchUpdateEvent {
  final String? matchId;
  final String
      status; // STARTED, AWAITING_CONFIRMATION, ENDED, DISPUTED, DECLINED
  final String player1;
  final String player2;
  final String?
      reporterUsername; // who submitted the first report (AWAITING_CONFIRMATION only)
  final String?
      claimedWinner; // who the reporter claims won (AWAITING_CONFIRMATION only)

  MatchUpdateEvent({
    required this.matchId,
    required this.status,
    required this.player1,
    required this.player2,
    this.reporterUsername,
    this.claimedWinner,
  });

  factory MatchUpdateEvent.fromJson(Map<String, dynamic> json) {
    return MatchUpdateEvent(
      matchId: json['matchId'] as String?,
      status: json['status'] as String,
      player1: json['player1'] as String,
      player2: json['player2'] as String,
      reporterUsername: json['reporterUsername'] as String?,
      claimedWinner: json['claimedWinner'] as String?,
    );
  }
}

/// Singleton service managing STOMP WebSocket + HTTP match endpoints.
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
  // State
  // ---------------------------------------------------------------------------
  StompClient? _stompClient;
  String? _myUsername;
  bool _isConnected = false;

  String? get myUsername => _myUsername;
  bool get isConnected => _isConnected;

  /// The current active match ID (set on STARTED, cleared on ENDED/DISPUTED).
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
  // 1. Connect — call after check-in
  // ---------------------------------------------------------------------------
  void connect(String username) {
    if (_isConnected && _myUsername == username) return;

    _myUsername = username;

    // Ensure player record exists via dev-login
    _devLogin(username);

    final url = '$_wsBase?username=$username';

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

    print('[WS] Connecting as $username...');
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
        print(
            '[WS] Invite [${invite.status}] from ${invite.from}: ${invite.inviteId}');
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

        if (event.status == 'STARTED') {
          activeMatchId = event.matchId;
          activeOpponent =
              (event.player1 == _myUsername) ? event.player2 : event.player1;
        }
        if (event.status == 'ENDED' ||
            event.status == 'DECLINED' ||
            event.status == 'DISPUTED') {
          activeMatchId = null;
          activeOpponent = null;
        }

        _matchUpdateController.add(event);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 2. HTTP endpoints
  // ---------------------------------------------------------------------------

  /// Ensure player exists (dev-login). Fire-and-forget.
  Future<void> _devLogin(String username) async {
    try {
      await http.post(
        Uri.parse('$_httpBase/dev/auth/login?username=$username'),
      );
    } catch (e) {
      print('[HTTP] Dev-login failed: $e');
    }
  }

  /// Send a challenge to [targetUsername]. Returns the inviteId on success.
  Future<String?> sendInvite(String targetUsername) async {
    try {
      final res = await http.post(
        Uri.parse('$_httpBase/matches/invite'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'challengerUsername': _myUsername,
          'targetUsername': targetUsername,
        }),
      );

      if (res.statusCode == 200) {
        print('[HTTP] Invite sent. ID: ${res.body}');
        return res.body;
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

  /// Cancel a pending invite (challenger withdraws).
  Future<bool> cancelInvite(String inviteId, String opponentUsername) async {
    try {
      final res = await http.post(
        Uri.parse('$_httpBase/matches/cancel'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'inviteId': inviteId,
          'challengerUsername': _myUsername,
          'opponentUsername': opponentUsername,
        }),
      );

      if (res.statusCode == 200) {
        print('[HTTP] Invite cancelled.');
        return true;
      } else {
        print('[HTTP] Cancel failed: ${res.body}');
        _errorController.add(res.body);
        return false;
      }
    } catch (e) {
      print('[HTTP] Cancel error: $e');
      _errorController.add('Network error: $e');
      return false;
    }
  }

  /// Accept a pending invite.
  Future<bool> acceptInvite(String inviteId, String challengerUsername) async {
    try {
      final res = await http.post(
        Uri.parse('$_httpBase/matches/accept'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'inviteId': inviteId,
          'challengerUsername': challengerUsername,
          'opponentUsername': _myUsername,
        }),
      );

      if (res.statusCode == 200) {
        print('[HTTP] Invite accepted.');
        return true;
      } else {
        print('[HTTP] Accept failed: ${res.body}');
        _errorController.add('Accept failed: ${res.body}');
        return false;
      }
    } catch (e) {
      print('[HTTP] Accept error: $e');
      _errorController.add('Network error: $e');
      return false;
    }
  }

  /// Decline a pending invite.
  Future<bool> declineInvite(String inviteId, String challengerUsername) async {
    try {
      final res = await http.post(
        Uri.parse('$_httpBase/matches/decline'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'inviteId': inviteId,
          'challengerUsername': challengerUsername,
          'opponentUsername': _myUsername,
        }),
      );

      return res.statusCode == 200;
    } catch (e) {
      print('[HTTP] Decline error: $e');
      return false;
    }
  }

  /// Report match result (first player submits their claim).
  /// [claimedWinner] is the username of whoever this player says won.
  Future<bool> reportResult(String matchId, String claimedWinner) async {
    try {
      final res = await http.post(
        Uri.parse('$_httpBase/matches/report'),
        headers: {'Content-Type': 'application/json'},
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

  /// Confirm match result (second player responds with their independent view).
  Future<bool> confirmResult(String matchId, String claimedWinner) async {
    try {
      final res = await http.post(
        Uri.parse('$_httpBase/matches/confirm'),
        headers: {'Content-Type': 'application/json'},
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
