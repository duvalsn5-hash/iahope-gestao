import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/business/business_category.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/company_repository.dart';
import 'scale_config_card.dart';

/// White-Label: logo (cabeçalho + cupom do PDV), nome fantasia e cor da marca.
class CompanySettingsScreen extends ConsumerStatefulWidget {
  const CompanySettingsScreen({super.key});

  @override
  ConsumerState<CompanySettingsScreen> createState() => _CompanySettingsScreenState();
}

class _CompanySettingsScreenState extends ConsumerState<CompanySettingsScreen> {
  static const _palette = ['#0F4C81', '#1B5E20', '#B71C1C', '#E65100', '#4A148C', '#006064', '#263238', '#AD1457'];

  late final TextEditingController _fantasia;
  bool _uploading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fantasia = TextEditingController(text: ref.read(sessionControllerProvider)?.tenant.nomeFantasia ?? '');
  }

  @override
  void dispose() {
    _fantasia.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    );
    if (file == null) return;
    // bytes em todas as plataformas (inclusive Web)
    final bytes = await file.readAsBytes();
    if (bytes.length > 2 * 1024 * 1024) {
      if (mounted) showError(context, 'A logo deve ter no máximo 2 MB');
      return;
    }
    setState(() => _uploading = true);
    try {
      final url = await ref.read(companyRepositoryProvider).uploadLogo(bytes, file.name);
      final s = ref.read(sessionControllerProvider)!;
      await ref.read(sessionControllerProvider.notifier).updateTenant(s.tenant.copyWith(logoUrl: url));
      if (mounted) showOk(context, 'Logo atualizada');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removeLogo() async {
    try {
      await ref.read(companyRepositoryProvider).removeLogo();
      final s = ref.read(sessionControllerProvider)!;
      await ref.read(sessionControllerProvider.notifier).updateTenant(s.tenant.copyWith(clearLogo: true));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _saveBrand({String? color}) async {
    setState(() => _saving = true);
    try {
      final r = await ref.read(companyRepositoryProvider).updateBrand(
            nomeFantasia: _fantasia.text.trim().isEmpty ? null : _fantasia.text.trim(),
            primaryColor: color,
          );
      final s = ref.read(sessionControllerProvider)!;
      await ref.read(sessionControllerProvider.notifier).updateTenant(
            s.tenant.copyWith(nomeFantasia: r['nomeFantasia'] as String?, primaryColor: r['primaryColor'] as String?),
          );
      if (mounted) showOk(context, 'Dados salvos');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    if (session == null) return const SizedBox.shrink();
    final tenant = session.tenant;
    final t = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Configurações da empresa', style: t.textTheme.headlineSmall),
        const SizedBox(height: 16),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(children: [
              if (!session.isSuperAdmin) ...[
                BusinessCategoryCard(category: session.business),
                const SizedBox(height: 16),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 16,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: t.colorScheme.outlineVariant),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: CompanyLogo(url: tenant.logoUrl, name: tenant.nomeFantasia, size: 140),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 380),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Logo da empresa', style: t.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          const Text('Aparece no cabeçalho do sistema, na tela de login e nos cupons do PDV. '
                              'PNG com fundo transparente, quadrada, até 2 MB.'),
                          const SizedBox(height: 16),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            FilledButton.icon(
                              onPressed: _uploading ? null : _pickLogo,
                              icon: _uploading
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.upload),
                              label: Text(tenant.logoUrl == null ? 'Enviar logo' : 'Trocar logo'),
                            ),
                            if (tenant.logoUrl != null)
                              OutlinedButton.icon(onPressed: _removeLogo, icon: const Icon(Icons.delete_outline), label: const Text('Remover')),
                          ]),
                        ]),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Identidade', style: t.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'CNPJ'),
                      child: Text(formatCnpj(tenant.cnpj)),
                    ),
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Razão social'),
                      child: Text(tenant.razaoSocial),
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: _fantasia, decoration: const InputDecoration(labelText: 'Nome fantasia')),
                    const SizedBox(height: 16),
                    Text('Cor da marca', style: t.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      for (final hex in _palette)
                        InkWell(
                          onTap: _saving ? null : () => _saveBrand(color: hex),
                          customBorder: const CircleBorder(),
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: AppTheme.parseHex(hex),
                            child: tenant.primaryColor?.toUpperCase() == hex
                                ? const Icon(Icons.check, color: Colors.white, size: 18)
                                : null,
                          ),
                        ),
                    ]),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(onPressed: _saving ? null : () => _saveBrand(), child: const Text('Salvar')),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              if (session.hasModule('BALANCA')) ...[
                const ScaleConfigCard(),
                const SizedBox(height: 16),
              ],
              Card(
                child: ListTile(
                  leading: const Icon(Icons.verified_outlined),
                  title: const Text('Licença de uso'),
                  subtitle: Text('Válida até ${dateBr(tenant.licenseExpiresAt)}'
                      '${session.licenseDaysLeft != null ? ' · ${session.licenseDaysLeft} dia(s) restantes' : ''}'),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

/// Ramo de negócio da empresa: o que ele adapta, primeiros passos e o que vem por aí.
class BusinessCategoryCard extends StatelessWidget {
  const BusinessCategoryCard({super.key, required this.category});
  final BusinessCategory category;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: t.colorScheme.primaryContainer,
              child: Icon(category.icon, color: t.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Categoria de negócio', style: t.textTheme.labelMedium),
                Text(category.label, style: t.textTheme.titleMedium),
                Text(category.description, style: t.textTheme.bodySmall),
              ]),
            ),
          ]),
          if (category.tips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Primeiros passos', style: t.textTheme.labelLarge),
            const SizedBox(height: 4),
            for (final (i, tip) in category.tips.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(radius: 10, child: Text('${i + 1}', style: const TextStyle(fontSize: 11))),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tip)),
                ]),
              ),
          ],
          const SizedBox(height: 12),
          Text('Categorias de produto sugeridas', style: t.textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in category.productCategories) Chip(label: Text(c), visualDensity: VisualDensity.compact),
          ]),
          if (category.comingSoon != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.amber.withValues(alpha: .15), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.upcoming_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Em breve: ${category.comingSoon}', style: t.textTheme.bodySmall)),
              ]),
            ),
          ],
          const SizedBox(height: 8),
          Text('Para mudar o ramo, fale com o suporte IaHope-Technology.', style: t.textTheme.bodySmall),
        ]),
      ),
    );
  }
}
