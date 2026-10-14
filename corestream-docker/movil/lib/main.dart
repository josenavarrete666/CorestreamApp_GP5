import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme.dart';
import 'providers.dart';
import 'ui/home_shell.dart';
import 'ui/login_screen.dart';
import 'ui/change_password_screen.dart';
import 'ui/auth_layout.dart';
import 'models/session_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const CoreStreamApp(),
  ));
}

class CoreStreamApp extends ConsumerWidget {
  const CoreStreamApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = ref.watch(darkModeProvider);
    final user = ref.watch(authProvider);
    final state = ref.watch(authControllerProvider);
    final ws = ref.watch(apiModeProvider) ? ref.watch(apiWebsocketProvider) : null;
    Widget home;
    if (state.phase == SessionPhase.restoring || state.phase == SessionPhase.signingOut) {
      final s = ref.watch(stringsProvider);
      final message = s(state.phase == SessionPhase.restoring ? 'restore_session' : 'closing_session');
      home = AuthLayout(subtitle: message, child: Center(child: CircularProgressIndicator(semanticsLabel: message)));
    } else if (state.phase == SessionPhase.passwordRequired || (state.phase == SessionPhase.signingIn && state.profile != null)) {
      home = const ChangePasswordScreen();
    } else if (user == null) {
      home = const LoginScreen();
    } else {
      home = HomeShell(key: ValueKey(user.id));
    }

    return MaterialApp(
      key: ValueKey(user?.id),
      title: 'CoreStream',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => Listener(onPointerDown: (_) => ws?.activity(),
          onPointerSignal: (_) => ws?.activity(), child: child!),
      home: home,
    );
  }
}
