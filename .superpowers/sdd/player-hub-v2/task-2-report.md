# Task 2 report — Shared V2 shell and exact Profile hierarchy

## Status

Completed Task 2 only. No Leaderboard or Room route/screen was added, and no
backend or WebSocket code was changed. The implementation commit is
`a5e4bd43fd89b9a59ed513e197dd6b23c9d0c66a` (`feat(profile): match Player Hub V2 layout`).

## Changed files

- `mobile/lib/features/player_hub/player_hub_shell.dart`
  - Added the reusable arena-backed shell: V2 header, title/subtitle, account
    badge slot, scrollable body slot, and navigation slot.
- `mobile/lib/features/player_hub/player_crest.dart`
  - Added the reusable gold player crest with normal and compact sizing.
- `mobile/lib/features/profile/profile_screen.dart`
  - Refactored Profile to use `PlayerHubShell` and `PlayerCrest`.
  - Preserved account fetching/editing, stats API handling, settings controls,
    and confirmation-based sign out.
  - Reordered the visible content to the V2 hierarchy: identity rail, match
    record/HUD, rank banner and `/leaderboard` CTA, history panel and
    `/history` CTA, private-account/sign-out row, then settings.
  - Retains a two-column desktop layout and stacked narrow layout.
- `mobile/test/features/profile/profile_screen_test.dart`
  - Added V2 hierarchy assertions, CTA destination interaction coverage, and
    narrow long-identity coverage; updated the retained theme-control test to
    scroll the control into view after the V2 sections were added.

## TDD record

1. Added `shows the V2 rank, history, and private-account hierarchy` before
   the corresponding UI existed.
2. Verified RED with the focused Profile test: it failed as expected because
   `ดูตารางอันดับ` was absent.
3. Implemented the shared shell/crest and Profile hierarchy, then verified
   GREEN with focused Profile tests.
4. Added interaction coverage that exercises real GoRouter test destinations
   for `/leaderboard` and `/history`, plus the long username/email responsive
   case. Existing profile behaviour tests continue to cover stats, errors,
   settings, and logout.

## Command results

- `rtk flutter test test/features/profile/profile_screen_test.dart --no-pub --reporter compact`
  - RED: one expected failure (`ดูตารางอันดับ` absent).
  - Final GREEN: 14 Profile tests passed.
- `rtk flutter test --no-pub --reporter compact`
  - Passed: 203 tests.
- `rtk git diff --check`
  - Passed: no whitespace errors.
- `rtk flutter analyze`
  - No Task 2 diagnostics. It reports 8 existing `prefer_const_constructors`
    info diagnostics in Task 1's
    `mobile/lib/features/player_hub/player_hub_fixture_provider.dart` lines
    8–16; that file was intentionally outside this task's scope.

## Concerns

- Static analysis is not fully clean because of the eight pre-existing Task 1
  info diagnostics described above. They are not caused by this task and were
  left untouched to preserve the task boundary.
- The Profile CTAs deliberately target string routes only. Their destination
  screens/routes are reserved for later tasks, as required.
