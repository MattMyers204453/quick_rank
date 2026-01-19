class Player {
  final String id;
  final String username;
  final String character; // e.g., "Cloud", "Joker"
  final int rating; // Current SmashRank Elo

  Player({
    required this.id,
    required this.username,
    required this.character,
    required this.rating,
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] as String,
      username: json['username'] as String,
      character: json['character'] as String,
      rating: json['rating'] as int,
    );
  }
}