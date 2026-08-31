import 'package:flutter/material.dart';

class LiveQrScannerView extends StatelessWidget {
  final ValueChanged<String> onScanned;
  final ValueChanged<String> onError;

  const LiveQrScannerView({
    super.key,
    required this.onScanned,
    required this.onError,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.5)),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_scanner_rounded, size: 48, color: Color(0xFFD8B4FE)),
          SizedBox(height: 8),
          Text(
            'Live camera scanner not supported on this platform.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
