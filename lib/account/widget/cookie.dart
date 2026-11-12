import 'dart:convert';
import 'dart:io';

import 'package:e1547/client/client.dart';
import 'package:e1547/identity/identity.dart';
import 'package:e1547/logs/logs.dart';
import 'package:e1547/settings/settings.dart';
import 'package:e1547/shared/data/rule34_api_key.dart';
import 'package:e1547/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:webview_cookie_manager_plus/webview_cookie_manager_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

class CookieCapturePage extends StatefulWidget {
  const CookieCapturePage({
    super.key,
    this.title,
    this.initialUrl,
    this.targetHost,
    this.engine,
    this.onCookiesCaptured,
  });

  /// The page on which to log into the website of [host], for the favorites
  /// that Rule34 and Derpibooru only take from a browser.
  factory CookieCapturePage.login({
    Key? key,
    required String host,
    void Function(Map<String, String> headers, List<Cookie> cookies)?
    onCookiesCaptured,
  }) {
    final BooruEngine engine = BooruEngine.fromHost(host);
    final bool isRule34 = engine == BooruEngine.rule34;
    return CookieCapturePage(
      key: key,
      title: Text(
        isRule34 ? 'Rule34 Web Login' : '${engine.displayName} Web Login',
      ),
      initialUrl: switch (engine) {
        BooruEngine.rule34 =>
          'https://rule34.xxx/index.php?page=account&s=login',
        BooruEngine.derpibooru => '${normalizeHostUrl(host)}/sessions/new',
        BooruEngine.e621 => null,
      },
      targetHost: isRule34 ? 'https://rule34.xxx' : host,
      engine: engine,
      onCookiesCaptured: onCookiesCaptured,
    );
  }

  final Widget? title;
  final String? initialUrl;
  final String? targetHost;
  final BooruEngine? engine;
  final void Function(Map<String, String> headers, List<Cookie> cookies)? onCookiesCaptured;

  @override
  State<CookieCapturePage> createState() => _CookieCapturePageState();
}

class _CookieCapturePageState extends State<CookieCapturePage> {
  Logger? logger;
  WebViewController? controller;
  bool _initialized = false;
  int _loadingProgress = 0;
  String? _errorMessage;
  bool _saving = false;
  String _effectiveHost = 'https://rule34.xxx';
  String _targetUrl = 'https://rule34.xxx/index.php?page=account&s=home';
  BooruEngine _engine = BooruEngine.rule34;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final fallbackClient = context.read<Client>();
      
      final titleStr = widget.title is Text ? (widget.title! as Text).data ?? '' : '';
      final isRule34 = widget.engine == BooruEngine.rule34 ||
          (widget.targetHost?.toLowerCase().contains('rule34') ?? false) ||
          (widget.initialUrl?.toLowerCase().contains('rule34') ?? false) ||
          titleStr.toLowerCase().contains('rule34');

      if (isRule34) {
        _effectiveHost = 'https://rule34.xxx';
        _targetUrl = widget.initialUrl ?? 'https://rule34.xxx/index.php?page=account&s=login';
      } else {
        _effectiveHost = widget.targetHost ?? fallbackClient.host;
        _targetUrl = widget.initialUrl ?? normalizeHostUrl(_effectiveHost);
      }
      _engine = isRule34
          ? BooruEngine.rule34
          : BooruEngine.fromHost(_effectiveHost);

      logger = Logger('CookieCapture', {
        'host': _effectiveHost,
      });

