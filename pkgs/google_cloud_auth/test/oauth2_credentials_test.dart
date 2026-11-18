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

import 'package:google_cloud_auth/google_cloud_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final class FakeCredentials extends OAuth2Credentials {
  final accessTokenCalls = <({http.Client client, bool forceRefresh})>[];

  @override
  Future<String> accessToken(
    http.Client client, {
    bool forceRefresh = false,
  }) async {
    accessTokenCalls.add((client: client, forceRefresh: forceRefresh));
    return 'abc123';
  }
}

void main() {
  final dummyClient = MockClient(
    (_) async => throw StateError('unexpected HTTP request'),
  );

  group('OAuth2Credentials', () {
    test('requestMetadata without forceRefresh', () async {
      final creds = FakeCredentials();
      expect(await creds.requestMetadata(dummyClient), {
        'authorization': ['Bearer abc123'],
      });
      expect(creds.accessTokenCalls, [
        (client: dummyClient, forceRefresh: false),
      ]);
    });

    test('requestMetadata with forceRefresh', () async {
      final creds = FakeCredentials();
      expect(await creds.requestMetadata(dummyClient, forceRefresh: true), {
        'authorization': ['Bearer abc123'],
      });
      expect(creds.accessTokenCalls, [
        (client: dummyClient, forceRefresh: true),
      ]);
    });
  });
}
