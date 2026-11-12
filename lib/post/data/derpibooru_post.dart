import 'package:deep_pick/deep_pick.dart';
import 'package:e1547/post/post.dart';

abstract final class DerpibooruPost {
  /// [interactions] is the list of the same name from the response that
  /// held [json], it tells which images the user favorited or voted on.
  static Post fromJson(dynamic json, {List<dynamic>? interactions}) => pick(json).letOrThrow(
    (post) {
      final id = post('id').asIntOrThrow();
      final width = post('width').asIntOrThrow();
      final height = post('height').asIntOrThrow();
      final ext = post('format').asStringOrNull() ?? 'png';
      final size = post('size').asIntOrNull() ?? 0;

      final representations = post('representations').asMapOrEmpty<String, dynamic>();
      final fileUrl = representations['full']?.toString() ??
          post('view_url').asStringOrNull();
      // Every representation of a video is a video, only its thumbnails are
      // also served as a gif.
      final String? still = (ext == 'webm' || ext == 'mp4')
          ? representations['thumb']?.toString().replaceFirst(
              RegExp(r'\.(webm|mp4)$'),
              '.gif',
            )
          : null;
      final sampleUrl = still ??
          representations['large']?.toString() ??
          representations['medium']?.toString() ??
          fileUrl;
      final previewUrl = still ??
          representations['thumb']?.toString() ??
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
      for (final raw in rawTags) {
        final lower = raw.toLowerCase();
        if (lower == 'explicit') {
          rating = Rating.e;
        } else if (lower == 'questionable' || lower == 'suggestive') {
          if (rating != Rating.e) rating = Rating.q;
        }

        // A tag keeps its whole name, namespace included, with its spaces
        // written the way the app writes them. Anything less could not be
        // searched for or followed again.
        final tag = raw.replaceAll(' ', '_');
        if (lower.startsWith('artist:') || lower.startsWith('editor:')) {
          tagMap['artist']!.add(tag);
        } else if (lower.startsWith('character:') || lower.startsWith('oc:')) {
          tagMap['character']!.add(tag);
        } else if (lower.startsWith('species:')) {
          tagMap['species']!.add(tag);
        } else if (lower.startsWith('meta:') || lower.startsWith('spoiler:')) {
          tagMap['meta']!.add(tag);
        } else {
          tagMap['general']!.add(tag);
        }
      }

      // The API lists these beside the images of a response, not within them.
      bool isFavorited = false;
      int? vote;
      for (final interaction in interactions ?? const []) {
        if (interaction is! Map || interaction['image_id'] != id) continue;
        switch (interaction['interaction_type']) {
          case 'faved':
            isFavorited = true;
          case 'voted':
            vote = interaction['value'] == 'up' ? 1 : -1;
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
