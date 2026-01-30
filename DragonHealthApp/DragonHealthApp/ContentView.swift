import SwiftUI
import InfraConfig
import InfraFeatureFlags
import InfraLogging

struct ContentView: View {
    let config: AppConfig
    let featureFlags: FeatureFlagService
    let logger: AppLogger

    var body: some View {
        HomeView(
            config: config,
            featureFlags: featureFlags,
            logger: logger
        )
    }
}

struct HomeView: View {
    let config: AppConfig
    let featureFlags: FeatureFlagService
    let logger: AppLogger

    private let quickActions: [QuickAction] = [
        QuickAction(title: "Add Portion", systemImage: "fork.knife"),
        QuickAction(title: "Log Workout", systemImage: "figure.run"),
        QuickAction(title: "Check-in", systemImage: "heart.text.square")
    ]

    private let metrics: [MetricCard] = [
        MetricCard(title: "Portions", value: "3", unit: "today", trend: "+1"),
        MetricCard(title: "Activity", value: "42", unit: "min", trend: "+12"),
        MetricCard(title: "Hydration", value: "1.6", unit: "L", trend: "+0.4"),
        MetricCard(title: "Sleep", value: "7.1", unit: "hrs", trend: "-0.3")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    StatusBannerView(
                        title: "DragonHealth iOS MVP",
                        subtitle: "Implementation in progress",
                        environmentName: config.environmentName
                    )

                    SectionHeaderView(title: "Quick Actions")
                    QuickActionsView(actions: quickActions) { action in
                        logger.info("quick_action", metadata: [
                            "action": action.title,
                            "environment": config.environmentName
                        ])
                    }

                    SectionHeaderView(title: "Today")
                    MetricsGridView(metrics: metrics)

                    SectionHeaderView(title: "Recent")
                    RecentActivityView(entries: [
                        "Portion target updated",
                        "Workout logged: 30 min",
                        "Body metrics check-in"
                    ])

                    EnvironmentFooterView(
                        schema: config.targetSchema,
                        flagsCount: featureFlags.allFlags().count
                    )
                }
                .padding(20)
            }
            .navigationTitle("DragonHealth")
        }
    }
}

private struct StatusBannerView: View {
    let title: String
    let subtitle: String
    let environmentName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(subtitle)
                .foregroundStyle(.secondary)
            Text("Env: \(environmentName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("DragonHealth MVP status")
    }
}

private struct SectionHeaderView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuickActionsView: View {
    let actions: [QuickAction]
    let onTap: (QuickAction) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(actions) { action in
                Button {
                    onTap(action)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: action.systemImage)
                            .font(.title2)
                        Text(action.title)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MetricsGridView: View {
    let metrics: [MetricCard]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 6) {
                    Text(metric.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(metric.value)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text(metric.unit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Trend: \(metric.trend)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.secondarySystemBackground))
                )
            }
        }
    }
}

private struct RecentActivityView: View {
    let entries: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(entries, id: \.self) { entry in
                HStack(spacing: 10) {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text(entry)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
            }
        }
    }
}

private struct EnvironmentFooterView: View {
    let schema: Int
    let flagsCount: Int

    var body: some View {
        Text("Schema v\(schema) • Flags \(flagsCount)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

private struct QuickAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
}

private struct MetricCard: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let unit: String
    let trend: String
}

#Preview {
    ContentView(
        config: AppConfig.defaultValue,
        featureFlags: InMemoryFeatureFlagService(flags: []),
        logger: AppLogger(category: .appUI)
    )
}
