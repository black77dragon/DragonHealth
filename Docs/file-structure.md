# iOS app repository file structure (v0.1)

This repository is organized to keep UI, domain logic, infrastructure, and resources separated for clarity and testability. It mirrors a clean layering approach suitable for an iOS native application built in Xcode and edited in VS Code.

## Top-level layout

```
DragonHealth/
├── App/                      # SwiftUI app entry, scenes, navigation, UI state
├── Core/                     # Domain models, use cases, pure Swift logic
│   └── DB/                   # Database gateway protocols + DB abstractions
├── Infra/                    # Implementation details (no UI)
│   ├── Config/               # Environment/config loading
│   ├── FeatureFlags/         # Runtime feature flag service
│   └── Logging/              # OSLog categories, sinks, redaction
├── Resources/                # Assets, localization, sample data, templates
├── Scripts/                  # Build, lint, db, and automation scripts
├── Tests/                    # Test targets, grouped by type
│   ├── Unit/
│   ├── Integration/
│   └── UI/
└── Docs/                     # Specifications and design docs
```

## Xcode project expectations

- Xcode project or Swift package manifests should live at the repository root.
- Groups in Xcode should map 1:1 to these folders to keep navigation consistent between Xcode and VS Code.

## Rules of separation

- App depends on Core and Infra.
- Core is pure logic with no UI or IO.
- Infra provides implementations for Core protocols (db, config, logging).
- Tests mirror the runtime structure and validate the critical flows.

## Next recommended docs

- Architecture overview (diagram + responsibilities)
- Data model specification (Core/DB-friendly)
- Feature flag registry and rollout plan
- Testing strategy and CI workflow
