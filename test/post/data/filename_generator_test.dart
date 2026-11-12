import 'dart:convert';

import 'package:e1547/post/post.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_support/posts.dart';

void main() {
  const int limit = DownloadFileNameGenerator.maxFileNameBytes;

  int bytes(String value) => utf8.encode(value).length;

  String name(Post post, [String? format]) =>
      DownloadFileNameGenerator.generate(post, format: format);

  setUp(Rule34Post.reset);

  group('a name', () {
    test('follows the format it is given', () {
      final Post post = samplePost(
        id: 42,
        ext: 'png',
        score: 7,
        tags: {
          'artist': ['some_artist'],
          'character': ['hero', 'villain'],
          'copyright': ['series'],
          'general': ['sunset'],
        },
      );

      expect(name(post), 'some_artist - 42.png');
      expect(name(post, '   '), 'some_artist - 42.png');
      expect(name(post, '{id}.{ext}'), '42.png');
      expect(
        name(post, '{id} {artist} {copyright} {character}.{extension}'),
        '42 some_artist series hero, villain.png',
      );
      expect(name(post, '{rating}_{score}_{id}'), 's_7_42.png');
    });

    test('names a post without an artist', () {
      expect(
        name(
          samplePost(
            id: 5,
            tags: {
              'general': ['sunset'],
            },
          ),
        ),
        'unknown_artist - 5.jpg',
      );
    });

    test('drops the namespace that some sites file tags under', () {
      final Post post = samplePost(
        id: 9,
        tags: {
          'artist': ['artist:some_one'],
          'character': ['oc:somepony'],
        },
      );

      expect(
        name(post, '{artist} {character} {id}'),
        'some_one somepony 9.jpg',
      );
    });

    test('holds nothing that a filesystem turns down', () {
      final Post post = samplePost(
        id: 3,
        tags: {
          'artist': [r'a/b\c:d*e?f"g<h>i|j'],
        },
      );

      final String result = name(post);

      expect(result, 'a_b_c_d_e_f_g_h_i_j - 3.jpg');
      expect(result, isNot(matches(RegExp(r'[/\\:*?"<>|]'))));
    });
  });

  group('a name that is too long', () {
    Post crowded({int id = 123456, String ext = 'jpg'}) => samplePost(
      id: id,
      ext: ext,
      tags: {
        'artist': [for (int i = 0; i < 40; i++) 'artist_number_$i'],
        'character': [for (int i = 0; i < 40; i++) 'character_number_$i'],
        'general': [for (int i = 0; i < 40; i++) 'general_tag_$i'],
      },
    );

    test('is cut down to what a filesystem takes', () {
      for (final String format in [
        ...DownloadFileNameGenerator.presets.map((e) => e.format),
        '{tags} {general} {artist} {character}',
        '{artist}',
      ]) {
        final String result = name(crowded(), format);

        expect(bytes(result), lessThanOrEqualTo(limit), reason: format);
        expect(result, endsWith('.jpg'), reason: format);
      }
    });

    test('keeps its id and the start of its lists', () {
      final String result = name(
        crowded(),
        '{artist} {character} - {id}.{extension}',
      );

      expect(result, startsWith('artist_number_0, artist_number_1'));
      expect(result, contains('character_number_0'));
      expect(result, endsWith(' - 123456.jpg'));
      // Whole tags are given up, not parts of them.
      expect(result, isNot(matches(RegExp(r'_number_?,|_numbe[^r]'))));
    });

    test('is still told apart from its neighbors', () {
      const String format = '{artist} {id}';

      final String first = name(crowded(id: 1000001), format);
      final String second = name(crowded(id: 1000002), format);

      expect(first, isNot(second));
      expect(first, contains('1000001'));
      expect(second, contains('1000002'));
    });

    test('is cut when a single tag is to blame', () {
      final Post post = samplePost(
        id: 77,
        ext: 'webm',
        tags: {
          'artist': ['a' * 400],
        },
      );

      for (final String format in ['{artist} - {id}', '{id} {artist}']) {
        final String result = name(post, format);

        expect(bytes(result), lessThanOrEqualTo(limit), reason: format);
        expect(result, contains('77'), reason: format);
        expect(result, endsWith('.webm'), reason: format);
      }
    });

    test('is measured in bytes, and not cut within a character', () {
      // Three bytes each, and two code units each for the last of them.
      final Post post = samplePost(
        id: 8,
        tags: {
          'artist': ['${'魔' * 120}${'😀' * 40}'],
        },
      );

      final String result = name(post, '{artist}.{extension}');

      expect(result.length, lessThan(limit));
      expect(bytes(result), lessThanOrEqualTo(limit));
      expect(bytes(result), greaterThan(limit - 8));
      // Cutting a character in half leaves a name that cannot be encoded.
      expect(utf8.decode(utf8.encode(result)), result);
      expect(result, isNot(contains('\uFFFD')));
      expect(result, endsWith('.jpg'));
    });

    test('is left alone when it fits', () {
      final Post post = samplePost(
        id: 8,
        tags: {
          'artist': ['a' * (limit - ' - 8.jpg'.length)],
        },
      );

      final String result = name(post);

      expect(bytes(result), limit);
      expect(result, '${'a' * (limit - 8)} - 8.jpg');
    });
  });
}
