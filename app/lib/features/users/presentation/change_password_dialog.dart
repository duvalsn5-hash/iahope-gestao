import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/common_widgets.dart';
import '../data/users_repository.dart';

/// Qualquer usuário (inclusive o Master) troca a própria senha.
Future<void> showChangePasswordDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _ChangePasswordDialog());

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(usersRepositoryProvider).changeMyPassword(_current.text, _next.text);
      if (!mounted) return;
      Navigator.pop(context);
      showOk(context, 'Senha alterada');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Trocar minha senha'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _current,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Senha atual'),
              validator: (v) => (v ?? '').isEmpty ? 'Informe a senha atual' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Nova senha', helperText: 'mínimo 8 caracteres; misture letras e números'),
              validator: (v) => (v ?? '').length < 8 ? 'Mínimo 8 caracteres' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Repita a nova senha'),
              validator: (v) => v != _next.text ? 'As senhas não conferem' : null,
              onFieldSubmitted: (_) => _save(),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Trocar senha')),
      ],
    );
  }
}
