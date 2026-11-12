import 'package:e1547/client/client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BooruEngine', () {
    test('is told from the host', () {
      expect(BooruEngine.fromHost('https://e621.net'), BooruEngine.e621);
      expect(BooruEngine.fromHost('https://e926.net'), BooruEngine.e621);
      expect(
        BooruEngine.fromHost('https://derpibooru.org'),
        BooruEngine.derpibooru,
      );
      expect(BooruEngine.fromHost('https://rule34.xxx'), BooruEngine.rule34);
      expect(
        BooruEngine.fromHost('https://API.Rule34.xxx'),
        BooruEngine.rule34,
      );
    });

    test('links to a post where its website shows it', () {
      expect(
        BooruEngine.e621.webUrl('https://e621.net', '/posts/12'),
        'https://e621.net/posts/12',
      );
      expect(
        BooruEngine.derpibooru.webUrl('https://derpibooru.org', '/posts/12'),
        'https://derpibooru.org/images/12',
      );
      expect(
        BooruEngine.rule34.webUrl('https://api.rule34.xxx', '/posts/12'),
        'https://rule34.xxx/index.php?page=post&s=view&id=12',
      );
      expect(
        BooruEngine.rule34.webUrl('rule34.xxx', '/posts/12'),
        'https://rule34.xxx/index.php?page=post&s=view&id=12',
      );
    });

    test('leaves other paths on the host', () {
      expect(
        BooruEngine.e621.webUrl('https://e621.net', '/pools/3'),
        'https://e621.net/pools/3',
      );
      expect(
        BooruEngine.e621.webUrl('https://e621.net', '/posts?tags=cat'),
        'https://e621.net/posts?tags=cat',
      );
    });
  });

  group('Rule34Credentials', () {
    const String key =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

    test('reads the string the site hands out', () {
      final creds = Rule34Credentials.parse('&api_key=$key&user_id=1234567');

      expect(creds?.apiKey, key);
      expect(creds?.userId, '1234567');
    });

    test('reads the parameters in any order', () {
      final creds = Rule34Credentials.parse(' user_id=12&api_key=abc123 ');

      expect(creds?.apiKey, 'abc123');
      expect(creds?.userId, '12');
    });

    test('reads the parameters out of a whole url', () {
      final creds = Rule34Credentials.parse(
        'https://api.rule34.xxx/index.php?page=dapi&s=post&q=index'
        '&api_key=abc123&user_id=12',
      );

      expect(creds?.apiKey, 'abc123');
      expect(creds?.userId, '12');
    });

    test('reads an id and a key given side by side', () {
      expect(Rule34Credentials.parse('12:abc123')?.userId, '12');
      expect(Rule34Credentials.parse('12:abc123')?.apiKey, 'abc123');
      expect(Rule34Credentials.parse('abc123 12')?.userId, '12');
      expect(Rule34Credentials.parse('abc123 12')?.apiKey, 'abc123');
    });

    test('rejects what holds no credentials', () {
      expect(Rule34Credentials.parse(''), isNull);
      expect(Rule34Credentials.parse('   '), isNull);
      expect(Rule34Credentials.parse('abc123'), isNull);
      expect(Rule34Credentials.parse('&api_key=abc123'), isNull);
      expect(Rule34Credentials.parse('&user_id=12'), isNull);
      expect(Rule34Credentials.parse('name:abc123'), isNull);
    });
  });
}