      final c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white);

      c.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _loadingProgress = progress);
          },
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _loadingProgress = 10;
                _errorMessage = null;
              });
            }
          },
          onPageFinished: (url) async {
            if (!mounted) return;
            setState(() => _loadingProgress = 100);

            // Auto-detect login completion on page load
            await _autoDetectLogin();
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                _errorMessage =
                    'Failed to load: ${error.description} (code ${error.errorCode})';
              });
            }
          },
        ),
      );

      c.loadRequest(Uri.parse(_targetUrl));
      setState(() {
        controller = c;
      });
    }
  }

  /// Evaluates [script] in the page and returns its result as text.
  Future<String> _evaluate(String script) async {
    final Object raw = await controller!.runJavaScriptReturningResult(script);
    String result = raw.toString().trim();
    // Android hands a string back the way JSON writes it.
    if (result.startsWith('"') && result.endsWith('"')) {
      try {
        final Object? decoded = jsonDecode(result);
        if (decoded is String) result = decoded;
      } on FormatException {
        result = result.substring(1, result.length - 1).replaceAll(r'\"', '"');
      }
    }
    return result;
  }

  /// Asks the page of a Philomena site who it is shown to.
  Future<PhilomenaPage> _readPhilomenaPage() async {
    final String state = await _evaluate('''
      (function() {
        var store = document.querySelector('.js-datastore');
        if (!store) return '';
        return (store.dataset.userIsSignedIn || 'false') + '|' +
            (store.dataset.userName || '');
      })()
    ''');
    final int split = state.indexOf('|');
    final String name = split < 0 ? '' : state.substring(split + 1);
    return PhilomenaPage(
      isSite: state.isNotEmpty,
      signedIn: state.startsWith('true|'),
      userName: name.isEmpty ? null : name,
    );
  }

  /// Reads what a Rule34 page shows of its user. Whether anyone is logged in
  /// is told by the cookies alone, no page says so dependably.
  Future<({String? username, String? apiKey, Map<String, String> cookies})>
  _readRule34Page() async {
    final String state = await _evaluate(r'''
      (function() {
        var profile = document.querySelector('a[href*="page=account&s=profile"]');
        var text = (document.body && document.body.innerText) ? document.body.innerText : '';
        var uname = '';
        if (profile) {
          var m = profile.href.match(/[?&]uname=([^&]+)/);
          if (m) uname = decodeURIComponent(m[1]);
        }
        var keyMatch = text.match(/api_key=([a-zA-Z0-9_\-]+)/i);
        var apiKey = keyMatch ? keyMatch[1] : '';
        var keyInput = document.querySelector('input[name="api_key"]');
        if (keyInput && keyInput.value) apiKey = keyInput.value;
        return uname + '|' + apiKey + '|' + (document.cookie || '');
      })()
    ''');
    final List<String> parts = state.split('|');
    if (parts.length < 3) {
      return (username: null, apiKey: null, cookies: const <String, String>{});
    }
    final String username = parts[0].trim();
    final String apiKey = parts[1].trim();
    return (
      username: username.isEmpty ? null : username,
      apiKey: apiKey.isEmpty ? null : apiKey,
      cookies: parseCookies(parts.sublist(2).join('|')),
    );
  }

  /// Whether [url] belongs to the site whose login is captured here.
  bool _isSiteUrl(String url) {
    final String? host = Uri.tryParse(url)?.host;
    if (host == null || host.isEmpty) return false;
    if (_engine == BooruEngine.rule34) return host.endsWith('rule34.xxx');
    return host == Uri.tryParse(normalizeHostUrl(_effectiveHost))?.host;
  }

  /// Saves the login as soon as a page shows that there is one.
  Future<void> _autoDetectLogin() async {
    try {
      if (controller == null || _engine == BooruEngine.e621) return;
      final ok = await _saveCookies(showToast: false, loginOnly: true);
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Login credentials successfully captured!'),
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.of(context).maybePop(true);
      }
    } on Object catch (_) {}
  }

  /// Stores the login of the page on an identity. Without a login, and
  /// unless [loginOnly], the clearance of a Cloudflare check is kept instead.
  Future<bool> _saveCookies({
    bool showToast = true,
    bool loginOnly = false,
  }) async {
    if (_saving) return false;
    setState(() => _saving = true);
    try {
      final idClient = context.read<IdentityClient>();
      final cookieManager = WebviewCookieManager();
      final currentUrl = await controller?.currentUrl() ?? _targetUrl;

      // The browser holds the cookies of every site that was ever opened in
      // it, of which only those of this one are taken.
      final origins = <String>{
        if (_isSiteUrl(currentUrl)) currentUrl,
        _effectiveHost,
        if (_engine == BooruEngine.rule34) ...[
          'https://rule34.xxx',
          'https://rule34.xxx/',
          'https://rule34.xxx/index.php',
          'https://rule34.xxx/index.php?page=account&s=home',
          'https://rule34.xxx/index.php?page=account&s=options',
          'https://rule34.xxx/public/addfav.php',
          'https://api.rule34.xxx',
          'https://api.rule34.xxx/',
          'http://rule34.xxx',
          'http://rule34.xxx/',
        ],
      };

      final Map<String, String> jar = {};
      final List<Cookie> allCookies = [];
      for (final origin in origins) {
        try {
          for (final cookie in await cookieManager.getCookies(origin)) {
            allCookies.add(cookie);
            jar[cookie.name] = cookie.value;
          }
        } on Object catch (_) {}
      }

      String? userAgent;
      if (controller != null) {
        try {
          final ua = (await _evaluate('navigator.userAgent')).replaceAll('"', '');
          if (ua.isNotEmpty && ua != 'null') userAgent = ua;
        } on Object catch (_) {}
      }

      final Map<String, String> headers = {
        if (userAgent != null) ...{
          HttpHeaders.userAgentHeader: userAgent,
          'user_agent': userAgent,
        },
      };

      // A login is only taken for one when the site itself vouches for it:
      // by its session cookies on Rule34, by its own page on Derpibooru.
      String? username;
      switch (_engine) {
        case BooruEngine.rule34:
          ({String? username, String? apiKey, Map<String, String> cookies})?
          page;
          if (controller != null && _isSiteUrl(currentUrl)) {
            try {
              page = await _readRule34Page();
              jar.addAll(page.cookies);
            } on Object catch (e) {
              logger?.error('Error in JS extractor', null, e);
            }
          }
          final session = rule34SessionOf(jar);
          if (session == null) break;
          username = page?.username ?? 'User #${session.userId}';
          headers['user_id'] = session.userId;
          headers['pass_hash'] = session.passHash;
          headers[HttpHeaders.cookieHeader] = formatCookies(jar);
          String? apiKey = page?.apiKey;
          if (apiKey == null) {
            try {
              apiKey = await fetchRule34ApiKey(headers: headers);
            } on Object catch (_) {}
          }
          if (apiKey != null && apiKey.isNotEmpty) headers['api_key'] = apiKey;
        case BooruEngine.derpibooru:
          if (controller == null || !_isSiteUrl(currentUrl)) break;
          final page = await _readPhilomenaPage();
          if (!page.signedIn) break;
          if (!jar.keys.any(philomenaSessionCookies.contains)) break;
          username = page.userName ?? 'Derpibooru User';
          headers[HttpHeaders.cookieHeader] = formatCookies(jar);
        case BooruEngine.e621:
          break;
      }

      if (username != null) {
        widget.onCookiesCaptured?.call(headers, allCookies);
        await _storeLogin(idClient, username: username, headers: headers);
        if (showToast && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Logged in successfully! User: $username'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return true;
      }
      if (loginOnly) return false;

      // Without a login this page resolves Cloudflare challenges, of which
      // only the clearance is kept, on the identity that is in use.
      final cleared = withCloudflareCookies(idClient.identity.headers, jar);
      if (cleared != null) {
        // The clearance only holds for the browser that earned it.
        if (userAgent != null) {
          cleared[HttpHeaders.userAgentHeader] = userAgent;
        }
        await idClient.replace(idClient.identity.copyWith(headers: cleared));
        return true;
      }

      if (showToast && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _engine == BooruEngine.e621
                  ? 'Nothing to save yet. Please complete the check shown on the page first.'
                  : 'No login session found yet. Please enter your username and password into the login form below and click Log In first.',
            ),
          ),
        );
      }
      return false;
    } on Object catch (e, stacktrace) {
      logger?.error('Failed to capture cookies', null, e, stacktrace);
      if (showToast && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error capturing login: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Stores a captured login on one identity of this site and makes it the
  /// active one. Other identities may be other accounts and are left alone.
  Future<void> _storeLogin(
    IdentityClient idClient, {
    required String username,
    required Map<String, String> headers,
  }) async {
    bool isSite(Identity identity) =>
        BooruEngine.fromHost(identity.host) == _engine &&
        (_engine == BooruEngine.rule34 ||
            normalizeHostUrl(identity.host) ==
                normalizeHostUrl(_effectiveHost));

    final Identity? target = isSite(idClient.identity)
        ? idClient.identity
        : (await idClient.all()).where(isSite).firstOrNull;

    if (target == null) {
      final created = await idClient.add(
        IdentityRequest(
          host: _effectiveHost,
          username: username,
          headers: headers,
        ),
      );
      await idClient.activate(created.id);
      return;
    }

    final merged = Map<String, String>.from(target.headers ?? {});
    // An API key belongs to its user and must not outlive a change of account.
    if (headers['user_id'] != null &&
        merged['user_id'] != null &&
        merged['user_id'] != headers['user_id'] &&
        !headers.containsKey('api_key')) {
      merged.remove('api_key');
    }
    merged.addAll(headers);
    final String? existing = target.username;
    await idClient.replace(
      target.copyWith(
        username:
            existing != null && existing.isNotEmpty && existing != 'Anonymous'
            ? existing
            : username,
        headers: merged,
      ),
    );
    if (target.id != idClient.identity.id) {
      await idClient.activate(target.id);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title:
            widget.title ??
            Text(
              _engine == BooruEngine.rule34 ? 'Rule34 Web Login' : 'Web Login',
            ),
        actions: [
          if (_engine == BooruEngine.rule34) ...[
            IconButton(
              icon: const Icon(Icons.home_outlined),
              tooltip: 'Account Home',
              onPressed: () {
                controller?.loadRequest(
                  Uri.parse('https://rule34.xxx/index.php?page=account&s=home'),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.key_outlined),
              tooltip: 'API Credentials',
              onPressed: () {
                controller?.loadRequest(
                  Uri.parse('https://rule34.xxx/index.php?page=account&s=options'),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.login),
              tooltip: 'Login Page',
              onPressed: () {
                controller?.loadRequest(
                  Uri.parse('https://rule34.xxx/index.php?page=account&s=login'),
                );
              },
            ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload Page',
            onPressed: () => controller?.reload(),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _engine == BooruEngine.rule34
                        ? 'Log into your Rule34 account below, then tap Save Login.'
                        : 'Log into your account below, then tap Save Login.',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _saving
                      ? null
                      : () async {
                          final ok = await _saveCookies();
                          if (ok && context.mounted) {
                            Navigator.of(context).maybePop(true);
                          }
                        },
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save Login'),
                ),
              ],
            ),
          ),
          if (_loadingProgress < 100)
            LinearProgressIndicator(value: _loadingProgress / 100)
          else
            const SizedBox(height: 2),
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.red.shade900,
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: controller == null
                ? const Center(child: CircularProgressIndicator())
                : WebViewWidget(controller: controller!),
          ),
        ],
      ),
      floatingActionButtonLocation: Handedness.of(
        context,
      ).floatingActionButtonLocation,
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.check),
        label: const Text('Save Login'),
        onPressed: _saving
            ? null
            : () async {
                final ok = await _saveCookies();
                if (ok && context.mounted) {
                  Navigator.of(context).maybePop(true);
                }
              },
      ),
    );
  }
}

