// Copyright 2025 Google LLC
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
import 'dart:math';

import 'package:google_cloud_storage_v2/storage.dart';
import 'package:test/test.dart';
import 'package:google_cloud_protobuf/protobuf.dart' as protobuf;

import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:test_utils/cloud.dart';
import 'package:test_utils/test_http_client.dart';

import '../lib/storage.dart';

void main() async {
  late Storage storage;
  late TestHttpClient testClient;

  group('CloudStorageV2', () {
    setUp(() async {
      final authClient = () async =>
          await auth.clientViaApplicationDefaultCredentials(
            scopes: ['https://www.googleapis.com/auth/cloud-platform'],
          );

      testClient = await TestHttpClient.fromEnvironment(authClient);
      storage = Storage(client: testClient);
    });

    tearDown(() => storage.close());
    test('create_and_update', () async {
      await testClient.startTest(
        'google_cloud_storage_v2',
        'create_and_update',
      );

      final bucketName =
          TestHttpClient.isRecording || TestHttpClient.isReplaying
          ? 'mybucket'
          : '${Random().nextInt(999999999)}${Random().nextInt(999999999)}';

      final createdBucket = await storage.createBucket(
        CreateBucketRequest(
          parent: '',
          bucketId: '123',
          bucket: Bucket(name: 'projects/$projectId/buckets/123'),
        ),
      );
      await testClient.endTest();
    });
  });
}
