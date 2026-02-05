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

@TestOn('vm')
library;

import 'dart:math';

import 'package:google_cloud_storage/google_cloud_storage.dart';
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:test_utils/cloud.dart';
import 'package:test_utils/test_http_client.dart';

const bucketChars = 'abcdefghijklmnopqrstuvwxyz0123456789';

String uniqueBucketName() {
  final random = Random();
  return [
    for (int i = 0; i < 32; i++)
      bucketChars[random.nextInt(bucketChars.length)],
  ].join();
}

void main() async {
  late Storage storage;
  late TestHttpClient testClient;

  group('bucket metadata', () {
    setUp(() async {
      Future<auth.AutoRefreshingAuthClient> authClient() async =>
          await auth.clientViaApplicationDefaultCredentials(
            scopes: [
              'https://www.googleapis.com/auth/cloud-platform',
              'https://www.googleapis.com/auth/devstorage.read_write',
            ],
          );

      testClient = await TestHttpClient.fromEnvironment(authClient);
      storage = Storage(client: testClient, projectId: projectId);
    });

    tearDown(() => storage.close());

    test('success', () async {
      await testClient.startTest(
        'google_cloud_storage',
        'get_bucket_metadata_success',
      );
      addTearDown(testClient.endTest);
      final bucketName =
          TestHttpClient.isRecording || TestHttpClient.isReplaying
          ? 'get_bucket_metadata_success'
          : uniqueBucketName();

      await storage.createBucket(BucketMetadata(name: bucketName));

      final metadata = await storage.bucketMetadata(bucketName);

      expect(metadata.name, bucketName);
      expect(metadata.kind, 'storage#bucket');
      expect(metadata.metageneration, 1);
    });

    test('get non-existent bucket metadata', () async {
      await testClient.startTest(
        'google_cloud_storage',
        'get_bucket_metadata_non_existent',
      );
      addTearDown(testClient.endTest);
      final bucketName =
          TestHttpClient.isRecording || TestHttpClient.isReplaying
          ? 'get_bucket_metadata_non_existent'
          : uniqueBucketName();

      expect(
        () => storage.bucketMetadata(bucketName),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('get bucket metadata with ifMetagenerationMatch success', () async {
      await testClient.startTest(
        'google_cloud_storage',
        'get_bucket_metadata_with_if_metageneration_match_success',
      );
      addTearDown(testClient.endTest);
      final bucketName =
          TestHttpClient.isRecording || TestHttpClient.isReplaying
          ? 'get_bucket_metadata_with_if_metageneration_match_success'
          : uniqueBucketName();

      final created = await storage.createBucket(
        BucketMetadata(name: bucketName),
      );

      final metadata = await storage.bucketMetadata(
        bucketName,
        ifMetagenerationMatch: created.metageneration,
      );

      expect(metadata.metageneration, created.metageneration);
    });

    test('get bucket metadata with ifMetagenerationMatch failure', () async {
      await testClient.startTest(
        'google_cloud_storage',
        'get_bucket_metadata_with_if_metageneration_match_failure',
      );
      addTearDown(testClient.endTest);
      final bucketName =
          TestHttpClient.isRecording || TestHttpClient.isReplaying
          ? 'get_bucket_metadata_with_if_metageneration_match_failure'
          : uniqueBucketName();

      await storage.createBucket(BucketMetadata(name: bucketName));

      expect(
        () => storage.bucketMetadata(bucketName, ifMetagenerationMatch: 0),
        throwsA(isA<PreconditionFailedException>()),
      );
    });

    test('idempotent transport failure', () async {
      var count = 0;
      final mockClient = MockClient((request) async {
        count++;
        if (count == 1) {
          throw http.ClientException('Some transport failure');
        } else if (count == 2) {
          return http.Response(
            '{"name": "bucket", "kind": "storage#bucket"}',
            200,
            headers: {'content-type': 'application/json; charset=UTF-8'},
          );
        } else {
          throw StateError('Unexpected call count: $count');
        }
      });

      final storage = Storage(client: mockClient, projectId: projectId);

      final metadata = await storage.bucketMetadata('bucket');
      expect(metadata.name, 'bucket');
      expect(count, 2);
    });
  });
}
