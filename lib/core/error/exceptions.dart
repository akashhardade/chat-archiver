// Base exception class used for handling exceptions in dio
// and also used in exception to failure mapper
class AppException implements Exception {
  final String? message;
  final int? statusCode;
  const AppException([this.message, this.statusCode]);

  @override
  String toString() => message ?? 'An error occurred';
}

/// Server-related exceptions
class ServerException extends AppException {
  const ServerException([super.message, super.statusCode]);
}

/// Network-related exceptions
class NetworkException extends AppException {
  const NetworkException([super.message]);
}

/// Cache-related exceptions
class CacheException extends AppException {
  const CacheException([super.message]);
}

/// Authentication exceptions
class UnauthorizedException extends AppException {
  const UnauthorizedException([super.message, super.statusCode]);
}

/// Permission exceptions
class ForbiddenException extends AppException {
  const ForbiddenException([super.message, super.statusCode]);
}

/// Resource not found exceptions
class NotFoundException extends AppException {
  const NotFoundException([super.message, super.statusCode]);
}

/// Bad request exceptions
class BadRequestException extends AppException {
  const BadRequestException([super.message, super.statusCode]);
}

/// Validation exceptions
class ValidationException extends AppException {
  const ValidationException([super.message, super.statusCode]);
}

/// Request cancelled exceptions
class RequestCancelledException extends AppException {
  const RequestCancelledException([super.message]);
}

/// Too many requests exceptions
class TooManyRequestsException extends AppException {
  const TooManyRequestsException([super.message, super.statusCode]);
}

/// Service unavailable exceptions
class ServiceUnavailableException extends AppException {
  const ServiceUnavailableException([super.message, super.statusCode]);
}

/// Timeout exceptions
class TimeoutException extends AppException {
  const TimeoutException([super.message, super.statusCode]);
}
