import Foundation

/// Offline verification of the pure logic, runnable without any test framework:
///
///     swift run DeepSeekUsage --self-test
///
/// This exists because a Command-Line-Tools-only macOS install has no XCTest, and the
/// behaviour most worth protecting (money decoding + spend attribution) must stay
/// verifiable there too.
public enum SelfTest {
    public struct Report: Sendable {
        public let passed: Int
        public let failures: [String]

        public var isSuccess: Bool { failures.isEmpty }
    }

    static let cnyFixture = """
    {"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"110.00","granted_balance":"10.00","topped_up_balance":"100.00"}]}
    """

    static let usdFixture = """
    {"is_available":false,"balance_infos":[{"currency":"USD","total_balance":"0.00","granted_balance":"0.00","topped_up_balance":"0.00"}]}
    """

    static let numericFixture = """
    {"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":12.5,"granted_balance":0,"topped_up_balance":12.5}]}
    """

    static let sparseFixture = """
    {"balance_infos":[{"currency":"CNY"}]}
    """

    /// Runs every offline check and reports the outcome.
    public static func run() -> Report {
        var failures: [String] = []
        var passed = 0

        func check(_ condition: Bool, _ label: String) {
            if condition {
                passed += 1
            } else {
                failures.append(label)
            }
        }

        // ── Decoding: documented string form ──────────────────────────────
        let cny = try? JSONDecoder().decode(BalanceResponse.self, from: Data(cnyFixture.utf8))
        check(cny != nil, "CNY fixture decodes")
        check(cny?.isAvailable == true, "CNY is_available == true")
        check(cny?.balanceInfos.count == 1, "CNY has one balance bucket")
        check(cny?.primary?.currency == "CNY", "CNY currency")
        check(cny?.primary?.totalBalance == Decimal(110), "CNY total_balance == 110")
        check(cny?.primary?.grantedBalance == Decimal(10), "CNY granted_balance == 10")
        check(cny?.primary?.toppedUpBalance == Decimal(100), "CNY topped_up_balance == 100")

        // ── Decoding: unavailable account + numeric form + sparse form ────
        let usd = try? JSONDecoder().decode(BalanceResponse.self, from: Data(usdFixture.utf8))
        check(usd?.isAvailable == false, "USD is_available == false")
        check(usd?.primary?.totalBalance == Decimal(0), "USD total_balance == 0")

        let numeric = try? JSONDecoder().decode(BalanceResponse.self, from: Data(numericFixture.utf8))
        check(numeric?.primary?.totalBalance == Decimal(string: "12.5"), "numeric total_balance decodes")

        let sparse = try? JSONDecoder().decode(BalanceResponse.self, from: Data(sparseFixture.utf8))
        check(sparse != nil, "sparse fixture decodes without throwing")
        check(sparse?.isAvailable == nil, "sparse is_available is nil, not false")
        check(sparse?.primary?.totalBalance == Decimal(0), "missing money fields degrade to 0")

        // ── Status-code mapping ───────────────────────────────────────────
        check(BalanceClient.error(forStatusCode: 200, body: "") == nil, "200 is not an error")
        check(BalanceClient.error(forStatusCode: 401, body: "") == .invalidAPIKey, "401 -> invalid key")
        check(BalanceClient.error(forStatusCode: 402, body: "") == .insufficientBalance, "402 -> insufficient balance")
        check(BalanceClient.error(forStatusCode: 429, body: "") == .rateLimited, "429 -> rate limited")
        check(BalanceClient.error(forStatusCode: 503, body: "") == .serverError(503), "503 -> server error")
        check(BalanceClient.error(forStatusCode: 418, body: "teapot") == .http(418, "teapot"), "418 -> raw http")

        // ── Spend attribution ─────────────────────────────────────────────
        var tracker = SpendTracker(dayKey: "2026-02-01", currency: "CNY", baseline: Decimal(100))
        tracker.apply(total: Decimal(90), currency: "CNY", dayKey: "2026-02-01")
        check(tracker.spentToday == Decimal(10), "balance drop is counted as spend")
        tracker.apply(total: Decimal(190), currency: "CNY", dayKey: "2026-02-01")
        check(tracker.spentToday == Decimal(10), "top-up does not erase recorded spend")
        check(tracker.baseline == Decimal(190), "top-up moves the baseline")
        tracker.apply(total: Decimal(185), currency: "CNY", dayKey: "2026-02-01")
        check(tracker.spentToday == Decimal(15), "spend after a top-up is measured from the new baseline")
        tracker.apply(total: Decimal(3), currency: "CNY", dayKey: "2026-02-02")
        check(tracker.spentToday == Decimal(0), "new day resets the window")
        check(tracker.baseline == Decimal(3), "new day re-baselines")
        tracker.apply(total: Decimal(3), currency: "USD", dayKey: "2026-02-02")
        check(tracker.currency == "USD", "currency change resets the tracker")

        runPricingChecks(check)

        return Report(passed: passed, failures: failures)
    }

