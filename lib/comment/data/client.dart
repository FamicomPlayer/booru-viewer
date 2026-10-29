import 'package:dio/dio.dart';
import 'package:e1547/client/client.dart';
import 'package:e1547/comment/comment.dart';
import 'package:e1547/identity/identity.dart';
import 'package:e1547/shared/shared.dart';

class CommentClient {
  CommentClient({required this.dio, this.identity});

  final Dio dio;
  final Identity? identity;

  BooruEngine get engine => BooruEngine.fromHost(identity?.host ?? dio.options.baseUrl);

  Future<Comment> get({required int id, CancelToken? cancelToken}) {
    if (engine == BooruEngine.derpibooru) {
      return dio
          .get('/api/v1/json/comments/$id', cancelToken: cancelToken)
          .then((r) => _parseDerpiComment(r.data['comment']));
    }
    return dio
        .get('/comments/$id.json', cancelToken: cancelToken)
        .then((response) => E621Comment.fromJson(response.data));
  }

  Future<List<Comment>> page({
    int? page,
    int? limit,
    QueryMap? query,
    CancelToken? cancelToken,
  }) {
    final postId = query?['search[post_id]'] ?? query?['post_id'] ?? query?['postId'];

    switch (engine) {
      case BooruEngine.derpibooru:
        final q = postId != null ? 'image_id:$postId' : '';
        return dio
            .get(
              '/api/v1/json/search/comments',
              queryParameters: {
                if (q.isNotEmpty) 'q': q,
                if (page != null) 'page': page,
                if (limit != null) 'per_page': limit,
              },
              cancelToken: cancelToken,
            )
            .then((r) {
              final comments = r.data['comments'] as List? ?? const [];
              return comments.map(_parseDerpiComment).toList();
            });

      case BooruEngine.rule34:
        return dio
            .get(
              '/index.php',
              queryParameters: {
                'page': 'dapi',
                's': 'comment',
                'q': 'index',
                'json': '1',
                if (postId != null) 'post_id': postId,
              },
              cancelToken: cancelToken,
            )
            .then((r) => _parseRule34Comments(r.data, postId));

      case BooruEngine.e621:
        return dio
            .get(
              '/comments.json',
              queryParameters: {'page': page, 'limit': limit, ...?query}.toQuery(),
              cancelToken: cancelToken,
            )
            .then(unwrapRailsArray)
            .then(
              (response) =>
                  (response.data as List).map<Comment>(E621Comment.fromJson).toList(),
            );
    }
  }

  Future<void> create({required int postId, required String content}) {
    switch (engine) {
      case BooruEngine.derpibooru:
        return dio.post(
          '/api/v1/json/comments',
          data: {
            'comment': {
              'body': content,
              'image_id': postId,
            },
          },
        );
      case BooruEngine.rule34:
        return dio.post(
          '/index.php?page=comment&s=save',
          data: FormData.fromMap({
            'comment': content,
            'post_id': postId,
          }),
        );
      case BooruEngine.e621:
        return dio.post(
          '/comments.json',
          data: FormData.fromMap({
            'comment[body]': content,
            'comment[post_id]': postId,
          }),
        );
    }
  }

  Future<void> update({
    required int id,
    required int postId,
    required String content,
  }) {
    if (engine != BooruEngine.e621) return Future.value();
    return dio.patch(
      '/comments/$id.json',
      data: FormData.fromMap({'comment[body]': content}),
    );
  }

  Future<VoteResult> vote({
    required int id,
    required bool upvote,
    required bool replace,
  }) {
    if (engine != BooruEngine.e621) {
      return Future.value(VoteResult(score: 0, ourScore: upvote ? 1 : -1));
    }
    return dio
        .post(
          '/comments/$id/votes.json',
          queryParameters: {'score': upvote ? 1 : -1, 'no_unvote': replace},
        )
        .then((response) => VoteResult.fromJson(response.data));
  }

  static Comment _parseDerpiComment(dynamic c) {
    return Comment(
      id: c['id'] is int ? c['id'] : int.tryParse(c['id'].toString()) ?? 0,
      postId: c['image_id'] is int ? c['image_id'] : int.tryParse(c['image_id']?.toString() ?? '') ?? 0,
      body: c['body']?.toString() ?? '',
      createdAt: DateTime.tryParse(c['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(c['updated_at']?.toString() ?? '') ?? DateTime.now(),
      creatorId: c['user_id'] is int ? c['user_id'] : int.tryParse(c['user_id']?.toString() ?? '') ?? 0,
      creatorName: c['author']?.toString() ?? 'Anonymous',
      score: 0,
      vote: null,
      warning: null,
      hidden: c['deleted'] == true,
    );
  }

  static List<Comment> _parseRule34Comments(dynamic data, dynamic fallbackPostId) {
    if (data == null) return const [];
    if (data is List) {
      return data.map((c) => Comment(
        id: c['id'] is int ? c['id'] : int.tryParse(c['id'].toString()) ?? 0,
        postId: c['post_id'] is int ? c['post_id'] : int.tryParse(c['post_id']?.toString() ?? fallbackPostId?.toString() ?? '0') ?? 0,
        body: c['body']?.toString() ?? '',
        createdAt: DateTime.tryParse(c['created_at']?.toString() ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(c['created_at']?.toString() ?? '') ?? DateTime.now(),
        creatorId: c['creator_id'] is int ? c['creator_id'] : int.tryParse(c['creator_id']?.toString() ?? '') ?? 0,
        creatorName: c['creator']?.toString() ?? 'Anonymous',
        score: 0,
        vote: null,
        warning: null,
        hidden: false,
      )).toList();
    }

    if (data is String) {
      final List<Comment> list = [];
      final matches = RegExp(r'<comment\s+([^>]+)/>').allMatches(data);
      for (final match in matches) {
        final attrString = match.group(1) ?? '';
        String? getAttr(String name) {
          final m = RegExp('$name="([^"]*)"').firstMatch(attrString);
          return m?.group(1);
        }

        final id = int.tryParse(getAttr('id') ?? '') ?? 0;
        final pId = int.tryParse(getAttr('post_id') ?? fallbackPostId?.toString() ?? '0') ?? 0;
        final creator = getAttr('creator') ?? 'Anonymous';
        final creatorId = int.tryParse(getAttr('creator_id') ?? '') ?? 0;
        final body = getAttr('body') ?? '';
        final createdAtStr = getAttr('created_at') ?? '';
        final createdAt = DateTime.tryParse(createdAtStr) ?? DateTime.now();

        list.add(Comment(
          id: id,
          postId: pId,
          body: body,
          createdAt: createdAt,
          updatedAt: createdAt,
          creatorId: creatorId,
          creatorName: creator,
          score: 0,
          vote: null,
          warning: null,
          hidden: false,
        ));
      }
      return list;
    }

    return const [];
  }
}
