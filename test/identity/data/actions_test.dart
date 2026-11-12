import 'dart:io';

import 'package:e1547/identity/identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('withoutLoginHeaders', () {
    test('removes every kind of credential', () {
      expect(
        withoutLoginHeaders({
          HttpHeaders.authorizationHeader: 'Basic secret',
          'key': 'a',
          'X-API-Key': 'a',
          'user_id': '42',
          'api_key': 'b',
          'apikey': 'b',
          'pass_hash': 'c',
        }),
        isEmpty,
      );
    });

    test('finds a session whatever way its cookies were written down', () {
      expect(
        withoutLoginHeaders({
          'Cookie': 'cf_clearance=keep;user_id=42;  pass_hash=abc',
        }),
        {'Cookie': 'cf_clearance=keep'},
      );
    });

    test('ends a session kept in cookies', () {
      expect(
        withoutLoginHeaders({
          HttpHeaders.cookieHeader:
              'cf_clearance=keep; user_id=42; pass_hash=abc; PHPSESSID=x',
        }),
        {HttpHeaders.cookieHeader: 'cf_clearance=keep'},
      );
    });

    test('drops a cookie header that only held a session', () {
      expect(
        withoutLoginHeaders({
          HttpHeaders.userAgentHeader: 'Agent/1.0',
          HttpHeaders.cookieHeader: 'user_id=42; pass_hash=abc',
        }),
        {HttpHeaders.userAgentHeader: 'Agent/1.0'},
      );
    });

    test('leaves the given headers untouched', () {
      final headers = {'api_key': 'b'};

      withoutLoginHeaders(headers);

      expect(headers, {'api_key': 'b'});
    });
  });
}
