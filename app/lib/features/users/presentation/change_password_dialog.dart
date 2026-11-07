import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/common_widgets.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/users_repository.dart';

/// Qualquer usuário (inclusive o Master) troca a própria senha.
/// [forced]: senha provisória — não dá para fechar sem trocar.
Future<void> showChangePasswordDialog(BuildContext context, {bool forced = false}) => showDialog<void>(
      context: context,
      barrierDismissible: !forced,
      builder: (_) => _ChangePasswordDialog(forced: forced),
    );

/// Mesmas regras da API: 8+, letras e números, sem o nome de usuário.
String? passwordProblem(String v, {String? username}) {
  if (v.length < 8) return 'Mínimo 8 caracteres';
  if (!RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) return 'Use letras e números';
  if (username != null && username.isNotEmpty && v.toLowerCase().contains(username.toLowerCase())) {
    return 'Não use o nome de usuário na senha';
  }
  return null;
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog({this.forced = false});
  final bool forced;

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
      final token = await ref.read(usersRepositoryProvider).changeMyPassword(_current.text, _next.text);
      await ref.read(sessionControllerProvider.notifier).replaceToken(token, mustChangePassword: false);
      if (!mounted) return;
      Navigator.pop(context);
      showOk(context, 'Senha alterada. Os outros aparelhos vão pedir login de novo.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final username = ref.watch(sessionControllerProvider)?.user.username;
    return PopScope(
      canPop: !widget.forced,
      child: AlertDialog(
      title: Text(widget.forced ? 'Crie sua senha' : 'Trocar minha senha'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (widget.forced)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Você entrou com uma senha provisória. Para continuar, crie uma senha só sua.'),
              ),
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
              validator: (v) => passwordProblem(v ?? '', username: username),
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
        widget.forced
            ? TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  ref.read(sessionControllerProvider.notifier).logout();
                },
                child: const Text('Sair'),
              )
            : TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Trocar senha')),
      ],
      ),
    );
  }
}
