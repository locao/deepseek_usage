import Foundation

/// Estimates spend by diffing consecutive balance reads.
///
/// The official API exposes a *balance*, never per-request billing, so this is a
/// best-effort reconstruction and is labelled as an estimate everywhere it surfaces:
///
/// - a balance **decrease** inside the same day is counted as spend;
/// - a balance **increase** (top-up or grant) only moves the baseline — it never
///   produces negative spend;
/// - a new day or a new currency resets the window.
///
/// It cannot see spend that was offset by a simultaneous top-up, and it cannot
/// attribute spend to a model or a key.
public struct SpendTracker: Codable, Equatable, Sendable {
    public private(set) var dayKey: String
    public private(set) var currency: String
    public private(set) var baseline: Decimal
    public private(set) var spentToday: Decimal

    /// Ignore sub-micro-currency jitter so a cosmetic float wobble is not "spend".
    public static let tolerance = Decimal(sign: .plus, exponent: -6, significand: 1)

    public init(dayKey: String, currency: String, baseline: Decimal, spentToday: Decimal = 0) {
        self.dayKey = dayKey
        self.currency = currency
        self.baseline = baseline
        self.spentToday = spentToday
    }

    /// Folds a fresh balance reading in. Returns the spend attributed to this reading.
    @discardableResult
    public mutating func apply(total: Decimal, currency: String, dayKey: String) -> Decimal {
        guard self.dayKey == dayKey, self.currency == currency else {
            self.dayKey = dayKey
            self.currency = currency
            self.baseline = total
            self.spentToday = 0
            return 0
        }

        let delta = baseline - total
        if delta > SpendTracker.tolerance {
            spentToday += delta
            baseline = total
            return delta
        }
        if delta < -SpendTracker.tolerance {
            baseline = total
        }
        return 0
    }

    /// Local-calendar day key, so "today" matches the user's clock.
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
