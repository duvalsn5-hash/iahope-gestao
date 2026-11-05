import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/domain/session.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/users_repository.dart';
import '../domain/app_user.dart';

final usersPageProvider = FutureProvider.autoDispose<UsersPage>((ref) => ref.read(usersRepositoryProvider).list());

/// Usuários da empresa: caixas, mecânicos, gerentes… (só o ADMIN).
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, UsersPage page, [AppUser? u]) async {
    if (u == null && page.activeCount >= page.maxUsers) {
      showError(context, 'Seu plano permite ${page.maxUsers} usuários ativos. Desative alguém ou fale com o suporte.');
      return;
    }
    final ok = await showDialog<bool>(context: context, builder: (_) => _UserDialog(user: u));
    if (ok == true) {
      ref.invalidate(usersPageProvider);
      if (context.mounted) showOk(context, u == null ? 'Usuário criado' : 'Usuário atualizado');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(usersPageProvider);
    final me = ref.watch(sessionControllerProvider);
    final t = Theme.of(context);

    return page.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(e.toString())),
      data: (p) => CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => _edit(context, ref, p)},
        child: Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(context, ref, p),
            icon: const Icon(Icons.person_add),
            label: const Text('Novo usuário'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text('Usuários', style: t.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text('${p.activeCount} de ${p.maxUsers} usuários ativos no seu plano. '
                  'Cada pessoa entra com o CNPJ da empresa, o próprio usuário e a própria senha.'),
              const SizedBox(height: 12),
              Card(
                child: Column(children: [
                  for (var i = 0; i < p.users.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    Builder(builder: (context) {
                      final u = p.users[i];
                      return ListTile(
                        onTap: () => _edit(context, ref, p, u),
                        leading: CircleAvatar(
                          child: Icon(switch (u.role) {
                            UserRole.mecanico => Icons.build,
                            UserRole.caixa => Icons.point_of_sale,
                            UserRole.admin => Icons.admin_panel_settings,
                            UserRole.gerente => Icons.supervisor_account,
                            _ => Icons.person,
                          }, size: 20),
                        ),
                        title: Text(u.fullName + (u.id == me?.user.id ? ' (você)' : ''),
                            style: TextStyle(color: u.isActive ? null : t.colorScheme.outline)),
                        subtitle: Text([
                          roleLabel(u.role),
                          if (u.username != null) 'usuário: ${u.username}',
                          if (u.role == UserRole.mecanico && u.commissionPct > 0) 'comissão ${number(u.commissionPct)}%',
                          u.lastLoginAt == null ? 'nunca entrou' : 'último acesso ${dateTimeBr(u.lastLoginAt)}',
                        ].join(' · ')),
                        trailing: u.isActive ? const Icon(Icons.chevron_right) : const Text('inativo'),
                      );
                    }),
                  ],
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserDialog extends ConsumerStatefulWidget {
  const _UserDialog({this.user});
  final AppUser? user;

  @override
  ConsumerState<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends ConsumerState<_UserDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.user?.fullName ?? '');
  late final _username = TextEditingController(text: widget.user?.username ?? '');
  late final _email = TextEditingController(text: widget.user?.email ?? '');
  final _password = TextEditingController();
  late final _commission = TextEditingController(
      text: (widget.user?.commissionPct ?? 0) == 0 ? '' : number(widget.user!.commissionPct));
  late UserRole _role = widget.user?.role ?? UserRole.caixa;
  late bool _active = widget.user?.isActive ?? true;
  bool _saving = false;

  bool get _isNew => widget.user == null;

  @override
  void dispose() {
    for (final c in [_name, _username, _email, _password, _commission]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(usersRepositoryProvider);
      final pct = _role == UserRole.mecanico ? parseMoney(_commission.text) : 0.0;
      final email = _email.text.trim().isEmpty ? null : _email.text.trim();
      if (_isNew) {
        await repo.create(
          username: _username.text.trim(),
          fullName: _name.text.trim(),
          email: email,
          role: _role,
          password: _password.text,
          commissionPct: pct,
        );
      } else {
        await repo.update(
          widget.user!.id,
          fullName: _name.text.trim(),
          email: email,
          role: _role,
          isActive: _active,
          commissionPct: pct,
          newPassword: _password.text.isEmpty ? null : _password.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return AlertDialog(
      title: Text(_isNew ? 'Novo usuário' : 'Editar usuário'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nome completo'),
                validator: (v) => (v ?? '').trim().length < 3 ? 'Informe o nome' : null,
              ),
              gap,
              TextFormField(
                controller: _username,
                enabled: _isNew,
                decoration: const InputDecoration(labelText: 'Usuário de acesso', helperText: 'sem espaço, ex.: carlos'),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._-]'))],
                validator: (v) => !_isNew || (v ?? '').trim().length >= 3 ? null : 'Mínimo 3 caracteres',
              ),
              gap,
              Text('Perfil', style: Theme.of(context).textTheme.labelLarge),
              for (final r in kAssignableRoles)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  onTap: () => setState(() => _role = r),
                  leading: Icon(_role == r ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: _role == r ? Theme.of(context).colorScheme.primary : null),
                  title: Text(roleLabel(r)),
                  subtitle: Text(roleHelp(r)),
                ),
              if (_role == UserRole.mecanico) ...[
                gap,
                TextFormField(
                  controller: _commission,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Comissão sobre a mão de obra', suffixText: '%'),
                ),
              ],
              gap,
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(labelText: _isNew ? 'Senha inicial' : 'Nova senha (deixe vazio para manter)'),
                validator: (v) {
                  final s = v ?? '';
                  if (_isNew && s.length < 8) return 'Mínimo 8 caracteres';
                  if (!_isNew && s.isNotEmpty && s.length < 8) return 'Mínimo 8 caracteres';
                  return null;
                },
              ),
              gap,
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail (opcional)'),
              ),
              if (!_isNew)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ativo'),
                  subtitle: const Text('Inativo não consegue entrar e não conta no limite do plano'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Salvar')),
      ],
    );
  }
}
