import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/game_art_frame.dart';
import '../../core/widgets/unit_avatar.dart';
import '../../shared/models/game_events.dart';
import 'match_controller.dart';
import 'match_found_transition.dart';

/// Loads the match while the encounter plays, and holds its last frame until
/// the destination has everything needed for its first useful paint.
class MatchEntryTransition extends ConsumerStatefulWidget {
  const MatchEntryTransition({
    super.key,
    required this.matchId,
    required this.leftName,
    required this.rightName,
    required this.onReady,
    this.title = 'พบคู่ต่อสู้!',
  });

  final String matchId;
  final String leftName;
  final String rightName;
  final String title;
  final VoidCallback onReady;

  @override
  ConsumerState<MatchEntryTransition> createState() =>
      _MatchEntryTransitionState();
}

class _MatchEntryTransitionState extends ConsumerState<MatchEntryTransition> {
  bool _animationDone = false;
  bool _artStarted = false;
  bool _artReady = false;
  bool _opening = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_artStarted) return;
    _artStarted = true;
    unawaited(_prepareArt());
  }

  Future<void> _prepareArt() async {
    await Future.wait([
      for (final path in {
        ...GameUiAssets.hud,
        ...GameBackgroundAssets.all,
        ...allUnitArtPaths,
      })
        precacheImage(AssetImage(path), context),
    ]);
    if (mounted) setState(() => _artReady = true);
  }

  @override
  Widget build(BuildContext context) {
    // Keep this auto-dispose controller alive through the route handoff.
    final view = ref.watch(matchControllerProvider(widget.matchId));
    final dataReady = !view.loading &&
        (view.phase?.phase != GamePhase.shopPlace || view.shop != null);
    if (_animationDone && _artReady && dataReady && !_opening) {
      _opening = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onReady();
      });
    }
    return MatchFoundTransition(
      leftName: widget.leftName,
      rightName: widget.rightName,
      title: widget.title,
      onCompleted: () => setState(() => _animationDone = true),
    );
  }
}
