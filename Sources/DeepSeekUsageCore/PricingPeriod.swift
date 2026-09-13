import Foundation

/// Which pricing period a request is billed at.
///
/// Both models DeepSeek currently documents (`deepseek-flash`, `deepseek-v4-pro`) have
/// peak and off-peak rates, so this is an account-wide property of the clock — it does
/// not depend on the model, the key, or the balance.
public enum PricingPeriod: String, Sendable, Equatable, CaseIterable {
    case peak
    case offPeak

    public var isPeak: Bool { self == .peak }
}

/// DeepSeek's peak / off-peak schedule:
///
/// > Off-peak rates are half of the peak rates. Peak hours are 01:00 - 04:00 and
/// > 06:00 - 10:00 UTC, Monday through Friday (all other hours are off-peak).
/// > — https://api-docs.deepseek.com/quick_start/pricing
///
/// The Chinese page states the same windows in Beijing time (09:00–12:00 and
/// 14:00–18:00, Monday–Friday), which is exactly UTC+8, so the two agree.
///
/// Everything here is computed in UTC on purpose: a user's local calendar must not shift
/// the window. The weekday is unambiguous despite the two phrasings because the windows
/// (01:00–10:00 UTC) map to 09:00–18:00 Beijing on the *same* calendar day.
public enum PricingSchedule {
    /// Peak windows as half-open UTC hour ranges: `[1, 4)` and `[6, 10)`.
    public static let peakWindowsUTC: [Range<Int>] = [1..<4, 6..<10]

    public static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    public static func period(at date: Date) -> PricingPeriod {
        period(at: date, calendar: utcCalendar)
    }

    /// `calendar` is injectable for testing; production always passes UTC.
    public static func period(at date: Date, calendar: Calendar) -> PricingPeriod {
        let parts = calendar.dateComponents([.weekday, .hour], from: date)
        guard let weekday = parts.weekday, let hour = parts.hour else { return .offPeak }

        // Calendar weekday numbering: 1 = Sunday … 7 = Saturday, so Mon–Fri is 2...6.
        guard (2...6).contains(weekday) else { return .offPeak }

        for window in peakWindowsUTC where window.contains(hour) {
            return .peak
        }
        return .offPeak
    }

    /// The next moment the period actually changes, or `nil` if none is found.
    ///
    /// Windows can only change at a window edge (01:00, 04:00, 06:00, 10:00 UTC), so it is
    /// enough to walk those candidates forward and return the first one whose period
    /// differs. That naturally skips the whole weekend, where every candidate is off-peak:
    /// Friday 10:00 UTC is followed by Monday 01:00 UTC.
    public static func nextTransition(after date: Date) -> Date? {
        nextTransition(after: date, calendar: utcCalendar)
    }

    public static func nextTransition(after date: Date, calendar: Calendar) -> Date? {
        let current = period(at: date, calendar: calendar)
        let hours = peakWindowsUTC.flatMap { [$0.lowerBound, $0.upperBound] }.sorted()
        let dayStart = calendar.startOfDay(for: date)

        // Four days is enough to clear a weekend and reach the next weekday window.
        for dayOffset in 0...4 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: dayStart) else { continue }
            for hour in hours {
                guard let candidate = calendar.date(byAdding: .hour, value: hour, to: day) else { continue }
                guard candidate > date else { continue }
                if period(at: candidate, calendar: calendar) != current {
                    return candidate
                }
            }
        }
        return nil
    }

    /// Human-readable schedule, e.g. `01:00–04:00 and 06:00–10:00 UTC, Mon–Fri`.
    public static let scheduleDescription = "01:00–04:00 and 06:00–10:00 UTC, Mon–Fri"
}
