import 'package:dio/dio.dart';

enum ApiErrorKind { network, session, permission, validation, rateLimit, server, contract, operation, superseded }

class ApiError implements Exception {
  const ApiError(this.kind, this.message, {this.status, this.retryAfter});
  final ApiErrorKind kind;
  final String message;
  final int? status;
  final Duration? retryAfter;

  factory ApiError.fromDio(DioException error) {
    final status = error.response?.statusCode;
    if (status == null) {
      return const ApiError(ApiErrorKind.network, 'No se pudo conectar. Comprueba la conexión y vuelve a intentar.');
    }
    final data = error.response?.data;
    final detail = data is Map ? data['detail'] : null;
    final message = detail is String ? detail : detail is List
        ? detail.map((e) => e is Map ? '${e['loc']}: ${e['msg']}' : 'Datos inválidos').join('\n')
        : 'La operación no pudo completarse (HTTP $status).';
    final seconds = int.tryParse(error.response?.headers.value('retry-after') ?? '');
    return ApiError(switch (status) {
      401 => ApiErrorKind.session,
      403 => ApiErrorKind.permission,
      422 => ApiErrorKind.validation,
      429 => ApiErrorKind.rateLimit,
      >= 500 => ApiErrorKind.server,
      _ => ApiErrorKind.operation,
    }, message, status: status, retryAfter: seconds == null ? null : Duration(seconds: seconds));
  }

  @override
  String toString() => message;
}
