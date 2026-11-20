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

import 'package:google_cloud_protobuf/protobuf.dart' show JsonEncodable;
import 'package:http/http.dart' as http;

import 'exceptions.dart';
import 'retry.dart';
import 'src/version.dart';
import 'src/web.dart'
    if (dart.library.io) 'src/vm.dart'
    show clientDartVersion, userAgentForClient;

export 'dart:typed_data' show Uint8List;

export 'src/web.dart'
    if (dart.library.io) 'src/vm.dart'
    show clientDartVersion, httpClientFromApiKey;

const String _clientKey = 'x-goog-api-client';
const String _userAgentKey = 'user-agent';

// ignore: prefer_const_declarations
String get _baseClientName =>
    'gl-dart/$clientDartVersion gax/$packageVersion rest/$packageVersion';

const String _contentTypeKey = 'content-type';
const String _typeJson = 'application/json';

/// A low-level mechanism to communicate with Google APIs.
///
/// Every request method takes a `retry` argument that decides whether, and
/// how, failed attempts are retried. `retry` defaults to [noRetry]: a
/// [ServiceClient] doesn't know whether an operation is safe to repeat, so the
/// caller must decide.
///
/// Every request method also takes a `timeout` argument. If `timeout` is set,
/// an attempt that doesn't complete within `timeout` fails with a
/// [TimeoutException]. The timeout applies to each attempt separately, and
/// `retry` decides whether an attempt that timed out is retried. For example,
/// [ExponentialRetry.onCodes] treats a [TimeoutException] as
/// [Code.deadlineExceeded]. If the final attempt fails with a
/// [TimeoutException], then there is no guarantee that the server did not
/// complete the request successfully.
///
/// For a streaming request, `timeout` limits the whole stream, including time
/// that the stream subscription is paused. Streaming request methods also take
/// a `streamWaitTimeout` argument, which limits the wait for the response to
/// start, and then the maximum delay between events. Time that the stream
/// subscription is paused doesn't count towards `streamWaitTimeout`.
///
/// If the server responds to a streaming request with server-sent events,
/// events reach the caller as they arrive. If a timeout happens after a
/// response has started, the response stream ends with a [TimeoutException] and
/// is not retried.
class ServiceClient {
  // As of 2026-10-16 there is no consistent timeout behavior for RPCs across
  // Google Cloud client libraries:
  //
  // For unary (non-streaming) requests:
  // - Go, Python, and Node.js apply the timeout to the entire call, i.e., all
  //   retries must complete within the timeout period.
  // - Java and Rust apply the timeout to each request attempt independently and
  //   use retry settings to limit the total call time.
  //
  // For streaming requests:
  // - Go has a deadline that applies to the entire stream but with no default
  //   timeout because of a concern for long-lived streams
  //   (see https://github.com/googleapis/gapic-generator-go/issues/411).
  // - Java has three timeout options for streams: a deadline for the entire
  //   stream (`timeout`), a deadline for the gap between messages
  //   (`streamWaitTimeout`), and a deadline for the caller asking for more
  //   data (`streamIdleTimeout`).
  // - Python (gRPC) has a deadline that applies to the entire stream.
  // - Python (REST) has a deadline that applies to the gap between messages.
  // - Node.js and Rust have deadlines that apply to the whole stream.
  //
  // This client follows the Java strategy, except that it does not support
  // `streamIdleTimeout`.

  final http.Client client;

  /// The version of the GAPIC-generated client library (e.g. `0.1.0`),
  /// which will be formatted as `gapic/<version>` in the `x-goog-api-client`
  /// header.
  ///
  /// Set this for client libraries that were generated completely by
  /// automation.
  final String? gapicVersion;

  /// The version of the hand-written client library (e.g. `0.6.4`),
  /// which will be formatted as `gccl/<version>` in the `x-goog-api-client`
  /// header.
  ///
  /// Set this if the client library includes hand-written components.
  final String? gcclVersion;

