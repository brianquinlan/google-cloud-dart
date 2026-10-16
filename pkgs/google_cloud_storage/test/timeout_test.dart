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

import 'package:google_cloud_rpc/retry.dart';
import 'package:google_cloud_storage/google_cloud_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _timeout = Duration(milliseconds: 50);

void main() {
  late List<http.Request> requests;

  /// A [Storage] that sends each response in [responses] in turn. A `null`
  /// response never arrives.
  Storage storageWithResponses(List<String?> responses) => Storage(
    client: MockClient((request) {
      requests.add(request);
      final body = responses.removeAt(0);
      return body == null
          ? Completer<http.Response>().future
          : Future.value(http.Response(body, 200));
    }),
    projectId: 'project',
  );

  setUp(() => requests = []);

  test('idempotent operations retry requests that time out', () async {
    final storage = storageWithResponses([
      null,
      '{"name": "bucket", "metageneration": "1"}',
    ]);

    final metadata = await storage.bucketMetadata('bucket', timeout: _timeout);
    expect(metadata.name, 'bucket');
    expect(requests, hasLength(2));
  });

  test(
    'non-idempotent operations do not retry requests that time out',
    () async {
      final storage = storageWithResponses([null, '{}']);

      await expectLater(
        storage.insertBucketAcl(
          'bucket',
          'allUsers',
          'READER',
          timeout: _timeout,
        ),
        throwsA(
          isA<TimeoutException>().having(
            (e) => e.duration,
            'duration',
            _timeout,
          ),
        ),
      );
      expect(requests, hasLength(1));
    },
  );

  test('each page request has its own timeout', () async {
    final storage = storageWithResponses([
      '{"items": [{"name": "a"}], "nextPageToken": "next"}',
      null,
      '{"items": [{"name": "b"}]}',
    ]);

    final objects = await storage
        .listObjects(
          'bucket',
          timeout: _timeout,
          retry: const ExponentialRetry(
            retryIf: isTransientError,
            initialDelay: Duration.zero,
          ),
        )
        .toList();
    expect(objects.map((o) => o.name), ['a', 'b']);
    expect(requests.map((r) => r.url.queryParameters['pageToken']), [
      null,
      'next',
      'next',
    ]);
  });

  group('forwarded by', () {
    const retry = noRetry;
    final calls = <String, Future<Object?> Function(Storage)>{
      'Storage.bucketMetadata': (s) =>
          s.bucketMetadata('bucket', retry: retry, timeout: _timeout),
      'Storage.createBucket': (s) => s.createBucket(
        BucketMetadata(name: 'bucket'),
        retry: retry,
        timeout: _timeout,
      ),
      'Storage.deleteBucket': (s) =>
          s.deleteBucket('bucket', retry: retry, timeout: _timeout),
      'Storage.deleteBucketAcl': (s) => s.deleteBucketAcl(
        'bucket',
        'allUsers',
        retry: retry,
        timeout: _timeout,
      ),
      'Storage.getBucketAcl': (s) =>
          s.getBucketAcl('bucket', 'allUsers', retry: retry, timeout: _timeout),
      'Storage.insertBucketAcl': (s) => s.insertBucketAcl(
        'bucket',
        'allUsers',
        'READER',
        retry: retry,
        timeout: _timeout,
      ),
      'Storage.listBucketAcl': (s) =>
          s.listBucketAcl('bucket', retry: retry, timeout: _timeout),
      'Storage.listBuckets': (s) =>
          s.listBuckets(retry: retry, timeout: _timeout).toList(),
      'Storage.patchBucket': (s) => s.patchBucket(
        'bucket',
        BucketMetadataPatchBuilder(),
        retry: retry,
        timeout: _timeout,
      ),
      'Storage.patchBucketAcl': (s) => s.patchBucketAcl(
        'bucket',
        'allUsers',
        'READER',
        retry: retry,
        timeout: _timeout,
      ),
      'Storage.updateBucketAcl': (s) => s.updateBucketAcl(
        'bucket',
        'allUsers',
        'READER',
        retry: retry,
        timeout: _timeout,
      ),
      'Storage.deleteObject': (s) =>
          s.deleteObject('bucket', 'object', retry: retry, timeout: _timeout),
      'Storage.deleteObjectAcl': (s) => s.deleteObjectAcl(
        'bucket',
        'object',
        'allUsers',
        retry: retry,
        timeout: _timeout,
      ),
      'Storage.getObjectAcl': (s) => s.getObjectAcl(
        'bucket',
        'object',
        'allUsers',
        retry: retry,
        timeout: _timeout,
      ),
      'Storage.insertObjectAcl': (s) => s.insertObjectAcl(
        'bucket',
        'object',
        'allUsers',
        'READER',
        retry: retry,
        timeout: _timeout,
      ),
      'Storage.listObjectAcl': (s) =>
          s.listObjectAcl('bucket', 'object', retry: retry, timeout: _timeout),
      'Storage.listObjects': (s) =>
          s.listObjects('bucket', retry: retry, timeout: _timeout).toList(),
      'Storage.makeObjectPublic': (s) => s.makeObjectPublic(
        'bucket',
        'object',
        retry: retry,
        timeout: _timeout,
      ),
      'Storage.moveObject': (s) =>
          s.moveObject('bucket', 'from', 'to', retry: retry, timeout: _timeout),
      'Storage.objectMetadata': (s) =>
          s.objectMetadata('bucket', 'object', retry: retry, timeout: _timeout),
      'Storage.patchObject': (s) => s.patchObject(
        'bucket',
        'object',
        ObjectMetadataPatchBuilder(),
        retry: retry,
        timeout: _timeout,
      ),
      'Storage.patchObjectAcl': (s) => s.patchObjectAcl(
        'bucket',
        'object',
        'allUsers',
        'READER',
        retry: retry,
        timeout: _timeout,
      ),
      'Storage.rewriteObject': (s) => s.rewriteObject(
        'bucket',
        'from',
        'bucket',
        'to',
        retry: retry,
        timeout: _timeout,
      ),
      'Storage.updateObjectAcl': (s) => s.updateObjectAcl(
        'bucket',
        'object',
        'allUsers',
        'READER',
        retry: retry,
        timeout: _timeout,
      ),
      'Bucket.create': (s) =>
          s.bucket('bucket').create(retry: retry, timeout: _timeout),
      'Bucket.delete': (s) =>
          s.bucket('bucket').delete(retry: retry, timeout: _timeout),
      'Bucket.metadata': (s) =>
          s.bucket('bucket').metadata(retry: retry, timeout: _timeout),
      'Bucket.patch': (s) => s
          .bucket('bucket')
          .patch(BucketMetadataPatchBuilder(), retry: retry, timeout: _timeout),
      'StorageObject.delete': (s) => s
          .bucket('bucket')
          .object('object')
          .delete(retry: retry, timeout: _timeout),
      'StorageObject.makePublic': (s) => s
          .bucket('bucket')
          .object('object')
          .makePublic(retry: retry, timeout: _timeout),
      'StorageObject.metadata': (s) => s
          .bucket('bucket')
          .object('object')
          .metadata(retry: retry, timeout: _timeout),
      'StorageObject.move': (s) => s
          .bucket('bucket')
          .object('object')
          .move('to', retry: retry, timeout: _timeout),
      'StorageObject.patch': (s) => s
          .bucket('bucket')
          .object('object')
          .patch(ObjectMetadataPatchBuilder(), retry: retry, timeout: _timeout),
      'StorageObject.rewrite': (s) => s
          .bucket('bucket')
          .object('object')
          .rewrite('to', retry: retry, timeout: _timeout),
    };

    for (final MapEntry(key: name, value: call) in calls.entries) {
      test(name, () async {
        final storage = storageWithResponses([null]);

        await expectLater(call(storage), throwsA(isA<TimeoutException>()));
        expect(requests, hasLength(1));
      });
    }
  });
}
