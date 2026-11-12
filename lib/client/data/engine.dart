import 'package:e1547/identity/identity.dart';

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

  static final RegExp _postPath = RegExp(r'^/posts/(\d+)$');

  /// Turns the app's own [path] into what the website of [host] shows for it.
  String webUrl(String host, String path) {
    final String? postId = _postPath.firstMatch(path)?.group(1);
    if (postId != null) {
      switch (this) {
        case BooruEngine.derpibooru:
          return assembleHostedUrl(host, '/images/$postId');
        case BooruEngine.rule34:
          // The API host serves no pages.
          final String site = normalizeHostUrl(host).replaceFirst('://api.', '://');
          return '$site/index.php?page=post&s=view&id=$postId';
        case BooruEngine.e621:
          break;
      }
    }
    return assembleHostedUrl(host, path);
  }
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
