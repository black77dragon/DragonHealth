import SwiftUI

private enum DailyHubSection: String, CaseIterable, Identifiable {
    case today
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return "Today"
        case .history:
            return "History"
        }
    }
}

struct DailyHubView: View {
    @AppStorage("dailyHub.selectedSection") private var selectedSectionRaw: String = DailyHubSection.today.rawValue

    private var selectedSection: DailyHubSection {
        DailyHubSection(rawValue: selectedSectionRaw) ?? .today
    }

    var body: some View {
        content
            .navigationTitle("Journal")
            .safeAreaInset(edge: .top) {
                sectionPicker
            }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedSection {
        case .today:
            TodayView()
        case .history:
            HistoryView()
        }
    }

    private var sectionPicker: some View {
        VStack(spacing: 0) {
            Picker("Journal section", selection: Binding(
                get: { selectedSection },
                set: { selectedSectionRaw = $0.rawValue }
            )) {
                ForEach(DailyHubSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)

            Divider()
        }
        .background(ZenStyle.pageBackground)
    }
}
