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
import 'package:google_cloud_storage/src/file_upload.dart'
    show fixedBoundaryString;
import 'package:test/test.dart';

import 'test_utils.dart';

void main() async {
  late Storage storage;

  group('upload object stream', () {
    group('google-cloud', tags: ['google-cloud'], () {
      setUp(() {
        fixedBoundaryString = 'boundary';
        storage = Storage();
      });

      tearDown(() => storage.close());

      test('successful upload', () async {
        final bucketName = await createBucketWithTearDown(
          storage,
          'upload_object_stream',
        );

        final upload = await storage.uploadObjectStream(
          bucketName,
          'test_stream.txt',
        );

        upload.sink.add(utf8.encode('Hello, '));
        upload.sink.add(utf8.encode('Stream World!'));
        await upload.sink.close();

        final metadata = await upload.metadata;
        expect(metadata.name, 'test_stream.txt');
        expect(metadata.size, '20');

        final downloaded = await storage.downloadObject(
          bucketName,
          'test_stream.txt',
        );
        expect(utf8.decode(downloaded), 'Hello, Stream World!');
      });
    });
  });
}
