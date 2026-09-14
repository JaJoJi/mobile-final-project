/// Build-time configuration for the Auto Chess mobile client.
///
/// Values are read from `--dart-define` flags at build time:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:80
///
/// For the Android emulator, the host machine is reachable at 10.0.2.2.
/// For iOS simulator, http://localhost works.
/// For physical device over LAN, use http://<your-LAN-ip>.
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost',
  );

  static const String wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'ws://localhost:80',
  );

  static const String apiNamespace = '/api';

  static Duration get requestTimeout => const Duration(seconds: 5);
}
