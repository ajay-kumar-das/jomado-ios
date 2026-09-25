import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject var runtime: JomadoRuntime

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent {
                        Label(
                            runtime.alarmDiagnostics.authorization.title,
                            systemImage: runtime.alarmDiagnostics.authorization.systemImage
                        )
                        .foregroundStyle(statusColor)
                    } label: {
                        Text("Alarm access")
                    }
                    LabeledContent(
                        "Generated alarms",
                        value: "\(runtime.alarmDiagnostics.registeredAlarmCount) of \(runtime.alarmDiagnostics.expectedAlarmCount) active"
                    )
                    Text(runtime.alarmDiagnostics.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let date = runtime.alarmDiagnostics.lastReconciledAt {
                        LabeledContent("Last checked", value: date.formatted(date: .abbreviated, time: .shortened))
                            .font(.footnote)
                    }
                } header: {
                    Text("Alarm health")
                } footer: {
                    Text("Jomado uses recurring relative schedules, so alarm times follow the device's local timezone and daylight saving rules.")
                }

                Section {
                    if runtime.alarmDiagnostics.authorization == .denied {
                        Button("Open iOS Settings") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                        }
                    } else if runtime.alarmDiagnostics.authorization != .authorized {
                        Button("Allow alarm access") {
                            Task { await runtime.requestAlarmAuthorization() }
                        }
                    }
                    Button(runtime.isReconcilingAlarms ? "Checking…" : "Check and repair alarms") {
                        Task { await runtime.reconcileAlarms() }
                    }
                    .disabled(runtime.isReconcilingAlarms)
                }

                Section("Privacy") {
                    Label("Reminder history stays on this device", systemImage: "lock.shield.fill")
                    Label("No account, tracking, or analytics upload", systemImage: "icloud.slash.fill")
                    Text("Jomado uses local history only to choose reminder styles and show your insights. It does not send response times, preferences, or hydration activity off-device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("AI verification remains intentionally disabled until the hydration loop is reliable.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Local content") {
                    LabeledContent("Messages", value: "\(runtime.contentCount)")
                    Text(runtime.contentDiagnostic)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Build") {
                    NavigationLink("Developer tools") {
                        DeveloperView(runtime: runtime)
                    }
                    LabeledContent("Version", value: "0.2")
                }
            }
            .navigationTitle("Settings")
            .refreshable { await runtime.refreshSystemState() }
        }
    }

    private var statusColor: Color {
        switch runtime.alarmDiagnostics.authorization {
        case .authorized:
            runtime.alarmDiagnostics.needsAttention ? .orange : .green
        case .notDetermined:
            .secondary
        case .denied:
            .red
        }
    }
}
