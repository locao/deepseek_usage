import Foundation

// swift-testing ships with Swift 6 toolchains, but the `Testing` module only sits on the
// default framework search path of a full Xcode install. When it is unavailable (a
// Command-Line-Tools-only Mac) this suite compiles to nothing; `swift run DeepSeekUsage
// --self-test` covers the same logic there and needs no test framework at all.
#if canImport(Testing)

import Testing

@testable import DeepSeekUsageCore

@Suite("Balance response decoding")
struct BalanceDecodingTests {
    @Test("decodes the documented string-encoded CNY response")
    func decodesCNY() throws {
        let response = try JSONDecoder().decode(BalanceResponse.self, from: Data(SelfTest.cnyFixture.utf8))

        #expect(response.isAvailable == true)
        #expect(response.balanceInfos.count == 1)
        #expect(response.primary?.currency == "CNY")
        #expect(response.primary?.totalBalance == Decimal(110))
        #expect(response.primary?.grantedBalance == Decimal(10))
        #expect(response.primary?.toppedUpBalance == Decimal(100))
    }

    @Test("decodes a numeric money field and an unavailable account")
    func decodesNumericAndUnavailable() throws {
        let numeric = try JSONDecoder().decode(BalanceResponse.self, from: Data(SelfTest.numericFixture.utf8))
        #expect(numeric.primary?.totalBalance == Decimal(string: "12.5"))

        let usd = try JSONDecoder().decode(BalanceResponse.self, from: Data(SelfTest.usdFixture.utf8))
        #expect(usd.isAvailable == false)
        #expect(usd.primary?.totalBalance == Decimal(0))
    }

    @Test("missing fields degrade instead of failing the whole response")
    func decodesSparse() throws {
        let response = try JSONDecoder().decode(BalanceResponse.self, from: Data(SelfTest.sparseFixture.utf8))

        #expect(response.isAvailable == nil)
        #expect(response.primary?.totalBalance == Decimal(0))
    }
}

@Suite("HTTP status mapping")
struct StatusMappingTests {
    @Test("maps DeepSeek's documented error codes")
    func mapsStatusCodes() {
        #expect(BalanceClient.error(forStatusCode: 200, body: "") == nil)
        #expect(BalanceClient.error(forStatusCode: 401, body: "") == .invalidAPIKey)
        #expect(BalanceClient.error(forStatusCode: 402, body: "") == .insufficientBalance)
        #expect(BalanceClient.error(forStatusCode: 429, body: "") == .rateLimited)
        #expect(BalanceClient.error(forStatusCode: 500, body: "") == .serverError(500))
        #expect(BalanceClient.error(forStatusCode: 418, body: "teapot") == .http(418, "teapot"))
    }
}

@Suite("Spend attribution")
struct SpendTrackerTests {
    @Test("counts balance drops as spend")
    func countsDrops() {
        var tracker = SpendTracker(dayKey: "2026-02-01", currency: "CNY", baseline: Decimal(100))
        tracker.apply(total: Decimal(90), currency: "CNY", dayKey: "2026-02-01")

        #expect(tracker.spentToday == Decimal(10))
    }

    @Test("a top-up moves the baseline without erasing recorded spend")
    func handlesTopUp() {
        var tracker = SpendTracker(dayKey: "2026-02-01", currency: "CNY", baseline: Decimal(100))
        tracker.apply(total: Decimal(90), currency: "CNY", dayKey: "2026-02-01")
        tracker.apply(total: Decimal(190), currency: "CNY", dayKey: "2026-02-01")

        #expect(tracker.spentToday == Decimal(10))
        #expect(tracker.baseline == Decimal(190))

        tracker.apply(total: Decimal(185), currency: "CNY", dayKey: "2026-02-01")
        #expect(tracker.spentToday == Decimal(15))
    }

    @Test("a new day resets the window")
    func resetsOnNewDay() {
        var tracker = SpendTracker(dayKey: "2026-02-01", currency: "CNY", baseline: Decimal(100))
        tracker.apply(total: Decimal(90), currency: "CNY", dayKey: "2026-02-01")
        tracker.apply(total: Decimal(3), currency: "CNY", dayKey: "2026-02-02")

        #expect(tracker.spentToday == Decimal(0))
        #expect(tracker.baseline == Decimal(3))
    }

