import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_colors.dart';

class PairingTicket {
  const PairingTicket({required this.serverUrl, required this.hostCode});

  final String serverUrl;
  final String hostCode;

  static PairingTicket? parse(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) return null;
      final serverUrl = decoded['serverUrl'] as String?;
      final hostCode = decoded['hostCode'] as String?;
      if (serverUrl == null || serverUrl.isEmpty || hostCode == null || hostCode.isEmpty) {
        return null;
      }
      return PairingTicket(serverUrl: serverUrl, hostCode: hostCode);
    } on FormatException {
      return null;
    }
  }
}

/// Camera-only page so scanner permissions and controls never complicate the
/// fast recording pages.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  bool _handled = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan connection ticket'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(onDetect: _onDetect),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
          Positioned(
            right: 20,
            bottom: 40,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                _message ?? 'Point the camera at the host connection ticket.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _message == null ? Colors.white : AppColors.stock,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;
    final ticket = PairingTicket.parse(value);
    if (ticket == null) {
      setState(() => _message = 'This is not a TallyTaps host connection ticket.');
      return;
    }
    _handled = true;
    Navigator.of(context).pop(ticket);
  }
}
