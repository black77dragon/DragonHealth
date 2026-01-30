# DragonHealth

DragonHealth is a personal iOS health app focused on portion-based nutrition tracking, sports activity logging, and body metric trend analysis.

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
=======
Personal iOS nutrition tracker.

## Repository structure

This repository is organized for a clean separation between UI, domain, and infrastructure. See the detailed structure guide in `Docs/file-structure.md`.

- `App/`: SwiftUI entry point, navigation, presentation
- `Core/`: Domain models and use cases (pure Swift)
- `Core/DB/`: Database gateway protocols and abstractions
- `Infra/`: Config, logging, feature flags, and DB implementations
- `Resources/`: Assets and templates
- `Scripts/`: Automation scripts (setup, lint, migrations)
- `Tests/`: Unit, integration, and UI tests
- `Docs/`: Specifications and architecture docs

