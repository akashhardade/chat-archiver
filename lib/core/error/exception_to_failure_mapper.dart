import 'exceptions.dart';
import 'failure.dart';

/// Maps an AppException to a Failure.
class ExceptionToFailureMapper {
  static Failure map(AppException exception) {
    final message = exception.message ?? 'Something went wrong';

    // --- Network & connectivity ---
    if (exception is NetworkException) {
      return NetworkFailure(message);
    }

    if (exception is TimeoutException) {
      return TimeoutFailure(message);
    }

    // --- Authentication & authorization ---
    if (exception is UnauthorizedException || exception is ForbiddenException) {
      return AuthFailure(message);
    }

    // --- Client & validation errors ---
    if (exception is ValidationException || exception is BadRequestException) {
      return ValidationFailure(message);
    }

    // --- Resource not found ---
    if (exception is NotFoundException) {
      return NotFoundFailure(message);
    }

    // --- Server & rate limiting ---
    if (exception is ServerException ||
        exception is ServiceUnavailableException ||
        exception is TooManyRequestsException) {
      return ServerFailure(message);
    }

    // --- Cache ---
    if (exception is CacheException) {
      return CacheFailure(message);
    }

    // --- Request cancelled ---
    if (exception is RequestCancelledException) {
      return UnknownFailure(message);
    }

    // --- Fallback ---
    return UnknownFailure(message);
  }
}
