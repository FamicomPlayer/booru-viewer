import 'dart:io';

import 'package:e1547/client/client.dart';
import 'package:e1547/identity/identity.dart';
import 'package:flutter_test/flutter_test.dart';

Identity identityOf(String host, [Map<String, String>? headers]) =>
    Identity(id: 1, host: host, username: 'tester', headers: headers);

void main() {
  group('cookies', () {
    test('are read from and written to a header', () {
      final cookies = parseCookies('a=1; b=two=2;c=3 ; ; broken');

      expect(cookies, {'a': '1', 'b': 'two=2', 'c': '3'});
      expect(formatCookies(cookies), 'a=1; b=two=2; c=3');
      expect(parseCookies(null), isEmpty);
    });

    test('follow what a response sets', () {
      final cookies = {'session': 'old', 'gone': 'x', 'kept': 'y'};

      // Several folded into one, with the comma of a date among them.
      const String folded =
          'gone=; Max-Age=0; expires=Thu, 01 Jan 1970 00:00:00 GMT, added=1; '
          'path=/';
      applySetCookies(cookies, ['session=new; path=/; HttpOnly', folded]);

      expect(cookies, {'session': 'new', 'kept': 'y', 'added': '1'});
    });

    test('are left alone by a response that sets none', () {
      final cookies = {'session': 'old'};

      applySetCookies(cookies, null);

      expect(cookies, {'session': 'old'});
    });
  });

  group('a Rule34 login', () {
    test('takes both of its cookies', () {
      expect(rule34SessionOf({'user_id': '42', 'pass_hash': 'abc'}), (
        userId: '42',
        passHash: 'abc',
      ));
    });

    test('is not taken from a page that anyone gets to see', () {
      // A visitor who is logged out has a session of sorts, and may have
      // one cookie left over from an earlier login.
      expect(rule34SessionOf({'PHPSESSID': 'x', 'cf_clearance': 'y'}), isNull);
      expect(rule34SessionOf({'user_id': '42'}), isNull);
      expect(rule34SessionOf({'pass_hash': 'abc'}), isNull);
      expect(rule34SessionOf({'user_id': '42', 'pass_hash': ''}), isNull);
      expect(rule34SessionOf({'user_id': 'me', 'pass_hash': 'abc'}), isNull);
    });

    test('is found wherever an identity keeps it', () {
      expect(
        identityOf('https://rule34.xxx', {
          'user_id': '42',
          'pass_hash': 'abc',
        }).hasWebLogin,
        isTrue,
      );
      expect(
        identityOf('https://rule34.xxx', {
          HttpHeaders.cookieHeader: 'user_id=42; pass_hash=abc',
        }).hasWebLogin,
        isTrue,
      );
    });

    test('is not what an API key is', () {
      final identity = identityOf('https://rule34.xxx', {
        'user_id': '42',
        'api_key': 'k3y',
      });

      expect(identity.needsWebLogin, isTrue);
      expect(identity.hasWebLogin, isFalse);
    });
  });

  group('a Derpibooru login', () {
    test('is told by the cookies of its session', () {
      expect(
        identityOf('https://derpibooru.org', {
          HttpHeaders.cookieHeader: 'other=1; _philomena_key=abc',
        }).hasWebLogin,
        isTrue,
      );
      expect(
        identityOf('https://derpibooru.org', {
          HttpHeaders.cookieHeader: 'user_remember_me=abc',
        }).hasWebLogin,
        isTrue,
      );
    });

    test('is not what a key or a passed check is', () {
      final identity = identityOf('https://derpibooru.org', {
        'key': 'k3y',
        HttpHeaders.cookieHeader: 'cf_clearance=x; techaro.lol-anubis-auth=y',
      });

      expect(identity.needsWebLogin, isTrue);
      expect(identity.hasWebLogin, isFalse);
    });
  });

  test('e621 has no use for a web login', () {
    final identity = identityOf('https://e621.net', {
      HttpHeaders.cookieHeader: '_danbooru_session=abc',
    });

    expect(identity.needsWebLogin, isFalse);
    expect(identity.hasWebLogin, isFalse);
  });

  group('the account of an identity', () {
    Identity named(String host, String? username, [Map<String, String>? h]) =>
        Identity(id: 1, host: host, username: username, headers: h);

    test('is the id of its user on Rule34', () {
      const String host = 'https://rule34.xxx';

      expect(webAccountOf(named(host, 'sasha', {'user_id': '42'})), '42');
      expect(
        webAccountOf(
          named(host, 'sasha', {
            HttpHeaders.cookieHeader: 'user_id=42; pass_hash=abc',
          }),
        ),
        '42',
      );
      expect(webAccountOf(named(host, '42')), '42');
      expect(webAccountOf(named(host, 'User #42')), '42');
      expect(webAccountOf(named(host, 'sasha')), isNull);
      expect(webAccountOf(named(host, null)), isNull);
    });

    test('is the name of its user on Derpibooru', () {
      const String host = 'https://derpibooru.org';

      expect(webAccountOf(named(host, 'Sasha ')), 'sasha');
      expect(webAccountOf(named(host, null)), isNull);
      // Names the app gives where it does not know one.
      expect(webAccountOf(named(host, 'Derpibooru User')), isNull);
      expect(webAccountOf(named(host, 'Anonymous')), isNull);
    });
  });

  group('a captured login', () {
    Identity rule34(int id, {String? userId, String? host}) => Identity(
      id: id,
      host: host ?? 'https://rule34.xxx',
      username: userId,
      headers: {'user_id': ?userId},
    );

    Identity pony(int id, String? name) =>
        Identity(id: id, host: 'https://derpibooru.org', username: name);

    const e621 = Identity(id: 9, host: 'https://e621.net', username: 'fox');

    Identity? target(
      List<Identity> identities,
      String host,
      String? account, {
      Identity? preferred,
    }) => webLoginTarget(
      identities: identities,
      host: host,
      account: account,
      preferred: preferred,
    );

    test('goes to the identity it was made for', () {
      final Identity a = rule34(1, userId: '42');
      final Identity b = rule34(2, userId: '43');

      expect(target([a, b], 'https://rule34.xxx', '43', preferred: b), b);
      expect(target([a, b], 'https://rule34.xxx', '42', preferred: a), a);
    });

    test('does not go to the identity of another account', () {
      final Identity a = rule34(1, userId: '42');
      final Identity b = rule34(2, userId: '43');

      // Made for one account, but logged into as the other.
      expect(target([a, b], 'https://rule34.xxx', '43', preferred: a), b);
      // An account that has no identity yet takes a new one.
      expect(target([a, b], 'https://rule34.xxx', '44', preferred: a), isNull);
      expect(target([a], 'https://rule34.xxx', '43', preferred: a), isNull);
    });

    test('is taken by an identity that is nobody\'s yet', () {
      final Identity guest = rule34(1);
      final Identity a = rule34(2, userId: '42');

      expect(target([guest], 'https://rule34.xxx', '42', preferred: guest), guest);
      // Unless the account already has an identity of its own.
      expect(target([guest, a], 'https://rule34.xxx', '42', preferred: guest), a);
    });

    test('for a new account never goes to the identity in use', () {
      final Identity a = rule34(1, userId: '42');

      expect(target([a], 'https://rule34.xxx', '43'), isNull);
      // The account is known already, and keeps its identity.
      expect(target([a], 'https://rule34.xxx', '42'), a);
    });

    test('does not go to an identity of another site', () {
      final Identity a = rule34(1, userId: '42');
      final Identity other = rule34(2, userId: '42', host: 'https://gelbooru.com');

      expect(target([e621], 'https://rule34.xxx', '42', preferred: e621), isNull);
      expect(target([other], 'https://rule34.xxx', '42', preferred: other), isNull);
      expect(target([a], 'https://derpibooru.org', '42', preferred: a), isNull);
      // The API of a site is the site.
      final Identity api = rule34(3, userId: '42', host: 'https://api.rule34.xxx');
      expect(target([api], 'https://rule34.xxx', '42', preferred: api), api);
    });

    test('is told apart by name on Derpibooru', () {
      final Identity sasha = pony(1, 'Sasha');
      final Identity unnamed = pony(2, 'Derpibooru User');
      const String host = 'https://derpibooru.org';

      expect(target([sasha], host, 'sasha', preferred: sasha), sasha);
      expect(target([sasha], host, 'Rarity', preferred: sasha), isNull);
      expect(target([sasha, unnamed], host, 'Rarity', preferred: unnamed), unnamed);
      expect(target([sasha, unnamed], host, 'SASHA', preferred: unnamed), sasha);
    });

    test('stays where it was made when the site does not say whose it is', () {
      final Identity sasha = pony(1, 'Sasha');

      expect(
        target([sasha], 'https://derpibooru.org', null, preferred: sasha),
        sasha,
      );
      expect(target([sasha], 'https://derpibooru.org', null), isNull);
    });
  });

  group('PhilomenaPage', () {
    test('reads who a page is shown to', () {
      final page = PhilomenaPage.parse('''
        <html><head><meta name="csrf-token" content="tok3n"></head><body>
        <div class="js-datastore" data-user-id="5" data-user-name="Tester"
            data-user-is-signed-in="true"></div></body></html>''');

      expect(page.isSite, isTrue);
      expect(page.signedIn, isTrue);
      expect(page.userName, 'Tester');
      expect(page.csrfToken, 'tok3n');
    });

    test('reads a visitor who is not logged in', () {
      final page = PhilomenaPage.parse('''
        <html><head><meta content="tok3n" name="csrf-token"></head><body>
        <div class="js-datastore" data-user-is-signed-in="false"
            data-user-name=""></div></body></html>''');

      expect(page.isSite, isTrue);
      expect(page.signedIn, isFalse);
      expect(page.userName, isNull);
      expect(page.csrfToken, 'tok3n');
    });

    test('tells a check in front of the site from the site', () {
      final page = PhilomenaPage.parse(
        '<html><head><title>Making sure you are not a bot!</title></head> '
        '<body>data-user-is-signed-in="true"</body></html>',
      );

      expect(page.isSite, isFalse);
      expect(page.signedIn, isFalse);
      expect(page.csrfToken, isNull);
    });
  });
}
