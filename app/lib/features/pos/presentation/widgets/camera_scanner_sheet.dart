import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Câmera como leitor de código de barras (Android/iOS).
/// No Windows e na Web use leitor USB/Bluetooth em modo teclado: ele "digita"
/// o código + Enter no campo de busca, que fica sempre focado.
bool get cameraScannerAvailable =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

Future<String?> scanWithCamera(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _ScannerSheet(),
  );
}

class _ScannerSheet extends StatefulWidget {
  const _ScannerSheet();

  @override
  State<_ScannerSheet> createState() => _ScannerSheetState();
}

class _ScannerSheetState extends State<_ScannerSheet> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.code128, BarcodeFormat.upcA, BarcodeFormat.qrCode],
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .6,
      child: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            final code = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
            if (_done || code == null || code.isEmpty) return;
            _done = true;
            Navigator.pop(context, code);
          },
        ),
        Center(
          child: Container(
            width: 260,
            height: 140,
            decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(12)),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton.filled(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: IconButton.filled(onPressed: () => _controller.toggleTorch(), icon: const Icon(Icons.flashlight_on)),
        ),
      ]),
    );
  }
}
