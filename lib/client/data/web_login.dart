import 'dart:io';

import 'package:dio/dio.dart';
import 'package:e1547/client/client.dart';
import 'package:e1547/identity/identity.dart';
import 'package:html/parser.dart' show parse;

/// The cookies that carry a login on a Philomena site such as Derpibooru.
const Set<String> philomenaSessionCookies = {
  '_philomena_key',
  'user_remember_me',
};

/// Reads the pairs of a `Cookie` header.
Map<String, String> parseCookies(String? header) {
  final Map<String, String> result = {};
  for (final String pair in (header ?? '').split(';')) {
    final int split = pair.indexOf('=');
    if (split <= 0) continue;
    result[pair.substring(0, split).trim()] = pair.substring(split + 1).trim();
  }
  return result;
}

/// Writes [cookies] as a `Cookie` header.
String formatCookies(Map<String, String> cookies) =>
    cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

// Adapters fold several cookies into one header, and dates hold commas too.
final RegExp _foldedCookies = RegExp(r',(?=\s*[^;,=\s]+=)');

/// Applies the `Set-Cookie` headers of a response to [cookies].
void applySetCookies(Map<String, String> cookies, List<String>? headers) {
  for (final String header in headers ?? const []) {
    for (final String cookie in header.split(_foldedCookies)) {
      final String pair = cookie.split(';').first;
      final int split = pair.indexOf('=');
      if (split <= 0) continue;
      final String name = pair.substring(0, split).trim();
      final String value = pair.substring(split + 1).trim();
      // A site takes a cookie back by sending it without a value.
      if (value.isEmpty) {
        cookies.remove(name);
      } else {
        cookies[name] = value;
      }
    }
  }
}

/// The two cookies that make a Rule34 login, or null when either is missing.
({String userId, String passHash})? rule34SessionOf(
  Map<String, String> cookies,
) {
  final String? userId = cookies['user_id'];
  final String? passHash = cookies['pass_hash'];
  if (userId == null || int.tryParse(userId) == null) return null;
  if (passHash == null || passHash.isEmpty) return null;
  return (userId: userId, passHash: passHash);
}

extension IdentityWebLogin on Identity {
  /// The cookies stored for the website of this identity.
  Map<String, String> get cookies => parseCookies(
    headers?[HttpHeaders.cookieHeader] ?? headers?['Cookie'],
  );

  /// The Rule34 login of this identity, from wherever it was stored.
  ({String userId, String passHash})? get rule34Session => rule34SessionOf({
    ...cookies,
    'user_id': ?headers?['user_id'],
    'pass_hash': ?headers?['pass_hash'],
  });

  /// Whether favorites are taken by the website rather than the API, which
  /// asks for a login made in a browser.
  bool get needsWebLogin => BooruEngine.fromHost(host) != BooruEngine.e621;

  /// Whether this identity holds the API key that Derpibooru lists the
  /// favorites and votes of its user for.
  bool get hasDerpibooruKey =>
      (headers?['key'] ?? headers?['X-API-Key'])?.isNotEmpty ?? false;

  /// Whether a browser login is stored for this identity.
  bool get hasWebLogin => switch (BooruEngine.fromHost(host)) {
    BooruEngine.rule34 => rule34Session != null,
    BooruEngine.derpibooru => cookies.keys.any(
      philomenaSessionCookies.contains,
    ),
    BooruEngine.e621 => false,
  };
}

/// Thrown when a website does not recognize the stored browser login.
class WebLoginException implements Exception {
  const WebLoginException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The names that an identity is given where the one of its user is not
/// known, which tell nothing of whose it is.
final RegExp _placeholderName = RegExp(
  r'^(anonymous|derpibooru user|rule34 user)$',
  caseSensitive: false,
);

/// Whether [name] stands in for a name that is not known.
bool isPlaceholderUsername(String? name) =>
    name == null || name.trim().isEmpty || _placeholderName.hasMatch(name.trim());

/// The site that [host] is a part of, as its subdomains are.
String _siteOf(String host) {
  final String name = Uri.tryParse(normalizeHostUrl(host))?.host ?? host;
  final List<String> labels = name.toLowerCase().split('.');
  return labels.skip(labels.length > 2 ? labels.length - 2 : 0).join('.');
}

/// The account that the website of [identity] knows it as, where that can
/// be told: the id of the user on Rule34, the name of the user on Derpibooru.
String? webAccountOf(Identity identity) {
  final String? name = identity.username?.trim();
  switch (BooruEngine.fromHost(identity.host)) {
    case BooruEngine.rule34:
      final String? id =
          identity.headers?['user_id'] ??
          identity.cookies['user_id'] ??
          name?.replaceFirst(RegExp('^User #'), '');
      return id != null && int.tryParse(id) != null ? id : null;
    case BooruEngine.derpibooru:
      return isPlaceholderUsername(name) ? null : name!.toLowerCase();
    case BooruEngine.e621:
      return null;
  }
}

/// The identity among [identities] that a browser login of [account] on the
/// site of [host] is stored on, or null where it takes a new one.
///
/// [preferred] is the identity that the login was made for. It is passed
/// over where it is known to be another account: the login of one account
/// must never end up on the identity of another.
Identity? webLoginTarget({
  required Iterable<Identity> identities,
  required String host,
  required String? account,
  Identity? preferred,
}) {
  final BooruEngine engine = BooruEngine.fromHost(host);
  bool onSite(Identity identity) =>
      BooruEngine.fromHost(identity.host) == engine &&
      _siteOf(identity.host) == _siteOf(host);

  if (preferred != null && !onSite(preferred)) preferred = null;
  final String? known = account?.trim().toLowerCase();
  // Whose login this is could not be told, so it stays where it was asked for.
  if (known == null || known.isEmpty) return preferred;
  if (preferred != null && webAccountOf(preferred) == known) return preferred;
  for (final Identity identity in identities) {
    if (onSite(identity) && webAccountOf(identity) == known) return identity;
  }
  // An identity that is nobody's yet takes the login as its own.
  if (preferred != null && webAccountOf(preferred) == null) return preferred;
  return null;
}

/// What a page of a Philomena site tells about its visitor.
class PhilomenaPage {
  const PhilomenaPage({
    required this.isSite,
    required this.signedIn,
    this.userName,
    this.csrfToken,
  });

