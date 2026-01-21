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
library;

import 'dart:math';

import 'package:google_cloud_storage/google_cloud_storage.dart';
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:test/test.dart';
import 'package:test_utils/cloud.dart';
import 'package:test_utils/test_http_client.dart';

const bucketChars = 'abcdefghijklmnopqrstuvwxyz0123456789';

String uniqueBucketName() {
  final random = Random();
  return List.generate(
    32,
    (index) => bucketChars[random.nextInt(bucketChars.length)],
  ).join();
}

void main() async {
  late StorageService storageService;
  late TestHttpClient testClient;

  group('bucket', () {
    setUp(() async {
      storageService = StorageService();
    });

    test('create', () async {
      final bucketName =
          //          TestHttpClient.isRecording || TestHttpClient.isReplaying
          //        ? 'dart-cloud-storage-test-bucket-create'
          //:
          //
          uniqueBucketName();

      //      final bucket = await storageService.createBucket(bucketName);
      // https://storage.googleapis.com/dart-cloud-storage-test-bucket-create/Baelish_Portrait_5th_level%20(2).webp
      final bucket = await storageService.getObjectMetadata(
        'dart-cloud-storage-test-bucket-create',
        'Baelish_Portrait_5th_level (2).webp',
      );
    });
  });
}
