import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers.dart';

/// Tipografía del logotipo (assets/fonts, SIL OFL 1.1).
const brandFontFamily = 'Manrope';

/// Logotipo de CoreStream de las pantallas de ingreso: emblema en el
/// degradado propio de CoreStream (azul→verde) y el nombre en Manrope
/// ExtraBold, con «Stream» en el mismo degradado.
class CoreStreamBrand extends StatelessWidget {
  const CoreStreamBrand({super.key});

  static const _blue = Color(0xFF4C8DFF);
  static const _green = Color(0xFF2FBF71);
  static const _gradient = LinearGradient(
    colors: [_blue, _green],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  Widget build(BuildContext context) {
    final c = cs(context);
    TextStyle wordmark(double weight) => TextStyle(
      fontFamily: brandFontFamily,
      fontSize: 34,
      fontWeight: FontWeight.w800,
      fontVariations: [FontVariation.weight(weight)],
      letterSpacing: -0.8,
      height: 1.1,
    );
    return Semantics(
      header: true,
      label: 'CoreStream',
      excludeSemantics: true,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: _gradient,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [BoxShadow(
              color: _blue.withValues(alpha: 0.4),
              blurRadius: 28,
              offset: const Offset(0, 12),
            )],
          ),
          child: Text('C', style: wordmark(800).copyWith(color: Colors.white, fontSize: 40, height: 1)),
        ),
        const SizedBox(height: 18),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: 'Core', style: wordmark(800).copyWith(color: c.ink)),
            TextSpan(text: 'Stream', style: wordmark(800).copyWith(
              foreground: Paint()..shader = _gradient.createShader(const Rect.fromLTWH(0, 0, 120, 40)),
            )),
          ]),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }
}

/// Crédito discreto del distribuidor (Alloxentric) al pie de las pantallas
/// de ingreso. En tema oscuro usa la versión con el texto claro del logo.
class AlloxentricCredit extends ConsumerWidget {
  const AlloxentricCredit({super.key});

  static const logoAsset = 'assets/branding/alloxentric_logo.png';
  static const logoAssetLight = 'assets/branding/alloxentric_logo_light.png';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = cs(context);
    final s = ref.watch(stringsProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: '${s('distributed_by')} Alloxentric',
      excludeSemantics: true,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(s('distributed_by').toUpperCase(), textAlign: TextAlign.center, style: TextStyle(
          color: c.faint, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.4,
        )),
        const SizedBox(height: 8),
        Image.asset(
          dark ? logoAssetLight : logoAsset,
          height: 20,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ]),
    );
  }
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
                const SizedBox(height: 10),
                Text(subtitle, textAlign: TextAlign.center,
                  style: TextStyle(color: c.mut, fontSize: 13.5, height: 1.5)),
                const SizedBox(height: 26),
                child,
                if (footer != null) ...[
                  const SizedBox(height: 26),
                  Text(footer!, textAlign: TextAlign.center,
                    style: TextStyle(color: c.mut, fontSize: 11.5, height: 1.5)),
                ],
                const SizedBox(height: 32),
                const AlloxentricCredit(key: Key('auth_distributor')),
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
