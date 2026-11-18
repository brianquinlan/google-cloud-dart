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

import 'package:http/http.dart' as http;

import 'application_default_credentials.dart'
    if (dart.library.js_interop) 'application_default_credentials_web.dart'
    show defaultCredentials;
import 'credentials.dart';

/// An [http.Client] that authenticates outgoing requests using [Credentials].
final class AuthClient extends http.BaseClient {
  // ignore: unused_field
  final FutureOr<Credentials> Function(http.Client client) _credentialsProvider;
  // ignore: unused_field
  final FutureOr<http.Client> Function() _clientFactory;

  /// The universe domain expected by the service client.
  final String universeDomain;

  /// Creates an [AuthClient] that authenticates requests with [credentials].
  ///
  /// If [credentials] is `null`, [defaultCredentials] is used.
  ///
  /// If [clientFactory] is provided, it is called once to create the underlying
  /// unauthenticated [http.Client] used for credential requests (such as
  /// [defaultCredentials] and [Credentials.requestMetadata]) as well as API
  /// requests. Closing this [AuthClient] closes that underlying [http.Client].
  AuthClient({
    FutureOr<Credentials>? credentials,
    FutureOr<http.Client> Function()? clientFactory,
    this.universeDomain = Credentials.defaultUniverseDomain,
  }) : _credentialsProvider = switch (credentials) {
         final Future<Credentials> future => (_) {
           future.ignore();
           return future;
         },
         final Credentials value => (_) => value,
         null => defaultCredentials,
       },
       _clientFactory = clientFactory ?? http.Client.new;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError('TODO: implement AuthClient.send');

  @override
  void close() {}
}
