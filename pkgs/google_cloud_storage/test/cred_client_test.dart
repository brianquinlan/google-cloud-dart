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
import 'package:google_cloud_storage/google_cloud_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final class _FakeCredentials extends Credentials {
  final FutureOr<Map<String, List<String>>> Function({
    Uri? uri,
    required bool forceRefresh,
  })
  _onRequestMetadata;

  final calls = <({Uri? uri, bool forceRefresh})>[];

  _FakeCredentials(this._onRequestMetadata);

  factory _FakeCredentials.tokens(
    List<String> tokens, {
    String? quotaProjectId,
  }) {
    var index = 0;
    return _FakeCredentials(({uri, required forceRefresh}) {
      if (forceRefresh && index < tokens.length - 1) {
        index++;
      }
      return {
        'authorization': ['Bearer ${tokens[index]}'],
        if (quotaProjectId != null) 'x-goog-user-project': [quotaProjectId],
      };
    });
  }

  @override
  Future<Map<String, List<String>>> requestMetadata({
    Uri? uri,
    bool forceRefresh = false,
  }) async {
    calls.add((uri: uri, forceRefresh: forceRefresh));
    return await _onRequestMetadata(uri: uri, forceRefresh: forceRefresh);
  }
}

final class _TrackingClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) _handler;
  bool isClosed = false;

  _TrackingClient(this._handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);

  @override
  void close() {
    isClosed = true;
  }
}

