// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:webcrypto/webcrypto.dart';

import '../verifier/token_verification_exception.dart';
import 'x509.dart';

/// Used when the response carries no usable freshness information.
const _defaultCacheDuration = Duration(hours: 1);

/// How long a client error is remembered before the endpoint is retried.
const _negativeCacheDuration = Duration(minutes: 5);

final _maxAgePattern = RegExp(r'(?:^|[,\s])max-age\s*=\s*"?(\d+)"?');

/// Status codes that are transient and so must never be negatively cached.
const _transientStatusCodes = {408, 429};

/// Computes how long a response may be treated as fresh.
///
/// Honors `Cache-Control: max-age`, reduced by the `Age` header, per
/// [RFC 9111 §4.2](https://datatracker.ietf.org/doc/html/rfc9111#section-4.2).
/// Returns `null` when the response says nothing useful.
Duration? freshnessLifetime(Map<String, String> headers) {
  final cacheControl = headers['cache-control']?.toLowerCase();
  if (cacheControl == null) return null;

  if (cacheControl.contains('no-store') || cacheControl.contains('no-cache')) {
    return Duration.zero;
  }

  final match = _maxAgePattern.firstMatch(cacheControl);
  if (match == null) return null;

  final maxAge = int.tryParse(match.group(1)!);
  if (maxAge == null) return null;

  final age = int.tryParse(headers['age'] ?? '') ?? 0;
  final seconds = maxAge - (age > 0 ? age : 0);
  return seconds > 0 ? Duration(seconds: seconds) : Duration.zero;
}

/// An in-memory cache of RSA public keys used to verify JWS signatures.
///
/// Keys are fetched from [uri], which may serve either of the two formats
/// Google uses:
///
/// - A JSON Web Key Set (JWKS), `{"keys": [...]}`, as served by
///   `https://www.googleapis.com/oauth2/v3/certs`. This is the preferred
///   format.
/// - A map of key ID to PEM-encoded X.509 certificate, `{"<kid>": "<pem>"}`,
///   as served by some older Google endpoints. Supported because a few
///   endpoints, notably the Firebase session cookie endpoint, offer nothing
///   else.
///
/// Only RSA keys usable for RS256 are retained; anything else in the response
/// is ignored so that new key types can be introduced without breaking
/// existing clients.
final class JwksCache {
  /// The endpoint public keys are fetched from.
  final Uri uri;

  final http.Client _httpClient;
  final bool _ownsClient;
  final DateTime Function() _clock;

  Map<String, RsassaPkcs1V15PublicKey>? _keys;
  DateTime? _expiry;

  /// The in-flight fetch, so that concurrent callers share one request.
  Future<Map<String, RsassaPkcs1V15PublicKey>>? _activeFetch;

  TokenVerificationException? _cachedError;
  DateTime? _cachedErrorExpiry;

