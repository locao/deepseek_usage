import Foundation

public enum SettingsKeys {
    /// Seconds between balance reads. Read/written through `@AppStorage` in the UI.
    public static let refreshInterval = "refreshIntervalSeconds"
    public static let defaultRefreshInterval: TimeInterval = 300
    /// DeepSeek enforces account-level *concurrency*, so any sane interval is fine;
    /// this is the floor that still respects their servers.
    public static let minimumRefreshInterval: TimeInterval = 30
}
