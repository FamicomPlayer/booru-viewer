// Runs the clients against the real sites, which takes credentials:
//
//   RULE34_LOGIN_CREDENTIALS='&api_key=...&user_id=...' \
//   DERPIBOORU_API_KEY='...' flutter test test/live
//
// Without them every test here is skipped, so the suite stays offline.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:e1547/client/client.dart';
import 'package:e1547/comment/comment.dart';
import 'package:e1547/identity/identity.dart';
import 'package:e1547/pool/pool.dart';
import 'package:e1547/post/post.dart';
import 'package:e1547/tag/tag.dart';
import 'package:e1547/traits/traits.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_support/harness.dart';

PostClient postsFor(Identity identity, Dio dio) => PostClient(
  dio: dio,
  pools: PoolClient(dio: dio),
  traits: ValueNotifier(
    const Traits(
      id: 1,
      userId: null,
      denylist: [],
      homeTags: '',
      avatar: null,
      perPage: null,
    ),
  ),
  identity: identity,
);

/// Counts the requests a site turned away for coming too quickly.
class RateLimitCounter extends Interceptor {
  int count = 0;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == HttpStatus.tooManyRequests) count++;
    handler.next(err);
  }
}

void main() {
  setUpAll(initializeTestApp);

  // Leaves the sites room between tests, both limit how often they are asked.
  setUp(() => Future<void>.delayed(const Duration(seconds: 1)));

  final Rule34Credentials? rule34 = Rule34Credentials.parse(
    Platform.environment['RULE34_LOGIN_CREDENTIALS'] ?? '',
  );

  group('Rule34', skip: rule34 == null
      ? 'set RULE34_LOGIN_CREDENTIALS to run against rule34.xxx'
      : null, () {
    late Identity identity;
    late Dio dio;
    late PostClient posts;
    late RateLimitCounter limited;

    setUp(() {
      Rule34Post.reset();
      identity = Identity(
        id: 1,
        host: 'https://rule34.xxx',
        username: rule34!.userId,
        headers: {'user_id': rule34.userId, 'api_key': rule34.apiKey},
      );
      dio = createDefaultDio(identity);
      limited = RateLimitCounter();
      // Ahead of the interceptor that retries, to see what it smooths over.
      dio.interceptors.insert(0, limited);
      posts = postsFor(identity, dio);
    });

    tearDown(() => dio.close());

    test('lists posts with the fields the app shows', () async {
      final result = await posts.page(limit: 10);

      expect(result, hasLength(10));
      for (final post in result) {
        expect(post.file, startsWith('https://'));
        expect(post.sample, startsWith('https://'));
        expect(post.preview, startsWith('https://'));
        expect(post.ext, isNotEmpty);
        expect(post.width, greaterThan(0));
        expect(post.height, greaterThan(0));
        expect(post.uploaderName, isNotEmpty);
        expect(post.createdAt.isAfter(DateTime(2010)), isTrue);
        // A post that was parsed just now is no reason to date it just now.
        expect(
          post.createdAt.isBefore(
            DateTime.now().subtract(const Duration(seconds: 5)),
          ),
          isTrue,
        );
        expect(post.tags.values.expand((e) => e), isNotEmpty);
      }
    });

    test('pages through a search without repeating posts', () async {
      final first = await posts.page(
        page: 1,
        limit: 10,
        query: {'tags': 'sort:id:asc'},
      );
      final second = await posts.page(
        page: 2,
        limit: 10,
        query: {'tags': 'sort:id:asc'},
      );

      expect(first, hasLength(10));
      expect(second, hasLength(10));
      expect(
        first.map((e) => e.id).toSet().intersection(
          second.map((e) => e.id).toSet(),
        ),
        isEmpty,
      );
      expect(second.first.id, greaterThan(first.last.id));
    });

    test('has no posts for a tag nobody uses', () async {
      final result = await posts.page(
        query: {'tags': 'zzzz_no_such_tag_qqq_e1547'},
      );

      expect(result, isEmpty);
    });

    test('has no posts on a page past the end of a search', () async {
      final result = await posts.page(page: 50, limit: 10, query: {'tags': 'id:1'});

      expect(result, isEmpty);
    });

    test('finds videos by file and stills by sample', () async {
      final result = await posts.page(limit: 5, query: {'tags': 'video'});

      expect(result, isNotEmpty);
      for (final post in result) {
        expect(post.type, PostType.video);
        expect(post.file, anyOf(endsWith('.mp4'), endsWith('.webm')));
        expect(
          post.sample,
          anyOf(endsWith('.jpg'), endsWith('.jpeg'), endsWith('.png')),
        );
      }
    });

    test('sorts tags into the categories the site has them in', () async {
      final response = await dio.get<List<dynamic>>(
        '/index.php',
        queryParameters: {
          'page': 'dapi',
          's': 'post',
          'q': 'index',
          'json': '1',
          'limit': 20,
          'fields': 'tag_info',
        },
      );
      const Map<String, String> buckets = {
        'tag': 'general',
        'artist': 'artist',
        'copyright': 'copyright',
        'character': 'character',
        'metadata': 'meta',
      };

      int compared = 0;
      for (final Map<String, dynamic> json
          in response.data!.cast<Map<String, dynamic>>()) {
        final post = Rule34Post.fromJson(json);
        for (final Map<String, dynamic> info
            in (json['tag_info'] as List).cast<Map<String, dynamic>>()) {
          final String tag = Rule34Post.unescapeTag(info['tag'] as String);
          expect(
            post.tags[buckets[info['type']]],
            contains(tag),
            reason: '$tag of post ${post.id} is a ${info['type']}',
          );
          compared++;
        }
      }
      expect(compared, greaterThan(100));
    });

    test('searches several tags as alternatives', () async {
      const List<String> tags = ['video', 'comic'];

      final result = await posts.byTags(tags: tags, limit: 20);

      expect(result, isNotEmpty);
      for (final post in result) {
        expect(tags.any(post.hasTag), isTrue, reason: 'post ${post.id}');
      }
    });

    test('understands the short names of ratings', () async {
      final questionable = await posts.page(
        limit: 10,
        query: {'tags': 'rating:q'},
      );
      final notExplicit = await posts.page(
        limit: 10,
        query: {'tags': '-rating:e'},
      );

      expect(questionable, isNotEmpty);
      expect(questionable.map((e) => e.rating).toSet(), {Rating.q});
      expect(notExplicit, isNotEmpty);
      expect(notExplicit.map((e) => e.rating), isNot(contains(Rating.e)));
    });

    test('reports credentials the site rejects', () async {
      const Identity stranger = Identity(
        id: 2,
        host: 'https://rule34.xxx',
        username: null,
        headers: null,
      );
      final Dio anonymous = createDefaultDio(stranger);
      addTearDown(anonymous.close);

      await expectLater(
        postsFor(stranger, anonymous).page(limit: 1),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            HttpStatus.unauthorized,
          ),
        ),
      );
    });

    test('looks up many posts without being turned away', () async {
      final List<int> ids = (await posts.page(
        limit: 30,
      )).map((e) => e.id).toList().reversed.toList();
      await Future<void>.delayed(const Duration(seconds: 1));

      final result = await posts.byIds(ids: ids);

      expect(result.map((e) => e.id), ids);
      expect(limited.count, 0);
    });

    test('reads a single post', () async {
      final int id = (await posts.page(limit: 1)).single.id;

      final post = await posts.get(id: id);

      expect(post.id, id);
      expect(post.file, startsWith('https://'));
    });

    test('completes tags', () async {
      final tags = await TagClient(
        dio: dio,
        identity: identity,
      ).autocomplete(search: 'sol');

      expect(tags, isNotEmpty);
      expect(tags.first.name, contains('sol'));
      expect(tags.first.count, greaterThan(0));
    });

    test('reads the comments of a post once', () async {
      final comments = CommentClient(dio: dio, identity: identity);

      final first = await comments.page(
        page: 1,
        query: {'search[post_id]': '1'},
      );
      final second = await comments.page(
        page: 2,
        query: {'search[post_id]': '1'},
      );

      expect(first, isNotEmpty);
      expect(first.map((e) => e.id).toSet(), hasLength(first.length));
      expect(first.map((e) => e.postId).toSet(), {1});
      expect(first.every((e) => !e.body.contains('&quot;')), isTrue);
      expect(second, isEmpty);
    });
  });

  final String? derpibooru = Platform.environment['DERPIBOORU_API_KEY'];

  group('Derpibooru', skip: derpibooru == null || derpibooru.isEmpty
      ? 'set DERPIBOORU_API_KEY to run against derpibooru.org'
      : null, () {
    late Identity identity;
    late Dio dio;
    late PostClient posts;

    setUp(() {
      identity = Identity(
        id: 1,
        host: 'https://derpibooru.org',
        username: 'tester',
        headers: {'key': derpibooru!},
      );
      dio = createDefaultDio(identity);
      posts = postsFor(identity, dio);
    });

    tearDown(() => dio.close());

    test('lists the favorites of the key owner', () async {
      // Asking without a valid key is answered with an error.
      expect(await posts.favorites(limit: 5), isA<List<Post>>());
    });

    test('lists posts for a tag search', () async {
      final result = await posts.page(
        limit: 5,
        query: {'tags': 'twilight_sparkle safe'},
      );

      expect(result, hasLength(5));
      for (final post in result) {
        expect(post.hasTag('twilight sparkle'), isTrue);
        expect(post.file, startsWith('https://'));
      }
    });

    test('looks posts up by id in the order asked for', () async {
      final result = await posts.byIds(ids: [2, 1]);

      expect(result.map((e) => e.id), [2, 1]);
    });

    test('searches several tags as alternatives', () async {
      const List<String> tags = ['twilight_sparkle', 'rarity'];

      final result = await posts.byTags(tags: tags, limit: 10);

      expect(result, hasLength(10));
      for (final post in result) {
        expect(tags.any(post.hasTag), isTrue, reason: 'post ${post.id}');
      }
    });

    test('shows a video by a still that exists', () async {
      final video = (await posts.page(
        limit: 1,
        query: {'tags': 'webm'},
      )).single;

      expect(video.type, PostType.video);
      expect(video.file, endsWith('.webm'));
      expect(video.preview, endsWith('.gif'));

      final response = await dio.get<List<int>>(
        video.preview!,
        options: Options(responseType: ResponseType.bytes),
      );
      expect(
        response.headers.value(HttpHeaders.contentTypeHeader),
        'image/gif',
      );
    });

    test('completes tags', () async {
      final tags = await TagClient(
        dio: dio,
        identity: identity,
      ).autocomplete(search: 'twi');

      expect(tags, isNotEmpty);
      expect(tags.first.count, greaterThan(0));
    });

    test('reads the comments of a post', () async {
      final result = await CommentClient(
        dio: dio,
        identity: identity,
      ).page(page: 1, limit: 5, query: {'search[post_id]': '1'});

      expect(result, hasLength(5));
      expect(result.map((e) => e.postId).toSet(), {1});
    });
  });
}
