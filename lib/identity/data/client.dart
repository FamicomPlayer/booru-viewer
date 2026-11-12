import 'dart:async';

import 'package:async/async.dart';
import 'package:drift/drift.dart';
import 'package:e1547/identity/identity.dart';
import 'package:e1547/shared/data/rule34_api_key.dart';
import 'package:flutter/foundation.dart';

class IdentityClient extends IdentityRepository with ChangeNotifier {
  IdentityClient({required GeneratedDatabase database, this.onCreate})
    : super(database);

  StreamSubscription<Identity?>? _subscription;

  final FutureOr<IdentityRequest> Function()? onCreate;

  bool _disposed = false;

  Future<void> activate(int? id) async {
    _subscription?.cancel();
    Identity? result;
    Stream<Identity?>? stream;
    if (id != null) {
      stream = _find(id);
      result = await stream.firstOrNull;
    }
    if (result == null) {
      if (_disposed) return;
      result = (await page(page: 1, limit: 1)).singleOrNull;
      stream = _find(result?.id);
    }
    if (result == null) {
      if (onCreate == null) {
        throw StateError(
          'IdentitiesClient failed to activate because no identity '
          'was found and no onCreate callback was provided',
        );
      }
      if (_disposed) return;
      result = await add(await onCreate!());
      stream = _find(result.id);
    }
    _identity = result;
    _subscription = stream!.listen(_onChanged);
    if (_disposed) return;
    notifyListeners();
  }

  Stream<Identity?> _find(int? id) => id == null
      ? Stream.value(null)
      : (select(
          identitiesTable,
        )..where((tbl) => tbl.id.equals(id))).watchSingleOrNull();

  bool _fetchingR34Key = false;
  Future<void> _autoFetchRule34ApiKey(Identity id) async {
    if (_fetchingR34Key || _disposed) return;
    _fetchingR34Key = true;
    try {
      final key = await fetchRule34ApiKey(identity: id);
      if (key != null && key.isNotEmpty && !_disposed) {
        final newHeaders = Map<String, String>.from(id.headers ?? {});
        newHeaders['api_key'] = key;
        await replace(id.copyWith(headers: newHeaders));
      }
    } catch (_) {} finally {
      _fetchingR34Key = false;
    }
  }

  Future<void> _onChanged(Identity? value) async {
    if (value == null) return activate(null);
    if (value == _identity) return;
    _identity = value;
    notifyListeners();

    if (value.host.contains('rule34')) {
      final apiKey = value.headers?['api_key'];
      final cookie = value.headers?['Cookie'] ?? value.headers?['cookie'];
      if ((apiKey == null || apiKey.isEmpty) &&
          cookie != null &&
          (cookie.contains('user_id') || cookie.contains('pass_hash'))) {
        _autoFetchRule34ApiKey(value);
      }
    }
  }

  Identity? _identity;

  Identity get identity {
    if (_identity == null) {
      throw StateError(
        'IdentityClient was not activated before accessing '
        'the identity property',
      );
    }
    return _identity!;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
