import 'dart:io';

import 'package:dio/dio.dart';
import 'package:e1547/client/client.dart';
import 'package:e1547/identity/identity.dart';
import 'package:e1547/logs/logs.dart';
import 'package:e1547/query/query.dart';
import 'package:e1547/settings/settings.dart';
import 'package:e1547/shared/shared.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';

/// Keys stored in [Identity.headers] that hold credentials for the
/// [BooruAuthInterceptor] rather than actual HTTP headers.
const Set<String> identityCredentialKeys = {
  'user_id',
  'api_key',
  'apikey',
  'pass_hash',
  'key',
  'user_agent',
};

/// Interceptor that handles booru-specific authentication and response quirks.
class BooruAuthInterceptor extends Interceptor {
  BooruAuthInterceptor({required this.identity, required this.engine});

  final Identity identity;
  final BooruEngine engine;

  /// What Rule34 answers, with status 200, when credentials are absent or wrong.
  static const String rule34MissingAuth = 'Missing authentication';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // API credentials must not follow requests to CDN or website hosts.
    final bool isApiHost =
        options.uri.host == Uri.tryParse(options.baseUrl)?.host;

    switch (engine) {
      case BooruEngine.derpibooru:
        final key = identity.headers?['key'] ??
            identity.headers?['X-API-Key'] ??
            identity.headers?['apikey'] ??
            (identity.username != null && identity.headers?[HttpHeaders.authorizationHeader] != null
                ? parseBasicAuth(identity.headers?[HttpHeaders.authorizationHeader])?.$2
                : null);
        if (isApiHost && key != null && key.isNotEmpty) {
          options.queryParameters.putIfAbsent('key', () => key);
          options.headers['X-API-Key'] = key;
        } else if (!isApiHost) {
          options.headers.remove('X-API-Key');
        }
      case BooruEngine.rule34:
        final cookieHeader = identity.headers?[HttpHeaders.cookieHeader] ?? identity.headers?['Cookie'];
        final cookieUserId = cookieHeader != null
            ? RegExp(r'(?:^|;\s*)user_id=(\d+)').firstMatch(cookieHeader)?.group(1)
            : null;
        final cookiePassHash = cookieHeader != null
            ? RegExp(r'(?:^|;\s*)pass_hash=([a-fA-F0-9]+)').firstMatch(cookieHeader)?.group(1)
            : null;

        final userId = identity.headers?['user_id'] ??
            cookieUserId ??
            (identity.username != null && int.tryParse(identity.username!) != null
                ? identity.username
                : null);
        final apiKey = identity.headers?['api_key'] ??
            identity.headers?['apikey'] ??
            (identity.headers?[HttpHeaders.authorizationHeader] != null
                ? parseBasicAuth(identity.headers?[HttpHeaders.authorizationHeader])?.$2
                : null);
        final passHash = identity.headers?['pass_hash'] ?? cookiePassHash;

        if (isApiHost) {
          if (userId != null && userId.isNotEmpty) {
            options.queryParameters.putIfAbsent('user_id', () => userId);
          }
          if (apiKey != null && apiKey.isNotEmpty) {
            options.queryParameters.putIfAbsent('api_key', () => apiKey);
          }
        }

        final jar = <String, String>{};
        final existingRaw = options.headers[HttpHeaders.cookieHeader] ??
            options.headers['Cookie'] ??
            identity.headers?[HttpHeaders.cookieHeader];
        if (existingRaw != null) {
          for (final part in existingRaw.toString().split('; ')) {
            final idx = part.indexOf('=');
            if (idx > 0) jar[part.substring(0, idx).trim()] = part.substring(idx + 1).trim();
          }
        }
        if (userId != null && userId.isNotEmpty) jar['user_id'] = userId;
        if (passHash != null && passHash.isNotEmpty) jar['pass_hash'] = passHash;
        if (jar.isNotEmpty) {
          options.headers[HttpHeaders.cookieHeader] = jar.entries
              .map((e) => '${e.key}=${e.value}')
              .join('; ');
        }
        final ua = identity.headers?[HttpHeaders.userAgentHeader] ?? identity.headers?['user_agent'];
        if (ua != null && ua.isNotEmpty) {
          options.headers[HttpHeaders.userAgentHeader] = ua;
        }
        options.headers.putIfAbsent('Referer', () => 'https://rule34.xxx/');
      case BooruEngine.e621:
        break;
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (engine == BooruEngine.rule34) {
      final Object? data = response.data;
      if (data is String && data.startsWith(rule34MissingAuth)) {
        // Without this, a rejected login is indistinguishable from "no results".
        response.statusCode = HttpStatus.unauthorized;
        handler.reject(
          DioException.badResponse(
            statusCode: HttpStatus.unauthorized,
            requestOptions: response.requestOptions,
            response: response,
          ),
          true,
        );
        return;
      }
      // Rule34 returns empty string instead of [] when 0 posts match.
      if (response.requestOptions.queryParameters['json'] == '1' ||
          response.requestOptions.queryParameters['json'] == 1) {
        if (data == null || (data is String && data.trim().isEmpty)) {
          response.data = <dynamic>[];
        }
      }
    }
    handler.next(response);
  }
}

