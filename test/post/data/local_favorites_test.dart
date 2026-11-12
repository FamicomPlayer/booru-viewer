import 'dart:io';

import 'package:drift/native.dart';
import 'package:e1547/app/app.dart';
import 'package:e1547/post/post.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_support/fixtures.dart';

void main() {
  late AppDatabase sqlite;
  late Post post;

  setUp(() {
    Rule34Post.reset();
    sqlite = AppDatabase(NativeDatabase.memory());
    LocalFavorites.init(sqlite);
    post = Rule34Post.fromJson(loadFixtureList('rule34_posts.json').first);
  });

  tearDown(() => sqlite.close());

  test('remembers a favorite for its host alone', () async {
    await LocalFavorites.save('https://api.rule34.xxx', post);

    expect(LocalFavorites.isFavorited('https://rule34.xxx', post.id), isTrue);
    expect(LocalFavorites.isFavorited('https://e621.net', post.id), isFalse);
    expect(
      LocalFavorites.isFavorited('https://derpibooru.org', post.id),
      isFalse,
    );
  });

  test('lists a favorite as favorited', () async {
    expect(post.isFavorited, isFalse);

    await LocalFavorites.save('https://rule34.xxx', post);
    final saved = await LocalFavorites.getLocalFavorites('https://rule34.xxx');

    expect(saved.single.id, post.id);
    expect(saved.single.isFavorited, isTrue);
    expect(await LocalFavorites.getLocalFavorites('https://e621.net'), isEmpty);
  });

  test('forgets a removed favorite', () async {
    await LocalFavorites.save('https://rule34.xxx', post);

    await LocalFavorites.remove('https://rule34.xxx', post.id);

    expect(LocalFavorites.isFavorited('https://rule34.xxx', post.id), isFalse);
    expect(
      await LocalFavorites.getLocalFavorites('https://rule34.xxx'),
      isEmpty,
    );
  });

  test('finds the favorites of an earlier run', () async {
    final Directory directory = Directory.systemTemp.createTempSync('favs');
    addTearDown(() => directory.deleteSync(recursive: true));
    final File file = File('${directory.path}/app.db');
    await sqlite.close();

    sqlite = AppDatabase(NativeDatabase(file));
    LocalFavorites.init(sqlite);
    await LocalFavorites.save('https://rule34.xxx', post);
    await LocalFavorites.save('https://e621.net', post.copyWith(id: 77));
    await sqlite.close();

    // The app starts again and has parsed no post yet.
    Rule34Post.reset();
    sqlite = AppDatabase(NativeDatabase(file));
    LocalFavorites.init(sqlite);
    await LocalFavorites.getLocalFavorites('https://rule34.xxx');

    expect(LocalFavorites.isFavorited('https://rule34.xxx', post.id), isTrue);
    expect(LocalFavorites.isFavorited('https://e621.net', 77), isTrue);
    expect(LocalFavorites.isFavorited('https://rule34.xxx', 77), isFalse);
    expect(Rule34Post.isFavorited(post.id), isTrue);
    expect(Rule34Post.isFavorited(77), isFalse);
  });

  test('keeps favorite marks of other sites out of Rule34', () {
    Rule34Post.markFavorited(1001, true, host: 'https://e621.net');

    expect(Rule34Post.isFavorited(1001), isFalse);

    Rule34Post.markFavorited(1001, true, host: 'https://api.rule34.xxx');

    expect(Rule34Post.isFavorited(1001), isTrue);
  });
}
