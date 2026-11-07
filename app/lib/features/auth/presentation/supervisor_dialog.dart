import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/common_widgets.dart';
import '../data/auth_repository.dart';

/// Autorização do gerente: pede usuário e senha de um gerente/administrador
/// e devolve um token que vale 3 minutos para aquela ação.
/// action: DESCONTO | CANCELAR_VENDA | TROCA
Future<String?> askSupervisor(BuildContext context, {required String action, required String reason}) =>
    showDialog<String>(context: context, builder: (_) => _SupervisorDialog(action: action, reason: reason));

class _SupervisorDialog extends ConsumerStatefulWidget {
  const _SupervisorDialog({required this.action, required this.reason});
  final String action, reason;

  @override
  ConsumerState<_SupervisorDialog> createState() => _SupervisorDialogState();
}

class _SupervisorDialogState extends ConsumerState<_SupervisorDialog> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _passFocus = FocusNode();
  bool _busy = false;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(authRepositoryProvider).supervisor(_user.text, _pass.text, widget.action);
      if (!mounted) return;
      showOk(context, 'Autorizado por ${r.name}');
      Navigator.pop(context, r.token);
    } catch (e) {
      if (mounted) showError(context, e);
      _pass.clear();
      _passFocus.requestFocus();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.admin_panel_settings_outlined, size: 36),
      title: const Text('Autorização do gerente'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.reason, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextField(
            controller: _user,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Usuário do gerente', prefixIcon: Icon(Icons.person_outline)),
            onSubmitted: (_) => _passFocus.requestFocus(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            focusNode: _passFocus,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Senha do gerente', prefixIcon: Icon(Icons.lock_outline)),
            onSubmitted: (_) => _go(),
          ),
          const SizedBox(height: 8),
          Text('A autorização fica registrada na auditoria com o nome do gerente.', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _busy ? null : _go, child: const Text('Autorizar')),
      ],
    );
  }
}
