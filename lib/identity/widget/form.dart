import 'dart:io';

import 'package:e1547/account/account.dart';
import 'package:e1547/app/app.dart';
import 'package:e1547/client/client.dart';
import 'package:e1547/identity/identity.dart';
import 'package:e1547/shared/shared.dart';
import 'package:flutter/material.dart';

class AccountForm extends StatefulWidget {
  const AccountForm({
    super.key,
    this.identity,
    this.initialHost,
    this.onSubmitted,
  });

  final Identity? identity;
  final String? initialHost;
  final VoidCallback? onSubmitted;

  @override
  State<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<AccountForm> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  late final TextEditingController hostController = TextEditingController(
    text: widget.identity?.host ?? widget.initialHost,
  );
  late final TextEditingController usernameController = TextEditingController(
    text: widget.identity?.username,
  );
  late final TextEditingController apikeyController = TextEditingController(
    text: (widget.identity?.headers?[HttpHeaders.authorizationHeader] != null ||
            widget.identity?.headers?['key'] != null ||
            widget.identity?.headers?['api_key'] != null)
        ? OmittedPasswordTextInputFormatter.passwordOmitted
        : null,
  );

  late bool? withAuth = isEditing ? widget.identity!.username != null : null;
  String? error;
  Map<String, String>? _capturedHeaders;

  bool get isEditing => widget.identity != null;
  BooruEngine get currentEngine => BooruEngine.fromHost(hostController.text);

  @override
  void initState() {
    super.initState();
    hostController.addListener(_onHostChanged);
  }

  void _onHostChanged() {
    setState(() {});
  }

  bool get isFulfilled {
    if (isEditing) return true;
    switch (withAuth) {
      case null:
        return false;
      case false:
        return true;
      case true:
        if (currentEngine == BooruEngine.derpibooru) {
          return apikeyController.text.trim().isNotEmpty;
        }
        if (currentEngine == BooruEngine.rule34) {
          return (usernameController.text.trim().isNotEmpty &&
                  apikeyController.text.trim().isNotEmpty) ||
              Rule34Credentials.parse(apikeyController.text) != null ||
              Rule34Credentials.parse(usernameController.text) != null ||
              (_capturedHeaders != null && _capturedHeaders!.isNotEmpty);
        }
        return usernameController.text.trim().isNotEmpty &&
            apikeyController.text.trim().isNotEmpty;
    }
  }

