import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_theme.dart';

class QrScannerScreen extends StatelessWidget {
  const QrScannerScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.darkBackground,
    appBar: AppBar(title: const Text('Escanear QR')),
    body: MobileScanner(
      onDetect: (capture) {
        final barcode = capture.barcodes.first;
        final String? code = barcode.rawValue;
        if (code != null) Navigator.pop(context, code);
      },
    ),
  );
}
