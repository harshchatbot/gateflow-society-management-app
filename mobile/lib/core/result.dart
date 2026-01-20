import 'app_error.dart';

class Result<T> {
  final T? data;
  final AppError? error;

  bool get isSuccess => data != null && error == null;
  bool get isFailure => error != null;

  Result._({this.data, this.error});

  factory Result.success(T data) => Result._(data: data);
  factory Result.failure(AppError error) => Result._(error: error);
}
