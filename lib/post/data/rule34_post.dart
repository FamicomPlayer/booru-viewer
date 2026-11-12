import 'dart:async';

import 'package:deep_pick/deep_pick.dart';
import 'package:dio/dio.dart';
import 'package:e1547/app/data/storage.dart';
import 'package:e1547/client/client.dart';
import 'package:e1547/post/post.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:html/parser.dart' show parse;

abstract final class Rule34Post {
  static final Map<String, int> _tagCategoryCache = {};
  static final Set<int> _favoritedPostIds = <int>{};

  static const Set<String> _knownCopyrights = {
    'overwatch', 'overwatch_2', 'pokemon', 'genshin_impact', 'honkai_star_rail',
    'league_of_legends', 'fate_(series)', 'fate/stay_night', 'fate/grand_order',
    'cyberpunk', 'cyberpunk_2077', 'touhou', 'vocaloid', 'marvel', 'dc_comics',
    'disney', 'nintendo', 'sega', 'capcom', 'street_fighter', 'tekken',
    'final_fantasy', 'final_fantasy_vii', 'dead_or_alive', 'evangelion', 'naruto',
    'one_piece', 'bleach', 'dragon_ball', 'hololive', 'nijisanji', 'arknights',
    'azur_lane', 'blue_archive', 'nikke', 'warhammer', 'mario_(series)', 'zelda',
    'sonic_the_hedgehog', 'metroid', 'resident_evil', 'mass_effect', 'halo',
    'spy_x_family', 'chainsaw_man', 'my_hero_academia', 'jujutsu_kaisen',
  };

  static const Set<String> _knownMeta = {
    '3d', 'render', '3d_animation', 'sound', 'video', 'webm', 'mp4', 'loop',
    'animated', 'animation', 'censor', 'uncensored', 'mosaic_censorship',
    'bar_censor', 'highres', 'absurdres', 'superabsurdres', 'lowres', 'png',
    'jpg', 'gif', 'photoshop', 'blender', 'source_filmmaker', 'sfm', 'ai_generated',
    'stable_diffusion', 'commission', 'patreon_reward', 'gumroad_reward', 'fanbox',
    'text', 'watermark', 'signature', 'dated', 'english_text', 'japanese_text',
    'bad_id', 'duplicate', 'sound_warning', 'epilepsy_warning', 'png_version_available',
  };

  static const Set<String> _knownGeneral = {
    '1girls', '2girls', '3girls', 'solo', 'female', 'female_only', 'breasts',
    'large_breasts', 'huge_breasts', 'small_breasts', 'medium_breasts', 'areola',
    'areolae', 'nipples', 'ass', 'thick_ass', 'thighs', 'thick_thighs', 'wide_hips',
    'hips', 'navel', 'belly', 'pussy', 'vagina', 'penis', 'oral', 'anal',
    'fingering', 'masturbation', 'sex', 'cum', 'panties', 'thong', 'g-string',
    'underwear', 'bra', 'bikini', 'swimsuit', 'dress', 'skirt', 'shirt',
    'see-through', 'transparent_clothing', 'translucent_clothing', 'long_sleeves',
    'glasses', 'choker', 'piercing', 'piercings', 'tattoo', 'tattoos',
    'mole_(marking)', 'beauty_mark', 'thick', 'curvy', 'bbw', 'chubby',
    'curvaceous', 'voluptuous', 'black_hair', 'blonde_hair', 'brown_hair',
    'black_lipstick', 'red_lipstick', 'smile', 'blush', 'goth', 'goth_girl',
    'bar_(place)', 'shiny_skin', 'skindentation', 'slightly_chubby',
    'slightly_chubby_female', 'solo_female', 'voluptuous_female', 'curvy_female',
    'curvy_figure', 'chubby_female', 'hands_behind_head', 'highleg_panties',
    'leg_strap', 'legwear', 'mesh', 'mesh_shirt', 'mesh_top', 'navel_piercing',
    'nipple_piercing', 'nipples_visible_through_clothing', 'nose_piercing',
    'pierced_belly_button', 'pierced_nipples', 'thigh_tattoo', 'wide_thighs',
    'big_areolae', 'big_nipples', 'areolae_visible_through_clothing',
  };

  // A single page of results carries well over a thousand distinct tags.
  static const int _maxTagCacheEntries = 20000;

  /// Tag categories as named by the `tag_info` field of the API.
  static const Map<String, int> _serverTagTypes = {
    'tag': 0,
    'artist': 1,
    'copyright': 3,
    'character': 4,
    'metadata': 5,
  };

