import DeepSeekUsageCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @AppStorage(SettingsKeys.refreshInterval) private var refreshInterval: Double = SettingsKeys.defaultRefreshInterval

    @State private var apiKeyDraft: String = ""
    @State private var feedback: String?
    @State private var feedbackIsError = false

    private static let platformUsageURL = URL(string: "https://platform.deepseek.com/usage")!

    var body: some View {
        Form {
            Section {
                SecureField("sk-…", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    Button("Save & Test") { saveAndTest() }
                        .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Clear") { clearKey() }
                    Spacer()
                }

                if let feedback {
                    Text(feedback)
                        .font(.caption)
                        .foregroundStyle(feedbackIsError ? Color.red : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("DeepSeek API key")
            } footer: {
                Text("Stored as a generic password in your login keychain. Only sent to api.deepseek.com as an Authorization header.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Refresh every", selection: $refreshInterval) {
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0)
                    Text("15 minutes").tag(900.0)
                    Text("1 hour").tag(3600.0)
                }
                .onChange(of: refreshInterval) { _, newValue in
                    store.setRefreshInterval(newValue)
                }

                HStack {
                    Button("Refresh now") { Task { await store.refresh() } }
                        .disabled(store.isLoading)
                    Spacer()
                    if let lastUpdated = store.lastUpdated {
                        Text("Updated ")
                            + Text(lastUpdated, style: .relative)
                            + Text(" ago")
                    } else {
                        Text("Not updated yet")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Polling")
            } footer: {
                Text("Each refresh is one GET /user/balance request. That is an account-metadata read: it consumes no tokens and costs nothing, so leaving the app open never uses your API credit. DeepSeek limits account-level concurrency, not request counts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Text("DeepSeek publishes no usage API for API keys — only a balance. The “Est. spent today” figure is therefore derived by diffing successive balance readings, so a top-up can hide spend and per-model detail is not available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("Open platform usage page", destination: SettingsView.platformUsageURL)
                    .font(.caption)
            } header: {
                Text("What this app can and cannot show")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            // `try?` flattens the throwing `String?` return into a single optional.
            if let stored = try? APIKeyStore.read() {
                apiKeyDraft = stored
            }
        }
    }

    private func saveAndTest() {
        do {
            try store.saveAPIKey(apiKeyDraft)
        } catch {
            feedbackIsError = true
            feedback = error.localizedDescription
            return
        }

        feedbackIsError = false
        feedback = "Saved to the keychain — testing…"

        Task {
            await store.refresh()
            if let message = store.errorMessage {
                feedbackIsError = true
                feedback = message
            } else if let primary = store.balance?.primary {
                feedbackIsError = false
                feedback = "Connected. Balance: \(MoneyFormatter.string(primary.totalBalance, currency: primary.currency))"
            } else {
                feedback = "Saved."
            }
        }
    }

    private func clearKey() {
        do {
            try store.saveAPIKey("")
            apiKeyDraft = ""
            feedbackIsError = false
            feedback = "Key removed from the keychain."
        } catch {
            feedbackIsError = true
            feedback = error.localizedDescription
        }
    }
}
