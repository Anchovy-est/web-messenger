import 'package:dio/dio.dart';

/// One field-level error from the backend's `error.details` array
/// (see backend/src/middleware/validate.js).
class ApiFieldError {
  const ApiFieldError({required this.field, required this.message});

  final String field;
  final String message;

  factory ApiFieldError.fromJson(Map<String, dynamic> json) {
    return ApiFieldError(
      field: json['field'] as String? ?? '',
      message: json['message'] as String? ?? '',
    );
  }
}

/// Typed wrapper around the backend's uniform error shape
/// `{ error: { code, message, details? } }` (see
/// backend/src/middleware/errorHandler.js), so UI code can branch on
/// [code] or read [fieldErrors] instead of parsing raw Dio errors.
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.fieldErrors = const [],
    this.details,
  });

  final int? statusCode;
  final String code;
  final String message;
  final List<ApiFieldError> fieldErrors;

  /// The raw `error.details` payload for error codes that carry
  /// structured (non-field-error) data — e.g. invitations'
  /// `ALREADY_IN_CHAT` includes `{ chatId }` so the UI can navigate
  /// straight there instead of just showing an error. Null whenever
  /// `details` was a field-error list (see [fieldErrors] instead) or
  /// absent entirely.
  final Map<String, dynamic>? details;

  /// Builds an [ApiException] from any [DioException], falling back to a
  /// generic network-error message when the response doesn't match the
  /// backend's expected error shape (e.g. no connection at all).
  factory ApiException.fromDioException(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic> && data['error'] is Map<String, dynamic>) {
      final error = data['error'] as Map<String, dynamic>;
      final rawDetails = error['details'];
      final fieldErrors = rawDetails is List
          ? rawDetails
                .whereType<Map<String, dynamic>>()
                .map(ApiFieldError.fromJson)
                .toList()
          : <ApiFieldError>[];
      return ApiException(
        statusCode: e.response?.statusCode,
        code: error['code'] as String? ?? 'UNKNOWN_ERROR',
        message: error['message'] as String? ?? 'Something went wrong.',
        fieldErrors: fieldErrors,
        details: rawDetails is Map<String, dynamic> ? rawDetails : null,
      );
    }

    // No response reached us at all — distinguish *why* so the message is
    // actually actionable instead of one generic "something's wrong" for
    // every non-response failure (a slow server times out very
    // differently from no network at all, and a cancelled request isn't
    // really a failure the user needs to see).
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ApiException(
          statusCode: null,
          code: 'TIMEOUT',
          message: 'The request timed out. Please try again.',
        );
      case DioExceptionType.cancel:
        return const ApiException(
          statusCode: null,
          code: 'CANCELLED',
          message: 'The request was cancelled.',
        );
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
      case DioExceptionType.badResponse:
      default:
        return const ApiException(
          statusCode: null,
          code: 'NETWORK_ERROR',
          message:
              'Could not reach the server. Check your connection and try again.',
        );
    }
  }

  /// Convenience: the message for a specific field, if the backend
  /// reported one (e.g. show it inline under a form field).
  String? messageForField(String field) {
    for (final error in fieldErrors) {
      if (error.field == field) return error.message;
    }
    return null;
  }

  @override
  String toString() => message;
}