/// Retries requests that the host turned away for being sent too quickly.
class RateLimitInterceptor extends Interceptor {
  RateLimitInterceptor({
    required this.dio,
    this.maxRetries = 3,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 10),
  });

  final Dio dio;
  final int maxRetries;
  final Duration baseDelay;
  final Duration maxDelay;

  static const String attemptKey = 'rate_limit.attempt';

  /// The wait before retry number [attempt], preferring the host's own hint.
  Duration delayFor(int attempt, Response? response) {
    final int? hinted = int.tryParse(
      response?.headers.value(HttpHeaders.retryAfterHeader) ?? '',
    );
    final Duration delay = hinted != null
        ? Duration(seconds: hinted)
        : baseDelay * (1 << attempt);
    return delay > maxDelay ? maxDelay : delay;
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final RequestOptions options = err.requestOptions;
    final int attempt = options.extra[attemptKey] as int? ?? 0;
    // Only reads are repeated, a write may have been applied already.
    if (err.response?.statusCode != HttpStatus.tooManyRequests ||
        options.method.toUpperCase() != 'GET' ||
        attempt >= maxRetries) {
      handler.next(err);
      return;
    }
    options.extra[attemptKey] = attempt + 1;
    await Future<void>.delayed(delayFor(attempt, err.response));
    try {
      handler.resolve(await dio.fetch<dynamic>(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

/// Create a default [Dio] instance for the given [Identity].
Dio createDefaultDio(Identity identity, {CachedQuery? queryCache}) {
  final engine = BooruEngine.fromHost(identity.host);
  String baseUrl = normalizeHostUrl(identity.host);
  if (engine == BooruEngine.rule34 && baseUrl.contains('rule34.xxx') && !baseUrl.contains('api.rule34.xxx')) {
    baseUrl = 'https://api.rule34.xxx';
  }

  final userAgent = identity.headers?[HttpHeaders.userAgentHeader] ??
      identity.headers?['user_agent'] ??
      AppInfo.instance.userAgent;

  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: {
        HttpHeaders.userAgentHeader: userAgent,
        for (final MapEntry(:key, :value) in (identity.headers ?? {}).entries)
          if (!identityCredentialKeys.contains(key)) key: value,
      },
      sendTimeout: const Duration(seconds: 30),
      connectTimeout: const Duration(seconds: 30),
    ),
  );
  dio.httpClientAdapter = NativeAdapter();
  dio.interceptors.add(NewlineReplaceInterceptor());
  dio.interceptors.add(BooruAuthInterceptor(identity: identity, engine: engine));
  dio.interceptors.add(RateLimitInterceptor(dio: dio));
  dio.interceptors.add(LoggingDioInterceptor());
  if (queryCache != null) {
    dio.queryCache = queryCache;
  }
  dio.queryIdentity = identity.id;
  return dio;
}
