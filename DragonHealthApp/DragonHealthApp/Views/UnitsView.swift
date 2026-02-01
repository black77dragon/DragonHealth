import SwiftUI
import Core

struct UnitsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingAdd = false
    @State private var editingUnit: FoodUnit?

    var body: some View {
        List {
            Section("Units") {
                if store.units.isEmpty {
                    Text("No units yet. Add units to use for food portions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.units) { unit in
                        UnitRow(unit: unit)
                            .contentShape(Rectangle())
                            .onTapGesture { editingUnit = unit }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(unit.isEnabled ? "Disable" : "Enable") {
                                    var updated = unit
                                    updated.isEnabled.toggle()
                                    Task { await store.saveUnit(updated) }
                                }
                                .tint(unit.isEnabled ? .orange : .green)
                            }
                    }
                }
            }
        }
        .navigationTitle("Units")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add Unit", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            UnitEditorSheet { unit in
                Task { await store.saveUnit(unit) }
            }
        }
        .sheet(item: $editingUnit) { unit in
            UnitDetailView(unit: unit)
        }
    }
}

private struct UnitRow: View {
    let unit: FoodUnit

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(unit.name)
                    .font(.subheadline)
                Text(unit.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !unit.isEnabled {
                Text("Disabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct UnitDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var unit: FoodUnit

    init(unit: FoodUnit) {
        _unit = State(initialValue: unit)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $unit.name)
                TextField("Symbol", text: $unit.symbol)
                Toggle("Allows Decimals", isOn: $unit.allowsDecimal)
                Toggle("Enabled", isOn: $unit.isEnabled)
                Stepper(value: $unit.sortOrder, in: 0...99) {
                    Text("Order: \(unit.sortOrder)")
                }
            }
            .navigationTitle(unit.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await store.saveUnit(unit)
                            await MainActor.run { dismiss() }
                        }
                    }
                }
            }
        }
    }
}

private struct UnitEditorSheet: View {
    let onSave: (FoodUnit) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = ""
    @State private var allowsDecimal = true
    @State private var isEnabled = true
    @State private var sortOrder = 0

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Symbol", text: $symbol)
                Toggle("Allows Decimals", isOn: $allowsDecimal)
                Toggle("Enabled", isOn: $isEnabled)
                Stepper(value: $sortOrder, in: 0...99) {
                    Text("Order: \(sortOrder)")
                }
            }
            .navigationTitle("New Unit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            FoodUnit(
                                name: name,
                                symbol: symbol,
                                allowsDecimal: allowsDecimal,
                                isEnabled: isEnabled,
                                sortOrder: sortOrder
                            )
                        )
                        dismiss()
                    }
                    .disabled(name.isEmpty || symbol.isEmpty)
                }
            }
        }
    }
}
