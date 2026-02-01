import Foundation

public struct DayBoundary: Hashable, Sendable {
    public let cutoffMinutes: Int

    public init(cutoffMinutes: Int) {
        self.cutoffMinutes = cutoffMinutes
    }

    public func dayStart(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let cutoff = cutoffMinutes
        let dayStart = calendar.startOfDay(for: date)
        let minutesSinceStart = Int(date.timeIntervalSince(dayStart) / 60)
        if minutesSinceStart < cutoff {
            return calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
        }
        return dayStart
    }

    public func dayKey(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let normalized = dayStart(for: date, calendar: calendar)
        return DayKeyFormatter.string(from: normalized, timeZone: calendar.timeZone)
    }
}

private final class DayKeyFormatter {
    static func string(from date: Date, timeZone: TimeZone) -> String {
        formatter(timeZone: timeZone).string(from: date)
    }

    static func date(from string: String, timeZone: TimeZone) -> Date? {
        formatter(timeZone: timeZone).date(from: string)
    }

    private static func formatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

public enum DayKeyParser {
    public static func date(from string: String, timeZone: TimeZone = .autoupdatingCurrent) -> Date? {
        DayKeyFormatter.date(from: string, timeZone: timeZone)
    }
}
