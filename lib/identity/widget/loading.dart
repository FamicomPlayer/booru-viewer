import 'dart:io';

import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:e1547/client/client.dart';
import 'package:e1547/identity/identity.dart';
import 'package:e1547/shared/shared.dart';
import 'package:flutter/material.dart';

class LoginLoadingDialog extends StatefulWidget {
  const LoginLoadingDialog({
    super.key,
    required this.identity,
    required this.host,
    required this.username,
    required this.apikey,
    this.extraHeaders,
    this.activate = false,
    this.onError,
    this.onDone,
  });

  final Identity? identity;
  final String host;
  final String? username;
  final String? apikey;
  final Map<String, String>? extraHeaders;
  final bool activate;
  final ValueSetter<String?>? onError;
  final VoidCallback? onDone;

  @override
  State<LoginLoadingDialog> createState() => _LoginLoadingDialogState();
}

class _LoginLoadingDialogState extends State<LoginLoadingDialog> {
  @override
  void initState() {
    super.initState();
    login();
  }

  Future<void> login() async {
    NavigatorState navigator = Navigator.of(context);
    IdentityClient client = context.read<IdentityClient>();
    Identity? identity = widget.identity;
    String host = widget.host;
    String? username = widget.username;
    String? apikey = widget.apikey;
    Map<String, String>? headers = Map.of(identity?.headers ?? {});
    if (widget.extraHeaders != null) {
      headers.addAll(widget.extraHeaders!);
    }
    final engine = BooruEngine.fromHost(host);

    if (apikey != null && apikey.isNotEmpty) {
      if (apikey == OmittedPasswordTextInputFormatter.passwordOmitted) {
        apikey = headers['api_key'] ??
            headers['key'] ??
            headers['X-API-Key'] ??
            parseBasicAuth(headers[HttpHeaders.authorizationHeader])?.$2;
        if (apikey == null) {
          throw StateError(
            'Login failed: API key was omitted but could not be recovered',
          );
        }
      }

      switch (engine) {
        case BooruEngine.derpibooru:
          headers['key'] = apikey;
          headers['X-API-Key'] = apikey;
          headers.remove(HttpHeaders.authorizationHeader);
          username = (username != null && username.isNotEmpty)
              ? username
              : 'Derpibooru User';
        case BooruEngine.rule34:
          final creds = Rule34Credentials.parse(apikey) ??
              (username != null ? Rule34Credentials.parse(username) : null);
          if (creds != null) {
            headers['user_id'] = creds.userId;
            headers['api_key'] = creds.apiKey;
            if (username == null ||
                username.isEmpty ||
                username.contains('&') ||
                username.contains('=')) {
              username = creds.userId;
            }
          } else {
            // Identities from the web login carry a name here, not their id.
            final String? userId = username
                ?.replaceFirst(RegExp('^User #'), '')
                .trim();
            if (userId != null && int.tryParse(userId) != null) {
              headers['user_id'] = userId;
            }
            headers['api_key'] = apikey;
          }
          headers.remove(HttpHeaders.authorizationHeader);
        case BooruEngine.e621:
          if (username != null) {
            headers[HttpHeaders.authorizationHeader] = encodeBasicAuth(
              username,
              apikey,
            );
          }
      }
    } else if (username != null &&
        username.isNotEmpty &&
        engine == BooruEngine.rule34) {
      final creds = Rule34Credentials.parse(username);
      if (creds != null) {
        headers['user_id'] = creds.userId;
        headers['api_key'] = creds.apiKey;
        username = creds.userId;
      }
    } else if (username != null &&
        (headers.containsKey('pass_hash') ||
            headers.containsKey('user_id') ||
            (headers.containsKey(HttpHeaders.cookieHeader) &&
                (headers[HttpHeaders.cookieHeader]!.contains('pass_hash') ||
                    headers[HttpHeaders.cookieHeader]!.contains('user_id'))) ||
            // A Derpibooru login made in the browser comes without a key.
            parseCookies(
              headers[HttpHeaders.cookieHeader],
            ).keys.any(philomenaSessionCookies.contains))) {
      if (username.isEmpty || username == 'Anonymous') {
        final uid = headers['user_id'];
        username = engine == BooruEngine.derpibooru
            ? 'Derpibooru User'
            : (uid != null && uid.isNotEmpty)
            ? 'User #$uid'
            : 'Rule34 User';
      }
    } else {
      // No name at all is the guest choice, which has to end any session.
      headers = withoutLoginHeaders(headers);
    }

    try {
      if (identity != null) {
        await client.replace(
          identity.copyWith(host: host, username: username, headers: headers),
        );
      } else {
        Identity created = await client.add(
          IdentityRequest(host: host, username: username, headers: headers),
        );
        if (widget.activate) await client.activate(created.id);
      }
    } on DriftRemoteException catch (e) {
      Object error = e.remoteCause;
      String? reason;
      // Duplicate username/host combination
      if (error is SqliteException && error.extendedResultCode == 2067) {
        // Reuse an existing anonymous identity so picking Guest is idempotent.
        if (identity == null && username == null) {
          List<Identity> all = await client.page(page: 1, limit: 9999);
          Iterable<Identity> matches = all.where(
            (e) =>
                e.username == null &&
                normalizeHostUrl(e.host) == normalizeHostUrl(host),
          );
          if (matches.isNotEmpty) {
            if (widget.activate) await client.activate(matches.first.id);
            await navigator.maybePop();
            widget.onDone?.call();
            return;
          }
        }
        reason = 'You already have an identity under this host and username.';
      }
      await navigator.maybePop();
      widget.onError?.call(reason);
      return;
    }
    await navigator.maybePop();
    widget.onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(4),
              child: SizedBox(
                height: 28,
                width: 28,
                child: CircularProgressIndicator(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Connecting to ${linkToDisplay(widget.host)} as ${widget.username ?? 'anonymous'}...',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
