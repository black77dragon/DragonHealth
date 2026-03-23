import SwiftUI
import Combine
import Core
import UserNotifications

private extension NightGuardStatus {
    var title: String {
        switch self {
        case .pending:
            return "Awaiting check-in"
        case .compliant:
            return "Kitchen closed successfully"
        case .violation:
            return "Late eating logged"
        case .proteinException:
            return "Recovery snack used"
        }
    }

    var subtitle: String {
        switch self {
        case .pending:
            return "No final update saved for this night yet."
        case .compliant:
            return "You finished the evening without reopening the kitchen."
        case .violation:
            return "A late eating moment was recorded."
        case .proteinException:
            return "A planned protein-based recovery step was used."
        }
    }

    var icon: String {
        switch self {
        case .pending:
            return "clock"
        case .compliant:
            return "checkmark.circle.fill"
        case .violation:
            return "xmark.circle.fill"
        case .proteinException:
            return "bolt.heart.fill"
        }
    }

    var tint: Color {
        switch self {
        case .pending:
            return .blue
        case .compliant:
            return .green
        case .violation:
            return .red
        case .proteinException:
            return .orange
        }
    }
}

private enum NightGuardPhase {
    case preCommit
    case closure
    case locked

    var title: String {
        switch self {
        case .preCommit:
            return "Set up tonight"
        case .closure:
            return "Close the kitchen"
        case .locked:
            return "Kitchen Closed"
        }
    }

    var message: String {
        switch self {
        case .preCommit:
            return "The easiest moment to protect tonight is before cravings show up."
        case .closure:
            return "Finish the evening ritual now so the rest of the night feels settled."
        case .locked:
            return "If the pull to eat shows up, slow the moment down and use the recovery plan."
        }
    }
}

private struct NightGuardReminderConfig {
    let enabled: Bool
    let kitchenCloseMinutes: Int
    let ritualLeadMinutes: Int
    let morningCheckMinutes: Int
}

private enum NightGuardNoteUpdate {
    case keep
    case set(String?)
}

@MainActor
private final class NightGuardReminderManager: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var scheduleMessage: String?

    private let center = UNUserNotificationCenter.current()
    private let reminderIDs = [
        "nightguard.ritual",
        "nightguard.close",
        "nightguard.recovery",
        "nightguard.morning"
    ]

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestPermissionIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            scheduleMessage = "Notifications are disabled. Enable them in iOS Settings."
            return false
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                await refreshAuthorizationStatus()
                if !granted {
                    scheduleMessage = "Reminder permission was not granted."
                }
                return granted
            } catch {
                scheduleMessage = "Reminder permission failed: \(error.localizedDescription)"
                return false
            }
        @unknown default:
            return false
        }
    }

    func applySchedule(config: NightGuardReminderConfig) async {
        center.removePendingNotificationRequests(withIdentifiers: reminderIDs)
        guard config.enabled else {
            scheduleMessage = "Reminders are off."
            return
        }
        let granted = await requestPermissionIfNeeded()
        guard granted else { return }

        let ritualMinutes = normalizeMinutes(config.kitchenCloseMinutes - config.ritualLeadMinutes)
        let recoveryMinutes = normalizeMinutes(config.kitchenCloseMinutes + 75)

        do {
            try await scheduleDaily(
                identifier: "nightguard.ritual",
                minuteOfDay: ritualMinutes,
                title: "Night Guard",
                body: "Closure ritual starts now. Brush, tea or water, lights off."
            )
            try await scheduleDaily(
                identifier: "nightguard.close",
                minuteOfDay: config.kitchenCloseMinutes,
                title: "Night Guard",
                body: "Kitchen is closed. Water or unsweetened tea only."
            )
            try await scheduleDaily(
                identifier: "nightguard.recovery",
                minuteOfDay: recoveryMinutes,
                title: "Night Guard",
                body: "Craving protocol: water, wait 10 minutes, redirect."
            )
            try await scheduleDaily(
                identifier: "nightguard.morning",
                minuteOfDay: config.morningCheckMinutes,
                title: "Night Guard",
                body: "Quick check-in: did you respect last night's rule?"
            )
            scheduleMessage = "Reminders scheduled."
        } catch {
            scheduleMessage = "Failed to schedule reminders: \(error.localizedDescription)"
        }
    }

    private func scheduleDaily(
        identifier: String,
        minuteOfDay: Int,
        title: String,
        body: String
    ) async throws {
        let clamped = normalizeMinutes(minuteOfDay)
        var components = DateComponents()
        components.hour = clamped / 60
        components.minute = clamped % 60

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await center.add(request)
    }

    private func normalizeMinutes(_ value: Int) -> Int {
        ((value % 1440) + 1440) % 1440
    }
}

