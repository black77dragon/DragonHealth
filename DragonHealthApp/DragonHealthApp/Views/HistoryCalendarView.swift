import SwiftUI
import UIKit
import Core

enum HistoryDayIndicator: Hashable {
    case score(Double)
}

struct HistoryCalendarView: UIViewRepresentable {
    let calendar: Calendar
    @Binding var selectedDate: Date
    let indicators: [String: HistoryDayIndicator]
    let onVisibleMonthChanged: (Date) -> Void

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = calendar
        view.locale = calendar.locale ?? .current
        view.delegate = context.coordinator

        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        context.coordinator.selection = selection
        view.selectionBehavior = selection

        let selectedComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        selection.setSelected(selectedComponents, animated: false)

        return view
    }

    func updateUIView(_ uiView: UICalendarView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.calendar = calendar
        context.coordinator.indicators = indicators
        context.coordinator.onVisibleMonthChanged = onVisibleMonthChanged

        uiView.calendar = calendar
        uiView.locale = calendar.locale ?? .current

        let selectedComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        if context.coordinator.selection?.selectedDate != selectedComponents {
            context.coordinator.selection?.setSelected(selectedComponents, animated: false)
        }

        let newKeys = Set(indicators.keys)
        let reloadKeys = newKeys.union(context.coordinator.indicatorKeys)
        if !reloadKeys.isEmpty {
            let reloadComponents = reloadKeys.compactMap { key -> DateComponents? in
                guard let date = DayKeyParser.date(from: key, timeZone: calendar.timeZone) else { return nil }
                return calendar.dateComponents([.year, .month, .day], from: date)
            }
            uiView.reloadDecorations(forDateComponents: reloadComponents, animated: false)
        }
        context.coordinator.indicatorKeys = newKeys
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: HistoryCalendarView
        var selection: UICalendarSelectionSingleDate?
        var indicatorKeys = Set<String>()
        var indicators: [String: HistoryDayIndicator]
        var calendar: Calendar
        var onVisibleMonthChanged: (Date) -> Void

        init(_ parent: HistoryCalendarView) {
            self.parent = parent
            self.indicators = parent.indicators
            self.calendar = parent.calendar
            self.onVisibleMonthChanged = parent.onVisibleMonthChanged
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard let dateComponents,
                  let date = calendar.date(from: dateComponents) else { return }
            parent.selectedDate = date
        }

        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            guard let date = calendar.date(from: dateComponents) else { return nil }
            let dayKey = DayBoundary(cutoffMinutes: 0).dayKey(for: date, calendar: calendar)
            guard let indicator = indicators[dayKey] else { return nil }
            switch indicator {
            case .score(let score):
                let color = UIColor(ScoreColor.color(for: score))
                return .default(color: color)
            }
        }

        func calendarView(
            _ calendarView: UICalendarView,
            didChangeVisibleDateComponentsFrom previousDateComponents: DateComponents
        ) {
            let visibleComponents = calendarView.visibleDateComponents
            guard let date = calendar.date(from: visibleComponents) else { return }
            onVisibleMonthChanged(date)
        }
    }
}
