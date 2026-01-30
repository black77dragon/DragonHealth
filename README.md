# DragonHealth

DragonHealth is a personal iOS health app focused on portion-based nutrition tracking, sports activity logging, and body metric trend analysis.

## Documentation

- Architecture: [docs/architecture.md](docs/architecture.md)
- Navigation and view hierarchy: [docs/architecture/navigation.md](docs/architecture/navigation.md)
- Repository structure: [Docs/file-structure.md](Docs/file-structure.md)

## Run in Xcode

1. Open `DragonHealthApp/DragonHealthApp.xcodeproj`.
2. If Xcode prompts for missing package dependencies, add the local package at the repo root (`/Users/renekeller/Projects/Dragonhealth`).
3. Select the `DragonHealthApp` scheme and an iOS Simulator.
4. Build and run with `⌘R`.

## Product Specification

The product specification is the source of truth for requirements and implementation decisions. It is stored as versioned Markdown in `docs/specs/` so it can be reviewed, diffed, and referenced alongside the codebase.

- Current spec: `docs/specs/dragonhealth-ios-spec-v0.1.md`

## Repository Structure

- `docs/specs/` - versioned product specifications and requirements

## Contribution Workflow

1. Update or add a spec in `docs/specs/` when requirements change.
2. Reference the relevant spec section in implementation PRs.
3. Keep specs versioned and append new versions rather than overwriting prior releases.

## Status

Early specification phase; implementation has not started.
