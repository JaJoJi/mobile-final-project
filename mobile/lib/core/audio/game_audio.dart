import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum GameSfx {
  purchase('purchase.ogg', 0.46),
  refresh('refresh.ogg', 0.40),
  ready('ready.ogg', 0.38);

  const GameSfx(this.fileName, this.volume);
  final String fileName;
  final double volume;
}

/// Small bounded mixer for planning-phase UI feedback.
abstract interface class GameAudio {
  bool get enabled;
  set enabled(bool value);
  Future<void> preload();
  Future<void> play(GameSfx sound);
  Future<void> dispose();
}

class AudioplayersGameAudio implements GameAudio {
  AudioplayersGameAudio({int voiceCount = 4})
      : _cache = AudioCache(prefix: 'assets/audio/'),
        _players = List.generate(voiceCount, (_) => AudioPlayer());

  final AudioCache _cache;
  final List<AudioPlayer> _players;
  final Map<GameSfx, DateTime> _lastPlayed = {};
  Future<void>? _preloadFuture;
  int _nextPlayer = 0;
  bool _enabled = false;

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (value) {
      unawaited(preload());
    } else {
      for (final player in _players) {
        unawaited(player.stop().catchError((_) {}));
      }
    }
  }

  @override
  Future<void> preload() {
    if (!_enabled) return Future.value();
    return _preloadFuture ??= _loadAll();
  }

  Future<void> _loadAll() async {
    try {
      await _cache.loadAll(GameSfx.values.map((s) => s.fileName).toList());
      for (final player in _players) {
        player.audioCache = _cache;
        await player.setReleaseMode(ReleaseMode.stop);
      }
    } catch (_) {
      // Audio is optional feedback. A missing platform plugin or failed asset
      // must never interrupt gameplay (notably in widget tests and web).
      _preloadFuture = null;
    }
  }

  @override
  Future<void> play(GameSfx sound) async {
    if (!_enabled) return;
    final now = DateTime.now();
    final last = _lastPlayed[sound];
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 75)) {
      return;
    }
    _lastPlayed[sound] = now;
    try {
      await preload();
      final player = _players[_nextPlayer++ % _players.length];
      await player.play(
        AssetSource(sound.fileName),
        volume: sound.volume,
        mode: PlayerMode.lowLatency,
      );
    } catch (_) {
      // Keep sound failures isolated from match state and user actions.
    }
  }

  @override
  Future<void> dispose() async {
    for (final player in _players) {
      await player.dispose();
    }
    await _cache.clearAll();
  }
}

final gameAudioProvider = Provider<GameAudio>((ref) {
  final audio = AudioplayersGameAudio();
  ref.onDispose(() => unawaited(audio.dispose()));
  return audio;
});
