import 'dart:math';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:e1547/client/client.dart';
import 'package:e1547/identity/identity.dart';
import 'package:e1547/pool/pool.dart';
import 'package:e1547/post/post.dart';
import 'package:e1547/shared/shared.dart';
import 'package:e1547/traits/traits.dart';
import 'package:flutter/foundation.dart';

class PostClient {
  PostClient({
    required this.dio,
    required this.pools,
    required this.traits,
    required this.identity,
  });

  final Dio dio;
  final PoolClient pools;
  final ValueNotifier<Traits> traits;
  final Identity identity;

  BooruEngine get engine => BooruEngine.fromHost(identity.host);

  Future<Post> get({required int id, CancelToken? cancelToken}) {
    switch (engine) {
      case BooruEngine.derpibooru:
        return dio
            .get('/api/v1/json/images/$id', cancelToken: cancelToken)
            .then((r) => DerpibooruPost.fromJson(r.data['image']));
      case BooruEngine.rule34:
        return dio
            .get(
              '/index.php',
              queryParameters: {
                'page': 'dapi',
                's': 'post',
                'q': 'index',
                'json': '1',
                'id': id,
              },
              cancelToken: cancelToken,
            )
            .then((r) {
              final data = r.data;
              if (data is List && data.isNotEmpty) {
                return Rule34Post.fromJson(data.first);
              }
              if (data is Map && data.containsKey('post')) {
                final posts = data['post'] as List;
                if (posts.isNotEmpty) return Rule34Post.fromJson(posts.first);
              }
              throw StateError('Post #$id not found');
            });
      case BooruEngine.e621:
        return dio
            .get('/posts/$id.json', cancelToken: cancelToken)
            .then(unwrapRailsArray)
            .then((response) => E621Post.fromJson(response.data));
    }
  }

  Future<List<Post>> page({
    int? page,
    int? limit,
    QueryMap? query,
    CancelToken? cancelToken,
  }) {
    switch (engine) {
      case BooruEngine.derpibooru:
        String q = '';
        if (query != null &&
            query['tags'] != null &&
            query['tags'].toString().trim().isNotEmpty) {
          final tags = query['tags']
              .toString()
              .split(RegExp(r'\s+'))
              .where((t) => t.isNotEmpty);
          q = tags.map((t) => t.replaceAll('_', ' ')).join(', ');
        }
        return dio
            .get(
              '/api/v1/json/search/images',
              queryParameters: {
                if (q.isNotEmpty) 'q': q,
                if (page != null) 'page': page,
                if (limit != null) 'per_page': limit,
              },
              cancelToken: cancelToken,
            )
            .then((r) {
              final images = r.data['images'] as List? ?? const [];
              return images.map(DerpibooruPost.fromJson).toList();
            })
            .then(_filter);

      case BooruEngine.rule34:
        String? tags = query?['tags']?.toString();
        if (tags != null) {
          tags = tags
              .replaceAll('rating:safe', 'rating:s')
              .replaceAll('rating:questionable', 'rating:q')
              .replaceAll('rating:explicit', 'rating:e');
        }
        final pid = (page != null && page > 0) ? (page - 1) : 0;
        return dio
            .get(
              '/index.php',
              queryParameters: {
                'page': 'dapi',
                's': 'post',
                'q': 'index',
                'json': '1',
                if (tags != null && tags.isNotEmpty) 'tags': tags,
                'pid': pid,
                if (limit != null) 'limit': limit,
              },
              cancelToken: cancelToken,
            )
            .then((r) {
              final data = r.data;
              List list = const [];
              if (data is List) {
                list = data;
              } else if (data is Map && data.containsKey('post')) {
                list = data['post'] as List;
              }
              return list.map(Rule34Post.fromJson).toList();
            })
            .then(_filter);

      case BooruEngine.e621:
        return dio
            .get(
              '/posts.json',
              queryParameters: {'page': page, 'limit': limit, ...?query}.toQuery(),
              cancelToken: cancelToken,
            )
            .then(unwrapRailsArray)
            .then(
              (response) =>
                  (response.data as List).map<Post>(E621Post.fromJson).toList(),
            )
            .then(_filter);
    }
  }

  /// Filters out "broken" posts.
  List<Post> _filter(List<Post> posts) => posts
      .whereNot((post) => !post.isDeleted && post.file == null)
      .whereNot((post) => post.ext == 'swf')
      .toList();

  Future<List<Post>> byIds({
    required List<int> ids,
    CancelToken? cancelToken,
  }) async {
    if (ids.isEmpty) return [];

    if (engine == BooruEngine.rule34) {
      final List<Post> result = [];
      for (final id in ids) {
        try {
          final p = await get(id: id, cancelToken: cancelToken);
          result.add(p);
        } on Exception {
          // Ignore individual fetch errors
        }
      }
      return result;
    }

    if (engine == BooruEngine.derpibooru) {
      final filter = ids.map((id) => 'id:$id').join(' || ');
      return page(
        query: {'tags': filter},
        limit: ids.length,
        cancelToken: cancelToken,
      );
    }

    // Server-side maximum id and page request size for e621.
    const int chunkSize = 320;

    List<List<int>> chunks = [];
    for (int i = 0; i < ids.length; i += chunkSize) {
      chunks.add(ids.sublist(i, min(i + chunkSize, ids.length)));
    }

    List<Post> result = [];
    for (final chunk in chunks) {
      String filter = 'id:${chunk.join(',')}';
      List<Post> part = await page(
        query: {'tags': filter},
        limit: chunk.length,
        cancelToken: cancelToken,
      );
      Map<int, Post> table = {for (Post e in part) e.id: e};
      result.addAll(
        (chunk.map((e) => table[e]).toList()..removeWhere((e) => e == null))
            .cast<Post>(),
      );
    }
    return result;
  }

