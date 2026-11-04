import 'package:flutter_test/flutter_test.dart';
import 'package:iahope_gestao/core/utils/formatters.dart';
import 'package:iahope_gestao/features/pos/domain/pos_models.dart';
import 'package:iahope_gestao/features/products/domain/product.dart';

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
}
