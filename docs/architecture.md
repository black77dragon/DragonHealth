# DragonHealth Architecture

## Assumptions and Scope
- iOS 17+
- SwiftUI
- SQLite persistence via Core/DB gateway and a single DatabaseActor
- No backend
- Single user
- Feature growth likely (HealthKit, widgets, rules engine)

## Recommended Architecture: MVVM + Domain Services

High-level structure:

UI (SwiftUI Views)
  -> ViewModels (state + intent)
  -> Domain Layer (rules and calculations)
  -> Persistence (SQLite via Core/DB + Infra)

This is a pragmatic, SwiftUI-native architecture that is testable and resists "fat ViewModel" drift.

## Why This Fits DragonHealth

- Offline-first: clear boundaries for domain rules and storage.
- Rule-heavy (targets, banking, tolerance): needs a Domain layer.
- SwiftUI: MVVM is native.
- Single-user: no session or multi-user context.
- Long-lived data: SQLite storage remains local and predictable.

## Core Layers

### UI Layer (SwiftUI Views)

Responsibilities:
- Rendering
- Navigation
- User input only

Rules:
- No calculations
- No business logic
- No persistence access
- Bind to @Observable ViewModels

Example:

struct MealDetailView: View {
    @Bindable var vm: MealDetailViewModel
}

### ViewModels (State + Intent)

Responsibilities:
- Own UI state
- Translate user actions into domain calls
- Prepare display-ready data

Allowed:
- Formatting
- Aggregation
- Simple conditionals

Forbidden:
- Target evaluation
- Portion math
- Streak logic

Example:

@Observable
final class MealDetailViewModel {
    let meal: MealSlot
    let domain: PortionEngine

    func addPortion(category: Category, amount: Double) {
        domain.addPortion(meal, category, amount)
    }
}

### Domain Layer (Most Important)

Core domain services:

Core/
- PortionEngine
- TargetEvaluator
- AdherenceEngine
- StreakEngine
- BodyTrendCalculator

These are pure Swift types:
- No SwiftUI
- No database access
- No environment dependencies

Example:

struct TargetEvaluator {
    func evaluate(
        actual: Double,
        rule: TargetRule
    ) -> TargetResult
}

Why this matters:
- Rules are testable
- Future-proof (HealthKit, widgets)
- Avoids logic duplication across screens

### Persistence Layer (SQLite)

SQLite is storage, not architecture.

Rules:
- Models are dumb
- No logic inside models
- Relationships explicit

Example:

struct DayLog {
    var date: Date
    var meals: [MealEntry]
}

Do not put computed properties like:
- isOnTarget
- totalProtein

Those belong in Domain.

## Concrete Module Layout (Recommended)

DragonHealth/
- App/
  - DragonHealthApp.swift
- Core/
  - PortionEngine.swift
  - TargetRule.swift
  - TargetEvaluator.swift
  - AdherenceEngine.swift
  - StreakEngine.swift
  - BodyTrendCalculator.swift
- Core/DB/
  - DBGateway.swift
  - DatabaseActor.swift
- Infra/
  - Logging/
  - Config/
  - FeatureFlags/
- Resources/
  - Assets/
  - Templates/
- Tests/
  - Unit/
  - Integration/
  - UI/

## Data Flow Example

"Add 1/4 protein at dinner"

MealDetailView
  -> MealDetailViewModel.addPortion()
  -> PortionEngine.addPortion()
  -> DatabaseActor mutation
  -> TargetEvaluator recompute
  -> AdherenceEngine recompute
  -> UI updates automatically

No circular dependencies.
No global state.
No view-to-view coupling.

## Key Architectural Decisions

1. Domain purity
   - Domain services must be pure Swift.
   - Testable and reusable.

2. Persistence access strategy
   - ViewModels call Core domain services.
   - Core uses Core/DB gateways backed by Infra implementations.

3. Global state vs scoped ViewModels
   - One ViewModel per screen.
   - Shared Domain services injected.
   - Avoid massive AppState and environment objects everywhere.

4. Date handling
   - Centralize day-boundary logic.

protocol DateProvider {
    func currentDay() -> Date
}

## Architecture Options Not Recommended

- Massive MVVM
  - ViewModels become god objects.
  - Logic duplicated across screens.

- Clean Architecture (Entities / UseCases / Repos)
  - Too heavy.
  - Slows iteration.
  - No backend benefit.

- Redux / TCA
  - Overkill.
  - Steep mental load.
  - Not justified for single-user offline app.

## Minimal ASCII Architecture Diagram

SwiftUI Views
  |
  v
ViewModels
  |
  v
Domain Services
  |
  v
SQLite