private struct NightGuardHeroMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .zenMetricLabel()
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ZenStyle.surface)
        )
    }
}

private struct NightGuardDisclosureCard<Content: View>: View {
    let title: String
    let subtitle: String
    @Binding var isExpanded: Bool
    let content: Content

    init(
        title: String,
        subtitle: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 16 : 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .zenSectionTitle()
                        Text(subtitle)
                            .zenSupportText()
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 12)
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .zenCard(cornerRadius: 18)
    }
}

private extension UNUserNotificationCenter {
    func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            requestAuthorization(options: options) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

struct NightGuardView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var reminderManager = NightGuardReminderManager()

    @AppStorage("nightguard.kitchenCloseMinutes") private var kitchenCloseMinutes: Int = 21 * 60
    @AppStorage("nightguard.ritualLeadMinutes") private var ritualLeadMinutes: Int = 15
    @AppStorage("nightguard.morningCheckMinutes") private var morningCheckMinutes: Int = 7 * 60
    @AppStorage("nightguard.remindersEnabled") private var remindersEnabled = true
    @AppStorage(NightGuardTracking.recordsStorageKey) private var recordsJSON = ""
    @AppStorage("nightguard.checklist.dayKey") private var checklistDayKey = ""
    @AppStorage("nightguard.checklist.brush") private var didBrushTeeth = false
    @AppStorage("nightguard.checklist.drink") private var didDrinkWaterOrTea = false
    @AppStorage("nightguard.checklist.lights") private var didTurnOffKitchenLights = false

    @State private var todayStatus: NightGuardStatus = .pending
    @State private var waitUntil: Date?
    @State private var reviewDate = Date()
    @State private var reviewStatus: NightGuardStatus = .pending
    @State private var reviewNote = ""
    @State private var didInitializeReview = false
    @State private var showingReviewSection = false
    @State private var showingReminderSettings = false
    @State private var reviewSaveMessage: String?
    @State private var reviewSaveDismissTask: Task<Void, Never>?
    @FocusState private var isReviewNoteFocused: Bool

    private var ritualStartMinutes: Int {
        normalizeMinutes(kitchenCloseMinutes - ritualLeadMinutes)
    }

    private var currentPhase: NightGuardPhase {
        let minute = minuteOfDay(for: Date())
        let dayCutoff = normalizeMinutes(store.settings.dayCutoffMinutes)
        if minute >= kitchenCloseMinutes || minute < dayCutoff {
            return .locked
        }
        if minute >= ritualStartMinutes {
            return .closure
        }
        return .preCommit
    }

    private var checklistCompletedCount: Int {
        [didBrushTeeth, didDrinkWaterOrTea, didTurnOffKitchenLights].filter { $0 }.count
    }

    private var complianceSummary: String {
        let completed = recentCompletedRecords(limit: 30)
        guard !completed.isEmpty else { return "No completed nights yet." }
        let compliant = completed.filter(\.status.isCompliant).count
        let rate = Int((Double(compliant) / Double(completed.count) * 100).rounded())
        return "\(rate)% compliance over last \(completed.count) completed nights."
    }

    private var recentNightRecords: [NightGuardRecord] {
        decodedRecords()
            .sorted(by: { $0.dayKey > $1.dayKey })
            .prefix(7)
            .map { $0 }
    }

    private var reminderSummary: String {
        guard remindersEnabled else { return "Reminders are off." }
        return "Ritual \(formattedTime(ritualStartMinutes)), close \(formattedTime(kitchenCloseMinutes)), morning \(formattedTime(morningCheckMinutes))."
    }

    private var nextStepTitle: String {
        switch currentPhase {
        case .preCommit:
            return "Prepare the evening"
        case .closure:
            return "Complete the closeout"
        case .locked:
            return "Use the recovery plan"
        }
    }

