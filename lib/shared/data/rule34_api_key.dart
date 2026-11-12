import 'dart:io';

import 'package:dio/dio.dart';
import 'package:e1547/identity/identity.dart';
import 'package:flutter/foundation.dart';

/// Fetches the user's API Key from Rule34 options page using session cookies.
Future<String?> fetchRule34ApiKey({Identity? identity, Map<String, String>? headers}) async {
  final hdrs = headers ?? identity?.headers;
  final cookie = hdrs?[HttpHeaders.cookieHeader] ?? hdrs?['Cookie'];
  if (cookie == null || (!cookie.contains('user_id') && !cookie.contains('pass_hash'))) {
    return null;
  }

  try {
    final dio = Dio();
    final response = await dio.get(
      'https://rule34.xxx/index.php?page=account&s=options',
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'Cookie': cookie,
          'User-Agent': hdrs?[HttpHeaders.userAgentHeader] ??
              hdrs?['user_agent'] ??
              'Mozilla/5.0 (Linux; Android 10; SM-G991B) AppleWebKit/537.36',
          'Referer': 'https://rule34.xxx/index.php?page=account&s=home',
        },
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    // Anything but the options page itself, such as a login redirect or a
    // captcha, has no key to offer.
    if (response.statusCode != HttpStatus.ok) return null;
    final html = response.data?.toString() ?? '';
    final keyMatch = RegExp(r'api_key=([a-zA-Z0-9_\-]+)').firstMatch(html) ??
        RegExp(r'name="api_key"[^>]*value="([^"]+)"', caseSensitive: false).firstMatch(html) ??
        RegExp(r'API Key[:\s]+([a-zA-Z0-9_\-]+)', caseSensitive: false).firstMatch(html);

    if (keyMatch != null && keyMatch.group(1) != null && keyMatch.group(1)!.isNotEmpty) {
      return keyMatch.group(1);
    }
  } on Object catch (e) {
    debugPrint('fetchRule34ApiKey error: $e');
  }
  return null;
}
