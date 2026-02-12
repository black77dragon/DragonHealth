import SwiftUI
import Core

enum HistoryDayIndicator: Hashable {
    case score(Double)
}

struct HistoryCalendarView: View {
    let calendar: Calendar
    let currentDay: Date
    @Binding var selectedDate: Date
    let indicators: [String: HistoryDayIndicator]
    let onVisibleMonthChanged: (Date) -> Void

    @State private var displayedMonth: Date

    init(
        calendar: Calendar,
        currentDay: Date,
        selectedDate: Binding<Date>,
        indicators: [String: HistoryDayIndicator],
        onVisibleMonthChanged: @escaping (Date) -> Void
    ) {
        self.calendar = calendar
        self.currentDay = currentDay
        self._selectedDate = selectedDate
        self.indicators = indicators
        self.onVisibleMonthChanged = onVisibleMonthChanged
        let monthStart = Self.monthStart(for: selectedDate.wrappedValue, calendar: calendar)
        _displayedMonth = State(initialValue: monthStart)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            weekdayRow
            monthGrid
        }
        .onAppear { onVisibleMonthChanged(displayedMonth) }
        .onChange(of: displayedMonth) { newValue in
            onVisibleMonthChanged(newValue)
        }
        .onChange(of: selectedDate) { newValue in
            let newMonth = Self.monthStart(for: newValue, calendar: calendar)
            if !calendar.isDate(newMonth, equalTo: displayedMonth, toGranularity: .month) {
                displayedMonth = newMonth
            }
        }
    }

    private var header: some View {
        HStack {
            Text(monthTitle(for: displayedMonth))
                .font(.headline)
            Spacer()
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .glassButton(.icon)
            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .glassButton(.icon)
        }
    }

    private var weekdayRow: some View {
        let symbols = orderedWeekdaySymbols()
        return HStack {
            ForEach(symbols.indices, id: \.self) { index in
                Text(symbols[index])
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        let dates = monthGridDates(for: displayedMonth)
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(dates.indices, id: \.self) { index in
                if let date = dates[index] {
                    let score = scoreValue(for: date)
                    let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                    let isToday = calendar.isDate(date, inSameDayAs: currentDay)
                    Button {
                        selectedDate = date
                    } label: {
                        CalendarDayCell(
                            date: date,
                            calendar: calendar,
                            score: score,
                            isSelected: isSelected,
                            isToday: isToday
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                        .frame(height: 56)
                }
            }
        }
    }

    private func changeMonth(by value: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = Self.monthStart(for: newMonth, calendar: calendar)
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date)
    }

    private func orderedWeekdaySymbols() -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols.map { $0.uppercased() }
        let firstIndex = max(0, min(calendar.firstWeekday - 1, symbols.count - 1))
        return Array(symbols[firstIndex...]) + symbols[..<firstIndex]
    }

    private func monthGridDates(for month: Date) -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let days = calendar.range(of: .day, in: .month, for: month) else {
            return []
        }

        let monthStart = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingEmpty = (firstWeekday - calendar.firstWeekday + 7) % 7

        var dates: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for offset in 0..<days.count {
            let day = calendar.date(byAdding: .day, value: offset, to: monthStart)
            dates.append(day)
        }

        let total = dates.count
        let trailingEmpty = (7 - (total % 7)) % 7
        dates.append(contentsOf: Array(repeating: nil, count: trailingEmpty))
        return dates
    }

    private func scoreValue(for date: Date) -> Double? {
        let dayKey = DayBoundary(cutoffMinutes: 0).dayKey(for: date, calendar: calendar)
        guard let indicator = indicators[dayKey] else { return nil }
        switch indicator {
        case .score(let score):
            return score
        }
    }

    private static func monthStart(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }
}

private struct CalendarDayCell: View {
    let date: Date
    let calendar: Calendar
    let score: Double?
    let isSelected: Bool
    let isToday: Bool

    private let ringSize: CGFloat = 26
    private let ringLineWidth: CGFloat = 2

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let score {
                    Circle()
                        .stroke(ScoreColor.color(for: score), lineWidth: ringLineWidth)
                        .frame(width: ringSize, height: ringSize)
                }

                if isSelected || isToday {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: ringSize - 2, height: ringSize - 2)
                }

                Text("\(calendar.component(.day, from: date))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle((isSelected || isToday) ? .white : .primary)
            }

            Text(scoreText)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(score.map { ScoreColor.color(for: $0) } ?? .clear)
                .opacity(score == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
    }

    private var scoreText: String {
        guard let score else { return "00" }
        return "\(Int(score.rounded()))"
    }
}
