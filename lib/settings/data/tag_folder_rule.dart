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
  bool matches(Post post) => tags.any(
    (entry) => post.hasTag(entry) || post.isDeniedBy([entry]),
  );

  /// The folder of the first of [rules] that [post] matches, if any.
  static String? folderFor(Post post, List<TagFolderRule> rules) {
    for (final rule in rules) {
      if (rule.folder.isEmpty) continue;
      if (rule.matches(post)) return rule.folder;
    }
    return null;
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
