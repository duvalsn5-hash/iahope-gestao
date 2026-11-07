import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/presentation/account_security_dialog.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/company_repository.dart';

/// Regras de segurança da empresa + acesso à auditoria.
class SecurityCard extends ConsumerStatefulWidget {
  const SecurityCard({super.key});

  @override
  ConsumerState<SecurityCard> createState() => _SecurityCardState();
}

class _SecurityCardState extends ConsumerState<SecurityCard> {
  late final _pct = TextEditingController(text: number(ref.read(sessionControllerProvider)?.tenant.maxDiscountPct ?? 10));
  bool _saving = false;

  @override
  void dispose() {
    _pct.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = parseMoney(_pct.text);
    if (v < 0 || v > 100) return showError(context, 'Informe de 0 a 100%');
    setState(() => _saving = true);
    try {
      await ref.read(companyRepositoryProvider).saveSecurity(maxDiscountPct: v);
      final s = ref.read(sessionControllerProvider);
      if (s != null) await ref.read(sessionControllerProvider.notifier).updateTenant(s.tenant.copyWith(maxDiscountPct: v));
      if (mounted) showOk(context, 'Limite de desconto salvo');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.security, color: t.colorScheme.primary),
            const SizedBox(width: 8),
            Text('Segurança', style: t.textTheme.titleMedium),
          ]),
          const SizedBox(height: 8),
          const _Bullet('Senha errada 5 vezes bloqueia o usuário por 15 min (você pode liberar em Usuários).'),
          const _Bullet('Usuário novo entra com senha provisória e é obrigado a criar a dele.'),
          const _Bullet('O sistema sai sozinho depois de 30 minutos sem uso.'),
          const _Bullet('Cada empresa só enxerga os próprios dados (isolamento por CNPJ no banco).'),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 180,
              child: TextField(
                controller: _pct,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Desconto máximo do caixa', suffixText: '%'),
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton(onPressed: _saving ? null : _save, child: const Text('Salvar')),
            ),
          ]),
          const SizedBox(height: 4),
          Text('Acima disso, o caixa precisa do usuário e senha de um gerente. Fica registrado na auditoria.',
              style: t.textTheme.bodySmall),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () => showDialog<void>(context: context, builder: (_) => const AuditDialog()),
              icon: const Icon(Icons.manage_search),
              label: const Text('Auditoria (quem fez o quê)'),
            ),
            OutlinedButton.icon(
              onPressed: () => showAccountSecurity(context),
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Ligar 2 etapas na minha conta'),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ]),
      );
}

/// Lista da auditoria com filtro por tipo e período.
class AuditDialog extends ConsumerStatefulWidget {
  const AuditDialog({super.key});

  @override
  ConsumerState<AuditDialog> createState() => _AuditDialogState();
}

class _AuditDialogState extends ConsumerState<AuditDialog> {
  static const _filters = [
    ('', 'Tudo'),
    ('LOGIN_FALHA', 'Senhas erradas'),
    ('DESCONTO_ACIMA_LIMITE', 'Descontos acima do limite'),
    ('VENDA_CANCELADA', 'Vendas canceladas'),
    ('TROCA_VALE', 'Trocas'),
    ('CAIXA_FECHADO', 'Fechamentos de caixa'),
    ('USUARIO_ALTERADO', 'Usuários alterados'),
  ];
  String _action = '';
  int _days = 30;
  late Future<List<AuditEntry>> _f = _load();

  Future<List<AuditEntry>> _load() => ref.read(companyRepositoryProvider).audit(action: _action, days: _days);

  void _reload() => setState(() => _f = _load());

  String _details(AuditEntry e) {
    final d = e.details;
    final parts = <String>[
      for (final entry in d.entries)
        if (entry.value != null && entry.value.toString().isNotEmpty && entry.key != 'tentativas')
          '${entry.key.replaceAll('_', ' ')}: ${entry.value is num && entry.key != 'venda' && entry.key != 'percentual' ? money(entry.value as num) : entry.value}',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      title: const Text('Auditoria'),
      content: SizedBox(
        width: 720,
        height: 520,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (k, v) in _filters)
              ChoiceChip(
                label: Text(v),
                selected: _action == k,
                onSelected: (_) {
                  _action = k;
                  _reload();
                },
              ),
            DropdownButton<int>(
              value: _days,
              items: const [
                DropdownMenuItem(value: 1, child: Text('Hoje')),
                DropdownMenuItem(value: 7, child: Text('7 dias')),
                DropdownMenuItem(value: 30, child: Text('30 dias')),
                DropdownMenuItem(value: 90, child: Text('90 dias')),
              ],
              onChanged: (v) {
                _days = v ?? 30;
                _reload();
              },
            ),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<AuditEntry>>(
              future: _f,
              builder: (_, snap) {
                if (snap.hasError) return Center(child: Text(snap.error.toString()));
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final items = snap.data!;
                if (items.isEmpty) return const Center(child: Text('Nada registrado no período'));
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = items[i];
                    final alert = e.action == 'LOGIN_FALHA' || e.action.contains('CANCEL') || e.action.contains('LIMITE');
                    return ListTile(
                      dense: true,
                      leading: Icon(alert ? Icons.warning_amber : Icons.history, color: alert ? t.colorScheme.error : null),
                      title: Text('${e.label}${e.user != null ? ' · ${e.user}' : ''}'),
                      subtitle: Text('${dateTimeBr(e.at)}${_details(e).isNotEmpty ? '\n${_details(e)}' : ''}'),
                      isThreeLine: _details(e).isNotEmpty,
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}
