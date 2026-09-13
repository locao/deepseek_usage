import Foundation

/// The app's version, read back from the bundle instead of repeated in source.
///
/// `scripts/build-app.sh` writes its `VERSION` variable into `CFBundleShortVersionString`,
/// so that one variable is the only place a release version is defined. A bare `swift run`
/// binary has no bundle `Info.plist` and therefore reports `dev`.
public enum AppInfo {
    public static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }

    public static var userAgent: String {
        "DeepSeekUsage/\(version) (macOS menu bar)"
    }
}