  /// Creates a `ServiceClient` using [client] for transport.
  ///
  /// The provided [http.Client] must be configured to provide whatever
  /// authentication is required by the API being accessed. You can do that
  /// using
  /// [`package:googleapis_auth`](https://pub.dev/packages/googleapis_auth).
  ///
  /// If [gapicVersion] is set, `gapic/<version>` is included in the
  /// `x-goog-api-client` header.
  ///
  /// If [gcclVersion] is set, `gccl/<version>` is included in the
  /// `x-goog-api-client` header.
  ///
  /// Both [gapicVersion] and [gcclVersion] should be set if the library
  /// includes both automatically-generated and hand-written components.
  /// For example, `package:google_cloud_firestore` (hand-written) wraps
  /// `package:google_cloud_firestore_v1` (generated).
  ServiceClient({required this.client, this.gapicVersion, this.gcclVersion});

  /// The `x-goog-api-client` header value sent with every request.
  String get clientHeader {
    final buffer = StringBuffer(_baseClientName);
    final gapic = gapicVersion?.trim();
    final hasGapic = gapic != null && gapic.isNotEmpty;
    final gccl = gcclVersion?.trim();
    final hasGccl = gccl != null && gccl.isNotEmpty;

    if (hasGapic) {
      buffer.write(' gapic/$gapic');
    }

    if (hasGccl) {
      buffer.write(' gccl/$gccl');
    }

    return buffer.toString();
  }

  /// The `User-Agent` header value sent with every request, or `null` if none
  /// should be sent.
  ///
  /// On the Dart VM, returns `'gcloud-dart/<gcclVersion>'` when
  /// [gcclVersion] is non-empty; otherwise returns `null`.
  String? get userAgentHeader {
    final gccl = gcclVersion?.trim();
    if (gccl == null || gccl.isEmpty) return null;
    return userAgentForClient(gccl);
  }

  Future<Map<String, dynamic>> get(
    Uri url, {
    RetryRunner retry = noRetry,
    Duration? timeout,
  }) => _makeRequest(url, 'GET', retry: retry, timeout: timeout);

  Stream<Map<String, dynamic>> getStreaming(
    Uri url, {
    required bool enableSse,
    RetryRunner retry = noRetry,
    Duration? timeout,
    Duration? streamWaitTimeout,
  }) => _makeStreamingRequest(
    url,
    'GET',
    enableSse: enableSse,
    retry: retry,
    timeout: timeout,
    streamWaitTimeout: streamWaitTimeout,
  );

  Future<Map<String, dynamic>> delete(
    Uri url, {
    RetryRunner retry = noRetry,
    Duration? timeout,
  }) => _makeRequest(url, 'DELETE', retry: retry, timeout: timeout);

  Stream<Map<String, dynamic>> deleteStreaming(
    Uri url, {
    required bool enableSse,
    RetryRunner retry = noRetry,
    Duration? timeout,
    Duration? streamWaitTimeout,
  }) => _makeStreamingRequest(
    url,
    'DELETE',
    enableSse: enableSse,
    retry: retry,
    timeout: timeout,
    streamWaitTimeout: streamWaitTimeout,
  );

  Future<Map<String, dynamic>> patch(
    Uri url, {
    JsonEncodable? body,
    RetryRunner retry = noRetry,
    Duration? timeout,
  }) => _makeRequest(url, 'PATCH', body: body, retry: retry, timeout: timeout);

  Stream<Map<String, dynamic>> patchStreaming(
    Uri url, {
    required bool enableSse,
    JsonEncodable? body,
    RetryRunner retry = noRetry,
    Duration? timeout,
    Duration? streamWaitTimeout,
  }) => _makeStreamingRequest(
    url,
    'PATCH',
    body: body,
    enableSse: enableSse,
    retry: retry,
    timeout: timeout,
    streamWaitTimeout: streamWaitTimeout,
  );

