import 'dart:convert';

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

  final List<String> tags;
  final String folder;

  Map<String, dynamic> toJson() => {
    'tags': tags,
    'folder': folder,
  };

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
