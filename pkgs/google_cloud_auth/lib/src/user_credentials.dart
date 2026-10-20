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

/// Design based on:
/// - https://github.com/googleapis/google-cloud-java/blob/main/google-auth-library-java/oauth2_http/java/com/google/auth/oauth2/UserCredentials.java
/// - https://github.com/googleapis/google-cloud-python/blob/main/packages/google-auth/google/oauth2/credentials.py
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import 'access_token.dart';
import 'credential_exception.dart';
import 'google_credentials.dart';
import 'json_utils.dart';
import 'platform_web.dart' if (dart.library.io) 'platform_io.dart';

const _infoDescription = 'authorized user info';

/// Credentials for a Google user account, authorized using OAuth 2.0.
///
/// User credentials consist of an OAuth 2.0 client ID and client secret, and a
/// refresh token that is exchanged for short-lived access tokens. They are
/// usually created by running `gcloud auth application-default login`, which
/// stores them in a credentials file with the type `authorized_user`.
///
/// User credentials cannot sign data so, unlike `ServiceAccountCredentials`
/// and `ComputeEngineCredentials`, they do not implement
/// `ServiceAccountSigner`.
///
/// User credentials are only supported in the default `googleapis.com`
/// universe domain.
final class UserCredentials extends GoogleCredentials {
  /// The OAuth 2.0 client ID.
  final String clientId;

  /// The quota project ID associated with the credentials, if available.
  final String? quotaProjectId;

  /// The OAuth 2.0 token endpoint URI.
  final Uri tokenUri;

  final String _clientSecret;
  final String _refreshToken;
  final FutureOr<http.Client> Function() _clientFactory;

  late final _accessTokenCache = AccessTokenCache(
    () => fetchAccessToken(
      clientFactory: _clientFactory,
      source: tokenUri.toString(),
      send: (client) => client.post(
        tokenUri,
        body: {
          'grant_type': 'refresh_token',
          'client_id': clientId,
          'client_secret': _clientSecret,
          'refresh_token': _refreshToken,
        },
      ),
    ),
  );

  /// Creates [UserCredentials] from an OAuth 2.0 [clientId], [clientSecret],
  /// and [refreshToken].
  ///
  /// If [tokenUri] is not provided, then the Google OAuth 2.0 token endpoint
  /// (`https://oauth2.googleapis.com/token`) is used.
  ///
  /// {@template google_cloud_auth.UserCredentials.clientFactory}
  /// If provided, [clientFactory] is called to create the [http.Client]s used
  /// to make requests. Each client it returns is closed after use, so it must
  /// return a new client on every call.
  /// {@endtemplate}
  UserCredentials({
    required this.clientId,
    required String clientSecret,
    required String refreshToken,
    this.quotaProjectId,
    Uri? tokenUri,
    FutureOr<http.Client> Function()? clientFactory,
  }) : _clientSecret = clientSecret,
       _refreshToken = refreshToken,
       tokenUri = tokenUri ?? Uri.https('oauth2.googleapis.com', '/token'),
       _clientFactory = clientFactory ?? http.Client.new;

  /// Creates [UserCredentials] from parsed authorized user JSON [info].
  ///
  /// [info] must contain `client_id`, `client_secret`, and `refresh_token`
  /// fields, and may contain a `quota_project_id` field. If present, the
  /// `type` field must be `authorized_user` and the `universe_domain` field
  /// must be `googleapis.com`. Other fields, such as `token_uri`, are ignored.
  ///
  /// {@macro google_cloud_auth.UserCredentials.clientFactory}
  ///
  /// Throws a [FormatException] if [info] is not valid.
  factory UserCredentials.fromAuthorizedUserInfo(
    Map<String, dynamic> info, {
    FutureOr<http.Client> Function()? clientFactory,
  }) {
    final type = info['type'];
    if (type != null && type != 'authorized_user') {
      throw const FormatException(
        "The value of 'type' must be 'authorized_user'.",
      );
    }

    final universeDomain = optionalString(info, 'universe_domain');
    if (universeDomain != null &&
        universeDomain.isNotEmpty &&
        universeDomain != GoogleCredentials.defaultUniverseDomain) {
      throw FormatException(
        'User credentials are only supported in the '
        "'${GoogleCredentials.defaultUniverseDomain}' universe domain, but "
        "the universe domain is '$universeDomain'.",
      );
    }

    return UserCredentials(
      clientId: requiredString(info, 'client_id', _infoDescription),
      clientSecret: requiredString(info, 'client_secret', _infoDescription),
      refreshToken: requiredString(info, 'refresh_token', _infoDescription),
      quotaProjectId: optionalString(info, 'quota_project_id'),
      clientFactory: clientFactory,
    );
  }

  /// Creates [UserCredentials] from an authorized user JSON string
  /// [jsonString].
  ///
  /// See [UserCredentials.fromAuthorizedUserInfo] for the supported fields.
  ///
  /// {@macro google_cloud_auth.UserCredentials.clientFactory}
  ///
  /// Throws a [FormatException] if [jsonString] is not valid.
  factory UserCredentials.fromAuthorizedUserString(
    String jsonString, {
    FutureOr<http.Client> Function()? clientFactory,
  }) => UserCredentials.fromAuthorizedUserInfo(
    decodeJsonObject(jsonString),
    clientFactory: clientFactory,
  );

  /// Creates [UserCredentials] from an authorized user JSON file at [path],
  /// such as the one created by `gcloud auth application-default login`.
  ///
  /// See [UserCredentials.fromAuthorizedUserInfo] for the supported fields.
  ///
  /// {@macro google_cloud_auth.UserCredentials.clientFactory}
  ///
  /// Throws a [CredentialException] if reading [path] fails or when running on
  /// the web, and a [FormatException] if the file contents are not valid.
  static Future<UserCredentials> fromAuthorizedUserFile(
    String path, {
    FutureOr<http.Client> Function()? clientFactory,
  }) async {
    final contents = await readCredentialFileAsString(path);
    return UserCredentials.fromAuthorizedUserString(
      contents,
      clientFactory: clientFactory,
    );
  }

  /// A non-expired current OAuth2 access token for the user.
  ///
  /// If the cached token is expired or if [forceRefresh] is `true`, then a new
  /// token is obtained from [tokenUri] using the refresh token.
  ///
  /// It is safe to call this method concurrently.
  ///
  /// Throws [CredentialException] on failure.
  Future<String> accessToken({bool forceRefresh = false}) =>
      _accessTokenCache.accessToken(forceRefresh: forceRefresh);
}
