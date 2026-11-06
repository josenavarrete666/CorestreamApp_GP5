import 'package:dio/dio.dart';

abstract class HttpPlatform {
  void configure(Dio dio);
  Future<String?> csrfToken(Uri origin);
}
