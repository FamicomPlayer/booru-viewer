import 'package:dio/dio.dart';
import 'package:e1547/client/client.dart';
import 'package:e1547/identity/identity.dart';
import 'package:e1547/shared/shared.dart';
import 'package:e1547/tag/tag.dart';

class TagClient {
  TagClient({required this.dio, this.identity});

  final Dio dio;
  final Identity? identity;

  BooruEngine get engine => BooruEngine.fromHost(identity?.host ?? dio.options.baseUrl);

  Future<List<Tag>> page({
    int? page,
    int? limit,
    QueryMap? query,
    CancelToken? cancelToken,
  }) {
    if (engine == BooruEngine.derpibooru) {
      final nameMatches = query?['search[name_matches]']?.toString().replaceAll('*', '') ?? '';
      return dio
          .get(
            '/api/v1/json/search/tags',
            queryParameters: {
              if (nameMatches.isNotEmpty) 'q': '$nameMatches*',
              if (page != null) 'page': page,
              if (limit != null) 'per_page': limit,
            },
            cancelToken: cancelToken,
          )
          .then((r) {
            final tags = r.data['tags'] as List? ?? const [];
            return tags.map(_parseDerpiTag).toList();
          });
    }

    if (engine == BooruEngine.rule34) {
      final term = query?['search[name_matches]']?.toString().replaceAll('*', '') ?? '';
      return autocomplete(search: term, limit: limit, cancelToken: cancelToken);
    }

    return dio
        .get(
          '/tags.json',
          queryParameters: {'page': page, 'limit': limit, ...?query},
          cancelToken: cancelToken,
        )
        .then(unwrapRailsArray)
        .then((response) => response.data.map<Tag>(E621Tag.fromJson).toList());
  }

  Future<List<TagPreview>> preview({
    required String tags,
    CancelToken? cancelToken,
  }) {
    if (engine != BooruEngine.e621) return Future.value(const []);
    return dio
        .post(
          '/tags/preview.json',
          data: {'tags': tags},
          cancelToken: cancelToken,
        )
        .then(unwrapRailsArray)
        .then(
          (response) => response.data
              .map<TagPreview>(
                (json) => TagPreview.fromJson(json as Map<String, dynamic>),
              )
              .toList(),
        );
  }

  Future<List<Tag>> autocomplete({
    String? search,
    int? limit,
    int? category,
    CancelToken? cancelToken,
  }) async {
    search ??= '';
    if (search.contains(':')) return [];

    switch (engine) {
      case BooruEngine.derpibooru:
        if (search.length < 2) return [];
        return dio
            .get(
              '/api/v1/json/search/tags',
              queryParameters: {'q': '$search*'},
              cancelToken: cancelToken,
            )
            .then((r) {
              final tags = r.data['tags'] as List? ?? const [];
              final list = tags.map(_parseDerpiTag).toList();
              return limit != null ? list.take(limit).toList() : list.take(10).toList();
            });

      case BooruEngine.rule34:
        if (search.length < 2) return [];
        return dio
            .get(
              'https://api.rule34.xxx/autocomplete.php',
              queryParameters: {'q': search},
              cancelToken: cancelToken,
            )
            .then((r) {
              final data = r.data;
              if (data is! List) return <Tag>[];
              return data.map((item) {
                final label = item['label']?.toString() ?? '';
                final value = item['value']?.toString() ?? label;
                int count = 0;
                final match = RegExp(r'\((\d+)\)').firstMatch(label);
                if (match != null) {
                  count = int.tryParse(match.group(1)!) ?? 0;
                }
                return Tag(
                  id: value.hashCode,
                  name: value,
                  count: count,
                  category: 0,
                );
              }).take(limit ?? 10).toList();
            });

      case BooruEngine.e621:
        if (category == null) {
          if (search.length < 3) return [];
          return dio
              .get(
                '/tags/autocomplete.json',
                queryParameters: {'search[name_matches]': search},
                cancelToken: cancelToken,
              )
              .then(unwrapRailsArray)
              .then(
                (response) =>
                    response.data.map<Tag>(E621Tag.fromJson).take(3).toList(),
              );
        } else {
          return page(
            limit: limit,
            query: {
              'search[name_matches]': '$search*',
              'search[category]': category,
              'search[order]': 'count',
            }.toQuery(),
          );
        }
    }
  }

  Future<String?> aliases({
    int? page,
    int? limit,
    QueryMap? query,
    CancelToken? cancelToken,
  }) {
    if (engine != BooruEngine.e621) return Future.value(null);
    return dio
        .get(
          '/tag_aliases.json',
          queryParameters: {'page': page, 'limit': limit, ...?query},
          cancelToken: cancelToken,
        )
        .then(unwrapRailsArray)
        .then((response) {
          return (response.data as List)
              .cast<Map<String, dynamic>>()
              .where((e) => e['status'] != 'deleted')
              .map((e) => e['consequent_name'] as String?)
              .firstOrNull;
        });
  }

  static Tag _parseDerpiTag(dynamic t) {
    int categoryId = 0;
    final cat = t['category']?.toString().toLowerCase();
    switch (cat) {
      case 'artist':
        categoryId = 1;
      case 'copyright':
        categoryId = 3;
      case 'character':
      case 'oc':
        categoryId = 4;
      case 'species':
        categoryId = 5;
      default:
        categoryId = 0;
    }
    return Tag(
      id: t['id'] is int ? t['id'] : int.tryParse(t['id'].toString()) ?? 0,
      name: t['name']?.toString() ?? '',
      count: t['images'] is int ? t['images'] : int.tryParse(t['images']?.toString() ?? '') ?? 0,
      category: categoryId,
    );
  }
}
