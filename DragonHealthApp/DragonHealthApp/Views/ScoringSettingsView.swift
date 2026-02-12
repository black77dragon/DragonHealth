import SwiftUI
import Core

struct ScoringSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingAddRule = false
    @State private var showingInfo = false

    private var categories: [Core.Category] {
        store.categories.filter { $0.isEnabled }
    }

    var body: some View {
        Form {
            Section("Daily Score") {
                Text("Adjust weights, penalties, and optional compensation rules.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Category Scoring") {
                if categories.isEmpty {
                    Text("No categories available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(categories) { category in
                        NavigationLink {
                            CategoryScoreProfileView(category: category)
                        } label: {
                            CategoryScoreRow(
                                category: category,
                                profile: store.scoreProfiles[category.id]
                            )
                        }
                    }
                }
            }

            Section("Compensation Rules") {
                if store.compensationRules.isEmpty {
                    Text("No compensation rules yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.compensationRules, id: \.self) { rule in
                        NavigationLink {
                            CompensationRuleDetailView(rule: rule)
                        } label: {
                            CompensationRuleRow(
                                rule: rule,
                                fromName: categoryName(rule.fromCategoryID),
                                toName: categoryName(rule.toCategoryID)
                            )
                        }
                    }
                    .onDelete { indices in
                        for index in indices {
                            guard index < store.compensationRules.count else { continue }
                            let rule = store.compensationRules[index]
                            Task { await store.deleteCompensationRule(rule) }
                        }
                    }
                }

                Button {
                    showingAddRule = true
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .glassButton(.text)
                .disabled(categories.count < 2)
            }
        }
        .navigationTitle("Scoring")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingInfo = true
                } label: {
                    Image(systemName: "info.circle.fill")
                        .glassLabel(.icon)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scoring help")
            }
        }
        .sheet(isPresented: $showingAddRule) {
            CompensationRuleEditorSheet(categories: categories) { rule in
                Task { await store.saveCompensationRule(rule) }
            }
        }
        .sheet(isPresented: $showingInfo) {
            ScoringInfoSheet()
        }
    }

    private func categoryName(_ id: UUID) -> String {
        store.categories.first(where: { $0.id == id })?.name ?? "Unknown"
    }
}

