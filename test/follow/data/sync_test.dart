import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:e1547/app/app.dart';
import 'package:e1547/follow/follow.dart';
import 'package:e1547/identity/identity.dart';
import 'package:e1547/pool/pool.dart';
import 'package:e1547/post/post.dart';
import 'package:e1547/traits/traits.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_support/fake_http.dart';
import '../../_support/fixtures.dart';
import '../../_support/harness.dart';

void main() {
  late AppDatabase sqlite;
  late FollowRepository repository;
  late Identity identity;
  late FakeHttpAdapter adapter;
  late PostClient posts;
  late ValueNotifier<Traits> traits;

  /// The status the API answers a search for a tag with, where it is not 200.
  late Map<String, int> failures;

  /// How many searches the API answers before it turns every other away.
  int? turnedAwayAfter;

  setUpAll(initializeTestApp);

  setUp(() async {
    Rule34Post.reset();
    failures = {};
    turnedAwayAfter = null;
    sqlite = AppDatabase(NativeDatabase.memory());
    repository = FollowRepository(database: sqlite);
    identity = await IdentityRepository(sqlite).add(
      const IdentityRequest(
        host: 'https://rule34.xxx',
        username: '42',
        headers: {'user_id': '42', 'api_key': 'k3y'},
      ),
    );
    final List<Map<String, Object?>> fixture = loadFixtureList(
      'rule34_posts.json',
    );
    adapter = FakeHttpAdapter((options) async {
      final Map<String, String> query = options.uri.queryParameters;
      if (query['page'] != 'dapi') {
        return const FakeResponse.html('Not Found', status: 404);
      }
      final int? failure = failures[query['tags']];
      if (failure != null) return FakeResponse('', status: failure);
      if (turnedAwayAfter != null &&
          adapter.requests.length > turnedAwayAfter!) {
        return const FakeResponse('', status: HttpStatus.tooManyRequests);
      }
      return FakeResponse.json(fixture);
    });
    final dio = fakeDio(adapter, identity);
    traits = ValueNotifier(
      const Traits(
        id: 1,
        userId: null,
        denylist: [],
        homeTags: '',
        avatar: null,
        perPage: null,
      ),
    );
    posts = PostClient(
      dio: dio,
      pools: PoolClient(dio: dio),
      traits: traits,
      identity: identity,
    );
    for (final String tags in ['first', 'second', 'third']) {
      await repository.add(FollowRequest(tags: tags), identity.id);
    }
  });

  tearDown(() async {
    traits.dispose();
    await sqlite.close();
  });

  Future<FollowSync> sync() async {
    final sync = FollowSync(
      repository: repository,
      identity: identity,
      traits: traits,
      postsClient: posts,
    );
    await sync.run().timeout(const Duration(seconds: 10));
    return sync;
  }

  Future<Map<String, Follow>> follows() async => {
    for (final follow in await repository.all(identity: identity.id))
      follow.tags: follow,
  };

  test('refreshes every follow of a Rule34 identity', () async {
    final result = await sync();

    expect(result.error, isNull);
    final refreshed = await follows();
    expect(refreshed.values.map((e) => e.updated), everyElement(isNotNull));
    expect(refreshed.values.map((e) => e.latest), everyElement(1002));
  });

  test('does not pass rejected credentials for a finished sync', () async {
    failures = {
      for (final tags in ['first', 'second', 'third'])
        tags: HttpStatus.unauthorized,
    };

    final result = await sync();

    expect(result.error, isA<DioException>());
    expect(
      (await follows()).values.map((e) => e.updated),
      everyElement(isNull),
    );
  });

  test('keeps what it refreshed before being turned away', () async {
    turnedAwayAfter = 1;

    final result = await sync();

    expect(result.error, isA<DioException>());
    expect(
      (await follows()).values.where((e) => e.updated != null),
      hasLength(1),
    );
  });

  test('moves past a follow that fails on its own', () async {
    failures = {'first': HttpStatus.internalServerError};

    final result = await sync();

    expect(result.error, isNull);
    final refreshed = await follows();
    expect(refreshed['first']!.updated, isNotNull);
    expect(refreshed['first']!.latest, isNull);
    expect(refreshed['second']!.latest, 1002);
    expect(refreshed['third']!.latest, 1002);
  });
}
