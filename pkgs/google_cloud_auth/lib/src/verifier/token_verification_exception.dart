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

/// Why a token failed verification.
///
/// Callers that need to react differently to different failures, such as
/// re-wrapping them in a domain-specific error type, should switch on this
/// rather than matching on the exception message.
enum TokenVerificationFailure {
  /// The token is not a well-formed JWS.
  malformed,

  /// The token declares an algorithm other than RS256, including `none`.
  unsupportedAlgorithm,

  /// The token has no `kid` header parameter, so no key can be selected.
  missingKeyId,

  /// The token's `kid` is not published by the key endpoint.
  ///
  /// Usually means the signing keys rotated and the token predates them, or
  /// that the token came from a different issuer than expected.
  unknownKeyId,

  /// The signature did not match the public key.
  invalidSignature,

  /// The public keys could not be fetched.
  ///
  /// The token may well be valid; it could not be checked.
  keyUnavailable,

  /// The `iss` claim is missing or not an expected issuer.
  invalidIssuer,

  /// The `aud` claim is missing or not an allowed audience.
  invalidAudience,

  /// The token has no `exp` claim.
  missingExpiration,

  /// The token expired, allowing for the configured clock skew.
  expired,

  /// The `iat` claim is further in the future than the configured clock skew.
  issuedInFuture,
}

/// Exception thrown when a token fails verification.
///
/// This covers both tokens that are structurally or cryptographically invalid
/// and failures to obtain the public keys needed to check them. Callers should
/// not distinguish between the two when deciding whether to accept a request:
/// in either case the token has not been verified. Use [reason] when the
/// distinction matters for reporting.
class TokenVerificationException implements Exception {
  /// Why verification failed.
  final TokenVerificationFailure reason;

  /// The message explaining the failure.
  final String message;

  /// The inner exception that caused this failure, if any.
  final Object? innerException;

  /// The stack trace of the inner exception, if any.
  final StackTrace? innerStackTrace;

  TokenVerificationException(
    this.reason,
    this.message, {
    this.innerException,
    this.innerStackTrace,
  });

  @override
  String toString() => innerException == null
      ? 'TokenVerificationException: $message'
      : 'TokenVerificationException: $message (caused by: $innerException)';
}