  Future<Map<String, dynamic>> post(
    Uri url, {
    JsonEncodable? body,
    RetryRunner retry = noRetry,
    Duration? timeout,
  }) => _makeRequest(url, 'POST', body: body, retry: retry, timeout: timeout);

  Stream<Map<String, dynamic>> postStreaming(
    Uri url, {
    required bool enableSse,
    JsonEncodable? body,
    RetryRunner retry = noRetry,
    Duration? timeout,
    Duration? streamWaitTimeout,
  }) => _makeStreamingRequest(
    url,
    'POST',
    body: body,
    enableSse: enableSse,
    retry: retry,
    timeout: timeout,
    streamWaitTimeout: streamWaitTimeout,
  );

  Future<Map<String, dynamic>> put(
    Uri url, {
    JsonEncodable? body,
    RetryRunner retry = noRetry,
    Duration? timeout,
  }) => _makeRequest(url, 'PUT', body: body, retry: retry, timeout: timeout);

  Stream<Map<String, dynamic>> putStreaming(
    Uri url, {
    required bool enableSse,
    JsonEncodable? body,
    RetryRunner retry = noRetry,
    Duration? timeout,
    Duration? streamWaitTimeout,
  }) => _makeStreamingRequest(
    url,
    'PUT',
    body: body,
    enableSse: enableSse,
    retry: retry,
    timeout: timeout,
    streamWaitTimeout: streamWaitTimeout,
  );

  /// Closes the client and cleans up any resources associated with it.
  ///
  /// Once [close] is called, no other methods should be called.
  void close() => client.close();

  /// Sends a single request, throwing a [ServiceException] if the response
  /// does not have a 2xx status code.
  Future<http.StreamedResponse> _send(
    Uri url,
    String method,
    String? encodedBody,
    _Attempt attempt,
  ) async {
    // `send` finalizes the request, so every attempt needs a new one.
    final request = http.Request(method, url);
    if (encodedBody != null) {
      request.body = encodedBody;
    }
    request.headers.addAll({
      _clientKey: clientHeader,
      _userAgentKey: ?userAgentHeader,
      if (encodedBody != null) _contentTypeKey: _typeJson,
    });

    final response = await attempt.send(client.send(request));
    final statusOK = response.statusCode >= 200 && response.statusCode < 300;
    if (!statusOK) {
      String? responseBody;
      try {
        responseBody = await attempt.readString(response.stream);
      } on FormatException {
        // The response body is not valid UTF-8.
      }
      throw ServiceException.fromHttpResponse(response, responseBody);
    }
    return response;
  }

  Future<Map<String, dynamic>> _makeRequest(
    Uri url,
    String method, {
    JsonEncodable? body,
    required RetryRunner retry,
    required Duration? timeout,
  }) {
    _checkTimeout(timeout, 'timeout');
    final encodedBody = body?._asEncodedJson;
    return retry.run(() async {
      final attempt = _Attempt(url, timeout: timeout);
      try {
        final response = await _send(url, method, encodedBody, attempt);
        final responseBody = await attempt.readString(response.stream);
        return responseBody.isEmpty
            ? {}
            : jsonDecode(responseBody) as Map<String, dynamic>;
      } finally {
        attempt.stop();
      }
    });
  }

