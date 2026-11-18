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

import 'package:http/http.dart' as http;

import 'credential_exception.dart';
import 'credentials.dart';

/// Credentials that authenticate requests using a Google Cloud API key.
///
/// See [API Keys Overview](https://cloud.google.com/api-keys/docs/overview).
final class ApiKeyCredentials extends Credentials {
  /// The API key value.
  final String apiKey;

  const ApiKeyCredentials(
    this.apiKey, {
    super.universeDomain = Credentials.defaultUniverseDomain,
  });

  /// Creates [ApiKeyCredentials] from [apiKey], or if `null`, from the first
  /// set environment variable in [environmentVariables].
  ///
  /// On the web, [apiKey] must be provided and [environmentVariables] is
  /// ignored.
  ///
  /// Throws [CredentialException] if [apiKey] is `null` and none of
  /// [environmentVariables] are set.
  factory ApiKeyCredentials.fromEnvironment({
    // ignore: avoid_unused_constructor_parameters
    String? apiKey,
    // ignore: avoid_unused_constructor_parameters
    List<String> environmentVariables = const ['GOOGLE_API_KEY'],
    // ignore: avoid_unused_constructor_parameters
    String universeDomain = Credentials.defaultUniverseDomain,
  }) => throw UnimplementedError(
    'TODO: implement ApiKeyCredentials.fromEnvironment',
  );

  @override
  Future<Map<String, List<String>>> requestMetadata(
    http.Client client, {
    Uri? uri,
    bool forceRefresh = false,
  }) => throw UnimplementedError('TODO: implement ApiKeyCredentials');
}
