import SwiftUI
import JomadoCore

struct DeveloperView: View {
    @ObservedObject var runtime: JomadoRuntime
    @State private var minutesLate = 0
    @State private var strategy: Strategy? = nil

    var body: some View {
        Form {
            Section("Reminder simulator") {
                Picker("Stage", selection: $minutesLate) { Text("Normal").tag(0); Text("Yellow · 4m").tag(4); Text("Orange · 10m").tag(10); Text("Red · 20m").tag(20) }
                Picker("Strategy", selection: $strategy) { Text("Adaptive").tag(Optional<Strategy>.none); ForEach(Strategy.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) } }
                Button("Trigger reminder now") { runtime.triggerDeveloperReminder(minutesLate: minutesLate, forcedStrategy: strategy) }
            }
            Section("Content") { LabeledContent("Loaded items", value: "\(runtime.contentCount)") }
            Section { Text("Use this screen to validate all urgency states and strategies without waiting for a real AlarmKit schedule.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Developer tools")
    }
}
