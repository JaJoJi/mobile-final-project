import 'package:flutter/foundation.dart';

/// Process-wide auth signal.
///
/// A plain [ChangeNotifier] (no Riverpod) so the Dio interceptor in
/// `api_client.dart` and the `GoRouter` in `router.dart` can both reach it
/// without a provider cycle — `ApiClient` is built before `AuthRepository`,
/// and the router is built before the widget tree.
///
/// The interceptor calls [signalSignedOut] when a token refresh fails; the
/// router listens (`refreshListenable`) and re-runs its redirect, which
/// bounces the user to `/login`.
class AuthGate extends ChangeNotifier {
  AuthGate._();

  /// The single shared instance.
  static final AuthGate instance = AuthGate._();

  /// Latest known auth state. `null` until the splash screen resolves it.
  bool? get isSignedIn => _isSignedIn;
  bool? _isSignedIn;

  void signalSignedIn() => _set(true);

  void signalSignedOut() => _set(false);

  void _set(bool value) {
    if (_isSignedIn == value) return;
    _isSignedIn = value;
    notifyListeners();
  }

  /// Back to the pre-launch "unresolved" state. Tests only — the app never
  /// un-resolves the gate at runtime.
  @visibleForTesting
  void reset() {
    _isSignedIn = null;
    notifyListeners();
  }
}
