import 'package:dio/dio.dart';

import 'fake_http.dart';
import 'fixtures.dart';

/// One of the sites the app browses, as far as searching its posts goes: it
/// holds posts and answers the searches of the app the way the site would.
abstract class FakeSite {
  /// What the app calls the site.
  String get name;

  String get host;

  /// The login of an identity on the site.
  Map<String, String> get headers;

  /// A tag as an artist is followed by, and several tags followed together.
  String get single;
  String get multi;

  /// The posts of the site, in its own format.
  final List<Map<String, Object?>> posts = [];

  /// Every search the app asked the site for.
  final List<String> searches = [];

  /// Adds a post that carries [tags], in the spelling of the site.
  void add(int id, List<String> tags);

  /// The tags of a post in the spelling of the site.
  List<String> tagsOf(Map<String, Object?> post);

  /// Whether a post with [tags] is found by [search].
  bool matches(String search, List<String> tags);

  /// The search and the size of the page that a request asks for.
  (String, int)? read(RequestOptions options);

  /// Wraps posts the way the site answers a search.
  FakeResponse wrap(List<Map<String, Object?>> posts);

  late final FakeHttpAdapter adapter = FakeHttpAdapter((options) async {
    final request = read(options);
    if (request == null) {
      return const FakeResponse.html('Not Found', status: 404);
    }
    final (String search, int limit) = request;
    searches.add(search);
    final found =
        posts.where((post) => matches(search, tagsOf(post))).toList()
          ..sort((a, b) => (b['id']! as int).compareTo(a['id']! as int));
    return wrap(found.take(limit).toList());
  });
}

class FakeE621Site extends FakeSite {
  @override
  String get name => 'e621';

  @override
  String get host => 'https://e621.net';

  @override
  Map<String, String> get headers => const {};

  @override
  String get single => 'canine';

  @override
  String get multi => 'wolf female';

  @override
  void add(int id, List<String> tags) {
    final template = loadFixtureList('posts.json').first;
    posts.add({
      ...template,
      'id': id,
      'sample': {
        ...template['sample']! as Map<String, Object?>,
        'url': 'https://static.e621.example/sample/$id.jpg',
      },
      'tags': {
        for (final key in (template['tags']! as Map<String, Object?>).keys)
          key: key == 'general' ? tags : <String>[],
      },
    });
  }

  @override
  List<String> tagsOf(Map<String, Object?> post) =>
      ((post['tags']! as Map)['general'] as List).cast<String>();

  @override
  bool matches(String search, List<String> tags) {
    final terms = search.split(' ').where((e) => e.isNotEmpty).toList();
    // A tilde marks alternatives, of which one is enough.
    final any = terms.where((e) => e.startsWith('~')).map((e) => e.substring(1));
    final all = terms.where((e) => !e.startsWith('~'));
    return all.every(tags.contains) && (any.isEmpty || any.any(tags.contains));
  }

  @override
  (String, int)? read(RequestOptions options) {
    if (options.uri.path != '/posts.json') return null;
    final query = options.uri.queryParameters;
    return (query['tags'] ?? '', int.parse(query['limit'] ?? '75'));
  }

  @override
  FakeResponse wrap(List<Map<String, Object?>> posts) =>
      FakeResponse.json({'posts': posts});
}

class FakeRule34Site extends FakeSite {
  @override
  String get name => 'Rule34';

  @override
  String get host => 'https://rule34.xxx';

  @override
  Map<String, String> get headers => const {'user_id': '42', 'api_key': 'k3y'};

  @override
  String get single => 'example_artist';

  @override
  String get multi => 'big_butt animated';

  @override
  void add(int id, List<String> tags) {
    final template = loadFixtureList('rule34_posts.json').first;
    posts.add({
      ...template,
      'id': id,
      'sample_url': 'https://api-cdn.rule34.xxx/samples/1/sample_$id.jpg',
      'tags': tags.join(' '),
      'tag_info': [
        for (final tag in tags) {'count': 1, 'type': 'tag', 'tag': tag},
      ],
    });
  }

  @override
  List<String> tagsOf(Map<String, Object?> post) =>
      (post['tags']! as String).split(' ');

  @override
  bool matches(String search, List<String> tags) =>
      search.split(' ').where((e) => e.isNotEmpty).every(tags.contains);

  @override
  (String, int)? read(RequestOptions options) {
    final query = options.uri.queryParameters;
    if (options.uri.host != 'api.rule34.xxx' || query['page'] != 'dapi') {
      return null;
    }
    return (query['tags'] ?? '', int.parse(query['limit'] ?? '100'));
  }

  // The site answers a search without results with nothing at all.
  @override
  FakeResponse wrap(List<Map<String, Object?>> posts) =>
      posts.isEmpty ? const FakeResponse('') : FakeResponse.json(posts);
}

class FakeDerpibooruSite extends FakeSite {
  @override
  String get name => 'Derpibooru';

  @override
  String get host => 'https://derpibooru.org';

  @override
  Map<String, String> get headers => const {'key': 'k3y'};

  // The site keeps spaces in the names of its tags, and has names with an
  // underscore of their own.
  @override
  String get single => 'artist:example_one';

  @override
  String get multi => 'twilight_sparkle animated';

  @override
  void add(int id, List<String> tags) => posts.add({
    'id': id,
    'width': 1280,
    'height': 720,
    'format': 'png',
    'size': 2048,
    'representations': {
      for (final name in ['full', 'large', 'medium', 'small', 'thumb'])
        name: 'https://derpicdn.net/img/2026/1/1/$id/$name.png',
    },
    'tags': tags,
    'score': 10,
    'faves': 4,
    'comment_count': 2,
    'created_at': '2026-01-01T12:00:00Z',
    'description': '',
    'uploader': 'fixture_uploader',
    'uploader_id': 9,
  });

  @override
  List<String> tagsOf(Map<String, Object?> post) =>
      (post['tags']! as List).cast<String>();

  @override
  bool matches(String search, List<String> tags) =>
      // A comma stands between terms that are all asked for, and a term in
      // brackets holds alternatives.
      search.split(', ').where((e) => e.isNotEmpty).every((term) {
        final inner = term.startsWith('(') && term.endsWith(')')
            ? term.substring(1, term.length - 1)
            : term;
        return inner.split(' || ').any(tags.contains);
      });

  @override
  (String, int)? read(RequestOptions options) {
    if (options.uri.path != '/api/v1/json/search/images') return null;
    final query = options.uri.queryParameters;
    return (query['q'] ?? '', int.parse(query['per_page'] ?? '15'));
  }

  @override
  FakeResponse wrap(List<Map<String, Object?>> posts) => FakeResponse.json({
    'images': posts,
    'interactions': <Object>[],
    'total': posts.length,
  });
}

/// The tags of [search], which is in the spelling of the app, in that of
/// [site].
List<String> siteTags(FakeSite site, String search) => [
  for (final tag in search.split(' '))
    // Only this one name has an underscore that is its own.
    site is FakeDerpibooruSite && tag != 'artist:under_score'
        ? tag.replaceAll('_', ' ')
        : tag,
];