    @Test("sub-micro balance jitter is not spend")
    func ignoresJitter() {
        var tracker = SpendTracker(dayKey: "2026-02-01", currency: "CNY", baseline: Decimal(100))
        tracker.apply(total: Decimal(100), currency: "CNY", dayKey: "2026-02-01")

        #expect(tracker.spentToday == Decimal(0))
    }
}

@Suite("Peak / off-peak schedule")
struct PricingScheduleTests {
    /// 2026-03-02 is a Monday; 2026-03-06 a Friday; 2026-03-07/08 the weekend.
    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let calendar = PricingSchedule.utcCalendar
        let components = DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: 0
        )
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private func period(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> PricingPeriod {
        PricingSchedule.period(at: utc(year, month, day, hour, minute))
    }

    @Test("fixture dates fall on the weekdays the expectations assume")
    func fixtureWeekdays() {
        let calendar = PricingSchedule.utcCalendar
        #expect(calendar.component(.weekday, from: utc(2026, 3, 2)) == 2)  // Monday
        #expect(calendar.component(.weekday, from: utc(2026, 3, 6)) == 6)  // Friday
        #expect(calendar.component(.weekday, from: utc(2026, 3, 7)) == 7)  // Saturday
        #expect(calendar.component(.weekday, from: utc(2026, 3, 8)) == 1)  // Sunday
    }

    @Test("windows are half-open and only apply Monday through Friday")
    func windowBoundaries() {
        #expect(period(2026, 3, 2, 0, 30) == .offPeak)
        #expect(period(2026, 3, 2, 1) == .peak)
        #expect(period(2026, 3, 2, 3, 59) == .peak)
        #expect(period(2026, 3, 2, 4) == .offPeak)
        #expect(period(2026, 3, 2, 6) == .peak)
        #expect(period(2026, 3, 2, 9, 59) == .peak)
        #expect(period(2026, 3, 2, 10) == .offPeak)
    }

    @Test("weekends and the hours between windows are off-peak")
    func weekendsAreOffPeak() {
        #expect(period(2026, 3, 2, 5) == .offPeak)
        #expect(period(2026, 3, 2, 11) == .offPeak)
        #expect(period(2026, 3, 6, 2) == .peak)
        #expect(period(2026, 3, 7, 2) == .offPeak)
        #expect(period(2026, 3, 8, 7) == .offPeak)
    }

    @Test("next transition lands on the following window edge")
    func nextTransitions() {
        func closes(_ lhs: Date?, _ rhs: Date) -> Bool {
            guard let lhs else { return false }
            return abs(lhs.timeIntervalSince(rhs)) < 1
        }

        #expect(closes(PricingSchedule.nextTransition(after: utc(2026, 3, 2, 2)), utc(2026, 3, 2, 4)))
        #expect(closes(PricingSchedule.nextTransition(after: utc(2026, 3, 2, 5)), utc(2026, 3, 2, 6)))
        #expect(closes(PricingSchedule.nextTransition(after: utc(2026, 3, 2, 7)), utc(2026, 3, 2, 10)))
        #expect(closes(PricingSchedule.nextTransition(after: utc(2026, 3, 2, 11)), utc(2026, 3, 3, 1)))
    }

    @Test("Friday off-peak runs through the weekend to Monday")
    func skipsWeekend() {
        let next = PricingSchedule.nextTransition(after: utc(2026, 3, 6, 11))
        let expected = utc(2026, 3, 9, 1)
        #expect(next != nil)
        if let next {
            #expect(abs(next.timeIntervalSince(expected)) < 1)
            #expect(PricingSchedule.period(at: next) == .peak)
        }
    }
}

@Suite("Offline self-test")
struct SelfTestTests {
    @Test("every bundled check passes")
    func selfTestPasses() {
        let report = SelfTest.run()
        #expect(report.failures.isEmpty, "\(report.failures)")
        #expect(report.passed > 0)
    }
}

#endif
