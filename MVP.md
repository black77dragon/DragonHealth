# DragonHealth MVP

## Purpose
Define the minimum viable product scope and the initial implementation plan for the first executable macOS build.

## Scope (confirmed)
- Today screen with single quick-add logging flow and meal picker.
- History screen read-only (calendar + daily summary).
- Body metrics screen with 7-day rolling averages for all metrics.
- Library screen for food list, category mapping, and favorites.
- Settings for categories, meal slots, targets, and day cutoff time.
- On-device SQLite storage only (no accounts, no server).

## Explicitly out of scope for MVP
- iCloud sync, PDF export, Apple Health, notifications, widgets, meal photos, recipes.

## UX rules
- Fast logging in under 10 seconds per meal.
- Daily totals determine success; meal targets are guidance only.
- Exact targets allow +/- 0.25 tolerance.
- Day cutoff default is 04:00; late-night entries count toward the previous day.

## Initial implementation milestones
1) SwiftPM scaffolding and baseline App/Core/Infra targets.
2) Core domain models and rule evaluation with unit tests.
3) SQLite schema and migrations (dbmate), seeded defaults.
4) App UI shells for Today/History/Body/Library/Settings.
5) Integration tests for DB and UI smoke tests.

## Acceptance tests (MVP)
- Log a meal via single quick-add with meal picker and see totals update.
- Daily adherence computed from totals only; per-meal guidance does not block success.
- Exact target tolerance of +/-0.25 is honored.
- History screen is read-only with calendar and daily summaries.
- Body metrics show 7-day averages for all metrics.

## Feature flag assessment
- No risky changes implemented yet. Future schema migrations and new workflows require a feature flag.
