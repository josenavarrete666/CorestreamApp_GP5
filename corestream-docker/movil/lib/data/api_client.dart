import 'package:dio/dio.dart';

import '../core/config.dart';
import '../models/api_models.dart';
import 'api_error.dart';
import 'http_platform.dart';
import 'http_platform_interface.dart';

class ApiClient {
  ApiClient(String origin, {Dio? dio, HttpPlatform? platform})
      : origin = Uri.parse(AppConfig.validateOrigin(origin)),
        dio = dio ?? Dio(), platform = platform ?? createHttpPlatform() {
    this.dio.options = BaseOptions(baseUrl: this.origin.origin,
        connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 20));
    this.platform.configure(this.dio);
  }
  final Uri origin;
  final Dio dio;
  final HttpPlatform platform;
  String? _access;
  int _generation = 0;
  bool _enabled = false;
  Future<ApiToken>? _refreshing;
  Future<ApiToken>? _loggingIn;
  void Function(ApiError)? onSessionLost;
  void Function()? onPasswordRequired;
  bool _passwordRequired = false;

  int get sessionGeneration => _generation;

  void beginSession() { _generation++; _access = null; _enabled = true; _passwordRequired = false; }
  void abandonSession() { _generation++; _access = null; _enabled = false; _passwordRequired = false; }

  Future<ApiToken> login(String email, String password) {
    if (_loggingIn != null) return _loggingIn!;
    beginSession();
    return _loggingIn = _login(email, password).whenComplete(() => _loggingIn = null);
  }

  Future<ApiToken> _login(String email, String password) async {
    final generation = _generation;
    final token = ApiToken.fromJson(await _send('/api/auth/login', method: 'POST',
        body: {'email': email.trim().toLowerCase(), 'password': password}));
    _check(generation, protected: false);
    _access = token.access;
    _passwordRequired = token.mustChangePassword;
    return token;
  }

  void _check(int generation, {bool protected = true}) {
    if (generation != _generation || (protected && !_enabled)) {
      throw const ApiError(ApiErrorKind.superseded, 'La sesión cambió.');
    }
  }

  Future<Object?> _send(String path, {String method = 'GET', Object? body,
      Map<String, dynamic>? query, String? bearer, String? csrf}) async {
    try {
      return (await dio.request<Object?>(path, data: body, queryParameters: query,
          options: Options(method: method, headers: {
            if (bearer != null) 'Authorization': 'Bearer $bearer',
            if (csrf != null) 'X-CSRF-Token': csrf,
          }))).data;
    } on DioException catch (error) { throw ApiError.fromDio(error); }
  }

  Future<ApiToken> refresh() {
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<ApiToken> _refresh() async {
    final generation = _generation;
    final csrf = await platform.csrfToken(origin);
    if (csrf == null || csrf.isEmpty) {
      throw const ApiError(ApiErrorKind.session, 'Inicia sesión para continuar.', status: 401);
    }
    final token = ApiToken.fromJson(await _send('/api/auth/refresh', method: 'POST', csrf: csrf));
    _check(generation, protected: false);
    _access = token.access;
    _passwordRequired = token.mustChangePassword;
    if (_passwordRequired) onPasswordRequired?.call();
    return token;
  }

  Future<Object?> request(String path, {String method = 'GET', Object? body,
      Map<String, dynamic>? query}) async {
    final generation = _generation;
    _check(generation);
    if (_passwordRequired && !{'/api/auth/me', '/api/auth/change-password'}.contains(path)) {
      throw const ApiError(ApiErrorKind.session, 'Actualiza tu contraseña para continuar.');
    }
    final access = _access;
    try {
      final value = await _send(path, method: method, body: body, query: query, bearer: access);
      _check(generation);
      if (_passwordRequired && !{'/api/auth/me', '/api/auth/change-password'}.contains(path)) {
        throw const ApiError(ApiErrorKind.session, 'Actualiza tu contraseña para continuar.');
      }
      return value;
    } on ApiError catch (error) {
      _check(generation);
      if (error.status != 401) rethrow;
      try {
        if (_access == access) await refresh();
      } on ApiError catch (failure) {
        _check(generation);
        if (failure.status == 401 || failure.status == 403) onSessionLost?.call(failure);
        rethrow;
      }
      _check(generation);
      if (_passwordRequired && !{'/api/auth/me', '/api/auth/change-password'}.contains(path)) {
        throw const ApiError(ApiErrorKind.session, 'Actualiza tu contraseña para continuar.');
      }
      try {
        final result = await _send(path, method: method, body: body, query: query, bearer: _access);
        _check(generation);
        if (_passwordRequired && !{'/api/auth/me', '/api/auth/change-password'}.contains(path)) {
          throw const ApiError(ApiErrorKind.session, 'Actualiza tu contraseña para continuar.');
        }
        return result;
      } on ApiError catch (failure) {
        _check(generation);
        if (failure.status == 401) onSessionLost?.call(failure);
        rethrow;
      }
    }
  }

  Future<bool> logout() async {
    _enabled = false;
    try {
      // Let in-flight cookie rotation settle before the final cookie deletion.
      if (_loggingIn != null) { try { await _loggingIn; } on ApiError { /* retry below */ } }
      if (_refreshing != null) { try { await _refreshing; } on ApiError { /* retry below */ } }
      try {
        await _send('/api/auth/logout', method: 'POST', bearer: _access);
      } on ApiError catch (error) {
        if (error.status != 401) rethrow;
        try { await refresh(); } on ApiError catch (refreshError) {
          if (refreshError.status == 401) return false;
          rethrow;
        }
        await _send('/api/auth/logout', method: 'POST', bearer: _access);
      }
      return true;
    } finally { abandonSession(); }
  }

  void dispose() { abandonSession(); dio.close(force: true); }
}
