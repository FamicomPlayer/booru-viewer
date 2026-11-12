import 'dart:convert';

import 'package:e1547/post/post.dart';

class TagFolderRule {
  const TagFolderRule({required this.tags, required this.folder});

  factory TagFolderRule.fromJson(Map<String, dynamic> json) => TagFolderRule(
    tags: (json['tags'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .where((t) => t.isNotEmpty)
            .toList() ??
        const [],
    folder: json['folder']?.toString().trim() ?? '',
  );

  /// The entries of this rule, one of which a post has to match. An entry
  /// names a tag, or several that are all asked for.
  final List<String> tags;
  final String folder;

  Map<String, dynamic> toJson() => {
    'tags': tags,
    'folder': folder,
  };

  /// Whether [post] belongs into the folder of this rule.
  ///
  /// An entry is read like a line of the blacklist: all of its tags have to
  /// match, `-` turns one around, and `rating:safe` and the like are
  /// understood. An entry also matches as the whole name of a tag, which is
  /// how sites that keep spaces in their tag names are written.
  bool matches(Post post) => specificity(post) != null;

  /// How many tags the most demanding entry that [post] matches asks for, or
  /// null where it matches none.
  int? specificity(Post post) {
    int? result;
    for (final String entry in tags) {
      final int? terms = post.hasTag(entry)
          ? 1
          : post.isDeniedBy([entry])
          ? entry.trim().split(RegExp(r'\s+')).length
          : null;
      if (terms != null && terms > (result ?? 0)) result = terms;
    }
    return result;
  }

  static final RegExp _separator = RegExp(r'[\\/]');
  static final RegExp _invalid = RegExp(r'[:*?"<>|\x00-\x1f]');

  /// [folder] as the folders it names below the downloads, with what a
  /// filesystem does not take as a name left out.
  static List<String> segmentsOf(String folder) => folder
      .split(_separator)
      .map(
        (e) => e
            .replaceAll(_invalid, '_')
            .trim()
            // Windows drops dots from the end of a name, and `..` leads out.
            .replaceFirst(RegExp(r'[. ]+$'), ''),
      )
      .where((e) => e.isNotEmpty)
      .toList();

  /// The folder that [post] is downloaded into, if any of [rules] names one.
  ///
  /// Of the rules that match, the one that asks for the most tags decides,
  /// so that `female big_butt` is not lost to a rule for `female` alone.
  /// Among rules that ask for as much, the first one does.
  static String? folderFor(Post post, List<TagFolderRule> rules) {
    String? result;
    int best = 0;
    for (final rule in rules) {
      final String folder = segmentsOf(rule.folder).join('/');
      if (folder.isEmpty) continue;
      final int? specificity = rule.specificity(post);
      if (specificity != null && specificity > best) {
        best = specificity;
        result = folder;
      }
    }
    return result;
  }

  static List<TagFolderRule> decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return defaultRules;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => TagFolderRule.fromJson(e as Map<String, dynamic>))
          .toList();
    } on Object catch (_) {
      return defaultRules;
    }
  }

  static String encodeList(List<TagFolderRule> rules) {
    return jsonEncode(rules.map((r) => r.toJson()).toList());
  }

  static const List<TagFolderRule> defaultRules = [
    TagFolderRule(tags: ['furry', 'anthro'], folder: 'furry'),
    TagFolderRule(tags: ['female'], folder: 'female'),
    TagFolderRule(tags: ['male'], folder: 'male'),
  ];
}
