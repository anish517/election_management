import 'kiosk_fullscreen_stub.dart'
    if (dart.library.js_interop) 'kiosk_fullscreen_web.dart';

void enterFullscreen() => enterKioskFullscreenPlatform();
void exitFullscreen() => exitKioskFullscreenPlatform();
bool isFullscreen() => isKioskFullscreenPlatform();
void toggleFullscreen() => toggleKioskFullscreenPlatform();
