import AppKit
import DeepSeekUsageCore
import SwiftUI

/// Small capsule label used for the header's status badges.
private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }
}

struct MenuContentView: View {
    @ObservedObject var store: UsageStore
    /// Overrides "now" for the pricing badge so both states can be rendered offscreen.
    /// `nil` in normal use, where the real clock drives it.
    var previewDate: Date?
    @AppStorage(SettingsKeys.refreshInterval) private var refreshInterval: Double = SettingsKeys.defaultRefreshInterval

    private static let platformUsageURL = URL(string: "https://platform.deepseek.com/usage")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            if let balance = store.balance {
                balanceSection(balance)
            } else {
                emptyState
            }

            spendSection

            if let message = store.errorMessage {
                errorRow(message)
            }

            Divider()

            actions
        }
        .padding(14)
        .frame(width: 320)
        .onChange(of: refreshInterval) { _, newValue in
            store.setRefreshInterval(newValue)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("DeepSeek Usage")
                .font(.headline)
            Spacer()
            HStack(spacing: 6) {
                availabilityBadge
                // Ticks on the minute so the badge flips at a window edge even when no
                // balance refresh is due. Costs nothing while the popover is closed.
                TimelineView(.everyMinute) { context in
                    pricingBadge(at: previewDate ?? context.date)
                }
            }
        }
    }

    @ViewBuilder
    private var availabilityBadge: some View {
        if let isAvailable = store.balance?.isAvailable {
            Badge(
                text: isAvailable ? "Available" : "No balance",
                color: isAvailable ? .green : .orange
            )
        }
    }

    private func pricingBadge(at date: Date) -> some View {
        let period = PricingSchedule.period(at: date)
        return Badge(
            text: period.isPeak ? "Peak" : "Off-Peak",
            color: period.isPeak ? .red : .green
        )
        .help(pricingHelp(period: period, date: date))
    }

    private func pricingHelp(period: PricingPeriod, date: Date) -> String {
        var text = "Off-peak rates are half of peak rates. Peak hours: \(PricingSchedule.scheduleDescription)."

        if let next = PricingSchedule.nextTransition(after: date) {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let relative = formatter.localizedString(for: next, relativeTo: date)
            let nextLabel = PricingSchedule.period(at: next).isPeak ? "peak" : "off-peak"
            text += "\n\n\(period.isPeak ? "Peak" : "Off-peak") now; \(nextLabel) \(relative)."
        }
        return text
    }

    @ViewBuilder
    private func balanceSection(_ balance: BalanceResponse) -> some View {
        if let primary = balance.primary {
            VStack(alignment: .leading, spacing: 6) {
                Text(MoneyFormatter.string(primary.totalBalance, currency: primary.currency))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                    GridRow {
                        Text("Granted").foregroundStyle(.secondary)
                        Text(MoneyFormatter.string(primary.grantedBalance, currency: primary.currency))
                            .monospacedDigit()
                    }
                    GridRow {
                        Text("Topped up").foregroundStyle(.secondary)
                        Text(MoneyFormatter.string(primary.toppedUpBalance, currency: primary.currency))
                            .monospacedDigit()
                    }
                }
                .font(.caption)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.hasAPIKey ? "Waiting for first reading…" : "No API key yet")
                .font(.callout)
            if !store.hasAPIKey {
                Text("Open Settings and paste a DeepSeek API key to show your balance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var spendSection: some View {
        if let spend = store.spend {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Est. spent today").foregroundStyle(.secondary)
                    Spacer()
                    Text(MoneyFormatter.string(spend.spentToday, currency: spend.currency))
                        .monospacedDigit()
                }
                .font(.caption)

                Text("Estimated from balance changes — the API exposes no per-request billing.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.isLoading)

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
            }

            HStack(spacing: 4) {
                if let lastUpdated = store.lastUpdated {
                    Text("Updated")
                    Text(lastUpdated, style: .relative)
                    Text("ago")
                } else if store.isLoading {
                    Text("Updating…")
                } else {
                    Text("Never updated")
                }
                Spacer()
                // A plain Button rather than `Link`: the link button style is AppKit-backed
                // and does not snapshot via ImageRenderer, so `--render-preview` could not
                // show it. Plain also suits this muted caption footer.
                Button("Platform usage") {
                    NSWorkspace.shared.open(MenuContentView.platformUsageURL)
                }
                .buttonStyle(.plain)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
