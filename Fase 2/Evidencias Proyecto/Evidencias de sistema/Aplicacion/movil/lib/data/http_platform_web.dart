import 'package:dio/browser.dart';
import 'package:dio/dio.dart';
import 'package:web/web.dart' as web;

import 'http_platform_interface.dart';

HttpPlatform createHttpPlatform() => WebHttpPlatform();

class WebHttpPlatform implements HttpPlatform {
  @override
  void configure(Dio dio) {
    dio.httpClientAdapter = BrowserHttpClientAdapter(withCredentials: true);
  }

  @override
  Future<String?> csrfToken(Uri origin) async {
    if (web.window.location.hostname != origin.host) return null;
    for (final part in web.document.cookie.split(';')) {
      final cookie = part.trim();
      if (cookie.startsWith('csrf_token=')) return cookie.substring('csrf_token='.length);
    }
    return null;
  }
}
