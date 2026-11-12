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
