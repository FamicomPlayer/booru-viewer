enum BooruEngine {
  e621,
  derpibooru,
  rule34;

  static BooruEngine fromHost(String host) {
    final lower = host.toLowerCase();
    if (lower.contains('derpibooru') ||
        lower.contains('furbooru') ||
        lower.contains('ponybooru')) {
      return BooruEngine.derpibooru;
    }
    if (lower.contains('rule34') || lower.contains('gelbooru')) {
      return BooruEngine.rule34;
    }
    return BooruEngine.e621;
  }

  String get displayName => switch (this) {
    BooruEngine.e621 => 'e621 / e926',
    BooruEngine.derpibooru => 'Derpibooru',
    BooruEngine.rule34 => 'Rule34.xxx',
  };

  String get defaultHost => switch (this) {
    BooruEngine.e621 => 'https://e621.net',
    BooruEngine.derpibooru => 'https://derpibooru.org',
    BooruEngine.rule34 => 'https://api.rule34.xxx',
  };
}

class Rule34Credentials {
  const Rule34Credentials({required this.userId, required this.apiKey});

  final String userId;
  final String apiKey;

  static Rule34Credentials? parse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // Matches strings like "&api_key=XYZ&user_id=123" or "api_key=XYZ&user_id=123"
    // or "user_id=123&api_key=XYZ"
    final keyMatch = RegExp(r'[?&]?api_key=([a-zA-Z0-9]+)').firstMatch(trimmed);
    final userMatch = RegExp(r'[?&]?user_id=([0-9]+)').firstMatch(trimmed);

    if (keyMatch != null && userMatch != null) {
      return Rule34Credentials(
        userId: userMatch.group(1)!,
        apiKey: keyMatch.group(1)!,
      );
    }

    // Space- or colon-delimited fallback: "userId:apiKey" or "userId apiKey"
    final parts = trimmed.split(RegExp(r'[:\s]+'));
    if (parts.length == 2) {
      if (int.tryParse(parts[0]) != null) {
        return Rule34Credentials(userId: parts[0], apiKey: parts[1]);
      } else if (int.tryParse(parts[1]) != null) {
        return Rule34Credentials(userId: parts[1], apiKey: parts[0]);
      }
    }

    return null;
  }
}
