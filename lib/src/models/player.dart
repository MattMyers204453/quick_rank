class Player {
  final String id;
  final String username;
  final String character;
  final int rating;

  Player({
    required this.id,
    required this.username,
    required this.character,
    required this.rating,
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    print(json);
    return Player(
      // API doesn't send ID yet, so we use username as the unique ID
      id: json['username'] as String? ?? '',

      // Handle the core fields
      username: json['username'] as String? ?? 'Unknown',
      character: json['character'] as String? ?? 'Random',

      // API doesn't send rating yet, so default to 0 (or 1000)
      rating: (json['rating'] as int?) ?? 0,
    );
  }
}
