// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

/// Tells `web/index.html` that auth has resolved and the destination page is
/// painted. Until then the lightweight HTML bootstrap remains above Flutter.
void hideBootstrapOverlay() {
  html.window.dispatchEvent(html.Event('auto-chess-ready'));
}
