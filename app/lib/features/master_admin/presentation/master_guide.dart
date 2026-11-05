import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/formatters.dart';
import '../domain/tenant.dart';

/// Passo a passo do Administrador Master, dentro do próprio painel.
/// Cada passo explica o que fazer e tem um botão que já leva à ação.
class MasterGuideCard extends StatelessWidget {
  const MasterGuideCard({
    super.key,
    required this.stats,
    required this.onNewClient,
    required this.onChangePassword,
    required this.onOpenHelp,
  });

  final AdminStats stats;
  final VoidCallback onNewClient;
  final VoidCallback onChangePassword;
  final VoidCallback onOpenHelp;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final hasClients = stats.total > 0;
    final steps = [
      _Step(
        icon: Icons.lock_reset,
        title: 'Proteja sua conta',
        text: 'Troque a senha do Master por uma só sua. Ela dá acesso a todas as empresas.',
        action: 'Trocar senha',
        onTap: onChangePassword,
      ),
      _Step(
        icon: Icons.add_business,
        title: 'Cadastre o primeiro cliente',
        text: 'CNPJ, razão social, vencimento da licença e o usuário administrador da empresa. '
            'Escolha o tipo de negócio (oficina, mercadinho…) e os módulos certos já vêm marcados.',
        action: 'Novo cliente',
        onTap: onNewClient,
        done: hasClients,
      ),
      const _Step(
        icon: Icons.send_to_mobile,
        title: 'Envie o acesso ao cliente',
        text: 'Na lista de clientes, toque em "Enviar acesso": o WhatsApp abre com o link do app, o CNPJ e o usuário. '
            'A senha você passa separado, por segurança.',
        done: false,
      ),
      const _Step(
        icon: Icons.extension_outlined,
        title: 'Ajuste os módulos quando o cliente pedir',
        text: 'Botão "Módulos" de cada cliente: liga e desliga PDV, Financeiro, Compras, Oficina, Balança… '
            'O cliente vê a mudança no próximo acesso.',
        done: false,
      ),
      const _Step(
        icon: Icons.event_available,
        title: 'Acompanhe as licenças',
        text: 'Os números no topo mostram quem vence em 7 dias e quem já venceu. "Renovar" muda a data; '
            '"Bloquear" corta o acesso na hora (por exemplo, inadimplência) e "Ativar" devolve.',
        done: false,
      ),
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: !hasClients,
        leading: Icon(Icons.school_outlined, color: t.colorScheme.primary),
        title: const Text('Guia do Master — passo a passo'),
        subtitle: Text(hasClients ? 'Toque para rever os passos' : 'Comece por aqui: 5 passos para colocar o primeiro cliente para rodar'),
        trailing: IconButton(tooltip: 'Ajuda completa', icon: const Icon(Icons.help_outline), onPressed: onOpenHelp),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          for (var i = 0; i < steps.length; i++) _StepTile(index: i + 1, step: steps[i]),
        ],
      ),
    );
  }
}

class _Step {
  const _Step({required this.icon, required this.title, required this.text, this.action, this.onTap, this.done = false});
  final IconData icon;
  final String title;
  final String text;
  final String? action;
  final VoidCallback? onTap;
  final bool done;
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.index, required this.step});
  final int index;
  final _Step step;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: step.done ? Colors.green.shade600 : t.colorScheme.primaryContainer,
          child: step.done
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : Text('$index', style: TextStyle(fontSize: 13, color: t.colorScheme.onPrimaryContainer)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(step.icon, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(step.title, style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 2),
            Text(step.text, style: t.textTheme.bodySmall),
            if (step.action != null && step.onTap != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: FilledButton.tonal(onPressed: step.onTap, child: Text(step.action!)),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// Ajuda completa do painel Master (perguntas frequentes).
Future<void> showMasterHelp(BuildContext context) => showDialog<void>(
      context: context,
      builder: (c) {
        final t = Theme.of(c);
        const faq = [
          ('O que é o Master?', 'É você, dono do sistema. Cadastra as empresas clientes, define o que cada uma pode usar e controla as licenças. '
              'O Master não vê o caixa nem as vendas do cliente pelo menu — cada empresa só enxerga os próprios dados.'),
          ('Como cadastro um cliente?', 'Botão "Novo cliente" (ou Ctrl+N). Informe o CNPJ, a razão social, o vencimento da licença, quantos usuários ele pode ter '
              'e crie o administrador da empresa (usuário e senha inicial). Escolha o tipo de negócio para marcar os módulos.'),
          ('O que são os módulos?', 'Partes do sistema que você libera por cliente: PDV e caixa, Financeiro, Compras por XML, Oficina de motos, '
              'Produtividade logística e Balança. Produtos (com foto), clientes, usuários e a logo vêm sempre.'),
          ('Como o cliente entra?', 'Pelo app (Android ou Windows) ou pelo navegador, no endereço do app Web. Ele digita o CNPJ da empresa, o usuário e a senha. '
              'Use "Enviar acesso" para mandar tudo pronto no WhatsApp.'),
          ('E os funcionários do cliente?', 'O administrador da empresa cria os próprios usuários em "Usuários" (caixa, mecânico, gerente…), até o limite que você definiu.'),
          ('Como funciona a licença?', 'Cada cliente tem uma data de vencimento. Faltando 7 dias, ele vê um aviso. Vencida, o acesso para automaticamente '
              'até você clicar em "Renovar".'),
          ('Quando usar "Bloquear"?', 'Para cortar o acesso na hora, por exemplo por falta de pagamento. Os dados ficam guardados; "Ativar" devolve tudo como estava.'),
          ('O cliente esqueceu a senha', 'O administrador da empresa troca a senha dos funcionários em "Usuários". Se foi o próprio administrador, fale com o suporte técnico para redefinir.'),
        ];
        return AlertDialog(
          title: const Text('Como usar o painel Master'),
          content: SizedBox(
            width: 560,
            child: ListView(shrinkWrap: true, children: [
              for (final f in faq)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(f.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  children: [Align(alignment: Alignment.centerLeft, child: Text(f.$2, style: t.textTheme.bodyMedium))],
                ),
              const SizedBox(height: 12),
              Text('App Web: ${AppConfig.webAppUrl}', style: t.textTheme.bodySmall),
              Text('Downloads (Android e Windows): ${AppConfig.downloadsUrl}', style: t.textTheme.bodySmall),
            ]),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Entendi'))],
        );
      },
    );

/// Mensagem de boas-vindas que o Master envia ao cliente.
String welcomeMessage(Tenant t, {String? adminUsername}) => [
      'Olá! O acesso da *${t.displayName}* ao IaHope Gestão está pronto.',
      '',
      '*Como entrar*',
      '• No navegador: ${AppConfig.webAppUrl}',
      '• Android e Windows: ${AppConfig.downloadsUrl}',
      '',
      '*CNPJ:* ${formatCnpj(t.cnpj)}',
      '*Usuário:* ${adminUsername ?? 'admin'}',
      '*Senha:* enviaremos em outra mensagem.',
      '',
      'Licença válida até ${dateBr(t.licenseExpiresAt)}.',
      'Na primeira vez, cadastre seus funcionários em "Usuários" e a logo em "Empresa".',
    ].join('\n');