  JwksCache({
    required this.uri,
    http.Client? httpClient,
    DateTime Function()? clock,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       _clock = clock ?? DateTime.now;

  /// When the currently cached keys go stale, or `null` if nothing is cached.
  DateTime? get expiry => _expiry;

  /// Returns the key identified by [keyId], or `null` if the endpoint does
  /// not publish it.
  ///
  /// If [keyId] is absent from an already-cached key set, the keys may simply
  /// have rotated, so the endpoint is re-fetched exactly once before giving
  /// up.
  ///
  /// Throws [TokenVerificationException] if the keys cannot be fetched.
  Future<RsassaPkcs1V15PublicKey?> lookupKey(String keyId) async {
    final cached = _freshKeys();
    if (cached == null) {
      // Nothing usable cached, so this fetch is already as current as it gets.
      return (await _fetch())[keyId];
    }

    final key = cached[keyId];
    if (key != null) return key;

    return (await _fetch())[keyId];
  }

  /// Discards any cached keys and fetches a new set.
  ///
  /// Throws [TokenVerificationException] if the keys cannot be fetched.
  Future<void> refresh() async {
    _expiry = null;
    await _fetch();
  }

  /// Closes the underlying HTTP client, if this cache created it.
  void close() {
    if (_ownsClient) _httpClient.close();
  }

  Map<String, RsassaPkcs1V15PublicKey>? _freshKeys() {
    final keys = _keys;
    final expiry = _expiry;
    if (keys == null || expiry == null) return null;
    return _clock().isBefore(expiry) ? keys : null;
  }

  Future<Map<String, RsassaPkcs1V15PublicKey>> _fetch() {
    final activeFetch = _activeFetch;
    if (activeFetch != null) return activeFetch;

    final cachedError = _cachedError;
    final cachedErrorExpiry = _cachedErrorExpiry;
    if (cachedError != null &&
        cachedErrorExpiry != null &&
        _clock().isBefore(cachedErrorExpiry)) {
      return Future.error(cachedError);
    }

    final fetch = _fetchKeys().whenComplete(() {
      _activeFetch = null;
    });
    _activeFetch = fetch;
    return fetch;
  }

  Future<Map<String, RsassaPkcs1V15PublicKey>> _fetchKeys() async {
    final http.Response response;
    try {
      response = await _httpClient.get(uri);
    } on Exception catch (e, stackTrace) {
      // Network failures are transient; do not negatively cache them.
      throw TokenVerificationException(
        TokenVerificationFailure.keyUnavailable,
        'Failed to fetch public keys from $uri: $e',
        innerException: e,
        innerStackTrace: stackTrace,
      );
    }

    if (response.statusCode != 200) {
      final error = TokenVerificationException(
        TokenVerificationFailure.keyUnavailable,
        'Failed to fetch public keys from $uri: '
        'HTTP ${response.statusCode} ${response.body}',
      );
      final statusCode = response.statusCode;
      final isClientError =
          statusCode >= 400 &&
          statusCode < 500 &&
          !_transientStatusCodes.contains(statusCode);
      if (isClientError) {
        // A misconfigured URL will keep failing, so stop hammering it. Server
        // errors and rate limiting are left uncached so that recovery is
        // immediate.
        _cachedError = error;
        _cachedErrorExpiry = _clock().add(_negativeCacheDuration);
      }
      throw error;
    }

    final keys = await _parseKeys(response.body);

    _keys = keys;
    _expiry = _clock().add(
      freshnessLifetime(response.headers) ?? _defaultCacheDuration,
    );
    _cachedError = null;
    _cachedErrorExpiry = null;
    return keys;
  }

  Future<Map<String, RsassaPkcs1V15PublicKey>> _parseKeys(String body) async {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException catch (e, stackTrace) {
      throw TokenVerificationException(
        TokenVerificationFailure.keyUnavailable,
        'Public keys from $uri are not valid JSON: ${e.message}',
        innerException: e,
        innerStackTrace: stackTrace,
      );
    }

    if (json is! Map<String, dynamic>) {
      throw TokenVerificationException(
        TokenVerificationFailure.keyUnavailable,
        'Public keys from $uri are not a JSON object.',
      );
    }

    final keys = switch (json['keys']) {
      final List<dynamic> jwks => await _parseJwks(jwks),
      _ => await _parseCertificateMap(json),
    };

    if (keys.isEmpty) {
      throw TokenVerificationException(
        TokenVerificationFailure.keyUnavailable,
        'Public keys from $uri contained no usable RSA keys.',
      );
    }
    return keys;
  }

  Future<Map<String, RsassaPkcs1V15PublicKey>> _parseJwks(
    List<dynamic> jwks,
  ) async {
    final keys = <String, RsassaPkcs1V15PublicKey>{};
    for (final entry in jwks) {
      if (entry is! Map<String, dynamic>) continue;

      final keyId = entry['kid'];
      if (keyId is! String) continue;

      // Ignore anything that is not an RS256 signing key. Google publishes
      // ES256 keys on some endpoints, and those are deliberately unsupported.
      if (entry['kty'] != 'RSA') continue;
      if (entry['alg'] case final alg? when alg != 'RS256') continue;
      if (entry['use'] case final use? when use != 'sig') continue;

      try {
        keys[keyId] = await RsassaPkcs1V15PublicKey.importJsonWebKey(
          entry,
          Hash.sha256,
        );
      } on Object {
        // Skip individual malformed keys rather than failing the whole set.
        continue;
      }
    }
    return keys;
  }

  Future<Map<String, RsassaPkcs1V15PublicKey>> _parseCertificateMap(
    Map<String, dynamic> json,
  ) async {
    final keys = <String, RsassaPkcs1V15PublicKey>{};
    for (final MapEntry(key: keyId, :value) in json.entries) {
      if (value is! String) continue;
      try {
        keys[keyId] = await RsassaPkcs1V15PublicKey.importSpkiKey(
          extractSubjectPublicKeyInfo(parsePemCertificate(value)),
          Hash.sha256,
        );
      } on Object {
        continue;
      }
    }
    return keys;
  }
}
