import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:e1547/client/client.dart';
import 'package:e1547/identity/identity.dart';

/// What a [FakeHttpAdapter] answers a request with.
class FakeResponse {
  const FakeResponse(
    this.body, {
    this.status = 200,
    this.contentType = Headers.jsonContentType,
    this.headers = const {},
  });

  /// A body the way a JSON API sends it.
  FakeResponse.json(Object? data, {int status = 200})
    : this(jsonEncode(data), status: status);

  /// A page of the website.
  const FakeResponse.html(String body, {int status = 200})
    : this(body, status: status, contentType: 'text/html; charset=UTF-8');

  final String body;
  final int status;
  final String contentType;
  final Map<String, List<String>> headers;
}

/// Answers the requests of a [Dio] from memory and records each of them, for
/// hosts that a local server cannot stand in for.
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.handler);

  final Future<FakeResponse> Function(RequestOptions options) handler;

  final List<RequestOptions> requests = [];

  /// The most requests that were ever underway at once.
  int peak = 0;
  int _running = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    _running++;
    if (_running > peak) peak = _running;
    try {
      final FakeResponse response = await handler(options);
      return ResponseBody.fromString(
        response.body,
        response.status,
        headers: {
          Headers.contentTypeHeader: [response.contentType],
          ...response.headers,
        },
      );
    } finally {
      _running--;
    }
  }

  @override
  void close({bool force = false}) {}
}

/// A [Dio] as the app builds it for [identity], answered by [adapter].
Dio fakeDio(FakeHttpAdapter adapter, Identity identity) =>
    createDefaultDio(identity)..httpClientAdapter = adapter;
