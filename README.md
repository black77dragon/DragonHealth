# DragonHealth

DragonHealth is a personal iOS health app focused on portion-based nutrition tracking, sports activity logging, and body metric trend analysis.

## Author

Rene W. Keller

## Stoic Quote (Proposed)

“Serenity grows when we accept what is, and devote our will to what can be done.”

## Documentation

- Architecture: [Docs/architecture.md](Docs/architecture.md)
- Navigation and view hierarchy: [Docs/architecture/navigation.md](Docs/architecture/navigation.md)
- Repository structure: [Docs/file-structure.md](Docs/file-structure.md)

## Current Features

- Today dashboard with adherence summary, category overview, per-meal breakdowns, and configurable display styles.
- Quick Add logging with meal slot, category, portion wheel (0.25 increments), notes, and food library prefills (defaults filter to selected category).
- History day picker with adherence summary, per-meal entries, and per-category totals.
- Body metrics logging with 7-day averages, charts, steps tracking, and Apple Health sync.
- Food library with favorites, photos, portion equivalents, and notes (used in Quick Add).
- Documents library for PDFs and images with import, preview, and delete.
- Profile and care details (photo, height, target weight, motivation, doctor/nutritionist names).
- Category and meal slot management with target rule editing.
- Manage hub for day boundary, categories, meal slots, backup/restore, Apple Health sync, documents, and care meetings.
- On-device SQLite storage with optional iCloud backups (no accounts or servers).

## Run in Xcode

1. Open `DragonHealthApp/DragonHealthApp.xcodeproj`.
2. If Xcode prompts for missing package dependencies, add the local package at the repo root (`/Users/renekeller/Projects/Dragonhealth`).
3. Select the `DragonHealthApp` scheme and an iOS Simulator.
4. Build and run with `⌘R`.

### Unsplash Photo Search

Food photo search uses the Unsplash API. Set the access key in `DragonHealthApp/Info.plist` under `UNSPLASH_ACCESS_KEY`.

## Product Specification

The product specification is the source of truth for requirements and implementation decisions. It is stored as versioned Markdown in `Docs/specs/` so it can be reviewed, diffed, and referenced alongside the codebase.

- Current spec: `Docs/specs/dragonhealth-ios-spec-v0.3.md`

## Repository Structure

- `Docs/specs/` - versioned product specifications and requirements

## Contribution Workflow

1. Update or add a spec in `Docs/specs/` when requirements change.
2. Reference the relevant spec section in implementation PRs.
3. Keep specs versioned and append new versions rather than overwriting prior releases.

## Status

MVP implemented with local storage, configurable tracking, iCloud backup/restore, Apple Health read-only sync, document storage, and care team notes. Export, iCloud device sync (beyond backups), notifications, widgets, and streak analytics are not yet implemented.
