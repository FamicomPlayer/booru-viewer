import 'dart:io';

import 'package:dio/dio.dart';
import 'package:e1547/identity/identity.dart';
import 'package:e1547/pool/pool.dart';
import 'package:e1547/post/post.dart';
import 'package:e1547/traits/traits.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_support/fake_http.dart';
import '../../_support/fixtures.dart';
import '../../_support/harness.dart';

const String missingAuth =
    'Missing authentication. Go to api.rule34.xxx for more information';

void main() {
  late FakeHttpAdapter adapter;

  /// Posts the API serves, by id.
  late Map<int, Map<String, Object?>> posts;

  /// What the website answers for its pages, by the `page` and `s` it is asked for.
  late Map<String, FakeResponse> pages;

  /// Replaces the answer of the post API when set.
  FakeResponse? Function(RequestOptions options)? api;

  setUpAll(initializeTestApp);

  setUp(() {
    Rule34Post.reset();
    posts = {
      for (final post in loadFixtureList('rule34_posts.json'))
        post['id']! as int: post,
    };
    pages = {};
    api = null;
    adapter = FakeHttpAdapter((options) async {
      final Uri uri = options.uri;
      final Map<String, String> query = uri.queryParameters;
      if (uri.host == 'api.rule34.xxx' && query['page'] == 'dapi') {
        final FakeResponse? override = api?.call(options);
        if (override != null) return override;
        final String? id = query['id'];
        if (id != null) {
          final post = posts[int.parse(id)];
          return post == null
              ? const FakeResponse('')
              : FakeResponse.json([post]);
        }
        return FakeResponse.json(posts.values.toList());
      }
      return pages['${uri.host}${uri.path}?${query['page']}&${query['s']}'] ??
          const FakeResponse.html('Not Found', status: 404);
    });
  });

  PostClient clientFor({
    String? username = '42',
    Map<String, String>? headers = const {'user_id': '42', 'api_key': 'k3y'},
  }) {
    final identity = Identity(
      id: 1,
      host: 'https://rule34.xxx',
      username: username,
      headers: headers,
    );
    final dio = fakeDio(adapter, identity);
    return PostClient(
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
  }

  /// The requests that reached the post API, without the tag scraping that
  /// follows a page in the background.
  List<RequestOptions> apiRequests() =>
      adapter.requests.where((e) => e.uri.host == 'api.rule34.xxx').toList();

  group('parsing', () {
    test('maps a post onto the model', () async {
      final post = (await clientFor().page()).first;

      expect(post.id, 1001);
      expect(post.ext, 'jpeg');
      expect(post.type, PostType.image);
      expect(post.width, 1600);
      expect(post.height, 1200);
      expect(post.file, endsWith('0123456789abcdef0123456789abcdef.jpeg'));
      expect(
        post.sample,
        endsWith('sample_0123456789abcdef0123456789abcdef.jpg'),
      );
      expect(
        post.preview,
        endsWith('thumbnail_0123456789abcdef0123456789abcdef.jpg'),
      );
      expect(post.rating, Rating.q);
      expect(post.score, 42);
      expect(post.commentCount, 3);
      expect(post.sources, ['https://example.com/artwork/1001']);
      expect(post.uploaderName, 'fixture_uploader');
      expect(post.relationships.parentId, isNull);
    });

    test('dates a post by its last change', () async {
      final post = (await clientFor().page()).first;

      expect(
        post.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
      );
    });

    test('plays the file of a video and shows its still', () async {
      final video = (await clientFor().page()).firstWhere((e) => e.id == 1002);

      expect(video.ext, 'mp4');
      expect(video.type, PostType.video);
      expect(video.file, endsWith('.mp4'));
      expect(video.sample, endsWith('.jpg'));
      expect(video.preview, endsWith('.jpg'));
      expect(video.rating, Rating.e);
      expect(video.sources, isEmpty);
      expect(video.relationships.parentId, 1001);
    });

    test('sorts tags into the categories the server names', () async {
      final post = (await clientFor().page()).first;

      expect(post.tags['artist'], ['example_artist']);
      expect(post.tags['copyright'], ['example_series']);
      expect(post.tags['character'], ["jeanne_d'arc_(fate)"]);
      expect(post.tags['meta'], ['highres']);
      expect(
        post.tags['general'],
        // The brackets alone would have made a character of the first.
        ['apple_(fruit)', 'landscape', 'sunset', 'untyped_tag'],
      );
    });

    test('guesses the categories the server leaves out', () {
      final post = Rule34Post.fromJson({
        'id': 1,
        'file_url': 'https://example.com/a.png',
        'image': 'a.png',
        'tags': 'some_name_(artist) somebody_(some_series) plain',
        'source': '',
      });

      expect(post.tags['artist'], ['some_name_(artist)']);
      expect(post.tags['character'], ['somebody_(some_series)']);
      expect(post.tags['general'], ['plain']);
    });

    test('keeps a category through a later resolve', () async {
      final client = clientFor();
      final post = (await client.page()).first;
      Rule34Post.reset();

      final resolved = await Rule34Post.resolveTagCategories(post, client.dio);

      expect(resolved.tags['artist'], ['example_artist']);
      expect(resolved.tags['copyright'], ['example_series']);
    });

    test('reads an empty body as no posts', () async {
      api = (_) => const FakeResponse('');

      expect(await clientFor().page(query: {'tags': 'no_such_tag'}), isEmpty);
    });

    test('reports rejected credentials instead of no posts', () async {
      api = (_) => FakeResponse.json(missingAuth);

      await expectLater(
        clientFor(headers: null, username: null).page(),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            HttpStatus.unauthorized,
          ),
        ),
      );
    });

    test('fails on a post that does not exist', () async {
      await expectLater(clientFor().get(id: 7), throwsStateError);
    });

    test('reads a single post', () async {
      final post = await clientFor().get(id: 1002);

      expect(post.id, 1002);
      expect(post.tags['meta'], ['animated', 'video']);
      expect(apiRequests().single.uri.queryParameters['id'], '1002');
    });

    test('looks at the page of a post once for tags it cannot place', () async {
      final client = clientFor();

      // The first post carries a tag the API names no category for.
      await client.get(id: 1001);
      await client.get(id: 1001);

      expect(
        adapter.requests.where((e) => e.uri.host == 'rule34.xxx'),
        hasLength(1),
      );
    });
  });

  group('requests', () {
    test('sends credentials and asks for tag categories', () async {
      await clientFor().page(page: 3, limit: 20, query: {'tags': 'landscape'});

      final query = apiRequests().single.uri.queryParameters;
      expect(query['api_key'], 'k3y');
      expect(query['user_id'], '42');
      expect(query['json'], '1');
      expect(query['fields'], 'tag_info');
      expect(query['tags'], 'landscape');
      expect(query['limit'], '20');
      // The API counts pages from zero.
      expect(query['pid'], '2');
    });

    test('leaves the tags out of an empty search', () async {
      await clientFor().page(query: {'tags': ''});

      expect(apiRequests().single.uri.queryParameters, isNot(contains('tags')));
    });

    test('spells out rating shorthands', () async {
      await clientFor().page(
        query: {'tags': 'landscape rating:s -rating:e rating:questionable'},
      );

      expect(
        apiRequests().single.uri.queryParameters['tags'],
        'landscape rating:safe -rating:explicit rating:questionable',
      );
    });

    test('joins several tags into a group of alternatives', () async {
      await clientFor().byTags(tags: ['sunset', 'red sky', 'fav:1']);

      expect(
        apiRequests().single.uri.queryParameters['tags'],
        '( sunset ~ red_sky )',
      );
    });

    test('searches a lone tag as it is', () async {
      await clientFor().byTags(tags: ['sunset']);

      expect(apiRequests().single.uri.queryParameters['tags'], 'sunset');
    });

    test('does not put stored credentials into headers', () async {
      await clientFor(
        headers: const {
          'user_id': '42',
          'api_key': 'k3y',
          'pass_hash': 'abc123',
          'user_agent': 'TestAgent/1.0',
        },
      ).page();

      final headers = apiRequests().single.headers;
      expect(headers, isNot(contains('api_key')));
      expect(headers, isNot(contains('pass_hash')));
      expect(headers, isNot(contains('user_id')));
      expect(headers, isNot(contains('user_agent')));
      expect(headers[HttpHeaders.userAgentHeader], 'TestAgent/1.0');
    });
  });

  group('ids', () {
    setUp(() {
      for (int id = 2000; id < 2012; id++) {
        posts[id] = {...posts[1001]!, 'id': id};
      }
    });

    test('looks ids up in the order they were asked for', () async {
      final ids = [2005, 2001, 1002, 2009];

      final result = await clientFor().byIds(ids: ids);

      expect(result.map((e) => e.id), ids);
      expect(
        apiRequests().map((e) => e.uri.queryParameters['id']),
        unorderedEquals(ids.map((e) => '$e')),
      );
    });

    test('skips ids that are gone', () async {
      final result = await clientFor().byIds(ids: [2001, 7, 2002]);

      expect(result.map((e) => e.id), [2001, 2002]);
    });

    test('never has more than two lookups underway', () async {
      final answer = adapter.handler;
      adapter = FakeHttpAdapter((options) async {
        // Longer than the lookups are spaced apart, so that they overlap.
        await Future<void>.delayed(PostClient.rule34LookupSpacing * 3);
        return answer(options);
      });

      final result = await clientFor().byIds(
        ids: List.generate(6, (index) => 2000 + index),
      );

      expect(result, hasLength(6));
      expect(adapter.peak, 2);
    });

    test('spaces lookups apart however fast the answers come', () async {
      final Stopwatch watch = Stopwatch()..start();

      await clientFor().byIds(ids: List.generate(5, (index) => 2000 + index));

      expect(
        watch.elapsed,
        greaterThanOrEqualTo(PostClient.rule34LookupSpacing * 4),
      );
    });

    test('fails as a whole when a lookup fails', () async {
      api = (options) => options.uri.queryParameters['id'] == '2001'
          ? const FakeResponse('', status: 500)
          : null;

      await expectLater(
        clientFor().byIds(ids: List.generate(8, (index) => 2000 + index)),
        throwsA(isA<DioException>()),
      );
      // The remaining ids are not asked for once the lookup is lost.
      expect(apiRequests().length, lessThan(8));
    });
  });

  group('favorites', () {
    const String site = 'rule34.xxx/index.php?favorites&view';
    const Map<String, String> session = {
      'user_id': '42',
      'api_key': 'k3y',
      'pass_hash': 'abc123',
    };

    setUp(() {
      pages[site] = const FakeResponse.html('''
        <div id="content">
          <span class="thumb"><a id="p1002" href="index.php?page=post&amp;s=view&amp;id=1002"><img src="t.jpg"/></a></span>
          <span class="thumb"><a id="p1001" href="index.php?page=post&amp;s=view&amp;id=1001"><img src="t.jpg"/></a></span>
        </div>
      ''');
    });

    test('reads the favorites off the website', () async {
      final result = await clientFor(headers: session).favorites(page: 2);

      expect(result.map((e) => e.id), [1002, 1001]);
      expect(result.every((e) => e.isFavorited), isTrue);

      final listing = adapter.requests.first.uri;
      expect(listing.host, 'rule34.xxx');
      expect(listing.queryParameters['id'], '42');
      // The website counts in posts, of which a page holds fifty.
      expect(listing.queryParameters['pid'], '50');
    });

    test('keeps the API key away from the website', () async {
      await clientFor(headers: session).favorites();

      final listing = adapter.requests.first;
      expect(listing.uri.queryParameters, isNot(contains('api_key')));
      expect(listing.headers, isNot(contains('api_key')));
      expect(
        listing.headers[HttpHeaders.cookieHeader],
        allOf(contains('user_id=42'), contains('pass_hash=abc123')),
      );
      expect(apiRequests().first.uri.queryParameters['api_key'], 'k3y');
    });

    test('does not take the favorites of others for our own', () async {
      final result = await clientFor(
        headers: session,
      ).page(query: {'tags': 'fav:99'});

      expect(adapter.requests.first.uri.queryParameters['id'], '99');
      expect(result.map((e) => e.id), [1002, 1001]);
      expect(result.any((e) => e.isFavorited), isFalse);
      expect(Rule34Post.isFavorited(1001), isFalse);
    });

    test('fails when the website turns the request away', () async {
      pages[site] = const FakeResponse.html('CAPTCHA', status: 403);

      await expectLater(
        clientFor(headers: session).favorites(),
        throwsA(isA<DioException>()),
      );
    });

    test('has no favorites without a user', () async {
      final result = await clientFor(headers: null, username: null).favorites();

      expect(result, isEmpty);
      expect(adapter.requests, isEmpty);
    });

    group('adding', () {
      const String addfav = 'rule34.xxx/public/addfav.php?null&null';

      test('accepts a new and an existing favorite', () async {
        for (final String answer in ['3', '1']) {
          Rule34Post.reset();
          pages[addfav] = FakeResponse.html(answer);

          await clientFor(headers: session).addFavorite(1001);

          expect(Rule34Post.isFavorited(1001), isTrue);
        }
        expect(adapter.requests.last.uri.queryParameters['id'], '1001');
      });

      test('fails when the session is rejected', () async {
        pages[addfav] = const FakeResponse.html('2');

        await expectLater(
          clientFor(headers: session).addFavorite(1001),
          throwsException,
        );
        expect(Rule34Post.isFavorited(1001), isFalse);
      });

      test('fails on a page that is not an answer', () async {
        pages[addfav] = const FakeResponse.html(
          '<title>Rule34.xxx CAPTCHA</title>',
          status: 403,
        );

        await expectLater(
          clientFor(headers: session).addFavorite(1001),
          throwsA(isA<DioException>()),
        );
        expect(Rule34Post.isFavorited(1001), isFalse);
      });

      test('needs the session of a web login', () async {
        await expectLater(clientFor().addFavorite(1001), throwsException);
        expect(adapter.requests, isEmpty);
      });
    });

    group('removing', () {
      const String delete = 'rule34.xxx/index.php?favorites&delete';

      test('asks the website with the session', () async {
        Rule34Post.markFavorited(1001, true);
        pages[delete] = const FakeResponse.html('');

        await clientFor(headers: session).removeFavorite(1001);

        final request = adapter.requests.single;
        expect(request.uri.queryParameters['id'], '1001');
        expect(
          request.headers[HttpHeaders.cookieHeader],
          allOf(contains('user_id=42'), contains('pass_hash=abc123')),
        );
        expect(Rule34Post.isFavorited(1001), isFalse);
      });

      test('keeps the favorite when the website refuses', () async {
        Rule34Post.markFavorited(1001, true);
        pages[delete] = const FakeResponse.html('CAPTCHA', status: 403);

        await expectLater(
          clientFor(headers: session).removeFavorite(1001),
          throwsA(isA<DioException>()),
        );
        expect(Rule34Post.isFavorited(1001), isTrue);
      });

      test('forgets a favorite of this device without asking', () async {
        Rule34Post.markFavorited(1001, true);

        await clientFor().removeFavorite(1001);

        expect(adapter.requests, isEmpty);
        expect(Rule34Post.isFavorited(1001), isFalse);
      });
    });
  });
}
