import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerScreen extends StatelessWidget {
  const QrScannerScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Escanear QR'),
      backgroundColor: const Color(0xFF004A99),
    ),
    body: MobileScanner(
      onDetect: (capture) {
        final barcode = capture.barcodes.first;
        final String? code = barcode.rawValue;
        if (code != null) Navigator.pop(context, code);
      },
    ),
  );
}
