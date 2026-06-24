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

import 'package:google_cloud_storage/google_cloud_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() async {
  late Storage storage;

  group('copy object', () {
    group('google-cloud', tags: ['google-cloud'], () {
      setUp(() {
        storage = Storage();
      });

      tearDown(() => storage.close());

      test('success same bucket', () async {
        final bucketName = await createBucketWithTearDown(
          storage,
          'copy_obj_same',
        );
        await storage.uploadObject(
          bucketName,
          'source.txt',
          utf8.encode('content'),
          ifGenerationMatch: BigInt.zero,
        );

        final copied = await storage.copyObject(
          bucketName,
          'source.txt',
          bucketName,
          'dest.txt',
        );

        expect(copied.name, 'dest.txt');
        expect(copied.bucket, bucketName);
        expect(copied.metageneration, BigInt.one);

        // Verify source still exists
        final sourceMeta = await storage.objectMetadata(
          bucketName,
          'source.txt',
        );
        expect(sourceMeta.name, 'source.txt');

        // Verify dest exists and has correct content
        final destMeta = await storage.objectMetadata(bucketName, 'dest.txt');
        expect(destMeta.name, 'dest.txt');
        final bytes = await storage.downloadObject(bucketName, 'dest.txt');
        expect(utf8.decode(bytes), 'content');
      });

      test('success cross bucket', () async {
        final srcBucketName = await createBucketWithTearDown(
          storage,
          'copy_obj_cross_src',
        );
        final destBucketName = await createBucketWithTearDown(
          storage,
          'copy_obj_cross_dest',
        );

        await storage.uploadObject(
          srcBucketName,
          'source.txt',
          utf8.encode('cross-bucket-content'),
          ifGenerationMatch: BigInt.zero,
        );

        final copied = await storage.copyObject(
          srcBucketName,
          'source.txt',
          destBucketName,
          'dest.txt',
        );

        expect(copied.name, 'dest.txt');
        expect(copied.bucket, destBucketName);

        // Verify dest exists and has correct content
        final bytes = await storage.downloadObject(destBucketName, 'dest.txt');
        expect(utf8.decode(bytes), 'cross-bucket-content');
      });

      test('copy through StorageObject.copyTo same bucket', () async {
        final bucketName = await createBucketWithTearDown(
          storage,
          'copy_so_same',
        );
        final source = storage.bucket(bucketName).object('source.txt');
        await source.uploadAsString(
          'so-content',
          ifGenerationMatch: BigInt.zero,
        );

        final copied = await source.copyTo('dest.txt');
        expect(copied.name, 'dest.txt');
        expect(copied.bucket, bucketName);

        final dest = storage.bucket(bucketName).object('dest.txt');
        final bytes = await dest.download();
        expect(utf8.decode(bytes), 'so-content');
      });

      test('copy through StorageObject.copyTo cross bucket', () async {
        final srcBucketName = await createBucketWithTearDown(
          storage,
          'copy_so_cross_src',
        );
        final destBucketName = await createBucketWithTearDown(
          storage,
          'copy_so_cross_dest',
        );

        final source = storage.bucket(srcBucketName).object('source.txt');
        await source.uploadAsString(
          'cross-so-content',
          ifGenerationMatch: BigInt.zero,
        );

        final copied = await source.copyTo(
          'dest.txt',
          destinationBucket: destBucketName,
        );
        expect(copied.name, 'dest.txt');
        expect(copied.bucket, destBucketName);

        final dest = storage.bucket(destBucketName).object('dest.txt');
        final bytes = await dest.download();
        expect(utf8.decode(bytes), 'cross-so-content');
      });

      test('metadata override', () async {
        final bucketName = await createBucketWithTearDown(
          storage,
          'copy_obj_meta',
        );
        await storage.uploadObject(
          bucketName,
          'source.txt',
          utf8.encode('content'),
          metadata: ObjectMetadata(contentType: 'text/plain'),
          ifGenerationMatch: BigInt.zero,
        );

        final copied = await storage.copyObject(
          bucketName,
          'source.txt',
          bucketName,
          'dest.txt',
          metadata: ObjectMetadata(contentType: 'application/json'),
        );

        expect(copied.name, 'dest.txt');
        expect(copied.contentType, 'application/json');
      });

      test('ifGenerationMatch: 0 failure', () async {
        final bucketName = await createBucketWithTearDown(
          storage,
          'copy_obj_fail_exist',
        );
        await storage.uploadObject(
          bucketName,
          'source.txt',
          utf8.encode('source'),
          ifGenerationMatch: BigInt.zero,
        );
        await storage.uploadObject(
          bucketName,
          'dest.txt',
          utf8.encode('dest'),
          ifGenerationMatch: BigInt.zero,
        );

        expect(
          () => storage.copyObject(
            bucketName,
            'source.txt',
            bucketName,
            'dest.txt',
            ifGenerationMatch: BigInt.zero,
          ),
          throwsA(isA<PreconditionFailedException>()),
        );
      });

      test('ifSourceGenerationMatch success', () async {
        final bucketName = await createBucketWithTearDown(
          storage,
          'copy_obj_src_gen_ok',
        );
        final source = await storage.uploadObject(
          bucketName,
          'source.txt',
          utf8.encode('content'),
          ifGenerationMatch: BigInt.zero,
        );

        final copied = await storage.copyObject(
          bucketName,
          'source.txt',
          bucketName,
          'dest.txt',
          ifSourceGenerationMatch: source.generation,
        );

        expect(copied.name, 'dest.txt');
      });

      test('ifSourceGenerationMatch failure', () async {
        final bucketName = await createBucketWithTearDown(
          storage,
          'copy_obj_src_gen_fail',
        );
        final source = await storage.uploadObject(
          bucketName,
          'source.txt',
          utf8.encode('content'),
          ifGenerationMatch: BigInt.zero,
        );

        expect(
          () => storage.copyObject(
            bucketName,
            'source.txt',
            bucketName,
            'dest.txt',
            ifSourceGenerationMatch: source.generation! + BigInt.one,
          ),
          throwsA(isA<PreconditionFailedException>()),
        );
      });
    });

    test('query parameters and body serialization', () async {
      var called = false;
      final mockClient = MockClient((request) async {
        called = true;
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/storage/v1/b/src-bucket/o/source.txt/copyTo/b/dest-bucket/o/dest.txt',
        );
        expect(request.url.queryParameters, {
          'sourceGeneration': '123',
          'ifSourceGenerationMatch': '456',
          'ifGenerationMatch': '789',
          'destinationPredefinedAcl': 'publicRead',
          'projection': 'full',
          'userProject': 'my-billing-project',
        });

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['contentType'], 'application/json');

        return http.Response(
          jsonEncode({
            'kind': 'storage#object',
            'name': 'dest.txt',
            'bucket': 'dest-bucket',
            'contentType': 'application/json',
          }),
          200,
          headers: {'content-type': 'application/json; charset=UTF-8'},
        );
      });

      final storage = Storage(client: mockClient, projectId: 'fake-project');
      final result = await storage.copyObject(
        'src-bucket',
        'source.txt',
        'dest-bucket',
        'dest.txt',
        metadata: ObjectMetadata(contentType: 'application/json'),
        sourceGeneration: BigInt.from(123),
        ifSourceGenerationMatch: BigInt.from(456),
        ifGenerationMatch: BigInt.from(789),
        destinationPredefinedAcl: 'publicRead',
        projection: 'full',
        userProject: 'my-billing-project',
      );

      expect(called, isTrue);
      expect(result.name, 'dest.txt');
      expect(result.contentType, 'application/json');
    });

    test('idempotent transport failure', () async {
      var count = 0;
      final mockClient = MockClient((request) async {
        count++;
        if (count == 1) {
          throw http.ClientException('Some transport failure');
        } else if (count == 2) {
          return http.Response(
            jsonEncode({
              'kind': 'storage#object',
              'name': 'dest.txt',
              'bucket': 'dest-bucket',
            }),
            200,
            headers: {'content-type': 'application/json; charset=UTF-8'},
          );
        } else {
          throw StateError('Unexpected call count: $count');
        }
      });

      final storage = Storage(client: mockClient, projectId: 'fake-project');

      // Should retry because ifGenerationMatch is specified
      await storage.copyObject(
        'src-bucket',
        'source.txt',
        'dest-bucket',
        'dest.txt',
        ifGenerationMatch: BigInt.from(789),
      );
      expect(count, 2);
    });

    test('non-idempotent transport failure', () async {
      var count = 0;
      final mockClient = MockClient((request) async {
        count++;
        if (count == 1) {
          throw http.ClientException('Some transport failure');
        } else {
          throw StateError('Unexpected call count: $count');
        }
      });

      final storage = Storage(client: mockClient, projectId: 'fake-project');

      // Should not retry because no generation conditions are specified
      await expectLater(
        storage.copyObject(
          'src-bucket',
          'source.txt',
          'dest-bucket',
          'dest.txt',
        ),
        throwsA(isA<http.ClientException>()),
      );
      expect(count, 1);
    });
  });
}
