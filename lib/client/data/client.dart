import 'dart:io';

import 'package:dio/dio.dart';
import 'package:e1547/account/account.dart';
import 'package:e1547/app/app.dart';
import 'package:e1547/client/client.dart';
import 'package:e1547/comment/comment.dart';
import 'package:e1547/flag/flag.dart';
import 'package:e1547/follow/follow.dart';
import 'package:e1547/history/history.dart';
import 'package:e1547/identity/identity.dart';
import 'package:e1547/pool/pool.dart';
import 'package:e1547/post/post.dart';
import 'package:e1547/query/query.dart';
import 'package:e1547/reply/reply.dart';
import 'package:e1547/shared/shared.dart';
import 'package:e1547/tag/tag.dart';
import 'package:e1547/ticket/ticket.dart';
import 'package:e1547/topic/topic.dart';
import 'package:e1547/traits/traits.dart';
import 'package:e1547/user/user.dart';
import 'package:e1547/wiki/wiki.dart';
import 'package:flutter/foundation.dart';

export 'package:dio/dio.dart' show CancelToken;

class Client with Disposable {
  Client({required this.identity, required this.traits, required this.storage})
    : dio = createDefaultDio(identity, queryCache: storage.queryCache);

  final Dio dio;
  final AppStorage storage;
  final Identity identity;
  final ValueNotifier<Traits> traits;

  late final AccountClient accounts = AccountClient(
    dio: dio,
    identity: identity,
    traits: traits,
    postsService: posts,
  );
  late final UserClient users = UserClient(dio: dio);

  late final PostClient posts = PostClient(
    dio: dio,
    pools: pools,
    traits: traits,
    identity: identity,
  );

  late final TagClient tags = TagClient(dio: dio, identity: identity);
  late final WikiClient wikis = WikiClient(dio: dio);

  late final CommentClient comments = CommentClient(dio: dio, identity: identity);

  late final PoolClient pools = PoolClient(dio: dio);
  // TODO: add Sets

  late final TopicClient topics = TopicClient(dio: dio);
  late final ReplyClient replies = ReplyClient(dio: dio);

  late final FlagClient flags = FlagClient(dio: dio);
  late final TicketClient tickets = TicketClient(dio: dio);

  late final FollowClient follows = FollowClient(
    database: storage.sqlite,
    identity: identity,
    dio: dio,
  );

  late final FollowServer followServer = FollowServer(
    database: storage.sqlite,
    identity: identity,
    traits: traits,
    postsClient: posts,
    poolsClient: pools,
    tagsClient: tags,
    onSynced: () => dio.queryCache?.invalidateKey(follows.queryKey),
  );

  late final HistoryServer historyServer = HistoryServer(
    database: storage.sqlite,
    identity: identity,
    traits: traits,
  );

  late final HistoryClient histories = HistoryClient(
    server: historyServer,
    dio: dio,
  );

  @override
  void dispose() {
    dio.close();
    for (final client in [
      accounts,
      users,
      posts,
      tags,
      wikis,
      comments,
      pools,
      topics,
      replies,
      flags,
      tickets,
      follows,
      followServer,
      historyServer,
      histories,
    ]) {
      Disposable.tryDispose(client);
    }
    super.dispose();
  }
}

extension ClientExtension on Client {
  String get host => identity.host;
  BooruEngine get engine => BooruEngine.fromHost(identity.host);
  bool get hasLogin {
    if (identity.username != null &&
        identity.username!.isNotEmpty &&
        identity.username != 'Anonymous') {
      return true;
    }
    final headers = identity.headers;
    if (headers == null) return false;
    if (headers.containsKey('key') ||
        headers.containsKey('X-API-Key') ||
        headers.containsKey('api_key') ||
        headers.containsKey('pass_hash') ||
        headers.containsKey('user_id') ||
        headers.containsKey(HttpHeaders.authorizationHeader)) {
      return true;
    }
    final cookie = headers[HttpHeaders.cookieHeader];
    if (cookie != null &&
        (cookie.contains('pass_hash') ||
         cookie.contains('user_id') ||
         cookie.contains('PHPSESSID') ||
         cookie.contains('_session'))) {
      return true;
    }
    return false;
  }
  String withHost(String path) => identity.withHost(path);
}