  factory PhilomenaPage.parse(String html) {
    final document = parse(html);
    final store = document.querySelector('.js-datastore');
    final String? name = store?.attributes['data-user-name'];
    return PhilomenaPage(
      isSite: store != null,
      signedIn: store?.attributes['data-user-is-signed-in'] == 'true',
      userName: name == null || name.isEmpty ? null : name,
      csrfToken: document
          .querySelector('meta[name="csrf-token"]')
          ?.attributes['content'],
    );
  }

  /// False for anything put in front of the site, such as a bot check.
  final bool isSite;
  final bool signedIn;
  final String? userName;
  final String? csrfToken;
}

/// The browser login of a Philomena site, through which its website takes
/// the favorites and votes that its API has no routes for.
class PhilomenaSession {
  PhilomenaSession({required this.dio, required Identity identity})
    : _cookies = identity.cookies;

  final Dio dio;
  final Map<String, String> _cookies;
  String? _csrfToken;

  /// Sends what the script of the site sends for an interaction, and returns
  /// the new counts of the image. [page] is where the interaction is offered.
  Future<Map<String, dynamic>> send(
    String method,
    String path, {
    required String page,
    Map<String, Object?> data = const {},
  }) async {
    if (!_cookies.keys.any(philomenaSessionCookies.contains)) {
      throw const WebLoginException(
        'A web login is required for this. Log in through "Web Login" first.',
      );
    }
    _csrfToken ??= await _open(page);
    try {
      return await _send(method, path, page, data);
    } on DioException catch (e) {
      // The token belongs to the session, which the site may have renewed.
      if (e.response?.statusCode != HttpStatus.forbidden) rethrow;
      _csrfToken = await _open(page);
      return _send(method, path, page, data);
    }
  }

  /// Loads [page] for the token that the site wants back with every write.
  Future<String> _open(String page) async {
    final response = await dio.get<String>(
      page,
      options: Options(
        responseType: ResponseType.plain,
        headers: {HttpHeaders.cookieHeader: formatCookies(_cookies)},
      ),
    );
    applySetCookies(_cookies, response.headers[HttpHeaders.setCookieHeader]);
    final site = PhilomenaPage.parse(response.data ?? '');
    final String? token = site.csrfToken;
    if (!site.isSite) {
      throw const WebLoginException(
        'The site asked to verify the browser. Open "Web Login" again.',
      );
    }
    if (!site.signedIn || token == null) {
      throw const WebLoginException(
        'The web login has expired. Log in through "Web Login" again.',
      );
    }
    return token;
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    String page,
    Map<String, Object?> data,
  ) async {
    final response = await dio.request<dynamic>(
      path,
      data: {...data, '_method': method},
      options: Options(
        method: method,
        contentType: Headers.jsonContentType,
        headers: {
          HttpHeaders.cookieHeader: formatCookies(_cookies),
          HttpHeaders.refererHeader: '${dio.options.baseUrl}$page',
          'x-csrf-token': _csrfToken,
          'x-requested-with': 'xmlhttprequest',
        },
      ),
    );
    applySetCookies(_cookies, response.headers[HttpHeaders.setCookieHeader]);
    final Object? body = response.data;
    // A login page in place of the counts means the site did not take it.
    if (body is! Map<String, dynamic> || !body.containsKey('faves')) {
      throw const WebLoginException(
        'The site did not accept the web login. Log in through "Web Login" '
        'again.',
      );
    }
    return body;
  }
}
