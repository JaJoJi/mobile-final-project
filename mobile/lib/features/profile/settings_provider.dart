import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-tweakable settings — P1-FE-02.
///
/// Persisted in `shared_preferences` (non-sensitive; tokens stay in
/// `flutter_secure_storage`). Loaded once in `main()` and injected via
/// [sharedPreferencesProvider], so reads/writes here are synchronous.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.wsAutoReconnect = true,
  });

  final ThemeMode themeMode;
  final bool wsAutoReconnect;

  AppSettings copyWith({ThemeMode? themeMode, bool? wsAutoReconnect}) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        wsAutoReconnect: wsAutoReconnect ?? this.wsAutoReconnect,
      );
}

/// Overridden in `main()` with the real instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) =>
      throw UnimplementedError('override sharedPreferencesProvider in main'),
);

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  static const _kThemeMode = 'settings.themeMode';
  static const _kWsAutoReconnect = 'settings.wsAutoReconnect';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() {
    final raw = _prefs.getString(_kThemeMode);
    final themeMode = ThemeMode.values
        .cast<ThemeMode?>()
        .firstWhere((m) => m!.name == raw, orElse: () => null);
    return AppSettings(
      themeMode: themeMode ?? ThemeMode.system,
      wsAutoReconnect: _prefs.getBool(_kWsAutoReconnect) ?? true,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _prefs.setString(_kThemeMode, mode.name);
  }

  Future<void> setWsAutoReconnect(bool value) async {
    state = state.copyWith(wsAutoReconnect: value);
    await _prefs.setBool(_kWsAutoReconnect, value);
  }
}