bool isCloudflareCookie(String name) =>
    name == 'cf_clearance' || name.startsWith('__cf');

/// Discards stored Cloudflare cookies once the host has rejected them.
Future<void> dropCloudflareCookies(IdentityClient client) async {
  Map<String, String>? headers = withoutCloudflareCookies(
    client.identity.headers,
  );
  if (headers == null) return;
  await client.replace(client.identity.copyWith(headers: headers));
}

/// Adds the Cloudflare cookies among [cookies] to those of [headers], or null
/// when there are none to add.
Map<String, String>? withCloudflareCookies(
  Map<String, String>? headers,
  Map<String, String> cookies,
) {
  Map<String, String> jar = {};
  for (final pair in (headers?[HttpHeaders.cookieHeader] ?? '').split('; ')) {
    int split = pair.indexOf('=');
    if (split <= 0) continue;
    jar[pair.substring(0, split)] = pair.substring(split + 1);
  }
  bool found = false;
  for (final MapEntry(:key, :value) in cookies.entries) {
    if (!isCloudflareCookie(key)) continue;
    jar[key] = value;
    found = true;
  }
  if (!found) return null;
  return {
    ...?headers,
    HttpHeaders.cookieHeader: jar.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; '),
  };
}

/// Strips Cloudflare cookies from [headers], or null when nothing changes.
Map<String, String>? withoutCloudflareCookies(Map<String, String>? headers) {
  String? existing = headers?[HttpHeaders.cookieHeader];
  if (existing == null) return null;

  List<String> pairs = existing.split('; ');
  List<String> kept = pairs
      .where((pair) => !isCloudflareCookie(pair.split('=').first))
      .toList();
  if (kept.length == pairs.length) return null;
  return {
    for (final MapEntry(:key, :value) in headers!.entries)
      if (key != HttpHeaders.cookieHeader)
        key: value
      else if (kept.isNotEmpty)
        key: kept.join('; '),
  };
}