  static void initDatabase(AppDatabase db) {
    // No-op: tag caching is kept strictly in-memory to avoid disk storage bloat.
  }

  static void markFavorited(int id, bool fav, {Post? post, String host = 'rule34.xxx'}) {
    if (fav) {
      _favoritedPostIds.add(id);
      if (post != null) {
        LocalFavorites.save(host, post);
      }
    } else {
      _favoritedPostIds.remove(id);
      LocalFavorites.remove(host, id);
    }
  }

  static bool isFavorited(int id) =>
      _favoritedPostIds.contains(id) || LocalFavorites.isFavorited(id);

  static int? getCachedTagCategory(String tag) {
    final norm = tag.trim().toLowerCase();
    return _tagCategoryCache[tag] ??
        _tagCategoryCache[norm] ??
        _tagCategoryCache[norm.replaceAll(' ', '_')] ??
        _tagCategoryCache[norm.replaceAll('_', ' ')];
  }

  static void cacheTagCategory(String tag, int category, {bool persist = false}) {
    final norm = tag.trim().toLowerCase().replaceAll(' ', '_');
    // Reinserting keeps recently written tags at the far end of the eviction order.
    _tagCategoryCache.remove(norm);
    if (_tagCategoryCache.length >= _maxTagCacheEntries) {
      _tagCategoryCache.remove(_tagCategoryCache.keys.first);
    }
    _tagCategoryCache[norm] = category;
  }

  /// Synchronous, instant categorization for a tag using memory cache and semantic rules.
  static int categorizeTagInstantly(String tag, {String source = ''}) {
    final norm = tag.trim().toLowerCase().replaceAll(' ', '_');

    // 1. Check memory / persistent cache
    final cached = getCachedTagCategory(norm);
    if (cached != null) return cached;

    // 2. Artist check from source URL
    if (source.isNotEmpty && norm.length > 2) {
      final strippedNorm = norm.replaceAll('_', '');
      if (source.contains('/$norm') ||
          source.contains('=$norm') ||
          source.contains('/$strippedNorm') ||
          source.contains('=$strippedNorm') ||
          (source.contains('status/') && (source.contains(norm) || source.contains(strippedNorm)))) {
        cacheTagCategory(norm, 1);
        return 1;
      }
    }

    // Common artist naming patterns
    if (norm.startsWith('by_') || norm.startsWith('art_by_')) {
      cacheTagCategory(norm, 1);
      return 1;
    }

    // 3. Known Meta
    if (_knownMeta.contains(norm)) {
      cacheTagCategory(norm, 5, persist: false);
      return 5;
    }

    // 4. Known Copyright
    if (_knownCopyrights.contains(norm)) {
      cacheTagCategory(norm, 3, persist: false);
      return 3;
    }

    // 5. Parenthetical category / Character heuristic:
    if (norm.contains('(') && norm.endsWith(')')) {
      final startIndex = norm.lastIndexOf('(');
      final inside = norm.substring(startIndex + 1, norm.length - 1).trim();
      if (inside == 'artist') {
        cacheTagCategory(norm, 1);
        return 1;
      }
      if (inside == 'cosplay' || inside == 'style' || inside == 'voice_actor') {
        cacheTagCategory(norm, 5);
        return 5;
      }
      if (inside != 'place' && inside != 'marking') {
        cacheTagCategory(norm, 4);
        cacheTagCategory(inside, 3);
        return 4;
      }
    }

    // 6. Known General
    if (_knownGeneral.contains(norm)) {
      cacheTagCategory(norm, 0, persist: false);
      return 0;
    }

    return 0;
  }

  /// Sorts [tags] into categories. [known] holds categories that are already
  /// established for this post and outrank the guesses of
  /// [categorizeTagInstantly].
  static Map<String, List<String>> categorizeAllTags(
    List<String> tags, {
    String source = '',
    Map<String, int> known = const {},
  }) {
    final Map<String, List<String>> map = {
      'artist': [],
      'copyright': [],
      'character': [],
      'general': [],
      'meta': [],
    };

    for (final tag in tags) {
      if (tag.isEmpty) continue;
      if (tag.startsWith('artist:')) {
        map['artist']!.add(tag.replaceFirst('artist:', ''));
      } else if (tag.startsWith('character:')) {
        map['character']!.add(tag.replaceFirst('character:', ''));
      } else if (tag.startsWith('copyright:')) {
        map['copyright']!.add(tag.replaceFirst('copyright:', ''));
      } else if (tag.startsWith('meta:')) {
        map['meta']!.add(tag.replaceFirst('meta:', ''));
      } else {
        final cat = getCachedTagCategory(tag) ??
            known[tag] ??
            categorizeTagInstantly(tag, source: source);
        switch (cat) {
          case 1:
            map['artist']!.add(tag);
          case 3:
            map['copyright']!.add(tag);
          case 4:
            map['character']!.add(tag);
          case 5:
            map['meta']!.add(tag);
          default:
            map['general']!.add(tag);
        }
      }
    }
    return map;
  }

