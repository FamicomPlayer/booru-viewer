import 'package:e1547/comment/comment.dart';
import 'package:e1547/identity/identity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_support/fake_http.dart';
import '../../_support/harness.dart';

/// The comment API answers in XML whatever format it is asked for.
const String comments = '''
<?xml version="1.0" encoding="UTF-8"?><comments type="array"><comment created_at="2026-11-12 16:25" post_id="1001" body="An &quot;ancient&quot; relic &amp; more &lt;3" creator="First&#039;s" id="7048019" creator_id="1435782"/><comment created_at="2026-11-12 16:25" post_id="1001" body="Second
line" creator="Second" id="7100561" creator_id="1226864"/>
</comments>''';

void main() {
  late FakeHttpAdapter adapter;
  late CommentClient client;
  late String body;

  setUpAll(initializeTestApp);

  setUp(() {
    body = comments;
    adapter = FakeHttpAdapter(
      (options) async =>
          FakeResponse(body, contentType: 'text/xml;charset=UTF-8'),
    );
    const identity = Identity(
      id: 1,
      host: 'https://rule34.xxx',
      username: '42',
      headers: {'user_id': '42', 'api_key': 'k3y'},
    );
    client = CommentClient(dio: fakeDio(adapter, identity), identity: identity);
  });

  test('asks for the comments of a post', () async {
    await client.page(page: 1, query: {'search[post_id]': '1001'});

    final query = adapter.requests.single.uri.queryParameters;
    expect(query['s'], 'comment');
    expect(query['post_id'], '1001');
    expect(query['api_key'], 'k3y');
  });

  test('tells the id of a comment from that of its post', () async {
    final result = await client.page(query: {'search[post_id]': '1001'});

    expect(result.map((e) => e.id), [7048019, 7100561]);
    expect(result.map((e) => e.postId), [1001, 1001]);
    expect(result.map((e) => e.creatorId), [1435782, 1226864]);
  });

  test('resolves the entities of the markup', () async {
    final result = await client.page(query: {'search[post_id]': '1001'});

    expect(result.first.body, 'An "ancient" relic & more <3');
    expect(result.first.creatorName, "First's");
    expect(result.last.body, 'Second\nline');
  });

  test('resolves an entity only once', () async {
    body =
        '<comments><comment post_id="1" body="&amp;lt;b&amp;gt; &#x41;&#66;" '
        'creator="a" id="2" creator_id="3"/></comments>';

    final result = await client.page(query: {'search[post_id]': '1'});

    expect(result.single.body, '&lt;b&gt; AB');
  });

  test('ends after the first page, which holds every comment', () async {
    final second = await client.page(
      page: 2,
      query: {'search[post_id]': '1001'},
    );

    expect(second, isEmpty);
    expect(adapter.requests, isEmpty);
  });

  test('has no comments for a post without any', () async {
    body =
        '<?xml version="1.0" encoding="UTF-8"?><comments type="array"></comments>';

    expect(await client.page(query: {'search[post_id]': '5'}), isEmpty);
  });
}
