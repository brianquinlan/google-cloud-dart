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

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'compute_engine_credentials.dart';
import 'credential_exception.dart';
import 'service_account_credentials.dart';
import 'service_account_signer.dart';

// Design based on:
// - https://github.com/googleapis/google-cloud-java/blob/main/google-auth-library-java/oauth2_http/java/com/google/auth/oauth2/DefaultCredentialsProvider.java
// - https://github.com/googleapis/google-auth-library-python/blob/main/google/auth/_default.py

/// Loads Application Default Credentials capable of signing messages.
///
/// Follows the standard Google Cloud Application Default Credentials
/// resolution:
/// 1. The credentials file pointed to by the `GOOGLE_APPLICATION_CREDENTIALS`
///    environment variable.
/// 2. The well-known credentials file created by
///    `gcloud auth application-default login` (if it contains service account
///    credentials).
/// 3. The Google Compute Engine (or Google Cloud Build / Cloud Run) metadata
///    server.
///
/// Throws a [CredentialException] if no credentials capable of signing messages
/// could be found or loaded.
Future<ServiceAccountSigner> applicationDefaultCredentials({
  http.Client? client,
  @visibleForTesting String? Function(String name)? getEnvironmentVariable,
  @visibleForTesting String? wellKnownFilePath,
  @visibleForTesting bool? isWindows,
}) async {
  final getEnv = getEnvironmentVariable ?? (name) => Platform.environment[name];
  final onWindows = isWindows ?? Platform.isWindows;

  // 1. Check GOOGLE_APPLICATION_CREDENTIALS
  final envPath = getEnv('GOOGLE_APPLICATION_CREDENTIALS');
  if (envPath != null && envPath.isNotEmpty) {
    final file = File(envPath);
    if (!await file.exists()) {
      throw CredentialException(
        'The GOOGLE_APPLICATION_CREDENTIALS environment variable points to a '
        'file that does not exist: $envPath',
      );
    }

    final String content;
    try {
      content = await file.readAsString();
    } on FileSystemException catch (e, stackTrace) {
      throw CredentialException(
        'Failed to read credentials file at $envPath: $e',
        innerException: e,
        innerStackTrace: stackTrace,
      );
    }

    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected JSON object.');
      }
      json = decoded;
    } on FormatException catch (e, stackTrace) {
      throw CredentialException(
        'The file at $envPath is not a valid JSON file: ${e.message}',
        innerException: e,
        innerStackTrace: stackTrace,
      );
    }

    final type = json['type'];
    if (type == 'service_account') {
      return ServiceAccountCredentials.fromServiceAccountInfo(json);
    }

    throw CredentialException(
      "The credential at '$envPath' has type '$type', which cannot be used to "
      'sign messages. Service account credentials are required.',
    );
  }

  // 2. Check well-known credentials file
  final adcPath =
      wellKnownFilePath ?? _getWellKnownCredentialsPath(getEnv, onWindows);
  if (adcPath != null) {
    final file = File(adcPath);
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic> &&
            decoded['type'] == 'service_account') {
          return await ServiceAccountCredentials.fromServiceAccountInfo(
            decoded,
          );
        }
      } catch (_) {
        // Fall through to Compute Engine metadata server check.
      }
    }
  }

  // 3. Check Google Compute Engine metadata server
  if (await ComputeEngineCredentials.isOnComputeEngine(client: client)) {
    return await ComputeEngineCredentials.create(client: client);
  }

  throw CredentialException(
    'Could not load Application Default Credentials. No service account '
    'credentials found in GOOGLE_APPLICATION_CREDENTIALS, the well-known '
    'credentials file, or the Compute Engine metadata server.',
  );
}

/// Alias for [applicationDefaultCredentials].
Future<ServiceAccountSigner> defaultCredentials({
  http.Client? client,
  @visibleForTesting String? Function(String name)? getEnvironmentVariable,
  @visibleForTesting String? wellKnownFilePath,
  @visibleForTesting bool? isWindows,
}) => applicationDefaultCredentials(
  client: client,
  getEnvironmentVariable: getEnvironmentVariable,
  wellKnownFilePath: wellKnownFilePath,
  isWindows: isWindows,
);

String? _getWellKnownCredentialsPath(
  String? Function(String name) getEnv,
  bool onWindows,
) {
  if (onWindows) {
    final appData = getEnv('APPDATA');
    if (appData == null || appData.isEmpty) return null;
    return p.windows.join(
      appData,
      'gcloud',
      'application_default_credentials.json',
    );
  } else {
    final cloudSdkConfig = getEnv('CLOUDSDK_CONFIG');
    if (cloudSdkConfig != null && cloudSdkConfig.isNotEmpty) {
      return p.posix.join(
        cloudSdkConfig,
        'application_default_credentials.json',
      );
    }
    final home = getEnv('HOME');
    if (home == null || home.isEmpty) return null;
    return p.posix.join(
      home,
      '.config',
      'gcloud',
      'application_default_credentials.json',
    );
  }
}
