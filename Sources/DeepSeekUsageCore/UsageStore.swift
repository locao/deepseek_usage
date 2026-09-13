import Combine
import Foundation

/// Observable state behind the menu bar item.
///
/// Refresh cadence is the only thing that touches the network, and it only ever calls
/// `GET /user/balance` — an account metadata read that consumes no tokens. The app
/// never calls an inference endpoint, so leaving it running costs nothing.
@MainActor
public final class UsageStore: ObservableObject {
    public enum Status: Equatable, Sendable {
        case idle
        case loading
        case loaded(Date)
        case failed(String)
    }

    @Published public private(set) var balance: BalanceResponse?
    @Published public private(set) var status: Status = .idle
    @Published public private(set) var spend: SpendTracker?
    @Published public private(set) var hasAPIKey: Bool = false

    public private(set) var refreshInterval: TimeInterval

    private let client: BalanceClient
    private let stateURL: URL?
    private let defaults: UserDefaults
    private let keyProvider: () throws -> String?
    private var refreshTask: Task<Void, Never>?

    public init(
        client: BalanceClient = BalanceClient(),
        stateURL: URL? = UsageStore.defaultStateURL,
        defaults: UserDefaults = .standard,
        keyProvider: (() throws -> String?)? = nil
    ) {
        self.client = client
        self.stateURL = stateURL
        self.defaults = defaults
        self.keyProvider = keyProvider ?? { try APIKeyStore.resolve() }
        self.spend = UsageStore.loadTracker(from: stateURL)

        let stored = defaults.object(forKey: SettingsKeys.refreshInterval) as? Double
        self.refreshInterval = UsageStore.clamp(stored ?? SettingsKeys.defaultRefreshInterval)
        self.hasAPIKey = UsageStore.resolveKey(using: self.keyProvider) != nil
    }

    // MARK: - Derived display state

    public var menuBarTitle: String {
        guard let primary = balance?.primary else { return hasAPIKey ? "DS …" : "DS —" }
        return MoneyFormatter.string(primary.totalBalance, currency: primary.currency)
    }

    public var lastUpdated: Date? {
        if case .loaded(let date) = status { return date }
        return nil
    }

    public var errorMessage: String? {
        if case .failed(let message) = status { return message }
        return nil
    }

    public var isLoading: Bool {
        status == .loading
    }

    // MARK: - Refreshing

    public func refresh() async {
        guard !isLoading else { return }

        let key: String?
        do {
            key = try keyProvider()
        } catch {
            hasAPIKey = false
            status = .failed(error.localizedDescription)
            return
        }

        guard let apiKey = key, !apiKey.isEmpty else {
            hasAPIKey = false
            status = .failed(BalanceError.missingAPIKey.localizedDescription)
            return
        }

        hasAPIKey = true
        status = .loading

        do {
            let response = try await client.fetchBalance(apiKey: apiKey)
            balance = response
            foldIntoTracker(response)
            status = .loaded(Date())
        } catch {
            // Keep the last successful reading on screen; only the status degrades.
            status = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - Auto refresh

    public func startAutoRefresh() {
        restartAutoRefresh()
    }

    public func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    public func setRefreshInterval(_ seconds: TimeInterval) {
        let clamped = UsageStore.clamp(seconds)
        guard clamped != refreshInterval else { return }
        refreshInterval = clamped
        restartAutoRefresh()
    }

    private func restartAutoRefresh() {
        refreshTask?.cancel()
        let interval = refreshInterval
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    // MARK: - API key

    public func saveAPIKey(_ key: String) throws {
        try APIKeyStore.save(key)
        hasAPIKey = APIKeyStore.hasStoredKey()
        if !hasAPIKey {
            balance = nil
            status = .idle
        }
    }

    public func storedAPIKey() -> String? {
        UsageStore.resolveKey(using: keyProvider)
    }

    // MARK: - Spend estimation

    private func foldIntoTracker(_ response: BalanceResponse) {
        guard let primary = response.primary else { return }
        let now = Date()
        var updated = spend ?? SpendTracker(
            dayKey: SpendTracker.dayKey(for: now),
            currency: primary.currency,
            baseline: primary.totalBalance
        )
        updated.apply(
            total: primary.totalBalance,
            currency: primary.currency,
            dayKey: SpendTracker.dayKey(for: now)
        )
        spend = updated
        persist(updated)
    }

    // MARK: - Preview support

    /// Seeds observable state without touching the network. Used by the offscreen preview
    /// renderer (`--render-preview`).
    public func seedForPreview(balance: BalanceResponse, spend: SpendTracker? = nil) {
        self.balance = balance
        self.spend = spend
        self.hasAPIKey = true
        self.status = .loaded(Date())
    }

    // MARK: - Persistence

    nonisolated public static var defaultStateURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }

        let directory = base.appendingPathComponent("DeepSeekUsage", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("state.json")
    }

    nonisolated static func loadTracker(from url: URL?) -> SpendTracker? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SpendTracker.self, from: data)
    }

    private func persist(_ tracker: SpendTracker) {
        guard let stateURL, let data = try? JSONEncoder().encode(tracker) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    // MARK: - Helpers

    nonisolated static func clamp(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return SettingsKeys.defaultRefreshInterval }
        return max(SettingsKeys.minimumRefreshInterval, seconds)
    }

    nonisolated static func resolveKey(using provider: () throws -> String?) -> String? {
        guard let value = try? provider() else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
