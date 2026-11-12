import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:e1547/client/client.dart';
import 'package:e1547/follow/follow.dart';
import 'package:e1547/identity/identity.dart';
import 'package:e1547/logs/logs.dart';
import 'package:e1547/pool/data/client.dart';
import 'package:e1547/post/post.dart';
import 'package:e1547/shared/shared.dart';
import 'package:e1547/tag/tag.dart';
import 'package:e1547/traits/traits.dart';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

class FollowSync {
  FollowSync({
    required this.repository,
    required this.identity,
    required this.traits,
    required this.postsClient,
    this.poolsClient,
    this.tagsClient,
    this.force,
  });

  late final Logger logger = Logger('FollowSync', {
    'identity': identity.id,
    'user': identity.usernameOrAnon,
    'host': identity.host,
  });

  late final BooruEngine engine = BooruEngine.fromHost(identity.host);

  final int refreshAmount = 16;
  final Duration refreshRate = const Duration(hours: 1);

  final FollowRepository repository;
  final Identity identity;
  final ValueNotifier<Traits> traits;
  final PostClient postsClient;
  final PoolClient? poolsClient;
  final TagClient? tagsClient;
  final bool? force;

  CancelableOperation<void>? _operation;

  bool get running => _operation != null;

  bool get completed => _operation?.isCompleted ?? false;

  bool get cancelled => _operation?.isCanceled ?? false;

  void cancel() {
    logger.debug('Sync cancelled for {user} on {host}');
    _operation?.cancel();
  }

  Object? get error => _error;
  Object? _error;

  Stream<double> get progress =>
      _remaining.stream.map((e) => _total == null ? 0 : e / _total!);

  late final StreamController<int> _remaining = BehaviorSubject()
    ..stream.listen(
      (value) => logger.debug('Synced {done} of {total} follows', {
        'done': (_total ?? 0) - value,
        'total': _total,
      }),
      onError: (exception, stacktrace) {
        _error = exception;
        // an Error means we are wrong, an Exception means the world is
        if (exception is Error) {
          logger.error(
            'Sync failed for {user} on {host}',
            null,
            exception,
            stacktrace,
          );
        } else {
          logger.warn(
            'Sync failed for {user} on {host}',
            null,
            exception,
            stacktrace,
          );
        }
      },
      onDone: () => logger.info('Synced {total} follows for {user} on {host}', {
        'total': _total,
      }),
    );

  int? _total;

  /// Failures in a row that the site, not a follow, may be to blame for, and
  /// how many of them end a run.
  int _siteFailures = 0;
  static const int _siteFailureLimit = 3;
  (Object, StackTrace)? _outage;

  List<String> _previousTags = [];

  void _assertNoDuplicates(List<String> tags) {
    bool tagsAreDifferent = !const DeepCollectionEquality().equals(
      _previousTags,
      tags,
    );
    assert(tagsAreDifferent, 'Sync tried refreshing same follows twice!');
    _previousTags = tags;
  }

  Future<void> run() async {
    _operation ??= CancelableOperation.fromFuture(_run());
    await _operation!.valueOrCancellation();
  }

  Future<void> _run() async {
    logger.info('Sync started for {user} on {host}');
    try {
      if (force ?? false) {
        logger.debug('Force refreshing all follows');
        await repository.transaction(() async {
          List<Follow> follows = await repository.all(
            types: [FollowType.notify, FollowType.update],
            // Without it the follows of every other site are reset as well.
            identity: identity.id,
          );
          for (final follow in follows) {
            await repository.replace(follow.copyWith(updated: null));
          }
        });
      }

      while (!cancelled) {
        List<Follow> follows = [];

        follows.addAll(
          await repository.outdated(
            minAge: refreshRate,
            types: [FollowType.notify, FollowType.update],
            identity: identity.id,
          ),
        );

        follows.addAll(
          await repository.fresh(
            types: [FollowType.bookmark],
            identity: identity.id,
          ),
        );

        _total ??= follows.length;
        _remaining.add(_total! - follows.length);

        // Only e621 has a search that takes several follows at once and still
        // tells which of them a post belongs to.
        List<Follow> singles = engine == BooruEngine.e621
            ? follows.where((e) => e.isSingle).toList()
            : [];
        if (singles.isNotEmpty) {
          await _save(await _refreshSingles(singles));
          continue;
        }

        List<Follow> others = follows.whereNot(singles.contains).toList();
        if (others.isNotEmpty) {
          await _save(await _refreshEach(others));
          // What was refreshed is kept, the run still ends as a failed one.
          if (_outage case (final Object error, final StackTrace stacktrace)) {
            Error.throwWithStackTrace(error, stacktrace);
          }
          continue;
        }

        break;
      }
    } on Object catch (error, stacktrace) {
      _remaining.addError(error, stacktrace);
    } finally {
      _remaining.close();
    }
  }

  Future<void> _save(List<Follow> updates) => repository.transaction(() async {
    for (final update in updates) {
      await repository.replace(update);
    }
  });

