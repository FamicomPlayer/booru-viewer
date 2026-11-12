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

    setUp(() {
      rejections = 0;
      adapter = FakeHttpAdapter((options) async {
        if (rejections > 0) {
          rejections--;
          return const FakeResponse('', status: HttpStatus.tooManyRequests);
        }
        return FakeResponse.json({'ok': true});
      });
      dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
        ..httpClientAdapter = adapter;
      dio.interceptors.add(
        RateLimitInterceptor(dio: dio, baseDelay: Duration.zero),
      );
    });

    test('repeats a request that was turned away', () async {
      rejections = 2;

      final response = await dio.get('/posts');

      expect(response.data, {'ok': true});
      expect(adapter.requests, hasLength(3));
    });

    test('gives up after its retries are spent', () async {
      rejections = 10;

      await expectLater(
        dio.get('/posts'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            HttpStatus.tooManyRequests,
          ),
        ),
      );
      expect(adapter.requests, hasLength(4));
    });

    test('does not repeat a write', () async {
      rejections = 1;

      await expectLater(dio.post('/favorites'), throwsA(isA<DioException>()));
      expect(adapter.requests, hasLength(1));
    });

    test('does not repeat other failures', () async {
      adapter = FakeHttpAdapter(
        (options) async => const FakeResponse('', status: 500),
      );
      dio.httpClientAdapter = adapter;

      await expectLater(dio.get('/posts'), throwsA(isA<DioException>()));
      expect(adapter.requests, hasLength(1));
    });

    test('waits longer with each retry, up to a limit', () {
      final interceptor = RateLimitInterceptor(dio: dio);

      expect(interceptor.delayFor(0, null), const Duration(seconds: 1));
      expect(interceptor.delayFor(1, null), const Duration(seconds: 2));
      expect(interceptor.delayFor(2, null), const Duration(seconds: 4));
      expect(interceptor.delayFor(9, null), interceptor.maxDelay);
    });

    test('waits as long as the host asks for', () {
      final interceptor = RateLimitInterceptor(dio: dio);
      Response<void> hinted(String value) => Response(
        requestOptions: RequestOptions(),
        headers: Headers.fromMap({
          HttpHeaders.retryAfterHeader: [value],
        }),
      );

      expect(interceptor.delayFor(0, hinted('3')), const Duration(seconds: 3));
      expect(interceptor.delayFor(0, hinted('600')), interceptor.maxDelay);
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
