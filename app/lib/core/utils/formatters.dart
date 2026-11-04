import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

String onlyDigits(String v) => v.replaceAll(RegExp(r'\D'), '');

bool isValidCnpj(String value) {
  final d = onlyDigits(value);
  if (d.length != 14 || RegExp(r'^(\d)\1{13}$').hasMatch(d)) return false;
  int calc(int len) {
    final w = len == 12
        ? [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
        : [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    var s = 0;
    for (var i = 0; i < len; i++) {
      s += int.parse(d[i]) * w[i];
    }
    final r = s % 11;
    return r < 2 ? 0 : 11 - r;
  }

  return calc(12) == int.parse(d[12]) && calc(13) == int.parse(d[13]);
}

/// 11444777000161 → 11.444.777/0001-61
String formatCnpj(String v) {
  final d = onlyDigits(v);
  if (d.length != 14) return v;
  return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5, 8)}/${d.substring(8, 12)}-${d.substring(12)}';
}

/// Máscara de digitação 00.000.000/0000-00
class CnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final d = onlyDigits(newValue.text);
    final digits = d.length > 14 ? d.substring(0, 14) : d;
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 5) b.write('.');
      if (i == 8) b.write('/');
      if (i == 12) b.write('-');
      b.write(digits[i]);
    }
    final text = b.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
final _number = NumberFormat.decimalPattern('pt_BR');
final _date = DateFormat('dd/MM/yyyy', 'pt_BR');
final _dateTime = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

String money(num v) => _money.format(v);
String number(num v) => _number.format(v);
String dateBr(DateTime? d) => d == null ? '-' : _date.format(d.toLocal());
String dateTimeBr(DateTime? d) => d == null ? '-' : _dateTime.format(d.toLocal());

/// Converte "1.234,56" ou "1234.56" em double.
double parseMoney(String v) {
  final t = v.trim().replaceAll(RegExp(r'[^\d,.-]'), '');
  if (t.contains(',')) return double.tryParse(t.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
  return double.tryParse(t) ?? 0;
}
