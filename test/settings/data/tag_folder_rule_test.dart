import 'package:e1547/post/post.dart';
import 'package:e1547/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_support/posts.dart';

void main() {
  /// The rules a user adds, behind those the app starts out with.
  const List<TagFolderRule> rules = [
    ...TagFolderRule.defaultRules,
    TagFolderRule(tags: ['female big_butt'], folder: 'booty buttcheeks'),
    TagFolderRule(tags: ['rating:safe female'], folder: 'cute'),
  ];

  Post post(List<String> tags, {Rating rating = Rating.e}) =>
      samplePost(tags: {'general': tags}, rating: rating);

  String? folderOf(Post post, [List<TagFolderRule> among = rules]) =>
      TagFolderRule.folderFor(post, among);

  group('an entry of several tags', () {
    test('asks for all of them', () {
      const rule = TagFolderRule(tags: ['female big_butt'], folder: 'booty');

      expect(rule.matches(post(['female', 'big_butt', 'solo'])), isTrue);
      expect(rule.matches(post(['female', 'solo'])), isFalse);
      expect(rule.matches(post(['big_butt'])), isFalse);
    });

    test('wins over a rule that asks for one of them alone', () {
      // The rule for `female` comes first, and matches as well.
      expect(folderOf(post(['female', 'big_butt'])), 'booty buttcheeks');
      expect(folderOf(post(['female', 'solo'])), 'female');
    });

    test('reads the rating of a post', () {
      expect(folderOf(post(['female'], rating: Rating.s)), 'cute');
      expect(folderOf(post(['female'], rating: Rating.q)), 'female');
      expect(folderOf(post(['male'], rating: Rating.s)), 'male');
    });

    test('leaves the choice to the first of rules that ask for as much', () {
      final Post both = post(['female', 'big_butt'], rating: Rating.s);

      expect(folderOf(both), 'booty buttcheeks');
      expect(folderOf(both, rules.reversed.toList()), 'cute');
    });

    test('takes a tag turned around', () {
      const rule = TagFolderRule(tags: ['female -male'], folder: 'solo');

      expect(rule.matches(post(['female'])), isTrue);
      expect(rule.matches(post(['female', 'male'])), isFalse);
    });
  });

  group('entries of a rule', () {
    const rule = TagFolderRule(tags: ['furry', 'anthro tail'], folder: 'furry');

    test('are alternatives', () {
      expect(rule.matches(post(['furry'])), isTrue);
      expect(rule.matches(post(['anthro', 'tail'])), isTrue);
      expect(rule.matches(post(['anthro'])), isFalse);
    });

    test('count for as much as the one that matched', () {
      expect(rule.specificity(post(['furry'])), 1);
      expect(rule.specificity(post(['furry', 'anthro', 'tail'])), 2);
      expect(rule.specificity(post(['tail'])), isNull);
    });
  });

  group('the tags of a post', () {
    test('are found in every category', () {
      final Post categorized = samplePost(
        tags: {
          'artist': ['some_artist'],
          'species': ['female'],
          'general': ['big_butt'],
        },
      );

      expect(folderOf(categorized), 'booty buttcheeks');
    });

    test('are matched whichever way their name is written', () {
      // Derpibooru keeps spaces and namespaces in the names of its tags.
      final Post pony = post(['twilight sparkle', 'artist:some one', 'Safe']);

      for (final String entry in [
        'twilight sparkle',
        'twilight_sparkle',
        'Twilight_Sparkle',
        'artist:some_one',
        'twilight_sparkle safe',
      ]) {
        expect(
          folderOf(pony, [
            TagFolderRule(tags: [entry], folder: 'pony'),
          ]),
          'pony',
          reason: entry,
        );
      }
    });

    test('are not matched by a part of their name', () {
      expect(
        folderOf(post(['female_focus', 'big_butt_(disambiguation)'])),
        isNull,
      );
    });
  });

  group('a folder', () {
    test('is not chosen where no rule matches', () {
      expect(folderOf(post(['landscape'])), isNull);
      expect(folderOf(post(['female']), const []), isNull);
    });

    test('may be several folders deep', () {
      expect(TagFolderRule.segmentsOf('ponies/ twilight sparkle '), [
        'ponies',
        'twilight sparkle',
      ]);
      expect(
        folderOf(post(['female']), const [
          TagFolderRule(tags: ['female'], folder: r'a\b/c'),
        ]),
        'a/b/c',
      );
    });

    test('stays below the downloads and within what a filesystem takes', () {
      expect(TagFolderRule.segmentsOf('../../etc'), ['etc']);
      expect(TagFolderRule.segmentsOf('/abs/./path/'), ['abs', 'path']);
      expect(TagFolderRule.segmentsOf('what? <now>: "this"|*'), [
        'what_ _now__ _this___',
      ]);
      expect(TagFolderRule.segmentsOf('trailing. /dots...'), [
        'trailing',
        'dots',
      ]);
    });

    test('is skipped where its name leaves nothing to create', () {
      expect(
        folderOf(post(['female']), const [
          TagFolderRule(tags: ['female'], folder: ' ../. '),
          TagFolderRule(tags: ['female'], folder: 'kept'),
        ]),
        'kept',
      );
    });
  });

  test('rules survive being saved', () {
    final List<TagFolderRule> restored = TagFolderRule.decodeList(
      TagFolderRule.encodeList(rules),
    );

    expect(restored.map((e) => e.folder), rules.map((e) => e.folder));
    expect(restored.map((e) => e.tags), rules.map((e) => e.tags));
    expect(
      folderOf(post(['female', 'big_butt']), restored),
      'booty buttcheeks',
    );
  });
}
