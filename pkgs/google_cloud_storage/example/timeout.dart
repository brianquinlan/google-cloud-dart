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

// #docregion timeout
import 'dart:async';

import 'package:google_cloud_rpc/retry.dart';
import 'package:google_cloud_storage/google_cloud_storage.dart';

void main() async {
  final storage = Storage();

  // Give up on each request after 10 seconds. This operation is idempotent, so
  // a request that times out is retried using `defaultRetry`.
  await storage.bucketMetadata(
    'my-bucket',
    timeout: const Duration(seconds: 10),
  );

  // Make a single request, and give up after 5 seconds.
  try {
    await storage.objectMetadata(
      'my-bucket',
      'my-object',
      timeout: const Duration(seconds: 5),
      retry: noRetry,
    );
  } on TimeoutException {
    print('Cloud Storage did not respond in time.');
  }

  storage.close();
}

// #enddocregion timeout
