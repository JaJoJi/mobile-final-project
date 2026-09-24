/// Converts the server's zero-based fusion tier into the one-based star level
/// shown to players.
///
/// The websocket contract and combat rules deliberately continue to use
/// `0..2`. UI code must go through this function instead of displaying a raw
/// tier, so changing the presentation cannot change fusion or combat logic.
int displayStarLevel(int fusionTier) {
  assert(
    fusionTier >= 0 && fusionTier <= 2,
    'fusionTier must follow the server contract (0..2)',
  );
  return fusionTier.clamp(0, 2) + 1;
}
