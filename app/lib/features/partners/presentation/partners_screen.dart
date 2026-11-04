import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/partners_repository.dart';
import '../domain/partner.dart';
import 'partner_form_dialog.dart';

class PartnerFilter {
  const PartnerFilter({this.q = '', this.kind});
  final String q;
  final String? kind; // CLIENTE | FORNECEDOR | null
}

final partnerFilterProvider = StateProvider.autoDispose<PartnerFilter>((_) => const PartnerFilter());

final partnerListProvider = FutureProvider.autoDispose<List<Partner>>((ref) {
  final f = ref.watch(partnerFilterProvider);
  return ref.read(partnersRepositoryProvider).search(f.q, kind: f.kind, all: true);
});

/// Clientes e fornecedores. Atalhos: Ctrl+N novo · Ctrl+F buscar
class PartnersScreen extends ConsumerStatefulWidget {
  const PartnersScreen({super.key});

  @override
  ConsumerState<PartnersScreen> createState() => _PartnersScreenState();
}

class _PartnersScreenState extends ConsumerState<PartnersScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(partnerFilterProvider.notifier).state = PartnerFilter(q: v.trim(), kind: ref.read(partnerFilterProvider).kind);
    });
  }

  Future<void> _edit([Partner? p]) async {
    final session = ref.read(sessionControllerProvider);
    if (p != null && !(session?.isManager ?? false)) return; // caixa só cadastra
    final kind = ref.read(partnerFilterProvider).kind == 'FORNECEDOR' ? PartnerKind.fornecedor : PartnerKind.cliente;
    final input = await showDialog<Partner>(
      context: context,
      builder: (_) => PartnerFormDialog(initial: p, defaultKind: kind),
    );
    if (input == null || !mounted) return;
    try {
      final repo = ref.read(partnersRepositoryProvider);
      if (p == null) {
        await repo.create(input);
      } else {
        await repo.update(p.id, input);
      }
      ref.invalidate(partnerListProvider);
      if (mounted) showOk(context, 'Cadastro salvo');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(partnerListProvider);
    final filter = ref.watch(partnerFilterProvider);
    final compact = Breakpoints.isCompact(context);
    final t = Theme.of(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => _edit(),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _searchFocus.requestFocus(),
      },
      child: Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(),
          icon: const Icon(Icons.person_add_alt_1),
          label: Text(compact ? 'Novo' : 'Novo cadastro (Ctrl+N)'),
        ),
        body: RefreshIndicator(
          onRefresh: () => ref.refresh(partnerListProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text('Clientes e fornecedores', style: t.textTheme.headlineSmall),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: compact ? double.infinity : 380,
                  child: TextField(
                    controller: _search,
                    focusNode: _searchFocus,
                    autofocus: !compact,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Nome, fantasia, CPF ou CNPJ'),
                    onChanged: _onSearch,
                  ),
                ),
                for (final k in const [(null, 'Todos'), ('CLIENTE', 'Clientes'), ('FORNECEDOR', 'Fornecedores')])
                  ChoiceChip(
                    label: Text(k.$2),
                    selected: filter.kind == k.$1,
                    onSelected: (_) => ref.read(partnerFilterProvider.notifier).state = PartnerFilter(q: filter.q, kind: k.$1),
                  ),
              ]),
              const SizedBox(height: 12),
              list.when(
                loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Card(child: ListTile(leading: const Icon(Icons.error), title: Text(e.toString()))),
                data: (items) => items.isEmpty
                    ? const Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Nenhum cadastro encontrado')))
                    : Card(
                        child: Column(children: [
                          for (var i = 0; i < items.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            _PartnerTile(p: items[i], onTap: () => _edit(items[i])),
                          ],
                        ]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PartnerTile extends StatelessWidget {
  const _PartnerTile({required this.p, required this.onTap});
  final Partner p;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final icon = switch (p.kind) {
      PartnerKind.fornecedor => Icons.local_shipping_outlined,
      PartnerKind.ambos => Icons.swap_horiz,
      PartnerKind.cliente => Icons.person_outline,
    };
    final info = [
      if (p.doc != null) formatDoc(p.doc),
      if (p.phone != null) p.phone!,
      if (p.cityState.isNotEmpty) p.cityState,
    ].join(' · ');
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(child: Icon(icon, size: 20)),
      title: Text(p.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: p.isActive ? null : t.colorScheme.outline)),
      subtitle: Text(info.isEmpty ? partnerKindLabel(p.kind) : '${partnerKindLabel(p.kind)} · $info',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: p.openReceivable > 0
          ? Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('a receber', style: t.textTheme.labelSmall),
              Text(money(p.openReceivable), style: TextStyle(fontWeight: FontWeight.w600, color: t.colorScheme.primary)),
            ])
          : (p.isActive ? null : const Text('inativo')),
    );
  }
}