    private var nextStepMessage: String {
        switch currentPhase {
        case .preCommit:
            return "Get the three ritual steps lined up before the kitchen closes at \(formattedTime(kitchenCloseMinutes))."
        case .closure:
            return "Finish the three ritual steps now so tonight ends with less friction."
        case .locked:
            return "If you feel pulled back into the kitchen, start with tea or water and a short pause."
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                currentStateHero
                primaryActionCard
                NightGuardDisclosureCard(
                    title: "Review a previous night",
                    subtitle: "Adjust status, add a short note, or reopen a recent evening.",
                    isExpanded: $showingReviewSection
                ) {
                    reviewSectionContent
                }
                NightGuardDisclosureCard(
                    title: "Reminder timing",
                    subtitle: reminderSummary,
                    isExpanded: $showingReminderSettings
                ) {
                    remindersSectionContent
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Night Guard")
        .onAppear {
            syncForCurrentDay()
            if !didInitializeReview {
                reviewDate = defaultReviewDate()
                loadReview(for: reviewDate)
                didInitializeReview = true
            }
            Task {
                await reminderManager.refreshAuthorizationStatus()
                await reminderManager.applySchedule(
                    config: NightGuardReminderConfig(
                        enabled: remindersEnabled,
                        kitchenCloseMinutes: kitchenCloseMinutes,
                        ritualLeadMinutes: ritualLeadMinutes,
                        morningCheckMinutes: morningCheckMinutes
                    )
                )
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            syncForCurrentDay()
            Task {
                await reminderManager.refreshAuthorizationStatus()
            }
        }
        .onChange(of: remindersEnabled) { _, _ in
            scheduleReminders()
        }
        .onChange(of: kitchenCloseMinutes) { _, _ in
            scheduleReminders()
        }
        .onChange(of: ritualLeadMinutes) { _, _ in
            scheduleReminders()
        }
        .onChange(of: morningCheckMinutes) { _, _ in
            scheduleReminders()
        }
        .onChange(of: reviewDate) { _, newValue in
            loadReview(for: newValue)
        }
    }

    private var currentStateHero: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.group) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: ZenSpacing.compact) {
                    Text(currentPhase.title)
                        .zenHeroTitle()
                    Text(currentPhase.message)
                        .zenSupportText()
                }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: todayStatus.icon)
                    Text(todayStatus.title)
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(todayStatus.tint.opacity(0.12), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(todayStatus.tint.opacity(0.28), lineWidth: 1)
                )
                .foregroundStyle(todayStatus.tint)
            }

            Text(todayStatus.subtitle)
                .zenSupportText()

            HStack {
                Label("Kitchen closes", systemImage: "lock")
                Spacer()
                Text(formattedTime(kitchenCloseMinutes))
            }
            .font(.footnote.weight(.medium))

            HStack(alignment: .center, spacing: 12) {
                NightGuardHeroMetric(label: "Ritual starts", value: formattedTime(ritualStartMinutes))
                NightGuardHeroMetric(label: "Close", value: formattedTime(kitchenCloseMinutes))
            }

            Text(complianceSummary)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(ZenSpacing.card)
        .zenCard(cornerRadius: 20)
    }

    private var primaryActionCard: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.group) {
            Text(nextStepTitle)
                .zenSectionTitle()
            Text(nextStepMessage)
                .zenSupportText()

            switch currentPhase {
            case .preCommit, .closure:
                ritualChecklistSection
            case .locked:
                recoveryPlanSection
            }
        }
        .padding(16)
        .zenCard(cornerRadius: 18)
    }

    private var ritualChecklistSection: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.group) {
            ritualRow(title: "Brush teeth", detail: "Create a clear finish line for food.", isDone: $didBrushTeeth)
            ritualRow(title: "Drink tea or water", detail: "Give yourself a quiet replacement routine.", isDone: $didDrinkWaterOrTea)
            ritualRow(title: "Turn off kitchen lights", detail: "Make the environment match the plan.", isDone: $didTurnOffKitchenLights)

            HStack {
                Text("Completed")
                    .zenMetricLabel()
                Spacer()
                Text("\(checklistCompletedCount)/3")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(checklistCompletedCount == 3 ? .green : .primary)
            }
        }
    }

    private var recoveryPlanSection: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.group) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    waitUntil = Date().addingTimeInterval(10 * 60)
                } label: {
                    Label("Start a 10-minute pause", systemImage: "timer")
                        .frame(maxWidth: .infinity)
                }
                .glassButton(.text)

                if let waitUntil {
                    Text("Pause running until \(waitUntil.formatted(date: .omitted, time: .shortened)).")
                        .zenSupportText()
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Button {
                        setStatus(.compliant)
                    } label: {
                        Label("Save as successful close", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .glassButton(.text)

                    Button {
                        setStatus(.violation)
                    } label: {
                        Label("Log late eating", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .glassButton(.text)
                    .tint(.red)
                }

                VStack(spacing: 10) {
                    Button {
                        setStatus(.compliant)
                    } label: {
                        Label("Save as successful close", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .glassButton(.text)

                    Button {
                        setStatus(.violation)
                    } label: {
                        Label("Log late eating", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .glassButton(.text)
                    .tint(.red)
                }
            }

            Button {
                setStatus(.proteinException)
            } label: {
                Label("Log recovery snack", systemImage: "heart.text.square")
                    .frame(maxWidth: .infinity)
            }
            .glassButton(.text)
            .tint(.orange)
        }
    }

    private var reviewSectionContent: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.group) {
            DatePicker("Night date", selection: $reviewDate, displayedComponents: .date)

            Picker("Status", selection: $reviewStatus) {
                Text(NightGuardStatus.compliant.title).tag(NightGuardStatus.compliant)
                Text(NightGuardStatus.proteinException.title).tag(NightGuardStatus.proteinException)
                Text(NightGuardStatus.violation.title).tag(NightGuardStatus.violation)
                Text(NightGuardStatus.pending.title).tag(NightGuardStatus.pending)
            }
            .pickerStyle(.menu)

            TextField("Short note (optional)", text: $reviewNote, axis: .vertical)
                .lineLimit(1...3)
                .focused($isReviewNoteFocused)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ZenStyle.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

            HStack(spacing: 10) {
                Button {
                    reviewDate = defaultReviewDate()
                    loadReview(for: reviewDate)
                } label: {
                    Label("Use Last Night", systemImage: "arrow.uturn.backward.circle")
                }
                .glassButton(.text)

                Button {
                    saveReview()
                } label: {
                    Label("Save Review", systemImage: "square.and.pencil")
                }
                .glassButton(.text)
            }

            if let reviewSaveMessage {
                Label(reviewSaveMessage, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !recentNightRecords.isEmpty {
                Divider()
                Text("Recent nights")
                    .zenMetricLabel()
                ForEach(Array(recentNightRecords.enumerated()), id: \.offset) { _, record in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formattedDate(forDayKey: record.dayKey))
                                .zenSectionTitle()
                            Text(record.status.title)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(record.status.tint)
                            if let note = record.note, !note.isEmpty {
                                Text(note)
                                    .zenSupportText()
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        Button("Edit") {
                            if let recordDate = DayKeyParser.date(from: record.dayKey, timeZone: store.appCalendar.timeZone) {
                                reviewDate = recordDate
                                loadReview(for: recordDate)
                            }
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var remindersSectionContent: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.group) {
            Toggle("Enable Night Guard reminders", isOn: $remindersEnabled)

            HStack {
                Text("Kitchen close")
                Spacer()
                DatePicker(
                    "",
                    selection: Binding(
                        get: { dateFromMinutes(kitchenCloseMinutes) },
                        set: { kitchenCloseMinutes = minuteOfDay(for: $0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)
            }

            HStack {
                Text("Ritual lead time")
                Spacer()
                Stepper("\(ritualLeadMinutes) min", value: $ritualLeadMinutes, in: 5...45, step: 5)
                    .labelsHidden()
                Text("\(ritualLeadMinutes) min")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Morning check-in")
                Spacer()
                DatePicker(
                    "",
                    selection: Binding(
                        get: { dateFromMinutes(morningCheckMinutes) },
                        set: { morningCheckMinutes = minuteOfDay(for: $0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)
            }

            Button {
                scheduleReminders()
            } label: {
                Label("Reschedule Reminders", systemImage: "bell.badge")
            }
            .glassButton(.text)
            .disabled(!remindersEnabled)

            if let message = reminderManager.scheduleMessage {
                Text(message)
                    .zenSupportText()
            }
        }
    }

    private func ritualRow(title: String, detail: String, isDone: Binding<Bool>) -> some View {
        Button {
            isDone.wrappedValue.toggle()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: isDone.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isDone.wrappedValue ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .zenSupportText()
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func scheduleReminders() {
        Task {
            await reminderManager.applySchedule(
                config: NightGuardReminderConfig(
                    enabled: remindersEnabled,
                    kitchenCloseMinutes: kitchenCloseMinutes,
                    ritualLeadMinutes: ritualLeadMinutes,
                    morningCheckMinutes: morningCheckMinutes
                )
            )
        }
    }

    private func syncForCurrentDay() {
        let key = dayKey(for: store.currentDay)
        if checklistDayKey != key {
            checklistDayKey = key
            didBrushTeeth = false
            didDrinkWaterOrTea = false
            didTurnOffKitchenLights = false
            waitUntil = nil
        }
        todayStatus = statusForDay(key) ?? .pending
    }

    private func setStatus(_ status: NightGuardStatus) {
        let key = dayKey(for: store.currentDay)
        todayStatus = status
        upsertRecord(dayKey: key, status: status, noteUpdate: .keep)
        if normalizedDayKey(for: reviewDate) == key {
            reviewStatus = status
        }
    }

    private func loadReview(for date: Date) {
        let key = normalizedDayKey(for: date)
        if let record = decodedRecords().first(where: { $0.dayKey == key }) {
            reviewStatus = record.status
            reviewNote = record.note ?? ""
        } else {
            reviewStatus = .pending
            reviewNote = ""
        }
    }

    private func saveReview() {
        isReviewNoteFocused = false
        let key = normalizedDayKey(for: reviewDate)
        upsertRecord(dayKey: key, status: reviewStatus, noteUpdate: .set(reviewNote))
        if key == dayKey(for: store.currentDay) {
            todayStatus = reviewStatus
        }
        showReviewSaveConfirmation()
    }

    private func showReviewSaveConfirmation() {
        let message = [
            "Saved. Your past self has been properly briefed.",
            "Saved. Midnight-you has fewer excuses now.",
            "Saved. The night log is safely tucked in."
        ].randomElement() ?? "Saved."

        reviewSaveDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) {
            reviewSaveMessage = message
        }

        reviewSaveDismissTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    reviewSaveMessage = nil
                }
            }
        }
    }

    private func upsertRecord(dayKey: String, status: NightGuardStatus, noteUpdate: NightGuardNoteUpdate) {
        var records = decodedRecords()
        let noteValue: String? = {
            switch noteUpdate {
            case .keep:
                return nil
            case .set(let value):
                return normalizedNote(value)
            }
        }()

        if let index = records.firstIndex(where: { $0.dayKey == dayKey }) {
            records[index].status = status
            records[index].updatedAt = Date()
            switch noteUpdate {
            case .keep:
                break
            case .set:
                records[index].note = noteValue
            }
        } else {
            records.append(
                NightGuardRecord(
                    dayKey: dayKey,
                    status: status,
                    updatedAt: Date(),
                    note: noteValue
                )
            )
        }
        let pruned = records
            .sorted(by: { $0.dayKey > $1.dayKey })
            .prefix(120)
        encodedRecords(Array(pruned))
    }

    private func statusForDay(_ dayKey: String) -> NightGuardStatus? {
        decodedRecords().first(where: { $0.dayKey == dayKey })?.status
    }

    private func recentCompletedRecords(limit: Int) -> [NightGuardRecord] {
        decodedRecords()
            .sorted(by: { $0.dayKey > $1.dayKey })
            .filter { $0.status != .pending }
            .prefix(limit)
            .map { $0 }
    }

    private func decodedRecords() -> [NightGuardRecord] {
        NightGuardTracking.decodeRecords(from: recordsJSON)
    }

    private func encodedRecords(_ records: [NightGuardRecord]) {
        guard let value = NightGuardTracking.encodeRecords(records) else { return }
        recordsJSON = value
    }

    private func normalizedNote(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedDayKey(for date: Date) -> String {
        let day = store.appCalendar.startOfDay(for: date)
        return dayKey(for: day)
    }

    private func defaultReviewDate() -> Date {
        store.appCalendar.date(byAdding: .day, value: -1, to: store.currentDay) ?? store.currentDay
    }

    private func formattedDate(forDayKey dayKey: String) -> String {
        guard let date = DayKeyParser.date(from: dayKey, timeZone: store.appCalendar.timeZone) else {
            return dayKey
        }
        let formatter = DateFormatter()
        formatter.calendar = store.appCalendar
        formatter.locale = store.appCalendar.locale ?? .current
        formatter.timeZone = store.appCalendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = store.appCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = store.appCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func formattedTime(_ minutes: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = store.appCalendar.locale
        formatter.timeZone = store.appCalendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: dateFromMinutes(minutes))
    }

    private func dateFromMinutes(_ minutes: Int) -> Date {
        let clamped = normalizeMinutes(minutes)
        var components = DateComponents()
        components.hour = clamped / 60
        components.minute = clamped % 60
        return store.appCalendar.date(from: components) ?? Date()
    }

    private func minuteOfDay(for date: Date) -> Int {
        let components = store.appCalendar.dateComponents([.hour, .minute], from: date)
        return ((components.hour ?? 0) * 60) + (components.minute ?? 0)
    }

    private func normalizeMinutes(_ value: Int) -> Int {
        ((value % 1440) + 1440) % 1440
    }
}
