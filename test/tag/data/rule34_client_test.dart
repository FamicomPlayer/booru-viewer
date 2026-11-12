import 'package:dio/dio.dart';
import 'package:e1547/identity/identity.dart';
import 'package:e1547/tag/tag.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_support/fake_http.dart';
import '../../_support/harness.dart';

void main() {
  late FakeHttpAdapter adapter;
  late TagClient client;

  setUpAll(initializeTestApp);

  setUp(() {
    // The site labels this JSON as a web page.
    adapter = FakeHttpAdapter(
      (options) async => const FakeResponse.html(
        '[{"label":"sunset (4404024)","value":"sunset"},'
        '{"label":"sunset_sky (1200)","value":"sunset_sky"},'
        '{"label":"sun","value":"sun"}]',
      ),
    );
    const identity = Identity(
      id: 1,
      host: 'https://rule34.xxx',
      username: '42',
      headers: {'user_id': '42', 'api_key': 'k3y'},
    );
    client = TagClient(dio: fakeDio(adapter, identity), identity: identity);
  });

  test('reads suggestions served as a web page', () async {
    final tags = await client.autocomplete(search: 'sun');

    expect(tags.map((e) => e.name), ['sunset', 'sunset_sky', 'sun']);
    expect(tags.map((e) => e.count), [4404024, 1200, 0]);

    final Uri uri = adapter.requests.single.uri;
    expect(uri.host, 'api.rule34.xxx');
    expect(uri.path, '/autocomplete.php');
    expect(uri.queryParameters['q'], 'sun');
  });

  test('respects the limit', () async {
    expect(await client.autocomplete(search: 'sun', limit: 2), hasLength(2));
  });

  test('has no suggestions for an unreadable answer', () async {
    adapter = FakeHttpAdapter(
      (options) async => const FakeResponse.html('<html>CAPTCHA</html>'),
    );
    client = TagClient(
      dio: client.dio..httpClientAdapter = adapter,
      identity: client.identity,
    );

    expect(await client.autocomplete(search: 'sun'), isEmpty);
  });

  test('does not ask about searches it cannot complete', () async {
    expect(await client.autocomplete(search: ''), isEmpty);
    expect(await client.autocomplete(search: 's'), isEmpty);
    expect(await client.autocomplete(search: 'rating:safe'), isEmpty);
    expect(adapter.requests, isEmpty);
  });

  test('pages tags through the suggestions, which have one page', () async {
    final first = await client.page(
      page: 1,
      query: {'search[name_matches]': 'sun*'},
    );
    final second = await client.page(
      page: 2,
      query: {'search[name_matches]': 'sun*'},
    );

    expect(first, hasLength(3));
    expect(second, isEmpty);
    expect(adapter.requests.single.uri.queryParameters['q'], 'sun');
  });

  test('passes cancellation on', () async {
    final token = CancelToken()..cancel();

    await expectLater(
      client.autocomplete(search: 'sun', cancelToken: token),
      throwsA(isA<DioException>()),
    );
  });
}
