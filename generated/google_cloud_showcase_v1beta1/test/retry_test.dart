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
// `setUpAll` builds and installs the Showcase server with `go install`, which
// can take much longer than the default 30s timeout when the Go build cache is
// cold.
@Timeout(Duration(minutes: 5))
library;

import 'package:google_cloud_rpc/retry.dart';
import 'package:google_cloud_rpc/rpc.dart';
import 'package:google_cloud_showcase_v1beta1/showcase.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:test_utils/insecure_proxy_http_client.dart';

import 'showcase_server.dart';

const _ok = 0;
const _invalidArgument = 3;
const _resourceExhausted = 8;
const _unavailable = 14;

void main() async {
  late SequenceService sequenceService;
  late ShowcaseServer showcaseServer;

  group('retry', () {
    setUpAll(() async {
      showcaseServer = await ShowcaseServer.start();
      sequenceService = SequenceService(
        client: InsecureProxyHttpClient(http.Client()),
      );
    });

    tearDownAll(() async {
      sequenceService.close();
      await showcaseServer.stop();
    });

    test('default does not retry', () async {
      final sequence = await sequenceService.createSequence(
        CreateSequenceRequest(
          sequence: Sequence(
            responses: [
              Sequence_Response(status: Status(code: _unavailable)),
              Sequence_Response(status: Status(code: _ok)),
            ],
          ),
        ),
      );

      await expectLater(
        () => sequenceService.attemptSequence(
          AttemptSequenceRequest(name: sequence.name),
        ),
        throwsA(isA<ServiceUnavailableException>()),
      );

      final report = await sequenceService.getSequenceReport(
        GetSequenceReportRequest(name: '${sequence.name}/sequenceReport'),
      );
      expect(report.attempts, hasLength(1));
    });

    test('retries transient failures until success', () async {
      final sequence = await sequenceService.createSequence(
        CreateSequenceRequest(
          sequence: Sequence(
            responses: [
              Sequence_Response(status: Status(code: _unavailable)),
              Sequence_Response(status: Status(code: _resourceExhausted)),
              Sequence_Response(status: Status(code: _ok)),
            ],
          ),
        ),
      );

      await sequenceService.attemptSequence(
        AttemptSequenceRequest(name: sequence.name),
        retry: const ExponentialRetry.onCodes([
          Code.unavailable,
          Code.resourceExhausted,
        ], initialDelay: Duration(milliseconds: 10)),
      );

      final report = await sequenceService.getSequenceReport(
        GetSequenceReportRequest(name: '${sequence.name}/sequenceReport'),
      );
      expect(report.attempts.map((a) => a.status?.code), [
        _unavailable,
        _resourceExhausted,
        _ok,
      ]);
    });

    test('stops on non-retryable error', () async {
      final sequence = await sequenceService.createSequence(
        CreateSequenceRequest(
          sequence: Sequence(
            responses: [
              Sequence_Response(status: Status(code: _unavailable)),
              Sequence_Response(status: Status(code: _invalidArgument)),
              Sequence_Response(status: Status(code: _ok)),
            ],
          ),
        ),
      );

      await expectLater(
        () => sequenceService.attemptSequence(
          AttemptSequenceRequest(name: sequence.name),
          retry: const ExponentialRetry.onCodes([
            Code.unavailable,
          ], initialDelay: Duration(milliseconds: 10)),
        ),
        throwsA(isA<BadRequestException>()),
      );

      final report = await sequenceService.getSequenceReport(
        GetSequenceReportRequest(name: '${sequence.name}/sequenceReport'),
      );
      expect(report.attempts.map((a) => a.status?.code), [
        _unavailable,
        _invalidArgument,
      ]);
    });

    test('stops when maxRetries is reached', () async {
      final sequence = await sequenceService.createSequence(
        CreateSequenceRequest(
          sequence: Sequence(
            responses: [
              Sequence_Response(status: Status(code: _unavailable)),
              Sequence_Response(status: Status(code: _unavailable)),
              Sequence_Response(status: Status(code: _unavailable)),
              Sequence_Response(status: Status(code: _ok)),
            ],
          ),
        ),
      );

      await expectLater(
        () => sequenceService.attemptSequence(
          AttemptSequenceRequest(name: sequence.name),
          retry: const ExponentialRetry.onCodes(
            [Code.unavailable],
            maxRetries: 1,
            initialDelay: Duration(milliseconds: 10),
          ),
        ),
        throwsA(isA<ServiceUnavailableException>()),
      );

      final report = await sequenceService.getSequenceReport(
        GetSequenceReportRequest(name: '${sequence.name}/sequenceReport'),
      );
      expect(report.attempts, hasLength(2));
    });
  });
}
