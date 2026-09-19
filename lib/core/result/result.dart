import 'app_error.dart';

/// Kontainer hasil operasi domain yang dapat bernilai sukses ([Success]) atau gagal ([Failure]).
///
/// Digunakan oleh repository dan application layer untuk menghindari melempar
/// exception liar yang membingungkan presentation layer.
///
/// Contoh:
/// ```dart
/// final result = await repository.getTask();
/// return result.when(
///   ok: (task) => Text(task.title),
///   err: (error) => Text(error.userMessage),
/// );
/// ```
sealed class Result<T> {
  const Result();

  /// Membuat instans sukses dengan muatan data [data].
  const factory Result.ok(T data) = Success<T>;

  /// Membuat instans kegagalan dengan objek kesalahan [error].
  const factory Result.err(AppError error) = Failure<T>;

  /// `true` jika operasi berhasil.
  bool get isOk => this is Success<T>;

  /// `true` jika operasi gagal.
  bool get isErr => this is Failure<T>;

  /// Mengambil muatan data jika sukses, atau `null` jika operasi gagal.
  T? get dataOrNull => switch (this) {
    Success(:final data) => data,
    Failure() => null,
  };

  /// Mengambil muatan kesalahan jika gagal, atau `null` jika operasi sukses.
  AppError? get errorOrNull => switch (this) {
    Success() => null,
    Failure(:final error) => error,
  };

  /// Melakukan pencocokan pola (exhaustive pattern matching) terhadap hasil operasi.
  R when<R>({
    required R Function(T data) ok,
    required R Function(AppError error) err,
  }) => switch (this) {
    Success(:final data) => ok(data),
    Failure(:final error) => err(error),
  };
}

/// Representasi operasi domain yang berhasil.
final class Success<T> extends Result<T> {
  /// Nilai hasil operasi yang sukses.
  final T data;

  const Success(this.data);

  @override
  String toString() => 'Result.ok(\$data)';
}

/// Representasi operasi domain yang gagal membawa [AppError].
final class Failure<T> extends Result<T> {
  /// Objek kesalahan domain yang terjadi.
  final AppError error;

  const Failure(this.error);

  @override
  String toString() => 'Result.err(\$error)';
}
