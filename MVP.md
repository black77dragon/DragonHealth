# DragonHealth MVP

## Purpose

Define the minimum viable product scope and the current implementation for the first executable iOS build.

## MVP Scope (implemented)
- Today screen with daily adherence summary, category progress, per-meal summaries, and Quick Add logging (meal + category + portion).
- History screen read-only with graphical day picker and per-category totals.
- Body metrics screen with 7-day rolling averages and a log of entries.
- Library screen for food list, category mapping, favorites, and notes.
- Settings for categories, meal slots, targets, day cutoff time, and iCloud backup status/manual backup.
- On-device SQLite storage only (no accounts, no server); optional iCloud backup.

## Explicitly out of scope for MVP
- iCloud sync (backup only), PDF export, Apple Health, notifications, widgets, meal photos, recipes, streaks, charts/heatmaps.

## UX rules
- Fast logging via Quick Add.
- Daily totals determine success; per-meal guidance is not implemented.
- Exact targets allow +/- 0.25 tolerance.
- Day cutoff default is 04:00; late-night entries count toward the previous day.
- Portion picker for logging uses 0.5 increments (0 to 6); stored portions round to 0.25.

## Implementation status
- Core domain models, target rules, day boundary, and 7-day averages implemented in Core.
- SQLite schema and migrations seeded with defaults.
- SwiftUI views for Today, History, Body, Library, and Settings complete.
- iCloud backup scheduler and manual backup flow wired into Settings.

## Acceptance tests (current build)
- Log a meal via Quick Add and see Today totals/adherence update.
- Change the day picker in History and see per-category totals update.
- Save a body metric entry and see it in the list and 7-day averages.
- Add, favorite, and delete food items in the Library.
- Change day cutoff and verify the current day boundary shifts.
- Run a manual iCloud backup when iCloud is available.

## Feature flag assessment
- Feature flag infrastructure exists; no user-facing flags are active yet.
