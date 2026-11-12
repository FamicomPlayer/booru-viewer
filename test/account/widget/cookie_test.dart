import 'dart:io';

import 'package:e1547/account/account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('withoutCloudflareCookies', () {
    test('strips Cloudflare cookies and keeps the rest', () {
      expect(
        withoutCloudflareCookies({
          HttpHeaders.cookieHeader:
              'cf_clearance=dead; _danbooru_session=keep; __cfruid=dead',
        }),
        {HttpHeaders.cookieHeader: '_danbooru_session=keep'},
      );
    });

    test('removes the header when only Cloudflare cookies remain', () {
      expect(
        withoutCloudflareCookies({
          HttpHeaders.authorizationHeader: 'Basic secret',
          HttpHeaders.cookieHeader: 'cf_clearance=dead',
        }),
        {HttpHeaders.authorizationHeader: 'Basic secret'},
      );
    });

    test('returns null when there is nothing to strip', () {
      expect(
        withoutCloudflareCookies({
          HttpHeaders.cookieHeader: '_danbooru_session=keep',
        }),
        null,
      );
      expect(withoutCloudflareCookies({}), null);
      expect(withoutCloudflareCookies(null), null);
    });

    test('keeps values containing separators intact', () {
      expect(
        withoutCloudflareCookies({
          HttpHeaders.cookieHeader: 'cf_clearance=dead; session=a=b=c',
        }),
        {HttpHeaders.cookieHeader: 'session=a=b=c'},
      );
    });
  });

  group('withCloudflareCookies', () {
    test('adds the clearance to an identity without cookies', () {
      expect(
        withCloudflareCookies(
          {HttpHeaders.authorizationHeader: 'Basic secret'},
          {'cf_clearance': 'fresh', '_danbooru_session': 'skip'},
        ),
        {
          HttpHeaders.authorizationHeader: 'Basic secret',
          HttpHeaders.cookieHeader: 'cf_clearance=fresh',
        },
      );
    });

    test('renews the clearance beside a kept session', () {
      expect(
        withCloudflareCookies(
          {HttpHeaders.cookieHeader: 'user_id=42; cf_clearance=stale'},
          {'cf_clearance': 'fresh', '__cfruid': 'new'},
        ),
        {
          HttpHeaders.cookieHeader:
              'user_id=42; cf_clearance=fresh; __cfruid=new',
        },
      );
    });

    test('returns null when the page set no clearance', () {
      expect(withCloudflareCookies(null, {}), null);
      expect(
        withCloudflareCookies(
          {HttpHeaders.cookieHeader: 'cf_clearance=stale'},
          {'_danbooru_session': 'skip'},
        ),
        null,
      );
    });
  });
}
