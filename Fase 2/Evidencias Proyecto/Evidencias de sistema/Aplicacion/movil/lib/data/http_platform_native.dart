import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import 'http_platform_interface.dart';

HttpPlatform createHttpPlatform() => NativeHttpPlatform();

class NativeHttpPlatform implements HttpPlatform {
  NativeHttpPlatform({CookieJar? jar}) : jar = jar ?? CookieJar();
  final CookieJar jar;

  @override
  void configure(Dio dio) => dio.interceptors.add(CookieManager(jar));

  @override
  Future<String?> csrfToken(Uri origin) async {
    final cookies = await jar.loadForRequest(origin.resolve('/api/auth/refresh'));
    for (final cookie in cookies) {
      if (cookie.name == 'csrf_token') return cookie.value;
    }
    return null;
  }
}
