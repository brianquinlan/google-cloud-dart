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

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import '../google_cloud_storage.dart';
import 'retry.dart';
import 'shim.dart' as shim;

// https://github.com/googleapis/googleapis/blob/211d22fa6dfabfa52cbda04d1aee852a01301edf/google/storage/v2/storage.proto
// https://github.com/invertase/dart_firebase_admin/tree/googleapis-storage/packages/googleapis_storage

// Get project is not provided - Python does the same but not Java.

// Discovery service or proto?
// How to run retry conformance tests?

typedef example_callback = ffi.Void Function();

final class StorageService {
  static const _host = 'storage.googleapis.com';
  final shim.ShimClient _client;

  StorageService() : _client = shim.createClient();

  /*
  Future<void> write(String bucketName) async {
    final w = writeObject(
      _client,
      bucketName.toNativeUtf8().cast(),
      'test-object'.toNativeUtf8().cast(),
    );
    writeChunk(w, 'test'.toNativeUtf8().cast(), 4);
    destroyWriter(w);
  }*/

  Future<void> createBucket(String bucketName) async {
    final completer = Completer<void>();
    void callback() {
      completer.complete();
    }

    final c = ffi.NativeCallable<example_callback>.listener(callback);

    shim.createBucket(
      _client,
      bucketName.toNativeUtf8().cast(),
      c.nativeFunction,
    );
    return completer.future;
  }

  void close() {
    shim.destroyClient(_client);
  }
}
