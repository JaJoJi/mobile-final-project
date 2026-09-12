import 'package:auto_chess_mobile/features/profile/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> makeContainer() async {
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('defaults: system theme, auto-reconnect and sound on', () async {
    SharedPreferences.setMockInitialValues({});
    final c = await makeContainer();
    final s = c.read(settingsProvider);
    expect(s.themeMode, ThemeMode.system);
    expect(s.wsAutoReconnect, isTrue);
    expect(s.soundEnabled, isTrue);
  });

  test('setThemeMode updates state and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final c = await makeContainer();

    await c.read(settingsProvider.notifier).setThemeMode(ThemeMode.dark);
    expect(c.read(settingsProvider).themeMode, ThemeMode.dark);

    final prefs = c.read(sharedPreferencesProvider);
    expect(prefs.getString('settings.themeMode'), 'dark');
  });

  test('setWsAutoReconnect persists', () async {
    SharedPreferences.setMockInitialValues({});
    final c = await makeContainer();

    await c.read(settingsProvider.notifier).setWsAutoReconnect(false);
    expect(c.read(settingsProvider).wsAutoReconnect, isFalse);
    expect(
      c.read(sharedPreferencesProvider).getBool('settings.wsAutoReconnect'),
      isFalse,
    );
  });

  test('setSoundEnabled persists', () async {
    SharedPreferences.setMockInitialValues({});
    final c = await makeContainer();

    await c.read(settingsProvider.notifier).setSoundEnabled(false);
    expect(c.read(settingsProvider).soundEnabled, isFalse);
    expect(
      c.read(sharedPreferencesProvider).getBool('settings.soundEnabled'),
      isFalse,
    );
  });

  test('reads persisted values on a fresh container (survives restart)',
      () async {
    SharedPreferences.setMockInitialValues({
      'settings.themeMode': 'light',
      'settings.wsAutoReconnect': false,
      'settings.soundEnabled': false,
    });
    final c = await makeContainer();
    final s = c.read(settingsProvider);
    expect(s.themeMode, ThemeMode.light);
    expect(s.wsAutoReconnect, isFalse);
    expect(s.soundEnabled, isFalse);
  });

  test('ignores a garbage persisted theme value', () async {
    SharedPreferences.setMockInitialValues({'settings.themeMode': 'sepia'});
    final c = await makeContainer();
    expect(c.read(settingsProvider).themeMode, ThemeMode.system);
  });
}