  void _checkForRule34Credentials(String text) {
    if (currentEngine != BooruEngine.rule34) return;
    final creds = Rule34Credentials.parse(text);
    if (creds != null) {
      if (usernameController.text != creds.userId) {
        usernameController.text = creds.userId;
      }
      if (apikeyController.text != creds.apiKey) {
        apikeyController.text = creds.apiKey;
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    hostController.removeListener(_onHostChanged);
    hostController.dispose();
    usernameController.dispose();
    apikeyController.dispose();
    super.dispose();
  }

  void submit() {
    if (!formKey.currentState!.validate()) return;
    if (withAuth == null) return;

    String? username = withAuth! ? usernameController.text.trim() : null;
    String? apikey = withAuth! ? apikeyController.text.trim() : null;

    if (withAuth! && currentEngine == BooruEngine.rule34) {
      final creds = Rule34Credentials.parse(apikey ?? '') ??
          (username != null ? Rule34Credentials.parse(username) : null);
      if (creds != null) {
        username = (username != null &&
                username.isNotEmpty &&
                !username.contains('&') &&
                !username.contains('='))
            ? username
            : creds.userId;
        apikey = creds.apiKey;
      }
    } else if (withAuth! && currentEngine == BooruEngine.derpibooru) {
      if (username == null || username.isEmpty) {
        username = 'Derpibooru User';
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => LoginLoadingDialog(
        identity: widget.identity,
        host: hostController.text,
        username: username,
        apikey: apikey,
        extraHeaders: _capturedHeaders,
        activate: !isEditing,
        onError: (value) => setState(() {
          value ??= 'Check your network connection and login details';
          error = 'Failed to log in. \n$value';
        }),
        onDone: widget.onSubmitted,
      ),
    );
  }

  Widget apiKeyLink() {
    return ListenableBuilder(
      listenable: hostController,
      builder: (context, _) {
        ClientFactory factory = context.watch<ClientFactory>();
        String? apiKeysUrl = factory.apiKeysUrl(hostController.text);
        String? registrationUrl = factory.registrationUrl(hostController.text);
        final engine = currentEngine;
        String linkText = switch (engine) {
          BooruEngine.rule34 => 'Where do I find my API Access Credentials?',
          BooruEngine.derpibooru => 'Where do I find my Derpibooru API key?',
          BooruEngine.e621 => 'Where do I find my API key?',
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (engine != BooruEngine.e621) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.login),
                  label: const Text('Web Login (Required for Favorites)'),
                  onPressed: () async {
                    final bool isRule34 = engine == BooruEngine.rule34;
                    final String host = hostController.text.trim();
                    final bool? captured = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (context) => CookieCapturePage(
                          title: Text(
                            isRule34
                                ? 'Rule34 Web Login'
                                : '${engine.displayName} Web Login',
                          ),
                          // A page that only a login gets to see, which is
                          // captured at once where there already is one.
                          initialUrl: isRule34
                              ? 'https://rule34.xxx/index.php?page=account&s=home'
                              : '${normalizeHostUrl(host)}/sessions/new',
                          targetHost: isRule34 && host.isEmpty
                              ? 'https://rule34.xxx'
                              : host,
                          engine: engine,
                          identity: widget.identity?.id,
                          newAccount: !isEditing,
                          onCookiesCaptured: (headers, cookies) {
                            _capturedHeaders = Map.of(headers);
                            final uid = headers['user_id'];
                            if (uid != null && uid.isNotEmpty) {
                              usernameController.text = uid;
                            }
                            final apiKey = headers['api_key'];
                            if (apiKey != null && apiKey.isNotEmpty) {
                              apikeyController.text = apiKey;
                            }
                          },
                        ),
                      ),
                    );
                    if (context.mounted) {
                      // Only Rule34 hands its credentials out with the login.
                      if (isRule34) {
                        // A login that was captured is the identity in use
                        // by now. Without one, that is some other account.
                        final Identity? saved = captured == true
                            ? context.read<IdentityClient>().identity
                            : null;
                        final uid = _capturedHeaders?['user_id'] ?? saved?.headers?['user_id'];
                        if (uid != null && uid.isNotEmpty && usernameController.text.isEmpty) {
                          usernameController.text = uid;
                        }
                        final apiKey = _capturedHeaders?['api_key'] ?? saved?.headers?['api_key'];
                        if (apiKey != null && apiKey.isNotEmpty && apikeyController.text.isEmpty) {
                          apikeyController.text = apiKey;
                        }
                      }
                      setState(() {});
                      if (captured == true) {
                        widget.onSubmitted?.call();
                        Navigator.of(context).maybePop(true);
                      }
                    }
                  },
                ),
              ),
            ],
            if (apiKeysUrl != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => launch(apiKeysUrl),
                  child: Text(linkText),
                ),
              ),
            if (registrationUrl != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => launch(registrationUrl),
                  child: const Text('Don\'t have an account? Sign up here'),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final engine = currentEngine;
    final usernameLabel = switch (engine) {
      BooruEngine.rule34 => 'User ID (e.g. 315839)',
      BooruEngine.derpibooru => 'Username (optional display name)',
      BooruEngine.e621 => 'Username',
    };
    final apikeyLabel = switch (engine) {
      BooruEngine.rule34 => 'API Access Credentials / Key',
      BooruEngine.derpibooru => 'API Key',
      BooruEngine.e621 => 'API key',
    };
    final apikeyHint = switch (engine) {
      BooruEngine.rule34 => '&api_key=...&user_id=...',
      _ => null,
    };
    final apikeyHelper = switch (engine) {
      BooruEngine.rule34 => 'Paste your full API Access Credentials or API key',
      BooruEngine.derpibooru => 'Found in Account Settings -> Edit -> API Key',
      _ => null,
    };

    return Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HostFormField(controller: hostController, readOnly: isEditing),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'The site is where your posts and account live.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 16),
          _AuthModeSelector(
            withAuth: withAuth,
            onChanged: (value) => setState(() {
              withAuth = value;
              error = null;
            }),
          ),
          AnimatedSize(
            duration: defaultAnimationDuration,
            alignment: Alignment.topCenter,
            child: withAuth == true
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 12),
                      UsernameFormField(
                        controller: usernameController,
                        labelText: usernameLabel,
                        optional: engine == BooruEngine.derpibooru,
                        onChanged: _checkForRule34Credentials,
                      ),
                      ApikeyFormField(
                        controller: apikeyController,
                        canOmit: isEditing,
                        optional: (engine == BooruEngine.rule34 &&
                                _capturedHeaders != null &&
                                _capturedHeaders!.isNotEmpty) ||
                            isEditing,
                        host: hostController.text,
                        labelText: apikeyLabel,
                        hintText: apikeyHint,
                        helperText: apikeyHelper,
                        onChanged: _checkForRule34Credentials,
                      ),
                      apiKeyLink(),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          IgnorePointer(
            ignoring: withAuth == null,
            child: ExcludeSemantics(
              excluding: withAuth == null,
              child: AnimatedOpacity(
                opacity: withAuth == null ? 0 : 1,
                duration: defaultAnimationDuration,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    ListenableBuilder(
                      listenable: Listenable.merge([
                        usernameController,
                        apikeyController,
                      ]),
                      builder: (context, _) {
                        Widget child = Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                isEditing
                                    ? 'Save'
                                    : (withAuth == true
                                          ? 'Log in'
                                          : 'Browse anonymously'),
                              ),
                              if (!isEditing) ...[
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward, size: 18),
                              ],
                            ],
                          ),
                        );
                        return isFulfilled
                            ? ElevatedButton(onPressed: submit, child: child)
                            : OutlinedButton(onPressed: submit, child: child);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthModeSelector extends StatelessWidget {
  const _AuthModeSelector({required this.withAuth, required this.onChanged});

  final bool? withAuth;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    ColorScheme scheme = Theme.of(context).colorScheme;
    ButtonStyle? themeStyle = TextButtonTheme.of(context).style;

    Widget segment(String label, bool selected, VoidCallback onTap) {
      return Expanded(
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: scheme.onSurface,
            backgroundColor: selected
                ? scheme.primary.withValues(alpha: 0.08)
                : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(
                color: selected ? scheme.primary : Colors.transparent,
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.standard,
            textStyle: TextStyle(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ).merge(themeStyle),
          child: Text(label),
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          segment('Sign in', withAuth == true, () => onChanged(true)),
          segment('Guest', withAuth == false, () => onChanged(false)),
        ],
      ),
    );
  }
}
