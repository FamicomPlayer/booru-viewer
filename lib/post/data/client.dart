import 'dart:io';
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
    this.identity,
  });

  final Dio dio;
  final PoolClient pools;
  final ValueNotifier<Traits> traits;
  final Identity? identity;

  BooruEngine get engine =>
      identity != null ? BooruEngine.fromHost(identity!.host) : BooruEngine.e621;

  /// Query shared by every Rule34 post request.
  static const Map<String, dynamic> _rule34PostQuery = {
    'page': 'dapi',
    's': 'post',
    'q': 'index',
    'json': '1',
    // Has the server name the category of each tag, which otherwise takes
    // scraping the post page.
    'fields': 'tag_info',
  };

  static List<Post> _rule34Posts(Object? data) {
    final List<dynamic> list = switch (data) {
      List() => data,
      {'post': final List<dynamic> posts} => posts,
      _ => const [],
    };
    return list.map(Rule34Post.fromJson).toList();
  }

  static final RegExp _shortRating = RegExp(
    r'^(-?)rating:(s|q|e)$',
    caseSensitive: false,
  );

  /// Rule34 only knows ratings by their full name.
  static String _rule34Tags(String tags) => tags
      .split(RegExp(r'\s+'))
      .where((tag) => tag.isNotEmpty)
      .map((tag) {
        final match = _shortRating.firstMatch(tag);
        if (match == null) return tag;
        final rating = switch (match.group(2)!.toLowerCase()) {
          's' => 'safe',
          'q' => 'questionable',
          _ => 'explicit',
        };
        return '${match.group(1)}rating:$rating';
      })
      .join(' ');

  /// The numeric id of the logged in Rule34 user.
  String? get rule34UserId {
    final username = identity?.username;
    final name = username != null && username.startsWith('User #')
        ? username.substring(6).trim()
        : username;
    return identity?.headers?['user_id'] ??
        _extractUserId(identity?.headers?[HttpHeaders.cookieHeader]) ??
        (name != null && int.tryParse(name) != null ? name : null);
  }

  Future<Post> get({required int id, CancelToken? cancelToken}) {
    switch (engine) {
      case BooruEngine.derpibooru:
        return dio
            .get('/api/v1/json/images/$id', cancelToken: cancelToken)
            .then(
              (r) => DerpibooruPost.fromJson(
                r.data['image'],
                interactions: r.data['interactions'] as List?,
              ),
            );
      case BooruEngine.rule34:
        return dio
            .get(
              '/index.php',
              queryParameters: {..._rule34PostQuery, 'id': id},
              cancelToken: cancelToken,
            )
            .then((r) async {
              final post = _rule34Posts(r.data).firstOrNull;
              if (post != null) {
                return Rule34Post.resolveTagCategories(post, dio);
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
        return _derpibooruSearch(
          q: q,
          page: page,
          limit: limit,
          cancelToken: cancelToken,
        );

      case BooruEngine.rule34:
        String? tags = query?['tags']?.toString();
        if (tags != null) {
          if (tags.startsWith('fav:')) {
            var userId = tags.substring(4).trim();
            if (userId.isEmpty || int.tryParse(userId) == null) {
              userId = rule34UserId ?? '';
            }
            if (userId.isNotEmpty) {
              return _rule34Favorites(
                userId: userId,
                page: page,
                limit: limit,
                cancelToken: cancelToken,
              );
            }
            return Future.value([]);
          }
          tags = _rule34Tags(tags);
        }
        final pid = (page != null && page > 0) ? (page - 1) : 0;
        return dio
            .get(
              '/index.php',
              queryParameters: {
                ..._rule34PostQuery,
                if (tags != null && tags.isNotEmpty) 'tags': tags,
                'pid': pid,
                if (limit != null) 'limit': limit,
              },
              cancelToken: cancelToken,
            )
            .then((r) {
              final posts = _rule34Posts(r.data);
              Rule34Post.prefetchPostsTags(posts, dio);
              return posts;
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

  /// Searches Derpibooru with [q] in the site's own query syntax.
  Future<List<Post>> _derpibooruSearch({
    required String q,
    int? page,
    int? limit,
    CancelToken? cancelToken,
  }) => dio
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
        final interactions = r.data['interactions'] as List?;
        return images
            .map((e) => DerpibooruPost.fromJson(e, interactions: interactions))
            .toList();
      })
      .then(_filter);

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
      // The API has no lookup for several ids and answers bursts with 429,
      // so the ids are fetched as a trickle.
      const int concurrency = 2;
      final List<Post?> result = List.filled(ids.length, null);
      int next = 0;
      Future<void> worker() async {
        while (next < ids.length) {
          final int index = next++;
          try {
            final response = await dio.get(
              '/index.php',
              queryParameters: {..._rule34PostQuery, 'id': ids[index]},
              cancelToken: cancelToken,
            );
            result[index] = _rule34Posts(response.data).firstOrNull;
          } on Object {
            // Stops the other worker, the lookup has failed as a whole.
            next = ids.length;
            rethrow;
          }
        }
      }

      await Future.wait(
        List.generate(min(concurrency, ids.length), (_) => worker()),
      );
      return _filter(result.nonNulls.toList());
    }

    // Server-side maximum page request size.
    final int chunkSize = engine == BooruEngine.derpibooru ? 50 : 320;

    List<List<int>> chunks = [];
    for (int i = 0; i < ids.length; i += chunkSize) {
      chunks.add(ids.sublist(i, min(i + chunkSize, ids.length)));
    }

    List<Post> result = [];
    for (final chunk in chunks) {
      List<Post> part = engine == BooruEngine.derpibooru
          ? await _derpibooruSearch(
              q: chunk.map((id) => 'id:$id').join(' || '),
              limit: chunk.length,
              cancelToken: cancelToken,
            )
          : await page(
              query: {'tags': 'id:${chunk.join(',')}'},
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
    final cleanTags = List<String>.from(tags);
    if (engine == BooruEngine.e621) {
      cleanTags.removeWhere((e) => e.contains(' ') || e.contains(':'));
    } else {
      cleanTags.removeWhere((e) => e.trim().isEmpty || e.contains(':'));
    }
    if (cleanTags.isEmpty) return [];

    int max = switch (engine) {
      BooruEngine.derpibooru => 30,
      BooruEngine.rule34 => 25,
      BooruEngine.e621 => 40,
    };
    int pages = (cleanTags.length / max).ceil();
    int chunkSize = (cleanTags.length / pages).ceil();

    int tagPage = page % pages != 0 ? page % pages : pages;
    int sitePage = (page / pages).ceil();

    List<String> chunk = cleanTags
        .sublist((tagPage - 1) * chunkSize)
        .take(chunkSize)
        .toList();

    switch (engine) {
      case BooruEngine.derpibooru:
        // Goes around page(), which would take this query apart as a tag list.
        return _derpibooruSearch(
          q: chunk.map((e) => e.replaceAll('_', ' ')).join(' || '),
          page: sitePage,
          limit: limit,
          cancelToken: cancelToken,
        );
      case BooruEngine.rule34:
        final names = chunk.map((e) => e.replaceAll(' ', '_'));
        return this.page(
          page: sitePage,
          query: {
            'tags': chunk.length == 1 ? names.first : '( ${names.join(' ~ ')} )',
          },
          limit: limit,
          cancelToken: cancelToken,
        );
      case BooruEngine.e621:
        return this.page(
          page: sitePage,
          query: {'tags': chunk.map((e) => '~$e').join(' ')},
          limit: limit,
          cancelToken: cancelToken,
        );
    }
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
        // Rule34 does not support post-level voting (only comment voting).
        return Future.value();
      case BooruEngine.derpibooru:
        // The site answers 404, its API has no way to vote.
        throw UnsupportedError(
          'Derpibooru does not offer voting through its API',
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
        return _derpibooruSearch(
          q: 'my:faves',
          page: page,
          limit: limit,
          cancelToken: cancelToken,
        );

      case BooruEngine.rule34:
        final userId = rule34UserId;
        if (userId != null && userId.isNotEmpty) {
          return _rule34Favorites(
            userId: userId,
            page: page,
            limit: limit,
            cancelToken: cancelToken,
          );
        }
        return Future.value([]);

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
        final rawCookie = identity?.headers?[HttpHeaders.cookieHeader] ??
            identity?.headers?['Cookie'] ??
            identity?.headers?['cookie'];
        final currentUserId = identity?.headers?['user_id'] ??
            _extractUserId(rawCookie);
        final currentPassHash = identity?.headers?['pass_hash'] ??
            _extractPassHash(rawCookie);

        if (currentUserId == null || currentPassHash == null) {
          throw Exception('Web login required to favorite on Rule34');
        }

        final cookieMap = <String, String>{};
        if (rawCookie != null && rawCookie.isNotEmpty) {
          for (final part in rawCookie.split(';')) {
            final trimmed = part.trim();
            final eq = trimmed.indexOf('=');
            if (eq > 0) {
              cookieMap[trimmed.substring(0, eq).trim()] =
                  trimmed.substring(eq + 1).trim();
            }
          }
        }
        cookieMap['user_id'] = currentUserId;
        cookieMap['pass_hash'] = currentPassHash;

        final fullCookieStr = cookieMap.entries
            .map((e) => '${e.key}=${e.value}')
            .join('; ');

        final userAgent = identity?.headers?[HttpHeaders.userAgentHeader] ??
            identity?.headers?['user_agent'] ??
            dio.options.headers[HttpHeaders.userAgentHeader];
        final referer = 'https://rule34.xxx/index.php?page=post&s=view&id=$postId';

        final response = await dio.get(
          'https://rule34.xxx/public/addfav.php',
          queryParameters: {'id': postId},
          options: Options(
            responseType: ResponseType.plain,
            headers: {
              if (userAgent != null) HttpHeaders.userAgentHeader: userAgent,
              HttpHeaders.cookieHeader: fullCookieStr,
              'Cookie': fullCookieStr,
              HttpHeaders.refererHeader: referer,
              'Referer': referer,
            },
          ),
        );

        // The site answers 1 for an existing favorite, 2 without a session and
        // anything else once the favorite was added.
        final body = response.data?.toString().trim() ?? '';
        if (body == '2') {
          throw Exception('Failed to favorite on Rule34: session rejected');
        }
        Rule34Post.markFavorited(postId, true);
      case BooruEngine.derpibooru:
        throw UnsupportedError(
          'Derpibooru does not offer favoriting through its API',
        );
      case BooruEngine.e621:
        await dio.post('/favorites.json', queryParameters: {'post_id': postId});
    }
  }

  Future<void> removeFavorite(int postId) async {
    switch (engine) {
      case BooruEngine.rule34:
        final rawCookie = identity?.headers?[HttpHeaders.cookieHeader] ??
            identity?.headers?['Cookie'] ??
            identity?.headers?['cookie'];
        final currentUserId = identity?.headers?['user_id'] ??
            _extractUserId(rawCookie);
        final currentPassHash = identity?.headers?['pass_hash'] ??
            _extractPassHash(rawCookie);

        final cookieMap = <String, String>{};
        if (rawCookie != null && rawCookie.isNotEmpty) {
          for (final part in rawCookie.split(';')) {
            final trimmed = part.trim();
            final eq = trimmed.indexOf('=');
            if (eq > 0) {
              cookieMap[trimmed.substring(0, eq).trim()] =
                  trimmed.substring(eq + 1).trim();
            }
          }
        }
        if (currentUserId != null) cookieMap['user_id'] = currentUserId;
        if (currentPassHash != null) cookieMap['pass_hash'] = currentPassHash;

        final fullCookieStr = cookieMap.entries
            .map((e) => '${e.key}=${e.value}')
            .join('; ');

        final userAgent = identity?.headers?[HttpHeaders.userAgentHeader] ??
            identity?.headers?['user_agent'] ??
            dio.options.headers[HttpHeaders.userAgentHeader];
        final referer = 'https://rule34.xxx/index.php?page=post&s=view&id=$postId';

        await dio.get(
          'https://rule34.xxx/index.php',
          queryParameters: {'page': 'favorites', 's': 'delete', 'id': postId},
          options: Options(
            headers: {
              if (userAgent != null) HttpHeaders.userAgentHeader: userAgent,
              if (fullCookieStr.isNotEmpty) ...{
                HttpHeaders.cookieHeader: fullCookieStr,
                'Cookie': fullCookieStr,
              },
              HttpHeaders.refererHeader: referer,
              'Referer': referer,
            },
            validateStatus: (status) => status == 200 || status == 302,
          ),
        );
        Rule34Post.markFavorited(postId, false);
      case BooruEngine.derpibooru:
        // Only favorites kept on this device can be taken back.
        if (!LocalFavorites.isFavorited(identity!.host, postId)) {
          throw UnsupportedError(
            'Derpibooru does not offer favoriting through its API',
          );
        }
      case BooruEngine.e621:
        await dio.delete('/favorites/$postId.json');
    }
  }

  static String? _extractUserId(String? cookieHeader) {
    if (cookieHeader == null || cookieHeader.isEmpty) return null;
    final match = RegExp(r'(?:^|;\s*)user_id=([^;\s]+)', caseSensitive: false).firstMatch(cookieHeader);
    return match?.group(1)?.replaceAll('"', '').trim();
  }

  static String? _extractPassHash(String? cookieHeader) {
    if (cookieHeader == null || cookieHeader.isEmpty) return null;
    final match = RegExp(r'(?:^|;\s*)pass_hash=([^;\s]+)', caseSensitive: false).firstMatch(cookieHeader);
    return match?.group(1)?.replaceAll('"', '').trim();
  }

  Future<List<Post>> _rule34Favorites({
    required String userId,
    int? page,
    int? limit,
    CancelToken? cancelToken,
  }) async {
    final pid = (page != null && page > 0) ? (page - 1) * 50 : 0;
    final response = await dio.get<String>(
      'https://rule34.xxx/index.php',
      queryParameters: {
        'page': 'favorites',
        's': 'view',
        'id': userId,
        'pid': pid,
      },
      options: Options(responseType: ResponseType.plain),
      cancelToken: cancelToken,
    );
    final html = response.data ?? '';
    final matches = RegExp(
      r'id="p(\d+)"|page=post&(?:amp;)?s=view&(?:amp;)?id=(\d+)',
    ).allMatches(html);
    // Another user's favorites must not be recorded as our own.
    final bool own = userId == rule34UserId;
    final ids = <int>{};
    for (final m in matches) {
      final id = int.tryParse(m.group(1) ?? m.group(2) ?? '');
      if (id == null) continue;
      ids.add(id);
      if (own) Rule34Post.markFavorited(id, true);
    }
    if (ids.isEmpty) return [];
    final posts = await byIds(ids: ids.toList(), cancelToken: cancelToken);
    if (!own) return posts;
    return posts.map((p) => p.copyWith(isFavorited: true)).toList();
  }
}
