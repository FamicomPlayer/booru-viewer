import 'dart:io';

import 'package:dio/dio.dart';
import 'package:e1547/client/client.dart';
import 'package:e1547/identity/identity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_support/fake_http.dart';
import '../../_support/harness.dart';

void main() {
  setUpAll(initializeTestApp);

  group('RateLimitInterceptor', () {
    late FakeHttpAdapter adapter;
    late Dio dio;

    /// How many of the coming requests are turned away.
    late int rejections;

    /// The wait the host names when it turns a request away.
    String? retryAfter;

    setUp(() {
      rejections = 0;
      retryAfter = '0';
      adapter = FakeHttpAdapter((options) async {
        if (rejections > 0) {
          rejections--;
          return FakeResponse(
            '',
            status: HttpStatus.tooManyRequests,
            headers: {
              if (retryAfter != null)
                HttpHeaders.retryAfterHeader: [retryAfter!],
            },
          );
        }
        return FakeResponse.json({'ok': true});
      });
      dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
        ..httpClientAdapter = adapter;
      dio.interceptors.add(RateLimitInterceptor(dio: dio));
    });

    Matcher turnedAway() => throwsA(
      isA<DioException>().having(
        (e) => e.response?.statusCode,
        'status',
        HttpStatus.tooManyRequests,
      ),
    );

    test('repeats a read once the host says how long to wait', () async {
      rejections = 2;

      final response = await dio.get('/posts');

      expect(response.data, {'ok': true});
      expect(adapter.requests, hasLength(3));
    });

    test('gives up after its retries are spent', () async {
      rejections = 10;

      await expectLater(dio.get('/posts'), turnedAway());
      expect(adapter.requests, hasLength(3));
    });

    test('passes a rejection on at once when no wait is named', () async {
      rejections = 1;
      retryAfter = null;

      await expectLater(dio.get('/posts'), turnedAway());
      expect(adapter.requests, hasLength(1));
    });

    test('does not hold a request for a long wait', () async {
      rejections = 1;
      retryAfter = '600';

      await expectLater(dio.get('/posts'), turnedAway());
      expect(adapter.requests, hasLength(1));
    });

    test('does not repeat a write', () async {
      rejections = 1;

      await expectLater(dio.post('/favorites'), turnedAway());
      expect(adapter.requests, hasLength(1));
    });

    test('does not repeat other failures', () async {
      adapter = FakeHttpAdapter(
        (options) async => const FakeResponse(
          '',
          status: 500,
          headers: {
            HttpHeaders.retryAfterHeader: ['0'],
          },
        ),
      );
      dio.httpClientAdapter = adapter;

      await expectLater(dio.get('/posts'), throwsA(isA<DioException>()));
      expect(adapter.requests, hasLength(1));
    });

    test('reads the wait the host asks for', () {
      final interceptor = RateLimitInterceptor(dio: dio);
      Response<void> hinted(String value) => Response(
        requestOptions: RequestOptions(),
        headers: Headers.fromMap({
          HttpHeaders.retryAfterHeader: [value],
        }),
      );

      expect(interceptor.delayFor(hinted('3')), const Duration(seconds: 3));
      expect(interceptor.delayFor(hinted('10')), interceptor.maxDelay);
      expect(interceptor.delayFor(hinted('11')), isNull);
      expect(interceptor.delayFor(hinted('soon')), isNull);
      expect(interceptor.delayFor(null), isNull);
    });
  });

  group('BooruAuthInterceptor', () {
    late FakeHttpAdapter adapter;

    setUp(() {
      adapter = FakeHttpAdapter((options) async => FakeResponse.json([]));
    });

    test('keeps a Derpibooru key on its own host', () async {
      final dio = fakeDio(
        adapter,
        const Identity(
          id: 1,
          host: 'https://derpibooru.org',
          username: 'tester',
          headers: {'key': 'k3y', 'X-API-Key': 'k3y'},
        ),
      );

      await dio.get('/api/v1/json/search/images');
      await dio.get('https://derpicdn.net/img/view/2026/1/1/1.png');

      final api = adapter.requests.first;
      expect(api.uri.queryParameters['key'], 'k3y');
      expect(api.headers['X-API-Key'], 'k3y');
      expect(api.headers, isNot(contains('key')));

      final cdn = adapter.requests.last;
      expect(cdn.uri.queryParameters, isEmpty);
      expect(cdn.headers, isNot(contains('X-API-Key')));
      expect(cdn.headers, isNot(contains('key')));
    });

    test('keeps a Rule34 key on its own host', () async {
      final dio = fakeDio(
        adapter,
        const Identity(
          id: 1,
          host: 'https://rule34.xxx',
          username: '42',
          headers: {'user_id': '42', 'api_key': 'k3y'},
        ),
      );

      await dio.get('/index.php', queryParameters: {'page': 'dapi'});
      await dio.get('https://api-cdn.rule34.xxx/images/1/a.mp4');

      expect(adapter.requests.first.uri.host, 'api.rule34.xxx');
      expect(adapter.requests.first.uri.queryParameters['api_key'], 'k3y');
      expect(adapter.requests.last.uri.queryParameters, isEmpty);
    });

    test('reads the Rule34 user from a session cookie', () async {
      final dio = fakeDio(
        adapter,
        const Identity(
          id: 1,
          host: 'https://rule34.xxx',
          username: 'somebody',
          headers: {
            HttpHeaders.cookieHeader:
                'cf_clearance=x; user_id=42; pass_hash=abc123',
            'api_key': 'k3y',
          },
        ),
      );

      await dio.get('/index.php', queryParameters: {'page': 'dapi'});

      final request = adapter.requests.single;
      expect(request.uri.queryParameters['user_id'], '42');
      expect(
        request.headers[HttpHeaders.cookieHeader],
        'cf_clearance=x; user_id=42; pass_hash=abc123',
      );
    });

    test('leaves e621 requests alone', () async {
      final dio = fakeDio(
        adapter,
        Identity(
          id: 1,
          host: 'https://e621.net',
          username: 'tester',
          headers: {
            HttpHeaders.authorizationHeader: encodeBasicAuth('tester', 'k3y'),
          },
        ),
      );

      await dio.get('/posts.json');

      final request = adapter.requests.single;
      expect(request.uri.queryParameters, isEmpty);
      expect(
        request.headers[HttpHeaders.authorizationHeader],
        encodeBasicAuth('tester', 'k3y'),
      );
    });
  });
}
