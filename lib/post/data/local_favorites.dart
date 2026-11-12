import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:e1547/app/data/storage.dart';
import 'package:e1547/post/post.dart';
import 'package:flutter/foundation.dart';

class LocalFavorites {
  static AppDatabase? _db;
  static bool _tablesInitialized = false;
  static final Set<int> _cachedFavoritedIds = <int>{};

  static void init(AppDatabase db) {
    _db = db;
  }

  static Future<void> _ensureTables() async {
    if (_tablesInitialized || _db == null) return;
    _tablesInitialized = true;
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
      await _loadFavoritedIds();
    } catch (e) {
      debugPrint('LocalFavorites _ensureTables error: $e');
    }
  }

  static Future<void> _loadFavoritedIds() async {
    if (_db == null) return;
    try {
      final rows = await _db!.customSelect('SELECT post_id FROM local_favorites').get();
      _cachedFavoritedIds.clear();
      for (final row in rows) {
        final id = row.read<int>('post_id');
        _cachedFavoritedIds.add(id);
      }
    } catch (_) {}
  }

  static bool isFavorited(int postId) {
    if (!_tablesInitialized) {
      _ensureTables();
    }
    return _cachedFavoritedIds.contains(postId);
  }

  static String _normalizeHost(String host) {
    if (host.toLowerCase().contains('rule34')) return 'rule34.xxx';
    return host;
  }

  static Future<void> save(String host, Post post) async {
    _cachedFavoritedIds.add(post.id);
    await _ensureTables();
    if (_db == null) return;
    try {
      final normHost = _normalizeHost(host);
      final jsonStr = jsonEncode(post.toJson());
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db!.customStatement(
        '''
        INSERT OR REPLACE INTO local_favorites (host, post_id, post_json, created_at)
        VALUES (?, ?, ?, ?);
        ''',
        [normHost, post.id, jsonStr, now],
      );
    } catch (e) {
      debugPrint('LocalFavorites save error: $e');
    }
  }

  static Future<void> remove(String host, int postId) async {
    _cachedFavoritedIds.remove(postId);
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
    } catch (e) {
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
        } catch (_) {}
      }
      return result;
    } catch (e) {
      debugPrint('LocalFavorites getLocalFavorites error: $e');
      return [];
    }
  }
}
