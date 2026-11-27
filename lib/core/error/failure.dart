import 'package:equatable/equatable.dart';

/// Base failure class used for handling failures in the data layer
/// & exception to failure mapper
abstract class Failure extends Equatable {
  final String message;
  const Failure(this.message);

  @override
  List<Object?> get props => [message];
}

/// Server failure
class ServerFailure extends Failure {
  const ServerFailure(super.message);
}

/// Network failure
class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

/// Cache failure
class CacheFailure extends Failure {
  const CacheFailure(super.message);
}

/// Authentication failure
class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

/// Validation failure
class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

/// Not found failure
class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message);
}

/// Timeout failure
class TimeoutFailure extends Failure {
  const TimeoutFailure(super.message);
}

/// Unknown failure
class UnknownFailure extends Failure {
  const UnknownFailure(super.message);
}

/// Remote quota / rate limit / storage-full failure (e.g. Google Drive).
class QuotaFailure extends Failure {
  const QuotaFailure(super.message);
}
