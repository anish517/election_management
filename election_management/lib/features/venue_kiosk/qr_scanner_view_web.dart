import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

@JS('startQrScanner')
external void _startQrScanner(
  JSString elementId,
  JSFunction onSuccess,
  JSFunction onError,
);

@JS('stopQrScanner')
external void _stopQrScanner();

class LiveQrScannerView extends StatefulWidget {
  final ValueChanged<String> onScanned;
  final ValueChanged<String> onError;

  const LiveQrScannerView({
    super.key,
    required this.onScanned,
    required this.onError,
  });

  @override
  State<LiveQrScannerView> createState() => _LiveQrScannerViewState();
}

class _LiveQrScannerViewState extends State<LiveQrScannerView> {
  static int _viewIdCounter = 0;
  late final String _viewType;
  late final String _elementId;
  bool _hasScanned = false;

  @override
  void initState() {
    super.initState();
    _viewIdCounter++;
    _elementId = 'qr-reader-$_viewIdCounter';
    _viewType = 'qr-reader-view-$_viewIdCounter';

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final div = web.HTMLDivElement()
        ..id = _elementId
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = '#0F172A'
        ..style.borderRadius = '14px'
        ..style.overflow = 'hidden';
      return div;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScanner();
    });
  }

  void _startScanner() {
    _startQrScanner(
      _elementId.toJS,
      ((JSString decoded) {
        if (!_hasScanned && mounted) {
          _hasScanned = true;
          widget.onScanned(decoded.toDart);
        }
      }).toJS,
      ((JSString err) {
        if (mounted) {
          widget.onError(err.toDart);
        }
      }).toJS,
    );
  }

  @override
  void dispose() {
    _stopQrScanner();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 240,
        width: double.infinity,
        child: HtmlElementView(viewType: _viewType),
      ),
    );
  }
}
