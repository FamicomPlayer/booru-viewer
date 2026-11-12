import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:e1547/app/data/storage.dart';
import 'package:e1547/post/post.dart';
import 'package:flutter/foundation.dart';

class LocalFavorites {
  static AppDatabase? _db;
  static Future<void>? _ready;

  /// Favorited post ids, by normalized host.
  static final Map<String, Set<int>> _cachedFavoritedIds = {};

  static void init(AppDatabase db) {
    if (identical(_db, db)) return;
    _db = db;
    _ready = null;
    _cachedFavoritedIds.clear();
    // Loads the ids ahead of the first page of posts asking for them.
    unawaited(_ensureTables());
  }

  static Future<void> _ensureTables() {
    if (_db == null) return Future.value();
    return _ready ??= _createTables();
  }

  static Future<void> _createTables() async {
    try {
      await _db!.customStatement('''
        CREATE TABLE IF NOT EXISTS local_favorites (
          host TEXT NOT NULL,
          post_id INTEGER NOT NULL,
          post_json TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          PRIMARY KEY (host, post_id)
        );
      ''');
      final rows = await _db!
          .customSelect('SELECT host, post_id FROM local_favorites')
          .get();
      // Merged rather than replaced, a save may have run in the meantime.
      for (final row in rows) {
        _idsOf(row.read<String>('host')).add(row.read<int>('post_id'));
      }
    } on Object catch (e) {
      // Not tried again before the next init, or a broken database would be
      // asked anew for every post that is parsed.
      debugPrint('LocalFavorites _createTables error: $e');
    }
  }

  static Set<int> _idsOf(String host) =>
      _cachedFavoritedIds.putIfAbsent(_normalizeHost(host), () => <int>{});

  static bool isFavorited(String host, int postId) {
    unawaited(_ensureTables());
    return _cachedFavoritedIds[_normalizeHost(host)]?.contains(postId) ?? false;
  }

  static String _normalizeHost(String host) {
    if (host.toLowerCase().contains('rule34')) return 'rule34.xxx';
    return host;
  }

  static Future<void> save(String host, Post post) async {
    _idsOf(host).add(post.id);
    await _ensureTables();
    if (_db == null) return;
    try {
      final normHost = _normalizeHost(host);
      // A post is saved before its favorite flag is updated.
      final jsonStr = jsonEncode(post.copyWith(isFavorited: true).toJson());
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db!.customStatement(
        '''
        INSERT OR REPLACE INTO local_favorites (host, post_id, post_json, created_at)
        VALUES (?, ?, ?, ?);
        ''',
        [normHost, post.id, jsonStr, now],
      );
    } on Object catch (e) {
      debugPrint('LocalFavorites save error: $e');
    }
  }

  static Future<void> remove(String host, int postId) async {
    _cachedFavoritedIds[_normalizeHost(host)]?.remove(postId);
    await _ensureTables();
    if (_db == null) return;
    try {
      final isR34 = host.toLowerCase().contains('rule34');
      if (isR34) {
        await _db!.customStatement(
          'DELETE FROM local_favorites WHERE host LIKE \'%rule34%\' AND post_id = ?;',
          [postId],
        );
      } else {
        await _db!.customStatement(
          'DELETE FROM local_favorites WHERE host = ? AND post_id = ?;',
          [host, postId],
        );
      }
    } on Object catch (e) {
      debugPrint('LocalFavorites remove error: $e');
    }
  }

  static Future<List<Post>> getLocalFavorites(String host) async {
    await _ensureTables();
    if (_db == null) return [];
    try {
      final isR34 = host.toLowerCase().contains('rule34');
      final rows = await _db!.customSelect(
        isR34
            ? 'SELECT post_json FROM local_favorites WHERE host LIKE \'%rule34%\' ORDER BY created_at DESC;'
            : 'SELECT post_json FROM local_favorites WHERE host = ? ORDER BY created_at DESC;',
        variables: isR34 ? const [] : [Variable<String>(host)],
      ).get();

      final List<Post> result = [];
      for (final row in rows) {
        try {
          final jsonStr = row.read<String>('post_json');
          final decoded = jsonDecode(jsonStr);
          result.add(Post.fromJson(decoded));
        } on Object catch (e) {
          debugPrint('LocalFavorites skipped an unreadable favorite: $e');
        }
      }
      return result;
    } on Object catch (e) {
      debugPrint('LocalFavorites getLocalFavorites error: $e');
      return [];
    }
  }
}
