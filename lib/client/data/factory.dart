import 'package:e1547/app/app.dart';
import 'package:e1547/client/client.dart';
import 'package:e1547/identity/identity.dart';
import 'package:e1547/traits/traits.dart';
import 'package:flutter/foundation.dart';

class ClientConfig {
  ClientConfig({
    required this.identity,
    required this.traits,
    required this.storage,
  });

  final Identity identity;
  final ValueNotifier<Traits> traits;
  final AppStorage storage;
}

const String _e621Host = 'https://e621.net';
const String _e926Host = 'https://e926.net';

class ClientFactory {
  Client create(ClientConfig config) => Client(
    identity: config.identity,
    traits: config.traits,
    storage: config.storage,
  );

  IdentityRequest createDefaultIdentity() {
    return const IdentityRequest(host: _e926Host);
  }

  TraitsRequest createDefaultTraits(Identity identity) {
    final engine = BooruEngine.fromHost(identity.host);
    return switch (engine) {
      BooruEngine.e621 => TraitsRequest(
        identity: identity.id,
        denylist: ['young -rating:s', 'gore', 'scat', 'watersports'],
        homeTags: 'score:>=20',
      ),
      BooruEngine.derpibooru => TraitsRequest(
        identity: identity.id,
        denylist: ['grimdark', 'grotesque'],
        homeTags: 'score.gte:20',
      ),
      BooruEngine.rule34 => TraitsRequest(
        identity: identity.id,
        denylist: ['gore', 'scat'],
        homeTags: 'score:>=20',
      ),
    };
  }

  String? registrationUrl(String host) {
    final engine = BooruEngine.fromHost(host);
    return switch (engine) {
      BooruEngine.e621 => '$host/users/new',
      BooruEngine.derpibooru => 'https://derpibooru.org/users/sign_up',
      BooruEngine.rule34 => 'https://rule34.xxx/index.php?page=account&s=reg',
    };
  }

  String? apiKeysUrl(String host) {
    final engine = BooruEngine.fromHost(host);
    return switch (engine) {
      BooruEngine.e621 => '$host/api_keys',
      BooruEngine.derpibooru => 'https://derpibooru.org/users/edit',
      BooruEngine.rule34 => 'https://rule34.xxx/index.php?page=account&s=options',
    };
  }

  String? unsafeHostUrl(String host) {
    return switch (normalizeHostUrl(host)) {
      _e926Host => _e621Host,
      _ => null,
    };
  }
}
