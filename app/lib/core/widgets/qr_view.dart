import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';

/// QR Code desenhado direto na tela (sem imagem nem internet).
class QrView extends StatelessWidget {
  const QrView(this.data, {super.key, this.size = 200});
  final String data;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white,
        padding: const EdgeInsets.all(10),
        child: CustomPaint(size: Size.square(size), painter: _QrPainter(data)),
      );
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.data);
  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    for (final e in Barcode.qrCode().make(data, width: size.width, height: size.height)) {
      if (e is BarcodeBar && e.black) {
        canvas.drawRect(Rect.fromLTWH(e.left, e.top, e.width, e.height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}
