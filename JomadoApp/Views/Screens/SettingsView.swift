import SwiftUI

struct SettingsView: View {
    @ObservedObject var runtime: JomadoRuntime
    var body: some View {
        NavigationStack {
            Form {
                Section("Privacy") {
                    Label("Behavior data stays on this device", systemImage: "lock.shield.fill")
                    Text("Jomado V1 does not upload reminder history, response times, or content preferences. AI verification is deliberately not included yet.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Alarm access") {
                    LabeledContent("Status", value: String(describing: runtime.alarmScheduler.authorizationState))
                    Button("Request alarm permission") { Task { _ = await runtime.alarmScheduler.requestAuthorization() } }
                }
                Section("Build") { NavigationLink("Developer tools") { DeveloperView(runtime: runtime) }; LabeledContent("Local content", value: "\(runtime.contentCount) items") }
            }.navigationTitle("Settings")
        }
    }
}
