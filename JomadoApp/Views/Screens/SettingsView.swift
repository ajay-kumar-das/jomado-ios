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
                            runtime.companionDiagnostics.authorization.title,
                            systemImage: runtime.companionDiagnostics.authorization.systemImage
                        )
                        .foregroundStyle(companionStatusColor)
                    } label: {
                        Text("Notification access")
                    }
                    LabeledContent("Upcoming reminders", value: "\(runtime.companionDiagnostics.scheduledCount) scheduled")
                    Text(runtime.companionDiagnostics.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let date = runtime.companionDiagnostics.lastReconciledAt {
                        LabeledContent("Last checked", value: date.formatted(date: .abbreviated, time: .shortened))
                            .font(.footnote)
                    }
                    if runtime.companionDiagnostics.authorization == .denied {
                        Button("Open iOS Settings") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                        }
                    } else if runtime.companionDiagnostics.authorization != .authorized {
                        Button("Allow companion reminders") {
                            Task { await runtime.requestCompanionAuthorization() }
                        }
                    }
                    Button("Refresh companion reminders") {
                        Task { await runtime.reconcileCompanionNotifications() }
                    }
                } header: {
                    Text("Companion reminders")
                } footer: {
                    Text("iOS delivers scheduled notifications even when Jomado is closed. Jomado uses repeating system schedules for any routine whose full weekday/time pattern fits safely in iOS's notification budget; denser routines use a rolling horizon and are replenished whenever Jomado opens. A requested “Remind me in 10 min” follow-up is preserved during reconciliation. The Live Activity can stay on the Lock Screen once started; remote push-to-start is still required to create a new one while the app process is not running.")
                }

                Section {
                    LabeledContent("Live Activities", value: runtime.companionActivityDiagnostics.activitiesEnabled ? "Allowed" : "Off")
                    LabeledContent(
                        "Terminated-app token",
                        value: runtime.companionActivityDiagnostics.pushToStartTokenAvailable ? "Ready on device" : "Waiting"
                    )
                    LabeledContent("Active companions", value: "\(runtime.companionActivityDiagnostics.activeActivityCount)")
                    if let date = runtime.companionActivityDiagnostics.tokenUpdatedAt {
                        LabeledContent("Token refreshed", value: date.formatted(date: .abbreviated, time: .shortened))
                            .font(.footnote)
                    }
                    Text(runtime.companionActivityDiagnostics.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    LabeledContent("Remote start", value: remoteRegistrationLabel)
                    Text(runtime.companionPushRegistrationDiagnostics.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let date = runtime.companionPushRegistrationDiagnostics.lastSuccessAt {
                        LabeledContent("Last registered", value: date.formatted(date: .abbreviated, time: .shortened))
                            .font(.footnote)
                    }
                    Button("Refresh Lock Screen status") {
                        runtime.refreshCompanionActivityDiagnostics()
                    }
                } header: {
                    Text("Lock Screen companion")
                } footer: {
                    Text("Remote registration is disabled unless an HTTPS production endpoint is configured. When enabled, Jomado sends only a random installation ID and ActivityKit routing token—never hydration history, routine times, completion state, content preferences, or analytics. Local notifications remain independent of the server.")
                }

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
                    LabeledContent("Version", value: "0.3")
                }
            }
            .navigationTitle("Settings")
            .refreshable { await runtime.refreshSystemState() }
        }
    }

    private var remoteRegistrationLabel: String {
        switch runtime.companionPushRegistrationDiagnostics.state {
        case .notConfigured: return "Off"
        case .waitingForToken: return "Waiting"
        case .registered: return "Registered"
        case .failed: return "Needs retry"
        }
    }

    private var companionStatusColor: Color {
        switch runtime.companionDiagnostics.authorization {
        case .authorized: return .green
        case .notDetermined: return .secondary
        case .denied: return .red
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