  /// Make a request that streams its results using
  /// [Server-sent events](https://html.spec.whatwg.org/multipage/server-sent-events.html).
  ///
  /// NOTE: most Google APIs do not support Server-sent events.
  Stream<Map<String, dynamic>> _makeStreamingRequest(
    Uri url,
    String method, {
    JsonEncodable? body,
    required bool enableSse,
    required RetryRunner retry,
    required Duration? timeout,
    required Duration? streamWaitTimeout,
  }) {
    _checkTimeout(timeout, 'timeout');
    _checkTimeout(streamWaitTimeout, 'streamWaitTimeout');
    final requestUrl = enableSse ? _makeUrlStreaming(url) : url;
    // Encoded when the stream is listened to, like everything else.
    late final encodedBody = body?._asEncodedJson;
    return _retryingStream(
      retry,
      requestUrl,
      timeout: timeout,
      stallTimeout: streamWaitTimeout,
      start: (attempt) async {
        final response = await _send(requestUrl, method, encodedBody, attempt);
        switch (_mimeType(response)) {
          case 'application/json':
            // The server responded with a non-streaming response, which should
            // be a list of JSON objects. The whole body is read as part of the
            // attempt, so a failure while reading it can be retried.
            final responseBody = await attempt.readString(response.stream);
            final json = (jsonDecode(responseBody) as List)
                .cast<Map<String, dynamic>>();
            return Stream.fromIterable(json);
          case 'text/event-stream':
            // The server responded with an event stream, which is what we
            // expect. Events reach the caller as they arrive, so failures after
            // this point are not retried.
            return _decodeEvents(response);
          default:
            _cancelResponse(response).ignoreExceptions();
            throw ServiceException(
              'Unsupported content type: ${response.headers['content-type']}',
              statusCode: response.statusCode,
            );
        }
      },
    );
  }

  /// The MIME type of [response], or `null` if its `content-type` header is
  /// missing or malformed.
  static String? _mimeType(http.BaseResponse response) {
    final contentType = response.headers['content-type'];
    if (contentType == null) return null;
    try {
      return http.MediaType.parse(contentType).mimeType;
    } on FormatException {
      return null;
    }
  }

  static void _checkTimeout(Duration? timeout, String name) {
    if (timeout != null && timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, name, 'must be positive');
    }
  }

  static Stream<Map<String, dynamic>> _decodeEvents(
    http.StreamedResponse response,
  ) {
    // Google APIs only generate "data" events.
    // The SSE specification does not require a space after the colon but
    // Google APIs always generate one.
    const dataPrefix = 'data: ';
    return response.stream
        .toStringStream()
        .transform(const LineSplitter())
        .where((line) => line.startsWith(dataPrefix))
        .map(
          (line) =>
              jsonDecode(line.substring(dataPrefix.length))
                  as Map<String, dynamic>,
        );
  }

  static Uri _makeUrlStreaming(Uri url) {
    final query = Map.of(url.queryParameters);
    query['alt'] = 'sse';
    return url.replace(queryParameters: query);
  }
}

/// The messages of the stream that [start] returns, where [start] is retried
/// as [retry] decides.
///
/// This is like `yield* await retry.run(start)`, except that the returned
/// stream can be paused and cancelled at any time, and that every call to
/// [start] is an [_Attempt] that is limited by [timeout] and [stallTimeout].
///
/// The messages are read as part of the attempt that returned them, so its
/// limits apply to them too. A failure while they are read is not retried,
/// because some of them may have reached the listener already.
Stream<T> _retryingStream<T>(
  RetryRunner retry,
  Uri url, {
  required Duration? timeout,
  required Duration? stallTimeout,
  required Future<Stream<T>> Function(_Attempt attempt) start,
}) {
  final controller = StreamController<T>();
  // How long to wait before each attempt after the first.
  late final Iterator<Duration> delays;
  // The attempt that the listener is waiting for, if any.
  _Attempt? attempt;
  // Waits to make the next attempt, if any.
  Timer? retryTimer;

  void startAttempt() {
    final current = attempt = _Attempt(
      url,
      timeout: timeout,
      stallTimeout: stallTimeout,
      isPaused: controller.isPaused,
    );
    unawaited(
      start(current).then(
        (messages) {
          if (!identical(current, attempt)) {
            // The listener cancelled, so nothing will read `messages`.
            messages.listen(null).cancel().ignoreExceptions();
            return;
          }
          unawaited(
            controller
                .addStream(current.limit(messages), cancelOnError: true)
                .whenComplete(controller.close),
          );
        },
        onError: (Object error, StackTrace stackTrace) {
          current.stop();
          if (!identical(current, attempt)) {
            // The listener cancelled, so there is nobody to report an
            // `Exception` to. An `Error` is a bug, so it is still reported, as
            // an uncaught error.
            if (error is! Exception) {
              Error.throwWithStackTrace(error, stackTrace);
            }
          } else if (error is Exception &&
              retry.isRetryable(error) &&
              delays.moveNext()) {
            attempt = null;
            // `retry.run` isn't used because its wait between attempts can't be
            // stopped, so a timer would outlive a cancelled subscription.
            retryTimer = Timer(delays.current, startAttempt);
          } else {
            controller.addError(error, stackTrace);
            unawaited(controller.close());
          }
        },
      ),
    );
  }

  controller.onListen = () {
    controller
      ..onPause = (() => attempt?.pause())
      ..onResume = (() => attempt?.resume())
      ..onCancel = () {
        retryTimer?.cancel();
        final current = attempt;
        attempt = null;
        return current?.cancel();
      };
    delays = retry.delays().iterator;
    startAttempt();
  };
  return controller.stream;
}

