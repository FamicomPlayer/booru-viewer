import 'dart:io';

import 'package:dio/dio.dart';
import 'package:e1547/client/client.dart';
import 'package:e1547/identity/identity.dart';
import 'package:e1547/pool/pool.dart';
import 'package:e1547/post/post.dart';
import 'package:e1547/traits/traits.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_support/fake_http.dart';
import '../../_support/harness.dart';

/// An image the way the Derpibooru API describes it.
Map<String, Object?> image(int id, {String format = 'png'}) => {
  'id': id,
  'width': 1280,
  'height': 720,
  'format': format,
  'size': 2048,
  'representations': {
    for (final name in ['full', 'large', 'medium', 'small', 'thumb'])
      name: 'https://derpicdn.net/img/2026/1/1/$id/$name.$format',
  },
  'tags': [
    'safe',
    'artist:example one',
    'artist:under_score',
    'oc:somepony',
    'twilight sparkle',
    'sunset',
  ],
  'score': 10,
  'faves': 4,
  'comment_count': 2,
  'created_at': '2026-01-01T12:00:00Z',
  'updated_at': '2026-01-02T12:00:00Z',
  'description': '',
  'source_url': 'https://example.com/$id',
  'uploader': 'fixture_uploader',
  'uploader_id': 9,
};

/// A page of the website, with what it tells its scripts about the visitor.
String sitePage({bool signedIn = true, String token = 'tok3n'}) =>
    '''
<!DOCTYPE html>
<html>
  <head><meta content="$token" name="csrf-token"></head>
  <body>
    <div class="js-datastore" data-user-is-signed-in="$signedIn"
        ${signedIn ? 'data-user-name="Tester"' : ''}></div>
  </body>
</html>''';