  Future<List<Follow>> _refreshSingles(List<Follow> singles) async {
    // A batch has to fit one page of the site, or the posts of some follows
    // are cut off and the follows still count as refreshed.
    List<Follow> follows = singles.take(min(40, 320 ~/ refreshAmount)).toList();
    List<String> tags = follows.map((e) => e.tags).toList();
    _assertNoDuplicates(tags);

    int limit = follows.length * refreshAmount;
    List<Post> allPosts = await rateLimit(
      postsClient.byTags(tags: tags, page: 1, limit: limit),
    );

    Map<Follow, List<Post>> assign(List<Follow> follows, List<Post> posts) {
      Map<Follow, List<Post>> result = {};
      for (final follow in follows) {
        result.putIfAbsent(follow, () => []);
        for (final post in posts) {
          if (post.hasTag(follow.alias ?? follow.tags)) {
            result.update(follow, (value) => value..add(post));
          }
        }
      }
      return result;
    }

    Map<Follow, List<Post>> updates = assign(follows, allPosts);

    bool hasLeftovers() {
      List<Post> picked = updates.values.flattened.toList();
      List<Post> leftovers = allPosts.whereNot(picked.contains).toList();
      if (leftovers.isNotEmpty) {
        logger.info('Sync found {count} leftover posts', {
          'count': leftovers.length,
          'posts': leftovers.map((e) => e.id).toList(),
        });
      }
      return leftovers.isNotEmpty;
    }

    if (hasLeftovers() && tagsClient != null) {
      for (final update in Map.from(updates).entries) {
        Follow follow = update.key;
        List<Post> posts = update.value;
        if (posts.isNotEmpty) continue;
        String? alias = await rateLimit(
          tagsClient!.aliases(query: {'search[antecedent_name]': follow.tags}),
        );
        if (alias != follow.alias) {
          Follow updated = follow.copyWith(alias: alias);
          updates[updated] = updates.remove(follow)!;
          await repository.replace(updated);
          updates = assign(updates.keys.toList(), allPosts);
          if (!hasLeftovers()) break;
        }
      }
    }

    List<Follow> result = [];
    for (final update in updates.entries) {
      Follow follow = update.key;
      List<Post> posts = update.value;
      bool limitReached = posts.length >= 5;
      bool latestReached = posts.any((e) => e.id == follow.latest);
      bool depleted = allPosts.length < limit;
      if ([limitReached, latestReached, depleted].any((e) => e)) {
        posts.removeWhere((e) => e.isDeniedBy(traits.value.denylist));
        result.add(follow.withUnseen(posts));
      } else {
        // If we didn't reach the limit but there's a mismatch (like tag aliasing),
        // we must still update the timestamp to prevent an infinite loop.
        result.add(follow.withTimestamp());
      }
    }
    return result;
  }

  /// Refreshes follows with a search each: every follow of Rule34 and
  /// Derpibooru, and on any site those that ask for several tags.
  Future<List<Follow>> _refreshEach(List<Follow> follows) async {
    // Written down in rounds, so that progress shows and survives a failure.
    follows = follows.take(15).toList();
    _assertNoDuplicates(follows.map((e) => e.tags).toList());

    List<Follow> result = [];
    for (Follow follow in follows) {
      if (cancelled) break;
      try {
        List<Post> posts = await rateLimit(
          postsClient.page(query: {'tags': follow.tags}, limit: refreshAmount),
        );
        posts.removeWhere((e) => e.isDeniedBy(traits.value.denylist));
        follow = follow.withUnseen(posts);
        if (engine == BooruEngine.e621) follow = await _withPool(follow);
        result.add(follow);
        _siteFailures = 0;
      } on Object catch (error, stacktrace) {
        final int? status = error is ClientException
            ? error.response?.statusCode
            : null;
        // Without an answer, or turned away as a client, every follow fails.
        final bool everyFollowFails =
            error is ClientException &&
            (status == null ||
                status == HttpStatus.unauthorized ||
                status == HttpStatus.forbidden ||
                status == HttpStatus.tooManyRequests);
        if (!everyFollowFails) {
          // One follow that keeps failing must not hold up those after it.
          logger.warn('Follow {tags} failed to refresh', {
            'tags': follow.tags,
          }, error);
          result.add(follow.withTimestamp());
          // A search the site turns down is at fault itself. Anything else
          // may be the site failing, which failures in a row give away: the
          // follows after them are then left to be refreshed another time.
          final bool turnedDown =
              status != null && status >= 400 && status < 500;
          if (!turnedDown && ++_siteFailures >= _siteFailureLimit) {
            _outage = (error, stacktrace);
            break;
          }
          continue;
        }
        // A failed request must not pass for a follow without new posts.
        // What was refreshed so far is kept, the failure returns next round.
        if (result.isEmpty) rethrow;
        break;
      }
    }
    return result;
  }

  /// Names a follow of a pool after it.
  Future<Follow> _withPool(Follow follow) async {
    RegExpMatch? match = poolRegex().firstMatch(follow.tags);
    if (poolsClient == null || follow.title != null || match == null) {
      return follow;
    }
    try {
      return follow.withPool(
        await poolsClient!.get(id: int.parse(match.namedGroup('id')!)),
      );
    } on ClientException catch (e) {
      if (e.response?.statusCode != HttpStatus.notFound) rethrow;
      logger.info('No pool for {tags}, set to bookmarked', {
        'tags': follow.tags,
      });
      return follow.copyWith(type: FollowType.bookmark);
    }
  }
}
