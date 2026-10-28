import 'package:deep_pick/deep_pick.dart';
import 'package:e1547/post/post.dart';

abstract final class Rule34Post {
  static Post fromJson(dynamic json) => pick(json).letOrThrow(
    (post) {
      final id = post('id').asIntOrThrow();
      final width = post('width').asIntOrNull() ?? 0;
      final height = post('height').asIntOrNull() ?? 0;

      final fileUrl = post('file_url').asStringOrNull();
      final sampleUrl = post('sample_url').asStringOrNull() ?? fileUrl;
      final previewUrl = post('preview_url').asStringOrNull() ?? sampleUrl;

      // Extract file extension
      String ext = 'jpg';
      final imageFileName = post('image').asStringOrNull() ?? fileUrl ?? '';
      final dotIndex = imageFileName.lastIndexOf('.');
      if (dotIndex != -1 && dotIndex < imageFileName.length - 1) {
        ext = imageFileName.substring(dotIndex + 1).toLowerCase();
        if (ext.contains('?')) ext = ext.split('?').first;
      }

      // Tags
      final rawTagsString = post('tags').asStringOrNull() ?? '';
      final tagList = rawTagsString
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .toList();

      final Map<String, List<String>> tagMap = {
        'general': [],
        'artist': [],
        'character': [],
        'copyright': [],
        'meta': [],
      };

      for (final tag in tagList) {
        if (tag.startsWith('artist:')) {
          tagMap['artist']!.add(tag.replaceFirst('artist:', ''));
        } else if (tag.startsWith('character:')) {
          tagMap['character']!.add(tag.replaceFirst('character:', ''));
        } else if (tag.startsWith('copyright:')) {
          tagMap['copyright']!.add(tag.replaceFirst('copyright:', ''));
        } else if (tag.startsWith('meta:')) {
          tagMap['meta']!.add(tag.replaceFirst('meta:', ''));
        } else {
          tagMap['general']!.add(tag);
        }
      }

      // Rating
      final ratingStr = (post('rating').asStringOrNull() ?? 's').toLowerCase();
      final Rating rating = switch (ratingStr) {
        'explicit' || 'e' => Rating.e,
        'questionable' || 'q' => Rating.q,
        _ => Rating.s,
      };

      // Created at date parsing
      DateTime createdAt = DateTime.now();
      final rawDate = post('created_at').asStringOrNull();
      if (rawDate != null) {
        createdAt = _parseR34Date(rawDate) ?? createdAt;
      }

      final score = post('score').asIntOrNull() ?? 0;
      final source = post('source').asStringOrNull();
      final List<String> sources = (source != null && source.isNotEmpty) ? [source] : [];

      final parentIdStr = post('parent_id').asStringOrNull();
      final parentId = parentIdStr != null ? int.tryParse(parentIdStr) : null;
      final hasChildren = post('has_children').asBoolOrNull() ??
          (post('has_children').asStringOrNull() == 'true');

      return Post(
        id: id,
        file: fileUrl,
        sample: sampleUrl,
        preview: previewUrl,
        width: width,
        height: height,
        ext: ext,
        size: 0,
        variants: null,
        tags: tagMap,
        uploaderId: post('creator_id').asIntOrNull() ?? 0,
        uploaderName: post('owner').asStringOrNull(),
        createdAt: createdAt,
        updatedAt: null,
        score: score,
        vote: null,
        isDeleted: post('status').asStringOrNull() == 'deleted',
        rating: rating,
        favCount: 0,
        isFavorited: false,
        commentCount: post('comment_count').asIntOrNull() ??
            (post('has_comments').asBoolOrNull() == true ? 1 : 0),
        description: '',
        sources: sources,
        pools: null,
        relationships: Relationships(
          parentId: (parentId != null && parentId > 0) ? parentId : null,
          hasChildren: hasChildren,
          hasActiveChildren: null,
          children: const [],
        ),
      );
    },
  );

  static DateTime? _parseR34Date(String dateStr) {
    // Try ISO first
    final direct = DateTime.tryParse(dateStr);
    if (direct != null) return direct;

    // Handles format like: "Wed Oct 28 21:25:24 +0100 2026"
    final parts = dateStr.trim().split(RegExp(r'\s+'));
    if (parts.length >= 6) {
      final monthMap = {
        'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
        'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
      };
      final month = monthMap[parts[1]];
      final day = int.tryParse(parts[2]);
      final year = int.tryParse(parts[5]);
      final timeParts = parts[3].split(':');
      if (month != null && day != null && year != null && timeParts.length == 3) {
        final hour = int.tryParse(timeParts[0]) ?? 0;
        final minute = int.tryParse(timeParts[1]) ?? 0;
        final second = int.tryParse(timeParts[2]) ?? 0;
        return DateTime.utc(year, month, day, hour, minute, second);
      }
    }
    return null;
  }
}
