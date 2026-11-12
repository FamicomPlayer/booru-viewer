import 'package:dio/dio.dart';
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
  'tags': ['safe', 'artist:example', 'oc:somepony', 'sunset'],
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

void main() {
  late FakeHttpAdapter adapter;
  late PostClient client;

  /// What the API reports the user to have done to its images.
  late List<Map<String, Object?>> interactions;

  setUpAll(initializeTestApp);

  setUp(() {
    interactions = [];
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
      return const FakeResponse.html('Not Found', status: 404);
    });
    const identity = Identity(
      id: 1,
      host: 'https://derpibooru.org',
      username: 'tester',
      headers: {'key': 'k3y'},
    );
    final dio = fakeDio(adapter, identity);
    client = PostClient(
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
  });

  String? search() => adapter.requests.last.uri.queryParameters['q'];

  test('turns a tag search into a query of the site', () async {
    await client.page(query: {'tags': 'twilight_sparkle safe'});

    expect(search(), 'twilight sparkle, safe');
  });

  test('asks for ids as alternatives', () async {
    final result = await client.byIds(ids: [2, 1]);

    expect(search(), 'id:2 || id:1');
    expect(result.map((e) => e.id), [2, 1]);
  });

  test('splits ids into pages the site can serve', () async {
    await client.byIds(ids: List.generate(51, (index) => index + 1));

    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.first.uri.queryParameters['per_page'], '50');
    expect(adapter.requests.last.uri.queryParameters['q'], 'id:51');
  });

  test('asks for followed tags as alternatives', () async {
    await client.byTags(tags: ['twilight_sparkle', 'rarity', 'my:faves']);

    expect(search(), 'twilight sparkle || rarity');
  });

  test('shows a still for a video and plays its file', () async {
    final video = await client.get(id: 2);

    expect(video.type, PostType.video);
    expect(video.file, endsWith('/2/full.webm'));
    expect(video.preview, endsWith('/2/thumb.gif'));
    expect(video.sample, endsWith('/2/thumb.gif'));
  });

  test('keeps the images of an image as they are', () async {
    final post = (await client.page()).first;

    expect(post.preview, endsWith('/1/thumb.png'));
    expect(post.sample, endsWith('/1/large.png'));
    expect(post.tags['artist'], ['example']);
    expect(post.tags['character'], ['somepony']);
  });

  test('reads favorites and votes from beside the images', () async {
    interactions = [
      {'image_id': 1, 'user_id': 5, 'interaction_type': 'faved', 'value': ''},
      {'image_id': 1, 'user_id': 5, 'interaction_type': 'voted', 'value': 'up'},
      {
        'image_id': 2,
        'user_id': 5,
        'interaction_type': 'voted',
        'value': 'down',
      },
      {'image_id': 3, 'user_id': 5, 'interaction_type': 'hidden', 'value': ''},
    ];

    final result = await client.page();

    expect(result.map((e) => e.isFavorited), [true, false, false]);
    expect(result.map((e) => e.vote), [1, -1, null]);
    expect((await client.get(id: 2)).vote, -1);
  });

  test('searches the favorites of the user', () async {
    await client.favorites(page: 2, limit: 10);

    final query = adapter.requests.single.uri.queryParameters;
    expect(query['q'], 'my:faves');
    expect(query['page'], '2');
    expect(query['per_page'], '10');
    expect(query['key'], 'k3y');
  });

  test('admits that the site takes no favorites or votes', () async {
    await expectLater(client.addFavorite(1), throwsUnsupportedError);
    await expectLater(client.removeFavorite(1), throwsUnsupportedError);
    await expectLater(
      client.vote(id: 1, upvote: true, replace: false),
      throwsUnsupportedError,
    );
    expect(adapter.requests, isEmpty);
  });

  test('shows and takes back a favorite kept on this device', () async {
    final post = (await client.page()).first;
    expect(post.isFavorited, isFalse);
    await LocalFavorites.save('https://derpibooru.org', post);
    addTearDown(() => LocalFavorites.remove('https://derpibooru.org', post.id));

    expect((await client.page()).first.isFavorited, isTrue);
    expect((await client.page())[1].isFavorited, isFalse);
    await expectLater(client.removeFavorite(post.id), completes);
  });

  test('passes cancellation on', () async {
    await expectLater(
      client.page(cancelToken: CancelToken()..cancel()),
      throwsA(isA<DioException>()),
    );
  });
}
