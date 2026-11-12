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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final fallbackClient = context.read<Client>();
      
      final titleStr = widget.title is Text ? (widget.title as Text).data ?? '' : '';
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

  Future<void> _autoDetectLogin() async {
    try {
      if (!_effectiveHost.contains('rule34')) return;
      if (controller == null) return;
      final currentUrl = await controller!.currentUrl() ?? '';
      final onAccountPage = currentUrl.contains('page=account&s=home') ||
          currentUrl.contains('page=account&s=options') ||
          currentUrl.contains('page=favorites');

      final checkRes = await controller!.runJavaScriptReturningResult('''
        (function() {
          var logout = document.querySelector('a[href*="s=logout"]') ||
                       document.querySelector('a[href*="page=account&s=logout"]');
          var fav = document.querySelector('a[href*="favorites"][href*="id="]') ||
                    document.querySelector('a[href*="s=view&id="]');
          var text = (document.body && document.body.innerText) ? document.body.innerText : '';
          var isLogged = (logout !== null) ||
                         (fav !== null) ||
                         text.indexOf('Logout') !== -1 ||
                         text.indexOf('Make like a tree') !== -1 ||
                         text.indexOf('My Favorites') !== -1 ||
                         text.indexOf('My Profile') !== -1;
          return isLogged ? '1' : '0';
        })()
      ''');

      final resStr = checkRes.toString().replaceAll('"', '').trim();
      final isLoggedMarker = resStr == '1' || resStr.toLowerCase() == 'true';

      if (onAccountPage || isLoggedMarker) {
        final ok = await _saveCookies(showToast: false);
        if (ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Login credentials successfully captured!'),
              duration: Duration(seconds: 2),
            ),
          );
          Navigator.of(context).maybePop(true);
        }
      }
    } catch (_) {}
  }

  Future<bool> _saveCookies({bool showToast = true}) async {
    if (_saving) return false;
    setState(() => _saving = true);
    try {
      final idClient = context.read<IdentityClient>();
      final cookieManager = WebviewCookieManager();
      final currentUrl = await controller?.currentUrl() ?? _targetUrl;

      // 1. Gather all cookies from Android native CookieManager
      final cookieDomains = <String>{
        currentUrl,
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
        _effectiveHost,
      };

      final Map<String, String> jar = {};
      final List<Cookie> allCookies = [];
      String? foundPassHash;
      String? foundUserId;
      String? foundUsername;
      String? pageApiKey;
      bool isLoggedIn = false;

      // Query raw cookies from native CookieManager
      for (final domain in cookieDomains) {
        try {
          final cList = await cookieManager.getCookies(domain);
          for (final c in cList) {
            allCookies.add(c);
            jar[c.name] = c.value;
            final cNameLower = c.name.trim().toLowerCase();
            if (cNameLower == 'user_id' && c.value.isNotEmpty) {
              foundUserId ??= c.value;
            }
            if (cNameLower == 'pass_hash' && c.value.isNotEmpty) {
              foundPassHash = c.value;
            }
          }
        } catch (_) {}
      }

      String? userAgent;
      if (controller != null) {
        try {
          final uaRes = await controller!.runJavaScriptReturningResult('navigator.userAgent');
          final ua = uaRes.toString().replaceAll('"', '').trim();
          if (ua.isNotEmpty && ua != 'null') {
            userAgent = ua;
          }
        } catch (_) {}
      }

      // 2. JavaScript DOM and document.cookie extractor inside the WebView
      if (controller != null && _effectiveHost.contains('rule34')) {
        try {
          const jsExtractor = '''
            (function() {
              var fav = document.querySelector('a[href*="favorites"][href*="id="]') ||
                        document.querySelector('a[href*="s=view&id="]');
              var profile = document.querySelector('a[href*="page=account&s=profile"]');
              var logout = document.querySelector('a[href*="s=logout"]') ||
                           document.querySelector('a[href*="page=account&s=logout"]');
              var text = (document.body && document.body.innerText) ? document.body.innerText : '';
              
              var uid = '';
              if (fav) {
                var m = fav.href.match(/[?&]id=([0-9]+)/);
                if (m) uid = m[1];
              }
              if (!uid && text) {
                var m2 = text.match(/user_id=([0-9]+)/i) || text.match(/User ID[:\\s]+([0-9]+)/i);
                if (m2) uid = m2[1];
              }
              var uidInput = document.querySelector('input[name="user_id"]');
              if (uidInput && uidInput.value) uid = uidInput.value;
              
              var uname = '';
              if (profile) {
                var mProf = profile.href.match(/[?&]uname=([^&]+)/);
                if (mProf) uname = decodeURIComponent(mProf[1]);
              }
              var unameInput = document.querySelector('input[name="user"]');
              if (unameInput && unameInput.value) uname = unameInput.value;
              
              var isLogged = (logout !== null) || 
                             (fav !== null) ||
                             text.indexOf('Logout') !== -1 || 
                             text.indexOf('Make like a tree') !== -1 ||
                             text.indexOf('My Favorites') !== -1 ||
                             text.indexOf('My Profile') !== -1;
                             
              var keyMatch = text.match(/api_key=([a-zA-Z0-9_\\-]+)/i) || 
                             text.match(/API Key[:\\s]+([a-zA-Z0-9_\\-]+)/i);
              var apiKey = keyMatch ? keyMatch[1] : '';
              var keyInput = document.querySelector('input[name="api_key"]') || document.querySelector('input[name="pass_hash"]');
              if (keyInput && keyInput.value) apiKey = keyInput.value;
              
              var c = document.cookie || '';
              
              return uid + '|' + uname + '|' + (isLogged ? '1' : '0') + '|' + apiKey + '|' + c;
            })()
          ''';

          final dynamic jsRaw = await controller!.runJavaScriptReturningResult(jsExtractor);
          if (jsRaw != null) {
            String rawStr = jsRaw.toString().trim();
            if (rawStr.startsWith('"') && rawStr.endsWith('"')) {
              try {
                final decoded = jsonDecode(rawStr);
                if (decoded is String) rawStr = decoded;
              } catch (_) {
                rawStr = rawStr.substring(1, rawStr.length - 1).replaceAll(r'\"', '"');
              }
            }

            final parts = rawStr.split('|');
            if (parts.length >= 5) {
              final jsUid = parts[0].trim();
              final jsUname = parts[1].trim();
              final jsIsLogged = parts[2].trim() == '1';
              final jsApiKey = parts[3].trim();
              final jsCookie = parts.sublist(4).join('|').trim();

              if (jsIsLogged) isLoggedIn = true;
              if (jsUid.isNotEmpty) foundUserId ??= jsUid;
              if (jsUname.isNotEmpty) foundUsername ??= jsUname;
              if (jsApiKey.isNotEmpty) pageApiKey ??= jsApiKey;

              for (final part in jsCookie.split(';')) {
                final trimmed = part.trim();
                final eqIdx = trimmed.indexOf('=');
                if (eqIdx > 0) {
                  final k = trimmed.substring(0, eqIdx).trim();
                  final v = trimmed.substring(eqIdx + 1).trim();
                  if (k.isNotEmpty && v.isNotEmpty) {
                    jar[k] = v;
                    if (k == 'user_id' && v.isNotEmpty) foundUserId ??= v;
                    if (k == 'pass_hash' && v.isNotEmpty) foundPassHash ??= v;
                  }
                }
              }
            }
          }
        } catch (e) {
          logger?.error('Error in JS extractor', null, e);
        }
      }

      Map<String, String> headers = {};
      if (userAgent != null) {
        headers[HttpHeaders.userAgentHeader] = userAgent;
        headers['user_agent'] = userAgent;
      }

      if (foundUserId != null) {
        headers['user_id'] = foundUserId;
      }
      if (foundPassHash != null) {
        headers['pass_hash'] = foundPassHash;
      }

      if (jar.isNotEmpty) {
        headers[HttpHeaders.cookieHeader] = jar.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join('; ');
      }

      if (_effectiveHost.contains('rule34') && (pageApiKey == null || pageApiKey.isEmpty)) {
        try {
          final fetchedKey = await fetchRule34ApiKey(headers: headers);
          if (fetchedKey != null && fetchedKey.isNotEmpty) {
            pageApiKey = fetchedKey;
          }
        } catch (_) {}
      }

      if (pageApiKey != null && pageApiKey.isNotEmpty) {
        headers['api_key'] = pageApiKey;
      }

      final isRule34Auth = _effectiveHost.contains('rule34') &&
          (foundPassHash != null ||
           isLoggedIn ||
           (foundUserId != null && foundUserId.isNotEmpty) ||
           currentUrl.contains('page=account&s=home') ||
           currentUrl.contains('page=account&s=options'));

      final isGenericAuth = !_effectiveHost.contains('rule34') && jar.isNotEmpty;

      if (isRule34Auth || isGenericAuth) {
        widget.onCookiesCaptured?.call(headers, allCookies);

        final newUsername = foundUsername ??
            ((foundUserId != null && foundUserId.isNotEmpty)
                ? 'User #$foundUserId'
                : 'Rule34 User');

        final allIdentities = await idClient.all();
        final r34Identities = allIdentities.where((i) => i.host.contains('rule34')).toList();

        // 1. Update EVERY rule34 identity with the captured auth headers
        for (final id in r34Identities) {
          final existingHeaders = Map<String, String>.from(id.headers ?? {});
          existingHeaders.addAll(headers);
          await idClient.replace(
            id.copyWith(
              username: (id.username != null &&
                      id.username!.isNotEmpty &&
                      id.username != 'Anonymous')
                  ? id.username
                  : newUsername,
              headers: existingHeaders,
            ),
          );
        }

        // 2. Ensure the active identity is a Rule34 identity with these headers
        if (idClient.identity.host.contains('rule34')) {
          final existingHeaders = Map<String, String>.from(idClient.identity.headers ?? {});
          existingHeaders.addAll(headers);
          await idClient.replace(
            idClient.identity.copyWith(
              username: (idClient.identity.username != null &&
                      idClient.identity.username!.isNotEmpty &&
                      idClient.identity.username != 'Anonymous')
                  ? idClient.identity.username
                  : newUsername,
              headers: existingHeaders,
            ),
          );
        } else if (r34Identities.isNotEmpty) {
          await idClient.activate(r34Identities.first.id);
        } else {
          final created = await idClient.add(
            IdentityRequest(
              host: 'https://rule34.xxx',
              username: newUsername,
              headers: headers,
            ),
          );
          await idClient.activate(created.id);
        }

        if (showToast && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Logged in successfully! User: ${foundUsername ?? foundUserId ?? "active"}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return true;
      } else {
        if (showToast && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No login session found yet. Please enter your username and password into the login form below and click Log In first.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return false;
      }
    } catch (e, stacktrace) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: widget.title ?? const Text('Rule34 Web Login'),
        actions: [
          if (_effectiveHost.contains('rule34')) ...[
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
                    _effectiveHost.contains('rule34')
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
                          final ok = await _saveCookies(showToast: true);
                          if (ok && mounted) {
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
                final ok = await _saveCookies(showToast: true);
                if (ok && mounted) {
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

/// Strips Cloudflare cookies from [headers], or null when nothing changes.
Map<String, String>? withoutCloudflareCookies(Map<String, String>? headers) {
  String? existing = headers?[HttpHeaders.cookieHeader];
  if (existing == null) return null;

  List<String> pairs = existing.split('; ');
  List<String> kept = pairs
      .where((pair) => !isCloudflareCookie(pair.split('=').first))
      .toList();
  if (kept.length == pairs.length) return null;
  return Map.fromEntries(
    headers!.entries.map(
      (entry) => entry.key == HttpHeaders.cookieHeader
          ? MapEntry(entry.key, kept.join('; '))
          : entry,
    ),
  );
}
