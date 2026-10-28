import 'dart:io';

import 'package:dio/dio.dart';
import 'package:e1547/client/client.dart';
import 'package:e1547/identity/identity.dart';
import 'package:e1547/logs/logs.dart';
import 'package:e1547/query/query.dart';
import 'package:e1547/settings/settings.dart';
import 'package:e1547/shared/shared.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';

/// Interceptor that handles booru-specific authentication and response quirks.
class BooruAuthInterceptor extends Interceptor {
  BooruAuthInterceptor({required this.identity, required this.engine});

  final Identity identity;
  final BooruEngine engine;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    switch (engine) {
      case BooruEngine.derpibooru:
        final key = identity.headers?['key'] ??
            identity.headers?['X-API-Key'] ??
            identity.headers?['apikey'] ??
            (identity.username != null && identity.headers?[HttpHeaders.authorizationHeader] != null
                ? parseBasicAuth(identity.headers?[HttpHeaders.authorizationHeader])?.$2
                : null);
        if (key != null && key.isNotEmpty) {
          options.queryParameters.putIfAbsent('key', () => key);
          options.headers['X-API-Key'] = key;
        }
      case BooruEngine.rule34:
        final userId = identity.headers?['user_id'] ??
            (identity.username != null && int.tryParse(identity.username!) != null
                ? identity.username
                : null);
        final apiKey = identity.headers?['api_key'] ??
            identity.headers?['apikey'] ??
            (identity.headers?[HttpHeaders.authorizationHeader] != null
                ? parseBasicAuth(identity.headers?[HttpHeaders.authorizationHeader])?.$2
                : null);

        if (userId != null && userId.isNotEmpty) {
          options.queryParameters.putIfAbsent('user_id', () => userId);
        }
        if (apiKey != null && apiKey.isNotEmpty) {
          options.queryParameters.putIfAbsent('api_key', () => apiKey);
        }
      case BooruEngine.e621:
        break;
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (engine == BooruEngine.rule34) {
      // Rule34 returns empty string instead of [] when 0 posts match.
      if (response.requestOptions.queryParameters['json'] == '1' ||
          response.requestOptions.queryParameters['json'] == 1) {
        if (response.data == null ||
            (response.data is String && (response.data as String).trim().isEmpty)) {
          response.data = <dynamic>[];
        }
      }
    }
    handler.next(response);
  }
}

/// Create a default [Dio] instance for the given [Identity].
Dio createDefaultDio(Identity identity, {CachedQuery? queryCache}) {
  final engine = BooruEngine.fromHost(identity.host);
  String baseUrl = normalizeHostUrl(identity.host);
  if (engine == BooruEngine.rule34 && baseUrl.contains('rule34.xxx') && !baseUrl.contains('api.rule34.xxx')) {
    baseUrl = 'https://api.rule34.xxx';
  }

  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: {
        HttpHeaders.userAgentHeader: AppInfo.instance.userAgent,
        ...?identity.headers,
      },
      sendTimeout: const Duration(seconds: 30),
      connectTimeout: const Duration(seconds: 30),
    ),
  );
  dio.httpClientAdapter = NativeAdapter();
  dio.interceptors.add(NewlineReplaceInterceptor());
  dio.interceptors.add(BooruAuthInterceptor(identity: identity, engine: engine));
  dio.interceptors.add(LoggingDioInterceptor());
  if (queryCache != null) {
    dio.queryCache = queryCache;
  }
  dio.queryIdentity = identity.id;
  return dio;
}
