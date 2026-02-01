import SwiftUI
import Core

struct CategoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var category: Core.Category
    @State private var ruleKind: TargetRuleKind
    @State private var ruleValue: Double
    @State private var rangeMin: Double
    @State private var rangeMax: Double

    init(category: Core.Category) {
        _category = State(initialValue: category)
        let details = TargetRuleKind.from(rule: category.targetRule)
        _ruleKind = State(initialValue: details.kind)
        _ruleValue = State(initialValue: details.value)
        _rangeMin = State(initialValue: details.rangeMin)
        _rangeMax = State(initialValue: details.rangeMax)
    }

    var body: some View {
        Form {
            TextField("Name", text: $category.name)
            TextField("Unit", text: $category.unitName)
            Toggle("Enabled", isOn: $category.isEnabled)
            Stepper(value: $category.sortOrder, in: 0...99) {
                Text("Order: \(category.sortOrder)")
            }

            Picker("Rule", selection: $ruleKind) {
                ForEach(TargetRuleKind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }

            switch ruleKind {
            case .exact, .atLeast, .atMost:
                HStack {
                    Text("Target")
                    Spacer()
                    TextField("0", value: $ruleValue, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            case .range:
                HStack {
                    Text("Min")
                    Spacer()
                    TextField("0", value: $rangeMin, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Max")
                    Spacer()
                    TextField("0", value: $rangeMax, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .navigationTitle(category.name)
        .toolbar {
            Button("Save") {
                category.targetRule = ruleKind.buildRule(value: ruleValue, min: rangeMin, max: rangeMax)
                Task {
                    await store.saveCategory(category)
                    await MainActor.run { dismiss() }
                }
            }
        }
    }
}

struct MealSlotDetailView: View {
    @EnvironmentObject private var store: AppStore
    @State private var mealSlot: MealSlot

    init(mealSlot: MealSlot) {
        _mealSlot = State(initialValue: mealSlot)
    }

    var body: some View {
        Form {
            TextField("Name", text: $mealSlot.name)
            Stepper(value: $mealSlot.sortOrder, in: 0...20) {
                Text("Order: \(mealSlot.sortOrder)")
            }
        }
        .navigationTitle(mealSlot.name)
        .toolbar {
            Button("Save") {
                Task { await store.saveMealSlot(mealSlot) }
            }
        }
    }
}

struct CategoryEditorSheet: View {
    let onSave: (Core.Category) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var unit = ""
    @State private var ruleKind: TargetRuleKind = .exact
    @State private var ruleValue: Double = 1
    @State private var rangeMin: Double = 1
    @State private var rangeMax: Double = 2
    @State private var isEnabled = true
    @State private var sortOrder = 0

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Unit", text: $unit)
                Toggle("Enabled", isOn: $isEnabled)
                Stepper(value: $sortOrder, in: 0...99) {
                    Text("Order: \(sortOrder)")
                }

                Picker("Rule", selection: $ruleKind) {
                    ForEach(TargetRuleKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }

                switch ruleKind {
                case .exact, .atLeast, .atMost:
                    HStack {
                        Text("Target")
                        Spacer()
                        TextField("0", value: $ruleValue, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                case .range:
                    HStack {
                        Text("Min")
                        Spacer()
                        TextField("0", value: $rangeMin, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Max")
                        Spacer()
                        TextField("0", value: $rangeMax, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle("New Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            Core.Category(
                                name: name,
                                unitName: unit,
                                isEnabled: isEnabled,
                                targetRule: ruleKind.buildRule(value: ruleValue, min: rangeMin, max: rangeMax),
                                sortOrder: sortOrder
                            )
                        )
                        dismiss()
                    }
                    .disabled(name.isEmpty || unit.isEmpty)
                }
            }
        }
    }
}

struct MealSlotEditorSheet: View {
    let onSave: (MealSlot) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var order = 0

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Stepper(value: $order, in: 0...20) {
                    Text("Order: \(order)")
                }
            }
            .navigationTitle("New Meal Slot")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(MealSlot(name: name, sortOrder: order))
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

enum TargetRuleKind: String, CaseIterable {
    case exact
    case atLeast
    case atMost
    case range

    var label: String {
        switch self {
        case .exact: return "Exact"
        case .atLeast: return "At Least"
        case .atMost: return "At Most"
        case .range: return "Range"
        }
    }

    static func from(rule: TargetRule) -> (kind: TargetRuleKind, value: Double, rangeMin: Double, rangeMax: Double) {
        switch rule {
        case .exact(let value):
            return (.exact, value, value, value)
        case .atLeast(let value):
            return (.atLeast, value, value, value)
        case .atMost(let value):
            return (.atMost, value, value, value)
        case .range(let min, let max):
            return (.range, min, min, max)
        }
    }

    func buildRule(value: Double, min: Double, max: Double) -> TargetRule {
        switch self {
        case .exact:
            return .exact(value)
        case .atLeast:
            return .atLeast(value)
        case .atMost:
            return .atMost(value)
        case .range:
            return .range(min: min, max: max)
        }
    }
}
