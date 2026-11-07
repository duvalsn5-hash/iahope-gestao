import 'package:flutter/material.dart';

import '../../../core/business/business_category.dart';
import '../../../core/business/business_category_picker.dart';
import '../../../core/utils/formatters.dart';
import '../../users/presentation/change_password_dialog.dart';
import '../domain/tenant.dart';

/// Cadastro de novo cliente + usuário ADMIN inicial.
class CreateTenantDialog extends StatefulWidget {
  const CreateTenantDialog({super.key});

  @override
  State<CreateTenantDialog> createState() => _CreateTenantDialogState();
}

class _CreateTenantDialogState extends State<CreateTenantDialog> {
  final _form = GlobalKey<FormState>();
  final _cnpj = TextEditingController();
  final _razao = TextEditingController();
  final _fantasia = TextEditingController();
  final _maxUsers = TextEditingController(text: '10');
  final _adminUser = TextEditingController(text: 'admin');
  final _adminName = TextEditingController();
  final _adminPass = TextEditingController();
  DateTime _expires = DateTime.now().add(const Duration(days: 30));
  String _category = kBusinessCategories.first.code;
  Set<String> _modules = {...kBusinessCategories.first.modules};

  @override
  void dispose() {
    for (final c in [_cnpj, _razao, _fantasia, _maxUsers, _adminUser, _adminName, _adminPass]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      NewTenantInput(
        cnpj: onlyDigits(_cnpj.text),
        razaoSocial: _razao.text.trim(),
        nomeFantasia: _fantasia.text.trim(),
        licenseExpiresAt: _expires,
        maxUsers: int.tryParse(_maxUsers.text) ?? 10,
        adminUsername: _adminUser.text.trim(),
        adminFullName: _adminName.text.trim(),
        adminPassword: _adminPass.text,
        modules: [for (final m in kModules) if (_modules.contains(m.$1)) m.$1],
        businessCategory: _category,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String? req(String? v, [int min = 1]) => (v ?? '').trim().length < min ? 'Obrigatório' : null;
    const gap = SizedBox(height: 12);

    return AlertDialog(
      title: const Text('Novo cliente'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _cnpj,
                autofocus: true,
                inputFormatters: [CnpjInputFormatter()],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'CNPJ'),
                validator: (v) => isValidCnpj(v ?? '') ? null : 'CNPJ inválido',
              ),
              gap,
              TextFormField(controller: _razao, decoration: const InputDecoration(labelText: 'Razão social'), validator: (v) => req(v, 3)),
              gap,
              TextFormField(controller: _fantasia, decoration: const InputDecoration(labelText: 'Nome fantasia')),
              gap,
              Row(children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _expires,
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) setState(() => _expires = d);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Vencimento da licença'),
                      child: Text(dateBr(_expires)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    controller: _maxUsers,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Máx. usuários'),
                    validator: (v) => (int.tryParse(v ?? '') ?? 0) > 0 ? null : 'Inválido',
                  ),
                ),
              ]),
              const Divider(height: 32),
              Align(alignment: Alignment.centerLeft, child: Text('Categoria de negócio', style: Theme.of(context).textTheme.titleSmall)),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('O ramo já marca os módulos certos, sugere categorias de produto e adapta o sistema. Dá para mudar depois.',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              const SizedBox(height: 8),
              BusinessCategoryPicker(
                selected: _category,
                onSelected: (c) => setState(() {
                  _category = c.code;
                  _modules = {...c.modules};
                }),
              ),
              if (businessCategoryOf(_category).comingSoon != null) ...[
                const SizedBox(height: 8),
                _ComingSoon(businessCategoryOf(_category).comingSoon!),
              ],
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerLeft, child: Text('Módulos contratados', style: Theme.of(context).textTheme.labelLarge)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final m in kModules)
                  FilterChip(
                    label: Text(m.$2),
                    tooltip: m.$3,
                    selected: _modules.contains(m.$1),
                    onSelected: (v) => setState(() => v ? _modules.add(m.$1) : _modules.remove(m.$1)),
                  ),
              ]),
              const Divider(height: 32),
              Align(alignment: Alignment.centerLeft, child: Text('Administrador da empresa', style: Theme.of(context).textTheme.titleSmall)),
              gap,
              TextFormField(controller: _adminName, decoration: const InputDecoration(labelText: 'Nome completo'), validator: (v) => req(v, 3)),
              gap,
              TextFormField(controller: _adminUser, decoration: const InputDecoration(labelText: 'Usuário de acesso'), validator: (v) => req(v, 3)),
              gap,
              TextFormField(
                controller: _adminPass,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Senha provisória',
                  helperText: '8+ caracteres, letras e números. O cliente cria a dele no 1º acesso.',
                ),
                validator: (v) => passwordProblem(v ?? '', username: _adminUser.text.trim()),
                onFieldSubmitted: (_) => _save(),
              ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Criar cliente')),
      ],
    );
  }
}

/// Aviso do que ainda está chegando para o ramo escolhido.
class _ComingSoon extends StatelessWidget {
  const _ComingSoon(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.amber.withValues(alpha: .15), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.upcoming_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text('Em breve para este ramo: $text', style: Theme.of(context).textTheme.bodySmall)),
        ]),
      );
}