    // MARK: - Peak / off-peak schedule

    private static func runPricingChecks(_ check: (Bool, String) -> Void) {
        // Fixture sanity: if these dates are not the weekdays the tests assume, the
        // expectations below would be meaningless, so assert the calendar first.
        check(utcWeekday(utc(2026, 3, 2, 12)) == 2, "fixture 2026-03-02 is a Monday in UTC")
        check(utcWeekday(utc(2026, 3, 6, 12)) == 6, "fixture 2026-03-06 is a Friday in UTC")
        check(utcWeekday(utc(2026, 3, 7, 12)) == 7, "fixture 2026-03-07 is a Saturday in UTC")
        check(utcWeekday(utc(2026, 3, 8, 12)) == 1, "fixture 2026-03-08 is a Sunday in UTC")

        // Documented windows: 01:00–04:00 and 06:00–10:00 UTC, Mon–Fri.
        check(period(2026, 3, 2, 0, 30) == .offPeak, "Mon 00:30 UTC is off-peak")
        check(period(2026, 3, 2, 1) == .peak, "Mon 01:00 UTC is peak (window start)")
        check(period(2026, 3, 2, 2) == .peak, "Mon 02:00 UTC is peak")
        check(period(2026, 3, 2, 3, 59) == .peak, "Mon 03:59 UTC is peak")
        check(period(2026, 3, 2, 4) == .offPeak, "Mon 04:00 UTC is off-peak (window end)")
        check(period(2026, 3, 2, 5) == .offPeak, "Mon 05:00 UTC is off-peak")
        check(period(2026, 3, 2, 6) == .peak, "Mon 06:00 UTC is peak (second window)")
        check(period(2026, 3, 2, 9, 59) == .peak, "Mon 09:59 UTC is peak")
        check(period(2026, 3, 2, 10) == .offPeak, "Mon 10:00 UTC is off-peak (window end)")
        check(period(2026, 3, 2, 11) == .offPeak, "Mon 11:00 UTC is off-peak")
        check(period(2026, 3, 2, 23, 30) == .offPeak, "Mon 23:30 UTC is off-peak")
        check(period(2026, 3, 6, 2) == .peak, "Fri 02:00 UTC is peak")
        check(period(2026, 3, 7, 2) == .offPeak, "Sat 02:00 UTC is off-peak (weekend)")
        check(period(2026, 3, 8, 7) == .offPeak, "Sun 07:00 UTC is off-peak (weekend)")

        // Transitions.
        check(close(PricingSchedule.nextTransition(after: utc(2026, 3, 2, 2)), utc(2026, 3, 2, 4)),
              "peak at 02:00 ends at 04:00")
        check(close(PricingSchedule.nextTransition(after: utc(2026, 3, 2, 5)), utc(2026, 3, 2, 6)),
              "off-peak at 05:00 ends at 06:00")
        check(close(PricingSchedule.nextTransition(after: utc(2026, 3, 2, 7)), utc(2026, 3, 2, 10)),
              "peak at 07:00 ends at 10:00")
        check(close(PricingSchedule.nextTransition(after: utc(2026, 3, 2, 11)), utc(2026, 3, 3, 1)),
              "off-peak after 10:00 runs to the next weekday window")
        check(close(PricingSchedule.nextTransition(after: utc(2026, 3, 6, 11)), utc(2026, 3, 9, 1)),
              "Friday off-peak skips the weekend to Monday 01:00")
        check(close(PricingSchedule.nextTransition(after: utc(2026, 3, 7, 12)), utc(2026, 3, 9, 1)),
              "Saturday off-peak runs to Monday 01:00")
        check(close(PricingSchedule.nextTransition(after: utc(2026, 3, 2, 1)), utc(2026, 3, 2, 4)),
              "exactly at a boundary returns the following one")

        check(PricingSchedule.peakWindowsUTC == [1..<4, 6..<10], "peak windows are [1,4) and [6,10) UTC")
    }

    private static func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let calendar = PricingSchedule.utcCalendar
        let components = DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: 0
        )
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private static func utcWeekday(_ date: Date) -> Int {
        PricingSchedule.utcCalendar.component(.weekday, from: date)
    }

    private static func period(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> PricingPeriod {
        PricingSchedule.period(at: utc(year, month, day, hour, minute))
    }

    /// Second-resolution comparison: the schedule works in whole hours, so a sub-second
    /// difference is not a meaningful failure.
    private static func close(_ lhs: Date?, _ rhs: Date) -> Bool {
        guard let lhs else { return false }
        return abs(lhs.timeIntervalSince(rhs)) < 1
    }
}
