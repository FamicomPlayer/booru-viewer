import 'package:e1547/post/post.dart';
import 'package:e1547/tag/tag.dart';

abstract final class DownloadFileNameGenerator {
  /// Default format when none is specified in settings.
  static const String defaultFormat = '{artist} - {id}.{extension}';

  /// Predefined formats for easy selection.
  static const List<({String label, String format})> presets = [
    (label: 'Artist - ID (Default)', format: '{artist} - {id}.{extension}'),
    (label: 'ID only', format: '{id}.{extension}'),
    (label: 'Artist_ID', format: '{artist}_{id}.{extension}'),
    (label: 'ID Artist', format: '{id} {artist}.{extension}'),
    (label: 'Full (ID Artist Copyright Character)', format: '{id} {artist} {copyright} {character}.{extension}'),
  ];

  static const List<String> availableTokens = [
    '{id}',
    '{artist}',
    '{character}',
    '{copyright}',
    '{general}',
    '{meta}',
    '{tags}',
    '{rating}',
    '{score}',
    '{extension}',
    '{ext}',
  ];

  /// Generates a sanitized filename based on [format] and [post].
  static String generate(Post post, {String? format}) {
    String pattern = (format != null && format.trim().isNotEmpty)
        ? format.trim()
        : defaultFormat;

    final String idStr = post.id.toString();
    List<String> artists = filterArtists(post.tags['artist'] ?? const []);
    if (artists.isEmpty) {
      final generalTags = post.tags['general'] ?? const [];
      final cachedArtists = generalTags.where((t) => Rule34Post.getCachedTagCategory(t) == 1).toList();
      if (cachedArtists.isNotEmpty) {
        artists = filterArtists(cachedArtists);
      }
    }
    if (artists.isEmpty && post.sources.isNotEmpty) {
      final allTags = post.tags.values.expand((t) => t).toList();
      final src = post.sources.join(' ').toLowerCase();
      for (final t in allTags) {
        final norm = t.toLowerCase().replaceAll(' ', '_');
        if (norm.length > 2 &&
            (src.contains('/$norm') || src.contains('=$norm') || (src.contains('status/') && src.contains(norm)))) {
          artists = [t];
          Rule34Post.cacheTagCategory(t, 1);
          break;
        }
      }
    }
    final String artistSeparator = pattern.contains('{artist}_') ? '_' : ', ';
    final String artistStr = artists.isNotEmpty ? artists.join(artistSeparator) : 'unknown_artist';

    final List<String> characters = post.tags['character'] ?? const [];
    final String characterStr = characters.isNotEmpty ? characters.join(', ') : '';

    final List<String> copyrights = post.tags['copyright'] ?? const [];
    final String copyrightStr = copyrights.isNotEmpty ? copyrights.join(', ') : '';

    final List<String> general = post.tags['general'] ?? const [];
    final String generalStr = general.isNotEmpty ? general.take(10).join(' ') : '';

    final List<String> meta = post.tags['meta'] ?? const [];
    final String metaStr = meta.isNotEmpty ? meta.join(' ') : '';

    final allTags = post.tags.values.expand((t) => t).toList();
    final String allTagsStr = allTags.isNotEmpty ? allTags.take(15).join(' ') : '';

    final String ratingStr = post.rating.name;
    final String scoreStr = post.score.toString();
    final String extStr = post.ext;

    String result = pattern
        .replaceAll('{id}', idStr)
        .replaceAll('{artist}', artistStr)
        .replaceAll('{character}', characterStr)
        .replaceAll('{copyright}', copyrightStr)
        .replaceAll('{general}', generalStr)
        .replaceAll('{meta}', metaStr)
        .replaceAll('{tags}', allTagsStr)
        .replaceAll('{rating}', ratingStr)
        .replaceAll('{score}', scoreStr)
        .replaceAll('{extension}', extStr)
        .replaceAll('{ext}', extStr);

    // If extension wasn't included in pattern, append it
    if (!result.toLowerCase().endsWith('.$extStr'.toLowerCase())) {
      result = '$result.$extStr';
    }

    // Clean up empty parentheses, brackets, or dangling delimiters
    result = result
        .replaceAll(RegExp(r'\(\s*\)'), '')
        .replaceAll(RegExp(r'\[\s*\]'), '')
        .replaceAll(RegExp(r'\{\s*\}'), '')
        .replaceAll(RegExp(r'\s*-\s*\.'), '.')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return sanitize(result);
  }

  /// Sanitizes string to be safe across Android, Linux, and Windows filesystems.
  static String sanitize(String input) {
    const invalidChars = r'[\/\\:\*\?"<>\|]';
    final cleaned = input.replaceAll(RegExp(invalidChars), '_');
    return cleaned.trim();
  }
}
