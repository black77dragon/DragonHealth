# DragonHealth

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