private struct ScoringInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Score Basics") {
                    Text("Daily Score is a weighted average of all enabled categories (0 to 100).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Weight") {
                    Text("Higher weight means the category has a bigger impact on the daily score.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Penalties") {
                    Text("Under penalty applies when you are below the target range. Over penalty applies when you exceed the target range.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Soft Limits") {
                    Text("Soft limit is how far you can deviate before the score drops significantly. Smaller values are stricter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Curve") {
                    Text("Linear reduces score steadily. Quadratic reduces score more sharply as you move further away.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Cap Over at Target") {
                    Text("When enabled, going over the target does not reduce the score.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Compensation Rules") {
                    Text("Allow one category to offset another. Example: extra Sports minutes can offset Treats overage.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Scoring Help")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .glassButton(.text)
                }
            }
        }
    }
}

private struct CategoryScoreRow: View {
    let category: Core.Category
    let profile: Core.ScoreProfile?

    var body: some View {
        let effectiveProfile = profile ?? Core.ScoreProfile.defaultProfile(for: category)
        VStack(alignment: .leading, spacing: 4) {
            Text(category.name)
            Text("Weight \(effectiveProfile.weight.cleanNumber) | Under \(effectiveProfile.underPenaltyPerUnit.cleanNumber) | Over \(effectiveProfile.overPenaltyPerUnit.cleanNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CategoryScoreProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    let category: Core.Category
    @State private var profile: Core.ScoreProfile

    init(category: Core.Category) {
        self.category = category
        _profile = State(initialValue: Core.ScoreProfile.defaultProfile(for: category))
    }

    @State private var usesCustomProfile = false

    var body: some View {
        Form {
            Section("Target") {
                Text(category.targetRule.displayText(unit: category.unitName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Use Custom Profile", isOn: $usesCustomProfile)
            }

            Section("Weight") {
                HStack {
                    Text("Weight")
                    Spacer()
                    Text(profile.weight.cleanNumber)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $profile.weight, in: 0...2, step: 0.05)
            }
            .disabled(!usesCustomProfile)

            Section("Penalties") {
                Stepper(value: $profile.underPenaltyPerUnit, in: 0...3, step: 0.1) {
                    Text("Under Penalty: \(profile.underPenaltyPerUnit.cleanNumber)")
                }
                Stepper(value: $profile.overPenaltyPerUnit, in: 0...3, step: 0.1) {
                    Text("Over Penalty: \(profile.overPenaltyPerUnit.cleanNumber)")
                }
            }
            .disabled(!usesCustomProfile)

            Section("Soft Limits") {
                Stepper(value: $profile.underSoftLimit, in: 0.1...60, step: 0.1) {
                    Text("Under Soft Limit: \(profile.underSoftLimit.cleanNumber)")
                }
                Stepper(value: $profile.overSoftLimit, in: 0.1...60, step: 0.1) {
                    Text("Over Soft Limit: \(profile.overSoftLimit.cleanNumber)")
                }
            }
            .disabled(!usesCustomProfile)

            Section("Curve") {
                Picker("Curve", selection: $profile.curve) {
                    Text("Linear").tag(Core.ScoreCurve.linear)
                    Text("Quadratic").tag(Core.ScoreCurve.quadratic)
                }
                .pickerStyle(.segmented)
            }
            .disabled(!usesCustomProfile)

            Section("Overage") {
                Toggle("Cap Over at Target", isOn: $profile.capOverAtTarget)
            }
            .disabled(!usesCustomProfile)

            Section {
                Button(role: .destructive) {
                    Task {
                        await store.deleteScoreProfile(categoryID: category.id)
                        profile = Core.ScoreProfile.defaultProfile(for: category)
                        usesCustomProfile = false
                    }
                } label: {
                    Text("Reset to Default")
                }
                .glassButton(.text)
                .disabled(!usesCustomProfile)
            }
        }
        .navigationTitle(category.name)
        .onAppear {
            if let stored = store.scoreProfiles[category.id] {
                profile = stored
                usesCustomProfile = true
            } else {
                profile = Core.ScoreProfile.defaultProfile(for: category)
                usesCustomProfile = false
            }
        }
        .onChange(of: usesCustomProfile) { _, newValue in
            if !newValue {
                profile = Core.ScoreProfile.defaultProfile(for: category)
            }
        }
        .toolbar {
            Button("Save") {
                Task {
                    if usesCustomProfile {
                        await store.saveScoreProfile(categoryID: category.id, profile: profile)
                    } else {
                        await store.deleteScoreProfile(categoryID: category.id)
                    }
                    await MainActor.run { dismiss() }
                }
            }
            .glassButton(.text)
        }
    }
}

private struct CompensationRuleRow: View {
    let rule: Core.CompensationRule
    let fromName: String
    let toName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(fromName) -> \(toName)")
            Text("Ratio \(rule.ratio.cleanNumber) | Max \(rule.maxOffset.cleanNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CompensationRuleDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    let rule: Core.CompensationRule
    @State private var ratio: Double
    @State private var maxOffset: Double

    init(rule: Core.CompensationRule) {
        self.rule = rule
        _ratio = State(initialValue: rule.ratio)
        _maxOffset = State(initialValue: rule.maxOffset)
    }

    var body: some View {
        Form {
            Section("Rule") {
                Text("From: \(categoryName(rule.fromCategoryID))")
                Text("To: \(categoryName(rule.toCategoryID))")
            }
            Section("Settings") {
                Stepper(value: $ratio, in: 0.5...120, step: 0.5) {
                    Text("Ratio: \(ratio.cleanNumber)")
                }
                Stepper(value: $maxOffset, in: 0...10, step: 0.5) {
                    Text("Max Offset: \(maxOffset.cleanNumber)")
                }
            }
        }
        .navigationTitle("Compensation")
        .toolbar {
            Button("Save") {
                Task {
                    let updated = Core.CompensationRule(
                        fromCategoryID: rule.fromCategoryID,
                        toCategoryID: rule.toCategoryID,
                        ratio: ratio,
                        maxOffset: maxOffset
                    )
                    await store.saveCompensationRule(updated)
                    await MainActor.run { dismiss() }
                }
            }
            .glassButton(.text)
        }
    }

    private func categoryName(_ id: UUID) -> String {
        store.categories.first(where: { $0.id == id })?.name ?? "Unknown"
    }
}

private struct CompensationRuleEditorSheet: View {
    let categories: [Core.Category]
    let onSave: (Core.CompensationRule) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fromCategoryID: UUID
    @State private var toCategoryID: UUID
    @State private var ratio: Double = 1
    @State private var maxOffset: Double = 1

    init(categories: [Core.Category], onSave: @escaping (Core.CompensationRule) -> Void) {
        self.categories = categories
        self.onSave = onSave
        let from = categories.first?.id ?? UUID()
        let to = categories.dropFirst().first?.id ?? from
        _fromCategoryID = State(initialValue: from)
        _toCategoryID = State(initialValue: to)
    }

    var body: some View {
        NavigationStack {
            Form {
                if categories.count < 2 {
                    Text("Add at least two categories to create a rule.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("From", selection: $fromCategoryID) {
                        ForEach(categories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                    Picker("To", selection: $toCategoryID) {
                        ForEach(categories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                    Stepper(value: $ratio, in: 0.5...120, step: 0.5) {
                        Text("Ratio: \(ratio.cleanNumber)")
                    }
                    Stepper(value: $maxOffset, in: 0...10, step: 0.5) {
                        Text("Max Offset: \(maxOffset.cleanNumber)")
                    }
                }
            }
            .navigationTitle("New Rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .glassButton(.text)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            Core.CompensationRule(
                                fromCategoryID: fromCategoryID,
                                toCategoryID: toCategoryID,
                                ratio: ratio,
                                maxOffset: maxOffset
                            )
                        )
                        dismiss()
                    }
                    .glassButton(.text)
                    .disabled(categories.count < 2 || fromCategoryID == toCategoryID)
                }
            }
        }
    }
}
