import 'dart:convert';

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

  /// The longest name, in bytes, that is asked of a filesystem. Android ends
  /// names at 255, and saving may still add a suffix of its own.
  static const int maxFileNameBytes = 200;

  static int _bytes(String value) => utf8.encode(value).length;

  /// The start of [value] that fits into [limit] bytes.
  static String _fit(String value, int limit) {
    final StringBuffer result = StringBuffer();
    int size = 0;
    for (final int rune in value.runes) {
      final String char = String.fromCharCode(rune);
      size += _bytes(char);
      if (size > limit) break;
      result.write(char);
    }
    return result.toString().replaceFirst(RegExp(r'[\s,_-]+$'), '');
  }

  // Sites that file tags under a namespace carry it in the name.
  static final RegExp _namespace = RegExp(r'^(artist|editor|oc|character):');

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

    String bare(String tag) => tag.replaceFirst(_namespace, '');
    final allTags = post.tags.values.expand((t) => t);

    // What each token stands for, and what goes between its entries.
    final Map<String, (List<String>, String)> lists = {
      '{artist}': (
        artists.map(bare).toList(),
        pattern.contains('{artist}_') ? '_' : ', ',
      ),
      '{character}': ((post.tags['character'] ?? []).map(bare).toList(), ', '),
      '{copyright}': ([...post.tags['copyright'] ?? []], ', '),
      '{general}': ((post.tags['general'] ?? []).take(10).toList(), ' '),
      '{meta}': ([...post.tags['meta'] ?? []], ' '),
      '{tags}': (allTags.take(15).toList(), ' '),
    };

    final String extStr = post.ext;

    String render() {
      String result = pattern.replaceAll('{id}', idStr);
      for (final MapEntry(key: token, value: (entries, separator))
          in lists.entries) {
        String value = entries.join(separator);
        if (token == '{artist}' && value.isEmpty) value = 'unknown_artist';
        result = result.replaceAll(token, value);
      }
      result = result
          .replaceAll('{rating}', post.rating.name)
          .replaceAll('{score}', post.score.toString())
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

    String result = render();

    // A name too long for the filesystem gives up tags from the end of its
    // longest list, which leaves the id and the start of every list in place.
    while (_bytes(result) > maxFileNameBytes) {
      List<String>? longest;
      for (final MapEntry(key: token, value: (entries, separator))
          in lists.entries) {
        if (!pattern.contains(token) || entries.length < 2) continue;
        if (longest == null ||
            entries.join(separator).length > longest.join(separator).length) {
          longest = entries;
        }
      }
      if (longest == null) break;
      longest.removeLast();
      result = render();
    }
    if (_bytes(result) <= maxFileNameBytes) return result;

    // What is still too long has a single tag or the format itself to blame,
    // and is cut off ahead of the extension.
    final String suffix = '.$extStr';
    final String base = result.substring(0, result.length - suffix.length);
    final int room = maxFileNameBytes - _bytes(suffix);
    final String cut = _fit(base, room);
    // The id is still there when its digits stand on their own, and are not
    // those of a longer number.
    final bool hasId = RegExp('(?<![0-9])$idStr(?![0-9])').hasMatch(cut);
    if (!pattern.contains('{id}') || hasId) return '$cut$suffix';
    // Posts that share the start of a name are still told apart by their id.
    return '${_fit(base, room - _bytes(idStr) - 1)} $idStr'.trim() + suffix;
  }

  /// Sanitizes string to be safe across Android, Linux, and Windows filesystems.
  static String sanitize(String input) {
    const invalidChars = r'[\/\\:\*\?"<>\|\x00-\x1f]';
    final cleaned = input.replaceAll(RegExp(invalidChars), '_');
    return cleaned.trim();
  }
}
