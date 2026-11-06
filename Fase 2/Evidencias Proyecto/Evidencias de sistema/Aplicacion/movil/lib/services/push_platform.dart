import 'push_platform_native.dart'
    if (dart.library.js_interop) 'push_platform_web.dart' as implementation;

/// true solo en un dispositivo Android real o emulador (no en web ni en
/// `flutter test`, que corre sobre el sistema anfitrión).
bool get supportsFcm => implementation.supportsFcm;
