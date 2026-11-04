import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/purchases_repository.dart';
import '../domain/purchase.dart';
import 'purchase_import_page.dart';

final purchaseListProvider = FutureProvider.autoDispose<List<PurchaseRow>>((ref) => ref.read(purchasesRepositoryProvider).list());

/// Compras: notas de entrada lançadas + importação de XML de NF-e. Atalho: Ctrl+I importar
class PurchasesScreen extends ConsumerStatefulWidget {
  const PurchasesScreen({super.key});

  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen> {
  bool _loading = false;

  Future<void> _import() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['xml']);
    if (file == null || !mounted) return;
    setState(() => _loading = true);
    try {
      final bytes = await file.readAsBytes();
      final preview = await ref.read(purchasesRepositoryProvider).preview(bytes, file.name);
      if (!mounted) return;
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => PurchaseImportPage(preview: preview), fullscreenDialog: true),
      );
      if (saved == true) {
        ref.invalidate(purchaseListProvider);
        if (mounted) showOk(context, 'Nota ${preview.number} lançada: estoque e contas a pagar atualizados');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(purchaseListProvider);
    final compact = Breakpoints.isCompact(context);
    final t = Theme.of(context);

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.keyI, control: true): _import},
      child: Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _loading ? null : _import,
          icon: _loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.upload_file),
          label: Text(compact ? 'Importar XML' : 'Importar XML da NF-e (Ctrl+I)'),
        ),
        body: RefreshIndicator(
          onRefresh: () => ref.refresh(purchaseListProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text('Compras (entrada de NF-e)', style: t.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Importe o XML enviado pelo fornecedor: o estoque, o custo dos produtos e as contas a pagar '
                'são atualizados de uma vez. Na próxima nota do mesmo fornecedor, os produtos já são reconhecidos.',
                style: t.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              list.when(
                loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Card(child: ListTile(leading: const Icon(Icons.error), title: Text(e.toString()))),
                data: (items) => items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(48),
                        child: Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.receipt_long_outlined, size: 56, color: t.colorScheme.outline),
                            const SizedBox(height: 8),
                            const Text('Nenhuma nota lançada ainda'),
                          ]),
                        ),
                      )
                    : Card(
                        child: Column(children: [
                          for (var i = 0; i < items.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.receipt_long, size: 20)),
                              title: Text('NF-e ${items[i].number}${items[i].series != null ? '/${items[i].series}' : ''} · '
                                  '${items[i].supplierName ?? 'Fornecedor'}'),
                              subtitle: Text('Emissão ${dateBr(items[i].issueDate)} · ${items[i].itemsCount} item(ns) · '
                                  'lançada ${dateTimeBr(items[i].createdAt)}${items[i].user != null ? ' por ${items[i].user}' : ''}'),
                              trailing: Text(money(items[i].total), style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
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
