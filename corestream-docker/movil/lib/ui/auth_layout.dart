import 'package:flutter/material.dart';

import '../core/theme.dart';

class CoreStreamBrand extends StatelessWidget {
  const CoreStreamBrand({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4C8DFF), Color(0xFF2FBF71)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
          color: const Color(0xFF4C8DFF).withValues(alpha: 0.45),
          blurRadius: 26,
          offset: const Offset(0, 12),
        )],
      ),
      child: const Text('C', style: TextStyle(
        color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800,
      )),
    ),
  );
}

class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.subtitle, required this.child, this.footer});
  final String subtitle;
  final Widget child;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final c = cs(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const CoreStreamBrand(key: Key('auth_brand')),
                const SizedBox(height: 16),
                Text('CoreStream', textAlign: TextAlign.center, style: TextStyle(
                  color: c.ink, fontSize: 27, fontWeight: FontWeight.w800, letterSpacing: -0.5,
                )),
                const SizedBox(height: 8),
                Text(subtitle, textAlign: TextAlign.center,
                  style: TextStyle(color: c.mut, fontSize: 13.5, height: 1.5)),
                const SizedBox(height: 26),
                child,
                if (footer != null) ...[
                  const SizedBox(height: 26),
                  Text(footer!, textAlign: TextAlign.center,
                    style: TextStyle(color: c.mut, fontSize: 11.5, height: 1.5)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthNotice extends StatelessWidget {
  const AuthNotice(this.message, {super.key, this.error = false, this.confirmed = false});
  final String message;
  final bool error;
  final bool confirmed;

  @override
  Widget build(BuildContext context) {
    final c = cs(context);
    final color = error ? c.red : confirmed ? c.green : c.mut;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: error ? c.red.withValues(alpha: 0.5) : c.line),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ExcludeSemantics(child: Icon(error ? Icons.error_outline : confirmed ? Icons.check_circle_outline : Icons.info_outline,
            size: 20, color: color)),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: color, fontSize: 13, height: 1.5))),
        ]),
      ),
    );
  }
}
