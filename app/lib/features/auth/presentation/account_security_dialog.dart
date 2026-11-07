import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/qr_view.dart';
import '../../users/presentation/change_password_dialog.dart';
import '../data/auth_repository.dart';
import 'session_controller.dart';

Future<void> showAccountSecurity(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _AccountSecurityDialog());

/// Segurança da minha conta: senha, verificação em 2 etapas e sair de todos os aparelhos.
class _AccountSecurityDialog extends ConsumerStatefulWidget {
  const _AccountSecurityDialog();

  @override
  ConsumerState<_AccountSecurityDialog> createState() => _AccountSecurityDialogState();
}

class _AccountSecurityDialogState extends ConsumerState<_AccountSecurityDialog> {
  ({String secret, String url})? _setup;
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final s = await _repo.totpSetup();
      setState(() => _setup = s);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enable() async {
    setState(() => _busy = true);
    try {
      final token = await _repo.totpEnable(_code.text);
      await ref.read(sessionControllerProvider.notifier).replaceToken(token, totpEnabled: true);
      if (!mounted) return;
      setState(() => _setup = null);
      showOk(context, 'Verificação em duas etapas ligada');
    } catch (e) {
      if (mounted) showError(context, e);
      _code.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    final pw = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Desligar as duas etapas?'),
        content: TextField(
          controller: pw,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Confirme com sua senha'),
          onSubmitted: (_) => Navigator.pop(c, true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Desligar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final token = await _repo.totpDisable(pw.text);
      await ref.read(sessionControllerProvider.notifier).replaceToken(token, totpEnabled: false);
      if (mounted) showOk(context, 'Verificação em duas etapas desligada');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logoutAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sair de todos os aparelhos?'),
        content: const Text('Todos os logins abertos desta conta (inclusive este) serão encerrados. '
            'Use se perdeu o celular ou acha que alguém viu sua senha.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sair de todos')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.logoutAll();
      if (!mounted) return;
      Navigator.pop(context);
      ref.read(sessionControllerProvider.notifier).expire('Você saiu de todos os aparelhos. Entre de novo.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = ref.watch(sessionControllerProvider);
    final on = s?.user.totpEnabled ?? false;
    final setup = _setup;
    return AlertDialog(
      title: const Text('Segurança da minha conta'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.password),
              title: const Text('Senha'),
              subtitle: const Text('8+ caracteres com letras e números. Ao trocar, os outros aparelhos saem.'),
              trailing: OutlinedButton(onPressed: () => showChangePasswordDialog(context), child: const Text('Trocar')),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(on ? Icons.verified_user : Icons.shield_outlined, color: on ? Colors.green.shade700 : null),
              title: Text('Verificação em duas etapas ${on ? '(ligada)' : '(desligada)'}'),
              subtitle: const Text('Além da senha, pede um código do celular (Google Authenticator, Microsoft Authenticator…). '
                  'Mesmo que descubram sua senha, não entram.'),
              trailing: on
                  ? TextButton(onPressed: _busy ? null : _disable, child: const Text('Desligar'))
                  : setup == null
                      ? FilledButton(onPressed: _busy ? null : _start, child: const Text('Ligar'))
                      : null,
            ),
            if (setup != null) ...[
              const SizedBox(height: 8),
              Text('1. Instale um aplicativo autenticador no celular.', style: t.textTheme.bodyMedium),
              Text('2. No aplicativo, toque em "+" e leia este QR Code:', style: t.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Center(child: QrView(setup.url, size: 190)),
              const SizedBox(height: 8),
              Text('Sem câmera? Digite a chave:', style: t.textTheme.bodySmall),
              Row(children: [
                Expanded(child: SelectableText(setup.secret, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold))),
                IconButton(
                  tooltip: 'Copiar',
                  onPressed: () => Clipboard.setData(ClipboardData(text: setup.secret)),
                  icon: const Icon(Icons.copy, size: 18),
                ),
              ]),
              const SizedBox(height: 8),
              Text('3. Digite o código de 6 dígitos que aparece no aplicativo:', style: t.textTheme.bodyMedium),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _code,
                    autofocus: true,
                    maxLength: 6,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, letterSpacing: 6),
                    decoration: const InputDecoration(counterText: '', hintText: '000000'),
                    onSubmitted: (_) => _enable(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _busy ? null : _enable, child: const Text('Confirmar')),
              ]),
              const SizedBox(height: 4),
              Text('Se perder o celular, o administrador da empresa (ou o suporte) zera as duas etapas.',
                  style: t.textTheme.bodySmall),
            ],
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.devices_other),
              title: const Text('Sair de todos os aparelhos'),
              subtitle: const Text('Encerra os logins abertos em computadores e celulares.'),
              trailing: OutlinedButton(onPressed: _logoutAll, child: const Text('Sair de todos')),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Saída automática'),
              subtitle: const Text('O sistema sai sozinho depois de 30 minutos sem uso.'),
            ),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}
