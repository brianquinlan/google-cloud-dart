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

import 'package:google_cloud_auth/google_cloud_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

const _testInfo = {
  'type': 'authorized_user',
  'client_id': 'test-client-id.apps.googleusercontent.com',
  'client_secret': 'test-client-secret',
  'refresh_token': 'test-refresh-token',
};

final _defaultTokenUri = Uri.https('oauth2.googleapis.com', '/token');

http.Response _tokenResponse(String accessToken, {int expiresIn = 3600}) =>
    http.Response(
      jsonEncode({
        'access_token': accessToken,
        'expires_in': expiresIn,
        'scope': 'https://www.googleapis.com/auth/cloud-platform',
        'token_type': 'Bearer',
      }),
      200,
    );

/// A client factory whose clients add each request to [requests] and respond
/// with an access token.
http.Client Function() _recordingClientFactory(List<http.Request> requests) =>
    () => MockClient((request) async {
      requests.add(request);
      return _tokenResponse('access-token');
    });

UserCredentials _credentials(MockClientHandler handler) =>
    UserCredentials.fromAuthorizedUserInfo(
      _testInfo,
      clientFactory: () => MockClient(handler),
    );

void main() {
  group('UserCredentials', () {
    group('fromAuthorizedUserInfo', () {
      test('all keys set', () async {
        final requests = <http.Request>[];
        final creds = UserCredentials.fromAuthorizedUserInfo({
          'type': 'authorized_user',
          'client_id': 'client-123.apps.googleusercontent.com',
          'client_secret': 'secret-123',
          'refresh_token': 'refresh-123',
          'quota_project_id': 'quota-project',
          'universe_domain': 'googleapis.com',
          'account': '',
        }, clientFactory: _recordingClientFactory(requests));

        expect(creds.quotaProjectId, 'quota-project');
        expect(creds.universeDomain, 'googleapis.com');

        await creds.accessToken();
        expect(requests.single.url, _defaultTokenUri);
        expect(requests.single.bodyFields, {
          'grant_type': 'refresh_token',
          'client_id': 'client-123.apps.googleusercontent.com',
          'client_secret': 'secret-123',
          'refresh_token': 'refresh-123',
        });
      });

      test('minimal keys set', () async {
        final requests = <http.Request>[];
        final creds = UserCredentials.fromAuthorizedUserInfo({
          'client_id': 'client-123.apps.googleusercontent.com',
          'client_secret': 'secret-123',
          'refresh_token': 'refresh-123',
        }, clientFactory: _recordingClientFactory(requests));

        expect(creds.quotaProjectId, isNull);
        expect(creds.universeDomain, 'googleapis.com');

        await creds.accessToken();
        expect(requests.single.url, _defaultTokenUri);
        expect(requests.single.bodyFields, {
          'grant_type': 'refresh_token',
          'client_id': 'client-123.apps.googleusercontent.com',
          'client_secret': 'secret-123',
          'refresh_token': 'refresh-123',
        });
      });

      test('ignores token_uri', () async {
        final requests = <http.Request>[];
        final creds = UserCredentials.fromAuthorizedUserInfo({
          ..._testInfo,
          'token_uri': 'https://example.com/token',
        }, clientFactory: _recordingClientFactory(requests));

        await creds.accessToken();
        expect(requests.single.url, _defaultTokenUri);
      });

      test('accepts empty universe_domain', () {
        final creds = UserCredentials.fromAuthorizedUserInfo({
          ..._testInfo,
          'universe_domain': '',
        });

        expect(creds.universeDomain, 'googleapis.com');
      });

      test('throws on invalid type', () {
        expect(
          () => UserCredentials.fromAuthorizedUserInfo({
            ..._testInfo,
            'type': 'service_account',
          }),
          throwsFormatException,
        );
      });

      for (final key in ['client_id', 'client_secret', 'refresh_token']) {
        test('throws on missing $key', () {
          final info = Map.of(_testInfo)..remove(key);

          expect(
            () => UserCredentials.fromAuthorizedUserInfo(info),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                contains("'$key'"),
              ),
            ),
          );
        });

        test('throws on empty $key', () {
          expect(
            () =>
                UserCredentials.fromAuthorizedUserInfo({..._testInfo, key: ''}),
            throwsFormatException,
          );
        });

        test('throws on non-string $key', () {
          expect(
            () => UserCredentials.fromAuthorizedUserInfo({
              ..._testInfo,
              key: 12345,
            }),
            throwsFormatException,
          );
        });
      }

      test('throws on non-string quota_project_id', () {
        expect(
          () => UserCredentials.fromAuthorizedUserInfo({
            ..._testInfo,
            'quota_project_id': 12345,
          }),
          throwsFormatException,
        );
      });

      test('throws on non-string universe_domain', () {
        expect(
          () => UserCredentials.fromAuthorizedUserInfo({
            ..._testInfo,
            'universe_domain': 12345,
          }),
          throwsFormatException,
        );
      });

      test('throws on non-default universe_domain', () {
        expect(
          () => UserCredentials.fromAuthorizedUserInfo({
            ..._testInfo,
            'universe_domain': 'custom.domain.com',
          }),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains("'custom.domain.com'"),
            ),
          ),
        );
      });
    });

    group('fromAuthorizedUserString', () {
      test('loads credentials from string', () async {
        final requests = <http.Request>[];
        final creds = UserCredentials.fromAuthorizedUserString(
          jsonEncode({..._testInfo, 'quota_project_id': 'quota-project'}),
          clientFactory: _recordingClientFactory(requests),
        );

        expect(creds.quotaProjectId, 'quota-project');

        await creds.accessToken();
        expect(
          requests.single.bodyFields,
          containsPair(
            'client_id',
            'test-client-id.apps.googleusercontent.com',
          ),
        );
      });

      test('throws on invalid JSON', () {
        expect(
          () => UserCredentials.fromAuthorizedUserString('not valid json'),
          throwsFormatException,
        );
      });

      test('throws on non-object JSON', () {
        expect(
          () => UserCredentials.fromAuthorizedUserString('[1, 2, 3]'),
          throwsFormatException,
        );
      });
    });

    group('fromAuthorizedUserFile', () {
      test('loads credentials from file', () async {
        // The format written by `gcloud auth application-default login`.
        const jsonString = '''
{
  "account": "",
  "client_id": "test-client-id.apps.googleusercontent.com",
  "client_secret": "test-client-secret",
  "quota_project_id": "test-project",
  "refresh_token": "test-refresh-token",
  "type": "authorized_user",
  "universe_domain": "googleapis.com"
}
''';
        final tempFilePath = await writeTempFile(
          'application_default_credentials.json',
          jsonString,
        );
        final requests = <http.Request>[];

        final creds = await UserCredentials.fromAuthorizedUserFile(
          tempFilePath,
          clientFactory: _recordingClientFactory(requests),
        );

        expect(creds.quotaProjectId, 'test-project');
        expect(creds.universeDomain, 'googleapis.com');

        await creds.accessToken();
        expect(requests.single.url, _defaultTokenUri);
        expect(
          requests.single.bodyFields,
          containsPair(
            'client_id',
            'test-client-id.apps.googleusercontent.com',
          ),
        );
      }, testOn: 'vm');

      test(
        'throws CredentialException when file cannot be read or on browser',
        () async {
          await expectLater(
            UserCredentials.fromAuthorizedUserFile(
              'non_existent_authorized_user.json',
            ),
            throwsA(isA<CredentialException>()),
          );
        },
      );
    });

    group('accessToken', () {
      test('exchanges refresh token for access token', () async {
        final requests = <http.Request>[];
        final creds = _credentials((request) async {
          requests.add(request);
          return _tokenResponse('access-token');
        });

        expect(await creds.accessToken(), 'access-token');

        final request = requests.single;
        expect(request.method, 'POST');
        expect(request.url, _defaultTokenUri);
        expect(
          request.headers['content-type'],
          startsWith('application/x-www-form-urlencoded'),
        );
        expect(request.bodyFields, {
          'grant_type': 'refresh_token',
          'client_id': 'test-client-id.apps.googleusercontent.com',
          'client_secret': 'test-client-secret',
          'refresh_token': 'test-refresh-token',
        });
      });

      test('fetches and caches access token', () async {
        var callCount = 0;
        final creds = _credentials((request) async {
          callCount++;
          return _tokenResponse('token-$callCount');
        });

        expect(await creds.accessToken(), 'token-1');
        expect(callCount, 1);

        // Cached
        expect(await creds.accessToken(), 'token-1');
        expect(callCount, 1);

        // Force refresh
        expect(await creds.accessToken(forceRefresh: true), 'token-2');
        expect(callCount, 2);
      });

      test('refreshes access token that is about to expire', () async {
        var callCount = 0;
        final creds = _credentials((request) async {
          callCount++;
          // Tokens that expire within a minute are not reused.
          return _tokenResponse('token-$callCount', expiresIn: 30);
        });

        expect(await creds.accessToken(), 'token-1');
        expect(await creds.accessToken(), 'token-2');
        expect(callCount, 2);
      });

      test('shares active request among concurrent callers', () async {
        final completer = Completer<http.Response>();
        var callCount = 0;
        final creds = _credentials((request) {
          callCount++;
          return completer.future;
        });

        final future1 = creds.accessToken();
        final future2 = creds.accessToken();
        final future3 = creds.accessToken(forceRefresh: true);

        await pumpEventQueue();
        expect(callCount, 1);

        completer.complete(_tokenResponse('shared-token'));

        expect(await Future.wait([future1, future2, future3]), [
          'shared-token',
          'shared-token',
          'shared-token',
        ]);
        expect(callCount, 1);
      });

      test(
        'clears active request on failure so subsequent call retries',
        () async {
          var callCount = 0;
          final creds = _credentials((request) async {
            callCount++;
            if (callCount == 1) {
              return http.Response('Internal Server Error', 500);
            }
            return _tokenResponse('recovered-token');
          });

          await expectLater(
            creds.accessToken(),
            throwsA(isA<CredentialException>()),
          );
          expect(callCount, 1);

          expect(await creds.accessToken(), 'recovered-token');
          expect(callCount, 2);
        },
      );

      test('throws CredentialException on HTTP error', () async {
        final creds = _credentials(
          (request) async => http.Response(
            jsonEncode({
              'error': 'invalid_grant',
              'error_description': 'Token has been expired or revoked.',
            }),
            400,
          ),
        );

        await expectLater(
          creds.accessToken(),
          throwsA(
            isA<CredentialException>().having(
              (e) => e.message,
              'message',
              allOf(contains('HTTP 400'), contains('invalid_grant')),
            ),
          ),
        );
      });

      test('throws CredentialException on network error', () async {
        final creds = _credentials(
          (request) async => throw http.ClientException('Network down'),
        );

        await expectLater(
          creds.accessToken(),
          throwsA(
            isA<CredentialException>()
                .having(
                  (e) => e.message,
                  'message',
                  contains('Failed to get access token'),
                )
                .having(
                  (e) => e.innerException,
                  'innerException',
                  isA<http.ClientException>(),
                ),
          ),
        );
      });

      test('throws CredentialException on invalid JSON', () async {
        final creds = _credentials(
          (request) async => http.Response('not valid json', 200),
        );

        await expectLater(
          creds.accessToken(),
          throwsA(
            isA<CredentialException>()
                .having(
                  (e) => e.message,
                  'message',
                  contains('Failed to parse token response'),
                )
                .having(
                  (e) => e.innerException,
                  'innerException',
                  isA<FormatException>(),
                ),
          ),
        );
      });

      test('throws CredentialException on non-map JSON', () async {
        final creds = _credentials(
          (request) async => http.Response('[1, 2, 3]', 200),
        );

        await expectLater(
          creds.accessToken(),
          throwsA(
            isA<CredentialException>().having(
              (e) => e.message,
              'message',
              contains('Failed to parse token response'),
            ),
          ),
        );
      });

      test('throws CredentialException on missing access_token', () async {
        final creds = _credentials(
          (request) async =>
              http.Response(jsonEncode({'expires_in': 3600}), 200),
        );

        await expectLater(
          creds.accessToken(),
          throwsA(
            isA<CredentialException>().having(
              (e) => e.message,
              'message',
              contains('Failed to parse token response'),
            ),
          ),
        );
      });
    });
  });
}
