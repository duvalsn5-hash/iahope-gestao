import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/common_widgets.dart';
import '../data/company_repository.dart';

final _companyProvider = FutureProvider.autoDispose((ref) => ref.read(companyRepositoryProvider).fetch());

/// Configuração da etiqueta da balança (módulo BALANCA).
/// Padrão Toledo/Filizola: 2 + código do produto + valor + dígito verificador (EAN-13).
class ScaleConfigCard extends ConsumerStatefulWidget {
  const ScaleConfigCard({super.key});

  @override
  ConsumerState<ScaleConfigCard> createState() => _ScaleConfigCardState();
}

class _ScaleConfigCardState extends ConsumerState<ScaleConfigCard> {
  String? _prefix;
  int _codeLength = 4;
  int _valueLength = 5;
  String _valueType = 'PRECO';
  bool _loaded = false;
  bool _saving = false;

  void _fill(Map<String, dynamic> company) {
    if (_loaded) return;
    final c = (company['scaleConfig'] as Map?) ?? const {};
    _prefix = (c['prefix'] ?? '2').toString();
    _codeLength = (c['codeLength'] as num? ?? 4).toInt();
    _valueLength = (c['valueLength'] as num? ?? 5).toInt();
    _valueType = (c['valueType'] ?? 'PRECO').toString();
    _loaded = true;
  }

  bool get _fits => 1 + _codeLength <= 12 - _valueLength;

  /// Exemplo de etiqueta com o layout atual: produto 123, valor 15,90 (ou 0,398 kg).
  String get _example {
    final code = '123'.padLeft(_codeLength, '0');
    final value = (_valueType == 'PRECO' ? '1590' : '398').padLeft(_valueLength, '0');
    final filler = '0' * (12 - 1 - _codeLength - _valueLength);
    return '${_prefix ?? '2'} $code ${filler.isEmpty ? '' : '$filler '}$value D';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(companyRepositoryProvider).saveScale({
        'prefix': _prefix ?? '2',
        'codeLength': _codeLength,
        'valueLength': _valueLength,
        'valueType': _valueType,
      });
      if (mounted) showOk(context, 'Configuração da balança salva');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final company = ref.watch(_companyProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: company.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text(e.toString()),
          data: (c) {
            _fill(c);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.scale),
                const SizedBox(width: 8),
                Text('Etiqueta de balança', style: t.textTheme.titleMedium),
              ]),
              const SizedBox(height: 4),
              const Text('Igual ao configurado na balança. No cadastro do produto, informe o "Código na balança".'),
              const SizedBox(height: 16),
              Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(
                  width: 110,
                  child: DropdownButtonFormField<String>(
                    initialValue: _prefix,
                    decoration: const InputDecoration(labelText: 'Prefixo'),
                    items: [for (final d in const ['2', '0', '1', '3', '4', '5', '6', '7', '8', '9']) DropdownMenuItem(value: d, child: Text(d))],
                    onChanged: (v) => setState(() => _prefix = v),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<int>(
                    initialValue: _codeLength,
                    decoration: const InputDecoration(labelText: 'Dígitos do código'),
                    items: const [
                      DropdownMenuItem(value: 4, child: Text('4')),
                      DropdownMenuItem(value: 5, child: Text('5')),
                      DropdownMenuItem(value: 6, child: Text('6')),
                    ],
                    onChanged: (v) => setState(() => _codeLength = v ?? 4),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<int>(
                    initialValue: _valueLength,
                    decoration: const InputDecoration(labelText: 'Dígitos do valor'),
                    items: const [
                      DropdownMenuItem(value: 5, child: Text('5')),
                      DropdownMenuItem(value: 6, child: Text('6')),
                    ],
                    onChanged: (v) => setState(() => _valueLength = v ?? 5),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: _valueType,
                    decoration: const InputDecoration(labelText: 'A etiqueta traz'),
                    items: const [
                      DropdownMenuItem(value: 'PRECO', child: Text('Preço total (centavos)')),
                      DropdownMenuItem(value: 'PESO', child: Text('Peso (gramas)')),
                    ],
                    onChanged: (v) => setState(() => _valueType = v ?? 'PRECO'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Text(
                _fits ? 'Exemplo: $_example  (produto 123, ${_valueType == 'PRECO' ? 'R\$ 15,90' : '0,398 kg'})' : 'Código e valor não cabem em 13 dígitos',
                style: TextStyle(fontFamily: 'monospace', color: _fits ? null : t.colorScheme.error),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: _saving || !_fits ? null : _save, child: const Text('Salvar')),
              ),
            ]);
          },
        ),
      ),
    );
  }
}
