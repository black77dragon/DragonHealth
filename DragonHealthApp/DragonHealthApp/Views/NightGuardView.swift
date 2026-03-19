import SwiftUI
import Combine
import Core
import UserNotifications

private extension NightGuardStatus {
    var title: String {
        switch self {
        case .pending:
            return "Pending"
        case .compliant:
            return "Rule Respected"
        case .violation:
            return "Rule Broken"
        case .proteinException:
            return "Protein Exception"
        }
    }

    var subtitle: String {
        switch self {
        case .pending:
            return "No final status logged for this night yet."
        case .compliant:
            return "Kitchen close rule respected."
        case .violation:
            return "Late-night calories were logged."
        case .proteinException:
            return "Strong true hunger handled within protocol."
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
            return "Pre-Commitment Window"
        case .closure:
            return "Closure Ritual Window"
        case .locked:
            return "Kitchen Closed"
        }
    }

    var message: String {
        switch self {
        case .preCommit:
            return "Food decisions are made in advance. Set up your environment now."
        case .closure:
            return "Run your closure ritual now: brush teeth, tea or water, lights off."
        case .locked:
            return "No calories after close. If craving appears: water, wait 10, then redirect."
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                phaseCard
                ritualCard
                protocolCard
                reviewCard
                remindersCard
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

    private var phaseCard: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.group) {
            HStack(alignment: .top) {
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
                .background(ZenStyle.elevatedSurface, in: Capsule())
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

            Text(complianceSummary)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(ZenSpacing.card)
        .zenCard(cornerRadius: 20)
    }

    private var ritualCard: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.group) {
            Text("Closure Ritual (\(formattedTime(ritualStartMinutes)))")
                .zenSectionTitle()
            Text("Complete all 3 steps before kitchen close.")
                .zenSupportText()

            ritualRow(title: "Brush teeth", isDone: $didBrushTeeth)
            ritualRow(title: "Drink tea or water", isDone: $didDrinkWaterOrTea)
            ritualRow(title: "Turn off kitchen lights", isDone: $didTurnOffKitchenLights)

            Text("Completed: \(checklistCompletedCount)/3")
                .font(.footnote.weight(.medium))
                .foregroundStyle(checklistCompletedCount == 3 ? .green : .secondary)
        }
        .padding(16)
        .zenCard(cornerRadius: 18)
    }

    private var protocolCard: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.group) {
            Text("After \(formattedTime(kitchenCloseMinutes)) Protocol")
                .zenSectionTitle()
            Text("Water or tea -> wait 10 minutes -> redirect attention.")
                .zenSupportText()

            HStack(spacing: 10) {
                Button {
                    waitUntil = Date().addingTimeInterval(10 * 60)
                } label: {
                    Label("Start 10-Min Wait", systemImage: "timer")
                }
                .glassButton(.text)

                if let waitUntil {
                    Text("Until \(waitUntil.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button {
                    setStatus(.compliant)
                } label: {
                    Label("Mark Rule Respected", systemImage: "checkmark.circle")
                }
                .glassButton(.text)

                Button {
                    setStatus(.violation)
                } label: {
                    Label("Log Violation", systemImage: "xmark.circle")
                }
                .glassButton(.text)
                .tint(.red)
            }

            Button {
                setStatus(.proteinException)
            } label: {
                Label("Log True Hunger (Protein Only)", systemImage: "heart.text.square")
            }
            .glassButton(.text)
            .tint(.orange)
        }
        .padding(16)
        .zenCard(cornerRadius: 18)
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.group) {
            Text("Previous Night Review")
                .zenSectionTitle()
            Text("Record success for last night, add a short note, and adjust any previous night.")
                .zenSupportText()

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
        .padding(16)
        .zenCard(cornerRadius: 18)
    }

    private var remindersCard: some View {
        VStack(alignment: .leading, spacing: ZenSpacing.group) {
            Text("Reminders")
                .zenSectionTitle()

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
        .padding(16)
        .zenCard(cornerRadius: 18)
    }

    private func ritualRow(title: String, isDone: Binding<Bool>) -> some View {
        Button {
            isDone.wrappedValue.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isDone.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isDone.wrappedValue ? Color.green : Color.secondary)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
            }
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
