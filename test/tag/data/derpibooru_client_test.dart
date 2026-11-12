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
    adapter = FakeHttpAdapter(
      (options) async => FakeResponse.json({
        'tags': [
          {
            'id': 1,
            'name': 'twilight sparkle',
            'category': 'character',
            'images': 337259,
          },
          {
            'id': 2,
            'name': 'artist:under_score',
            'category': 'origin',
            'images': 222,
          },
        ],
        'total': 2,
      }),
    );
    const identity = Identity(
      id: 1,
      host: 'https://derpibooru.org',
      username: 'tester',
      headers: {'key': 'k3y'},
    );
    client = TagClient(dio: fakeDio(adapter, identity), identity: identity);
  });

  String? search() => adapter.requests.single.uri.queryParameters['q'];

  test('writes the names of tags the way a search takes them', () async {
    final tags = await client.autocomplete(search: 'tw');

    expect(tags.map((e) => e.name), ['twilight_sparkle', 'artist:under_score']);
    expect(tags.map((e) => e.count), [337259, 222]);
    // Makers of an image are filed under a category of their own name.
    expect(tags.map((e) => e.category), [4, 1]);
    expect(search(), 'tw*');
  });

  test('completes a name in both ways it may be written', () async {
    await client.autocomplete(search: 'twilight_sp');

    expect(search(), 'twilight_sp* || twilight sp*');
  });

  test('pages tags by the start of their name', () async {
    await client.page(page: 2, query: {'search[name_matches]': 'artist:un_*'});

    final query = adapter.requests.single.uri.queryParameters;
    expect(query['q'], 'artist:un_* || artist:un *');
    expect(query['page'], '2');
  });
}
