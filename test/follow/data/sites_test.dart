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
import '../../_support/harness.dart';
import '../../_support/sites.dart';

/// Follows as the three sites refresh them. Each site answers searches the
/// way the real one does, so a follow only finds posts that its search, as
/// the app writes it for that site, really matches.
void main() {
  late AppDatabase sqlite;
  late FollowRepository repository;
  late ValueNotifier<Traits> traits;

  setUpAll(initializeTestApp);

  setUp(() {
    Rule34Post.reset();
    sqlite = AppDatabase(NativeDatabase.memory());
    repository = FollowRepository(database: sqlite);
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
  });

  tearDown(() async {
    traits.dispose();
    await sqlite.close();
  });

  Future<Identity> identityOn(FakeSite site, {String username = 'tester'}) =>
      IdentityRepository(sqlite).add(
        IdentityRequest(
          host: site.host,
          username: username,
          headers: site.headers,
        ),
      );

  Future<FollowSync> sync(
    FakeSite site,
    Identity identity, {
    bool force = false,
  }) async {
    final dio = fakeDio(site.adapter, identity);
    final sync = FollowSync(
      repository: repository,
      identity: identity,
      traits: traits,
      postsClient: PostClient(
        dio: dio,
        pools: PoolClient(dio: dio),
        traits: traits,
        identity: identity,
      ),
      force: force,
    );
    await sync.run().timeout(const Duration(seconds: 20));
    return sync;
  }

  Future<Follow> followOf(Identity identity, String tags) async =>
      (await repository.getByTags(tags, identity.id))!;

  for (final FakeSite Function() create in [
    FakeE621Site.new,
    FakeRule34Site.new,
    FakeDerpibooruSite.new,
  ]) {
    final String name = create().name;

    group(name, () {
      late FakeSite site;
      late Identity identity;

      setUp(() async {
        site = create();
        identity = await identityOn(site);
      });

      test('previews a follow of one tag with its newest post', () async {
        site.add(10, siteTags(site, '${site.single} extra'));
        site.add(12, siteTags(site, site.single));
        site.add(20, siteTags(site, 'unrelated'));
        await repository.add(FollowRequest(tags: site.single), identity.id);

        final result = await sync(site, identity);

        expect(result.error, isNull);
        final follow = await followOf(identity, site.single);
        expect(follow.latest, 12);
        expect(follow.thumbnail, contains('12'));
        expect(follow.unseen, 0);
        expect(follow.updated, isNotNull);
      });

      test('previews a follow of several tags with a post that carries '
          'all of them', () async {
        final List<String> tags = siteTags(site, site.multi);
        site.add(30, tags);
        // Newer, but each with one of the tags alone.
        site.add(31, [tags.first]);
        site.add(32, [tags.last]);
        await repository.add(FollowRequest(tags: site.multi), identity.id);

        final result = await sync(site, identity);

        expect(result.error, isNull);
        final follow = await followOf(identity, site.multi);
        expect(follow.latest, 30);
        expect(follow.thumbnail, contains('30'));
        expect(follow.unseen, 0);
      });

      test('refreshes follows of one and of several tags together', () async {
        final List<String> tags = siteTags(site, site.multi);
        // The first of the tags, the way the app writes it.
        final String first = site.multi.split(' ').first;
        site.add(40, siteTags(site, site.single));
        site.add(41, tags);
        site.add(42, [tags.first]);
        await repository.add(FollowRequest(tags: site.single), identity.id);
        await repository.add(FollowRequest(tags: site.multi), identity.id);
        await repository.add(FollowRequest(tags: first), identity.id);

        final result = await sync(site, identity);

        expect(result.error, isNull);
        expect((await followOf(identity, site.single)).latest, 40);
        expect((await followOf(identity, site.multi)).latest, 41);
        // The tag on its own is on both of the posts that carry it.
        expect((await followOf(identity, first)).latest, 42);
      });

      test('counts the posts that are new since the last refresh', () async {
        site.add(50, siteTags(site, site.single));
        site.add(51, siteTags(site, site.multi));
        await repository.add(FollowRequest(tags: site.single), identity.id);
        await repository.add(FollowRequest(tags: site.multi), identity.id);
        await sync(site, identity);

        site.add(60, siteTags(site, site.single));
        site.add(61, siteTags(site, site.single));
        site.add(62, siteTags(site, site.multi));
        final result = await sync(site, identity, force: true);

        expect(result.error, isNull);
        final single = await followOf(identity, site.single);
        expect(single.unseen, 2);
        expect(single.latest, 61);
        expect(single.thumbnail, contains('61'));
        final multi = await followOf(identity, site.multi);
        expect(multi.unseen, 1);
        expect(multi.latest, 62);
        expect(multi.thumbnail, contains('62'));
      });

      test('marks a follow without posts as refreshed', () async {
        site.add(70, siteTags(site, 'unrelated'));
        await repository.add(FollowRequest(tags: site.single), identity.id);
        await repository.add(FollowRequest(tags: site.multi), identity.id);

        final result = await sync(site, identity);

        expect(result.error, isNull);
        for (final String tags in [site.single, site.multi]) {
          final follow = await followOf(identity, tags);
          expect(follow.updated, isNotNull);
          expect(follow.latest, isNull);
          expect(follow.thumbnail, isNull);
        }
      });

      test('leaves the follows of another account alone', () async {
        final Identity other = await identityOn(site, username: 'other');
        site.add(80, siteTags(site, site.single));
        await repository.add(FollowRequest(tags: site.single), identity.id);
        await repository.add(FollowRequest(tags: site.single), other.id);
        await repository.add(FollowRequest(tags: site.multi), other.id);

        await sync(site, identity);

        expect((await followOf(identity, site.single)).latest, 80);
        for (final String tags in [site.single, site.multi]) {
          final follow = await followOf(other, tags);
          expect(follow.updated, isNull);
          expect(follow.latest, isNull);
          expect(follow.thumbnail, isNull);
        }
        expect(await repository.all(identity: identity.id), hasLength(1));
        expect(await repository.all(identity: other.id), hasLength(2));
      });

      test(
        'does not reset the follows of another account when forced',
        () async {
          final Identity other = await identityOn(site, username: 'other');
          site.add(90, siteTags(site, site.single));
          await repository.add(FollowRequest(tags: site.single), identity.id);
          await repository.add(FollowRequest(tags: site.single), other.id);
          await sync(site, other);
          final Follow before = await followOf(other, site.single);
          expect(before.updated, isNotNull);

          await sync(site, identity, force: true);

          expect(await followOf(other, site.single), before);
        },
      );
    });
  }

  test('keeps the follows of each site to itself', () async {
    final sites = [FakeE621Site(), FakeRule34Site(), FakeDerpibooruSite()];
    final identities = [for (final site in sites) await identityOn(site)];
    // The same tag is followed on every site, and found on each under an id
    // of its own.
    for (final (int index, FakeSite site) in sites.indexed) {
      site.add(100 + index, ['sunset']);
      await repository.add(
        const FollowRequest(tags: 'sunset'),
        identities[index].id,
      );
    }

    for (final (int index, FakeSite site) in sites.indexed) {
      final result = await sync(site, identities[index], force: true);
      expect(result.error, isNull);
    }

    for (final (int index, FakeSite site) in sites.indexed) {
      final follow = await followOf(identities[index], 'sunset');
      expect(follow.latest, 100 + index, reason: site.name);
      expect(follow.thumbnail, contains('${100 + index}'));
      // Every site was only asked by its own identity.
      expect(site.searches, isNotEmpty);
      expect(await repository.all(identity: identities[index].id), [follow]);
    }
  });
}
