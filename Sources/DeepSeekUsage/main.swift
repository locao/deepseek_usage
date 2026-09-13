import AppKit
import Foundation
import SwiftUI

import DeepSeekUsageCore

///     DeepSeekUsage              # run the menu bar app
///     DeepSeekUsage --check      # print the current balance and exit
///     DeepSeekUsage --self-test  # offline checks of money decoding + spend logic
///     DeepSeekUsage --help
enum CLI {
    static let usage = """
    DeepSeekUsage — macOS menu bar app for DeepSeek API balance.

    USAGE:
      DeepSeekUsage              Run the menu bar app (no Dock icon).
      DeepSeekUsage --check      Print the account balance and pricing period, then exit.
      DeepSeekUsage --self-test  Run offline logic checks and exit.
      DeepSeekUsage --render-preview <dir>
                                 Write PNG snapshots of the popover and exit.
      DeepSeekUsage --version    Print the version and exit.
      DeepSeekUsage --help       Show this message.

    The API key is read from the login keychain, or from the DEEPSEEK_API_KEY
    environment variable when set.

    ENDPOINT:
      GET https://api.deepseek.com/user/balance
      Account metadata only — this read bills no tokens.
    """

    static func runCheck() async -> Int32 {
        let now = Date()
        let period = PricingSchedule.period(at: now)
        print("pricing: \(period.isPeak ? "peak" : "off-peak") now (peak hours: \(PricingSchedule.scheduleDescription))")
        if let next = PricingSchedule.nextTransition(after: now) {
            let upcoming = PricingSchedule.period(at: next).isPeak ? "peak" : "off-peak"
            let stamp = ISO8601DateFormatter().string(from: next)
            print("next change: \(upcoming) at \(stamp)")
        }

        do {
            guard let apiKey = try APIKeyStore.resolve() else {
                fail("no API key found. Set DEEPSEEK_API_KEY or save one in the app's Settings.")
                return 2
            }

            let response = try await BalanceClient().fetchBalance(apiKey: apiKey)
            print("is_available: \(response.isAvailable.map(String.init) ?? "unknown")")

            if response.balanceInfos.isEmpty {
                print("(no balance buckets returned)")
            }
            for info in response.balanceInfos {
                print("""
                \(info.currency):
                  total      \(MoneyFormatter.string(info.totalBalance, currency: info.currency))
                  granted    \(MoneyFormatter.string(info.grantedBalance, currency: info.currency))
                  topped up  \(MoneyFormatter.string(info.toppedUpBalance, currency: info.currency))
                """)
            }

            return response.isAvailable == false ? 1 : 0
        } catch {
            fail((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return 1
        }
    }

    /// Renders the popover to PNG with a fixed sample balance, once at a peak time and
    /// once off-peak. Development aid: it makes the visual states reviewable without
    /// having to wait for a particular hour of the day.
    @MainActor
    static func renderPreview(into directory: String) -> Int32 {
        // Accessory/prohibited: render offscreen without stealing focus or showing UI.
        NSApplication.shared.setActivationPolicy(.prohibited)

        let store = UsageStore(stateURL: nil, keyProvider: { nil })
        store.seedForPreview(
            balance: BalanceResponse(
                isAvailable: true,
                balanceInfos: [
                    BalanceInfo(currency: "CNY", totalBalance: 110, grantedBalance: 10, toppedUpBalance: 100)
                ]
            ),
            spend: SpendTracker(
                dayKey: SpendTracker.dayKey(for: Date()),
                currency: "CNY",
                baseline: 110,
                spentToday: Decimal(string: "0.42") ?? 0
            )
        )

        // Monday 02:00 UTC is inside a peak window; Monday 05:00 UTC is between windows.
        let calendar = PricingSchedule.utcCalendar
        func utc(hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: hour, second: 0)) ?? Date()
        }

        let base = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        } catch {
            fail("could not create \(directory): \(error.localizedDescription)")
            return 1
        }

        for (name, date) in [("peak", utc(hour: 2)), ("offpeak", utc(hour: 5))] {
            let renderer = ImageRenderer(content: MenuContentView(store: store, previewDate: date))
            renderer.scale = 2

            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:])
            else {
                fail("could not render the \(name) preview")
                return 1
            }

            let url = base.appendingPathComponent("popover-\(name).png")
            do {
                try png.write(to: url)
                print("wrote \(url.path)")
            } catch {
                fail("could not write \(url.path): \(error.localizedDescription)")
                return 1
            }
        }
        return 0
    }

    private static func fail(_ message: String) {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--help") || arguments.contains("-h") {
    print(CLI.usage)
    exit(0)
}

if arguments.contains("--version") || arguments.contains("-v") {
    print("DeepSeekUsage \(AppInfo.version)")
    print("user agent: \(AppInfo.userAgent)")
    exit(0)
}

if arguments.contains("--self-test") {
    let report = SelfTest.run()
    if report.isSuccess {
        print("self-test: OK — \(report.passed) checks passed")
        exit(0)
    }
    for failure in report.failures {
        print("self-test FAIL: \(failure)")
    }
    print("self-test: \(report.failures.count) of \(report.passed + report.failures.count) checks failed")
    exit(1)
}

if arguments.contains("--check") {
    let status = await CLI.runCheck()
    exit(status)
}

if let index = arguments.firstIndex(of: "--render-preview") {
    guard index + 1 < arguments.count else {
        FileHandle.standardError.write(Data("error: --render-preview needs an output directory\n".utf8))
        exit(2)
    }
    // Top-level code is already main-actor isolated, so no `await` is needed here.
    let status = CLI.renderPreview(into: arguments[index + 1])
    exit(status)
}

DeepSeekUsageApp.main()
