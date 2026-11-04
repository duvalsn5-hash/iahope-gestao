import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/partners_repository.dart';
import '../domain/partner.dart';
import 'partner_form_dialog.dart';

/// Busca rápida de cliente (PDV) ou fornecedor, com cadastro na hora.
/// Retorna o Partner escolhido, ou null.
class PartnerPickerDialog extends ConsumerStatefulWidget {
  const PartnerPickerDialog({super.key, this.kind = 'CLIENTE', this.title = 'Identificar cliente'});
  final String kind;
  final String title;

  @override
  ConsumerState<PartnerPickerDialog> createState() => _PartnerPickerDialogState();
}

class _PartnerPickerDialogState extends ConsumerState<PartnerPickerDialog> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Partner> _items = const [];
  int _sel = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    setState(() => _loading = true);
    try {
      final r = await ref.read(partnersRepositoryProvider).search(q, kind: widget.kind);
      if (mounted) {
        setState(() {
          _items = r;
          _sel = 0;
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final digits = onlyDigits(_q.text);
    final p = await showDialog<Partner>(
      context: context,
      builder: (_) => PartnerFormDialog(
        quick: true,
        initial: digits.length >= 11
            ? Partner(id: '', kind: PartnerKind.cliente, name: '', doc: digits)
            : null,
      ),
    );
    if (p == null || !mounted) return;
    try {
      final created = await ref.read(partnersRepositoryProvider).create(p);
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    void move(int d) {
      if (_items.isEmpty) return;
      setState(() => _sel = (_sel + d).clamp(0, _items.length - 1).toInt());
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => move(-1),
      },
      child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(children: [
          TextField(
            controller: _q,
            autofocus: true,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Nome, CPF ou CNPJ — ↑/↓ e Enter',
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
            ),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 250), () => _load(v.trim()));
            },
            onSubmitted: (_) {
              if (_items.isNotEmpty) Navigator.pop(context, _items[_sel]);
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _items.isEmpty && !_loading
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('Nenhum cadastro encontrado'),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(onPressed: _create, icon: const Icon(Icons.person_add), label: const Text('Cadastrar agora')),
                    ]),
                  )
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final p = _items[i];
                      return ListTile(
                        selected: i == _sel,
                        selectedTileColor: t.colorScheme.primaryContainer,
                        title: Text(p.displayName),
                        subtitle: Text([if (p.doc != null) formatDoc(p.doc), if (p.phone != null) p.phone!].join(' · ')),
                        trailing: p.openReceivable > 0 ? Text('deve ${money(p.openReceivable)}') : null,
                        onTap: () => Navigator.pop(context, p),
                      );
                    },
                  ),
          ),
        ]),
      ),
      actions: [
        TextButton.icon(onPressed: _create, icon: const Icon(Icons.person_add_alt), label: const Text('Novo cliente')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      ],
      ),
    );
  }
}
