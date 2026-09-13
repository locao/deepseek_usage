import AppKit
import DeepSeekUsageCore
import SwiftUI

/// Keeps the process out of the Dock and the app switcher even when the binary is run
/// directly (`swift run`) without the bundled `LSUIElement` Info.plist key.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@MainActor
public struct DeepSeekUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: UsageStore

    public init() {
        let store = UsageStore()
        _store = StateObject(wrappedValue: store)
        // The refresh loop only issues GET /user/balance. No inference call is ever made,
        // so an idle menu bar app costs nothing.
        store.startAutoRefresh()
        Task { await store.refresh() }
    }

    public var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
        } label: {
            Text(store.menuBarTitle)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }
}
