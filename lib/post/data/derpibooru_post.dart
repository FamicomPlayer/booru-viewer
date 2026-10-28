import 'package:deep_pick/deep_pick.dart';
import 'package:e1547/post/post.dart';

abstract final class DerpibooruPost {
  static Post fromJson(dynamic json) => pick(json).letOrThrow(
    (post) {
      final id = post('id').asIntOrThrow();
      final width = post('width').asIntOrThrow();
      final height = post('height').asIntOrThrow();
      final ext = post('format').asStringOrNull() ?? 'png';
      final size = post('size').asIntOrNull() ?? 0;

      final representations = post('representations').asMapOrEmpty<String, dynamic>();
      final fileUrl = representations['full']?.toString() ??
          post('view_url').asStringOrNull();
      final sampleUrl = representations['large']?.toString() ??
          representations['medium']?.toString() ??
          fileUrl;
      final previewUrl = representations['thumb']?.toString() ??
          representations['small']?.toString() ??
          sampleUrl;

      // Variants
      final Map<String, String?> variants = {};
      representations.forEach((key, value) {
        if (value != null) {
          variants[key] = value.toString();
        }
      });

      // Tags categorization
      final rawTags = post('tags').asListOrEmpty((p) => p.asStringOrThrow());
      final Map<String, List<String>> tagMap = {
        'general': [],
        'artist': [],
        'character': [],
        'species': [],
        'meta': [],
      };

      Rating rating = Rating.s;
      for (final tag in rawTags) {
        final lower = tag.toLowerCase();
        if (lower == 'explicit') {
          rating = Rating.e;
        } else if (lower == 'questionable' || lower == 'suggestive') {
          if (rating != Rating.e) rating = Rating.q;
        }

        if (lower.startsWith('artist:') || lower.startsWith('editor:')) {
          tagMap['artist']!.add(tag.replaceFirst(RegExp(r'^(artist|editor):'), ''));
        } else if (lower.startsWith('character:') || lower.startsWith('oc:')) {
          tagMap['character']!.add(tag.replaceFirst(RegExp(r'^(character|oc):'), ''));
        } else if (lower.startsWith('species:')) {
          tagMap['species']!.add(tag.replaceFirst('species:', ''));
        } else if (lower.startsWith('meta:') || lower.startsWith('spoiler:')) {
          tagMap['meta']!.add(tag);
        } else {
          tagMap['general']!.add(tag);
        }
      }

      // Interactions (favorites and votes)
      final interactions = post('interactions').asListOrEmpty((p) => p.asMapOrEmpty<String, dynamic>());
      bool isFavorited = false;
      int? vote;
      for (final interaction in interactions) {
        final type = interaction['interaction_type'];
        if (type == 'faved') {
          isFavorited = true;
        } else if (type == 'up') {
          vote = 1;
        } else if (type == 'down') {
          vote = -1;
        }
      }

      final score = post('score').asIntOrNull() ??
          ((post('upvotes').asIntOrNull() ?? 0) - (post('downvotes').asIntOrNull() ?? 0));

      final sourceUrl = post('source_url').asStringOrNull();
      final List<String> sources = (sourceUrl != null && sourceUrl.isNotEmpty) ? [sourceUrl] : [];

      return Post(
        id: id,
        file: fileUrl,
        sample: sampleUrl,
        preview: previewUrl,
        width: width,
        height: height,
        ext: ext,
        size: size,
        variants: variants.isEmpty ? null : variants,
        tags: tagMap,
        uploaderId: post('uploader_id').asIntOrNull() ?? 0,
        uploaderName: post('uploader').asStringOrNull(),
        createdAt: post('created_at').asDateTimeOrNull() ?? DateTime.now(),
        updatedAt: post('updated_at').asDateTimeOrNull(),
        score: score,
        vote: vote,
        isDeleted: post('deletion_reason').asStringOrNull() != null,
        rating: rating,
        favCount: post('faves').asIntOrNull() ?? 0,
        isFavorited: isFavorited,
        commentCount: post('comment_count').asIntOrNull() ?? 0,
        description: post('description').asStringOrNull() ?? '',
        sources: sources,
        pools: null,
        relationships: const Relationships(
          parentId: null,
          hasChildren: false,
          hasActiveChildren: null,
          children: [],
        ),
      );
    },
  );
}
