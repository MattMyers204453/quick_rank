/// Pool player (from search results).
class Player {
  final String id;
  final String username;
  final String character;
  final int elo; // Character-specific Elo (from pool check-in)

  Player({
    required this.id,
    required this.username,
    required this.character,
    required this.elo,
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['username'] as String? ?? '',
      username: json['username'] as String? ?? 'Unknown',
      character: json['character'] as String? ?? 'Random',
      elo: (json['elo'] as num?)?.toInt() ?? 0,
    );
  }
}

// =============================================================================
// Global Leaderboard
// =============================================================================

class GlobalRankedPlayer {
  final int rank;
  final String username;
  final int elo; // Highest character Elo
  final int peakElo;
  final int wins;
  final int losses;
  final int totalGames;
  final String? bestCharacter;

  GlobalRankedPlayer({
    required this.rank,
    required this.username,
    required this.elo,
    required this.peakElo,
    required this.wins,
    required this.losses,
    required this.totalGames,
    this.bestCharacter,
  });

  factory GlobalRankedPlayer.fromJson(Map<String, dynamic> json) {
    return GlobalRankedPlayer(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      username: json['username'] as String? ?? 'Unknown',
      elo: (json['elo'] as num?)?.toInt() ?? 0,
      peakElo: (json['peakElo'] as num?)?.toInt() ?? 1200,
      wins: (json['wins'] as num?)?.toInt() ?? 0,
      losses: (json['losses'] as num?)?.toInt() ?? 0,
      totalGames: (json['totalGames'] as num?)?.toInt() ?? 0,
      bestCharacter: json['bestCharacter'] as String?,
    );
  }

  double get winRate => totalGames > 0 ? (wins / totalGames * 100) : 0.0;
}

// =============================================================================
// Per-Character Leaderboard
// =============================================================================

class CharacterRankedPlayer {
  final int rank;
  final String username;
  final int elo;
  final int peakElo;
  final int wins;
  final int losses;
  final int totalGames;

  CharacterRankedPlayer({
    required this.rank,
    required this.username,
    required this.elo,
    required this.peakElo,
    required this.wins,
    required this.losses,
    required this.totalGames,
  });

  factory CharacterRankedPlayer.fromJson(Map<String, dynamic> json) {
    return CharacterRankedPlayer(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      username: json['username'] as String? ?? 'Unknown',
      elo: (json['elo'] as num?)?.toInt() ?? 0,
      peakElo: (json['peakElo'] as num?)?.toInt() ?? 1200,
      wins: (json['wins'] as num?)?.toInt() ?? 0,
      losses: (json['losses'] as num?)?.toInt() ?? 0,
      totalGames: (json['totalGames'] as num?)?.toInt() ?? 0,
    );
  }

  double get winRate => totalGames > 0 ? (wins / totalGames * 100) : 0.0;
}

// =============================================================================
// Profile
// =============================================================================

class PlayerProfile {
  final String username;
  final int elo; // Global (highest character)
  final int peakElo;
  final int wins;
  final int losses;
  final int totalGames;
  final int rank;
  final int totalActivePlayers;
  final String? mainCharacter;
  final String? memberSince;

  PlayerProfile({
    required this.username,
    required this.elo,
    required this.peakElo,
    required this.wins,
    required this.losses,
    required this.totalGames,
    required this.rank,
    required this.totalActivePlayers,
    this.mainCharacter,
    this.memberSince,
  });

  factory PlayerProfile.fromJson(Map<String, dynamic> json) {
    return PlayerProfile(
      username: json['username'] as String? ?? 'Unknown',
      elo: (json['elo'] as num?)?.toInt() ?? 1200,
      peakElo: (json['peakElo'] as num?)?.toInt() ?? 1200,
      wins: (json['wins'] as num?)?.toInt() ?? 0,
      losses: (json['losses'] as num?)?.toInt() ?? 0,
      totalGames: (json['totalGames'] as num?)?.toInt() ?? 0,
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      totalActivePlayers: (json['totalActivePlayers'] as num?)?.toInt() ?? 0,
      mainCharacter: json['mainCharacter'] as String?,
      memberSince: json['memberSince'] as String?,
    );
  }

  double get winRate => totalGames > 0 ? (wins / totalGames * 100) : 0.0;
}

class CharacterStat {
  final String character;
  final int elo;
  final int peakElo;
  final int wins;
  final int losses;
  final int totalGames;
  final int characterRank;

  CharacterStat({
    required this.character,
    required this.elo,
    required this.peakElo,
    required this.wins,
    required this.losses,
    required this.totalGames,
    required this.characterRank,
  });

  factory CharacterStat.fromJson(Map<String, dynamic> json) {
    return CharacterStat(
      character: json['character'] as String? ?? 'Unknown',
      elo: (json['elo'] as num?)?.toInt() ?? 1200,
      peakElo: (json['peakElo'] as num?)?.toInt() ?? 1200,
      wins: (json['wins'] as num?)?.toInt() ?? 0,
      losses: (json['losses'] as num?)?.toInt() ?? 0,
      totalGames: (json['totalGames'] as num?)?.toInt() ?? 0,
      characterRank: (json['characterRank'] as num?)?.toInt() ?? 0,
    );
  }

  double get winRate => totalGames > 0 ? (wins / totalGames * 100) : 0.0;
}

class MatchHistoryEntry {
  final String matchId;
  final String opponent;
  final bool won;
  final String? myCharacter;
  final String? opponentCharacter;
  final int? eloBefore;
  final int? eloAfter;
  final int? eloDelta;
  final String? playedAt;

  MatchHistoryEntry({
    required this.matchId,
    required this.opponent,
    required this.won,
    this.myCharacter,
    this.opponentCharacter,
    this.eloBefore,
    this.eloAfter,
    this.eloDelta,
    this.playedAt,
  });

  factory MatchHistoryEntry.fromJson(Map<String, dynamic> json) {
    return MatchHistoryEntry(
      matchId: json['matchId'] as String? ?? '',
      opponent: json['opponent'] as String? ?? 'Unknown',
      won: json['won'] as bool? ?? false,
      myCharacter: json['myCharacter'] as String?,
      opponentCharacter: json['opponentCharacter'] as String?,
      eloBefore: (json['eloBefore'] as num?)?.toInt(),
      eloAfter: (json['eloAfter'] as num?)?.toInt(),
      eloDelta: (json['eloDelta'] as num?)?.toInt(),
      playedAt: json['playedAt'] as String?,
    );
  }
}