/// One attempt at a request, which fails if it takes too long.
///
/// The attempt fails with a [TimeoutException] if it isn't over within
/// `timeout`, or if the server shows no sign of life for `stallTimeout`:
/// first by starting its response, and then with each event of the stream
/// that [limit] returns. Time that the attempt is paused for doesn't count
/// towards `stallTimeout`.
///
/// The attempt is over when the stream that [limit] returns ends, or when
/// [stop] is called.
final class _Attempt {
  final Uri _url;
  final Duration? _stallTimeout;

  Timer? _deadlineTimer;
  Timer? _stallTimer;

  /// Whether whoever reads the results of this attempt has paused.
  bool _isPaused;

  /// Whether the response has started.
  var _hasResponse = false;

  /// Whether this attempt is over.
  var _isOver = false;

  /// Why this attempt was abandoned, if it was.
  Exception? _failure;

  /// Fails, with [_failure], when this attempt is abandoned.
  final _abandoned = Completer<Never>();

  /// Ends the stream that [limit] returned early, while that stream is read.
  Future<void>? Function(Exception failure)? _endStream;

  _Attempt(
    this._url, {
    required Duration? timeout,
    Duration? stallTimeout,
    bool isPaused = false,
  }) : _stallTimeout = stallTimeout,
       _isPaused = isPaused {
    // Nothing waits for `_abandoned` once the response has started.
    _abandoned.future.ignore();
    if (timeout != null) {
      _deadlineTimer = Timer(
        timeout,
        () => _timeOut(
          _hasResponse
              ? 'Request to $_url did not complete'
              : 'Request to $_url did not return any data',
          timeout,
        ),
      );
    }
    _restartStallTimer();
  }

  /// Waits for the response to the request that [pending] completes with.
  Future<http.StreamedResponse> send(
    Future<http.StreamedResponse> pending,
  ) async {
    try {
      final response = await Future.any([pending, _abandoned.future]);
      // This attempt may have been abandoned just as the response started.
      if (_failure case final failure?) throw failure;
      _hasResponse = true;
      _restartStallTimer();
      return response;
    } catch (e) {
      // TODO: Use `http.Abortable` when it is widely available. In practice,
      // `client` will almost always be a `package:googleapis_auth` wrapper,
      // which does not forward `Abortable.abortTrigger` to the underlying
      // client.
      //
      // Abandoning this attempt doesn't abort its request, so the response
      // may start anyway. Nothing will read it, so it is cancelled.
      if (identical(e, _failure)) {
        pending.then(_cancelResponse).ignoreExceptions();
      }
      rethrow;
    }
  }

