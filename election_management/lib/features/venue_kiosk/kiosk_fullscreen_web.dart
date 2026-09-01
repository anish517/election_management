import 'dart:js_interop';

@JS('enterKioskFullscreen')
external void _enterKioskFullscreen();

@JS('exitKioskFullscreen')
external void _exitKioskFullscreen();

@JS('isKioskFullscreen')
external JSBoolean _isKioskFullscreen();

@JS('toggleKioskFullscreen')
external void _toggleKioskFullscreen();

void enterKioskFullscreenPlatform() {
  try {
    _enterKioskFullscreen();
  } catch (_) {}
}

void exitKioskFullscreenPlatform() {
  try {
    _exitKioskFullscreen();
  } catch (_) {}
}

bool isKioskFullscreenPlatform() {
  try {
    return _isKioskFullscreen().toDart;
  } catch (_) {
    return false;
  }
}

void toggleKioskFullscreenPlatform() {
  try {
    _toggleKioskFullscreen();
  } catch (_) {}
}
