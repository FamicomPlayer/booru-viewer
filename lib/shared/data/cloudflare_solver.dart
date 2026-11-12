import 'dart:async';
import 'dart:io';

import 'package:e1547/identity/identity.dart';
import 'package:e1547/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:webview_cookie_manager_plus/webview_cookie_manager_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

class CloudflareSolver {
  static bool _isSolving = false;
  static Completer<bool>? _currentCompleter;

  /// Attempts to solve Cloudflare challenge for [uri].
  ///
  /// Initially works silently in the background (hidden from the user).
  /// If it succeeds within [revealDelay], it closes invisibly without any UI popup.
  /// If interactive verification is required, it reveals a clean verification card.
  /// Once solved, saves cookies and the matching User-Agent into [IdentityClient].
  static Future<bool> solve({
    Uri? uri,
    BuildContext? context,
    Duration revealDelay = const Duration(seconds: 3),
  }) async {
    if (_isSolving) {
      return _currentCompleter?.future ?? Future.value(false);
    }

    final targetContext = context ?? AppNavigator.currentContext;
    if (targetContext == null || !targetContext.mounted) {
      return false;
    }

    final targetUri = uri ?? Uri.parse('https://rule34.xxx/index.php');
    _isSolving = true;
    final completer = Completer<bool>();
    _currentCompleter = completer;

    final revealed = ValueNotifier<bool>(false);
    Timer? revealTimer;
    Timer? pollTimer;
    BuildContext? dialogContext;
    bool cleanedUp = false;

    void cleanup() {
      if (cleanedUp) return;
      cleanedUp = true;
      revealTimer?.cancel();
      revealTimer = null;
      pollTimer?.cancel();
      pollTimer = null;
      _isSolving = false;
      _currentCompleter = null;
    }

    Future<void> onClearanceDetected(WebViewController controller) async {
      try {
        final cookieManager = WebviewCookieManager();
        final cookies = await cookieManager.getCookies(targetUri.toString());

        String? userAgent;
        try {
          final rawUa = await controller.runJavaScriptReturningResult('navigator.userAgent');
          final parsed = rawUa.toString().replaceAll('"', '').trim();
          if (parsed.isNotEmpty && parsed != 'null') {
            userAgent = parsed;
          }
        } on Object catch (_) {}

        final activeContext = dialogContext ?? targetContext;
        if (activeContext.mounted) {
          final identityClient = activeContext.read<IdentityClient>();
          final headers = Map<String, String>.from(identityClient.identity.headers ?? {});

          if (userAgent != null && userAgent.isNotEmpty) {
            headers[HttpHeaders.userAgentHeader] = userAgent;
            headers['user_agent'] = userAgent;
          }

          final jar = <String, String>{};
          final existing = headers[HttpHeaders.cookieHeader];
          if (existing != null) {
            for (final part in existing.split('; ')) {
              final split = part.indexOf('=');
              if (split > 0) jar[part.substring(0, split)] = part.substring(split + 1);
            }
          }

          for (final c in cookies) {
            jar[c.name] = c.value;
            if (c.name == 'user_id') headers['user_id'] = c.value;
            if (c.name == 'pass_hash') headers['pass_hash'] = c.value;
          }

          if (jar.isNotEmpty) {
            headers[HttpHeaders.cookieHeader] = jar.entries
                .map((e) => '${e.key}=${e.value}')
                .join('; ');
          }

          identityClient.replace(identityClient.identity.copyWith(headers: headers));
        }

        cleanup();
        if (!completer.isCompleted) {
          completer.complete(true);
        }

        if (dialogContext != null && dialogContext!.mounted) {
          Navigator.of(dialogContext!).pop(true);
        }
      } on Object catch (e) {
        debugPrint('CloudflareSolver clearance handling error: $e');
      }
    }

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent);

    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (url) async {
          final cookieManager = WebviewCookieManager();
          final cookies = await cookieManager.getCookies(targetUri.toString());
          if (cookies.any((c) => c.name.toLowerCase() == 'cf_clearance')) {
            await onClearanceDetected(controller);
          }
        },
      ),
    );

    controller.loadRequest(targetUri);

    revealTimer = Timer(revealDelay, () {
      if (!completer.isCompleted) {
        revealed.value = true;
      }
    });

    pollTimer = Timer.periodic(const Duration(milliseconds: 700), (_) async {
      try {
        final cookieManager = WebviewCookieManager();
        final cookies = await cookieManager.getCookies(targetUri.toString());
        if (cookies.any((c) => c.name.toLowerCase() == 'cf_clearance')) {
          await onClearanceDetected(controller);
        }
      } on Object catch (_) {}
    });

    try {
      showDialog<bool>(
        context: targetContext,
        barrierDismissible: false,
        barrierColor: Colors.transparent,
        routeSettings: const RouteSettings(name: 'cloudflare_solver'),
        builder: (ctx) {
          dialogContext = ctx;
          return ValueListenableBuilder<bool>(
            valueListenable: revealed,
            builder: (context, isRevealed, child) {
              return Visibility(
                visible: isRevealed,
                maintainState: true,
                maintainAnimation: true,
                maintainSize: true,
                child: child!,
              );
            },
            child: Material(
              type: MaterialType.transparency,
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    constraints: const BoxConstraints(maxWidth: 480),
                    decoration: BoxDecoration(
                      color: Theme.of(targetContext).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                          child: Row(
                            children: [
                              const Icon(Icons.security, size: 20),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Security Check',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  cleanup();
                                  if (!completer.isCompleted) {
                                    completer.complete(false);
                                  }
                                  Navigator.of(ctx).pop(false);
                                },
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        SizedBox(
                          height: 380,
                          child: WebViewWidget(controller: controller),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ).then((result) {
        cleanup();
        if (!completer.isCompleted) {
          completer.complete(result ?? false);
        }
      });
    } on Object catch (e) {
      cleanup();
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }

    return completer.future;
  }
}
