import 'package:flutter_test/flutter_test.dart';
import 'package:iahope_gestao/core/business/business_category.dart';
import 'package:iahope_gestao/core/utils/formatters.dart';
import 'package:iahope_gestao/features/pos/domain/pos_models.dart';
import 'package:iahope_gestao/features/products/domain/product.dart';
import 'package:iahope_gestao/features/workshop/domain/workshop.dart';

void main() {
  group('CNPJ', () {
    test('valida dígitos verificadores', () {
      expect(isValidCnpj('11.444.777/0001-61'), isTrue);
      expect(isValidCnpj('11222333000181'), isTrue);
      expect(isValidCnpj('11.444.777/0001-62'), isFalse);
      expect(isValidCnpj('11111111111111'), isFalse);
    });
    test('formata', () => expect(formatCnpj('11444777000161'), '11.444.777/0001-61'));
  });

  test('parseMoney aceita vírgula e ponto', () {
    expect(parseMoney('1.234,56'), 1234.56);
    expect(parseMoney('20'), 20);
    expect(parseMoney('9.90'), 9.9);
  });

  test('totais do carrinho com desconto', () {
    const p = Product(id: '1', sku: 'A', name: 'Caixa', unit: 'UN', price: 4.9, stockQty: 10);
    const s = PosState(items: [CartItem(product: p, qty: 3)], discount: 1.7);
    expect(s.subtotal, 14.7);
    expect(s.total, 13.0);
  });

  test('OS: peças + mão de obra − desconto e fluxo de andamento', () {
    final items = [
      OsItem(kind: 'PECA', productId: 'p', description: 'Óleo', qty: 2, unitPrice: 38, stockQty: 1),
      OsItem(kind: 'SERVICO', description: 'Troca de óleo', qty: 1, unitPrice: 25),
    ];
    expect(items.first.missingStock, isTrue);
    final partsTotal = items.where((i) => i.isPart).fold<double>(0, (a, i) => a + i.total);
    expect(partsTotal, 76);
    expect(OsStatus.aberta.next, OsStatus.orcamento);
    expect(OsStatus.pronta.next, isNull);
    expect(osStatusFromApi('EM_EXECUCAO'), OsStatus.emExecucao);
  });

  test('categoria de negócio: ramos, módulos e padrão', () {
    expect(businessCategoryOf('MODA').label, 'Loja de roupas e calçados');
    expect(businessCategoryOf('OFICINA_MOTO').modules, contains('OFICINA'));
    expect(businessCategoryOf('MERCADINHO').modules, contains('BALANCA'));
    expect(businessCategoryOf('xyz').code, 'OUTRO');
    expect(kBusinessCategories.map((c) => c.code).toSet().length, kBusinessCategories.length);
  });
}
