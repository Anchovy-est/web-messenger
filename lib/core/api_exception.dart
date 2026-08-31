import 'package:dio/dio.dart';

/// One field-level error from the backend's `error.details` array.
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

/// Typed wrapper around the backend's error shape
/// `{ error: { code, message, details? } }`.
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

  /// Structured error details for codes that aren't field errors (e.g.
  /// `ALREADY_IN_CHAT` carries `{ chatId }`).
  final Map<String, dynamic>? details;

  /// Builds an [ApiException] from a [DioException], with a generic
  /// network message when there's no response at all.
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

    // No response reached us — pick the message that actually fits.
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

  /// The backend's error message for one field, if it reported one.
  String? messageForField(String field) {
    for (final error in fieldErrors) {
      if (error.field == field) return error.message;
    }
    return null;
  }

  @override
  String toString() => message;
}

/// The message to show for any caught error — an [ApiException]'s own
/// message, or a generic fallback otherwise.
String errorMessageFor(Object error) =>
    error is ApiException ? error.message : 'Something went wrong.';
