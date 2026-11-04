import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/domain/session.dart';
import '../../auth/presentation/session_controller.dart';

/// Sobre / Ajuda (F1): créditos, empresa, licença e atalhos de teclado.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionControllerProvider);
    final t = Theme.of(context);

    const shortcuts = [
      ('F1', 'Sobre / Ajuda'),
      ('F2', 'PDV (no PDV: foco na busca)'),
      ('F3', 'Produtividade (no PDV: identificar cliente)'),
      ('Alt+P / Alt+C', 'Produtos / Clientes e fornecedores'),
      ('Alt+F / Alt+N', 'Financeiro / Compras (NF-e)'),
      ('F4', 'Empresa'),
      ('F6', 'Administração Master'),
      ('F7', 'PDV: quantidade · Produtividade: lançar'),
      ('F8', 'PDV: remover item · Produtividade: nova carga'),
      ('F9', 'PDV: desconto · Cupom: imprimir'),
      ('F10', 'PDV: finalizar / concluir pagamento'),
      ('Ctrl+Del', 'PDV: cancelar venda'),
      ('Ctrl+N / Ctrl+F', 'Novo cadastro / buscar (nas telas de cadastro)'),
      ('Ctrl+I', 'Compras: importar XML da NF-e'),
      ('F1–F4, F6', 'Pagamento: Dinheiro, PIX, Débito, Crédito, A prazo'),
    ];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(Icons.hub_outlined, size: 64, color: t.colorScheme.primary),
              const SizedBox(height: 8),
              Text(AppConfig.appName, textAlign: TextAlign.center, style: t.textTheme.headlineMedium),
              Text('Gestão Operacional · Logística · PDV — v1.0.0', textAlign: TextAlign.center, style: t.textTheme.bodyMedium),
              const SizedBox(height: 16),
              Card(
                color: t.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    AppConfig.credits,
                    textAlign: TextAlign.center,
                    style: t.textTheme.titleMedium?.copyWith(color: t.colorScheme.onPrimaryContainer, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (s != null)
                Card(
                  child: Column(children: [
                    ListTile(
                      leading: CompanyLogo(url: s.tenant.logoUrl, name: s.tenant.nomeFantasia, size: 40),
                      title: Text(s.tenant.nomeFantasia),
                      subtitle: Text('${s.tenant.razaoSocial}\nCNPJ ${formatCnpj(s.tenant.cnpj)}'),
                      isThreeLine: true,
                    ),
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(s.user.fullName),
                      subtitle: Text('${s.user.username} · ${roleLabel(s.user.role)}'),
                    ),
                    if (!s.isSuperAdmin)
                      ListTile(
                        leading: const Icon(Icons.verified_outlined),
                        title: const Text('Licença'),
                        subtitle: Text('Válida até ${dateBr(s.tenant.licenseExpiresAt)}'),
                      ),
                    const ListTile(
                      leading: Icon(Icons.dns_outlined),
                      title: Text('Servidor'),
                      subtitle: Text(AppConfig.apiUrl),
                    ),
                  ]),
                ),
              const SizedBox(height: 16),
              Text('Atalhos de teclado', style: t.textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(children: [
                  for (final (k, v) in shortcuts)
                    ListTile(
                      dense: true,
                      leading: SizedBox(width: 110, child: Text(k, style: const TextStyle(fontWeight: FontWeight.bold))),
                      title: Text(v),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              Text(
                'Leitor de código de barras: use leitores USB/Bluetooth em modo teclado (HID) com sufixo Enter. '
                'No Android, o botão de câmera no PDV também lê códigos. Digite "3*" antes do código para lançar 3 unidades.',
                style: t.textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              const CreditsFooter(),
            ]),
          ),
        ),
      ],
    );
  }
}