void main() {
  late FakeHttpAdapter adapter;

  /// What the API reports the user to have done to its images.
  late List<Map<String, Object?>> interactions;

  /// What the website answers a visit of an image page with.
  late FakeResponse page;

  /// Replaces the answer of the website to a favorite or a vote when set.
  FakeResponse? Function(RequestOptions options)? site;

  setUpAll(initializeTestApp);

  setUp(() {
    interactions = [];
    page = FakeResponse.html(sitePage());
    site = null;
    adapter = FakeHttpAdapter((options) async {
      final Uri uri = options.uri;
      if (uri.path == '/api/v1/json/search/images') {
        final int count = int.parse(uri.queryParameters['per_page'] ?? '3');
        return FakeResponse.json({
          'images': [
            image(1),
            image(2, format: 'webm'),
            for (int id = 3; id <= count; id++) image(id),
          ],
          'interactions': interactions,
          'total': count,
        });
      }
      if (uri.path == '/api/v1/json/images/2') {
        return FakeResponse.json({
          'image': image(2, format: 'webm'),
          'interactions': interactions,
        });
      }
      if (RegExp(r'^/images/\d+$').hasMatch(uri.path)) return page;
      if (RegExp(r'^/images/\d+/(fave|vote)$').hasMatch(uri.path)) {
        return site?.call(options) ??
            FakeResponse.json({
              'score': 11,
              'faves': 5,
              'upvotes': 11,
              'downvotes': 0,
            });
      }
      return const FakeResponse.html('Not Found', status: 404);
    });
  });

  PostClient clientFor({String? cookie}) {
    final identity = Identity(
      id: 1,
      host: 'https://derpibooru.org',
      username: 'tester',
      headers: {'key': 'k3y', HttpHeaders.cookieHeader: ?cookie},
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

  /// A client whose identity has logged in through the browser.
  PostClient loggedIn() =>
      clientFor(cookie: '_philomena_key=s3ssion; user_remember_me=r3member');

  String? search() => adapter.requests.last.uri.queryParameters['q'];

  group('searching', () {
    test('asks for a tag in both ways its name may be written', () async {
      await clientFor().page(query: {'tags': 'twilight_sparkle safe'});

      expect(search(), '(twilight_sparkle || twilight sparkle), safe');
    });

    test('keeps a namespace and turns a tag around', () async {
      await clientFor().page(
        query: {'tags': 'artist:under_score -oc:somepony -big_wings'},
      );

      expect(
        search(),
        '(artist:under_score || artist:under score), -oc:somepony, '
        '-(big_wings || big wings)',
      );
    });

    test('asks for ids as alternatives', () async {
      final result = await clientFor().byIds(ids: [2, 1]);

      expect(search(), 'id:2 || id:1');
      expect(result.map((e) => e.id), [2, 1]);
    });

    test('splits ids into pages the site can serve', () async {
      await clientFor().byIds(ids: List.generate(51, (index) => index + 1));

      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.first.uri.queryParameters['per_page'], '50');
      expect(adapter.requests.last.uri.queryParameters['q'], 'id:51');
    });

    test('asks for followed tags as alternatives', () async {
      await clientFor().byTags(
        tags: ['artist:example', 'rarity', 'sunset animated'],
      );

      expect(search(), 'artist:example || rarity || (sunset, animated)');
    });

    test('searches the favorites of the user', () async {
      await clientFor().favorites(page: 2, limit: 10);

      final query = adapter.requests.single.uri.queryParameters;
      expect(query['q'], 'my:faves');
      expect(query['page'], '2');
      expect(query['per_page'], '10');
      expect(query['key'], 'k3y');
    });

    test('passes cancellation on', () async {
      await expectLater(
        clientFor().page(cancelToken: CancelToken()..cancel()),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('parsing', () {
    test('shows a still for a video and plays its file', () async {
      final video = await clientFor().get(id: 2);

      expect(video.type, PostType.video);
      expect(video.file, endsWith('/2/full.webm'));
      expect(video.preview, endsWith('/2/thumb.gif'));
      expect(video.sample, endsWith('/2/thumb.gif'));
    });

    test('keeps the images of an image as they are', () async {
      final post = (await clientFor().page()).first;

      expect(post.preview, endsWith('/1/thumb.png'));
      expect(post.sample, endsWith('/1/large.png'));
    });

    test('keeps the names of tags whole, written the way of the app', () async {
      final post = (await clientFor().page()).first;

      expect(post.tags['artist'], ['artist:example_one', 'artist:under_score']);
      expect(post.tags['character'], ['oc:somepony']);
      expect(post.tags['general'], ['safe', 'twilight_sparkle', 'sunset']);
      // What a tag is found by is what it can be searched and followed by.
      expect(post.hasTag('artist:example_one'), isTrue);
      expect(post.hasTag('twilight sparkle'), isTrue);
      expect(post.hasTag('example_one'), isFalse);
    });

    test('reads favorites and votes from beside the images', () async {
      interactions = [
        {'image_id': 1, 'user_id': 5, 'interaction_type': 'faved', 'value': ''},
        {
          'image_id': 1,
          'user_id': 5,
          'interaction_type': 'voted',
          'value': 'up',
        },
        {
          'image_id': 2,
          'user_id': 5,
          'interaction_type': 'voted',
          'value': 'down',
        },
        {
          'image_id': 3,
          'user_id': 5,
          'interaction_type': 'hidden',
          'value': '',
        },
      ];

      final client = clientFor();
      final result = await client.page();

      expect(result.map((e) => e.isFavorited), [true, false, false]);
      expect(result.map((e) => e.vote), [1, -1, null]);
      expect((await client.get(id: 2)).vote, -1);
    });
  });

  group('browser login', () {
    test('favorites the way the website does', () async {
      // Folded into one header, the way native adapters report them.
      const String renewed =
          '_philomena_key=r3newed; path=/; expires=Thu, 12 Nov 2026 '
          '17:38:25 GMT; HttpOnly, other=1; path=/';
      page = FakeResponse.html(
        sitePage(),
        headers: {
          HttpHeaders.setCookieHeader: [renewed],
        },
      );

      await loggedIn().addFavorite(1);

      final visit = adapter.requests.first;
      expect(visit.method, 'GET');
      expect(visit.uri.path, '/images/1');
      // The key is for the API, the website has no use for it.
      expect(visit.uri.queryParameters, isEmpty);
      expect(visit.headers, isNot(contains('X-API-Key')));
      expect(
        visit.headers[HttpHeaders.cookieHeader],
        '_philomena_key=s3ssion; user_remember_me=r3member',
      );

      final write = adapter.requests.last;
      expect(write.method, 'POST');
      expect(write.uri.path, '/images/1/fave');
      expect(write.uri.queryParameters, isEmpty);
      expect(write.headers['x-csrf-token'], 'tok3n');
      expect(write.headers['x-requested-with'], 'xmlhttprequest');
      expect(write.contentType, Headers.jsonContentType);
      expect(write.data, {'_method': 'POST'});
      // The site renewed the session with the page, which the write follows.
      expect(
        write.headers[HttpHeaders.cookieHeader],
        '_philomena_key=r3newed; user_remember_me=r3member; other=1',
      );
    });

    test('takes a favorite back', () async {
      await loggedIn().removeFavorite(1);

      final write = adapter.requests.last;
      expect(write.method, 'DELETE');
      expect(write.uri.path, '/images/1/fave');
      expect(write.data, {'_method': 'DELETE'});
    });

    test('asks for the token of a session once', () async {
      final client = loggedIn();

      await client.addFavorite(1);
      await client.addFavorite(2);
      await client.removeFavorite(3);

      expect(adapter.requests.where((e) => e.method == 'GET'), hasLength(1));
      expect(adapter.requests, hasLength(4));
    });

    test('casts a vote and takes it back', () async {
      final client = loggedIn();

      await client.vote(id: 1, upvote: true, replace: true);
      await client.vote(id: 1, upvote: false, replace: true);
      await client.vote(id: 1, upvote: false, replace: false);

      final writes = adapter.requests.where((e) => e.method != 'GET').toList();
      expect(writes.map((e) => e.uri.path).toSet(), {'/images/1/vote'});
      expect(writes.map((e) => e.method), ['POST', 'POST', 'DELETE']);
      expect(writes.map((e) => e.data), [
        {'up': true, '_method': 'POST'},
        {'up': false, '_method': 'POST'},
        {'_method': 'DELETE'},
      ]);
    });

    test('asks for a new token when the site turns one down', () async {
      int writes = 0;
      site = (options) =>
          writes++ == 0 ? const FakeResponse('', status: 403) : null;

      await loggedIn().addFavorite(1);

      expect(adapter.requests.map((e) => e.method), [
        'GET',
        'POST',
        'GET',
        'POST',
      ]);
    });

    test('does not write without a login in the browser', () async {
      await expectLater(
        clientFor().addFavorite(1),
        throwsA(isA<WebLoginException>()),
      );
      await expectLater(
        clientFor().vote(id: 1, upvote: true, replace: true),
        throwsA(isA<WebLoginException>()),
      );
      expect(adapter.requests, isEmpty);
    });

    test('does not write when the site shows nobody logged in', () async {
      page = FakeResponse.html(sitePage(signedIn: false));

      await expectLater(
        loggedIn().addFavorite(1),
        throwsA(isA<WebLoginException>()),
      );
      expect(adapter.requests.map((e) => e.method), ['GET']);
    });

    test('does not write when a check stands before the site', () async {
      page = const FakeResponse.html(
        '<html><title>Making sure you are not a bot!</title></html>',
      );

      await expectLater(
        loggedIn().addFavorite(1),
        throwsA(isA<WebLoginException>()),
      );
      expect(adapter.requests.map((e) => e.method), ['GET']);
    });

    test('does not take a login page for an answer', () async {
      site = (options) => const FakeResponse.html('<html>Log in</html>');

      await expectLater(
        loggedIn().addFavorite(1),
        throwsA(isA<WebLoginException>()),
      );
    });
  });

  group('favorites of this device', () {
    test('are shown and taken back without the site', () async {
      final client = clientFor();
      final post = (await client.page()).first;
      expect(post.isFavorited, isFalse);
      await LocalFavorites.save('https://derpibooru.org', post);
      addTearDown(
        () => LocalFavorites.remove('https://derpibooru.org', post.id),
      );
      adapter.requests.clear();

      expect((await client.page()).first.isFavorited, isTrue);
      expect((await client.page())[1].isFavorited, isFalse);
      await client.removeFavorite(post.id);

      expect((await client.page()).first.isFavorited, isFalse);
      expect(adapter.requests.where((e) => e.method != 'GET'), isEmpty);
    });

    test('leave once the site has taken them', () async {
      final post = (await clientFor().page()).first;
      await LocalFavorites.save('https://derpibooru.org', post);

      await loggedIn().addFavorite(post.id);

      expect(
        LocalFavorites.isFavorited('https://derpibooru.org', post.id),
        isFalse,
      );
    });
  });
}
