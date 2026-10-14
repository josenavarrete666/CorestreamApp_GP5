import 'http_platform_native.dart'
    if (dart.library.js_interop) 'http_platform_web.dart' as implementation;
import 'http_platform_interface.dart';

HttpPlatform createHttpPlatform() => implementation.createHttpPlatform();
