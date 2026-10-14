import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'auth_layout.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();

  Future<void> _submit() async {
    if (ref.read(authControllerProvider).busy || !_form.currentState!.validate()) return;
    await ref.read(authControllerProvider.notifier).changePassword(_old.text, _new.text);
  }

  @override
  void dispose() { _old.dispose(); _new.dispose(); _confirm.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final state = ref.watch(authControllerProvider);
    return AuthLayout(
      subtitle: s('change_password_required'),
      child: AutofillGroup(child: Form(key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextFormField(key: const Key('old_password'), controller: _old, obscureText: true, enabled: !state.busy,
            autocorrect: false, enableSuggestions: false, textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(labelText: s('old_password'), prefixIcon: const Icon(Icons.lock_outline)),
            validator: (v) => v == null || v.isEmpty ? s('required') : null),
          const SizedBox(height: 16),
          TextFormField(key: const Key('new_password'), controller: _new, obscureText: true, enabled: !state.busy,
            autocorrect: false, enableSuggestions: false, textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(labelText: s('new_password'), prefixIcon: const Icon(Icons.lock_outline)), validator: (v) {
              if (v == null || v.length < 8 || v.length > 128) {
                return s('password_min');
              }
              if (!RegExp(r'[A-Z]').hasMatch(v) || !RegExp(r'[a-z]').hasMatch(v) ||
                  !RegExp(r'[0-9]').hasMatch(v) || !RegExp(r'[!@#$%^&*()]').hasMatch(v)) {
                return s('password_strength');
              }
              return null;
            }),
          const SizedBox(height: 16),
          TextFormField(key: const Key('confirm_password'), controller: _confirm, obscureText: true, enabled: !state.busy,
            autocorrect: false, enableSuggestions: false, textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            decoration: InputDecoration(labelText: s('confirm_password'), prefixIcon: const Icon(Icons.lock_outline)),
            validator: (v) => v != _new.text ? s('password_match') : null),
          if (state.error != null) Padding(padding: const EdgeInsets.only(top: 16),
            child: AuthNotice(state.error!.message, error: true)),
          const SizedBox(height: 24),
          FilledButton(key: const Key('change_password_submit'), onPressed: state.busy ? null : _submit,
            child: state.busy ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(
              strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary, semanticsLabel: s('change_and_login')))
              : Text(s('change_and_login'))),
          TextButton(key: const Key('change_password_logout'),
            onPressed: state.busy ? null : () => ref.read(authControllerProvider.notifier).logout(), child: Text(s('logout'))),
        ]),
      )),
    );
  }
}