  static String unescapeTag(String tag) {
    if (!tag.contains('&')) return tag;
    return tag
        .replaceAll('&amp;', '&')
        .replaceAll('&#039;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }

  static void parseAndCacheSidebarTags(String html) {
    if (html.isEmpty) return;
    final doc = parse(html);
    final liTags = doc.querySelectorAll('li[class*="tag-type-"]');
    for (final li in liTags) {
      final className = li.className;
      int cat = 0;
      if (className.contains('tag-type-artist')) {
        cat = 1;
      } else if (className.contains('tag-type-copyright')) {
        cat = 3;
      } else if (className.contains('tag-type-character')) {
        cat = 4;
      } else if (className.contains('tag-type-meta') || className.contains('tag-type-metadata')) {
        cat = 5;
      }

      final aTags = li.querySelectorAll('a');
      for (final a in aTags) {
        final text = a.text.trim();
        if (text.isEmpty || text == '?' || text == '+' || text == '-') continue;
        // The text parsed by `html` is already unescaped!
        cacheTagCategory(text.replaceAll(' ', '_'), cat);
      }
    }
  }

  static final Set<int> _resolvingPostIds = <int>{};

  static Future<Post> resolveTagCategories(Post post, Dio dio) async {
    final allExistingTags = <String>{
      ...post.tags['artist'] ?? const [],
      ...post.tags['copyright'] ?? const [],
      ...post.tags['character'] ?? const [],
      ...post.tags['general'] ?? const [],
      ...post.tags['meta'] ?? const [],
    };
    if (allExistingTags.isEmpty) return post;

    final source = post.sources.join(' ').toLowerCase();

    // The page only needs scraping for tags whose category is still unknown.
    final needsScrape =
        allExistingTags.any((t) => getCachedTagCategory(t) == null);

    if (needsScrape) {
      try {
        final response = await dio.get<String>(
          'https://rule34.xxx/index.php',
          queryParameters: {
            'page': 'post',
            's': 'view',
            'id': post.id,
          },
          options: Options(
            responseType: ResponseType.plain,
            headers: {'Referer': 'https://rule34.xxx/'},
            validateStatus: (status) => status != null && status < 500,
          ),
        );
        if (response.statusCode == 429) {
          await Future.delayed(const Duration(seconds: 2));
        }
        final html = response.data ?? '';
        if (html.isNotEmpty && html.contains('tag-sidebar')) {
          if (html.contains('Remove from favorites') ||
              html.contains('action=removefav') ||
              html.contains('s=delete&amp;id=${post.id}')) {
            markFavorited(post.id, true, post: post);
          }

          parseAndCacheSidebarTags(html);
        }
      } catch (_) {}
    }

    // Categories the post already carries must survive tags leaving the cache.
    final known = <String, int>{
      for (final tag in post.tags['artist'] ?? const <String>[]) tag: 1,
      for (final tag in post.tags['copyright'] ?? const <String>[]) tag: 3,
      for (final tag in post.tags['character'] ?? const <String>[]) tag: 4,
      for (final tag in post.tags['meta'] ?? const <String>[]) tag: 5,
    };
    final newTags = categorizeAllTags(
      allExistingTags.toList(),
      source: source,
      known: known,
    );
    final bool isFav = isFavorited(post.id) || post.isFavorited;
    return post.copyWith(tags: newTags, isFavorited: isFav);
  }

  static bool _prefetching = false;
  static DateTime _lastScrapeTime = DateTime.fromMillisecondsSinceEpoch(0);

  static void prefetchPostsTags(List<Post> posts, Dio dio) {
    if (posts.isEmpty || _prefetching) return;
    _prefetching = true;
    Future.microtask(() async {
      try {
        final toPrefetch = posts.take(6);
        for (final post in toPrefetch) {
          if ((post.tags['artist']?.isEmpty ?? true)) {
            final hasCachedArtist = post.tags['general']?.any((t) => getCachedTagCategory(t) == 1) ?? false;
            if (!hasCachedArtist) {
              final elapsed = DateTime.now().difference(_lastScrapeTime).inMilliseconds;
              if (elapsed < 800) {
                await Future.delayed(Duration(milliseconds: 800 - elapsed));
              }
              _lastScrapeTime = DateTime.now();
              await resolveTagCategories(post, dio);
            }
          }
        }
      } catch (_) {
      } finally {
        _prefetching = false;
      }
    });
  }

  /// Pre-categorizes a buffer of 2-3 posts ahead and behind the current post in fullscreen/detail view
  static void preloadSurroundingTags(BuildContext context, int index, List<Post> posts, {int reach = 3}) {
    Future.microtask(() async {
      try {
        final client = context.read<Client>();
        if (client.engine != BooruEngine.rule34) return;

        for (int offset = 0; offset <= reach; offset++) {
          for (final i in [index + offset, index - offset]) {
            if (i >= 0 && i < posts.length) {
              final p = posts[i];
              if (_resolvingPostIds.contains(p.id)) continue;

              final hasArtist = (p.tags['artist']?.isNotEmpty ?? false) ||
                  p.tags.values.expand((e) => e).any((t) => getCachedTagCategory(t) == 1);
              if (!hasArtist) {
                _resolvingPostIds.add(p.id);
                try {
                  final elapsed = DateTime.now().difference(_lastScrapeTime).inMilliseconds;
                  if (elapsed < 500) {
                    await Future.delayed(Duration(milliseconds: 500 - elapsed));
                  }
                  _lastScrapeTime = DateTime.now();

                  final resolved = await resolveTagCategories(p, client.dio);
                  // An unchanged post would only wake every listener for nothing.
                  if (resolved != p) client.posts.postCache.set(resolved);
                } catch (_) {} finally {
                  _resolvingPostIds.remove(p.id);
                }
              }
            }
          }
        }
      } catch (_) {}
    });
  }

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

      final source = post('source').asStringOrNull();
      final List<String> sources = (source != null && source.isNotEmpty) ? [source] : [];

      // Tags
      final rawTagsString = post('tags').asStringOrNull() ?? '';
      final tagList = rawTagsString
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .map(unescapeTag)
          .toList();

      // Present when the request asked for `fields=tag_info`.
      final serverCategories = <String, int>{};
      for (final info in post('tag_info').asListOrEmpty((p) => p)) {
        final name = info('tag').asStringOrNull();
        final category = _serverTagTypes[info('type').asStringOrNull()];
        if (name == null || category == null) continue;
        serverCategories[unescapeTag(name)] = category;
      }
      serverCategories.forEach(cacheTagCategory);

      final tagMap = categorizeAllTags(
        tagList,
        source: source ?? '',
        known: serverCategories,
      );

      // Rating
      final ratingStr = (post('rating').asStringOrNull() ?? 's').toLowerCase();
      final Rating rating = switch (ratingStr) {
        'explicit' || 'e' => Rating.e,
        'questionable' || 'q' => Rating.q,
        _ => Rating.s,
      };

      // The JSON API only reports the time of the last change.
      DateTime createdAt = DateTime.now();
      final rawDate =
          post('created_at').asStringOrNull() ??
          post('change').asStringOrNull();
      if (rawDate != null) {
        createdAt = _parseR34Date(rawDate) ?? createdAt;
      }

      final score = post('score').asIntOrNull() ?? 0;
      final parentIdStr = post('parent_id');
      final rawParentId = parentIdStr.asIntOrNull() ?? int.tryParse(parentIdStr.asStringOrNull() ?? '');
      final parentId = (rawParentId != null && rawParentId > 0) ? rawParentId : null;
      final hasChildren = post('has_children').asBoolOrNull() ??
          (post('has_children').asStringOrNull() == 'true');

      final bool isFav = isFavorited(id);
      final int commentCount = post('comment_count').asIntOrNull() ?? 0;

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
        isDeleted: false,
        rating: rating,
        favCount: 0,
        isFavorited: isFav,
        commentCount: commentCount,
        description: '',
        sources: sources,
        pools: null,
        relationships: Relationships(
          parentId: parentId,
          hasChildren: hasChildren,
          hasActiveChildren: null,
          children: const [],
        ),
      );
    },
  );

  static DateTime? _parseR34Date(String raw) {
    try {
      final asInt = int.tryParse(raw);
      if (asInt != null) {
        return DateTime.fromMillisecondsSinceEpoch(asInt * 1000);
      }
      return DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }
}