  Future<List<Post>> byTags({
    required List<String> tags,
    int? page,
    int? limit,
    CancelToken? cancelToken,
  }) async {
    page ??= 1;
    tags.removeWhere((e) => e.contains(' ') || e.contains(':'));
    if (tags.isEmpty) return [];
    int max = 40;
    int pages = (tags.length / max).ceil();
    int chunkSize = (tags.length / pages).ceil();

    int tagPage = page % pages != 0 ? page % pages : pages;
    int sitePage = (page / pages).ceil();

    List<String> chunk = tags
        .sublist((tagPage - 1) * chunkSize)
        .take(chunkSize)
        .toList();
    String filter = chunk.map((e) => '~$e').join(' ');
    return this.page(
      page: sitePage,
      query: {'tags': filter},
      limit: limit,
      cancelToken: cancelToken,
    );
  }

  Future<void> update({required int id, required Map<String, String?> data}) {
    if (engine != BooruEngine.e621) return Future.value();
    return dio.put('/posts/$id.json', data: FormData.fromMap(data));
  }

  Future<void> vote({
    required int id,
    required bool upvote,
    required bool replace,
  }) {
    switch (engine) {
      case BooruEngine.rule34:
        return dio.get(
          '/index.php',
          queryParameters: {
            'page': 'post',
            's': 'vote',
            'id': id,
            'type': upvote ? 'up' : 'down',
          },
        );
      case BooruEngine.derpibooru:
        return dio.post(
          '/api/v1/json/images/$id/vote',
          queryParameters: {'val': upvote ? 'up' : 'down'},
        );
      case BooruEngine.e621:
        return dio.post(
          '/posts/$id/votes.json',
          queryParameters: {'score': upvote ? 1 : -1, 'no_unvote': replace},
        );
    }
  }

  Future<List<Post>> favorites({
    int? page,
    int? limit,
    QueryMap? query,
    CancelToken? cancelToken,
  }) {
    switch (engine) {
      case BooruEngine.derpibooru:
        return dio
            .get(
              '/api/v1/json/search/images',
              queryParameters: {
                'q': 'my:faves',
                if (page != null) 'page': page,
                if (limit != null) 'per_page': limit,
              },
              cancelToken: cancelToken,
            )
            .then((r) {
              final images = r.data['images'] as List? ?? const [];
              return images.map(DerpibooruPost.fromJson).toList();
            })
            .then(_filter);

      case BooruEngine.rule34:
        final userId = identity.headers?['user_id'] ??
            (identity.username != null && int.tryParse(identity.username!) != null
                ? identity.username
                : null);
        final favTag = (userId != null && userId.isNotEmpty) ? 'fav:$userId' : 'vote:3';
        final pid = (page != null && page > 0) ? (page - 1) : 0;
        return dio
            .get(
              '/index.php',
              queryParameters: {
                'page': 'dapi',
                's': 'post',
                'q': 'index',
                'json': '1',
                'tags': favTag,
                'pid': pid,
                if (limit != null) 'limit': limit,
              },
              cancelToken: cancelToken,
            )
            .then((r) {
              final data = r.data;
              List list = const [];
              if (data is List) {
                list = data;
              } else if (data is Map && data.containsKey('post')) {
                list = data['post'] as List;
              }
              return list.map(Rule34Post.fromJson).toList();
            })
            .then(_filter);

      case BooruEngine.e621:
        return dio
            .get(
              '/favorites.json',
              queryParameters: {
                'page': page,
                'limit': limit,
                // may not contain tags, or we get redirected to a html page
                ...?(query?..remove('tags')),
              },
              cancelToken: cancelToken,
            )
            .then(unwrapRailsArray)
            .then(
              (response) => (response.data as List<dynamic>)
                  .map<Post>(E621Post.fromJson)
                  .where((post) => !post.isDeleted && post.file != null)
                  .toList(),
            );
    }
  }

  Future<void> addFavorite(int postId) async {
    switch (engine) {
      case BooruEngine.rule34:
        await dio.get(
          '/index.php',
          queryParameters: {'page': 'favorites', 's': 'add', 'id': postId},
        );
      case BooruEngine.derpibooru:
        // Philomena favorites via API
        break;
      case BooruEngine.e621:
        await dio.post('/favorites.json', queryParameters: {'post_id': postId});
    }
  }

  Future<void> removeFavorite(int postId) async {
    switch (engine) {
      case BooruEngine.rule34:
        await dio.get(
          '/index.php',
          queryParameters: {'page': 'favorites', 's': 'delete', 'id': postId},
        );
      case BooruEngine.derpibooru:
        break;
      case BooruEngine.e621:
        await dio.delete('/favorites/$postId.json');
    }
  }
}
