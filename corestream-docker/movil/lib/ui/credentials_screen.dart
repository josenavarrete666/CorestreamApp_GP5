import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/session_state.dart';
import '../providers.dart';
import 'auth_layout.dart';

class CredentialsScreen extends ConsumerStatefulWidget {
  const CredentialsScreen({super.key});
  @override
  ConsumerState<CredentialsScreen> createState() => _CredentialsScreenState();
}

class _CredentialsScreenState extends ConsumerState<CredentialsScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  int _retrySeconds = 0;
  bool get _cooldown => _retrySeconds > 0;
  Timer? _timer;

  Future<void> _submit() async {
    if (_cooldown || ref.read(authControllerProvider).busy || !_form.currentState!.validate()) return;
    await ref.read(authControllerProvider.notifier).login(_email.text, _password.text);
    if (!mounted) return;
    final state = ref.read(authControllerProvider);
    if (state.phase == SessionPhase.authenticated || state.phase == SessionPhase.passwordRequired) _password.clear();
    if (state.error?.status == 429) {
      _timer?.cancel();
      final delay = state.error?.retryAfter ?? const Duration(seconds: 30);
      final seconds = (delay.inMilliseconds / 1000).ceil();
      setState(() => _retrySeconds = seconds < 1 ? 1 : seconds);
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) { timer.cancel(); return; }
        setState(() => _retrySeconds--);
        if (_retrySeconds == 0) timer.cancel();
      });
    }
  }

  @override
  void dispose() { _timer?.cancel(); _email.dispose(); _password.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final state = ref.watch(authControllerProvider);
    final pending = state.phase == SessionPhase.logoutPending;
    return AuthLayout(
      subtitle: s('api_login_sub'),
      footer: s('api_capabilities'),
      child: AutofillGroup(child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (pending) ...[
            AuthNotice(s('logout_pending'), key: const Key('logout_pending')),
            const SizedBox(height: 12),
            FilledButton(onPressed: state.busy ? null : () => ref.read(authControllerProvider.notifier).resolvePendingLogout(), child: Text(s('finish_logout'))),
          ] else ...[
            TextFormField(key: const Key('login_email'), controller: _email,
              enabled: !state.busy, keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.username], textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: s('email'), prefixIcon: const Icon(Icons.email_outlined)),
              validator: (value) => value != null && RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim()) ? null : s('email_invalid')),
            const SizedBox(height: 16),
            TextFormField(key: const Key('login_password'), controller: _password,
              enabled: !state.busy, obscureText: _obscure, autofillHints: const [AutofillHints.password],
              autocorrect: false, enableSuggestions: false, textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(labelText: s('password'), prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(tooltip: s(_obscure ? 'show_password' : 'hide_password'),
                   onPressed: state.busy ? null : () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined))),
              validator: (value) => value == null || value.isEmpty ? s('required') : null),
            const SizedBox(height: 24),
            FilledButton(key: const Key('login_submit'), onPressed: state.busy || _cooldown ? null : _submit,
               child: state.busy ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(
                 strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary, semanticsLabel: s('signing_in'))) : Text(s('sign_in'))),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 16),
            AuthNotice(state.error!.message, key: const Key('login_error'), error: true),
            if (_cooldown) Padding(padding: const EdgeInsets.only(top: 12),
              child: Text(s('login_retry_after').replaceAll('{seconds}', '$_retrySeconds'),
                key: const Key('login_cooldown'), textAlign: TextAlign.center)),
            if (!pending) TextButton(onPressed: state.busy || _cooldown ? null : () => ref.read(authControllerProvider.notifier).restore(), child: Text(s('retry'))),
          ],
          if (state.revocationConfirmed) ...[const SizedBox(height: 12), AuthNotice(s('signed_out_confirmed'), confirmed: true)],
        ]),
      )),
    );
  }
}