void main() {
  final testUrl = Uri.https('storage.googleapis.com', '/storage/v1/b/my-bkt');

  group('CredClient', () {
    test(
      'populates request headers from Credentials.requestMetadata',
      () async {
        final creds = _FakeCredentials(
          ({uri, required forceRefresh}) => {
            'authorization': ['Bearer tok-1'],
            'x-multi': ['a', 'b'],
            'x-empty': const [],
          },
        );
        late http.Request captured;
        final delegate = MockClient((request) async {
          captured = request;
          return http.Response('ok', 200);
        });
        final client = CredClient(creds, delegate);
        addTearDown(client.close);

        final original = http.Request('POST', testUrl)
          ..persistentConnection = false
          ..followRedirects = false
          ..maxRedirects = 2
          ..headers['x-custom'] = 'keep'
          ..body = 'payload';

        final streamed = await client.send(original);
        final response = await http.Response.fromStream(streamed);

        expect(response.statusCode, 200);
        expect(response.body, 'ok');
        expect(original.finalized, isTrue);
        // Original request headers are not mutated in place.
        expect(original.headers.containsKey('authorization'), isFalse);

        expect(creds.calls, [(uri: testUrl, forceRefresh: false)]);
        expect(captured.method, 'POST');
        expect(captured.url, testUrl);
        expect(captured.body, 'payload');
        expect(captured.persistentConnection, isFalse);
        expect(captured.followRedirects, isFalse);
        expect(captured.maxRedirects, 2);
        expect(captured.headers['authorization'], 'Bearer tok-1');
        expect(captured.headers['x-multi'], 'a, b');
        expect(captured.headers.containsKey('x-empty'), isFalse);
        expect(captured.headers['x-custom'], 'keep');
      },
    );

    test('preserves explicit per-request x-goog-user-project header', () async {
      final creds = _FakeCredentials.tokens([
        'tok-1',
      ], quotaProjectId: 'cred-quota-project');
      final capturedRequests = <http.Request>[];
      final delegate = MockClient((request) async {
        capturedRequests.add(request);
        return http.Response('ok', 200);
      });
      final client = CredClient(creds, delegate);
      addTearDown(client.close);

      await client.get(testUrl);
      await client.get(
        testUrl,
        headers: {'X-Goog-User-Project': 'caller-project'},
      );

      expect(
        capturedRequests[0].headers['x-goog-user-project'],
        'cred-quota-project',
      );
      expect(
        capturedRequests[1].headers['x-goog-user-project'],
        'caller-project',
      );
    });

    for (final (description, statusCode, wwwAuth) in [
      ('bare 401 without WWW-Authenticate', 401, null),
      (
        '401 with Bearer realm only (no error param)',
        401,
        'Bearer realm="https://accounts.google.com/"',
      ),
      (
        '401 with Bearer invalid_token',
        401,
        'Bearer realm="https://accounts.google.com/", error="invalid_token"',
      ),
      (
        'non-401 with Bearer invalid_token challenge',
        400,
        'Bearer error="invalid_token", error_description="Token expired"',
      ),
    ]) {
      test('refreshes and retries once on $description', () async {
        final creds = _FakeCredentials.tokens(['stale-tok', 'fresh-tok']);
        final seenAuthHeaders = <String?>[];
        final seenBodies = <String>[];
        var attempt = 0;

        final delegate = MockClient((request) async {
          attempt++;
          seenAuthHeaders.add(request.headers['authorization']);
          seenBodies.add(request.body);
          if (attempt == 1) {
            return http.Response(
              'unauthorized',
              statusCode,
              headers: {'www-authenticate': ?wwwAuth},
            );
          }
          return http.Response('success', 200);
        });

        final client = CredClient(creds, delegate);
        addTearDown(client.close);

        final response = await client.post(testUrl, body: 'hello');
        expect(response.statusCode, 200);
        expect(response.body, 'success');
        expect(seenAuthHeaders, ['Bearer stale-tok', 'Bearer fresh-tok']);
        expect(seenBodies, ['hello', 'hello']);
        expect(creds.calls, [
          (uri: testUrl, forceRefresh: false),
          (uri: testUrl, forceRefresh: false),
          (uri: testUrl, forceRefresh: true),
        ]);
      });
    }

    test(
      'deduplicates forceRefresh when concurrent 401 already refreshed',
      () async {
        final creds = _FakeCredentials.tokens(['stale-tok', 'fresh-tok']);
        final first401Barrier = Completer<void>();
        var inFlightStale = 0;

        final delegate = _TrackingClient((request) async {
          await request.finalize().drain<void>();
          if (request.headers['authorization'] == 'Bearer stale-tok') {
            inFlightStale++;
            if (inFlightStale == 2) {
              first401Barrier.complete();
            }
            await first401Barrier.future;
            return http.StreamedResponse(
              const Stream.empty(),
              401,
              headers: {'WWW-Authenticate': 'Bearer error="invalid_token"'},
            );
          }
          return http.StreamedResponse(Stream.value(utf8.encode('ok')), 200);
        });

        final client = CredClient(creds, delegate);
        addTearDown(client.close);

        final responses = await Future.wait([
          client.get(testUrl),
          client.get(testUrl),
        ]);
        expect(responses.map((r) => r.statusCode), [200, 200]);
        // Only a single forceRefresh: true call is issued for concurrent 401s.
        expect(creds.calls.where((c) => c.forceRefresh), hasLength(1));
      },
    );

    test('retries at most once when refreshed token still gets 401', () async {
      final creds = _FakeCredentials.tokens(['tok-1', 'tok-2', 'tok-3']);
      var attempts = 0;
      final delegate = MockClient((request) async {
        attempts++;
        return http.Response('still unauthorized $attempts', 401);
      });

      final client = CredClient(creds, delegate);
      addTearDown(client.close);

      final response = await client.get(testUrl);
      expect(attempts, 2);
      expect(response.statusCode, 401);
      expect(response.body, 'still unauthorized 2');
      expect(creds.calls, [
        (uri: testUrl, forceRefresh: false),
        (uri: testUrl, forceRefresh: false),
        (uri: testUrl, forceRefresh: true),
      ]);
    });

    for (final (description, statusCode, wwwAuth) in [
      ('403 Forbidden without WWW-Authenticate', 403, null),
      (
        '403 with insufficient_scope',
        403,
        'Bearer realm="https://accounts.google.com/", '
            'error="insufficient_scope"',
      ),
      ('401 with insufficient_scope', 401, 'Bearer error="insufficient_scope"'),
      ('400 with invalid_request', 400, 'Bearer error="invalid_request"'),
    ]) {
      test('does not refresh on $description', () async {
        final creds = _FakeCredentials.tokens(['tok-1', 'tok-2']);
        var attempts = 0;
        final delegate = MockClient((request) async {
          attempts++;
          return http.Response(
            '{"error":{"message":"denied"}}',
            statusCode,
            headers: {'www-authenticate': ?wwwAuth},
          );
        });

        final client = CredClient(creds, delegate);
        addTearDown(client.close);

        final response = await client.get(testUrl);
        expect(attempts, 1);
        expect(response.statusCode, statusCode);
        expect(response.body, '{"error":{"message":"denied"}}');
        expect(creds.calls, [(uri: testUrl, forceRefresh: false)]);
      });
    }

    test('propagates CredentialException on refresh failure', () async {
      final creds = _FakeCredentials(({uri, required forceRefresh}) {
        if (forceRefresh) {
          throw CredentialException('refresh token revoked');
        }
        return {
          'authorization': ['Bearer stale-tok'],
        };
      });
      final delegate = MockClient((_) async => http.Response('', 401));
      final client = CredClient(creds, delegate);
      addTearDown(client.close);

      await expectLater(
        () => client.get(testUrl),
        throwsA(isA<CredentialException>()),
      );
    });

    test('forwards StreamedRequest without buffering and sets auth', () async {
      final creds = _FakeCredentials.tokens(['stream-tok']);
      String? seenAuth;
      int? seenContentLength;
      List<int>? seenBytes;

      final delegate = _TrackingClient((request) async {
        seenAuth = request.headers['authorization'];
        seenContentLength = request.contentLength;
        seenBytes = await request.finalize().toBytes();
        return http.StreamedResponse(
          Stream.value(utf8.encode('stream-ok')),
          200,
        );
      });
      final client = CredClient(creds, delegate);
      addTearDown(client.close);

      final streamedRequest = http.StreamedRequest('PUT', testUrl)
        ..contentLength = 6;
      unawaited(() async {
        streamedRequest.sink.add([1, 2, 3]);
        streamedRequest.sink.add([4, 5, 6]);
        await streamedRequest.sink.close();
      }());

      final response = await http.Response.fromStream(
        await client.send(streamedRequest),
      );
      expect(response.statusCode, 200);
      expect(response.body, 'stream-ok');
      expect(seenAuth, 'Bearer stream-tok');
      expect(seenContentLength, 6);
      expect(seenBytes, [1, 2, 3, 4, 5, 6]);
    });

    test('supports AbortableRequest aborted during requestMetadata', () async {
      final abortCompleter = Completer<void>();
      final creds = _FakeCredentials(({uri, required forceRefresh}) async {
        abortCompleter.complete();
        await Future<void>.delayed(Duration.zero);
        return {
          'authorization': ['Bearer tok'],
        };
      });
      var delegateCalled = false;
      final delegate = _TrackingClient((_) async {
        delegateCalled = true;
        return http.StreamedResponse(const Stream.empty(), 200);
      });
      final client = CredClient(creds, delegate);
      addTearDown(client.close);

      final request = http.AbortableRequest(
        'GET',
        testUrl,
        abortTrigger: abortCompleter.future,
      );

      await expectLater(
        () => client.send(request),
        throwsA(isA<http.RequestAbortedException>()),
      );
      expect(delegateCalled, isFalse);
    });

    test('close closes the delegate client', () {
      final creds = _FakeCredentials.tokens(['tok']);
      final delegate = _TrackingClient(
        (_) async => http.StreamedResponse(const Stream.empty(), 200),
      );
      final client = CredClient(creds, delegate);
      expect(delegate.isClosed, isFalse);
      client.close();
      expect(delegate.isClosed, isTrue);
    });
  });

  group('Storage with CredClient and credentials', () {
    test('authenticates metadata, upload, download, and sink upload', () async {
      final creds = _FakeCredentials.tokens(['storage-tok']);
      final seenAuth = <String?>[];
      final delegate = _TrackingClient((request) async {
        seenAuth.add(request.headers['authorization']);
        final bodyBytes = await request.finalize().toBytes();
        final path = request.url.path;

        if (request.method == 'GET' &&
            request.url.queryParameters['alt'] == 'media') {
          return http.StreamedResponse(
            Stream.value(utf8.encode('hello')),
            200,
            headers: {'x-goog-stored-content-encoding': 'identity'},
          );
        }
        if (request.method == 'GET' && path == '/storage/v1/b/my-bkt') {
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"name":"my-bkt"}')),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' &&
            request.url.queryParameters['uploadType'] == 'multipart') {
          expect(bodyBytes, isNotEmpty);
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"name":"obj","bucket":"my-bkt"}')),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' &&
            request.url.queryParameters['uploadType'] == 'resumable') {
          return http.StreamedResponse(
            const Stream.empty(),
            200,
            headers: {
              'location':
                  'https://storage.googleapis.com/upload/storage/v1/b/my-bkt/o?upload_id=123',
            },
          );
        }
        if (request.method == 'PUT' &&
            request.url.queryParameters['upload_id'] == '123') {
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"name":"sink-obj","bucket":"my-bkt"}')),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.StreamedResponse(const Stream.empty(), 404);
      });

      final storage = Storage(
        projectId: 'test-project',
        client: CredClient(creds, delegate),
      );

      final bucketMeta = await storage.bucketMetadata('my-bkt');
      expect(bucketMeta.name, 'my-bkt');

      final downloaded = await storage.downloadObject('my-bkt', 'obj');
      expect(utf8.decode(downloaded), 'hello');

      final uploaded = await storage.uploadObject('my-bkt', 'obj', [1, 2, 3]);
      expect(uploaded.name, 'obj');

      final sink = storage.uploadObjectFromSink('my-bkt', 'sink-obj')
        ..add([4, 5, 6]);
      final sinkUploaded = await sink.close();
      expect(sinkUploaded.name, 'sink-obj');

      expect(seenAuth, hasLength(5));
      expect(seenAuth, everyElement('Bearer storage-tok'));

      storage.close();
      expect(delegate.isClosed, isTrue);
    });

    test('does not double-authenticate an explicit http.Client', () async {
      final creds = _FakeCredentials.tokens(['cred-tok']);
      late http.Request captured;
      final explicitClient = MockClient((request) async {
        captured = request;
        return http.Response('{"name":"my-bkt"}', 200);
      });

      final storage = Storage(
        projectId: 'test-project',
        client: explicitClient,
        credentials: creds,
      );
      addTearDown(storage.close);

      await storage.bucketMetadata('my-bkt');
      expect(creds.calls, isEmpty);
      expect(captured.headers.containsKey('authorization'), isFalse);
    });
  });
}