  /// Reads all of [bytes], the body of the response, as a string.
  Future<String> readString(Stream<List<int>> bytes) =>
      // An empty chunk doesn't show that the server is still sending the body.
      utf8.decodeStream(limit(bytes.where((chunk) => chunk.isNotEmpty)));

  /// [stream], which is read from the response, as a stream that ends with an
  /// error as soon as this attempt is abandoned.
  ///
  /// This attempt is over when the returned stream ends.
  Stream<T> limit<T>(Stream<T> stream) {
    final controller = StreamController<T>();
    controller.onListen = () {
      StreamSubscription<T>? subscription;

      // Ends the returned stream, with `error` if there is one, and stops
      // listening to `stream`.
      Future<void>? end([Object? error, StackTrace? stackTrace]) {
        _endStream = null;
        stop();
        if (error != null) controller.addError(error, stackTrace);
        // `stream` is cancelled below, unless it's done, so `close` need not
        // cancel it.
        controller
          ..onCancel = null
          ..close();
        return subscription?.cancel();
      }

      final source = subscription = stream.listen(
        (event) {
          controller.add(event);
          _restartStallTimer();
        },
        onError: (Object error, StackTrace stackTrace) =>
            end(error, stackTrace)?.ignoreExceptions(),
        onDone: end,
      );
      // `stream` ended as soon as it was listened to, so there is nothing left
      // to end early, pause, resume or cancel.
      if (controller.isClosed) {
        source.cancel().ignoreExceptions();
        return;
      }
      _endStream = end;
      controller
        ..onPause = source.pause
        ..onResume = source.resume
        ..onCancel = () {
          _endStream = null;
          stop();
          return source.cancel();
        };
    };
    return controller.stream;
  }

  /// Stops the clock of `stallTimeout`, because whoever reads the results of
  /// this attempt has paused.
  void pause() {
    _isPaused = true;
    _stallTimer?.cancel();
  }

  /// Restarts the clock of `stallTimeout`, after [pause].
  void resume() {
    _isPaused = false;
    _restartStallTimer();
  }

  /// Abandons this attempt, because nothing waits for its results any more.
  ///
  /// The returned future, if any, completes when the response is cancelled.
  Future<void>? cancel() => _abandon(const _Cancelled());

  /// Ends this attempt, so that it doesn't time out.
  void stop() {
    _isOver = true;
    _deadlineTimer?.cancel();
    _stallTimer?.cancel();
  }

  void _timeOut(String message, Duration duration) =>
      _abandon(TimeoutException(message, duration))?.ignoreExceptions();

  /// Ends this attempt early: fails whatever waits for its results with
  /// [failure], and stops reading the response.
  Future<void>? _abandon(Exception failure) {
    if (_isOver) return null;
    stop();
    _failure = failure;
    _abandoned.completeError(failure);
    return _endStream?.call(failure);
  }

  /// Restarts the clock of `stallTimeout`, because the server showed a sign of
  /// life.
  void _restartStallTimer() {
    final stallTimeout = _stallTimeout;
    if (stallTimeout == null || _isPaused || _isOver) return;
    _stallTimer?.cancel();
    _stallTimer = Timer(
      stallTimeout,
      () => _timeOut(
        _hasResponse
            ? 'No data received from $_url'
            : 'Request to $_url did not return any data',
        stallTimeout,
      ),
    );
  }
}

/// What the operations of an [_Attempt] fail with after [_Attempt.cancel].
final class _Cancelled implements Exception {
  const _Cancelled();
}

/// Cancels [response], which releases its connection.
Future<void> _cancelResponse(http.StreamedResponse response) =>
    response.stream.listen(null).cancel();

extension on JsonEncodable {
  String get _asEncodedJson => jsonEncode(toJson());
}

extension on Future<void> {
  void ignoreExceptions() {
    unawaited(catchError((_) {}, test: (e) => e is Exception));
  }
}
