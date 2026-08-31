import 'package:flutter/material.dart';
import 'qr_scanner_view_stub.dart'
    if (dart.library.js_interop) 'qr_scanner_view_web.dart';

Widget buildLiveQrScanner({
  required ValueChanged<String> onScanned,
  required ValueChanged<String> onError,
}) {
  return LiveQrScannerView(
    onScanned: onScanned,
    onError: onError,
  );
}
