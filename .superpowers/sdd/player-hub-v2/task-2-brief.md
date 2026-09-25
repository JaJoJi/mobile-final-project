# Task 2 brief — Shared V2 shell and exact Profile hierarchy

Implement only Task 2 in the approved plan. Create a reusable
`PlayerHubShell` and `PlayerCrest` under `mobile/lib/features/player_hub/`.
Refactor `mobile/lib/features/profile/profile_screen.dart` and its
navigation to use the shell without changing existing account editing,
settings, logout, or profile stats API behavior.

The required V2 visible order is: top header `โปรไฟล์ผู้บัญชาการ` with
subtitle and account badge; identity rail with crest, username, email,
rating, rating label and edit action; `บันทึกการประลอง`; HUD stats; rank
banner with `ดูตารางอันดับ` CTA targeting `/leaderboard`; history panel
headed `ทุกแมตช์คือประสบการณ์` with CTA targeting `/history`; private account
row `ข้อมูลบัญชีเป็นส่วนตัว` and sign-out action; then settings panel as
subordinate preserved app behavior. Desktop is two columns; narrow screens
stack. Use arena V2 background and current V2 shell styling. Preserve
semantic labels and no overflow at 360x640/text scale 2.0. Move shared
presentation from Profile rather than duplicate it.

Update Profile widget tests first to assert the five V2 elements above,
long username/email behavior, all retained profile behaviors, and responsive
render. Do not add router or leaderboard screen in this task; only navigate
to its string route. Run focused profile tests, flutter analyze, and commit
with `feat(profile): match Player Hub V2 layout`. Do not push. Write detailed
report to `.superpowers/sdd/player-hub-v2/task-2-report.md`.
